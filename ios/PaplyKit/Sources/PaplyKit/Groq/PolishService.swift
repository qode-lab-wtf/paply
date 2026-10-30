import CryptoKit
import Foundation
import Synchronization

/// Wartet auf das Ergebnis einer Task – höchstens `timeout` lang und nur, solange der
/// Aufrufer nicht abgebrochen wird. Die Task selbst läuft weiter (z. B. eine geteilte
/// Modellabfrage); nil bei Zeitüberschreitung oder Abbruch.
func awaitResult<T: Sendable>(_ task: Task<T, Never>, timeout: Duration? = nil) async -> T? {
    let gate = ResumeGate<T?>()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            gate.attach(continuation)
            Task { gate.resume(await task.value) }
            if let timeout {
                Task {
                    try? await Task.sleep(for: timeout)
                    gate.resume(nil)
                }
            }
        }
    } onCancel: {
        gate.resume(nil)
    }
}

/// Setzt eine Continuation genau einmal fort, egal wer zuerst kommt.
final class ResumeGate<T: Sendable>: Sendable {
    private enum State {
        case waiting
        case attached(CheckedContinuation<T, Never>)
        case resolved(T)
        case done
    }
    private let state = Mutex<State>(.waiting)

    func attach(_ continuation: CheckedContinuation<T, Never>) {
        let early: T? = state.withLock { s in
            if case .resolved(let value) = s {
                s = .done
                return value
            }
            s = .attached(continuation)
            return nil
        }
        if let early { continuation.resume(returning: early) }
    }

    func resume(_ value: T) {
        let continuation: CheckedContinuation<T, Never>? = state.withLock { s in
            switch s {
            case .waiting:
                s = .resolved(value)
                return nil
            case .attached(let continuation):
                s = .done
                return continuation
            case .resolved, .done:
                return nil
            }
        }
        continuation?.resume(returning: value)
    }
}

