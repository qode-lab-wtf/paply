import Foundation

// Aufgaben für Sperrbildschirm und Home-Bildschirm (Widgets/TasksWidget.swift).
//
// Die Gedanken liegen im privaten Container der App – die Widget-Erweiterung sieht nur diese Momentaufnahme in der
// App Group und die Warteschlange der im Widget abgehakten Aufgaben (Dateien: `TaskWidgetFiles`). Die App schreibt
// die Momentaufnahme bei jeder Änderung (entprellt, `TaskWidgetSync`); das Widget rechnet daraus für jeden Zeitpunkt
// seiner Timeline selbst die Zahlen und Fälligkeiten (um Mitternacht wird „Morgen“ zu „Heute“, um 8:00 eine Aufgabe
// von 8:00 überfällig).
//
// Diese Datei ist reine Logik ohne Dateien und ohne PaplyKit: App, Tastatur und Widgets übersetzen sie mit, und
// PaplyKitTests prüft sie über einen Verweis (`PaplyKit/Tests/PaplyKitTests/Shared/TaskSnapshot.swift`).

/// Einstellungen der Aufgaben-Widgets in den App-Group-Defaults (`AppGroup.defaults`).
enum TaskWidgetSettings {
    /// Bool, fehlt = true: Abhaken im Widget nur entsperrt (Face ID). Schalter im Entwicklerbereich
    /// („Abhaken nur mit Face ID“). Das Widget wählt danach `CompleteTaskIntent` bzw. `CompleteTaskQuickIntent`;
    /// ändert sich der Wert, lädt die App das Widget neu.
    static let requireAuthKey = "paply.tasks.requireAuth"

    static func requiresAuth(_ defaults: UserDefaults?) -> Bool {
        defaults?.object(forKey: requireAuthKey) as? Bool ?? true
    }
}

/// Kennung der Erinnerung zur Uhrzeit einer Aufgabe: `task/<Gedanke>/<Aufgabe>` – gleich
/// `TaskReminderPlan.identifier` (PaplyKit; ein Test prüft das). Hier, damit auch die Widget-Erweiterung (ohne
/// PaplyKit) die Erinnerung beim Abhaken entfernen kann.
enum TaskReminderID {
    static func identifier(thoughtID: String, taskID: String) -> String {
        "task/" + thoughtID + "/" + taskID
    }
}

/// `tasks-snapshot.json` – was die Widgets über die Aufgaben wissen. Kein Diagnoseprotokoll, nur App Group.
struct TaskSnapshot: Codable, Sendable, Equatable {
    static let formatVersion = 1
    /// so viele Aufgaben stehen in `items` (Home mittel zeigt 4, eine Reserve für das Abhaken ohne App)
    static let maxItems = 5
    /// Obergrenze für `dueDates` (die frühesten zählen; mehr braucht keine Zahl auf dem Sperrbildschirm)
    static let maxDueDates = 500

    /// Eine der nächsten Aufgaben
    struct Item: Codable, Sendable, Equatable, Identifiable {
        var thoughtID: String
        var taskID: String
        var text: String
        var dueAt: Date?
        /// eine Uhrzeit wurde gesprochen (`TaskDueLabel.spokenTime`) – sonst zählt nur der Tag
        var hasTime: Bool
        /// Titel des Themas (nil = ohne Thema)
        var topicTitle: String?
        /// Themenfarbe als 0xRRGGBB (satter Mittelton im dunklen Schema, wie die Punkte der App); nil = ohne Thema
        var topicColor: UInt32?
        /// Themen-Symbol = `TopicIcon.rawValue` (Lucide-Schlüssel, z. B. "map-pin")
        var topicSymbol: String?

        var id: String { thoughtID + "/" + taskID }
    }

    var version: Int = TaskSnapshot.formatVersion
    /// geschrieben um
    var generatedAt: Date
    /// alle offenen Aufgaben (Gedanken außerhalb von „Zuletzt gelöscht“)
    var openCount: Int
    /// überfällig + heute, Stand `generatedAt` (Zahl am Reiter)
    var urgentCount: Int
    /// Zeitpunkte der heute (Tag von `generatedAt`) erledigten Aufgaben – die Zahl für den Ring. Als Zeitpunkte, damit
    /// das Widget nach Mitternacht von selbst bei 0 beginnt.
    var doneTodayAt: [Date]
    /// Fälligkeit aller offenen Aufgaben mit Datum, aufsteigend – damit das Widget „überfällig + heute“ für jeden
    /// späteren Zeitpunkt selbst zählt
    var dueDates: [Date]
    /// die nächsten bis zu `maxItems` offenen Aufgaben: überfällig, heute, demnächst (nach Zeitpunkt), dann ohne Datum
    var items: [Item]

    static func empty(at date: Date) -> TaskSnapshot {
        TaskSnapshot(generatedAt: date, openCount: 0, urgentCount: 0, doneTodayAt: [], dueDates: [], items: [])
    }

    /// Gleicher Inhalt, nur zu anderer Zeit geschrieben (dann das Widget nicht neu laden – kein Spam)
    func sameContent(as other: TaskSnapshot?) -> Bool {
        guard var other else { return false }
        other.generatedAt = generatedAt
        return other == self
    }
}

// MARK: - Zahlen zu einem Zeitpunkt

extension TaskSnapshot {
    struct Counts: Equatable, Sendable {
        /// alle offenen
        var open: Int
        /// überfällig + heute
        var urgent: Int
        /// heute erledigt
        var doneToday: Int

        /// Zahl auf dem Sperrbildschirm: heute fällige (inkl. überfälliger), sonst alle offenen
        var focus: Int { urgent > 0 ? urgent : open }

