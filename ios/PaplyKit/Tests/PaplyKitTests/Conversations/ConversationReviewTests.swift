import Foundation
import Testing
@testable import PaplyKit

struct ConversationReviewTests {
    @Test func damagedEntryDoesNotBlockRecording() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        try await store.save(.init(id: "broken", origin: .recording, trigger: .app, state: .recording))
        let reopened = ConversationStore(root: root)
        #expect(try await reopened.all().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("quarantine").path).count == 1)
        let (item, writer) = try await reopened.beginRecording(trigger: .control, at: Date())
        _ = writer.close()
        _ = try await reopened.finishRecording(item.id, durationMs: 0, gaps: [])
        let (_, next) = try await reopened.beginRecording(trigger: .control, at: Date())
        _ = next.close()
    }

    @Test func failedImportLeavesNoConversation() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("bad.wav")
        try Data("kein Ton".utf8).write(to: source)
        let store = ConversationStore(root: root)
        await #expect(throws: (any Error).self) { try await store.importAudio(from: source, at: Date()) }
        #expect(try await ConversationStore(root: root).all().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".import-") })
    }

    @Test func reassignmentMatchesContentAndTimeNotIndex() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        try await store.save(.init(id: "test", origin: .recording, trigger: .app, state: .done, stagesDone: [.speakers]))
        let old = ConversationUtterance(id: "u0", speakerID: "S2", start: 10, end: 12, text: "Guten Morgen", speakerOwner: .user)
        var transcript = ConversationTranscript(utterances: [old], languages: ["de"], model: "test", createdAt: Date())
        try await store.saveTranscript(transcript, for: "test")
        transcript.utterances = [.init(id: "u0", speakerID: "S1", start: 0, end: 1, text: "Etwas anderes"), .init(id: "u7", speakerID: "S1", start: 10.2, end: 12.2, text: "Guten Morgen!")]
        try await store.saveTranscript(transcript, for: "test")
        let saved = try await store.transcript("test")!
        #expect(saved.utterances[0].speakerOwner == .ai)
        #expect(saved.utterances[1].speakerID == "S2")
        #expect(saved.utterances[1].text == "Guten Morgen!")
        #expect(saved.utterances[1].start == 10.2)
    }

    @Test func learningExpiresAndSwitchesOff() throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("learning")
        let gate = ConversationLearningGate(directory: directory)
        let source = root.appendingPathComponent("source.wav")
        try Data([1]).write(to: source)
        let hook = gate.hook { source in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("copy.wav"))
        }
        hook(source)
        #expect(!FileSafety.exists(directory))
        gate.configure(enabled: true); hook(source)
        #expect(FileSafety.exists(directory.appendingPathComponent("copy.wav")))
        gate.configure(enabled: true, now: Date().addingTimeInterval(8 * 86400))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        hook(source); gate.configure(enabled: false); hook(source)
        #expect(!FileSafety.exists(directory))
    }

    @Test func isolatedSoundsAndClearLexicalWords() {
        let d = Diarization(segments: [.init(start: 0, end: 1, cluster: 0), .init(start: 3, end: 4, cluster: 1)], centroids: [:], speechSeconds: [:], model: "test")
        let result = SpeakerAlignment.align(words: [.init(word: "Mhm.", start: 0, end: 0.3), .init(word: "Ja!", start: 3, end: 3.2)], diarization: d)
        #expect(result.utterances.count == 1)
        #expect(result.utterances[0].text == "Ja!")
        #expect(!result.utterances[0].uncertain)
    }

    @Test func summaryReassignmentsAreBoundedAndValidated() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let answer = #"{"title":"Plan","overview":"Plan","points":[],"tasks":[],"commitments":[],"topicID":null,"newTopic":null,"names":[],"reassignments":[{"utteranceID":"u0","speakerID":"S2"},{"utteranceID":"u1","speakerID":"S9"},{"utteranceID":"u2","speakerID":"S2"},{"utteranceID":"u3","speakerID":"S2"},{"utteranceID":"u4","speakerID":"S2"},{"utteranceID":"u5","speakerID":"S2"},{"utteranceID":"u6","speakerID":"S2"}]}"#
        let server = MockServer { request, _ in
            #expect(String(data: request.body, encoding: .utf8)?.contains("UNSICHER u2") == true)
            return .json(200, ["choices": [["finish_reason": "stop", "message": ["content": answer]]]])
        }
        var utterances = (0..<20).map { ConversationUtterance(id: "u\($0)", speakerID: "S1", start: Double($0), end: Double($0 + 1), text: "Ja", uncertain: true) }
        utterances[0].speakerOwner = .user
        utterances[3].uncertain = false
        let transcript = ConversationTranscript(utterances: utterances, languages: ["de"], model: "test", createdAt: Date())
        let summarizer = ConversationSummarizer(ledger: ConversationLedger.make(root: root), client: server.client())
        let result = try await summarizer.summarize(ConversationPipelineTests().input(root), transcript: transcript, speakers: [.init(id: "S1", speechSeconds: 10, colorIndex: 1), .init(id: "S2", speechSeconds: 10, colorIndex: 2)], apiKey: "test")
        #expect(result.transcript?.utterances.filter { $0.speakerID == "S2" }.map(\.id) == ["u2", "u4", "u5"])
        #expect(server.requests.count == 1)
    }
}

