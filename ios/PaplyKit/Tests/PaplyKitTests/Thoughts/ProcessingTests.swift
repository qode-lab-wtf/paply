import Foundation
import Synchronization
import Testing
@testable import PaplyKit

// MARK: - Ersatzteile (kein Groq)

actor MockStructurer: ThoughtStructuring {
    private var queue: [StructureOutcome]
    private let fallback: StructureOutcome
    private(set) var inputs: [StructureInput] = []
    private var onCall: (@Sendable (StructureInput) async -> Void)?

    init(_ outcomes: [StructureOutcome] = [], fallback: StructureOutcome = ProcessingTests.success()) {
        queue = outcomes
        self.fallback = fallback
    }

    func setOnCall(_ block: @escaping @Sendable (StructureInput) async -> Void) { onCall = block }
    func push(_ outcome: StructureOutcome) { queue.append(outcome) }
    var calls: Int { inputs.count }

    func structure(_ input: StructureInput, apiKey: String) async -> StructureOutcome {
        inputs.append(input)
        if let onCall { await onCall(input) }
        return queue.isEmpty ? fallback : queue.removeFirst()
    }
}

actor MockTranscriber: ThoughtTranscribing {
    private var queue: [TranscriptionResult]
    private(set) var calls = 0

    init(_ results: [TranscriptionResult] = []) { queue = results }

    func push(_ result: TranscriptionResult) { queue.append(result) }

    func transcribe(audioURL: URL, apiKey: String, settings: PaplySettings) async -> TranscriptionResult {
        calls += 1
        return queue.isEmpty ? .success(text: "ähm also die Tomaten im Garten muss ich morgen gießen", languages: ["de"], audioSeconds: 2, model: "whisper-large-v3")
            : queue.removeFirst()
    }
}

final class Flags: Sendable {
    private let state = Mutex<(online: Bool, key: String?, busy: Bool, busyChecks: Int)>((true, "gsk_test", false, 0))
    var online: Bool { get { state.withLock { $0.online } } set { state.withLock { $0.online = newValue } } }
    var key: String? { get { state.withLock { $0.key } } set { state.withLock { $0.key = newValue } } }
    var busy: Bool { get { state.withLock { $0.busy } } set { state.withLock { $0.busy = newValue } } }
    var busyChecks: Int { state.withLock { $0.busyChecks } }
    func checkBusy() -> Bool { state.withLock { $0.busyChecks += 1; return $0.busy } }
}

/// Sendable-Kiste für Werte, die Tests aus Closures heraus setzen.
final class Box<Value: Sendable>: Sendable {
    private let state: Mutex<Value>
    init(_ value: Value) { state = Mutex(value) }
    var value: Value { get { state.withLock { $0 } } set { state.withLock { $0 = newValue } } }
    func update(_ change: (inout Value) -> Void) { state.withLock { change(&$0) } }
}

struct Harness {
    let root: URL
    let store: ThoughtStore
    let structurer: MockStructurer
    let transcriber: MockTranscriber
    let flags: Flags
    let clock: TestClock
    let processor: ThoughtProcessor
    let sleeps: Box<[TimeInterval]>

    static func make(structurer: MockStructurer = MockStructurer(), transcriber: MockTranscriber = MockTranscriber(),
                     configure: (inout ThoughtProcessor.Options) -> Void = { _ in },
                     onSleep: (@Sendable () -> Void)? = nil, name: String = #function) throws -> Harness {
        let root = StoreSupport.temporaryRoot(name)
        let clock = TestClock()
        let store = try ThoughtStore(root: root, now: clock.function)
        let flags = Flags()
        var options = ThoughtProcessor.Options()
        options.autoRetry = false
        configure(&options)
        let environment = ProcessorEnvironment(apiKey: { flags.key }, isOnline: { flags.online },
                                               isDictationBusy: { flags.checkBusy() }, settings: { PaplySettings() }, uiLanguage: "de")
        var finderOptions = CandidateFinder.Options()
        finderOptions.models = []
        let ledger = TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: { TokenLedger.Limits() }, now: clock.function)
        let sleeps = Box<[TimeInterval]>([])
        let processor = ThoughtProcessor(store: store, structurer: structurer, finder: CandidateFinder(store: store, options: finderOptions, now: clock.function),
                                         ledger: ledger, environment: environment, transcriber: transcriber, options: options,
                                         now: clock.function, sleep: { [sleeps] seconds in
                                             sleeps.update { $0.append(seconds) }
                                             onSleep?()
                                         })
        return Harness(root: root, store: store, structurer: structurer, transcriber: transcriber, flags: flags, clock: clock,
                       processor: processor, sleeps: sleeps)
    }

    /// Aufnahme wie H3: Platzhalter + WAV, dann `captured`.
    func capture(seconds: Double = 1) async throws -> String {
        let (thought, writer) = try await store.beginCapture(trigger: .control, at: clock.now)
        writer.append(StoreSupport.tone(seconds: seconds))
        try await store.finishCapture(thought.id, durationMs: writer.close())
        return thought.id
    }

    func run(_ reason: String = "test") async {
        await processor.kick(reason: reason)
        await processor.waitUntilIdle()
    }

    func thought(_ id: String) async -> Thought? { await store.thought(id) }

    func cleanup() { StoreSupport.remove(root) }
}

