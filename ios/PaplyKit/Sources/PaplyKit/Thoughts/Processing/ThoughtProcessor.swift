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
/// - Diagnose (`ThoughtTrace`): Beginn und Ende von Umschrift und Ordnung mit Dauer, Wartegründe – nur Zahlen und Codes.
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
    private let trace: ThoughtTrace

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
                ledger: TokenLedger, environment: ProcessorEnvironment, trace: ThoughtTrace = .off) {
        self.init(store: store, structurer: structurer, finder: finder, ledger: ledger, environment: environment,
                  transcriber: FileTranscriber(), trace: trace)
    }

    public init(store: ThoughtStore, structurer: ThoughtStructuring, finder: CandidateFinding, ledger: TokenLedger,
                environment: ProcessorEnvironment, transcriber: ThoughtTranscribing, options: Options = Options(),
                now: @escaping @Sendable () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
                trace: ThoughtTrace = .off) {
        self.trace = trace
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
        guard let thought = await store.thought(id), thought.deletedAt == nil, thought.kind != ConversationKind.thoughtKind, thought.state != .recording else { return }
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
            .filter { $0.deletedAt == nil && $0.kind != ConversationKind.thoughtKind && Self.isWaiting($0.state) }
            .compactMap(\.status.retryAt)
            .filter { $0 > clock }
            .min()
    }

    /// Gibt es Gedanken, die ohne Zutun des Nutzers noch geordnet werden können (nicht: Schlüssel fehlt)?
    public func hasPendingWork() async -> Bool {
        await store.all().contains { thought in
            thought.deletedAt == nil && thought.kind != ConversationKind.thoughtKind && thought.state != .waitingKey && (Self.isInFlight(thought.state) || Self.isWaiting(thought.state))
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
        let thoughts = await store.all().filter { $0.kind != ConversationKind.thoughtKind }
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
        guard let thought = await store.thought(id), thought.deletedAt == nil, thought.kind != ConversationKind.thoughtKind, thought.state != .recording else { return }
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
            let liveResult = FileTranscriber.result(from: live, model: settings.transcriptionModel)
            traceTranscription(id, liveResult, started: nil)
            switch liveResult {
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
        guard await waitForDictation(id) else { return nil }
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
        trace.log("thought.transcribe.begin", ["id": .s(ThoughtTrace.short(id)), "model": .s(settings.transcriptionModel),
                                               "audioS": .ms(Double(thought.durationMs) / 1000)])
        let started = ContinuousClock.now
        let result = await transcriber.transcribe(audioURL: audioURL, apiKey: key, settings: settings)
        traceTranscription(id, result, started: started)
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
            trace.log("thought.structure.cached", ["id": .s(ThoughtTrace.short(id))])
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
        guard await waitForDictation(id) else { return }
        _ = try? await store.update(id) { $0.state = .structuring }
        eventBroadcast.yield(.processing(id))
        let settings = await environment.settings()
        // Themen wie beim Aufruf: verschwindet das gewählte Thema bis zum Übernehmen, wird es damit neu angelegt
        let topicsAtCall = await store.topics()
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
        trace.log("thought.structure.begin", ["id": .s(ThoughtTrace.short(id)), "textLen": .i(source.text.count),
                                              "parts": .i(parts.count), "topics": .i(context.entries.count),
                                              "candidates": .i(candidates.count)])
        let started = ContinuousClock.now
        var result: StructureOutcome?
        if parts.count == 1 {
            result = await structureIfWanted(id, base, key: key)
            if result == .unusable(code: "too_large") {
                result = await structureParts(id, source: source, parts: PartSplitter.split(source, force: true), base: base, key: key)
            }
        } else {
            result = await structureParts(id, source: source, parts: parts, base: base, key: key)
        }
        traceStructure(id, result, started: started)
        guard let outcome = result else {
            // gelöscht/verworfen während des Ordnens: zurück auf „verschriftlicht“, Wiederherstellen ordnet neu
            _ = try? await store.update(id) { if $0.deletedAt != nil { $0.state = .transcribed } }
            return
        }
        switch outcome {
        case let .success(result, model, usage):
            let record = AIResultRecord(result: result, model: model, usage: usage, at: now(),
                                        chosenTopic: Self.label(of: result.topic, topics: topicsAtCall, index: context.entries))
            try? await store.saveAIResult(id, record) // vor dem Übernehmen sichern (Mac-Plan-Cache)
            await apply(id, source: source, record: record)
        case let .wait(state, retryAt, message):
            if state == .waitingKey { rejectedKey = key }
            await structureWait(id, state: state, retryAt: retryAt, message: message)
        case .unusable(let code):
            await applyRaw(id, source: source, code: code)
        }
    }

    /// Name und Symbol eines gewählten vorhandenen Themas beim Aufruf (Index-Eintrag ohne Symbol: ✨).
    static func label(of decision: TopicDecision, topics: [Topic], index: [TopicIndexEntry]) -> TopicLabel? {
        guard case .existing(let id) = decision else { return nil }
        if let topic = ThoughtStore.resolve(id, in: topics) { return TopicLabel(name: topic.title, icon: topic.icon) }
        return index.first { $0.topicID == id }.map { TopicLabel(name: $0.name, icon: .sparkles) }
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
        let structurer = structurer
        return await ThoughtTrace.$thoughtID.withValue(ThoughtTrace.short(id)) {
            await structurer.structure(input, apiKey: key)
        }
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
                if gap > 0 {
                    trace.log("thought.wait", ["id": .s(ThoughtTrace.short(id)), "state": .s("partGap"), "waitS": .ms(gap)])
                    await sleeper(gap)
                }
            }
            if Task.isCancelled { return .wait(.waitingNetwork, retryAt: nil, message: "Abgebrochen") }
            guard await waitForDictation(id) else { return .wait(.waitingNetwork, retryAt: nil, message: "Abgebrochen") }
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
        for task in first.result.tasks + progress.rest.flatMap({ $0.tasks.map(\.draft) })
        where seen.insert(RawText.taskKey(task.text, dueHint: task.dueHint)).inserted {
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
        var aiTopic: Topic?
        if current.topicOwner != .user {
            aiTopic = await resolveTopic(result.topic, chosen: record.chosenTopic)
        }
        var links: [ThoughtLink] = []
        for related in result.related where related.thoughtID != id {
            guard let target = await store.thought(related.thoughtID), target.deletedAt == nil else { continue }
            links.append(ThoughtLink(target: target.id, kind: related.kind, reason: related.reason, origin: .ai, createdAt: clock))
        }
        let keywords = await keywords(for: (result.title) + "\n" + (result.cleanText ?? source.text), language: source.languages.first)
        let createdAt = current.createdAt
        let drafts = result.tasks.map { draft in
            let due = DueDate.resolved(draft.dueHint, reference: createdAt, now: clock)
            return ThoughtTask(text: draft.text, quote: draft.quote, dueHint: draft.dueHint, dueAt: due?.date,
                               dueHasTime: due?.hasTime, owner: .ai, createdAt: clock)
        }
        let raw = RawText.tidy(source.text)
        let ai = Thought.AIInfo(model: record.model ?? "", promptVersion: options.promptVersion,
                                tokens: record.usage?.total ?? 0, at: clock, rejections: result.rejections)
        let aiLinks = links
        // Zuweisung und Thema in einem Schritt: Wurde das Thema inzwischen mit seinem letzten Gedanken entfernt,
        // legt der Speicher es wieder an, statt eine ID ins Leere zu setzen. Hat inzwischen ein anderer Lauf oder der
        // Nutzer ein gleichnamiges Thema angelegt, nimmt der Speicher dieses (Namensprüfung im selben Schritt).
        let updated = try? await store.update(id, topic: aiTopic) { t, chosenTopic in
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
            // Die Entwürfe sind schon ohne Doppelte (Text und Zeitausdruck); gegen Erledigte und Eigene zählt `sameTask`
            t.tasks = kept + drafts.filter { draft in !kept.contains { RawText.sameTask($0, draft) } }
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

    /// Themenwahl der KI auflösen → das Thema, das der Gedanke bekommt (nil = ohne Thema). Neue Themen gibt es nur,
    /// wenn die Doppel-Schranke sie durchlässt; angelegt werden sie erst beim Übernehmen, im selben Schritt wie die
    /// Zuweisung (`ThoughtStore.update(_:topic:_:)`).
    ///
    /// Rechte eines Laufs (KONZEPT §6.10): Die KI wählt ein vorhandenes Thema, keins oder legt **ein** neues an.
    /// Vorhandene Themen (Name, Symbol, Beschreibung, Besitzer, Reihenfolge) ändert sie nie – angelegt wird nur
    /// angehängt.
    private func resolveTopic(_ decision: TopicDecision, chosen: TopicLabel?) async -> Topic? {
        let topics = await store.topics()
        switch decision {
        case .none:
            return nil
        case .existing(let id):
            if let topic = ThoughtStore.resolve(id, in: topics) { return topic }
            // Inzwischen mit seinem letzten Gedanken entfernt: wie ein neues Thema mit Name und Symbol von damals –
            // es trägt jetzt wieder einen Gedanken. Kein Namens- und Mengenlimit: Das Thema gab es ja schon.
            guard let chosen else { return nil }
            return await newTopic(chosen.name, icon: chosen.icon, topics: topics, restoring: true)
        case let .new(name, icon):
            return await newTopic(name, icon: icon, topics: topics, restoring: false)
        }
    }

    /// Doppel-Schranke gegen alle lebenden Themen (nicht nur den gesendeten Index); sonst ein neues KI-Thema (noch nicht
    /// gespeichert). Mehrdeutig (mehrere gleich gute Titel): ohne Thema. Der Speicher prüft den Namen beim Übernehmen
    /// noch einmal im selben Schritt (`ThoughtStore.update(_:topic:_:)`).
    private func newTopic(_ name: String, icon: TopicIcon, topics: [Topic], restoring: Bool) async -> Topic? {
        let same = TopicHygiene.sameNamed(name, among: topics)
        if same.count == 1 { return same[0] }
        guard same.isEmpty else { return nil }
        if restoring {
            guard !name.trimmed.isEmpty else { return nil }
        } else {
            let summaries = TopicIndex.summaries(topics: topics, thoughts: await store.all())
            guard TopicHygiene.isValidNewName(name), summaries.filter(\.isActive).count < TopicIndex.maxActive else { return nil }
        }
        return Topic(title: name.trimmed, icon: icon, owner: .ai, createdAt: now())
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
        var fields: ThoughtTrace.Fields = ["id": .s(ThoughtTrace.short(id)), "state": .s(state.rawValue)]
        if let retryAt { fields["waitS"] = .ms(max(0, retryAt.timeIntervalSince(now()))) }
        if let attempts { fields["attempts"] = .i(attempts) }
        trace.log("thought.wait", fields)
    }

    private func attention(_ id: String, message: String, attempts: Int? = nil) async {
        let updated = try? await store.update(id) { t in
            t.state = .needsAttention
            t.status.message = message
            t.status.retryAt = nil
            if let attempts { t.status.attempts = attempts }
        }
        if updated != nil { eventBroadcast.yield(.failed(id, message: message)) }
        var fields: ThoughtTrace.Fields = ["id": .s(ThoughtTrace.short(id)), "why": .s(Self.attentionCode(message))]
        if let attempts { fields["attempts"] = .i(attempts) }
        trace.log("thought.attention", fields)
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
        trace.log("thought.empty", ["id": .s(ThoughtTrace.short(id))])
    }

    /// false, wenn abgebrochen. Wartegrund „Diktat“ geht mit der Wartezeit ins Protokoll.
    private func waitForDictation(_ id: String) async -> Bool {
        var started: ContinuousClock.Instant?
        while await environment.isDictationBusy() {
            if started == nil { started = .now }
            if Task.isCancelled { break }
            await sleeper(options.dictationPoll)
        }
        if let started {
            trace.log("thought.wait.dictation", ["id": .s(ThoughtTrace.short(id)), "ms": ThoughtTrace.milliseconds(since: started)])
        }
        return !Task.isCancelled
    }

    // MARK: Diagnose (nur Zahlen und Codes, nie Text)

    private func traceTranscription(_ id: String, _ result: TranscriptionResult, started: ContinuousClock.Instant?) {
        var fields: ThoughtTrace.Fields = ["id": .s(ThoughtTrace.short(id)), "live": .b(started == nil)]
        if let started { fields["ms"] = ThoughtTrace.milliseconds(since: started) }
        switch result {
        case let .success(text, languages, audioSeconds, model):
            fields["result"] = .s("ok")
            fields["textLen"] = .i(text.count)
            fields["langs"] = .s(languages.joined(separator: ","))
            fields["audioS"] = .ms(audioSeconds)
            fields["model"] = .s(model)
        case .noSpeech:
            fields["result"] = .s("noSpeech")
        case .failure(let failure):
            fields["result"] = .s(failure.rawValue)
        }
        trace.log("thought.transcribe.end", fields)
    }

    private func traceStructure(_ id: String, _ outcome: StructureOutcome?, started: ContinuousClock.Instant) {
        var fields: ThoughtTrace.Fields = ["id": .s(ThoughtTrace.short(id)), "ms": ThoughtTrace.milliseconds(since: started)]
        switch outcome {
        case nil:
            fields["result"] = .s("cancelled")
        case let .success(result, model, usage):
            fields["result"] = .s("ok")
            fields["model"] = .s(model)
            fields["fallback"] = .b(model != ThoughtStructurer.primaryModel)
            fields["tokens"] = .i(usage.total)
            fields["tasks"] = .i(result.tasks.count)
            switch result.topic {
            case .existing: fields["topic"] = .s("existing")
            case .new: fields["topic"] = .s("new")
            case .none: fields["topic"] = .s("none")
            }
            fields["links"] = .i(result.related.count)
            fields["textIsRaw"] = .b(result.cleanText == nil)
            fields["rejections"] = .i(result.rejections.count)
        case let .wait(state, _, _):
            fields["result"] = .s("wait")
            fields["code"] = .s(state.rawValue)
        case .unusable(let code):
            fields["result"] = .s("raw")
            fields["code"] = .s(code)
        }
        trace.log("thought.structure.end", fields)
    }

    /// Fester Code statt der (deutschen) Meldung
    static func attentionCode(_ text: String) -> String {
        switch text {
        case "Ton fehlt · nicht verschriftlicht": "audioMissing"
        case "Modell nicht verfügbar": "modelMissing"
        case "Budget zu klein": "budgetTooSmall"
        case message(.needsAttention): "failed"
        default: "other"
        }
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

    /// Schlüssel für doppelte Aufgaben: Text und Zeitausdruck. „Mama anrufen“ morgen und übermorgen sind zwei Aufgaben.
    static func taskKey(_ text: String, dueHint: String?) -> String {
        key(text) + "\u{1F}" + key(dueHint ?? "")
    }

    /// „Erneut ordnen“: Ist der Entwurf eine erledigte oder eigene Aufgabe? Gleicher Text und gleicher Zeitausdruck –
    /// fehlt er auf einer Seite, zählt nur der Text (die erledigte „Tomaten gießen · morgen“ kommt nicht als „Tomaten
    /// gießen“ zurück). Zwei verschiedene Tage bleiben zwei Aufgaben.
    static func sameTask(_ kept: ThoughtTask, _ draft: ThoughtTask) -> Bool {
        guard key(kept.text) == key(draft.text) else { return false }
        let a = key(kept.dueHint ?? ""), b = key(draft.dueHint ?? "")
        return a.isEmpty || b.isEmpty || a == b
    }
}

/// Fälligkeit (§6.7): `NSDataDetector` liefert den Tag, bezogen auf die Aufnahmezeit, und die Uhrzeit für Ziffern und
/// Englisch. Deutsche Wortformen und eine genannte Tageszeit liest `SpokenTime` („um acht“, „halb drei“, „morgen um
/// 7 Uhr früh“). Ohne erkannte Uhrzeit bleibt die Vorgabe des Detektors (12:00, „morgen früh“ 9:00) – nur zum
/// Sortieren; angezeigt wird eine Uhrzeit nur mit `hasTime`.
enum DueDate {
    struct Resolved: Equatable, Sendable {
        var date: Date
        /// Im Wortlaut steht eine Uhrzeit (`clock`), und `date` liegt genau auf ihr
        var hasTime: Bool
    }

    private static let leading = ["bis zum", "bis", "am", "ab", "spätestens", "by", "until", "on", "before"]

    static func resolve(_ hint: String?, reference: Date, now: Date, calendar: Calendar = .current) -> Date? {
        resolved(hint, reference: reference, now: now, calendar: calendar)?.date
    }

    /// Erster Treffer des Detektors im Zeitausdruck (ohne führendes „bis“, „am“ …)
    private static func detect(_ hint: String?) -> (text: String, date: Date)? {
        guard var text = hint?.trimmed, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let lower = text.lowercased()
        for word in leading where lower.hasPrefix(word + " ") {
            text = String(text.dropFirst(word.count + 1))
            break
        }
        text = germanAm(text)
        guard let date = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.date else { return nil }
        return (text, date)
    }

    /// Deutsches „am“ nach einer Ziffer ist nie „a.m.“: Der Detektor liest „um 8 am Freitag“ sonst als heute 8:00.
    /// Nach „um <Ziffer>“ wird „Uhr“ eingefügt („um 8 Uhr am Freitag“ → Freitag 8:00, gemessen).
    static func germanAm(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)\b(um\s+\d{1,2}(?:[:.]\d{2})?)\s+am\b"#, with: "$1 Uhr am", options: .regularExpression)
    }

    /// Die Uhrzeit eines Zeitausdrucks – eine Regel für `hasTime` beim Auflösen und für die Anzeige älterer Aufgaben:
    /// - Wortform oder Tageszeit (`SpokenTime` legt fest): diese Uhrzeit
    /// - Ziffern oder Englisch: die Uhrzeit des Detektors, wenn sie auf demselben Zifferblatt liegt wie die genannte
    ///   („morgen um 07:00“ → 7:00, „8 pm“ → 20:00); sonst hat er sie nicht gelesen („morgen gegen 8“ → 12:00) → keine
    /// - nichts Eindeutiges erkannt → keine
    static func clock(_ spoken: SpokenTime.Found?, detected: Date) -> SpokenTime.Clock? {
        guard let spoken else { return nil }
        if spoken.fixed { return spoken.clock }
        // Der Detektor rechnet in der Zeitzone des Geräts
        let parts = Calendar.current.dateComponents([.hour, .minute], from: detected)
        guard let hour = parts.hour, let minute = parts.minute,
              hour % 12 == spoken.clock.hour % 12, minute == spoken.clock.minute else { return nil }
        return SpokenTime.Clock(hour: hour, minute: minute)
    }

    /// Uhrzeit eines Zeitausdrucks nach `clock` (für Aufgaben ohne `dueHasTime`)
    static func spokenClock(_ hint: String?) -> SpokenTime.Clock? {
        guard let detected = detect(hint) else { return nil }
        return clock(SpokenTime.find(in: detected.text), detected: detected.date)
    }

    static func resolved(_ hint: String?, reference: Date, now: Date, calendar: Calendar = .current) -> Resolved? {
        guard let (text, detected) = detect(hint) else { return nil }
        let spoken = SpokenTime.find(in: text)
        let clock = clock(spoken, detected: detected)
        // Ein Datum mit Ziffern („am 10. November“) gilt, wie es dasteht. Relative Angaben („morgen“, auch „morgen um
        // 15 Uhr“) gelten ab der Aufnahme, nicht ab dem Verarbeiten: so viele Kalendertage nach dem Aufnahmetag.
        let absolute = spoken.map(\.otherDigits) ?? text.contains(where: \.isNumber)
        var date = detected
        if !absolute {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: detected)).day ?? 0
            let time = calendar.dateComponents([.hour, .minute, .second], from: detected)
            guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: reference)),
                  let shifted = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
            else { return nil }
            date = shifted
        }
        // Ziffern/Englisch: Die Uhrzeit des Detektors steht schon in `date`; nur eine festgelegte wird gesetzt
        if let clock, spoken?.fixed == true {
            if clock.hour == 24 {
                // Mitternacht = 0:00 des Folgetags
                guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else { return nil }
                date = next
            } else {
                guard let set = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: date) else { return nil }
                date = set
            }
        }
        guard date > reference.addingTimeInterval(-86_400), date < reference.addingTimeInterval(2 * 365 * 86_400) else { return nil }
        return Resolved(date: date, hasTime: clock != nil)
    }
}
