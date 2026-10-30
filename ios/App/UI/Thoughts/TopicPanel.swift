import PaplyKit
import SwiftUI

// Themen-Panel über der Karte (wie Apple Karten): Thema antippen → Karte zoomt hinein, das Panel
// gleitet mit den Karten des Themas hoch. Drei Raststufen: klein (nur Kopf), mittel, groß. Unter „groß“
// zieht man das ganze Panel; in „groß“ scrollt der Inhalt, gezogen wird am Kopf oder durch Ziehen über
// den Anfang hinaus. Ganz nach unten ziehen oder freie Kartenfläche antippen schließt es.
// Eigene Ansicht statt System-Blatt: Ein `.sheet` läge über Tab-Leiste und Aufnahme-Knopf.

/// Was ein Thema tun kann (⋯ im Kopf des Panels)
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

/// Höhen der Raststufen, gemessen von der Unterkante des Bildschirms
struct PanelHeights: Equatable {
    var small: CGFloat
    var medium: CGFloat
    var large: CGFloat

    subscript(_ detent: PanelDetent) -> CGFloat {
        switch detent {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }
}

extension Color {
    /// Fläche des Panels (wie das Blatt im Entwurf, dunkler Wald)
    static let paplySheet = Color(uiColor: UIColor(hex: 0x11301F))
}

struct TopicPanel: View {
    let topicID: String
    let heights: PanelHeights
    /// verdeckte Höhe unten (Tab-Leiste, Werkzeugleiste) – so viel Luft bekommt der Inhalt unten
    let bottomInset: CGFloat
    @Binding var detent: PanelDetent
    let onClose: () -> Void
    let onAction: (TopicAction) -> Void

    @Environment(ThoughtsModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var drag: CGFloat = 0
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var scrolled = false

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
    }

    var body: some View {
        let height = visibleHeight(heights[detent] - drag)
        let scrolls = detent == .large || voiceOver
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.26))
                    .frame(width: 36, height: 5)
                    .padding(.top, 7)
                    .padding(.bottom, 7)
                    .accessibilityHidden(true)
                TopicPanelHeader(topicID: topicID, onClose: onClose, onAction: onAction)
                    .padding(.leading, 18)
                    .padding(.trailing, 14)
                    .padding(.bottom, 12)
            }
            .contentShape(Rectangle())
            .onTapGesture { if detent == .small { settle(.medium) } }
            .gesture(dragGesture, including: detent == .large ? .all : .subviews)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(scrolled ? 0.1 : 0))
                    .frame(height: 0.5)
            }
            .accessibilityElement(children: .contain)
            .accessibilityActions {
                if detent != .large { Button("Größer") { settle(detent == .small ? .medium : .large) } }
                if detent != .small { Button("Kleiner") { settle(detent == .large ? .medium : .small) } }
                Button("Schließen", action: onClose)
            }

            ScrollView {
                TopicPanelBody(topicID: topicID, columns: columns)
                    .padding(.horizontal, 12)
                    .padding(.bottom, bottomInset + 28)
            }
            .scrollPosition($scroll)
            .scrollDisabled(!scrolls)
            .scrollIndicators(scrolls ? .automatic : .hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top
            } action: { _, offset in
                if (offset > 2) != scrolled { scrolled = offset > 2 }
                // in „groß“ über den Anfang hinaus ziehen = eine Stufe kleiner
                if detent == .large, !voiceOver, offset < -70 { settle(.medium) }
            }
            .opacity(height < heights.small + 30 && detent == .small ? 0 : 1)
            // unten unter Tab-Leiste und Werkzeugleiste sanft ausblenden
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Color.paplySheet.opacity(0), Color.paplySheet.opacity(0.94)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: bottomInset + 24)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: max(0, height), alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .background(PanelSurface(tint: TopicPalette.tint(for: resolvedID), shape: shape))
        .gesture(dragGesture, including: detent == .large ? .subviews : .all)
        .onChange(of: detent) { _, new in
            if new != .large { withAnimation(PaplyMotion.smooth(reduce)) { scroll.scrollTo(edge: .top) } }
        }
        .onChange(of: topicID) { _, _ in scroll.scrollTo(edge: .top) }
        #if DEBUG
        .task {
            // Bildschirmfotos: `-PaplyPanelScrollY <pt>` scrollt den Inhalt
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-PaplyPanelScrollY"), i + 1 < args.count, let y = Double(args[i + 1]) else { return }
            try? await Task.sleep(for: .seconds(1.2))
            scroll.scrollTo(y: y)
        }
        #endif
        .sensoryFeedback(.selection, trigger: detent)
    }

    /// Mittel: eine Spalte (ruhig, ohne Silbentrennung); groß: zwei Spalten, ab xxLarge wieder eine
    private var columns: Int {
        detent == .large && typeSize < .xxLarge ? 2 : 1
    }

    /// Ein Alias zeigt sein Ziel – Farbe wie Karte und Kopf
    private var resolvedID: String {
        TopicPalette.isNeutral(topicID) ? topicID : (model.topic(topicID)?.id ?? topicID)
    }

    // MARK: Ziehen

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                drag = value.translation.height
            }
            .onEnded { value in
                let rest = heights[detent]
                let current = rest - value.translation.height
                let predicted = rest - value.predictedEndTranslation.height
                if predicted < heights.small * 0.72 || current < heights.small - 44 {
                    withAnimation(PaplyMotion.smooth(reduce)) { drag = 0 }
                    onClose()
                    return
                }
                let target = PanelDetent.allCases.min { abs(heights[$0] - predicted) < abs(heights[$1] - predicted) } ?? detent
                settle(target)
            }
    }

    private func settle(_ target: PanelDetent) {
        withAnimation(reduce ? .linear(duration: 0.15) : .interpolatingSpring(stiffness: 300, damping: 32)) {
            detent = target
            drag = 0
        }
    }

    /// Über „groß“ hinaus nur gedämpft, nach unten bis knapp über null
    private func visibleHeight(_ h: CGFloat) -> CGFloat {
        if h > heights.large { return heights.large + (h - heights.large) * 0.18 }
        return max(h, 24)
    }
}

