import PaplyKit
import SwiftUI
import UIKit

// Zeile der Gedanken-Liste (KONZEPT §3.1) im Stil von Apple Notizen:
// 1. Titel · 2. Zeit + Vorschau · 3. Thema (nur unter „Alle“) · offene Aufgaben · Verknüpfung.
// Bewusst leicht: keine Modellzugriffe, nur fertige Werte – flüssig auch mit 2 000 Gedanken.

struct ThoughtRow: View {
    let thought: Thought
    let topic: Topic?
    let showTopic: Bool
    let time: String
    /// Ausschnitt mit Fundstellen (Suche) statt der Vorschau
    var snippet: AttributedString?
    /// Titel mit Fundstellen (Suche)
    var highlightedTitle: AttributedString?
    /// Anfang des Rohtexts, solange der Gedanke noch nicht geordnet ist
    var raw: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
                    .font(.headline)
                    .foregroundStyle(Color.paplyText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .contentTransition(.opacity)
                    .shimmer(thought.isProcessing)
                if !hasFooter {
                    Spacer(minLength: 0)
                    indicators
                }
            }
            secondLine
            footer
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduce ? .linear(duration: 0.15) : .smooth(duration: 0.25), value: thought.title)
        .animation(PaplyMotion.bouncy(reduce), value: thought.state)
        .animation(PaplyMotion.bouncy(reduce), value: thought.topicId)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Zeile 2

    @ViewBuilder
    private var secondLine: some View {
        if thought.isProcessing {
            (Text(time).foregroundStyle(Color.paplyText.opacity(0.78)) + Text("  Wird geordnet …").foregroundStyle(Color.paplySecondaryText))
                .font(.subheadline)
                .lineLimit(1)
        } else if let note = thought.stateNote, note.action != .reorganize {
            HStack(spacing: 6) {
                Text(time).foregroundStyle(Color.paplyText.opacity(0.78))
                LucideImage(note.icon, size: 14, stroke: 2, relativeTo: .subheadline)
                    .foregroundStyle(note.tint == .paplyBeak ? Color.paplyBeak : Color.paplySecondaryText)
                Text(note.text)
                    .foregroundStyle(note.tint == .paplyBeak ? Color.paplyBeak : Color.paplySecondaryText)
                    .lineLimit(1)
            }
            .font(.subheadline)
        } else if let snippet {
            (Text(time).foregroundStyle(Color.paplyText.opacity(0.78)) + Text("  ") + Text(snippet))
                .font(.subheadline)
                .foregroundStyle(Color.paplySecondaryText)
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
        } else {
            (Text(time).foregroundStyle(Color.paplyText.opacity(0.78)) + Text("  ") + Text(preview).foregroundStyle(Color.paplySecondaryText))
                .font(.subheadline)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
        }
    }

    private var preview: String {
        let line = thought.previewLine
        return line.isEmpty ? "Kein weiterer Text" : line
    }

    private var titleText: Text {
        if let highlightedTitle { return Text(highlightedTitle) }
        return Text(title)
    }

    /// Noch nicht geordnet: Anfang des Rohtexts, sonst „Gedanke · 0:42“ – so bleiben Wartende unterscheidbar
    private var title: String {
        if thought.state != .done, thought.title?.isEmpty ?? true,
           let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return String(raw.prefix(90))
        }
        return thought.displayTitle
    }

    // MARK: Fußzeile

    /// Eigene dritte Zeile nur für Thema bzw. „nicht geordnet“; Aufgaben/Verknüpfung allein stehen
    /// rechts in der Titelzeile.
    private var hasFooter: Bool {
        !thought.isProcessing && ((showTopic && topic != nil) || thought.textIsRaw)
    }

    @ViewBuilder
    private var indicators: some View {
        if !thought.isProcessing, thought.openTaskCount > 0 || !thought.links.isEmpty {
            HStack(spacing: 10) {
                if thought.openTaskCount > 0 {
                    HStack(spacing: 3) {
                        LucideImage(.circle, size: 12, stroke: 2.2, relativeTo: .caption)
                        Text("\(thought.openTaskCount)")
                            .monospacedDigit()
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if !thought.links.isEmpty {
                    LucideImage(.link, size: 13, stroke: 2.1, relativeTo: .caption)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.paplySecondaryText)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if hasFooter {
            HStack(spacing: 10) {
                if showTopic, let topic {
                    HStack(spacing: 5) {
                        TopicGlyph(key: topic.icon.rawValue, size: 13, stroke: 1.9, relativeTo: .caption)
                        Text(topic.title)
                    }
                    .foregroundStyle(ThoughtTint.mint.opacity(0.9))
                        .lineLimit(1)
                        .transition(.asymmetric(insertion: .offset(x: -8).combined(with: .opacity), removal: .opacity))
                }
                if thought.textIsRaw {
                    Text("nicht geordnet")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.paplySecondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                Spacer(minLength: 0)
                indicators
            }
            .font(.caption.weight(.medium))
            .padding(.top, 2)
        }
    }

    private var accessibilityText: String {
        var parts = [title, time]
        if thought.isProcessing {
            parts.append("Wird geordnet")
        } else if let note = thought.stateNote {
            parts.append(note.text)
        } else if !thought.previewLine.isEmpty {
            parts.append(thought.previewLine)
        }
        if showTopic, let topic { parts.append("Thema \(topic.title)") }
        let open = thought.openTaskCount
        if open > 0 { parts.append(open == 1 ? "1 offene Aufgabe" : "\(open) offene Aufgaben") }
        if !thought.links.isEmpty { parts.append("verknüpft") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Zeile mit allen Aktionen (Übersicht, Thema, Suche)

struct ThoughtListRow: View {
    let thought: Thought
    let topic: Topic?
    let showTopic: Bool
    let time: String
    var snippet: AttributedString?
    var highlightedTitle: AttributedString?
    /// Ziel des Zoom-Übergangs, wenn die große Aufnahme-Ansicht in diese neue Zeile zurückkehrt
    var zoomSource = false

    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.captureZoom) private var zoom
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Button {
            nav.path.append(.thought(thought.id))
        } label: {
            ThoughtRow(thought: thought, topic: topic, showTopic: showTopic, time: time, snippet: snippet,
                       highlightedTitle: highlightedTitle,
                       raw: thought.state == .done ? nil : model.source(thought.id)?.text)
        }
        .captureZoomSource(thought.id, in: zoomSource ? zoom : nil)
        .listRowBackground(Color.paplyRow)
        .modifier(ThoughtRowActions(
            thought: thought,
            onDelete: delete,
            onTopic: { nav.topicPicker = SheetID(id: thought.id) },
            onCopy: {
                ThoughtClipboard.copy(thought)
                nav.show(ThoughtsToast(text: "Kopiert"), reduceMotion: reduce)
            },
            onReorganize: { model.reorganize(thought.id) }
        ))
    }

    private func delete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var token: UndoToken?
        withAnimation(PaplyMotion.smooth(reduce)) { token = model.delete(thought.id) }
        guard let token else { return }
        nav.show(ThoughtsToast(text: "Gelöscht", undo: token, seconds: 4), reduceMotion: reduce)
        ThoughtsUndo.register(undoManager, name: "Löschen", model: model, token: token)
    }
}

// MARK: - Aktionen einer Zeile (Wischen, Kontextmenü)

/// Wischen und Kontextmenü wie in §3.1. Der Aufrufer liefert die Aktionen.
struct ThoughtRowActions: ViewModifier {
    let thought: Thought
    let onDelete: () -> Void
    let onTopic: () -> Void
    let onCopy: () -> Void
    let onReorganize: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: onDelete) {
                    Label("Löschen", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(action: onTopic) {
                    Label("Thema", systemImage: "tag")
                }
                .tint(ThoughtTint.swipe)
            }
            .contextMenu {
                ShareLink(item: ThoughtShare.text(thought)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                Button(action: onCopy) {
                    Label("Kopieren", systemImage: "doc.on.doc")
                }
                Button(action: onTopic) {
                    Label("Thema ändern", systemImage: "tag")
                }
                if thought.canReorganize {
                    Button(action: onReorganize) {
                        Label(thought.state == .needsAttention ? "Erneut versuchen" : "Erneut ordnen", systemImage: "arrow.clockwise")
                    }
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Löschen", systemImage: "trash")
                }
            } preview: {
                ThoughtPreviewCard(thought: thought)
            }
            .accessibilityAction(named: "Thema ändern", onTopic)
            .accessibilityAction(named: "Löschen", onDelete)
    }
}

/// Vorschau beim langen Drücken: Titel und Text wie ein kleines Blatt
struct ThoughtPreviewCard: View {
    let thought: Thought

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(thought.displayTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.paplyText)
            if let text = thought.text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundStyle(Color.paplyText.opacity(0.85))
                    .lineLimit(10)
            }
            if !thought.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(thought.tasks.prefix(4)) { task in
                        Label(task.text, systemImage: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline)
                            .foregroundStyle(task.done ? Color.paplySecondaryText : Color.paplyText)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(PaplyBackground())
    }
}

// MARK: - Hervorhebung der Fundstellen

enum SearchHighlight {
    /// Beliebiger Text mit hervorgehobenen Wortanfängen der Anfrage
    static func attributed(_ text: String, query: String, color: Color = ThoughtTint.mint) -> AttributedString {
        attributed(SearchHit(thoughtID: "", field: .title, snippet: text), query: query, color: color)
    }

    /// Ausschnitt mit Fundstellen (Bereiche aus dem Suchindex oder, falls leer, Wortanfänge der Anfrage)
    static func attributed(_ hit: SearchHit, query: String, color: Color = .paplyText) -> AttributedString {
        var text = AttributedString(hit.snippet)
        let ns = hit.snippet as NSString
        var ranges: [NSRange] = hit.ranges.compactMap { range in
            guard range.lowerBound >= 0, range.upperBound <= ns.length else { return nil }
            return NSRange(location: range.lowerBound, length: range.count)
        }
        if ranges.isEmpty {
            for word in query.split(separator: " ") where !word.isEmpty {
                var search = NSRange(location: 0, length: ns.length)
                while true {
                    let found = ns.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive], range: search)
                    guard found.location != NSNotFound else { break }
                    ranges.append(found)
                    let next = found.location + max(found.length, 1)
                    guard next < ns.length else { break }
                    search = NSRange(location: next, length: ns.length - next)
                }
            }
        }
        for range in ranges {
            guard let swiftRange = Range(range, in: hit.snippet),
                  let lower = AttributedString.Index(swiftRange.lowerBound, within: text),
                  let upper = AttributedString.Index(swiftRange.upperBound, within: text) else { continue }
            text[lower..<upper].foregroundColor = color
            text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }
}

enum ThoughtClipboard {
    @MainActor
    static func copy(_ thought: Thought) {
        UIPasteboard.general.string = ThoughtShare.text(thought)
    }
}