        /// Ring „heute erledigt / heute gesamt“ (gesamt = erledigt + noch fällig). Nichts fällig und nichts erledigt: 0.
        var progress: Double {
            let total = doneToday + urgent
            return total == 0 ? 0 : Double(doneToday) / Double(total)
        }
    }

    /// Zahlen zum Zeitpunkt `date` (Eintrag der Timeline): „heute“ und „erledigt heute“ beziehen sich auf seinen Tag.
    func counts(at date: Date, calendar: Calendar = .current) -> Counts {
        let endOfDay = Self.startOfNextDay(after: date, calendar: calendar)
        let urgent = min(openCount, dueDates.reduce(0) { $0 + ($1 < endOfDay ? 1 : 0) })
        let done = doneTodayAt.reduce(0) { $0 + (calendar.isDate($1, inSameDayAs: date) ? 1 : 0) }
        return Counts(open: openCount, urgent: urgent, doneToday: done)
    }

    /// Die nächste Aufgabe mit Uhrzeit, die am Tag von `date` noch kommt („3 fällig · nächste 15:00“)
    func nextTimed(after date: Date, calendar: Calendar = .current) -> Item? {
        items
            .filter { $0.hasTime && ($0.dueAt.map { $0 >= date && calendar.isDate($0, inSameDayAs: date) } ?? false) }
            .min { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
    }

    static func startOfNextDay(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }
}

// MARK: - Fälligkeit einer Zeile

extension TaskSnapshot.Item {
    struct Due: Equatable, Sendable {
        enum Day: Equatable, Sendable {
            /// vor `days` Tagen (1 = gestern)
            case past(days: Int)
            case today
            case tomorrow
            /// in 2–6 Tagen: Wochentag
            case weekday
            /// später: Datum
            case later
        }

        var date: Date
        var day: Day
        /// Uhrzeit anzeigen
        var showsTime: Bool
        /// überfällig: Tag vorbei oder – mit Uhrzeit – der Zeitpunkt vorbei
        var isLate: Bool
    }

    /// Fälligkeit aus Sicht von `now`; nil = ohne Datum
    func due(at now: Date, calendar: Calendar = .current) -> Due? {
        guard let dueAt else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueAt)).day ?? 0
        let day: Due.Day = switch days {
        case ..<0: .past(days: -days)
        case 0: .today
        case 1: .tomorrow
        case 2...6: .weekday
        default: .later
        }
        let late = days < 0 || (days == 0 && hasTime && dueAt <= now)
        return Due(date: dueAt, day: day, showsTime: hasTime, isLate: late)
    }
}

// MARK: - Abhaken im Widget

/// Eine im Widget abgehakte Aufgabe (`task-completions/<id>.json`). Die App wendet sie an und löscht die Datei.
struct TaskCompletion: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var thoughtID: String
    var taskID: String
    /// Zeitpunkt des Tipps – wird `doneAt` der Aufgabe
    var at: Date

    init(thoughtID: String, taskID: String, at: Date = Date(), id: String = UUID().uuidString) {
        self.id = id
        self.thoughtID = thoughtID
        self.taskID = taskID
        self.at = at
    }
}

extension TaskSnapshot {
    /// Sofort nach dem Tipp (optimistisch): Aufgabe raus, Zahlen eins weniger, Ring eins weiter. nil = die Aufgabe
    /// steht nicht (mehr) in der Momentaufnahme – z. B. ein zweiter Tipp auf dieselbe: dann ändert sich nichts.
    func completing(_ completion: TaskCompletion, calendar: Calendar = .current) -> TaskSnapshot? {
        guard let index = items.firstIndex(where: { $0.thoughtID == completion.thoughtID && $0.taskID == completion.taskID }) else {
            return nil
        }
        var next = self
        let item = next.items.remove(at: index)
        next.openCount = max(0, openCount - 1)
        if let due = item.dueAt {
            if let k = next.dueDates.firstIndex(where: { abs($0.timeIntervalSince(due)) < 0.5 }) { next.dueDates.remove(at: k) }
            if due < Self.startOfNextDay(after: generatedAt, calendar: calendar) { next.urgentCount = max(0, urgentCount - 1) }
        }
        next.doneTodayAt.append(completion.at)
        next.doneTodayAt.sort()
        return next
    }

    /// Warteschlange darüberlegen (was im Widget abgehakt, aber in der App noch nicht angewandt ist). Idempotent:
    /// Schon Entferntes bleibt unverändert.
    func applying(_ completions: [TaskCompletion], calendar: Calendar = .current) -> TaskSnapshot {
        completions.reduce(self) { $0.completing($1, calendar: calendar) ?? $0 }
    }
}

// MARK: - Timeline

extension TaskSnapshot {
    /// Zeitpunkte der Timeline ab `now`: jetzt, jede kommende Uhrzeit einer angezeigten Aufgabe (dann wird sie
    /// überfällig) und die nächsten `days` Mitternächte (Zahlen, „Morgen“ → „Heute“, Ring beginnt bei 0).
    /// Nach dem letzten Eintrag holt WidgetKit eine neue Timeline (`.atEnd`); jede Änderung in der App lädt ohnehin neu.
    func timelineDates(from now: Date, calendar: Calendar = .current, days: Int = 2, limit: Int = 24) -> [Date] {
        var dates: Set<Date> = [now]
        var horizon = now
        var midnight = now
        for _ in 0..<max(1, days) {
            midnight = Self.startOfNextDay(after: midnight, calendar: calendar)
            dates.insert(midnight)
            horizon = midnight
        }
        for item in items where item.hasTime {
            if let due = item.dueAt, due > now, due <= horizon { dates.insert(due) }
        }
        return Array(dates.sorted().prefix(max(1, limit)))
    }
}
