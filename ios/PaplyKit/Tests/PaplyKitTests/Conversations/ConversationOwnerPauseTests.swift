import Foundation
import Testing
@testable import PaplyKit

struct ConversationOwnerPauseTests {
    func conversation() -> Conversation {
        Conversation(origin: .recording, trigger: .app, state: .done, stagesDone: [.speakers],
            summary: .init(overview: "[S1] plant", points: [], commitments: [
                .init(id: "a", speakerID: "S1", text: "Anrufen"),
                .init(id: "b", speakerID: "S2", text: "Schreiben"),
                .init(id: "c", speakerID: "shared", text: "Abstimmen")]),
            speakers: [.init(id: "S1", speechSeconds: 10, colorIndex: 0), .init(id: "S2", speechSeconds: 5, colorIndex: 1)])
    }
    @Test func summaryRetainsEveryPersonWithoutOwner() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let answer = #"{"title":"Plan","overview":"Plan","points":[],"tasks":[{"text":"Anrufen","quote":"Ich rufe an.","dueHint":null,"speakerID":"S1"},{"text":"Schreiben","quote":"Ich schreibe.","dueHint":null,"speakerID":"S2"},{"text":"Abstimmen","quote":"Wir stimmen ab.","dueHint":null,"speakerID":null}],"commitments":[],"topicID":null,"newTopic":null,"names":[]}"#
        let server = MockServer { _, _ in
            .json(200, ["choices": [["finish_reason": "stop", "message": ["content": answer]]], "usage": ["total_tokens": 500]])
        }
        let summarizer = ConversationSummarizer(ledger: ConversationLedger.make(root: root), client: server.client())
        let transcript = ConversationTranscript(utterances: [.init(id: "u0", speakerID: "S1", start: 0, end: 4, text: "Ich rufe an. Ich schreibe. Wir stimmen ab.")], languages: ["de"], model: "test", createdAt: Date())
        let result = try await summarizer.summarize(ConversationPipelineTests().input(root), transcript: transcript, speakers: conversation().speakers, apiKey: "test")
        #expect(result.summary?.commitments.map(\.speakerID) == ["S1", "S2", "shared"])
        #expect(result.tasks.isEmpty)
    }
    @Test func requiresSecureOwner() {
        var item = conversation()
        #expect(ConversationTasks.derive(item, preserving: []).isEmpty)
        item.speakers[0].personID = VoicePerson.ownerID
        #expect(ConversationTasks.derive(item, preserving: []).isEmpty)
        item.speakers[0].nameSource = .owner
        #expect(ConversationTasks.derive(item, preserving: []).map(\.id) == ["a"])
        item.speakers[0].nameSource = .user
        #expect(ConversationTasks.derive(item, preserving: []).count == 1)
    }
    @Test func preservesCheckedAndEditedWithoutDuplicates() {
        var item = conversation()
        item.speakers[0].nameSource = .owner
        let existing = [ThoughtTask(id: "a", text: "Schon angerufen", done: true, owner: .ai),
                        ThoughtTask(id: "c", text: "Selbst geändert", owner: .user)]
        #expect(ConversationTasks.derive(item, preserving: existing) == existing)
        item.speakers[0].nameSource = .none
        #expect(ConversationTasks.derive(item, preserving: existing) == existing)
    }
    @Test func oldSummaryAndGapDecode() throws {
        let summary = try JSONDecoder().decode(ConversationSummary.self, from: Data(#"{"overview":"Alt","points":[],"commitments":[{"id":"c","speakerID":"S2","text":"Anrufen"}]}"#.utf8))
        #expect(summary.taskCatalogVersion == nil)
        #expect(summary.commitments.first?.speakerID == "S2")
        let gap = try JSONDecoder().decode(ConversationGap.self, from: Data(#"{"at":12,"seconds":180,"reason":"interruption"}"#.utf8))
        #expect(gap.startedAt == nil)
        #expect(gap.label == "Anruf · 3 Min.")
    }
    @Test func gapLinesKeepOrderAndTrailingPause() {
        let utterances = [ConversationUtterance(id: "u0", speakerID: "S1", start: 0, end: 2, text: "Vorher"),
                          ConversationUtterance(id: "u1", speakerID: "S1", start: 2, end: 4, text: "Nachher")]
        let lines = ConversationText.transcriptLines(utterances, gaps: [.init(at: 2, seconds: 720, reason: "pause"), .init(at: 4, seconds: 180, reason: "call")]) { $0.text }
        #expect(lines == ["Vorher", "Pause · 12 Min.", "Nachher", "Anruf · 3 Min."])
        #expect(ConversationText.render("[S2]", speakers: []) == "Person 2")
    }
    @Test func migrationAndMergeKeepAllTasks() async throws {
        let root = try ConversationCoreTests().root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(root: root)
        let thoughts = try ThoughtStore(root: root.appendingPathComponent("thoughts"))
        let (recording, writer) = try await store.beginRecording(trigger: .app, at: Date())
        _ = writer.close()
        var item = conversation()
        item.summary?.taskCatalogVersion = nil
        let fixture = item
        try await store.update(recording.id) { value in
            value.summary = fixture.summary; value.speakers = fixture.speakers; value.state = .done; value.stagesDone = [.speakers]
        }
        var thought = Thought(id: recording.id, kind: ConversationKind.thoughtKind, trigger: .app, state: .done)
        thought.tasks = [.init(id: "old", text: "Alte Aufgabe", owner: .ai)]
        try await thoughts.save(thought)
        let processor = ConversationProcessor(store: store, thoughts: thoughts, profiles: VoiceProfileStore(root: root), analyzer: UnusedAnalyzer(), environment: .init(apiKey: { "" }))
        try await processor.reconcileDeletionStates()
        #expect(await thoughts.thought(recording.id)?.tasks.isEmpty == true)
        #expect(try await store.conversation(recording.id)?.summary?.commitments.count == 4)
        try await processor.nameSpeaker(recording.id, speakerID: "S1", as: .owner, rememberVoice: false)
        #expect(await thoughts.thought(recording.id)?.tasks.count == 1)
        try await processor.mergeSpeakers(recording.id, from: "S1", into: "S2")
        #expect(await thoughts.thought(recording.id)?.tasks.count == 2)
        try await processor.reconcileDeletionStates()
        #expect(try await store.conversation(recording.id)?.summary?.commitments.count == 4)
    }
}
private struct UnusedAnalyzer: ConversationAnalyzing {
    func analyze(_ input: ConversationAnalysisInput, apiKey: String, progress: @escaping @Sendable (ConversationProgress) -> Void) async -> ConversationAnalysisOutcome { .empty }
}
