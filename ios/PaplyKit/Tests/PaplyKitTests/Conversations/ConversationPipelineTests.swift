import Foundation
import Testing
@testable import PaplyKit

struct ConversationPipelineTests {
    @Test func frenchCheckPreservesLanguageAndCacheSpeech() async throws {
        let root = try ConversationCoreTests().root(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("audio.wav")
        let writer = try WAVWriter(url: audio)
        writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        let server = MockServer { request, _ in
            let check = request.field("language") == "de"
            let text = check ? "Guten Abend" : "Bonsoir"
            return .json(200, ["words": [["word": text, "start": 0, "end": 0.2]],
                "segments": [["text": text, "start": 0, "end": 0.2, "avg_logprob": check ? -0.6 : -0.1]],
                "language": check ? "german" : "french", "duration": 0.2])
        }
        let transcriber = ConversationTranscriber(ledger: ConversationLedger.make(root: root), client: server.client())
        for _ in 0..<2 {
            let result = try await transcriber.transcribe(audio: audio, workDirectory: root.appendingPathComponent("work"), apiKey: "test", mainLanguage: "de", vocabulary: [])
            #expect(result.language == "fr")
            #expect(result.words.first?.word == "Bonsoir")
            #expect(result.languageSpeechSeconds?["fr"] != nil)
        }
        #expect(server.requests("transcriptions").map { $0.field("language") } == [nil, "de"])
    }

    func input(_ root: URL) -> ConversationAnalysisInput {
        .init(id: "test", audio: root.appendingPathComponent("audio.wav"), workDirectory: root.appendingPathComponent("work"), recordedAt: Date(), expectedSpeakers: nil, gaps: [], mainLanguage: "de", vocabulary: [], topics: [], people: [], previous: nil)
    }
    func answer() -> String {
        #"{"title":"Plan","overview":"Anna ruft an.","points":["Anrufen"],"tasks":[],"commitments":[],"topicID":"erfunden","newTopic":null,"names":[{"speakerID":"S1","name":"Anna","quote":"Ich bin Anna."},{"speakerID":"S1","name":"Erika","quote":"Ich bin Anna."}]}"#
    }
    @Test func summaryValidatesNamesTopicsAndCaches() async throws {
        let root = try ConversationCoreTests().root(); defer { try? FileManager.default.removeItem(at: root) }
        let answer = answer()
        let server = MockServer { request, _ in
            #expect(request.json?["model"] as? String == "openai/gpt-oss-120b")
            #expect(request.json?["reasoning_effort"] as? String == "low")
            #expect(request.json?["max_completion_tokens"] as? Int == 2000)
            return .json(200, ["choices": [["finish_reason":"stop", "message":["content":answer]]], "usage":["total_tokens":500]])
        }
        let summarizer = ConversationSummarizer(ledger: ConversationLedger.make(root: root), client: server.client())
        let transcript = ConversationTranscript(utterances: [.init(id: "u0", speakerID: "S1", start: 0, end: 3, text: "Ich bin Anna.")], languages: ["de"], model: "whisper-large-v3", createdAt: Date())
        var input = input(root)
        input.previous = Conversation(origin: .recording, trigger: .app, state: .done, title: "Mein Titel", titleOwner: .user)
        for _ in 0..<2 {
            let result = try await summarizer.summarize(input, transcript: transcript, speakers: [.init(id: "S1", speechSeconds: 3, colorIndex: 1)], apiKey: "test")
            #expect(result.title == "Mein Titel")
            #expect(result.speakers[0].suggestion?.name == "Anna")
            #expect(result.topic == TopicDecision.none)
        }
        #expect(server.requests.count == 1)
    }
    @Test func partialTranscriptOnRateLimit() async throws {
        let root = try ConversationCoreTests().root(); defer { try? FileManager.default.removeItem(at: root) }
        let writer = try WAVWriter(url: root.appendingPathComponent("audio.wav")); writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        let server = MockServer { request, _ in
            if request.path.hasSuffix("transcriptions") {
                return .json(200, ["words":[["word":"Hallo", "start":0, "end":0.1]], "segments":[], "duration":0.2])
            }
            return .json(429, ["error":["code":"rate_limit_exceeded"]], headers: ["Retry-After":"120"])
        }
        let ledger = ConversationLedger.make(root: root)
        let analyzer = ConversationAnalyzer(diarizer: FakeDiarizer(), transcriber: .init(ledger: ledger, client: server.client()), summarizer: .init(ledger: ledger, client: server.client()))
        for _ in 0..<2 {
            let outcome = await analyzer.analyze(input(root), apiKey: "test") { _ in }
            guard case .partial(let result, .waitingLimit, let retry, _) = outcome else { Issue.record("Teilstand fehlt"); return }
            #expect(result.transcript?.utterances.first?.text == "Hallo")
            #expect(result.stagesDone == [.speakers, .transcript])
            #expect((retry?.timeIntervalSinceNow ?? 0) > 100)
        }
        #expect(server.requests("transcriptions").count == 1)
    }
    @Test func thoughtProcessorNeverProcessesConversations() async throws {
        let h = try Harness.make()
        defer { StoreSupport.remove(h.root) }
        let item = Thought(id: "conversation-test", kind: ConversationKind.thoughtKind, trigger: .app, state: .captured)
        try await h.store.save(item)
        #expect(await h.processor.hasPendingWork() == false)
        await h.processor.kick(reason: "test")
        await h.processor.waitUntilIdle()
        await h.processor.reorganize(item.id)
        await h.processor.waitUntilIdle()
        #expect(await h.transcriber.calls == 0)
        #expect(await h.structurer.calls == 0)
        #expect(await h.store.thought(item.id)?.state == .captured)
    }
    @Test func rateHeadersPauseNextCall() throws {
        let limits = ConversationRateLimits()
        let response = HTTPURLResponse(url: URL(string:"https://example.invalid")!, statusCode: 200, httpVersion: nil, headerFields: ["x-ratelimit-remaining-tokens":"100", "x-ratelimit-reset-tokens":"1m2s"])!
        limits.receive(response, model: "m")
        #expect(throws: TokenLedger.Refusal.self) { try limits.check(model: "m", amount: 200) }
        try limits.check(model: "other", amount: 200)
    }
    @Test func linkedThoughtSurvivesReanalysisAndDeletion() async throws {
        let root = try ConversationCoreTests().root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root), thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts-root"))
        let (item, writer) = try await store.beginRecording(trigger: .app, at: Date())
        writer.append(StoreSupport.tone(seconds: 0.2)); let duration = writer.close()
        try await store.finishRecording(item.id, durationMs: duration, gaps: [])
        try await thoughts.save(Thought(id: item.id, kind: ConversationKind.thoughtKind, trigger: .app, state: .done, title: "Nutzertitel", titleOwner: .user, text: "Nutzertext", textOwner: .user))
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: FixedAnalyzer(), environment: .init(apiKey: { "test" }))
        await processor.kick(); await processor.waitUntilIdle()
        let thought = await thoughts.thought(item.id)
        #expect(thought?.title == "Nutzertitel"); #expect(thought?.text == "Nutzertext")
        #expect(thought?.tasks.isEmpty == true); #expect(thought?.kind == ConversationKind.thoughtKind)
        try await processor.delete(item.id)
        #expect(await thoughts.thought(item.id)?.deletedAt != nil)
        try await processor.restore(item.id)
        #expect(await thoughts.thought(item.id)?.deletedAt == nil)
        try await processor.purge(item.id)
        #expect(await thoughts.thought(item.id) == nil)
    }
    @Test func learningHookRunsBeforeAudioDeletion() async throws {
        let root = try ConversationCoreTests().root(); defer { try? FileManager.default.removeItem(at: root) }
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts-root")), profiles = VoiceProfileStore(root: root)
        await thoughts.setAudioReleaseHook(profiles.learningHook())
        let (thought, writer) = try await thoughts.beginCapture(trigger: .app, at: Date())
        writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        try await thoughts.update(thought.id) { $0.state = .captured }
        let source = ThoughtSource(text: "Hallo", sentences: [], model: "test", createdAt: Date(), languages: ["de"], audioSeconds: 0.2)
        try await thoughts.saveSourceOnce(thought.id, source)
        #expect(!FileSafety.exists(thoughts.wavURL(thought.id)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: profiles.learningDirectory.path).count == 1)
    }
}
private struct FixedAnalyzer: ConversationAnalyzing {
    func analyze(_ input: ConversationAnalysisInput, apiKey: String, progress: @escaping @Sendable (ConversationProgress) -> Void) async -> ConversationAnalysisOutcome {
        .done(.init(stagesDone: ConversationStage.allCases, speakers: [], speakerPrints: [:], transcript: nil, title: "KI-Titel", summary: .init(overview: "Überblick", points: ["Punkt"]), tasks: [.init(text: "Anna anrufen", quote: "Anna anrufen", dueHint: nil)], topic: TopicDecision.none, audioSeconds: 0.2, usage: nil, model: nil))
    }
}
