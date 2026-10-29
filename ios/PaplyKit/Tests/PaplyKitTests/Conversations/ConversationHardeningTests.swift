import Foundation
import Testing
@testable import PaplyKit

struct ConversationHardeningTests {
    @Test func firstRoomVoiceCannotPoisonOwner() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceProfileStore(root: root)
        func print(_ vector: [Float]) -> VoicePrint { .init(vector: vector, model: "m", seconds: 10, source: .thought) }
        try await store.learn(print([0, 1]))
        for _ in 0..<2 { try await store.learn(print([1, 0])) }
        #expect(try await store.learningStatus().isLearning)
        let reopened = VoiceProfileStore(root: root)
        try await reopened.learn(print([1, 0]))
        #expect(try await reopened.learningStatus().learnedThoughts == 3)
        #expect(try await reopened.people().first?.prints.allSatisfy { $0.vector == [1, 0] } == true)
        try await reopened.learn(print([0, 1]))
        #expect(try await reopened.learningStatus().learnedThoughts == 3)
    }

    @Test func enrollmentBypassesCandidates() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let profiles = VoiceProfileStore(root: root)
        try await profiles.enroll(audio: root, diarizer: FakeDiarizer())
        #expect(try await profiles.learningStatus().isLearning == false)
        #expect(try await profiles.people().first?.prints.first?.source == .enrollment)
    }

    @Test func silenceAndShiftedWords() {
        let d = Diarization(segments: [.init(start: 1, end: 2, cluster: 0)],
                            centroids: [0: [1, 0]], speechSeconds: [0: 1], model: "m")
        let words: [ConversationWord] = [
            .init(word: "Hallo", start: 0.6, end: 0.8),
            .init(word: "Welt", start: 1.2, end: 1.7),
            .init(word: "Vielen Dank.", start: 12, end: 13),
            .init(word: "Untertitel Copyright", start: 18, end: 19)]
        #expect(SpeakerAlignment.align(words: words, diarization: d).utterances.map(\.text).joined(separator: " ") == "Hallo Welt")
    }

    @Test func overlapJoinLosesNoWordsOrRepeats() {
        let first: [ConversationWord] = [
            .init(word: "Wir", start: 598, end: 598.3),
            .init(word: "planen", start: 598.4, end: 599),
            .init(word: "morgen", start: 599.1, end: 599.8)]
        let next: [ConversationWord] = [
            .init(word: "planen", start: 598.45, end: 599.05),
            .init(word: "morgen", start: 599.15, end: 599.85),
            .init(word: "weiter.", start: 600, end: 600.5),
            .init(word: "Ja", start: 601, end: 601.2),
            .init(word: "ja", start: 601.5, end: 601.7)]
        #expect(ConversationTranscriber.join(first, next).map(\.word) == ["Wir", "planen", "morgen", "weiter.", "Ja", "ja"])
    }

    @Test func quietCutUsesLastThirtySeconds() {
        var samples = Array(repeating: Int16(1000), count: 600 * 16000)
        samples.replaceSubrange(585 * 16000..<586 * 16000, with: repeatElement(Int16(1), count: 16000))
        let cut = ConversationTranscriber.quietCut(samples)
        #expect(cut >= 585 * 16000 && cut < 586 * 16000)
    }

    @Test func contextPrioritizesNamedTopicsAndFits() {
        var input = ConversationPipelineTests().input(URL(fileURLWithPath: "/tmp"))
        input.topics = (0..<300).map { .init(topicID: "t\($0)", name: "Projekt \($0)", count: 300 - $0, hint: [], about: String(repeating: "x", count: 10000)) }
        let context = ConversationSummarizer.context(input, speakers: [], raw: "Projekt 299")
        #expect(PartSplitter.estimateTokens(context) < 1200)
        #expect(context.contains("t299: Projekt 299"))
    }

    @Test func invalidSpeakerReferencesAreCleaned() {
        let speakers = [ConversationSpeaker(id: "S2", speechSeconds: 10, colorIndex: 2)]
        #expect(ConversationSummarizer.sanitize("Sprecher 2 hilft [S99].", speakers: speakers) == "[S2] hilft eine Person.")
    }

    @Test func shortRateLimitRetriesInternally() async throws {
        var calls = 0
        let value: Int = try await ConversationRetry.run {
            calls += 1
            if calls == 1 { throw GroqFailure.http(status: 429, code: nil, retryAfter: 0.01) }
            return 7
        }
        #expect(value == 7)
        #expect(calls == 2)
    }

    @Test func editorRendersAndPreservesUserFields() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        let profiles = VoiceProfileStore(root: root)
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: profiles,
            analyzer: UnusedAnalyzer(), environment: .init(apiKey: { "" }))
        let speakers = [ConversationSpeaker(id: "S1", speechSeconds: 10, colorIndex: 1),
                        ConversationSpeaker(id: "S2", speechSeconds: 5, colorIndex: 2)]
        try await store.save(.init(id: "test", origin: .recording, trigger: .app, state: .done, stagesDone: [.speakers],
            title: "[S2] hilft", summary: .init(overview: "[S1] fragt [S2].", points: []), speakers: speakers))
        try await thoughts.save(.init(id: "test", kind: ConversationKind.thoughtKind, trigger: .app, state: .done))
        try await store.saveVoiceprints(["S1": .init(vector: [1, 0], model: "m", seconds: 10, source: .conversation)], for: "test")
        try await store.saveTranscript(.init(utterances: [.init(id: "u0", speakerID: "S1", start: 0, end: 2, text: "Hallo")],
            languages: ["de"], model: "test", createdAt: Date()), for: "test")
        try await processor.nameSpeaker("test", speakerID: "S1", as: .owner, rememberVoice: true)
        try await processor.nameSpeaker("test", speakerID: "S2", as: .newPerson("Anna"), rememberVoice: false)
        #expect(await thoughts.thought("test")?.text == "Ich fragt Anna.")
        #expect(await thoughts.thought("test")?.title == "Anna hilft")
        #expect(try await profiles.learningStatus().isLearning == false)
        try await processor.reassignUtterance("test", utteranceID: "u0", to: "S2")
        try await processor.reassignUtterance("test", utteranceID: "u0", to: "S1")
        #expect(try await store.transcript("test")?.utterances.first?.speakerID == "S1")
        try await processor.mergeSpeakers("test", from: "S1", into: "S2")
        #expect(try await store.conversation("test")?.speakers.first?.colorIndex == 2)
        #expect(try await store.conversation("test")?.speakers.first?.speechSeconds == 15)
        #expect(try await store.transcript("test")?.utterances.first?.speakerID == "S2")
        try await thoughts.update("test") { $0.text = "Mein Text"; $0.textOwner = .user }
        try await processor.rename("test", title: "Neuer Titel")
        #expect(await thoughts.thought("test")?.text == "Mein Text")
        #expect(await thoughts.thought("test")?.title == "Neuer Titel")
        try await thoughts.delete("test")
        try await processor.synchronizeLinkedThought("test")
        #expect(try await store.conversation("test")?.deletedAt != nil)
        try await thoughts.restore("test")
        try await processor.reconcileDeletionStates()
        #expect(try await store.conversation("test")?.deletedAt == nil)
    }
}

