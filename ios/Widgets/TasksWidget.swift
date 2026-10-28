import AppIntents
import SwiftUI
import WidgetKit

/// Aufgaben auf Sperrbildschirm und Home-Bildschirm (Ansichten: Shared/UI/TaskWidgetViews.swift).
///
/// Daten: `tasks-snapshot.json` in der App Group (die App schreibt sie bei jeder Änderung, entprellt, und lädt das
/// Widget dann neu) plus die Warteschlange der hier abgehakten Aufgaben darüber (`TaskWidgetFiles.loadCurrent`).
/// Timeline: jetzt, jede kommende Uhrzeit einer angezeigten Aufgabe (wird dann überfällig) und die nächsten zwei
/// Mitternächte („Morgen“ → „Heute“, Ring beginnt bei 0); danach holt WidgetKit eine neue (`.atEnd`).
///
/// Antippen: Kreis hakt ab (`CompleteTaskIntent`, nur entsperrt – oder `CompleteTaskQuickIntent`, wenn „Abhaken nur
/// mit Face ID“ aus ist). Text (mittel) öffnet den Gedanken an der Aufgabe (`paply-ios://task/<Gedanke>/<Aufgabe>`),
/// sonst öffnet das Widget den Reiter Aufgaben (klein unterstützt nur `widgetURL`).
/// Gesperrt: `.privacySensitive()` – iOS zeigt statt der Texte Platzhalter, Zahl und Uhrzeiten bleiben.
/// Beta „Gedanken & Aufgaben“ aus (`BetaFeatures`, App Group): ruhiger Zustand ohne Aufgaben; antippen öffnet Paply mit
/// dem Hinweis. Die App lädt alle Widgets beim Umschalten neu.
struct TasksWidget: Widget {
    static let kind = WidgetKinds.tasks

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TasksWidgetProvider()) { entry in
            TasksWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Paply-Aufgaben")
        .description("Deine nächsten Aufgaben aus den Gedanken. Auf dem Home-Bildschirm mit einem Tipp abhaken.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium])
    }
}

struct TasksWidgetEntry: TimelineEntry {
    let date: Date
    let state: TaskWidgetContent.State
    let requiresAuth: Bool

    var content: TaskWidgetContent { TaskWidgetContent(date: date, state: state, requiresAuth: requiresAuth) }
}

struct TasksWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksWidgetEntry {
        TasksWidgetEntry(date: Date(), state: .ready(.sample()), requiresAuth: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksWidgetEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            // Widget-Galerie: Beispiel statt echter Aufgaben (auch, solange Paply noch nichts geschrieben hat)
            let state: TaskWidgetContent.State = Self.betaOn ? .ready(.sample(now: now)) : .betaOff
            completion(TasksWidgetEntry(date: now, state: state, requiresAuth: true))
            return
        }
        completion(TasksWidgetEntry(date: now, state: Self.state(), requiresAuth: Self.requiresAuth))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksWidgetEntry>) -> Void) {
        let now = Date()
        let state = Self.state()
        let auth = Self.requiresAuth
        switch state {
        case .ready(let snapshot):
            let entries = snapshot.timelineDates(from: now).map { TasksWidgetEntry(date: $0, state: state, requiresAuth: auth) }
            completion(Timeline(entries: entries, policy: .atEnd))
        case .noData, .betaOff:
            // die App lädt neu, sobald sie zum ersten Mal schreibt bzw. die Beta umgeschaltet wird
            completion(Timeline(entries: [TasksWidgetEntry(date: now, state: state, requiresAuth: auth)], policy: .never))
        case .locked:
            // vor dem ersten Entsperren: später erneut lesen
            completion(Timeline(entries: [TasksWidgetEntry(date: now, state: state, requiresAuth: auth)],
                                policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }

    private static func state() -> TaskWidgetContent.State {
        guard betaOn else { return .betaOff }
        return switch TaskWidgetFiles.loadCurrent() {
        case .ready(let snapshot): .ready(snapshot)
        case .missing: .noData
        case .unreadable: .locked
        }
    }

    private static var requiresAuth: Bool { TaskWidgetSettings.requiresAuth(AppGroup.defaults) }

    /// Beta „Gedanken & Aufgaben“ (vor dem ersten Entsperren nicht lesbar → an; die Aufgaben sind dann ohnehin gesperrt)
    private static var betaOn: Bool { BetaFeatures.thoughtsEnabled(AppGroup.defaults) }
}

struct TasksWidgetEntryView: View {
    let entry: TasksWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TaskWidgetView(content: entry.content, family: family)
            .widgetURL(PaplyURL.tasks)
            .containerBackground(for: .widget) {
                switch family {
                case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
                    TaskWidgetStyle.background
                default:
                    Color.clear
                }
            }
    }
}
