import Foundation

/// Warteschlange: Verschriftlichen → Ordnen (KONZEPT §6.1, §5.3, §6.8). Port von Mac `queue.js`.
///
/// Zustände: `captured` → `transcribing` → `transcribed` → `structuring` → `done`; Warten:
/// `waitingNetwork`/`Key`/`Limit`/`Budget`; Ende ohne Ordnung: `needsAttention`, `empty` (wird entfernt).
///
/// - Seriell: immer nur ein Gedanke, zuerst frische, dann wartende (älteste zuerst).
/// - Neustart-fest: Der Zustand steht in `thought.json`; `transcribing`/`structuring` werden einfach
///   fortgesetzt. Whisper wird je Gedanke genau einmal erfolgreich gerufen: Liegt `source.json`, nie wieder –
///   und der Ton wird gelöscht (der Speicher behält nur den Rohtext).
///   Ein validiertes KI-Ergebnis liegt vor dem Übernehmen als `ai-result.json` (kein Neukauf nach Absturz).
/// - Diktat hat Vorrang: kein Groq-Aufruf, solange `isDictationBusy` true ist.
/// - Nutzerfelder (`owner == .user`) überschreibt die KI nie; gelöschte Gedanken werden nicht übernommen.
public actor ThoughtProcessor {
    public struct Options: Sendable {
        /// Fehlversuche (Server/unlesbar) bis `needsAttention`
        public var maxAttempts = 5
        public var backoffBase: TimeInterval = 30
        public var backoffMax: TimeInterval = 600
        public var limitMinimumWait: TimeInterval = 15 * 60
        public var budgetMinimumWait: TimeInterval = 60
        /// Teile-Modus: Abstand der Aufrufe (Minutenlimit)
        public var partGap: TimeInterval = 60
        /// Abfrage-Takt, solange ein Diktat läuft
        public var dictationPoll: TimeInterval = 1.5
        /// Netzfehler: erst nach so langer Zeit ohne Erfolg aufgeben (Mac: 24 h)
        public var attentionAfter: TimeInterval = 24 * 3600
        /// so lange auf das Ergebnis der Live-Pipeline warten, bevor der Dateiweg gilt
        public var liveWait: TimeInterval = 15 * 60
        /// wird mit jedem Ergebnis gespeichert (`ai.promptVersion`)
        public var promptVersion = ThoughtPrompt.version
        /// Wiederholungen per Timer, solange die App lebt (Tests: aus)
        public var autoRetry = true

        public init() {}
    }

    private let store: ThoughtStore
    private let structurer: ThoughtStructuring
    private let finder: CandidateFinding
    private let ledger: TokenLedger
    private let environment: ProcessorEnvironment
    private let transcriber: ThoughtTranscribing
    public nonisolated let options: Options
    private let now: @Sendable () -> Date
    private let sleeper: @Sendable (TimeInterval) async -> Void

    private var running: Task<Void, Never>?
    private var restarting: Task<Void, Never>?
    private var rerun = false
    private var timer: Task<Void, Never>?
    private var liveOutcomes: [String: DictationOutcome] = [:]
    private var expectedLive: [String: Date] = [:]
    /// Rohtexte, deren Schreiben scheiterte: nie ein zweites Mal verschriftlichen
    private var pendingSources: [String: ThoughtSource] = [:]
    /// abgelehnter Schlüssel: keine weiteren Aufrufe, bis er sich ändert (Mac `authKey`)
    private var rejectedKey: String?
    private let eventBroadcast = Broadcast<ProcessorEvent>()

    public init(store: ThoughtStore, structurer: ThoughtStructuring, finder: CandidateFinding,
                ledger: TokenLedger, environment: ProcessorEnvironment) {
        self.init(store: store, structurer: structurer, finder: finder, ledger: ledger, environment: environment,
                  transcriber: FileTranscriber())
    }

    public init(store: ThoughtStore, structurer: ThoughtStructuring, finder: CandidateFinding, ledger: TokenLedger,
                environment: ProcessorEnvironment, transcriber: ThoughtTranscribing, options: Options = Options(),
                now: @escaping @Sendable () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.store = store
        self.structurer = structurer
        self.finder = finder
        self.ledger = ledger
        self.environment = environment
        self.transcriber = transcriber
        self.options = options
        self.now = now
        self.sleeper = sleep
    }

    /// Jeder Zugriff liefert einen eigenen Strom (Live Activity, Oberfläche).
    public nonisolated var events: AsyncStream<ProcessorEvent> { eventBroadcast.stream }

    // MARK: Auslöser

    /// Eine Live-Pipeline läuft für diesen Gedanken: der Dateiweg wartet auf ihr Ergebnis (max. `liveWait`).
    public func expectLiveTranscript(_ id: String) {
        expectedLive[id] = now()
    }

    /// Die Live-Pipeline wurde abgebrochen (Gedanke verworfen): Erwartung und ein etwa schon gemeldetes
    /// Live-Ergebnis entfallen. Wird der Gedanke wiederhergestellt, ordnet die Warteschlange sofort über den
    /// Dateiweg, statt bis zu `liveWait` zu warten.
    public func cancelLiveTranscript(_ id: String) {
        expectedLive[id] = nil
        liveOutcomes[id] = nil
    }

    /// Ergebnis der Live-Pipeline
    public func liveTranscript(_ id: String, outcome: DictationOutcome) {
        liveOutcomes[id] = outcome
        expectedLive[id] = nil
        kick(reason: "live")
    }

    public func kick(reason: String) {
        if running != nil {
            rerun = true
            return
        }
        running = Task { await self.drain() }
    }

    /// „Erneut ordnen“ bzw. „Erneut versuchen“: bewusst neue Anfrage, alter KI-Cache verworfen.
    public func reorganize(_ id: String) {
        let previous = restarting
        restarting = Task {
            await previous?.value
            await self.restart(id)
        }
    }

    private func restart(_ id: String) async {
        guard let thought = await store.thought(id), thought.deletedAt == nil, thought.state != .recording else { return }
        await store.discardAIResult(id)
        let transcribed = await store.hasSource(id) || pendingSources[id] != nil
        _ = try? await store.update(id) { t in
            t.state = transcribed ? .transcribed : .captured
            t.status = Thought.Status()
        }
        kick(reason: "reorganize")
    }

    /// Wartet, bis die Warteschlange nichts mehr tun kann (BGTask, Tests).
    public func waitUntilIdle() async {
        while let task = restarting ?? running {
            await task.value
            if restarting == task { restarting = nil }
        }
    }

    /// BGTask läuft ab: laufende Arbeit abbrechen (der Zustand bleibt fortsetzbar).
    public func cancelRunning() {
        running?.cancel()
    }

    /// Frühester geplanter Wiederholungszeitpunkt (für den BGTask).
    public func nextRetryDate() async -> Date? {
        let clock = now()
        return await store.all()
            .filter { $0.deletedAt == nil && Self.isWaiting($0.state) }
            .compactMap(\.status.retryAt)
            .filter { $0 > clock }
            .min()
    }

    /// Gibt es Gedanken, die ohne Zutun des Nutzers noch geordnet werden können (nicht: Schlüssel fehlt)?
    public func hasPendingWork() async -> Bool {
        await store.all().contains { thought in
            thought.deletedAt == nil && thought.state != .waitingKey && (Self.isInFlight(thought.state) || Self.isWaiting(thought.state))
        }
    }

    // MARK: Takt

    private func drain() async {
        repeat {
            rerun = false
            var visited: Set<String> = []
            while !Task.isCancelled, let id = await nextItem(excluding: visited) {
                visited.insert(id)
                await process(id)
            }
        } while rerun && !Task.isCancelled
        running = nil
        await scheduleRetry()
    }

    private func scheduleRetry() async {
        timer?.cancel()
        timer = nil
        guard options.autoRetry, let next = await nextRetryDate() else { return }
        let delay = max(1, next.timeIntervalSince(now()))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.kick(reason: "retry")
        }
    }

    static func isInFlight(_ state: ThoughtState) -> Bool {
        [.captured, .transcribing, .transcribed, .structuring].contains(state)
    }

    static func isWaiting(_ state: ThoughtState) -> Bool {
        [.waitingNetwork, .waitingKey, .waitingLimit, .waitingBudget].contains(state)
    }

    private func nextItem(excluding visited: Set<String>) async -> String? {
        let thoughts = await store.all()
        let clock = now()
        // Netz und Schlüssel nur abfragen, wenn ein wartender Gedanke sie braucht
        let needsNetwork = thoughts.contains { $0.deletedAt == nil && $0.state == .waitingNetwork }
        let needsKey = thoughts.contains { $0.deletedAt == nil && $0.state == .waitingKey }
        let online = needsNetwork ? await environment.isOnline() : false
        let key = needsKey ? await environment.apiKey()?.trimmed : nil
        var best: (priority: Int, created: Date, id: String)?
        for thought in thoughts where thought.deletedAt == nil && !visited.contains(thought.id) {
            let priority: Int
            let due = (thought.status.retryAt ?? .distantPast) <= clock
            switch thought.state {
            case .captured:
                if let since = expectedLive[thought.id], liveOutcomes[thought.id] == nil,
                   clock.timeIntervalSince(since) < options.liveWait { continue }
                priority = 0
            case .transcribing, .transcribed, .structuring:
                priority = 0
            case .waitingNetwork:
                guard due, online else { continue }
                priority = 1
            case .waitingKey:
                guard let key, !key.isEmpty, key != rejectedKey else { continue }
                priority = 1
            case .waitingLimit, .waitingBudget:
                guard due else { continue }
                priority = 1
            case .recording, .done, .needsAttention, .empty:
                continue
            }
            let candidate = (priority, thought.createdAt, thought.id)
            if best == nil || candidate < best! { best = candidate }
        }
        return best?.id
    }

    // MARK: Ein Gedanke

    private func process(_ id: String) async {
        guard let thought = await store.thought(id), thought.deletedAt == nil, thought.state != .recording else { return }
        var source = await store.source(id)
        if source == nil, let pending = pendingSources[id] {
            if (try? await store.saveSourceOnce(id, pending)) != nil { pendingSources[id] = nil }
            source = pending
        }
        if source != nil {
            liveOutcomes[id] = nil
            expectedLive[id] = nil
        } else {
            source = await transcribe(thought)
        }
        guard let source else { return }
        if source.text.trimmed.isEmpty {
            await markEmpty(id)
            return
        }
        await store.releaseAudio(id) // Ton nur bis zum Rohtext (auch nach einem Absturz dazwischen)
        await structure(id, source: source)
    }

    // MARK: Verschriftlichen

    private func transcribe(_ thought: Thought) async -> ThoughtSource? {
        let id = thought.id
        let settings = await environment.settings()
        if let live = liveOutcomes.removeValue(forKey: id) {
            expectedLive[id] = nil
            switch FileTranscriber.result(from: live, model: settings.transcriptionModel) {
            case .noSpeech:
                await markEmpty(id)
                return nil
            case let .success(text, languages, seconds, model):
                await recordLiveAudio(seconds: seconds, model: model)
                return await persistSource(id, text: text, languages: languages, seconds: seconds, model: model)
            case .failure:
                break // Dateiweg
            }
        }
        expectedLive[id] = nil
        guard let key = await environment.apiKey()?.trimmed, !key.isEmpty else {
            await wait(id, .waitingKey, message: Self.message(.waitingKey))
            return nil
        }
        guard key != rejectedKey else {
            await wait(id, .waitingKey, message: Self.keyRejectedMessage)
            return nil
        }
        guard await environment.isOnline() else {
            await wait(id, .waitingNetwork, message: Self.message(.waitingNetwork))
            return nil
        }
        guard let audioURL = await store.audioURL(id) else {
            await attention(id, message: "Ton fehlt · nicht verschriftlicht")
            return nil
        }
        guard await waitForDictation() else { return nil }
        let seconds = max(1, Int((Double(thought.durationMs) / 1000).rounded(.up)))
        let reservation: TokenLedger.Reservation
        do {
            reservation = try await ledger.reserve(model: settings.transcriptionModel, amount: seconds, unit: .audio)
        } catch {
            await refused(id, error)
            return nil
        }
        // Direkt vor dem Upload, atomar im Speicher: gelöscht oder verworfen → nichts geht an Groq.
        guard let current = try? await store.update(id, { if $0.deletedAt == nil { $0.state = .transcribing } }),
              current.deletedAt == nil else {
            await ledger.settle(reservation, actual: 0)
            return nil
        }
        eventBroadcast.yield(.processing(id))
        let result = await transcriber.transcribe(audioURL: audioURL, apiKey: key, settings: settings)
        switch result {
        case let .success(text, languages, audioSeconds, model):
            await ledger.settle(reservation, actual: Int(audioSeconds.rounded(.up)))
            return await persistSource(id, text: text, languages: languages, seconds: audioSeconds, model: model)
        case .noSpeech:
            await ledger.settle(reservation, actual: 0)
            await markEmpty(id)
            return nil
        case .failure(let failure):
            await ledger.settle(reservation, actual: 0)
            await transcriptionFailed(id, failure, key: key)
            return nil
        }
    }

    /// Die Live-Pipeline hat Whisper schon gerufen: Audiominuten nachträglich verbuchen.
    private func recordLiveAudio(seconds: Double, model: String) async {
        let amount = max(1, Int(seconds.rounded(.up)))
        if let reservation = try? await ledger.reserve(model: model, amount: amount, unit: .audio) {
            await ledger.settle(reservation, actual: amount)
        }
    }

    private func persistSource(_ id: String, text: String, languages: [String], seconds: Double, model: String) async -> ThoughtSource? {
        let spoken = languages.isEmpty ? [detectLanguage(text)].compactMap { $0 } : languages
        let source = ThoughtSource(text: text, sentences: PartSplitter.sentences(text, thoughtID: id), model: model,
                                   createdAt: now(), languages: spoken, audioSeconds: seconds)
        do {
            try await store.saveSourceOnce(id, source)
        } catch ThoughtStoreError.sourceExists {
            return await store.source(id)
        } catch ThoughtStoreError.notFound {
            return nil // inzwischen endgültig gelöscht: nichts aufheben, nichts neu anlegen
        } catch {
            pendingSources[id] = source // nächster Durchlauf schreibt erneut, ohne Whisper
        }
        _ = try? await store.update(id) { t in
            t.state = .transcribed
            t.languages = spoken
            t.status = Thought.Status()
        }
        return source
    }

    private func transcriptionFailed(_ id: String, _ failure: TranscriptionFailure, key: String) async {
        switch failure {
        case .unauthorized:
            rejectedKey = key
            await wait(id, .waitingKey, message: Self.keyRejectedMessage)
        case .rateLimited:
            let retryAt = now().addingTimeInterval(options.limitMinimumWait)
            await wait(id, .waitingLimit, retryAt: retryAt, message: Self.limitMessage(retryAt))
        case .network:
            await failedAttempt(id, network: true)
        case .server, .invalidResponse:
            await failedAttempt(id, network: false)
        case .modelMissing:
            await attention(id, message: "Modell nicht verfügbar")
        case .rejected, .unreadableAudio:
            await attention(id, message: Self.message(.needsAttention))
        case .cancelled:
            _ = try? await store.update(id) { $0.state = .captured }
        }
    }

    /// Netz-/Serverfehler: Backoff 30 s · 2ⁿ ≤ 10 Min. Server: nach 5 Versuchen `needsAttention`;
    /// Netz: erst nach 5 Versuchen und 24 h ohne Erfolg.
    private func failedAttempt(_ id: String, network: Bool, transcribed: Bool = false) async {
        guard let thought = await store.thought(id) else { return }
        let attempts = thought.status.attempts + 1
        let age = now().timeIntervalSince(thought.createdAt)
        let giveUp = attempts >= options.maxAttempts && (!network || age >= options.attentionAfter)
        if giveUp {
            if transcribed, let source = await store.source(id) {
                await applyRaw(id, source: source, code: network ? "network" : "server")
            } else {
                await attention(id, message: Self.message(.needsAttention), attempts: attempts)
            }
            return
        }
        let delay = min(options.backoffMax, options.backoffBase * pow(2, Double(attempts - 1)))
        let message = network ? Self.message(.waitingNetwork) : "Gesichert · Groq gestört, neuer Versuch gleich"
        await wait(id, .waitingNetwork, retryAt: now().addingTimeInterval(delay), message: message, attempts: attempts)
    }

    // MARK: Ordnen

    private func structure(_ id: String, source: ThoughtSource) async {
        if let cached = await store.aiResultRecord(id) {
            await apply(id, source: source, record: cached)
            return
        }
        guard let key = await environment.apiKey()?.trimmed, !key.isEmpty else {
            await wait(id, .waitingKey, message: Self.message(.waitingKey))
            return
        }
        guard key != rejectedKey else {
            await wait(id, .waitingKey, message: Self.keyRejectedMessage)
            return
        }
        guard await environment.isOnline() else {
            await wait(id, .waitingNetwork, message: Self.message(.waitingNetwork))
            return
        }
        guard await waitForDictation() else { return }
        _ = try? await store.update(id) { $0.state = .structuring }
        eventBroadcast.yield(.processing(id))
        let settings = await environment.settings()
        let context = await finder.topicIndex(forText: source.text, languages: source.languages)
        // Zeitbezug = Aufnahmezeit, auch wenn erst später (offline) geordnet wird: `now` im Prompt und
        // die `when`-Angaben der Kandidaten („heute 09:40“) passen so zu „vorhin“ im Gesprochenen.
        let recordedAt = await store.thought(id)?.createdAt ?? now()
        let candidates = await finder.candidates(forText: source.text, languages: source.languages, excluding: id,
                                                 relativeTo: recordedAt)
        let base = StructureInput(transcript: source.text, sentences: source.sentences, spokenLanguages: source.languages,
                                  uiLanguage: environment.uiLanguage, vocabulary: settings.vocabulary,
                                  topics: context.entries, topicsFull: context.full, candidates: candidates,
                                  recordedAt: recordedAt)
        let parts = PartSplitter.split(source)
        var result: StructureOutcome?
        if parts.count == 1 {
            result = await structureIfWanted(id, base, key: key)
            if result == .unusable(code: "too_large") {
                result = await structureParts(id, source: source, parts: PartSplitter.split(source, force: true), base: base, key: key)
            }
        } else {
            result = await structureParts(id, source: source, parts: parts, base: base, key: key)
        }
        guard let outcome = result else {
            // gelöscht/verworfen während des Ordnens: zurück auf „verschriftlicht“, Wiederherstellen ordnet neu
            _ = try? await store.update(id) { if $0.deletedAt != nil { $0.state = .transcribed } }
            return
        }
        switch outcome {
        case let .success(result, model, usage):
            let record = AIResultRecord(result: result, model: model, usage: usage, at: now())
            try? await store.saveAIResult(id, record) // vor dem Übernehmen sichern (Mac-Plan-Cache)
            await apply(id, source: source, record: record)
        case let .wait(state, retryAt, message):
            if state == .waitingKey { rejectedKey = key }
            await structureWait(id, state: state, retryAt: retryAt, message: message)
        case .unusable(let code):
            await applyRaw(id, source: source, code: code)
        }
    }

    private func structureWait(_ id: String, state: ThoughtState, retryAt: Date?, message: String) async {
        switch state {
        case .waitingKey:
            await wait(id, .waitingKey, message: Self.keyRejectedMessage)
        case .waitingLimit:
            let at = max(retryAt ?? .distantPast, now().addingTimeInterval(60))
            await wait(id, .waitingLimit, retryAt: at, message: Self.limitMessage(retryAt == nil ? nil : at))
        case .waitingBudget:
            let at = max(retryAt ?? .distantPast, now().addingTimeInterval(options.budgetMinimumWait))
            await wait(id, .waitingBudget, retryAt: at, message: Self.message(.waitingBudget))
        case .needsAttention:
            await attention(id, message: message.isEmpty ? Self.message(.needsAttention) : message)
        default:
            if Task.isCancelled {
                _ = try? await store.update(id) { $0.state = .transcribed }
                return
            }
            await failedAttempt(id, network: true, transcribed: true)
        }
    }

    /// Ordnen nur, solange der Gedanke nicht gelöscht ist – direkt vor jedem Aufruf geprüft. nil = abgebrochen.
    private func structureIfWanted(_ id: String, _ input: StructureInput, key: String) async -> StructureOutcome? {
        guard let thought = await store.thought(id), thought.deletedAt == nil else { return nil }
        return await structurer.structure(input, apiKey: key)
    }

    /// Teile-Modus (§6.2): Teil 1 voll, Teile 2…n kurz, ≥ 60 s Abstand; Fortschritt in `ai-parts.json`.
    /// nil = gelöscht/verworfen, bevor alle Teile geordnet waren (Fortschritt bleibt gespeichert).
    private func structureParts(_ id: String, source: ThoughtSource, parts: [PartSplitter.Part],
                                base: StructureInput, key: String) async -> StructureOutcome? {
        guard parts.count > 1 else { return await structureIfWanted(id, base, key: key) }
        let hash = String(StableHash.of(source.text), radix: 16)
        var progress = await store.parts(id) ?? StructureParts(transcriptHash: hash, count: parts.count)
        if progress.transcriptHash != hash || progress.count != parts.count {
            progress = StructureParts(transcriptHash: hash, count: parts.count)
        }
        if progress.first == nil {
            var input = base
            input.transcript = parts[0].text
            input.sentences = parts[0].sentences
            guard let outcome = await structureIfWanted(id, input, key: key) else { return nil }
            guard case let .success(result, model, usage) = outcome else { return outcome }
            progress.first = AIResultFile(AIResultRecord(result: result, model: model, usage: usage, at: now()))
            progress.lastCallAt = now()
            try? await store.saveParts(id, progress)
        }
        while progress.rest.count < parts.count - 1 {
            let index = progress.rest.count + 1
            if let last = progress.lastCallAt {
                let gap = options.partGap - now().timeIntervalSince(last)
                if gap > 0 { await sleeper(gap) }
            }
            if Task.isCancelled { return .wait(.waitingNetwork, retryAt: nil, message: "Abgebrochen") }
            guard await waitForDictation() else { return .wait(.waitingNetwork, retryAt: nil, message: "Abgebrochen") }
            var input = base
            input.transcript = parts[index].text
            input.sentences = parts[index].sentences
            input.topics = []
            input.topicsFull = false
            input.candidates = []
            input.part = (index: index + 1, count: parts.count)
            guard let outcome = await structureIfWanted(id, input, key: key) else { return nil }
            switch outcome {
            case let .success(result, _, usage):
                progress.rest.append(StructureParts.Part(cleanText: result.cleanText, tasks: result.tasks.map(StructureParts.StoredTask.init),
                                                         rejections: result.rejections, tokens: usage.total))
            case .unusable(let code):
                progress.rest.append(StructureParts.Part(cleanText: nil, tasks: [], rejections: [code], tokens: 0))
            case .wait:
                return outcome
            }
            progress.lastCallAt = now()
            try? await store.saveParts(id, progress)
        }
        guard let first = progress.first?.record else { return .unusable(code: "parts") }
        var texts = [first.result.cleanText ?? RawText.tidy(parts[0].text)]
        for (offset, part) in progress.rest.enumerated() { texts.append(part.cleanText ?? RawText.tidy(parts[offset + 1].text)) }
        let allRaw = first.result.cleanText == nil && progress.rest.allSatisfy { $0.cleanText == nil }
        var tasks: [TaskDraft] = []
        var seen: Set<String> = []
        for task in first.result.tasks + progress.rest.flatMap({ $0.tasks.map(\.draft) }) where seen.insert(RawText.key(task.text)).inserted {
            tasks.append(task)
        }
        var rejections = first.result.rejections
        for code in progress.rest.flatMap(\.rejections) where !rejections.contains(code) { rejections.append(code) }
        let combined = StructureResult(title: first.result.title, cleanText: allRaw ? nil : texts.joined(separator: "\n\n"),
                                       topic: first.result.topic, tasks: tasks, related: first.result.related, rejections: rejections)
        let firstUsage = first.usage ?? TokenUsage(prompt: 0, completion: 0, total: 0)
        let restTokens = progress.rest.reduce(0) { $0 + $1.tokens }
        let usage = TokenUsage(prompt: firstUsage.prompt, completion: firstUsage.completion, total: firstUsage.total + restTokens)
        return .success(combined, model: first.model ?? ThoughtStructurer.primaryModel, usage: usage)
    }

    // MARK: Übernehmen

    /// Nur KI-eigene Felder; Nutzerfelder, erledigte und eigene Aufgaben bleiben. Gelöscht → nichts.
    private func apply(_ id: String, source: ThoughtSource, record: AIResultRecord) async {
        guard let current = await store.thought(id), current.deletedAt == nil else { return }
        let result = record.result
        let clock = now()
        var topicID: String?
        if current.topicOwner != .user { topicID = await resolveTopic(result.topic) }
        var links: [ThoughtLink] = []
        for related in result.related where related.thoughtID != id {
            guard let target = await store.thought(related.thoughtID), target.deletedAt == nil else { continue }
            links.append(ThoughtLink(target: target.id, kind: related.kind, reason: related.reason, origin: .ai, createdAt: clock))
        }
        let keywords = await keywords(for: (result.title) + "\n" + (result.cleanText ?? source.text), language: source.languages.first)
        let createdAt = current.createdAt
        let drafts = result.tasks.map { draft in
            ThoughtTask(text: draft.text, quote: draft.quote, dueHint: draft.dueHint,
                        dueAt: DueDate.resolve(draft.dueHint, reference: createdAt, now: clock), owner: .ai, createdAt: clock)
        }
        let raw = RawText.tidy(source.text)
        let ai = Thought.AIInfo(model: record.model ?? "", promptVersion: options.promptVersion,
                                tokens: record.usage?.total ?? 0, at: clock, rejections: result.rejections)
        let chosenTopic = topicID
        let aiLinks = links
        let updated = try? await store.update(id) { t in
            guard t.deletedAt == nil else { return }
            if t.titleOwner != .user {
                t.title = result.title.trimmed.isEmpty ? RawText.fallbackTitle(result.cleanText ?? raw) : result.title
                t.titleOwner = .ai
            }
            if t.textOwner != .user {
                t.text = result.cleanText ?? raw
                t.textIsRaw = result.cleanText == nil
                t.textOwner = .ai
            }
            if t.topicOwner != .user {
                t.topicId = chosenTopic
                t.topicOwner = .ai
            }
            let kept = t.tasks.filter { $0.owner == .user || $0.done }
            var keys = Set(kept.map { RawText.key($0.text) })
            t.tasks = kept + drafts.filter { keys.insert(RawText.key($0.text)).inserted }
            let userLinks = t.links.filter { $0.origin == .user }
            let linked = Set(userLinks.map(\.target))
            t.links = userLinks + aiLinks.filter { !linked.contains($0.target) }
            t.languages = source.languages
            t.keywords = keywords
            t.ai = ai
            t.state = .done
            t.status = Thought.Status()
        }
        guard let updated, updated.state == .done else { return }
        await store.discardParts(id)
        await finder.didChange(updated)
        let topic = await store.resolveTopic(updated.topicId)
        eventBroadcast.yield(.saved(id, topicTitle: topic?.title, topicIcon: topic?.icon))
    }

    /// Ordnen gescheitert: `done` mit Rohtext, ohne KI-Thema, -Aufgaben und -Verbindungen („Erneut ordnen“).
    private func applyRaw(_ id: String, source: ThoughtSource, code: String) async {
        guard let current = await store.thought(id), current.deletedAt == nil else { return }
        let clock = now()
        let raw = RawText.tidy(source.text)
        let keywords = await keywords(for: raw, language: source.languages.first)
        let ai = Thought.AIInfo(model: "", promptVersion: options.promptVersion, tokens: 0, at: clock, rejections: [code])
        let updated = try? await store.update(id) { t in
            guard t.deletedAt == nil else { return }
            if t.textOwner != .user {
                t.text = raw
                t.textIsRaw = true
                t.textOwner = .ai
            }
            if t.titleOwner != .user {
                t.title = RawText.fallbackTitle(t.text ?? raw)
                t.titleOwner = .ai
            }
            if t.topicOwner != .user { t.topicId = nil }
            t.tasks = t.tasks.filter { $0.owner == .user || $0.done }
            t.links = t.links.filter { $0.origin == .user }
            t.languages = source.languages
            t.keywords = keywords
            t.ai = ai
            t.state = .done
            t.status = Thought.Status()
        }
        guard let updated, updated.state == .done else { return }
        await store.discardParts(id)
        await finder.didChange(updated)
        let topic = await store.resolveTopic(updated.topicId)
        eventBroadcast.yield(.saved(id, topicTitle: topic?.title, topicIcon: topic?.icon))
    }

    /// Themenwahl der KI auflösen; neue Themen legt nur das an, was die Doppel-Schranke durchlässt.
    ///
    /// Rechte eines Laufs (KONZEPT §6.10): Die KI wählt ein vorhandenes Thema, keins oder legt **ein** neues an.
    /// Vorhandene Themen (Name, Symbol, Beschreibung, Besitzer, Reihenfolge) ändert sie nie – angelegt wird nur
    /// angehängt (`updateTopics` mit reinem Anhängen).
    private func resolveTopic(_ decision: TopicDecision) async -> String? {
        let topics = await store.topics()
        switch decision {
        case .none:
            return nil
        case .existing(let id):
            return ThoughtStore.resolve(id, in: topics)?.id
        case let .new(name, icon):
            let thoughts = await store.all()
            let summaries = TopicIndex.summaries(topics: topics, thoughts: thoughts)
            let entries = summaries.map {
                TopicIndexEntry(topicID: $0.topic.id, name: $0.topic.title, count: $0.count, hint: [], about: $0.topic.describedNote)
            }
            if let match = TopicHygiene.matchExisting(name, among: entries) { return match.topicID }
            if let match = TopicMentions.describedMatch(name, among: entries) { return match.topicID }
            guard TopicHygiene.isValidNewName(name), summaries.filter(\.isActive).count < TopicIndex.maxActive else { return nil }
            let topic = Topic(title: name.trimmed, icon: icon, owner: .ai, createdAt: now())
            guard (try? await store.updateTopics({ $0.append(topic) })) != nil else { return nil }
            return topic.id
        }
    }

    private func keywords(for text: String, language: String?) async -> [String] {
        if let finder = finder as? CandidateFinder { return await finder.keywords(forText: text, language: language) }
        return Keywords.top(Keywords.counts(Keywords.terms(text, language: language)), limit: 5)
    }

    // MARK: Zustände setzen

    private func wait(_ id: String, _ state: ThoughtState, retryAt: Date? = nil, message: String, attempts: Int? = nil) async {
        let updated = try? await store.update(id) { t in
            t.state = state
            t.status.message = message
            t.status.retryAt = retryAt
            if let attempts { t.status.attempts = attempts }
        }
        if updated != nil { eventBroadcast.yield(.waiting(id, state, message: message)) }
    }

    private func attention(_ id: String, message: String, attempts: Int? = nil) async {
        let updated = try? await store.update(id) { t in
            t.state = .needsAttention
            t.status.message = message
            t.status.retryAt = nil
            if let attempts { t.status.attempts = attempts }
        }
        if updated != nil { eventBroadcast.yield(.failed(id, message: message)) }
    }

    private func refused(_ id: String, _ refusal: TokenLedger.Refusal) async {
        switch refusal {
        case .budgetTooSmall:
            await attention(id, message: "Budget zu klein")
        case .budget(let retryAt), .minute(let retryAt):
            let at = max(retryAt, now().addingTimeInterval(options.budgetMinimumWait))
            await wait(id, .waitingBudget, retryAt: at, message: Self.message(.waitingBudget))
        }
    }

    /// Nichts gesagt: kein Eintrag, Ton gelöscht (§5.2).
    private func markEmpty(_ id: String) async {
        await store.purge(id)
        pendingSources[id] = nil
        eventBroadcast.yield(.empty(id))
    }

    /// false, wenn abgebrochen
    private func waitForDictation() async -> Bool {
        while await environment.isDictationBusy() {
            if Task.isCancelled { return false }
            await sleeper(options.dictationPoll)
        }
        return !Task.isCancelled
    }

    // MARK: Texte (§3.7)

    static let keyRejectedMessage = "Gesichert · Groq-Schlüssel ungültig"

    static func message(_ state: ThoughtState) -> String {
        switch state {
        case .waitingNetwork: "Gesichert · wartet auf Netz"
        case .waitingKey: "Gesichert · Groq-Schlüssel fehlt"
        case .waitingLimit: "Gesichert · Groq-Limit, später"
        case .waitingBudget: "Gesichert · Kontingent für heute erreicht"
        case .needsAttention: "Ton gesichert · nicht verschriftlicht"
        default: ""
        }
    }

    static func limitMessage(_ retryAt: Date?) -> String {
        guard let retryAt else { return message(.waitingLimit) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return "Gesichert · Groq-Limit, ab ca. " + formatter.string(from: retryAt)
    }
}

