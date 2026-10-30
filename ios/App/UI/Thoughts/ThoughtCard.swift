import PaplyKit
import SwiftUI
import UIKit

// Gedanken-Karte im Themen-Panel: Titel (höchstens zwei Zeilen), 2–3 Zeilen Text, offene Aufgaben direkt
// abhakbar (höchstens zwei, sonst „+ n“), Fuß mit Zeit und Verknüpfung. Zustände (wird geordnet, wartet,
// Fehler, nicht geordnet) wie in der Liste; solange nicht geordnet, kommen Titel und Vorschau aus dem
// Rohtext (`RawTitle`: ohne „Ähm, also“). Ohne Silbentrennung, kurze letzte Wörter („1“, „…“) bleiben beim
// Wort davor. Antippen → Detail mit Zoom, lange drücken → Kontextmenü.

/// Mauerwerk (im Panel: mittel eine Spalte, groß zwei): jede Karte kommt in die gerade kürzere Spalte
/// (Lesereihenfolge bleibt). Rechnet nur bei neuer Breite, Spaltenzahl oder neuen Karten, nie pro Bild.
struct MasonryLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 10

    struct Cache {
        var width: CGFloat = -1
        var columns = 0
        var frames: [CGRect] = []
        var height: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 360
        arrange(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        arrange(width: bounds.width, subviews: subviews, cache: &cache)
        for (index, subview) in subviews.enumerated() where index < cache.frames.count {
            let frame = cache.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        let count = max(1, columns)
        guard cache.width != width || cache.columns != count || cache.frames.count != subviews.count else { return }
        let columnWidth = max(1, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        var heights = Array(repeating: CGFloat(0), count: count)
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)
        for subview in subviews {
            let column = heights.indices.min { heights[$0] < heights[$1] - 0.5 } ?? 0
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let y = heights[column] == 0 ? 0 : heights[column] + spacing
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing), y: y, width: columnWidth, height: height))
            heights[column] = y + height
        }
        cache = Cache(width: width, columns: count, frames: frames, height: heights.max() ?? 0)
    }
}

// MARK: - Karte

struct ThoughtCard: View {
    let thought: Thought
    /// Rohtext, solange der Gedanke nicht geordnet ist
    var raw: String?
    var linkCount = 0
    /// schmale Spalte (zwei Spalten im Panel)
    var compact = false

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var big: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        let open = thought.tasks.filter { !$0.done }
        let rawParts = Self.rawParts(thought, raw: raw)
        VStack(alignment: .leading, spacing: 0) {
            Text(CardText.keepingLastWord(rawParts?.title ?? thought.displayTitle))
                .font(compact ? .subheadline.weight(.semibold) : .callout.weight(.semibold))
                .foregroundStyle(Color.paplyText)
                .lineLimit(big ? 5 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .shimmer(thought.isProcessing)
            secondary(rest: rawParts?.rest ?? "")
                .padding(.top, 4)
            if !open.isEmpty, !thought.isProcessing {
                tasks(open)
                    .padding(.top, 10)
            }
            footer
                .padding(.top, 10)
        }
        .padding(.horizontal, compact ? 14 : 16)
        .padding(.top, 13)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .withoutHyphenation()
        .background(ThoughtCardSurface())
        .animation(reduce ? .linear(duration: 0.15) : .smooth(duration: 0.25), value: thought.title)
        .animation(PaplyMotion.smooth(reduce), value: open.map(\.id))
        .animation(PaplyMotion.bouncy(reduce), value: thought.state)
    }

    /// Noch nicht geordnet und ohne Titel: Titel und Vorschau aus dem Rohtext (sonst „Gedanke · 0:42“)
    static func rawParts(_ thought: Thought, raw: String?) -> RawTitle.Parts? {
        guard thought.state != .done, thought.title?.isEmpty ?? true, let raw else { return nil }
        return RawTitle.split(raw)
    }

    // MARK: Inhalt

