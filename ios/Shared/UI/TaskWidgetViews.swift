import AppIntents
import SwiftUI
import WidgetKit

// Ansichten der Aufgaben-Widgets (Widgets/TasksWidget.swift). Liegen in Shared/UI, damit die App sie im Debug auf einer
// Vorschauseite mit allen Familien zeigen kann (`-PaplyScreen widgets`); die Familie kommt deshalb als Wert herein.
//
// Sperrbildschirm (Zahl, ohne Abhaken):
// - rund: Ring „heute erledigt / heute gesamt“, in der Mitte die heute fälligen (inkl. überfälliger), sonst alle offenen.
// - rechteckig: „Aufgaben · 3 fällig“ und die nächsten 2 Aufgaben. Die Texte sind `.privacySensitive()`: Bei gesperrtem
//   Gerät ersetzt iOS sie durch Platzhalter – sichtbar bleiben Zahl und Uhrzeiten, nie der Wortlaut.
// - in der Zeile: „3 fällig · nächste 15:00“.
// Home (Stil von Apples Erinnerungen, Paply-Optik): bis zu 3 (klein) bzw. 4 (mittel) Aufgaben mit Kreis zum Abhaken
// (`Button(intent:)`), Themenfarbe als Punkt, Fälligkeit. Texte auch hier `.privacySensitive()` (StandBy).

/// Was ein Aufgaben-Widget zu einem Zeitpunkt zeigt
struct TaskWidgetContent: Sendable {
    enum State: Sendable {
        case ready(TaskSnapshot)
        /// App hat noch keine Momentaufnahme geschrieben
        case noData
        /// vor dem ersten Entsperren nach einem Neustart nicht lesbar
        case locked
    }

    let date: Date
    let state: State
    /// Abhaken nur entsperrt (Face ID) – wählt den Intent
    let requiresAuth: Bool

    var snapshot: TaskSnapshot? {
        if case .ready(let snapshot) = state { return snapshot }
        return nil
    }

    var counts: TaskSnapshot.Counts? { snapshot?.counts(at: date) }
}

// MARK: - Einstieg

struct TaskWidgetView: View {
    let content: TaskWidgetContent
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            TaskWidgetCircular(content: content)
        case .accessoryRectangular:
            TaskWidgetRectangular(content: content)
        case .accessoryInline:
            TaskWidgetInline(content: content)
        case .systemMedium:
            TaskWidgetHome(content: content, medium: true)
        default:
            TaskWidgetHome(content: content, medium: false)
        }
    }
}

// MARK: - Farben, Texte

enum TaskWidgetStyle {
    static let secondary = Color.paplyText.opacity(0.62)
    static let tertiary = Color.paplyText.opacity(0.42)
    /// heute fällig (ThoughtTint.mint der App)
    static let today = Color(uiColor: UIColor(hex: 0xD8F39A))
    /// überfällig
    static let late = Color.paplyBeak

    static func topicColor(_ item: TaskSnapshot.Item) -> Color {
        item.topicColor.map { Color(uiColor: UIColor(hex: $0)) } ?? Color.paplyText.opacity(0.32)
    }

    static func dueColor(_ due: TaskSnapshot.Item.Due) -> Color {
        if due.isLate { return late }
        return due.day == .today ? today : secondary
    }

    /// Hintergrund der Home-Widgets: Waldverlauf wie die App
    static var background: some View {
        RadialGradient(
            colors: [Color(uiColor: UIColor(hex: 0x1D4A35)), .paplyForest, Color(uiColor: UIColor(hex: 0x08160F))],
            center: UnitPoint(x: 0.3, y: -0.1),
            startRadius: 0,
            endRadius: 340
        )
    }
}