private struct UnusedAnalyzer: ConversationAnalyzing {
    func analyze(_ input: ConversationAnalysisInput, apiKey: String, progress: @escaping @Sendable (ConversationProgress) -> Void) async -> ConversationAnalysisOutcome { .empty }
}

private struct BrokenDiarizer: SpeakerDiarizing {
    let embeddingModel = "broken"
    func voiceprint(audio: URL) async throws -> VoicePrint? { nil }
    func diarize(audio: URL, expectedSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization {
        throw ThoughtStoreError.unavailable
    }
}

extension ConversationHardeningTests {
    @Test func diarizerFailureReturnsTextAndRecoversFromWhisperCache() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try WAVWriter(url: root.appendingPathComponent("audio.wav"))
        writer.append(StoreSupport.tone(seconds: 0.2))
        _ = writer.close()
        let answer = ConversationPipelineTests().answer()
        let server = MockServer { request, _ in
            if request.path.hasSuffix("transcriptions") {
                return .json(200, ["words": [["word": "Hallo", "start": 0, "end": 0.1]], "duration": 0.2])
            }
            return .json(200, ["choices": [["finish_reason": "stop", "message": ["content": answer]]]])
        }
        let ledger = ConversationLedger.make(root: root)
        let transcriber = ConversationTranscriber(ledger: ledger, client: server.client())
        let summarizer = ConversationSummarizer(ledger: ledger, client: server.client())
        let input = ConversationPipelineTests().input(root)
        let broken = ConversationAnalyzer(diarizer: BrokenDiarizer(), transcriber: transcriber, summarizer: summarizer)
        let first = await broken.analyze(input, apiKey: "test") { _ in }
        guard case .partial(let partial, _, let retry, _) = first else { Issue.record("Wortlaut fehlt"); return }
        #expect(partial.transcript?.utterances.first?.text == "Hallo")
        #expect(partial.speakers.count == 1)
        #expect(retry != nil)
        let repaired = ConversationAnalyzer(diarizer: FakeDiarizer(), transcriber: transcriber, summarizer: summarizer)
        let next = await repaired.analyze(input, apiKey: "test") { _ in }
        guard case .done = next else { Issue.record("Wiederaufnahme fehlt"); return }
        #expect(server.requests("transcriptions").count == 1)
    }