/// Fläche des Panels: Wald, oben ein Hauch der Themenfarbe, feine Kante, Schatten nach oben
private struct PanelSurface: View {
    let tint: TopicTint
    let shape: UnevenRoundedRectangle

    var body: some View {
        shape
            .fill(Color.paplySheet)
            .overlay(alignment: .top) {
                LinearGradient(colors: [tint.fill.opacity(0.7), tint.fill.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                    .clipShape(shape)
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 24, y: -2)
    }
}

// MARK: - Kopf

struct TopicPanelHeader: View {
    let topicID: String
    let onClose: () -> Void
    let onAction: (TopicAction) -> Void

    @Environment(ThoughtsModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let topic = TopicPalette.isNeutral(topicID) ? nil : model.topic(topicID)
        let items = model.panelThoughts(topicID)
        let open = items.reduce(0) { $0 + $1.openTaskCount }
        HStack(spacing: 13) {
            badge(topic)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(topic))
                    .font(.paplyTitle(.title3))
                    .foregroundStyle(Color.paplyText)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                subtitle(items, open: open)
                    .font(.subheadline)
                    .foregroundStyle(Color.paplySecondaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : (typeSize >= .xxLarge ? 2 : 1))
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 6)
            if let topic {
                Menu {
                    Button { onAction(.rename(topic)) } label: { Label("Umbenennen", systemImage: "pencil") }
                    Button { onAction(.icon(topic)) } label: { Label("Bild oder Symbol", systemImage: "photo") }
                    Button { onAction(.merge(topic)) } label: { Label("Zusammenführen …", systemImage: "arrow.triangle.merge") }
                    Divider()
                    Button(role: .destructive) { onAction(.delete(topic)) } label: { Label("Löschen", systemImage: "trash") }
                } label: {
                    circleIcon("ellipsis")
                }
                .accessibilityLabel("Thema bearbeiten")
            }
            Button(action: onClose) {
                circleIcon("xmark")
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .accessibilityLabel("Schließen")
        }
    }

    @ViewBuilder
    private func badge(_ topic: Topic?) -> some View {
        if topicID == ThoughtsHome.pendingID {
            LucideImage(.sparkles, size: 22, stroke: 1.9, scales: false)
                .foregroundStyle(ThoughtTint.mint)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(ThoughtTint.mint.opacity(0.14)))
                .accessibilityHidden(true)
        } else {
            TopicTintBadge(topicID: topic?.id, icon: topic?.icon, size: 44)
        }
    }

