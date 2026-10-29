import Observation
import PaplyKit
import UIKit

@MainActor @Observable
final class ConversationsModel {
    static let shared = ConversationsModel()
    private(set) var conversations: [Conversation] = []
    private(set) var people: [VoicePerson] = []
    private(set) var transcripts: [String: [ConversationUtterance]] = [:]
    private(set) var audioIDs: Set<String> = []
    var error: String?
    @ObservationIgnored private var loaded: Set<String> = []
    private(set) var learnedThoughtCount: Int?

    init() {
        Task {
            await reload()
            for await _ in ConversationsEnvironment.store.changes { await reload() }
        }
        Task {
            for await _ in ConversationsEnvironment.processor.events { await reload() }
        }
    }
    func reload() async {
        do {
            conversations = try await ConversationsEnvironment.store.all()
            people = try await ConversationsEnvironment.profiles.people()
            let learning = try await ConversationsEnvironment.profiles.learningStatus()
            learnedThoughtCount = learning.learnedThoughts > 0 ? learning.learnedThoughts : nil
            for id in loaded { await loadTranscript(id) }
        } catch { self.error = "Gespräche konnten nicht geladen werden." }
    }
    func display(_ id: String, thoughts: ThoughtsModel) -> ConversationDisplay? {
        guard var conversation = conversations.first(where: { $0.id == id }) else { return nil }
        if !conversation.stagesDone.contains(.speakers) { conversation.speakers = [] }
        let thought = thoughts.thought(id)
        return ConversationDisplay(
            conversation: conversation, topic: thoughts.topic(thought?.topicId)?.title, tasks: thought?.tasks ?? [])
    }
    func loadTranscript(_ id: String) async {
        loaded.insert(id)
        transcripts[id] = (try? await ConversationsEnvironment.store.transcript(id)?.utterances) ?? []
        if (try? await ConversationsEnvironment.store.audioURL(id)) != nil {
            audioIDs.insert(id)
        } else {
            audioIDs.remove(id)
        }
    }
    func perform(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await action()
                await reload()
            } catch {
                self.error = "Das hat nicht geklappt. Bitte erneut versuchen."
                Diag.log("conversation.action.failed", ["code": .i((error as NSError).code)])
            }
        }
    }
    func choose(_ choice: ConversationSpeakerChoice, speaker: ConversationSpeaker, id: String) {
        perform {
            let editing = ConversationsEnvironment.editing
            switch choice {
            case .merge(let target): try await editing.mergeSpeakers(id, from: speaker.id, into: target)
            case .person(let person):
                try await editing.nameSpeaker(
                    id, speakerID: speaker.id, as: person == VoicePerson.ownerID ? .owner : .person(person),
                    rememberVoice: true)
            case .newName(let name):
                try await editing.nameSpeaker(id, speakerID: speaker.id, as: .newPerson(name), rememberVoice: true)
            case .suggestion(let suggestion):
                let identity: SpeakerIdentity =
                    suggestion.personID.map { $0 == VoicePerson.ownerID ? .owner : .person($0) }
                    ?? .newPerson(suggestion.name)
                try await editing.nameSpeaker(id, speakerID: speaker.id, as: identity, rememberVoice: true)
            case .doNotRemember:
                let identity: SpeakerIdentity
                if speaker.isOwner {
                    identity = .owner
                } else if let person = speaker.personID {
                    identity = .person(person)
                } else if let name = speaker.name {
                    identity = .newPerson(name)
                } else {
                    throw ThoughtStoreError.unavailable
                }
                try await editing.nameSpeaker(id, speakerID: speaker.id, as: identity, rememberVoice: false)
            }
        }
    }
    func takeTask(_ id: String, taskID: String) {
        perform { try await ConversationsEnvironment.processor.takeTask(id, taskID: taskID) }
    }
    func shareText(_ item: ConversationDisplay) -> String {
        let summary = item.conversation.summary
        var parts = [item.conversation.title ?? "Gespräch", summary?.overview ?? ""]
        parts += summary?.points.map { "• " + $0 } ?? []
        parts += summary?.commitments.map { task in
            let linked = item.tasks.first { $0.id == task.id }
            let person = task.speakerID == "shared" ? "Gemeinsam / unklar" : "[\(task.speakerID)]"
            return (linked?.done == true ? "☑ " : "☐ ") + person + ": " + (linked?.text ?? task.text)
        } ?? []
        let catalogIDs = Set(summary?.commitments.map(\.id) ?? [])
        parts += item.tasks.filter { !catalogIDs.contains($0.id) }.map { ($0.done ? "☑ " : "☐ ") + $0.text }
        return ConversationText.render(parts.joined(separator: "\n\n"), speakers: item.conversation.speakers)
    }
    func copyTranscript(_ item: ConversationDisplay) {
        UIPasteboard.general.string = ConversationText.transcriptLines(transcripts[item.id] ?? [], gaps: item.conversation.gaps) { utterance in
            ConversationText.render("[\(utterance.speakerID)]: \(utterance.text)", speakers: item.conversation.speakers)
        }.joined(separator: "\n\n")
    }
    func unloadTranscript(_ id: String) {
        loaded.remove(id)
        transcripts.removeValue(forKey: id)
    }
}