    @Test func shortWhisperLimitUsesMockRetry() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try WAVWriter(url: root.appendingPathComponent("audio.wav"))
        writer.append(StoreSupport.tone(seconds: 0.2))
        _ = writer.close()
        let server = MockServer { _, index in
            if index == 0 { return .json(429, ["error": ["code": "rate_limit_exceeded"]], headers: ["Retry-After": "0.01"]) }
            return .json(200, ["words": [["word": "Hallo", "start": 0, "end": 0.1]], "duration": 0.2])
        }
        let transcriber = ConversationTranscriber(ledger: ConversationLedger.make(root: root), client: server.client())
        let result = try await transcriber.transcribe(audio: root.appendingPathComponent("audio.wav"),
            workDirectory: root.appendingPathComponent("work"), apiKey: "test", mainLanguage: "de", vocabulary: [])
        #expect(result.words.count == 1)
        #expect(server.requests.count == 2)
    }

    @Test func overlappingSimilarVoicesStaySeparate() {
        let d = Diarization(segments: [.init(start: 0, end: 2, cluster: 0), .init(start: 1, end: 1.5, cluster: 1)],
                            centroids: [0: [1, 0], 1: [0.99, 0.01]], speechSeconds: [0: 2, 1: 0.5], model: "m")
        #expect(SpeakerAlignment.align(words: [], diarization: d).speakers.count == 2)
    }

    @Test func deletionJournalCompletesAfterRestart() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        try await store.save(.init(id: "test", origin: .recording, trigger: .app, state: .captured))
        try await thoughts.save(.init(id: "test", kind: ConversationKind.thoughtKind, trigger: .app, state: .done))
        try FileSafety.writeAtomically(Data("true".utf8), to: store.directory("test").appendingPathComponent("deletion.json"))
        try await store.delete("test")
        let reopened = ConversationStore(root: root)
        let processor = ConversationProcessor(store: reopened, thoughts: thoughts, profiles: VoiceProfileStore(root: root),
            analyzer: UnusedAnalyzer(), environment: .init(apiKey: { "" }))
        try await processor.reconcileDeletionStates()
        #expect(await thoughts.thought("test")?.deletedAt != nil)
        let deleted = try await reopened.conversation("test")?.deletedAt
        try await processor.delete("test")
        #expect(try await reopened.conversation("test")?.deletedAt == deleted)
        try await processor.restore("test")
        try await processor.restore("test")
        #expect(await thoughts.thought("test")?.deletedAt == nil)
    }
}