    private func title(_ topic: Topic?) -> String {
        if let topic { return topic.title }
        switch topicID {
        case ThoughtsHome.pendingID: return "Noch nicht geordnet"
        case ThoughtMapView.moreID: return "Weitere Themen"
        default: return "Ohne Thema"
        }
    }

    private func subtitle(_ items: [Thought], open: Int) -> Text {
        var text = Text(items.count == 1 ? "1 Gedanke" : "\(items.count) Gedanken")
        if open == 0, let oldest = items.last?.createdAt, items.count > 1 {
            text = text + Text(" · seit \(ThoughtDate.dayMonthShort.string(from: oldest))")
        }
        if open > 0 {
            text = text + Text(" · ") + Text("\(open) offen").foregroundStyle(ThoughtTint.gold).fontWeight(.semibold)
        }
        return text
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.paplyText.opacity(0.85))
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.1)))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }
}

// MARK: - Inhalt

/// Offene Aufgaben des Themas oben, darunter alle Gedanken als Mauerwerk, nach Zeit gegliedert.
struct TopicPanelBody: View {
    let topicID: String
    /// Spalten des Mauerwerks (mittel 1, groß 2)
    var columns = 1

    @Environment(ThoughtsModel.self) private var model

    var body: some View {
        let items = model.panelThoughts(topicID)
        let open = items
            .flatMap { thought in thought.tasks.filter { !$0.done }.map { (task: $0, thought: thought) } }
            .sorted { a, b in
                switch (a.task.dueAt, b.task.dueAt) {
                case let (x?, y?): x < y
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): a.thought.createdAt > b.thought.createdAt
                }
            }
        LazyVStack(alignment: .leading, spacing: 0) {
            if !open.isEmpty {
                PanelSectionLabel(title: "Offen", count: open.count)
                PanelTaskGroup(items: open)
            }
            if items.isEmpty {
                Text(model.topic(topicID).map { "Noch keine Gedanken zu „\($0.title)“. Sprich einfach darüber – Paply ordnet sie hier ein." }
                     ?? "Keine Gedanken mehr in diesem Thema.")
                    .font(.subheadline)
                    .foregroundStyle(Color.paplySecondaryText)
                    .padding(.horizontal, 6)
                    .padding(.top, 18)
            }
            ForEach(PanelRow.rows(items)) { row in
                switch row.kind {
                case .label(let title):
                    PanelSectionLabel(title: title)
                case .cards(let thoughts):
                    MasonryLayout(columns: columns, spacing: 10) {
                        ForEach(thoughts) { thought in
                            ThoughtCardButton(thought: thought, zoomID: "panel:\(thought.id)", compact: columns > 1)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
    }
}

/// Eine Zeile des Panel-Inhalts: Abschnittskopf oder ein Block Karten. Bis 24 Gedanken ein durchgehendes
/// Mauerwerk, darüber nach Zeit gegliedert; große Abschnitte in Blöcken zu 12, damit nur Sichtbares entsteht.
private struct PanelRow: Identifiable {
    enum Kind {
        case label(String)
        case cards([Thought])
    }

    let id: String
    let kind: Kind

    static func rows(_ items: [Thought]) -> [PanelRow] {
        guard !items.isEmpty else { return [] }
        let sections = items.count <= 24
            ? [ThoughtSection(id: "all", title: "Gedanken", kind: .today, thoughts: items)]
            : ThoughtSections.make(items)
        var rows: [PanelRow] = []
        for section in sections {
            rows.append(PanelRow(id: "label-\(section.id)", kind: .label(section.title)))
            for start in stride(from: 0, to: section.thoughts.count, by: 12) {
                let block = Array(section.thoughts[start..<min(start + 12, section.thoughts.count)])
                rows.append(PanelRow(id: "cards-\(section.id)-\(start)", kind: .cards(block)))
            }
        }
        return rows
    }
}

private struct PanelSectionLabel: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count {
                Text("\(count)")
                    .foregroundStyle(Color.paplyTertiaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .font(.paplyTitle(.subheadline, weight: .semibold))
        .foregroundStyle(Color.paplySecondaryText)
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Offene Aufgaben des Themas: höchstens drei, „Alle n zeigen“ klappt auf
private struct PanelTaskGroup: View {
    let items: [(task: ThoughtTask, thought: Thought)]

    @Environment(ThoughtsNav.self) private var nav
    @Environment(TaskCheckoff.self) private var checkoff
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false

    var body: some View {
        let shown = expanded ? items : Array(items.prefix(3))
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.task.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 50)
                }
                row(item)
                    .transition(.opacity)
            }
            if items.count > 3 {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 14)
                Button {
                    withAnimation(PaplyMotion.smooth(reduce)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Weniger zeigen" : "Alle \(items.count) zeigen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paplyGreenBright)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(ThoughtCardSurface(cornerRadius: 18))
        .withoutHyphenation()
        .animation(PaplyMotion.smooth(reduce), value: items.map(\.task.id))
    }

    private func row(_ item: (task: ThoughtTask, thought: Thought)) -> some View {
        let done = checkoff.isShownDone(item.task)
        let due = Self.due(item, done: done)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            TaskCheckButton(task: item.task, thoughtID: item.thought.id, size: 22)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.task.text)
                    .font(.body)
                    .foregroundStyle(done ? Color.paplySecondaryText : Color.paplyText)
                    .strikethrough(done, color: Color.paplySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.thought.displayTitle)
                    .font(.footnote)
                    .foregroundStyle(Color.paplySecondaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                if typeSize.isAccessibilitySize, let due {
                    Text(due.text)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(due.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { nav.path.append(.thought(item.thought.id, task: item.task.id)) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            if !typeSize.isAccessibilitySize, let due {
                Text(due.text)
                    .font(.subheadline)
                    .foregroundStyle(due.color)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
    }

    /// Fälligkeit wie im Reiter Aufgaben: Wortlaut am Tag der Aufnahme, danach der Tag; überfällig in Warnfarbe
    private static func due(_ item: (task: ThoughtTask, thought: Thought), done: Bool) -> (text: String, color: Color)? {
        guard let label = TaskDueLabel.make(task: item.task, recordedAt: item.thought.createdAt) else { return nil }
        let group = TaskAgenda.group(dueAt: item.task.dueAt, now: Date())
        let color: Color = done ? .paplySecondaryText : (group == .overdue ? .paplyBeak : (group == .today ? ThoughtTint.mint : .paplySecondaryText))
        return (TaskDueText.text(label), color)
    }
}

// MARK: - Gedanken eines Panels

extension ThoughtsModel {
    /// Gedanken, die das Panel zu einer Kennung zeigt (neueste zuerst): ein Thema (auch zusammengeführte
    /// Aliasse), „Ohne Thema“ (`ThoughtsHome.noTopicID`), „Weitere Themen“ (`ThoughtMapView.moreID`) oder „Noch nicht
    /// geordnet“ (`ThoughtsHome.pendingID`).
    func panelThoughts(_ id: String) -> [Thought] {
        if id == ThoughtsHome.pendingID {
            return thoughts.filter { $0.isProcessing || $0.isWaiting }
        }
        // Sammelkreis der Karte: dieselbe Regel wie die Karte (`MapLayout.collected`)
        if id == ThoughtMapView.moreID { return mapCollectedThoughts() }
        if TopicPalette.isNeutral(id) {
            // wie die Karte: Laufendes und Wartendes steht im Eingang, nicht unter „Ohne Thema“
            return thoughts.filter { topic($0.topicId) == nil && !$0.isInMapInbox }
        }
        let resolved = topic(id)?.id ?? id
        return thoughts.filter { $0.topicId == resolved || ($0.topicId != nil && topic($0.topicId)?.id == resolved) }
    }
}
