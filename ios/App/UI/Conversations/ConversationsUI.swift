import PaplyKit
import SwiftUI

/// Ausschließlich Anzeigewerte des verknüpften Gedankens. Keine Speicherabhängigkeit.
struct ConversationDisplay: Identifiable {
    var conversation: Conversation
    var topic: String? = nil
    var tasks: [ThoughtTask] = []
    var id: String { conversation.id }
}

enum ConversationTint {
    static let blue = Color(uiColor: Brand.conversationBlue)
    static let turquoise = Color(uiColor: Brand.conversationTurquoise)
    static var fill: LinearGradient {
        LinearGradient(colors: [blue, turquoise], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let speakers: [Color] = [0x83BCE8, 0xD8AD85, 0xB6A2DF, 0xE49DA8, 0x99C9C0, 0xD8CE8D, 0xB4BED6, 0xCFABE0]
        .map { Color(uiColor: UIColor(hex: $0)) }
    static func color(_ speaker: ConversationSpeaker) -> Color {
        speaker.isOwner ? .paplyGreenBright : speakers[((speaker.colorIndex % 8) + 8) % 8]
    }
    static func name(_ speaker: ConversationSpeaker) -> String {
        if speaker.isOwner { return "Ich" }
        return speaker.name ?? "Sprecher \(speaker.id.dropFirst())"
    }
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
    static func duration(_ ms: Int) -> String { ms < 60_000 ? "\(max(0, ms / 1000)) Sek" : "\(ms / 60_000) Min" }
}

struct ConversationSpeakerLabel: View {
    let speaker: ConversationSpeaker
    var showSuggestion = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Circle().fill(ConversationTint.color(speaker)).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(showSuggestion && speaker.name == nil && !speaker.isOwner
                 ? speaker.suggestion.map { "\($0.name) ?" } ?? ConversationTint.name(speaker)
                 : ConversationTint.name(speaker))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ConversationTint.color(speaker))
    }
}

extension Conversation {
    var presentationStatus: String? {
        switch state {
        case .done: return nil
        case .recording: return "Aufnahme läuft"
        case .captured: return "Wartet auf Auswertung"
        case .analyzing:
            switch progress?.stage {
            case .speakers: return "Wer spricht …"
            case .transcript: return "Text wird geschrieben …"
            case .summary: return "Zusammenfassung entsteht …"
            case nil: return "Wird ausgewertet …"
            }
        case .waitingNetwork: return "Wartet auf Internet"
        case .waitingKey: return "Groq-Schlüssel fehlt"
        case .waitingLimit: return "Wartet auf freies Kontingent"
        case .waitingBudget: return "Für heute ist das Kontingent aufgebraucht"
        case .needsAttention: return "Auswertung nicht gelungen – der Ton ist gesichert"
        case .empty: return "Nichts Gesprochenes erkannt"
        }
    }
}

struct ConversationStatusBand: View {
    let conversation: Conversation
    let onRetry: () -> Void
    var body: some View {
        if let text = conversation.presentationStatus {
            VStack(alignment: .leading, spacing: 8) {
                Label(text, systemImage: conversation.state == .needsAttention ? "exclamationmark.circle" : "waveform")
                    .shimmer(conversation.state == .analyzing)
                if conversation.state == .analyzing, let fraction = conversation.progress?.fraction {
                    ProgressView(value: min(1, max(0, fraction))).tint(ConversationTint.blue)
                }
                if !conversation.stagesDone.isEmpty { Text("Fertige Teile stehen schon hier.").font(.caption) }
                if conversation.state != .analyzing && conversation.state != .recording {
                    Button("Erneut versuchen", action: onRetry).frame(minHeight: 44)
                }
            }
            .font(.subheadline).foregroundStyle(Color.paplySecondaryText)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).paplyCard()
        }
    }
}

/// Bereit für Thought.kind == "conversation"; Navigation entscheidet der Aufrufer.
struct ConversationThoughtRow: View {
    let item: ConversationDisplay
    let time: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(item.conversation.title ?? "Neues Gespräch").font(.headline)
                    .shimmer(item.conversation.state == .analyzing)
            } icon: { Image(systemName: "person.2.wave.2").foregroundStyle(ConversationTint.blue) }
            Text("\(time) · \(ConversationTint.duration(item.conversation.durationMs))")
                .font(.subheadline).foregroundStyle(Color.paplySecondaryText)
            ConversationChipLayout(spacing: 6) { speakerNames }
            .font(.caption)
            if let topic = item.topic { Label(topic, systemImage: "tag").font(.caption).foregroundStyle(ConversationTint.turquoise) }
            if !item.tasks.isEmpty {
                Label("\(item.tasks.filter { !$0.done }.count) offene Aufgaben", systemImage: "checklist")
                    .font(.caption).foregroundStyle(Color.paplySecondaryText)
            }
            if let status = item.conversation.presentationStatus {
                Text(status).font(.caption).foregroundStyle(Color.paplySecondaryText)
                    .shimmer(item.conversation.state == .analyzing)
            }
        }
        .foregroundStyle(Color.paplyText).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var speakerNames: some View {
        ForEach(item.conversation.speakers) { ConversationSpeakerLabel(speaker: $0) }
    }
}

/// Chips umbrechen statt Namen abzuschneiden; die Breite bleibt bei Dynamic Type begrenzt.
struct ConversationChipLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                 anchor: .topLeading, proposal: ProposedViewSize(width: min(bounds.width, subviews[index].sizeThatFits(.unspecified).width), height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let width = max(1, width)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(width, ideal.width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: subviews.isEmpty ? 0 : y + rowHeight), positions)
    }
}