// MARK: - Hilfen

/// Rohtext als Rückfall (§6.7): Leerraum zusammengefasst, Satzanfänge groß; Ersatztitel.
enum RawText {
    static func tidy(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ").trimmed
        var out = ""
        var capitalizeNext = true
        for character in collapsed {
            if capitalizeNext, character.isLetter {
                out += character.uppercased()
                capitalizeNext = false
            } else {
                out.append(character)
                if character.isLetter || character.isNumber { capitalizeNext = false }
            }
            if ".!?…".contains(character) || character == "\n" { capitalizeNext = true }
        }
        return out
    }

    /// erste 6 Wörter des Textes + „…“
    static func fallbackTitle(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let head = words.prefix(6).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?…–- "))
        if head.isEmpty { return "Gedanke" }
        return words.count > 6 ? head + " …" : head
    }

    /// Vergleichsschlüssel für Doppelte (klein, ohne Akzente/Satzzeichen)
    static func key(_ text: String) -> String {
        TextAnalysis.alphanumericRuns(Keywords.fold(text)).joined(separator: " ")
    }
}

/// Fälligkeit nur als Sortierdatum (§6.7): `NSDataDetector` auf den Wortlaut, bezogen auf die Aufnahmezeit.
enum DueDate {
    private static let leading = ["bis zum", "bis", "am", "ab", "spätestens", "by", "until", "on", "before"]

    static func resolve(_ hint: String?, reference: Date, now: Date) -> Date? {
        guard var text = hint?.trimmed, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let lower = text.lowercased()
        for word in leading where lower.hasPrefix(word + " ") {
            text = String(text.dropFirst(word.count + 1))
            break
        }
        guard let date = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date else { return nil }
        // Relative Angaben („morgen“) gelten ab der Aufnahme, nicht ab dem Verarbeiten
        let absolute = text.contains(where: \.isNumber)
        let resolved = absolute ? date : date.addingTimeInterval(reference.timeIntervalSince(now))
        guard resolved > reference.addingTimeInterval(-86_400), resolved < reference.addingTimeInterval(2 * 365 * 86_400) else { return nil }
        return resolved
    }
}
