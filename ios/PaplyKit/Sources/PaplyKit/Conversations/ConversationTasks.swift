import Foundation

/// Einzige Ableitung für Auswertung und spätere Sprecherkorrekturen.
public enum ConversationTasks {
    public static func derive(_ conversation: Conversation, preserving existing: [ThoughtTask], now: Date = Date()) -> [ThoughtTask] {
        let owners = Set(conversation.speakers.filter(\.isOwner).map(\.id))
        let kept = existing.filter { $0.owner == .user || $0.done }
        guard !owners.isEmpty else { return kept }
        let drafts = (conversation.summary?.commitments ?? []).filter {
            owners.contains($0.speakerID) || $0.speakerID == "shared"
        }.map { task in
            let due = DueDate.resolved(task.dueHint, reference: conversation.createdAt, now: now)
            return ThoughtTask(id: task.id, text: ConversationText.render(task.text, speakers: conversation.speakers),
                quote: task.quote, dueHint: task.dueHint, dueAt: due?.date, dueHasTime: due?.hasTime, owner: .ai)
        }
        return kept + drafts.filter { draft in !kept.contains { $0.id == draft.id || RawText.sameTask($0, draft) } }
    }
}

extension ConversationGap {
    public var label: String {
        let title = reason == "call" || reason == "interruption" ? "Anruf" : "Pause"
        let duration = seconds < 60 ? "\(max(1, Int(seconds))) Sek." : "\(Int(seconds / 60)) Min."
        guard let startedAt, let endedAt else { return "\(title) · \(duration)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(title) · \(duration) (\(formatter.string(from: startedAt))–\(formatter.string(from: endedAt)))"
    }
}

extension ConversationText {
    /// Lücken liegen auf der komprimierten Ton-Zeitachse, Uhrzeiten auf der Wanduhr.
    public static func transcriptLines(_ utterances: [ConversationUtterance], gaps: [ConversationGap], line: (ConversationUtterance) -> String) -> [String] {
        var result: [String] = []
        var pending = gaps.sorted { $0.at < $1.at }
        for utterance in utterances {
            while let gap = pending.first, gap.at <= utterance.start {
                result.append(gap.label); pending.removeFirst()
            }
            result.append(line(utterance))
            // Auch eine Lücke innerhalb eines zusammengefassten Beitrags sichtbar halten.
            while let gap = pending.first, gap.at < utterance.end {
                result.append(gap.label); pending.removeFirst()
            }
        }
        return result + pending.map(\.label)
    }
}