enum TaskWidgetText {
    private static let locale = Locale(identifier: "de_DE")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f
    }

    private static let time = formatter("HH:mm")
    private static let weekday = formatter("EE")
    private static let day = formatter("d. MMM")

    static func time(_ date: Date) -> String { time.string(from: date) }

    /// Fälligkeit kurz: „15:00“ (heute), „Heute“, „Gestern“, „Morgen 8:00“, „Fr. 9:00“, „12. Dez.“
    static func due(_ due: TaskSnapshot.Item.Due) -> String {
        let clock = due.showsTime ? time.string(from: due.date) : nil
        switch due.day {
        case .today:
            return clock ?? "Heute"
        case .past(let days):
            return days == 1 ? "Gestern" : day.string(from: due.date)
        case .tomorrow:
            return clock.map { "Morgen \($0)" } ?? "Morgen"
        case .weekday:
            return weekday.string(from: due.date) + (clock.map { " \($0)" } ?? "")
        case .later:
            return day.string(from: due.date)
        }
    }

    /// Noch kürzer für den Sperrbildschirm: Uhrzeit nur heute („15:00“, „Heute“, „Gestern“, „Morgen“, „Fr.“, „12. Dez.“)
    static func shortDue(_ due: TaskSnapshot.Item.Due) -> String {
        switch due.day {
        case .today: due.showsTime ? time.string(from: due.date) : "Heute"
        case .past(let days): days == 1 ? "Gestern" : day.string(from: due.date)
        case .tomorrow: "Morgen"
        case .weekday: weekday.string(from: due.date)
        case .later: day.string(from: due.date)
        }
    }

    /// „3 fällig“ (heute + überfällig), sonst „12 offen“
    static func count(_ counts: TaskSnapshot.Counts) -> String {
        counts.urgent > 0 ? "\(counts.urgent) fällig" : "\(counts.open) offen"
    }

    static func doneToday(_ n: Int) -> String {
        n == 1 ? "Heute 1 erledigt" : "Heute \(n) erledigt"
    }

    static func accessibility(_ counts: TaskSnapshot.Counts) -> String {
        var parts = [counts.urgent > 0 ? "\(counts.urgent) fällig" : "\(counts.open) offen"]
        if counts.urgent > 0, counts.open > counts.urgent { parts.append("\(counts.open) offen insgesamt") }
        if counts.doneToday > 0 { parts.append("heute \(counts.doneToday) erledigt") }
        return "Aufgaben: " + parts.joined(separator: ", ")
    }
}

// MARK: - Sperrbildschirm: rund

struct TaskWidgetCircular: View {
    let content: TaskWidgetContent

    var body: some View {
        let counts = content.counts
        Gauge(value: counts?.progress ?? 0) {
            Text("Aufgaben")
        } currentValueLabel: {
            center(counts)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counts.map { $0.open == 0 ? "Aufgaben: alles erledigt" : TaskWidgetText.accessibility($0) } ?? "Aufgaben")
    }

