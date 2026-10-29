import Foundation
import PaplyKit

/// Echte Gesprächsablage plus sofortiger verknüpfter Gedanke, auch für verworfene Aufnahmen.
struct ConversationRecordingBridge: ConversationRecordingStore {
    let store: ConversationStore
    let thoughts: ThoughtStore
    private func link(_ item: Conversation) async throws {
        if await thoughts.thought(item.id) == nil {
            try await thoughts.save(
                Thought(
                    id: item.id, kind: ConversationKind.thoughtKind,
                    createdAt: item.createdAt, durationMs: item.durationMs, trigger: item.trigger, state: .done))
        }
    }
    func beginRecording(trigger: ThoughtTrigger, at: Date) async throws -> (
        conversation: Conversation, audio: WAVWriter
    ) {
        let result = try await store.beginRecording(trigger: trigger, at: at)
        do { try await link(result.conversation) } catch {
            _ = result.audio.close()
            await store.discardRecording(result.conversation.id)
            throw error
        }
        return result
    }
    func finishRecording(_ id: String, durationMs: Int, gaps: [ConversationGap]) async throws -> Conversation? {
        try await store.finishRecording(id, durationMs: durationMs, gaps: gaps)
    }
    func discardRecording(_ id: String) async {
        if let item = try? await store.conversation(id), item.state == .recording,
            let duration = try? WAVWriter.repair(store.wavURL(id))
        {
            _ = try? await store.finishRecording(id, durationMs: duration, gaps: item.gaps)
        }
        await store.discardRecording(id)
        try? await thoughts.delete(id)
    }
    func importAudio(from url: URL, at: Date) async throws -> Conversation {
        let item = try await store.importAudio(from: url, at: at)
        try await link(item)
        return item
    }
}