extension ConversationReviewTests {
    @Test func clampedWordTimesAndModelCache() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = ConversationPipelineTests().input(root)
        let writer = try WAVWriter(url: input.audio)
        writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        try FileSafety.createDirectory(input.workDirectory)
        let stale = Diarization(segments: [], centroids: [:], speechSeconds: [:], model: "old-fallback")
        try ThoughtJSON.encoder().encode(ConversationAnalyzer.CachedDiarization(stale)).write(to: input.workDirectory.appendingPathComponent("diarization.json"))
        let server = MockServer { request, _ in
            if request.path.hasSuffix("transcriptions") {
                return .json(200, ["words": [["word": "Hallo", "start": 0.0, "end": 2.0]], "segments": [], "duration": 0.2])
            }
            return .json(429, ["error": ["code": "rate_limit_exceeded"]], headers: ["Retry-After": "120"])
        }
        let ledger = ConversationLedger.make(root: root)
        let analyzer = ConversationAnalyzer(diarizer: FakeDiarizer(), transcriber: .init(ledger: ledger, client: server.client()), summarizer: .init(ledger: ledger, client: server.client()))
        let outcome = await analyzer.analyze(input, apiKey: "test") { _ in }
        guard case .partial(let result, _, _, _) = outcome else { Issue.record("Teilstand fehlt"); return }
        #expect(result.transcript?.utterances.first?.end == 0.2)
        let cache = try ThoughtJSON.decoder().decode(ConversationAnalyzer.CachedDiarization.self, from: Data(contentsOf: input.workDirectory.appendingPathComponent("diarization.json")))
        #expect(cache.model == "fake-v1")
        #expect(server.requests("transcriptions").count == 1)
    }

    @Test func wordMajoritySmoothsOnlyWeakEvidence() {
        let words = (0..<10).map { ConversationWord(word: "Wort", start: Double($0), end: Double($0) + 0.5) }
        var segments = (0..<8).map { Diarization.Segment(start: Double($0), end: Double($0) + 0.5, cluster: 0) }
        segments += [.init(start: 8, end: 8.5, cluster: 1), .init(start: 8, end: 8.4, cluster: 0), .init(start: 9, end: 9.5, cluster: 1)]
        let d = Diarization(segments: segments, centroids: [:], speechSeconds: [:], model: "test")
        let result = SpeakerAlignment.align(words: words, diarization: d)
        #expect(result.utterances.count == 2)
        #expect(result.utterances[0].end == 8.5)
        #expect(result.utterances[1].start == 9)
    }

    @Test func editingAndDeletionDoNotWaitForAnalysis() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        let analyzer = SuspendedConversationAnalyzer()
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: analyzer, environment: .init(apiKey: { "test" }))
        let (item, writer) = try await store.beginRecording(trigger: .app, at: Date())
        writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        _ = try await store.finishRecording(item.id, durationMs: 200, gaps: [])
        await processor.kick()
        await analyzer.waitForStart()
        try await processor.rename(item.id, title: "Eigener Titel")
        #expect(try await store.conversation(item.id)?.title == "Eigener Titel")
        try await processor.delete(item.id)
        await processor.waitUntilIdle()
        #expect(await analyzer.cancelled)
        #expect(try await store.conversation(item.id)?.deletedAt != nil)
    }
}

private actor SuspendedConversationAnalyzer: ConversationAnalyzing {
    var started = false
    var cancelled = false
    func waitForStart() async {
        while !started { await Task.yield() }
    }
    func analyze(_ input: ConversationAnalysisInput, apiKey: String, progress: @escaping @Sendable (ConversationProgress) -> Void) async -> ConversationAnalysisOutcome {
        started = true
        do { try await Task.sleep(for: .seconds(20)) } catch { cancelled = true }
        return .wait(.captured, retryAt: nil, message: "abgebrochen")
    }
}

extension ConversationReviewTests {
    @Test func failedFinishDoesNotLockOutNextRecording() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let (item, writer) = try await store.beginRecording(trigger: .app, at: Date())
        _ = writer.close()
        let metadata = store.directory(item.id).appendingPathComponent("conversation.json")
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) { try await store.finishRecording(item.id, durationMs: 0, gaps: []) }
        #expect(try await store.conversation(item.id)?.state == .needsAttention)
        let (_, next) = try await store.beginRecording(trigger: .control, at: Date())
        _ = next.close()
    }
}