    @ViewBuilder
    private func center(_ counts: TaskSnapshot.Counts?) -> some View {
        if let counts, counts.open > 0 {
            VStack(spacing: 0) {
                LucideImage(.listChecks, size: 11, stroke: 2.4, scales: false)
                Text("\(counts.focus)")
                    .font(.system(size: counts.focus > 99 ? 16 : 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        } else if counts != nil {
            LucideImage(.check, size: 22, stroke: 3, scales: false)
        } else {
            LucideImage(.listChecks, size: 20, stroke: 2.2, scales: false)
        }
    }
}

// MARK: - Sperrbildschirm: rechteckig

struct TaskWidgetRectangular: View {
    let content: TaskWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            switch content.state {
            case .ready(let snapshot):
                let counts = snapshot.counts(at: content.date)
                if counts.open == 0 {
                    Text("Alles erledigt").font(.subheadline)
                    if counts.doneToday > 0 {
                        Text(TaskWidgetText.doneToday(counts.doneToday)).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(snapshot.items.prefix(2)) { item in row(item) }
                }
            case .noData:
                Text("Öffne Paply einmal").font(.subheadline).foregroundStyle(.secondary)
            case .locked:
                Text("Nach dem Entsperren").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 4) {
            LucideImage(.listChecks, size: 14, stroke: 2.3, scales: false)
            Text("Aufgaben")
                .font(.headline)
            if let counts = content.counts, counts.open > 0 {
                Text("· " + TaskWidgetText.count(counts))
                    .font(.headline.weight(.regular))
                    .contentTransition(.numericText())
            }
        }
        .lineLimit(1)
        .widgetAccentable()
    }

    private func row(_ item: TaskSnapshot.Item) -> some View {
        HStack(spacing: 5) {
            if let due = item.due(at: content.date) {
                // Fälligkeit nie abschneiden – lieber den Text
                Text(TaskWidgetText.shortDue(due))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
            Text(item.text)
                .font(.subheadline)
                .privacySensitive()
        }
        .lineLimit(1)
    }
}

// MARK: - Sperrbildschirm: in der Zeile

struct TaskWidgetInline: View {
    let content: TaskWidgetContent

    var body: some View {
        ViewThatFits {
            ForEach(Array(variants.enumerated()), id: \.offset) { _, text in
                Label(text, systemImage: "checklist")
            }
        }
    }

    /// längste zuerst; ViewThatFits nimmt die erste, die passt
    private var variants: [String] {
        guard let snapshot = content.snapshot, let counts = content.counts else { return ["Aufgaben"] }
        guard counts.open > 0 else { return ["Alles erledigt"] }
        let count = TaskWidgetText.count(counts)
        guard let next = snapshot.nextTimed(after: content.date), let at = next.dueAt else { return [count] }
        let time = TaskWidgetText.time(at)
        return ["\(count) · nächste \(time)", "\(count) · \(time)", count]
    }
}

// MARK: - Home

struct TaskWidgetHome: View {
    let content: TaskWidgetContent
    let medium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: medium ? 6 : 7) {
            header
            switch content.state {
            case .ready(let snapshot):
                let counts = snapshot.counts(at: content.date)
                if counts.open == 0 || snapshot.items.isEmpty {
                    allDone(counts)
                } else {
                    rows(snapshot)
                }
            case .noData:
                note("Öffne Paply einmal – dann stehen deine Aufgaben hier.")
            case .locked:
                note("Nach dem ersten Entsperren wieder da.")
            }
        }
        // oben ausgerichtet ohne eigenen Spacer (der kostete einen Abstand – dann passte eine Zeile weniger)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Kopf

    /// Kennung, „Aufgaben“, rechts die Zahl der offenen (mittel: davor der Ring „heute erledigt / heute gesamt“).
    /// Passt der Titel nicht (kleines Widget auf kleinem iPhone, dreistellige Zahl), bleiben Kennung und Zahl.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(title: true)
            headerRow(title: false)
        }
        .frame(height: 22)
    }

    private func headerRow(title: Bool) -> some View {
        HStack(alignment: .center, spacing: 4) {
            HStack(spacing: 6) {
                TaskWidgetBadge(size: 22)
                if title {
                    Text("Aufgaben")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paplyText)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let counts = content.counts, counts.open > 0 {
                if medium, counts.urgent + counts.doneToday > 0 {
                    TaskWidgetRing(progress: counts.progress, size: 18)
                        .padding(.trailing, 2)
                }
                Text("\(counts.open)")
                    .font(.system(size: medium ? 22 : 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.paplyGreenBright)
                    .fixedSize()
                    .contentTransition(.numericText())
                    .widgetAccentable()
                    .accessibilityLabel(TaskWidgetText.accessibility(counts))
            }
        }
    }

    // MARK: Zeilen

    @ViewBuilder
    private func rows(_ snapshot: TaskSnapshot) -> some View {
        let limit = medium ? 4 : 3
        let items = Array(snapshot.items.prefix(limit))
        // Bei großer Schrift passen weniger Zeilen – lieber eine weglassen als abschneiden
        ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: items.count, through: 1, by: -1)), id: \.self) { n in
                list(Array(items.prefix(n)))
            }
        }
        .layoutPriority(1) // vor dem Spacer: die Liste bekommt die ganze Höhe
    }

    private func list(_ items: [TaskSnapshot.Item]) -> some View {
        VStack(alignment: .leading, spacing: medium ? 0 : 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if medium {
                    TaskWidgetMediumRow(item: item, date: content.date, requiresAuth: content.requiresAuth,
                                        separator: index < items.count - 1)
                } else {
                    TaskWidgetSmallRow(item: item, date: content.date, requiresAuth: content.requiresAuth)
                }
            }
        }
    }

    // MARK: Leer

    /// Ruhig: grüner Haken, „Alles erledigt“, darunter heute Geschafftes. Klein untereinander (unten links, wie Apples
    /// Widgets), mittel nebeneinander.
    @ViewBuilder
    private func allDone(_ counts: TaskSnapshot.Counts) -> some View {
        let check = ZStack {
            Circle().fill(Color.paplyGreenBright)
            LucideImage(.check, size: 15, stroke: 3.4, scales: false)
                .foregroundStyle(Color.paplyForest)
        }
        .frame(width: 30, height: 30)
        .widgetAccentable()
        let words = VStack(alignment: .leading, spacing: 1) {
            Text("Alles erledigt")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.paplyText)
            Text(counts.doneToday > 0 ? TaskWidgetText.doneToday(counts.doneToday) : "Nichts mehr offen")
                .font(.caption)
                .foregroundStyle(TaskWidgetStyle.secondary)
        }
        .lineLimit(1)
        if medium {
            HStack(spacing: 10) { check; words }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) { check; words }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .accessibilityElement(children: .combine)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(TaskWidgetStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Zeile „klein“: Kreis · Text, darunter Punkt in der Themenfarbe und Fälligkeit (ohne Datum: das Thema)
private struct TaskWidgetSmallRow: View {
    let item: TaskSnapshot.Item
    let date: Date
    let requiresAuth: Bool

    var body: some View {
        let due = item.due(at: date)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TaskWidgetCheck(item: item, requiresAuth: requiresAuth, size: 17)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.text)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.paplyText)
                    .privacySensitive()
                HStack(spacing: 4) {
                    TaskWidgetDot(item: item, size: 6)
                    if let due {
                        Text(TaskWidgetText.due(due))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(TaskWidgetStyle.dueColor(due))
                    } else if let topic = item.topicTitle {
                        Text(topic)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(TaskWidgetStyle.tertiary)
                            .privacySensitive()
                    }
                }
            }
            .lineLimit(1)
            .invalidatableContent()
        }
        .accessibilityElement(children: .contain)
    }
}