/// Cache der verfügbaren Groq-Modelle je Schlüssel. Gespeichert wird nur ein Hash des
/// Schlüssels. Nach 5 Minuten (wie Desktop) gilt die Liste als veraltet: Sie wird dann
/// sofort geliefert und im Hintergrund aufgefrischt – das Polieren wartet nie auf eine
/// Auffrischung, nur auf die allererste Liste. Parallele Abfragen teilen sich eine Anfrage.
package actor ModelCatalog {
    package static let shared = ModelCatalog()
    static let lifetime: TimeInterval = 5 * 60

    private struct Entry {
        var ids: [String]
        var checkedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var pending: [String: Task<[String]?, Never>] = [:]
    private let now: @Sendable () -> Date

    package init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    static func fingerprint(_ apiKey: String) -> String {
        SHA256.hash(data: Data(apiKey.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Verfügbare Modelle; nil, wenn noch keine Liste da ist und sie gerade nicht abrufbar
    /// ist – oder der Aufrufer abgebrochen wurde (dann sofort).
    package func models(_ client: GroqClient, forceRefresh: Bool = false) async -> [String]? {
        let key = Self.fingerprint(client.apiKey)
        if !forceRefresh, let entry = entries[key] {
            if now().timeIntervalSince(entry.checkedAt) >= Self.lifetime { _ = fetch(key, client) }
            return entry.ids
        }
        return await awaitResult(fetch(key, client)) ?? nil
    }

    /// Alter der Liste in Sekunden; nil, wenn keine da ist.
    func age(apiKey: String) -> TimeInterval? {
        entries[Self.fingerprint(apiKey)].map { now().timeIntervalSince($0.checkedAt) }
    }

    private func fetch(_ key: String, _ client: GroqClient) -> Task<[String]?, Never> {
        if let task = pending[key] { return task }
        let task = Task { () -> [String]? in
            var ids: [String]?
            if case .success(let list) = await client.listModels() { ids = list }
            self.pending[key] = nil
            if let ids { self.entries[key] = Entry(ids: ids, checkedAt: self.now()) }
            return ids
        }
        pending[key] = task
        return task
    }

    func remove(_ model: String, apiKey: String) {
        let key = Self.fingerprint(apiKey)
        entries[key]?.ids.removeAll { $0 == model }
    }

    func reset() {
        entries.removeAll()
        pending.removeAll()
    }
}

struct PolishResult: Sendable, Equatable {
    var polished: String?
    /// Sicherheitsnetz-Grund bzw. "truncated" (`PolishRejectionCode`).
    var rejection: String?
    /// Technischer Grund (`PolishFailureCode`).
    var error: PolishFailureCode?
    var model: String?
}

/// Polieren mit Modellwahl, genau einem Wiederholversuch und Sicherheitsnetz.
/// Kein Zeitlimit: Es gilt nur das Leerlauf-Timeout der Verbindung.
struct PolishService: Sendable {
    let client: GroqClient
    let catalog: ModelCatalog
    var strictEdits = true

    func polish(text: String, messages: [ChatMessage], vocabulary: String, settings: PaplySettings) async -> PolishResult {
        var preferred: [String] = []
        for model in [settings.polishModel, settings.fallbackPolishModel] where !model.isEmpty && !preferred.contains(model) {
            preferred.append(model)
        }
        guard !preferred.isEmpty else { return PolishResult(error: .modelUnavailable) }

        let available = await catalog.models(client)
        if Task.isCancelled { return PolishResult(error: .cancelled) }
        // Ist die Modellliste nicht abrufbar, direkt das bevorzugte Modell versuchen
        // (Desktop bliebe hier roh); fehlt es wirklich, greift unten das Ausweichmodell.
        let selected = available.map { GroqModels.select(available: $0, preferred: preferred) } ?? preferred.first
        guard var model = selected else { return PolishResult(error: .modelUnavailable) }

        let maxTokens = GroqModels.polishTokenBudget(text)
        var outcome = await client.chat(model: model, messages: messages, maxTokens: maxTokens)
        if case .failure(let failure) = outcome {
            let fallback = preferred.first { $0 != model && (available?.contains($0) ?? true) }
            if failure.isModelMissing {
                await catalog.remove(model, apiKey: client.apiKey)
                guard let fallback else { return PolishResult(error: .modelUnavailable, model: model) }
                model = fallback
                outcome = await client.chat(model: model, messages: messages, maxTokens: maxTokens)
            } else if case .http(429, _, _) = failure, client.retryDelay(for: failure) == nil, let fallback {
                // Langes Limit (z. B. Tages-Tokens im Free-Tier, Retry-After in Minuten):
                // Das Ausweichmodell hat ein eigenes Kontingent – einmal dort versuchen.
                model = fallback
                outcome = await client.chat(model: model, messages: messages, maxTokens: maxTokens)
            } else if failure.isRetryable, let delay = client.retryDelay(for: failure) {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return PolishResult(error: .cancelled, model: model) }
                outcome = await client.chat(model: model, messages: messages, maxTokens: maxTokens)
            }
        }

        switch outcome {
        case .failure(let failure):
            return PolishResult(error: failure.polishCode, model: model)
        case .success(let completion):
            // Nur ein regulär beendeter Text („stop“) ist vollständig; „length“, Inhaltsfilter
            // usw. könnten den Schluss des Diktats abschneiden → Rohtext.
            if let reason = completion.finishReason, reason != "stop" {
                return PolishResult(rejection: PolishRejectionCode.truncated.rawValue, model: model)
            }
            let result = PolishSafetyNet.finalPolishText(completion.content?.trimmed)
            if let reason = PolishSafetyNet.rejection(raw: text, result: result, vocabulary: vocabulary, strictEdits: strictEdits) {
                return PolishResult(rejection: reason, model: model)
            }
            return PolishResult(polished: result, model: model)
        }
    }
}