private struct EditingAnalyzer: ConversationAnalyzing {
    var includeThird = false
    func analyze(_ input: ConversationAnalysisInput, apiKey: String, progress: @escaping @Sendable (ConversationProgress) -> Void) async -> ConversationAnalysisOutcome {
        var speakers = [
            ConversationSpeaker(id: "S1", speechSeconds: 2, colorIndex: 1),
            ConversationSpeaker(id: "S2", suggestion: .init(name: "Falsch", source: .transcript), speechSeconds: 1, colorIndex: 2)]
        if includeThird { speakers.append(.init(id: "S3", speechSeconds: 1, colorIndex: 3)) }
        return .done(.init(stagesDone: ConversationStage.allCases, speakers: speakers, speakerPrints: [:],
            transcript: .init(utterances: [.init(id: "u0", speakerID: "S1", start: 0, end: 0.1, text: "Bitte anrufen.")],
                              languages: ["de"], model: "test", createdAt: input.recordedAt),
            title: "[S1] plant", summary: .init(overview: "[S1] hilft [S2].", points: [], commitments: [.init(id: "task1", speakerID: "S1", text: "[S1] anrufen", quote: "Bitte anrufen.")]),
            tasks: [], topic: nil,
            audioSeconds: 0.2, usage: nil, model: nil))
    }
}

extension ConversationHardeningTests {
    @Test func editsSurviveProcessorRestartAndReanalysis() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        let profiles = VoiceProfileStore(root: root)
        let (item, writer) = try await store.beginRecording(trigger: .app, at: Date())
        writer.append(StoreSupport.tone(seconds: 0.2))
        _ = try await store.finishRecording(item.id, durationMs: writer.close(), gaps: [])
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: profiles,
            analyzer: EditingAnalyzer(), environment: .init(apiKey: { "test" }))
        await processor.kick()
        await processor.waitUntilIdle()
        try await processor.rejectSuggestion(item.id, speakerID: "S2")
        try await processor.mergeSpeakers(item.id, from: "S1", into: "S2")
        try await processor.nameSpeaker(item.id, speakerID: "S2", as: .newPerson("Anna"), rememberVoice: false)
        #expect(await thoughts.thought(item.id)?.tasks.isEmpty == true)
        try await processor.nameSpeaker(item.id, speakerID: "S2", as: .owner, rememberVoice: false)
        #expect(await thoughts.thought(item.id)?.tasks.first?.text == "Ich anrufen")
        try await thoughts.update(item.id) {
            $0.tasks[0].text = "Mein eigener Auftrag"
            $0.tasks[0].owner = .user
            $0.title = "Mein eigener Titel"
            $0.titleOwner = .user
        }
        let restarted = ConversationProcessor(store: store, thoughts: thoughts, profiles: profiles,
            analyzer: EditingAnalyzer(), environment: .init(apiKey: { "test" }))
        try await restarted.retry(item.id)
        await restarted.waitUntilIdle()
        #expect(try await store.conversation(item.id)?.speakers.map(\.id) == ["S2"])
        #expect(try await store.conversation(item.id)?.speakers.first?.suggestion == nil)
        #expect(try await store.transcript(item.id)?.utterances.first?.speakerID == "S2")
        #expect(await thoughts.thought(item.id)?.text == "Ich hilft Ich.")
        #expect(await thoughts.thought(item.id)?.title == "Mein eigener Titel")
        #expect(await thoughts.thought(item.id)?.tasks.contains { $0.text == "Mein eigener Auftrag" && $0.owner == .user } == true)
    }

    @Test func greyAndUnknownIdentityStayUnconfirmed() {
        let speaker = ConversationSpeaker(id: "S1", speechSeconds: 10, colorIndex: 1)
        let person = VoicePerson(id: "owner", name: "", prints: [.init(vector: [1, 0], model: "m", seconds: 10, source: .enrollment)])
        for (vector, suggested) in [([Float(0.7), Float(0.714)], true), ([Float(0), Float(1)], false)] {
            let result = SpeakerIdentifier.identify([speaker], prints: ["S1": .init(vector: vector, model: "m", seconds: 10, source: .conversation)], people: [person])
            #expect(result[0].personID == nil)
            #expect((result[0].suggestion != nil) == suggested)
        }
    }
}

