import Foundation
import Testing
@testable import PaplyKit

struct ConversationSecondReviewTests {
    @Test func invalidDiarizationIsNeverReusable() {
        #expect(!ConversationAnalyzer.valid(.init(segments: [], centroids: [:], speechSeconds: [:], model: "test")))
        #expect(!ConversationAnalyzer.valid(.init(segments: [.init(start: 0, end: .nan, cluster: 0)], centroids: [:], speechSeconds: [:], model: "test")))
        #expect(!ConversationAnalyzer.valid(.init(segments: [.init(start: 0, end: 1, cluster: 0)], centroids: [0: [.nan]], speechSeconds: [:], model: "test")))
    }
    @Test func invalidFramesThrow() {
        var turns = NemotronTurnAccumulator()
        #expect(throws: (any Error).self) { try turns.append([], frames: 1) }
        #expect(throws: (any Error).self) { try turns.append([Float](repeating: .nan, count: 8), frames: 1) }
    }
    @Test func deletedTasksStayDeletedAcrossRenameAndRestart() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        var item = ConversationOwnerPauseTests().conversation()
        item.id = "deleted-task"
        item.speakers[0].personID = VoicePerson.ownerID
        item.speakers[0].nameSource = .user
        try await store.save(item)
        try await thoughts.save(.init(id: item.id, kind: ConversationKind.thoughtKind, trigger: .app, state: .done))
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: NoAnalysis(), environment: .init(apiKey: { "" }))
        try await processor.reconcileDeletionStates()
        #expect(await thoughts.thought(item.id)?.tasks.map(\.id) == ["a"])
        try await thoughts.update(item.id) { $0.tasks.removeAll() }
        try await processor.rename(item.id, title: "Neu")
        #expect(try await store.conversation(item.id)?.deletedTaskIDs == ["a"])
        try await processor.nameSpeaker(item.id, speakerID: "S2", as: .owner, rememberVoice: false)
        #expect(await thoughts.thought(item.id)?.tasks.map(\.id) == ["b"])
        let restarted = ConversationProcessor(store: ConversationStore(root: root), thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: NoAnalysis(), environment: .init(apiKey: { "" }))
        await restarted.kick()
        await restarted.waitUntilIdle()
        #expect(await thoughts.thought(item.id)?.tasks.map(\.id) == ["b"])
        try await restarted.takeTask(item.id, taskID: "c")
        #expect(await thoughts.thought(item.id)?.tasks.last?.owner == .user)
    }
    @Test func doneDeletesAudioAndRetryDoesNothing() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let (item, writer) = try await store.beginRecording(trigger: .app, at: Date())
        writer.append([Float](repeating: 0.1, count: 16000)); _ = writer.close()
        try await store.update(item.id) { $0.state = .done }
        try await store.compactAudio(item.id)
        #expect(try await store.audioURL(item.id) == nil)
        #expect(!FileSafety.exists(store.directory(item.id).appendingPathComponent("audio.m4a")))
        try FileSafety.createDirectory(store.workDirectory(item.id))
        let leftover = store.workDirectory(item.id).appendingPathComponent("chunk.flac")
        try Data([1, 2]).write(to: leftover)
        try await store.housekeeping()
        #expect(!FileSafety.exists(leftover))
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: NoAnalysis(), environment: .init(apiKey: { "" }))
        try await processor.retry(item.id)
        #expect(try await store.conversation(item.id)?.state == .done)
    }
    @Test func unchangedUpdateDoesNotBumpRevision() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        try await store.save(.init(id: "unchanged", origin: .recording, trigger: .app, state: .done))
        let before = try await store.conversation("unchanged")
        try await store.update("unchanged") { $0.state = .done }
        #expect(try await store.conversation("unchanged") == before)
    }
    @Test func recoveredPauseIsClosed() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let (item, writer) = try await store.beginRecording(trigger: .app, at: Date())
        writer.append([Float](repeating: 0.1, count: 16000)); _ = writer.close()
        try await store.update(item.id) { $0.gaps = [.init(at: 1, seconds: 0, reason: "pause", startedAt: Date().addingTimeInterval(-600))] }
        let recovered = try await ConversationStore(root: root).conversation(item.id)
        #expect(recovered?.gaps.first?.endedAt != nil)
        #expect((recovered?.gaps.first?.seconds ?? 0) >= 600)
    }
}
private struct NoAnalysis: ConversationAnalyzing {
    func analyze(_ input: ConversationAnalysisInput, apiKey: String, progress: @escaping @Sendable (ConversationProgress) -> Void) async -> ConversationAnalysisOutcome { .empty }
}

extension ConversationSecondReviewTests {
    @Test func migrationNeverTurnsUserTasksIntoCommitments() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        var item = ConversationOwnerPauseTests().conversation()
        item.id = "migration-user"
        item.summary?.taskCatalogVersion = nil
        try await store.save(item)
        var thought = Thought(id: item.id, kind: ConversationKind.thoughtKind, trigger: .app, state: .done)
        thought.tasks = [.init(id: "manual", text: "Meine eigene Aufgabe", owner: .user)]
        try await thoughts.save(thought)
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: NoAnalysis(), environment: .init(apiKey: { "" }))
        await processor.kick(); await processor.waitUntilIdle()
        #expect(try await store.conversation(item.id)?.summary?.commitments.contains { $0.id == "manual" } == false)
        #expect(await thoughts.thought(item.id)?.tasks.first?.owner == .user)
        let settled = try await store.conversation(item.id)
        await processor.kick(); await processor.waitUntilIdle()
        #expect(try await store.conversation(item.id) == settled)
    }
    @Test func mergePreservesTargetName() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        var item = ConversationOwnerPauseTests().conversation()
        item.id = "merge-target"
        item.speakers[0].personID = VoicePerson.ownerID
        item.speakers[0].nameSource = .user
        item.speakers[1].name = "Anna"
        item.speakers[1].nameSource = .user
        try await store.save(item)
        try await thoughts.save(.init(id: item.id, kind: ConversationKind.thoughtKind, trigger: .app, state: .done))
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: NoAnalysis(), environment: .init(apiKey: { "" }))
        try await processor.mergeSpeakers(item.id, from: "S1", into: "S2")
        #expect(try await store.conversation(item.id)?.speakers.first?.name == "Anna")
    }
    @Test func provisionalSpeakerCannotBecomeOwner() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        var item = ConversationOwnerPauseTests().conversation()
        item.id = "provisional"
        item.stagesDone = [.transcript]
        try await store.save(item)
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: NoAnalysis(), environment: .init(apiKey: { "" }))
        await #expect(throws: ThoughtStoreError.notFound) {
            try await processor.nameSpeaker(item.id, speakerID: "S1", as: .owner, rememberVoice: false)
        }
        var transcript = ConversationTranscript(utterances: [.init(id: "u", speakerID: "S1", start: 0, end: 1, text: "Hallo", speakerOwner: .user)], languages: ["de"], model: "test", createdAt: Date())
        try await store.saveTranscript(transcript, for: item.id)
        transcript.utterances[0].speakerID = "S2"
        transcript.utterances[0].speakerOwner = .ai
        try await store.saveTranscript(transcript, for: item.id)
        #expect(try await store.transcript(item.id)?.utterances.first?.speakerID == "S2")
    }
}