/// Zeile „mittel“: Kreis · Text (antippen öffnet den Gedanken) · rechts Fälligkeit und Punkt in der Themenfarbe
private struct TaskWidgetMediumRow: View {
    let item: TaskSnapshot.Item
    let date: Date
    let requiresAuth: Bool
    let separator: Bool

    var body: some View {
        HStack(spacing: 10) {
            TaskWidgetCheck(item: item, requiresAuth: requiresAuth, size: 17)
            if let url = PaplyURL.task(thoughtID: item.thoughtID, taskID: item.taskID) {
                Link(destination: url) { label }
                    .invalidatableContent()
            } else {
                label
            }
        }
        .frame(height: 24)
    }

    private var label: some View {
        let due = item.due(at: date)
        return HStack(spacing: 8) {
            Text(item.text)
                .font(.subheadline)
                .foregroundStyle(Color.paplyText)
                .lineLimit(1)
                .privacySensitive()
            Spacer(minLength: 4)
            if let due {
                Text(TaskWidgetText.due(due))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(TaskWidgetStyle.dueColor(due))
                    .lineLimit(1)
                    .fixedSize()
            }
            TaskWidgetDot(item: item, size: 7)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if separator {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Kreis zum Abhaken. Wählt den Intent nach dem Schalter „Abhaken nur mit Face ID“.
private struct TaskWidgetCheck: View {
    let item: TaskSnapshot.Item
    let requiresAuth: Bool
    let size: CGFloat

    var body: some View {
        Group {
            if requiresAuth {
                Button(intent: CompleteTaskIntent(thoughtID: item.thoughtID, taskID: item.taskID)) { circle }
            } else {
                Button(intent: CompleteTaskQuickIntent(thoughtID: item.thoughtID, taskID: item.taskID)) { circle }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abhaken: \(item.text)")
    }

    private var circle: some View {
        Circle()
            .strokeBorder(Color.paplyText.opacity(0.5), lineWidth: 1.5)
            .frame(width: size, height: size)
            .padding(6)
            .contentShape(Rectangle())
            .padding(-6)
    }
}

/// Punkt in der Themenfarbe
private struct TaskWidgetDot: View {
    let item: TaskSnapshot.Item
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(TaskWidgetStyle.topicColor(item))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Kennung „Aufgaben“: Lucide list-checks auf hellgrünem Kreis
struct TaskWidgetBadge: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.paplyGreenBright)
            LucideImage(.listChecks, size: size * 0.6, stroke: 2.6, scales: false)
                .foregroundStyle(Color.paplyForest)
        }
        .frame(width: size, height: size)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// Kleiner Ring „heute erledigt / heute gesamt“
struct TaskWidgetRing: View {
    let progress: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.paplyText.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.paplyGreenBright, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

// MARK: - Beispiel (Widget-Galerie, Platzhalter)

extension TaskSnapshot {
    /// Beispieldaten ohne echte Personendaten
    static func sample(now: Date = Date(), calendar: Calendar = .current) -> TaskSnapshot {
        let today = calendar.startOfDay(for: now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            (calendar.date(byAdding: .day, value: day, to: today) ?? today).addingTimeInterval(Double(hour * 3_600 + minute * 60))
        }
        let items = [
            Item(thoughtID: "s_sample1", taskID: "k_1", text: "Steuerberater wegen der Belege anrufen", dueAt: at(0, 15), hasTime: true,
                 topicTitle: "Finanzen", topicColor: 0x5FB99A, topicSymbol: "wallet"),
            Item(thoughtID: "s_sample2", taskID: "k_2", text: "Notizen aus der Retro an alle schicken", dueAt: at(0, 19), hasTime: true,
                 topicTitle: "Team", topicColor: 0x5B8FE0, topicSymbol: "users"),
            Item(thoughtID: "s_sample3", taskID: "k_3", text: "Flug nach Porto buchen", dueAt: at(3, 12), hasTime: false,
                 topicTitle: "Urlaub", topicColor: 0xE0B045, topicSymbol: "plane"),
            Item(thoughtID: "s_sample4", taskID: "k_4", text: "Buch über Gewohnheiten vormerken", dueAt: nil, hasTime: false,
                 topicTitle: "Lesen", topicColor: 0xC27BD1, topicSymbol: "book"),
        ]
        return TaskSnapshot(generatedAt: now, openCount: 7, urgentCount: 2, doneTodayAt: [at(0, 9), at(0, 11)],
                            dueDates: [at(0, 15), at(0, 19), at(3, 12), at(5, 12)], items: items)
    }
}