extension ConversationHardeningTests {
    @Test func partialSummaryFallsBackButFinalUsesPrimary() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let answer = #"{"title":"Plan","overview":"[S1] plant.","points":[],"tasks":[{"text":"Erfunden","quote":"NICHT GESAGT","dueHint":null,"speakerID":null}],"commitments":[],"topicID":"falsch","newTopic":null,"names":[]}"#
        let server = MockServer { _, index in
            if index == 0 { return .json(429, ["error": ["code": "rate_limit_exceeded"]], headers: ["Retry-After": "120"]) }
            return .json(200, ["choices": [["finish_reason": "stop", "message": ["content": answer]]], "usage": ["total_tokens": 100]])
        }
        let ledger = TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: {
            var limits = TokenLedger.Limits()
            limits.minuteTokens = 100000
            return limits
        })
        let summarizer = ConversationSummarizer(ledger: ledger, client: server.client())
        let transcript = ConversationTranscript(utterances: [.init(id: "u0", speakerID: "S1", start: 0, end: 100,
            text: String(repeating: "Wir planen das Büro. ", count: 600))], languages: ["de"], model: "test", createdAt: Date())
        let result = try await summarizer.summarize(ConversationPipelineTests().input(root), transcript: transcript,
            speakers: [.init(id: "S1", speechSeconds: 100, colorIndex: 1)], apiKey: "test")
        let models = server.requests.compactMap { $0.json?["model"] as? String }
        #expect(models.first == ConversationSummarizer.primaryModel)
        #expect(models.contains(ConversationSummarizer.fallbackModel))
        #expect(models.last == ConversationSummarizer.primaryModel)
        #expect(result.tasks.isEmpty)
        #expect(result.topic == TopicDecision.none)
    }
}

extension ConversationHardeningTests {
    @Test func learningCountSurvivesPrintCompactionAndForget() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceProfileStore(root: root)
        for _ in 0..<25 {
            try await store.learn(.init(vector: [1, 0], model: "m", seconds: 10, source: .thought))
        }
        let reopened = VoiceProfileStore(root: root)
        #expect(try await reopened.learningStatus().learnedThoughts == 25)
        #expect(try await reopened.people().first?.prints.count == 20)
        try await reopened.forgetVoice(VoicePerson.ownerID)
        #expect(try await reopened.learningStatus().learnedThoughts == 0)
        #expect(try await reopened.learningStatus().isLearning)
    }
}

extension ConversationHardeningTests {
    @Test func seamReplacesTruncatedWord() {
        let previous = [ConversationWord(word: "ange", start: 599.5, end: 600)]
        let next = [ConversationWord(word: "angefangen", start: 599.45, end: 600.4),
                    ConversationWord(word: "heute", start: 600.5, end: 601)]
        #expect(ConversationTranscriber.join(previous, next).map(\.word) == ["angefangen", "heute"])
    }
}

extension ConversationHardeningTests {
    @Test func replayedCandidateDoesNotBecomeThreeThoughts() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let print = VoicePrint(vector: [1, 0], model: "m", seconds: 10, source: .thought)
        for _ in 0..<3 {
            try await VoiceProfileStore(root: root).learn(print, candidateID: "same-recording")
        }
        #expect(try await VoiceProfileStore(root: root).learningStatus().isLearning)
    }
}

extension ConversationHardeningTests {
    @Test func explicitReassignmentWinsOverEarlierMergeOnRetry() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        let (item, writer) = try await store.beginRecording(trigger: .app, at: Date())
        writer.append(StoreSupport.tone(seconds: 0.2))
        _ = try await store.finishRecording(item.id, durationMs: writer.close(), gaps: [])
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root),
            analyzer: EditingAnalyzer(includeThird: true), environment: .init(apiKey: { "test" }))
        await processor.kick()
        await processor.waitUntilIdle()
        try await processor.mergeSpeakers(item.id, from: "S1", into: "S2")
        try await processor.reassignUtterance(item.id, utteranceID: "u0", to: "S3")
        try await processor.retry(item.id)
        await processor.waitUntilIdle()
        #expect(try await store.transcript(item.id)?.utterances.first?.speakerID == "S3")
        #expect(try await store.transcript(item.id)?.utterances.first?.speakerOwner == .user)
    }
}