// MARK: - Tests

@Suite("Gedanken-Warteschlange")
struct ProcessingTests {
    static func success(title: String = "Tomaten gießen", clean: String? = "Die Tomaten im Garten muss ich morgen gießen.",
                        topic: TopicDecision = .new(name: "Garten", icon: .leaf),
                        tasks: [TaskDraft] = [TaskDraft(text: "Tomaten gießen", quote: "die tomaten im garten muss ich morgen gießen", dueHint: "morgen")],
                        related: [RelatedDraft] = [], tokens: Int = 3_000) -> StructureOutcome {
        .success(StructureResult(title: title, cleanText: clean, topic: topic, tasks: tasks, related: related),
                 model: "openai/gpt-oss-120b", usage: TokenUsage(prompt: tokens - 500, completion: 500, total: tokens))
    }

    @Test func capturedThoughtIsTranscribedStructuredAndCompacted() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let events = h.processor.events
        let id = try await h.capture(seconds: 2)
        await h.run()
        let thought = try #require(await h.thought(id))
        #expect(thought.state == .done)
        #expect(thought.title == "Tomaten gießen" && thought.titleOwner == .ai)
        #expect(thought.text == "Die Tomaten im Garten muss ich morgen gießen." && !thought.textIsRaw)
        #expect(thought.tasks.map(\.text) == ["Tomaten gießen"])
        #expect(thought.tasks.first?.dueHint == "morgen")
        #expect(thought.ai?.tokens == 3_000 && thought.ai?.model == "openai/gpt-oss-120b")
        #expect(!thought.keywords.isEmpty)
        #expect(thought.audio?.file == "audio.m4a")
        #expect(thought.audio?.deleteAfter == h.clock.now.addingTimeInterval(AudioCompactor.audioRetention))
        let topic = try #require(await h.store.resolveTopic(thought.topicId))
        #expect(topic.title == "Garten" && topic.owner == .ai)
        let source = try #require(await h.store.source(id))
        #expect(source.text == "ähm also die Tomaten im Garten muss ich morgen gießen")
        #expect(source.sentences.first?.id == "\(id)_s0")
        #expect(await h.store.aiResult(id) != nil) // Cache vor dem Übernehmen
        #expect(await h.transcriber.calls == 1)
        #expect(await h.structurer.calls == 1)
        let input = try #require(await h.structurer.inputs.first)
        #expect(input.part == nil && input.uiLanguage == "de" && input.reasoningEffort == "low")
        var iterator = events.makeAsyncIterator()
        var seen: [ProcessorEvent] = []
        while let event = await iterator.next() {
            seen.append(event)
            if case .saved = event { break }
        }
        #expect(seen.contains(.processing(id)))
        #expect(seen.last == .saved(id, topicTitle: "Garten", topicIcon: .leaf))
    }

    @Test func offlineWaitsAndResumesWhenNetworkReturns() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.flags.online = false
        let id = try await h.capture()
        await h.run()
        var thought = try #require(await h.thought(id))
        #expect(thought.state == .waitingNetwork)
        #expect(thought.status.message == "Gesichert · wartet auf Netz")
        #expect(await h.transcriber.calls == 0)
        await h.run() // weiter offline: nichts passiert
        #expect(await h.transcriber.calls == 0)
        h.flags.online = true
        await h.run("network")
        thought = try #require(await h.thought(id))
        #expect(thought.state == .done)
        #expect(await h.transcriber.calls == 1)
    }

    @Test func missingKeyWaitsUntilKeyIsEntered() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.flags.key = nil
        let id = try await h.capture()
        await h.run()
        #expect(await h.thought(id)?.state == .waitingKey)
        #expect(await h.thought(id)?.status.message == "Gesichert · Groq-Schlüssel fehlt")
        h.flags.key = "gsk_neu"
        await h.run("key")
        #expect(await h.thought(id)?.state == .done)
    }

    @Test func rejectedKeyIsNotRetriedUntilItChanges() async throws {
        let structurer = MockStructurer([.wait(.waitingKey, retryAt: nil, message: "401")])
        let h = try Harness.make(structurer: structurer)
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.run()
        #expect(await h.thought(id)?.state == .waitingKey)
        await h.run()
        #expect(await structurer.calls == 1) // gleicher Schlüssel: kein neuer Aufruf
        h.flags.key = "gsk_anderer"
        await h.run()
        #expect(await structurer.calls == 2)
        #expect(await h.thought(id)?.state == .done)
    }

    @Test func limitWaitsUntilRetryTime() async throws {
        let h = try Harness.make(structurer: MockStructurer([.wait(.waitingLimit, retryAt: nil, message: "429")]))
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.run()
        let waiting = try #require(await h.thought(id))
        #expect(waiting.state == .waitingLimit)
        let retryAt = try #require(waiting.status.retryAt)
        #expect(retryAt >= h.clock.now.addingTimeInterval(60))
        #expect(await h.processor.nextRetryDate() == retryAt)
        await h.run()
        #expect(await h.structurer.calls == 1) // vor retryAt kein Aufruf
        h.clock.set(retryAt.addingTimeInterval(1))
        await h.run("retry")
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.structurer.calls == 2)
        #expect(await h.transcriber.calls == 1)
    }

    @Test func budgetWaitUsesLedgerTime() async throws {
        let later = Date(timeIntervalSince1970: 1_793_200_000)
        let h = try Harness.make(structurer: MockStructurer([.wait(.waitingBudget, retryAt: later, message: "Budget")]))
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.run()
        #expect(await h.thought(id)?.state == .waitingBudget)
        #expect(await h.thought(id)?.status.retryAt == later)
        #expect(await h.thought(id)?.status.message == "Gesichert · Kontingent für heute erreicht")
    }

    @Test func restartInStructuringUsesCachedResultWithoutNewCalls() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let id = try await h.capture()
        try await h.store.saveSourceOnce(id, ThoughtSource(text: "die tomaten gießen", sentences: [], model: "whisper-large-v3",
                                                           createdAt: h.clock.now, languages: ["de"], audioSeconds: 1))
        let cached = StructureResult(title: "Aus dem Cache", cleanText: "Die Tomaten gießen.", topic: .none, tasks: [], related: [])
        try await h.store.saveAIResult(id, AIResultRecord(result: cached, model: "openai/gpt-oss-120b", usage: TokenUsage(prompt: 1, completion: 1, total: 2)))
        try await h.store.update(id) { $0.state = .structuring } // Absturz mitten im Ordnen
        await h.run("launch")
        #expect(await h.thought(id)?.title == "Aus dem Cache")
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.transcriber.calls == 0)
        #expect(await h.structurer.calls == 0)
    }

    @Test func restartInStructuringWithoutCacheAsksOnceMore() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let id = try await h.capture()
        try await h.store.saveSourceOnce(id, ThoughtSource(text: "die tomaten gießen", sentences: [], model: "whisper-large-v3",
                                                           createdAt: h.clock.now, languages: ["de"], audioSeconds: 1))
        try await h.store.update(id) { $0.state = .structuring }
        await h.run("launch")
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.transcriber.calls == 0) // Rohtext liegt: nie wieder Whisper
        #expect(await h.structurer.calls == 1)
    }

    @Test func deletedDuringStructuringIsNotApplied() async throws {
        let structurer = MockStructurer()
        let h = try Harness.make(structurer: structurer)
        defer { h.cleanup() }
        let id = try await h.capture()
        let store = h.store
        await structurer.setOnCall { _ in try? await store.delete(id) }
        await h.run()
        let thought = try #require(await h.thought(id))
        #expect(thought.deletedAt != nil)
        #expect(thought.state != .done)
        #expect(thought.title == nil)
        #expect(await h.store.aiResult(id) != nil) // gesichert: Wiederherstellen kostet keinen neuen Aufruf
        #expect(await h.store.topics().isEmpty) // kein Thema angelegt
        try await h.store.restore(id)
        await h.run()
        #expect(await h.thought(id)?.state == .done)
        #expect(await structurer.calls == 1)
    }

    @Test func userFieldsSurviveReorganize() async throws {
        let structurer = MockStructurer()
        let h = try Harness.make(structurer: structurer)
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.run()
        let own = Topic(title: "Balkon", icon: .home, owner: .user)
        try await h.store.saveTopics(await h.store.topics() + [own])
        try await h.store.update(id) { t in
            t.title = "Mein Titel"
            t.titleOwner = .user
            t.topicId = own.id
            t.topicOwner = .user
            t.tasks[0].done = true
            t.tasks[0].doneAt = Date()
            t.tasks.append(ThoughtTask(text: "Erde kaufen", owner: .user))
        }
        await structurer.push(Self.success(title: "KI-Titel", clean: "Neuer Text.", topic: .new(name: "Gemüse", icon: .leaf),
                                           tasks: [TaskDraft(text: "Tomaten gießen", quote: "tomaten", dueHint: nil),
                                                   TaskDraft(text: "Dünger holen", quote: "dünger", dueHint: nil)]))
        await h.processor.reorganize(id)
        await h.processor.waitUntilIdle()
        let thought = try #require(await h.thought(id))
        #expect(thought.state == .done)
        #expect(thought.title == "Mein Titel")
        #expect(thought.topicId == own.id)
        #expect(thought.text == "Neuer Text.")
        #expect(thought.tasks.map(\.text) == ["Tomaten gießen", "Erde kaufen", "Dünger holen"]) // erledigt + eigene bleiben, Doppel fällt weg
        #expect(thought.tasks[0].done)
        #expect(await structurer.calls == 2) // „Erneut ordnen“ = neue Anfrage
        #expect(await h.transcriber.calls == 1) // aber kein zweites Whisper
        #expect(await h.store.aiResult(id)?.title == "KI-Titel")
        #expect(!(await h.store.topics().contains { $0.title == "Gemüse" })) // Thema vom Nutzer: KI-Wahl ignoriert
    }

    @Test func liveTranscriptAvoidsSecondWhisperCall() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.processor.expectLiveTranscript(id)
        await h.run("captured")
        #expect(await h.thought(id)?.state == .captured) // wartet auf die Live-Pipeline
        await h.processor.liveTranscript(id, outcome: DictationOutcome(text: "die tomaten gießen", raw: "die tomaten gießen", languages: ["de"],
                                                                       timings: DictationTimings(audioSeconds: 1)))
        await h.processor.waitUntilIdle()
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.transcriber.calls == 0)
        #expect(await h.store.source(id)?.text == "die tomaten gießen")
    }

    @Test func failedLiveTranscriptFallsBackToFile() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.processor.liveTranscript(id, outcome: DictationOutcome(errorMessage: GroqFailure.network(code: -1009).germanMessage))
        await h.processor.waitUntilIdle()
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.transcriber.calls == 1)
    }

    @Test func nothingSaidRemovesThought() async throws {
        let h = try Harness.make(transcriber: MockTranscriber([.noSpeech]))
        defer { h.cleanup() }
        let events = h.processor.events
        let id = try await h.capture()
        await h.run()
        #expect(await h.thought(id) == nil)
        #expect(!FileManager.default.fileExists(atPath: h.store.directory(id).path))
        var iterator = events.makeAsyncIterator()
        var last: ProcessorEvent?
        while let event = await iterator.next() {
            last = event
            if case .empty = event { break }
        }
        #expect(last == .empty(id))
    }

    @Test func serverErrorsEndInNeedsAttentionAfterFiveAttempts() async throws {
        let h = try Harness.make(transcriber: MockTranscriber(Array(repeating: .failure(.server), count: 5)))
        defer { h.cleanup() }
        let id = try await h.capture()
        var delays: [TimeInterval] = []
        for _ in 0..<5 {
            await h.run()
            let thought = try #require(await h.thought(id))
            if let retryAt = thought.status.retryAt {
                delays.append(retryAt.timeIntervalSince(h.clock.now))
                h.clock.set(retryAt)
            }
        }
        #expect(delays == [30, 60, 120, 240])
        let thought = try #require(await h.thought(id))
        #expect(thought.state == .needsAttention)
        #expect(thought.status.message == "Ton gesichert · nicht verschriftlicht")
        await h.run()
        #expect(await h.transcriber.calls == 5) // keine weiteren Versuche
        await h.processor.reorganize(id) // „Erneut versuchen“
        await h.processor.waitUntilIdle()
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.transcriber.calls == 6)
    }

    @Test func networkErrorsBackOffWithoutGivingUpEarly() async throws {
        let h = try Harness.make(transcriber: MockTranscriber(Array(repeating: .failure(.network), count: 7)))
        defer { h.cleanup() }
        let id = try await h.capture()
        for attempt in 0..<7 {
            await h.run()
            if attempt < 6, let retryAt = await h.thought(id)?.status.retryAt { h.clock.set(retryAt) }
        }
        let thought = try #require(await h.thought(id))
        #expect(thought.state == .waitingNetwork) // < 24 h: weiter warten
        #expect(thought.status.attempts == 7)
        #expect(thought.status.retryAt == h.clock.now.addingTimeInterval(600)) // höchstens 10 Min.
    }

    @Test func unusableResultKeepsRawText() async throws {
        let h = try Harness.make(structurer: MockStructurer([.unusable(code: "invalid_output")]))
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.run()
        let thought = try #require(await h.thought(id))
        #expect(thought.state == .done)
        #expect(thought.textIsRaw)
        #expect(thought.text == "Ähm also die Tomaten im Garten muss ich morgen gießen")
        #expect(thought.title == "Ähm also die Tomaten im Garten …")
        #expect(thought.topicId == nil && thought.tasks.isEmpty)
        #expect(thought.ai?.rejections == ["invalid_output"])
    }

    @Test func dictationHasPriority() async throws {
        let flagsBox = Box<Flags?>(nil)
        let h = try Harness.make(onSleep: {
            // nach dem dritten Warten ist das Diktat fertig
            if let flags = flagsBox.value, flags.busyChecks >= 3 { flags.busy = false }
        })
        defer { h.cleanup() }
        flagsBox.value = h.flags
        h.flags.busy = true
        let id = try await h.capture()
        await h.run()
        #expect(await h.thought(id)?.state == .done)
        #expect(h.flags.busyChecks >= 4)
        #expect(h.sleeps.value.count >= 3)
    }

    @Test func linksOnlyToExistingThoughtsAndExistingTopicResolves() async throws {
        let structurer = MockStructurer()
        let h = try Harness.make(structurer: structurer)
        defer { h.cleanup() }
        let older = StoreSupport.thought(createdAt: h.clock.now.addingTimeInterval(-3_600), title: "Tomaten pflanzen", text: "Im Garten Tomaten pflanzen.")
        try await h.store.save(older)
        let garden = Topic(id: "t_garden", title: "Garten", icon: .leaf, owner: .user)
        let alias = Topic(id: "t_alias", title: "Beet", icon: .leaf, owner: .ai, mergedInto: "t_garden")
        try await h.store.saveTopics([garden, alias])
        await structurer.push(Self.success(topic: .existing("t_alias"), related: [
            RelatedDraft(thoughtID: older.id, kind: .continues, reason: "Gleiches Beet"),
            RelatedDraft(thoughtID: "s_gibtsnicht", kind: .sameMatter, reason: "x"),
        ]))
        let id = try await h.capture()
        await h.run()
        let thought = try #require(await h.thought(id))
        #expect(thought.topicId == "t_garden") // Alias aufgelöst
        #expect(thought.links.map(\.target) == [older.id])
        #expect(thought.links.first?.origin == .ai)
        let candidates = try #require(await structurer.inputs.first?.candidates)
        #expect(candidates.contains { $0.thoughtID == older.id }) // letzte 3 h immer dabei
        #expect(!candidates.contains { $0.thoughtID == id })
        let topics = try #require(await structurer.inputs.first?.topics)
        #expect(topics.map(\.topicID) == ["t_garden"])
    }

    /// Offline aufgenommen, erst später geordnet: `recordedAt` = Aufnahmezeit, Kandidaten relativ dazu,
    /// gespeicherte Prompt-Version = `ThoughtPrompt.version`.
    @Test func lateStructuringUsesTheRecordingTime() async throws {
        let structurer = MockStructurer()
        let h = try Harness.make(structurer: structurer)
        defer { h.cleanup() }
        let older = StoreSupport.thought(createdAt: h.clock.now.addingTimeInterval(-3_600), title: "Tomaten pflanzen",
                                         text: "Im Garten Tomaten pflanzen.")
        try await h.store.save(older)
        let id = try await h.capture()
        let recordedAt = try #require(await h.thought(id)?.createdAt)
        h.clock.advance(2 * 86_400)                                          // erst zwei Tage später geordnet
        await h.run()
        let input = try #require(await structurer.inputs.first)
        #expect(input.recordedAt == recordedAt)
        let candidate = try #require(input.candidates.first { $0.thoughtID == older.id }) // 3-h-Fenster der Aufnahme
        #expect(candidate.when == CandidateFinder.when(older.createdAt, now: recordedAt))
        #expect(candidate.when.hasPrefix("heute"))
        #expect(await h.thought(id)?.ai?.promptVersion == ThoughtPrompt.version)
        #expect(ThoughtProcessor.Options().promptVersion == ThoughtPrompt.version)
    }

    /// Verworfen mit Live-Pipeline (H3): Ohne Abbruch wartet der Dateiweg bis `liveWait`; nach
    /// `cancelLiveTranscript` ordnet ein Wiederherstellen sofort.
    @Test func cancelledLiveTranscriptDoesNotDelayARestore() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.processor.expectLiveTranscript(id)
        try await h.store.delete(id)                                         // verworfen → „Zuletzt gelöscht“
        await h.processor.cancelLiveTranscript(id)
        try await h.store.restore(id)
        await h.run()
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.transcriber.calls == 1)

        // Gegenprobe: Erwartung ohne Abbruch hält den Dateiweg innerhalb von `liveWait` zurück.
        let waiting = try await h.capture()
        await h.processor.expectLiveTranscript(waiting)
        await h.run()
        #expect(await h.thought(waiting)?.state == .captured)
        #expect(await h.transcriber.calls == 1)
    }

    @Test func newTopicMatchingExistingNameReusesIt() async throws {
        let h = try Harness.make(structurer: MockStructurer([Self.success(topic: .new(name: "Gärten", icon: .leaf))]))
        defer { h.cleanup() }
        let garden = Topic(id: "t_garden", title: "Garten", icon: .leaf, owner: .ai)
        try await h.store.saveTopics([garden])
        let id = try await h.capture()
        await h.run()
        #expect(await h.thought(id)?.topicId == "t_garden")
        #expect(await h.store.topics().count == 1)
    }

    @Test func longThoughtUsesPartsWithGapAndCombinesResult() async throws {
        let sentence = "Und dann müssen wir noch die Umzugskartons im Keller zählen und beschriften damit nichts verloren geht. "
        let long = String(repeating: sentence, count: 70) // ≈ 7 300 Bytes ≈ 2 400 Tokens
        let structurer = MockStructurer([
            Self.success(title: "Umzug planen", clean: "Teil eins.", topic: .new(name: "Umzug", icon: .home),
                         tasks: [TaskDraft(text: "Kartons zählen", quote: "kartons", dueHint: nil)]),
            Self.success(title: "", clean: nil, topic: .none,
                         tasks: [TaskDraft(text: "Kartons zählen", quote: "kartons", dueHint: nil),
                                 TaskDraft(text: "Kartons beschriften", quote: "beschriften", dueHint: nil)]),
        ])
        let transcriber = MockTranscriber([.success(text: long, languages: ["de"], audioSeconds: 420, model: "whisper-large-v3")])
        let h = try Harness.make(structurer: structurer, transcriber: transcriber)
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.run()
        let inputs = await structurer.inputs
        #expect(inputs.count == 2)
        #expect(inputs[0].part == nil)
        #expect(inputs[1].part?.index == 2 && inputs[1].part?.count == 2)
        #expect(inputs[1].candidates.isEmpty && inputs[1].topics.isEmpty)
        #expect(inputs.allSatisfy { PartSplitter.estimateTokens($0.transcript) <= PartSplitter.maxPartTokens })
        #expect(h.sleeps.value.contains { $0 > 50 }) // ≥ 60 s zwischen den Teilen
        let thought = try #require(await h.thought(id))
        #expect(thought.state == .done)
        #expect(thought.title == "Umzug planen")
        #expect(thought.text?.hasPrefix("Teil eins.\n\n") == true) // Teil 2 fiel auf den Rohtext zurück
        #expect(!thought.textIsRaw)
        #expect(thought.tasks.map(\.text) == ["Kartons zählen", "Kartons beschriften"])
        #expect(thought.ai?.tokens == 6_000)
        #expect(await h.store.parts(id) == nil)
    }

    @Test func partsProgressSurvivesWaiting() async throws {
        let sentence = "Und dann müssen wir noch die Umzugskartons im Keller zählen und beschriften damit nichts verloren geht. "
        let long = String(repeating: sentence, count: 70)
        let structurer = MockStructurer([Self.success(), .wait(.waitingLimit, retryAt: nil, message: "429"), Self.success()])
        let transcriber = MockTranscriber([.success(text: long, languages: ["de"], audioSeconds: 420, model: "whisper-large-v3")])
        let h = try Harness.make(structurer: structurer, transcriber: transcriber)
        defer { h.cleanup() }
        let id = try await h.capture()
        await h.run()
        #expect(await h.thought(id)?.state == .waitingLimit)
        #expect(await h.store.parts(id)?.first != nil)
        h.clock.advance(3_600)
        await h.run()
        #expect(await h.thought(id)?.state == .done)
        #expect(await structurer.calls == 3) // Teil 1 nicht doppelt
    }

    @Test func softDiscardedThoughtIsNeverProcessedUntilRestored() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let id = try await h.capture()
        let now = h.clock.now
        try await h.store.update(id) { $0.deletedAt = now } // H3: in der Live Activity verworfen (mit Ton)
        await h.run()
        // die Live-Pipeline liefert trotzdem noch: wird aufgehoben, aber nicht verarbeitet
        await h.processor.liveTranscript(id, outcome: DictationOutcome(text: "die tomaten gießen", raw: "die tomaten gießen", languages: ["de"]))
        await h.processor.waitUntilIdle()
        #expect(await h.thought(id)?.state == .captured)
        #expect(await h.store.source(id) == nil)
        #expect(await h.transcriber.calls == 0)
        #expect(await h.structurer.calls == 0)
        try await h.store.restore(id)
        await h.run("restore")
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.transcriber.calls == 0) // Ergebnis der Live-Pipeline genutzt
        #expect(await h.store.source(id)?.text == "die tomaten gießen")
    }

    @Test func topicHygieneAsksOnceAndStoresSuggestions() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let names = ["Wohnung", "Wohnungen", "Garten", "Fitness", "Lesen", "Urlaub", "Auto", "Familie"]
        let topics = names.map { Topic(title: $0, icon: .list, owner: .user) }
        try await store.saveTopics(topics)
        let (a, b) = (topics[0].id, topics[1].id)
        let content = "{\"pairs\":[{\"a\":\"\(a)\",\"b\":\"\(b)\",\"merge\":true,\"name\":\"Wohnung\",\"reason\":\"gleiches Vorhaben\"}]}"
        let server = MockServer { _, _ in
            .json(200, ["choices": [["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": content]]],
                        "usage": ["prompt_tokens": 400, "completion_tokens": 100, "total_tokens": 500]])
        }
        let ledger = TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: { TokenLedger.Limits() })
        let now = Date()
        let outcome = await TopicHygieneRunner.run(store: store, ledger: ledger, apiKey: "test-placeholder", force: false,
                                                   transport: server.transport, baseURL: server.baseURL, now: now)
        guard case .suggestions(let list) = outcome, let suggestion = list.first else {
            Issue.record("keine Vorschläge: \(outcome)")
            return
        }
        #expect(list.count == 1)
        #expect(Set([suggestion.a, suggestion.b]) == [a, b])
        #expect(suggestion.name == "Wohnung" && suggestion.reason == "gleiches Vorhaben")
        #expect(await store.pendingSuggestions() == list)
        #expect(await store.topicsInfo().lastHygieneAt != nil)
        let request = try #require(server.requests("/chat/completions").first)
        #expect(request.json?["model"] as? String == "openai/gpt-oss-20b")
        #expect(await ledger.summary().tokens == 500)
        // höchstens 1× je 7 Tage
        let again = await TopicHygieneRunner.run(store: store, ledger: ledger, apiKey: "test-placeholder", force: false,
                                                 transport: server.transport, baseURL: server.baseURL, now: now.addingTimeInterval(86_400))
        #expect(again == .notDue)
        // abgelehnt: nie wieder gefragt
        try await store.declineMerge(a, b)
        let forced = await TopicHygieneRunner.run(store: store, ledger: ledger, apiKey: "test-placeholder", force: true,
                                                  transport: server.transport, baseURL: server.baseURL, now: now)
        #expect(forced == .suggestions([]))
        #expect(server.requests("/chat/completions").count == 1)
    }

    // MARK: Hilfen

    @Test func partSplitterKeepsShortTranscriptsWhole() {
        let source = ThoughtSource(text: "Kurz.", sentences: [.init(id: "s_0", text: "Kurz.")], model: "w", createdAt: Date(), languages: [], audioSeconds: 1)
        #expect(PartSplitter.split(source).count == 1)
        let words = Array(repeating: "wort", count: 3_000).joined(separator: " ") // ein Satz ohne Satzzeichen, ≈ 5 000 Tokens
        let long = ThoughtSource(text: words, sentences: [.init(id: "s_0", text: words)], model: "w", createdAt: Date(), languages: [], audioSeconds: 600)
        let parts = PartSplitter.split(long)
        #expect(parts.count == 4)
        #expect(parts.allSatisfy { $0.tokens <= PartSplitter.maxPartTokens })
        #expect(parts.map(\.text).joined(separator: " ") == words)
    }

    @Test func partSplitterCutsBeforeHesitationsInUnpunctuatedText() throws {
        // e35 aus dem Bewertungssatz: 938 Wörter Whisper-Rohtext ohne ein einziges Satzzeichen
        let line = try String(contentsOf: StoreSupport.fixtures.appendingPathComponent("eval.jsonl"), encoding: .utf8)
            .split(separator: "\n").first { $0.contains("\"id\": \"e35\"") || $0.contains("\"id\":\"e35\"") }
        let found = try #require(line)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(found.utf8)) as? [String: Any])
        let transcript = try #require(object["transcript"] as? String)
        let source = ThoughtSource(text: transcript, sentences: PartSplitter.sentences(transcript, thoughtID: "s_e35"), model: "w",
                                   createdAt: Date(), languages: ["de"], audioSeconds: 420)
        let parts = PartSplitter.split(source)
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { $0.tokens <= PartSplitter.maxPartTokens })
        for part in parts.dropFirst() {
            let first = part.text.split(separator: " ").first.map { String($0).lowercased() } ?? ""
            #expect(PartSplitter.hesitations.contains(first), "Teil beginnt mit „\(first)“")
        }
        #expect(parts.map(\.text).joined(separator: " ") == transcript.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        let sizes = parts.map(\.tokens)
        #expect(Double(sizes.min()!) / Double(sizes.max()!) > 0.6) // ungefähr gleich groß
        #expect(parts.allSatisfy { $0.sentences.first?.id == "s_e35_s0" }) // Satz-ID bleibt erhalten
    }

    @Test func partSplitterPrefersSentenceEndsThenMarkersThenLength() {
        // Satzzeichen vorhanden: an Satzanfängen schneiden
        let sentence = "Wir müssen die Kartons im Keller zählen und beschriften, damit nichts verloren geht. "
        let punctuated = String(repeating: sentence, count: 80)
        let source = ThoughtSource(text: punctuated, sentences: PartSplitter.sentences(punctuated, thoughtID: "s_p"), model: "w",
                                   createdAt: Date(), languages: ["de"], audioSeconds: 400)
        let parts = PartSplitter.split(source)
        #expect(parts.count == 2)
        #expect(parts.allSatisfy { $0.text.hasPrefix("Wir müssen") && $0.text.hasSuffix("geht.") })
        // ohne Satzzeichen, mit Gesprächsmarkern: vor „also“
        let words = (0..<700).map { $0 % 50 == 0 && $0 > 0 ? "also" : "wort\($0 % 7)" }.joined(separator: " ")
        let marked = PartSplitter.split(ThoughtSource(text: words, sentences: [.init(id: "s_m_s0", text: words)], model: "w",
                                                      createdAt: Date(), languages: ["de"], audioSeconds: 400), force: true)
        #expect(marked.count == 2)
        #expect(marked[1].text.hasPrefix("also "))
        // gar nichts: nach Länge, an Wortgrenzen, ausgewogen
        let plain = Array(repeating: "wort", count: 2_000).joined(separator: " ")
        let byLength = PartSplitter.split(ThoughtSource(text: plain, sentences: [.init(id: "s_l_s0", text: plain)], model: "w",
                                                        createdAt: Date(), languages: [], audioSeconds: 400))
        #expect(byLength.count == 3)
        #expect(byLength.allSatisfy { $0.tokens <= PartSplitter.maxPartTokens && $0.tokens > 900 })
        // „um“ ist im Deutschen kein Zögerlaut („um zu“), im Englischen schon
        let german = PartSplitter.words([.init(id: "a", text: "ich gehe raus um zu laufen")], languages: ["de"])
        let english = PartSplitter.words([.init(id: "a", text: "so I think um we should go")], languages: ["en"])
        #expect(german[3].boundary == 0)
        #expect(english[3].boundary == 3)
    }

    @Test func transcriptionErrorsAreClassified() {
        #expect(FileTranscriber.classify(GroqFailure.http(status: 401, code: nil, retryAfter: nil).germanMessage) == .unauthorized)
        #expect(FileTranscriber.classify(GroqFailure.http(status: 403, code: nil, retryAfter: nil).germanMessage) == .unauthorized)
        #expect(FileTranscriber.classify(GroqFailure.http(status: 429, code: nil, retryAfter: 3).germanMessage) == .rateLimited)
        #expect(FileTranscriber.classify(GroqFailure.http(status: 503, code: nil, retryAfter: nil).germanMessage) == .server)
        #expect(FileTranscriber.classify(GroqFailure.http(status: 404, code: nil, retryAfter: nil).germanMessage) == .modelMissing)
        #expect(FileTranscriber.classify(GroqFailure.http(status: 400, code: nil, retryAfter: nil).germanMessage) == .rejected)
        #expect(FileTranscriber.classify(GroqFailure.network(code: -1009).germanMessage) == .network)
        #expect(FileTranscriber.classify(GroqFailure.invalidResponse.germanMessage) == .invalidResponse)
        #expect(FileTranscriber.result(from: DictationOutcome(noSpeech: true), model: "w") == .noSpeech)
        #expect(FileTranscriber.result(from: DictationOutcome(), model: "w") == .failure(.cancelled))
    }

    @Test func fileTranscriberMakesExactlyOneWhisperRequest() async throws {
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models("whisper-large-v3") }
            return Groq.transcription("die tomaten im garten gießen")
        }
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let url = root.appendingPathComponent("audio.wav")
        let writer = try WAVWriter(url: url)
        writer.append(Synth.withFloor(Synth.silence(0.5) + Synth.speech(4) + Synth.silence(0.5)))
        _ = writer.close()
        var settings = PaplySettings()
        settings.chunkedUpload = true // wird für den Dateiweg abgeschaltet
        let transcriber = FileTranscriber(transport: server.transport, baseURL: server.baseURL, catalog: ModelCatalog())
        let result = await transcriber.transcribe(audioURL: url, apiKey: "test-placeholder", settings: settings)
        #expect(result == .success(text: "die tomaten im garten gießen", languages: ["de"], audioSeconds: 5, model: "whisper-large-v3"))
        #expect(server.requests("/audio/transcriptions").count == 1)
        #expect(server.requests("/chat/completions").isEmpty) // nie polieren
    }

    @Test func dueDatesFollowRecordingTime() {
        // NSDataDetector rechnet ab der echten Uhr; verarbeitet wird „jetzt“, aufgenommen vor zwei Tagen (offline)
        let processed = Date()
        let recorded = processed.addingTimeInterval(-2 * 86_400)
        let tomorrow = DueDate.resolve("morgen", reference: recorded, now: processed)
        #expect(tomorrow.map { Calendar.current.isDate($0, inSameDayAs: recorded.addingTimeInterval(86_400)) } == true)
        #expect(DueDate.resolve("irgendwann", reference: recorded, now: recorded) == nil)
        #expect(DueDate.resolve(nil, reference: recorded, now: recorded) == nil)
    }

    @Test func rawTextFallbackHelpers() {
        #expect(RawText.tidy("ähm  also. das geht   so? ja") == "Ähm also. Das geht so? Ja")
        #expect(RawText.fallbackTitle("eins zwei drei vier fünf sechs sieben") == "eins zwei drei vier fünf sechs …")
        #expect(RawText.fallbackTitle("kurz.") == "kurz")
        #expect(RawText.key("Tomaten gießen!") == RawText.key("tomaten giessen"))
    }
}
