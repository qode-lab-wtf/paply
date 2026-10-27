import PaplyKit
import SwiftUI

// Chip-Leiste (KONZEPT §3.1): „Alle“ · „Aufgaben n“ · aktive Themen nach letzter Aktivität.
// Der gewählte Chip ist grün gefüllt, die Auswahl gleitet (matchedGeometryEffect, Smooth).

/// Was ein Chip mit einem Thema tun kann (langes Drücken bzw. ⋯ im Themen-Kopf)
enum TopicAction: Identifiable {
    case rename(Topic)
    case icon(Topic)
    case merge(Topic)
    case delete(Topic)

    var id: String {
        switch self {
        case .rename(let t): "rename-\(t.id)"
        case .icon(let t): "icon-\(t.id)"
        case .merge(let t): "merge-\(t.id)"
        case .delete(let t): "delete-\(t.id)"
        }
    }

    var topic: Topic {
        switch self {
        case .rename(let t), .icon(let t), .merge(let t), .delete(let t): t
        }
    }
}

struct TopicChips: View {
    let topics: [Topic]
    /// nil = kein Aufgaben-Chip
    let taskCount: Int?
    let selection: ThoughtsFilter
    let onSelect: (ThoughtsFilter) -> Void
    let onAction: (TopicAction) -> Void

    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                chips
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .scrollClipDisabled()
            .onChange(of: selection) { _, new in
                withAnimation(PaplyMotion.smooth(reduce)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder
    private var chips: some View {
        let row = HStack(spacing: 8) {
            chip(.all, title: "Alle", symbol: nil)
            if let taskCount {
                chip(.tasks, title: "Aufgaben", symbol: "checklist", count: taskCount)
            }
            ForEach(topics) { topic in
                chip(.topic(topic.id), title: topic.title, symbol: topic.icon.systemImage)
                    .contextMenu {
                        Button { onAction(.rename(topic)) } label: { Label("Umbenennen", systemImage: "pencil") }
                        Button { onAction(.icon(topic)) } label: { Label("Symbol", systemImage: "square.grid.2x2") }
                        Button { onAction(.merge(topic)) } label: { Label("Zusammenführen mit …", systemImage: "arrow.triangle.merge") }
                        Divider()
                        Button(role: .destructive) { onAction(.delete(topic)) } label: { Label("Löschen", systemImage: "trash") }
                    }
            }
        }
        if #available(iOS 26, *) {
            if PaplyStyle.usesGlass {
                GlassEffectContainer(spacing: 8) { row }
            } else {
                row
            }
        } else {
            row
        }
    }

    private func chip(_ filter: ThoughtsFilter, title: String, symbol: String?, count: Int? = nil) -> some View {
        let selected = selection == filter
        return Button {
            withAnimation(PaplyMotion.smooth(reduce)) {
                // zweites Tippen auf das gewählte Thema → zurück zu „Alle“
                onSelect(selected && filter != .all ? .all : filter)
            }
        } label: {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .imageScale(.small)
                        .foregroundStyle(selected ? Color.paplyForest : ThoughtTint.mint)
                }
                Text(title)
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .opacity(0.7)
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.paplyForest : Color.paplyText)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.paplyGreenBright)
                        .matchedGeometryEffect(id: "chip.selection", in: ns)
                }
            }
            .modifier(ChipSurface(selected: selected))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .id(filter)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
    }
}

/// Nicht gewählte Chips: Glas (iOS 26) bzw. Weiß 8 %
private struct ChipSurface: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        if selected {
            content
        } else {
            content.paplyGlass(.plain, interactive: true)
        }
    }
}

// MARK: - Themen-Kopf (§3.1 „Gewähltes Thema“)

struct TopicHeader: View {
    let topic: Topic
    let count: Int
    let onAction: (TopicAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            TopicBadge(icon: topic.icon, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.paplyText)
                    .lineLimit(2)
                Text(count == 1 ? "1 Gedanke" : "\(count) Gedanken")
                    .font(.subheadline)
                    .foregroundStyle(Color.paplySecondaryText)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 8)
            Menu {
                Button { onAction(.rename(topic)) } label: { Label("Umbenennen", systemImage: "pencil") }
                Button { onAction(.icon(topic)) } label: { Label("Symbol", systemImage: "square.grid.2x2") }
                Button { onAction(.merge(topic)) } label: { Label("Zusammenführen …", systemImage: "arrow.triangle.merge") }
                Divider()
                Button(role: .destructive) { onAction(.delete(topic)) } label: { Label("Löschen", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.paplyText)
                    .frame(width: 40, height: 40)
                    .paplyGlass(.plain, interactive: true, in: Circle())
            }
            .accessibilityLabel("Thema bearbeiten")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

/// Kompakte Karte „Offen“ mit den offenen Aufgaben des Themas (max. 3, „Alle n zeigen“)
struct TopicOpenTasks: View {
    let items: [(task: ThoughtTask, thought: Thought)]
    let onToggle: (ThoughtTask, Thought) -> Void
    let onOpen: (ThoughtTask, Thought) -> Void
    @State private var expanded = false

    var body: some View {
        let shown = expanded ? items : Array(items.prefix(3))
        ForEach(shown, id: \.task.id) { item in
            TaskLine(task: item.task, subtitle: (nil, item.thought.displayTitle), onToggle: { onToggle(item.task, item.thought) })
                .contentShape(Rectangle())
                .onTapGesture { onOpen(item.task, item.thought) }
                .listRowBackground(Color.paplyRow)
        }
        if items.count > 3 {
            Button {
                withAnimation(.paplySmooth) { expanded.toggle() }
            } label: {
                Text(expanded ? "Weniger zeigen" : "Alle \(items.count) zeigen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.paplyGreenBright)
            }
            .listRowBackground(Color.paplyRow)
        }
    }
}
