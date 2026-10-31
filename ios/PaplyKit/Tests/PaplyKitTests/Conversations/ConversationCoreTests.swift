import Foundation
import AVFoundation
import Testing
@testable import PaplyKit

struct FakeDiarizer: SpeakerDiarizing {
    var embeddingModel: String { "fake-v1" }
    var result = Diarization(segments: [.init(start: 0, end: 10, cluster: 0)], centroids: [0: [1, 0]], speechSeconds: [0: 10], model: "fake-v1")
    var print: VoicePrint? = .init(vector: [1, 0], model: "fake-v1", seconds: 10, source: .thought)
    func diarize(audio: URL, expectedSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization { progress(1); return result }
    func voiceprint(audio: URL) async throws -> VoicePrint? { print }
}

struct ConversationCoreTests {
    func root() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/paply-gsp-k-tests-" + UUID().uuidString)
        try FileSafety.createDirectory(url); return url
    }
    @Test func recordingRecoveryAndRevision() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let (item, writer) = try await store.beginRecording(trigger: .app, at: Date())
        writer.append(Array(repeating: 0.1, count: 32000)); _ = writer.close()
        #expect(try await store.conversation(item.id)?.state == .recording)
        let reopened = ConversationStore(root: root)
        #expect(try await reopened.conversation(item.id)?.state == .captured)
        #expect(try await reopened.conversation(item.id)?.durationMs == 2000)
        let before = try await reopened.conversation(item.id)!.rev
        try await reopened.update(item.id) { $0.title = "Eigener Titel"; $0.id = "falsch" }
        #expect(try await reopened.conversation(item.id)?.rev == before + 1)
        #expect(try await reopened.conversation(item.id)?.id == item.id)
        try await reopened.delete(item.id)
        #expect(try await reopened.conversation(item.id)?.deletedAt != nil)
        try await reopened.restore(item.id)
        #expect(try await reopened.conversation(item.id)?.deletedAt == nil)
    }
    @Test func invalidPathRejected() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        await #expect(throws: ThoughtStoreError.invalidID) { try await store.save(Conversation(id: "../bad", origin: .recording, trigger: .app, state: .captured)) }
    }
    @Test func transcriptKeepsUserAssignment() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root), id = "test"
        try await store.save(.init(id: id, origin: .recording, trigger: .app, state: .captured, stagesDone: [.speakers]))
        var transcript = ConversationTranscript(utterances: [.init(id: "u0", speakerID: "S2", start: 0, end: 1, text: "Hallo", speakerOwner: .user)], languages: ["de"], model: "test", createdAt: Date())
        try await store.saveTranscript(transcript, for: id)
        transcript.utterances[0].speakerID = "S1"; transcript.utterances[0].speakerOwner = .ai
        try await store.saveTranscript(transcript, for: id)
        #expect(try await store.transcript(id)?.utterances[0].speakerID == "S2")
    }
    @Test func importAndDeleteAfterDone() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.wav"), writer = try WAVWriter(url: root.appendingPathComponent("source.wav"))
        writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        let store = ConversationStore(root: root)
        let item: Conversation
        do { item = try await store.importAudio(from: source, at: Date()) } catch { Issue.record("Import: \(error)"); return }
        #expect(item.durationMs == 200); #expect(item.expectedSpeakers == nil)
        try await store.update(item.id) { $0.state = .done }
        do { try await store.compactAudio(item.id) } catch { Issue.record("Komprimierung: \(error)"); return }
        #expect(try await store.audioURL(item.id) == nil)
        #expect(!FileSafety.exists(store.wavURL(item.id)))
        try await store.housekeeping(now: Date().addingTimeInterval(31 * 86400))
        #expect(try await store.audioURL(item.id) == nil)
    }
    @Test func stereoImportResamplesAndRetainsOriginal() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("stereo.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: source, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        buffer.frameLength = 4800
        for i in 0..<4800 {
            buffer.floatChannelData![0][i] = Float(0.3 * sin(Double(i) * 0.03))
            buffer.floatChannelData![1][i] = Float(0.3 * sin(Double(i) * 0.07))
        }
        try file.write(from: buffer); file.close()
        let store = ConversationStore(root: root)
        let item = try await store.importAudio(from: source, at: Date())
        #expect(abs(item.durationMs - 100) < 5)
        #expect(item.expectedSpeakers == 2)
        #expect(FileSafety.exists(store.directory(item.id).appendingPathComponent("import-original.wav")))
    }
    @Test func profileLimitAndModelIsolation() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceProfileStore(root: root)
        let person = try await store.create(name: "Anna")
        for i in 0..<25 { try await store.add(.init(vector: [1, Float(i) / 100], model: "a", seconds: 10, source: .conversation), to: person.id) }
        let saved = try await store.people().first { $0.id == person.id }!
        #expect(saved.prints.count == 20)
        #expect(SpeakerThresholds.score(.init(vector: [1,0], model: "b", seconds: 10, source: .conversation), against: saved) == 0)
        try await store.rename(person.id, name: "Anja")
        #expect(try await store.people().first { $0.id == person.id }?.name == "Anja")
        try await store.forgetVoice(person.id)
        #expect(try await store.people().first { $0.id == person.id }?.prints.isEmpty == true)
    }
    @Test func learningRejectsOutlierAndRemovesCopies() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("audio.wav"), writer = try WAVWriter(url: root.appendingPathComponent("audio.wav"))
        writer.append([0.1]); _ = writer.close()
        let store = VoiceProfileStore(root: root)
        try await store.add(.init(vector: [1,0], model: "fake-v1", seconds: 10, source: .enrollment), to: VoicePerson.ownerID)
        for _ in 0..<12 { store.learningHook()(source) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.learningDirectory.path).count == 10)
        try await store.processLearningQueue(diarizer: FakeDiarizer(print: .init(vector: [0,1], model: "fake-v1", seconds: 10, source: .thought)))
        #expect(try await store.people().first { $0.isOwner }?.prints.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.learningDirectory.path).isEmpty)
    }
    @Test func clearMidSentenceSwitchSurvives() {
        let d = Diarization(segments: [.init(start: 0, end: 2, cluster: 0), .init(start: 2, end: 4, cluster: 1)], centroids: [0:[1,0], 1:[0,1]], speechSeconds: [0:2,1:2], model: "m")
        let result = SpeakerAlignment.align(words: [.init(word: "Ich", start: 0, end: 1), .init(word: "Nein!", start: 2, end: 3)], diarization: d)
        #expect(result.utterances.map(\.speakerID) == ["S1", "S2"])
        #expect(result.utterances.map(\.text) == ["Ich", "Nein!"])
    }
    @Test func overlapIsUncertain() {
        let d = Diarization(segments: [.init(start: 0, end: 3, cluster: 0), .init(start: 1, end: 2, cluster: 1)], centroids: [0:[1,0],1:[0,1]], speechSeconds: [0:3,1:1], model: "m")
        let result = SpeakerAlignment.align(words: [.init(word: "Ja", start: 1.2, end: 1.5)], diarization: d)
        #expect(result.utterances.first?.uncertain == true)
    }
    @Test func fragmentsMergeAndGapsSplit() {
        let d = Diarization(segments: [.init(start: 0, end: 2, cluster: 0), .init(start: 2, end: 3, cluster: 1)], centroids: [0:[1,0],1:[0.99,0.01]], speechSeconds: [0:2,1:1], model: "m")
        let result = SpeakerAlignment.align(words: [.init(word: "Hallo", start: 0, end: 1), .init(word: "Welt", start: 2, end: 3)], diarization: d, gaps: [.init(at: 1.5, seconds: 30, reason: "call")])
        #expect(result.speakers.count == 1); #expect(result.utterances.count == 2)
        #expect(result.utterances.last?.start == 2)
    }
    @Test func globalMatchingAndOwnerColor() {
        let speakers = [ConversationSpeaker(id: "S1", speechSeconds: 5, colorIndex: 1), ConversationSpeaker(id: "S2", speechSeconds: 4, colorIndex: 2)]
        let prints = ["S1": VoicePrint(vector: [1,0], model: "m", seconds: 5, source: .conversation), "S2": VoicePrint(vector: [0.8,0.6], model: "m", seconds: 4, source: .conversation)]
        let people = [VoicePerson(id: "owner", name: "", prints: [.init(vector: [1,0], model: "m", seconds: 10, source: .enrollment)]), VoicePerson(id: "other", name: "Anna", prints: [.init(vector: [0.9,-0.43589], model: "m", seconds: 10, source: .enrollment)])]
        let result = SpeakerIdentifier.identify(speakers, prints: prints, people: people)
        #expect(result[0].personID == nil)
        #expect(result[0].suggestion?.personID == "other")
        #expect(result[1].suggestion?.personID == "owner")
        let owner = SpeakerIdentifier.identify([speakers[0]], prints: prints, people: [people[0]])
        #expect(owner[0].colorIndex == 0); #expect(owner[0].nameSource == .owner)
    }
    @Test func cosineRejectsInvalidVectors() {
        #expect(SpeakerThresholds.cosine([0,0], [1,0]) == 0)
        #expect(SpeakerThresholds.cosine([.nan,0], [1,0]) == 0)
        #expect(SpeakerThresholds.cosine([1], [1,0]) == 0)
    }
    @Test func whisperContractAndCache() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let server = MockServer { request, _ in
            #expect(request.field("model") == "whisper-large-v3")
            #expect(request.field("response_format") == "verbose_json")
            #expect(request.bodyText.contains("timestamp_granularities[]"))
            #expect(request.field("language") == nil)
            return .json(200, ["words": [["word":"Hallo", "start":0, "end":0.1]], "segments": [["text":"Hallo", "start":0, "end":0.1]], "language":"de", "duration":0.2])
        }
        let audio = root.appendingPathComponent("audio.wav"), writer = try WAVWriter(url: root.appendingPathComponent("audio.wav"))
        writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        let transcriber = ConversationTranscriber(ledger: ConversationLedger.make(root: root), client: server.client())
        for _ in 0..<2 {
            let result = try await transcriber.transcribe(audio: audio, workDirectory: root.appendingPathComponent("work"), apiKey: "test", mainLanguage: "de", vocabulary: [])
            #expect(result.words.count == 1)
        }
        #expect(server.requests.count == 1)
    }
    @Test func analyzerKeepsSpeakersWhenKeyMissing() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let analyzer = ConversationAnalyzer(diarizer: FakeDiarizer(), ledger: ConversationLedger.make(root: root))
        let input = ConversationAnalysisInput(id: "test", audio: root.appendingPathComponent("audio.wav"), workDirectory: root, recordedAt: Date(), expectedSpeakers: nil, gaps: [], mainLanguage: "de", vocabulary: [], topics: [], people: [], previous: nil)
        let outcome = await analyzer.analyze(input, apiKey: "") { _ in }
        guard case .partial(let result, .waitingKey, _, _) = outcome else { Issue.record("Teilstand fehlt"); return }
        #expect(result.stagesDone == [.speakers]); #expect(result.speakers.count == 1)
    }
}
