import Foundation
import Testing
@testable import PaplyKit

struct AudioExpiryReviewTests {
    @Test func waitingThoughtAudioExpiresButActiveCaptureSurvives() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ThoughtStore(root: root), start = Date(timeIntervalSince1970: 1000000)
        let (thought, writer) = try await store.beginCapture(trigger: .app, at: start)
        writer.append(Array(repeating: 0.1, count: 16000)); _ = writer.close()
        await store.housekeeping(now: start.addingTimeInterval(31 * 86400))
        #expect(FileSafety.exists(store.wavURL(thought.id)))
        _ = try await store.finishCapture(thought.id, durationMs: 1000)
        try await store.update(thought.id) { $0.state = .waitingKey }
        await store.housekeeping(now: start.addingTimeInterval(29 * 86400))
        #expect(FileSafety.exists(store.wavURL(thought.id)))
        await store.housekeeping(now: start.addingTimeInterval(31 * 86400))
        #expect(!FileSafety.exists(store.wavURL(thought.id)))
        #expect(await store.thought(thought.id)?.status.message == "Audio nach 30 Tagen entfernt · bitte erneut aufnehmen")
    }
    @Test func waitingConversationAudioExpiresButRecordingSurvives() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root), start = Date(timeIntervalSince1970: 1000000)
        let (item, writer) = try await store.beginRecording(trigger: .app, at: start)
        writer.append(Array(repeating: 0.1, count: 16000)); _ = writer.close()
        try await store.housekeeping(now: start.addingTimeInterval(31 * 86400))
        #expect(FileSafety.exists(store.wavURL(item.id)))
        _ = try await store.finishRecording(item.id, durationMs: 1000, gaps: [])
        try await store.update(item.id) { $0.state = .waitingKey }
        try await store.housekeeping(now: start.addingTimeInterval(29 * 86400))
        #expect(FileSafety.exists(store.wavURL(item.id)))
        try await store.housekeeping(now: start.addingTimeInterval(31 * 86400))
        #expect(!FileSafety.exists(store.wavURL(item.id)))
        #expect(try await store.conversation(item.id)?.status.message == "Audio nach 30 Tagen entfernt · bitte erneut aufnehmen")
    }
}