    private var previewLines: Int { big ? 6 : (compact ? 4 : 2) }

    /// Schmale Spalte: Vorschau etwas kleiner, damit eine Zeile mehr als zwei Wörter trägt
    private func previewText(_ text: String) -> some View {
        Text(text)
            .font(compact ? .footnote : .subheadline)
            .foregroundStyle(Color.paplySecondaryText)
            .lineSpacing(2)
            .lineLimit(previewLines)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func secondary(rest: String) -> some View {
        if thought.isProcessing {
            VStack(alignment: .leading, spacing: 7) {
                if !rest.isEmpty { previewText(rest) }
                HStack(spacing: 6) {
                    LucideImage(.sparkles, size: 14, stroke: 2, relativeTo: .subheadline)
                        .foregroundStyle(ThoughtTint.mint)
                    Text("Wird geordnet …")
                        .foregroundStyle(Color.paplySecondaryText)
                        .shimmer()
                }
                .font(.subheadline)
            }
        } else if let note = thought.stateNote, note.action != .reorganize {
            VStack(alignment: .leading, spacing: 7) {
                if !rest.isEmpty { previewText(rest) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    LucideImage(note.icon, size: 14, stroke: 2, relativeTo: .subheadline)
                        .foregroundStyle(note.tint == .paplyBeak ? Color.paplyBeak : Color.paplySecondaryText)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    Text(note.text)
                        .foregroundStyle(note.tint == .paplyBeak ? Color.paplyBeak : Color.paplySecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                if thought.textIsRaw {
                    Text("nicht geordnet")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.paplySecondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                if !preview.isEmpty {
                    previewText(preview)
                }
            }
        }
    }

    private var preview: String {
        guard let text = thought.text, !text.isEmpty else { return "" }
        return text.prefix(260).split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private func tasks(_ open: [ThoughtTask]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(open.prefix(2)) { task in
                CardTaskRow(task: task, thoughtID: thought.id)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if open.count > 2 {
                Text("+ \(open.count - 2) weitere")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.paplySecondaryText)
                    .padding(.leading, 29)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if Calendar.current.isDateInToday(thought.createdAt) {
                Circle()
                    .fill(Color.paplyGreenBright)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(ThoughtDate.card(thought.createdAt))
                .monospacedDigit()
            Spacer(minLength: 4)
            if linkCount > 0 {
                HStack(spacing: 3) {
                    LucideImage(.link, size: 12, stroke: 2.2, relativeTo: .caption)
                    Text("\(linkCount)").monospacedDigit()
                }
                .accessibilityHidden(true)
            }
        }
        .font(compact ? .caption : .footnote)
        .foregroundStyle(Color.paplyTertiaryText)
        .lineLimit(1)
    }
}

/// Satz-Hilfen der Karten
enum CardText {
    /// Ein kurzes letztes Wort („1“, „…“, „ab“) bleibt beim Wort davor (geschütztes Leerzeichen), damit es
    /// nicht allein in der letzten Zeile steht.
    static func keepingLastWord(_ text: String) -> String {
        guard let space = text.range(of: " ", options: .backwards), space.lowerBound > text.startIndex else { return text }
        guard text[space.upperBound...].count <= 3 else { return text }
        return text.replacingCharacters(in: space, with: "\u{00A0}")
    }
}

/// Fläche der Karte: Weiß 7 % auf dem Wald, feine Kante, weicher Schatten (nur auf der Form – günstig)
struct ThoughtCardSurface: View {
    var cornerRadius: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.paplyCard)
            .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
            .overlay(shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
    }
}

extension Color {
    /// Karten auf dem Wald (etwas dichter als Listenzeilen, damit sie auf getönten Flächen tragen)
    static let paplyCard = Color(uiColor: UIColor(hex: 0x1E3F31, alpha: 0.82))
}

/// Eine offene Aufgabe auf der Karte: Haken + Text (durchgestrichen, solange sie 1,2 s „wartet“)
private struct CardTaskRow: View {
    let task: ThoughtTask
    let thoughtID: String
    @Environment(TaskCheckoff.self) private var checkoff

    var body: some View {
        let done = checkoff.isShownDone(task)
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            TaskCheckButton(task: task, thoughtID: thoughtID, size: 20)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Text(task.text)
                .font(.subheadline)
                .foregroundStyle(done ? Color.paplySecondaryText : Color.paplyText)
                .strikethrough(done, color: Color.paplySecondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Karte mit allen Aktionen

/// Karte zum Antippen (Detail mit Zoom) und lange Drücken (Teilen, Kopieren, Thema ändern, Erneut
/// ordnen, Löschen) – die bisherigen Wisch-Aktionen der Liste wohnen jetzt im Kontextmenü.
struct ThoughtCardButton: View {
    let thought: Thought
    /// Kennung der Zoom-Quelle (eindeutig je Stelle, z. B. „panel:<id>“)
    let zoomID: String
    /// schmale Spalte (zwei Spalten im Panel)
    var compact = false

    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.captureZoom) private var zoom
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let linkCount = model.linked(thought.id).count
        let raw = thought.state == .done ? nil : model.source(thought.id)?.text
        ThoughtCard(thought: thought, raw: raw, linkCount: linkCount, compact: compact)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .modifier(CardZoomSource(id: zoomID, namespace: zoom))
            .contextMenu {
                ThoughtMenuItems(thought: thought, onDelete: delete, onTopic: { nav.topicPicker = SheetID(id: thought.id) },
                                 onCopy: copy, onReorganize: { model.reorganize(thought.id) })
            } preview: {
                ThoughtPreviewCard(thought: thought)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(linkCount: linkCount, raw: raw))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
            .accessibilityActions {
                ForEach(thought.tasks.filter { !$0.done }.prefix(2)) { task in
                    Button("Abhaken: \(task.text)") { model.toggleTask(thought.id, task.id) }
                }
                Button("Thema ändern") { nav.topicPicker = SheetID(id: thought.id) }
                Button("Löschen", action: delete)
            }
    }

    private func open() {
        nav.path.append(.thought(thought.id, zoom: zoomID))
    }

    private func copy() {
        ThoughtClipboard.copy(thought)
        nav.show(ThoughtsToast(text: "Kopiert"), reduceMotion: reduce)
    }

    private func delete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var token: UndoToken?
        withAnimation(PaplyMotion.smooth(reduce)) { token = model.delete(thought.id) }
        guard let token else { return }
        nav.show(ThoughtsToast(text: "Gelöscht", undo: token, seconds: 4), reduceMotion: reduce)
        ThoughtsUndo.register(undoManager, name: "Löschen", model: model, token: token)
    }

    private func accessibilityText(linkCount: Int, raw: String?) -> String {
        let title = ThoughtCard.rawParts(thought, raw: raw)?.title ?? thought.displayTitle
        var parts = [title, ThoughtDate.card(thought.createdAt)]
        if thought.isProcessing {
            parts.append("Wird geordnet")
        } else if let note = thought.stateNote {
            parts.append(note.text)
        } else if !thought.previewLine.isEmpty {
            parts.append(thought.previewLine)
        }
        let open = thought.tasks.filter { !$0.done }
        if !open.isEmpty {
            parts.append(open.count == 1 ? "1 offene Aufgabe: \(open[0].text)" : "\(open.count) offene Aufgaben")
        }
        if linkCount > 0 { parts.append("verknüpft") }
        return parts.joined(separator: ", ")
    }
}

/// Zoom-Quelle der Karte mit gleicher Rundung wie die Karte
private struct CardZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        } else {
            content
        }
    }
}

extension View {
    /// Detail mit Zoom aus der Karte (nur wenn eine Karte die Quelle ist)
    @ViewBuilder
    func detailZoom(_ sourceID: String?, in namespace: Namespace.ID?) -> some View {
        if let sourceID, let namespace {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
