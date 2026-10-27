import AppIntents
import SwiftUI
import WidgetKit

/// Sperrbildschirm-Widget „Paply-Gedanke“ für die Reihe unter der Uhr (wie die ChatGPT- und Claude-Widgets).
/// Ein Tipp nimmt wie das Steuerelement ohne App einen Gedanken auf, der nächste beendet (`ThoughtWidgetIntent`).
/// Reagiert die App darauf nicht, öffnet der Intent Paply in der großen Ansicht (`OpenURLIntent`, ab iOS 18.2).
/// Rückfall per `widgetURL` (Tipp außerhalb des Knopfs): Paply öffnet und nimmt in der großen Ansicht auf.
/// Zustand aus `thought-state.json` (nur recording/id/startedAt, nie Text); die App lädt das Widget bei jedem
/// Wechsel neu (`WidgetCenter.shared.reloadTimelines(ofKind:)` in ThoughtBridge).
struct ThoughtWidget: Widget {
    static let kind = WidgetKinds.thought

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ThoughtWidgetProvider()) { entry in
            ThoughtWidgetView(entry: entry)
        }
        .configurationDisplayName("Paply-Gedanke")
        .description("Ein Tipp nimmt einen Gedanken auf, nochmal tippen beendet. Paply ordnet ihn in der App.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct ThoughtWidgetEntry: TimelineEntry {
    let date: Date
    let recording: Bool
    let startedAt: Date?

    static func idle(_ date: Date = Date()) -> ThoughtWidgetEntry {
        ThoughtWidgetEntry(date: date, recording: false, startedAt: nil)
    }
}

struct ThoughtWidgetProvider: TimelineProvider {
    /// Länger nimmt Paply nie auf (ThoughtCapture.limit = 10 Min.) – danach zeigt das Widget wieder
    /// „bereit“, auch wenn die App abstürzte, ohne den Zustand zurückzusetzen.
    static let longestRecording: TimeInterval = 11 * 60

    func placeholder(in context: Context) -> ThoughtWidgetEntry { .idle() }

    func getSnapshot(in context: Context, completion: @escaping (ThoughtWidgetEntry) -> Void) {
        completion(context.isPreview ? .idle() : Self.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThoughtWidgetEntry>) -> Void) {
        let entry = Self.current()
        var entries = [entry]
        if entry.recording, let startedAt = entry.startedAt {
            entries.append(.idle(startedAt.addingTimeInterval(Self.longestRecording)))
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private static func current() -> ThoughtWidgetEntry {
        let now = Date()
        guard let state = SharedStore.read(ThoughtStateFile.self, .thoughtState), state.recording else { return .idle(now) }
        if let startedAt = state.startedAt, now.timeIntervalSince(startedAt) >= longestRecording { return .idle(now) }
        return ThoughtWidgetEntry(date: now, recording: true, startedAt: state.startedAt)
    }
}

struct ThoughtWidgetView: View {
    let entry: ThoughtWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: ThoughtWidgetIntent()) {
            Group {
                if family == .accessoryRectangular {
                    rectangular
                } else {
                    mark(size: nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .widgetURL(PaplyURL.thoughtStart(source: "widget"))
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityLabel(entry.recording ? "Paply-Gedanke, Aufnahme läuft" : "Paply-Gedanke")
        .accessibilityHint(entry.recording ? "Beendet die Aufnahme." : "Nimmt einen Gedanken auf.")
    }

    /// p-Kopf im Kreis; während der Aufnahme gefüllt (Symbole aus Widgets/Assets.xcassets, wie das Steuerelement)
    private func mark(size: CGFloat?) -> some View {
        ZStack {
            if entry.recording {
                Image("paply.mark.fill")
                    .resizable()
                    .scaledToFit()
            } else {
                AccessoryWidgetBackground()
                    .clipShape(Circle())
                Image("paply.mark")
                    .resizable()
                    .scaledToFit()
                    .padding(size.map { $0 * 0.24 } ?? 15)
            }
        }
        .frame(width: size, height: size)
        .widgetAccentable()
    }

    private var rectangular: some View {
        HStack(spacing: 10) {
            mark(size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("Gedanke")
                    .font(.headline)
                    .widgetAccentable()
                Group {
                    if entry.recording, let startedAt = entry.startedAt {
                        Text("Aufnahme · \(Text(startedAt, style: .timer))")
                    } else if entry.recording {
                        Text("Aufnahme läuft")
                    } else {
                        Text("Tippen und sprechen")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
