import Foundation

/// Reiter „Aufgaben“: alle Aufgaben aller Gedanken außerhalb von „Zuletzt gelöscht“, nach Fälligkeit gegliedert.
///
/// Regeln:
/// - Jede offene Aufgabe steht in genau einer Gruppe – ohne Obergrenze: Überfällig (Tag vor heute), Heute,
///   Demnächst (mit Datum, ab morgen), Irgendwann (ohne Datum).
/// - Überfällig, Heute und Demnächst nach Zeitpunkt (früheste zuerst); Irgendwann in der Reihenfolge der Eingabe
///   (neueste Gedanken zuerst, Aufgaben eines Gedankens in ihrer Reihenfolge). Gleichstände bleiben stabil.
/// - Erledigt: neueste zuerst; `recentlyDone` nur die der letzten `doneWindowDays` Kalendertage (inkl. heute),
///   `allDone` alle (ohne Zeitpunkt ganz am Ende).
/// - Die Zahl am Reiter (`urgentCount`) zählt Überfällige und Heutige.
public struct TaskAgenda: Sendable {
    public struct Item: Sendable, Identifiable {
        public let task: ThoughtTask
        public let thought: Thought
        /// Gedanke + Aufgabe: eindeutig, selbst wenn zwei Gedanken einmal dieselbe Aufgaben-ID trügen (eine doppelte
        /// ID ließe Zeilen einer Liste verschwinden)
        public var id: String { thought.id + "/" + task.id }

        public init(task: ThoughtTask, thought: Thought) {
            self.task = task
            self.thought = thought
        }
    }

    public enum Group: String, Sendable, CaseIterable {
        case overdue, today, upcoming, someday
    }

    public private(set) var overdue: [Item] = []
    public private(set) var today: [Item] = []
    public private(set) var upcoming: [Item] = []
    public private(set) var someday: [Item] = []
    /// erledigt in den letzten `doneWindowDays` Kalendertagen, neueste zuerst
    public private(set) var recentlyDone: [Item] = []
    /// alle erledigten, neueste zuerst
    public private(set) var allDone: [Item] = []

    public init(thoughts: [Thought], now: Date = Date(), calendar: Calendar = .current, doneWindowDays: Int = 7) {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
        let doneSince = calendar.date(byAdding: .day, value: -max(0, doneWindowDays - 1), to: startOfToday) ?? startOfToday
        var dated: [Group: [(item: Item, at: Date, order: Int)]] = [:]
        var done: [(item: Item, at: Date?, order: Int)] = []
        var order = 0
        for thought in thoughts where thought.deletedAt == nil {
            for task in thought.tasks {
                defer { order += 1 }
                let item = Item(task: task, thought: thought)
                if task.done {
                    done.append((item, task.doneAt, order))
                    continue
                }
                guard let due = task.dueAt else {
                    someday.append(item)
                    continue
                }
                let group: Group = due < startOfToday ? .overdue : (due < startOfTomorrow ? .today : .upcoming)
                dated[group, default: []].append((item, due, order))
            }
        }
        func byDate(_ group: Group) -> [Item] {
            (dated[group] ?? []).sorted { $0.at != $1.at ? $0.at < $1.at : $0.order < $1.order }.map(\.item)
        }
        overdue = byDate(.overdue)
        today = byDate(.today)
        upcoming = byDate(.upcoming)
        let sortedDone = done.sorted { a, b in
            switch (a.at, b.at) {
            case let (x?, y?) where x != y: x > y
            case (_?, nil): true
            case (nil, _?): false
            default: a.order < b.order
            }
        }
        allDone = sortedDone.map(\.item)
        recentlyDone = sortedDone.filter { ($0.at ?? .distantPast) >= doneSince }.map(\.item)
    }

    public func items(_ group: Group) -> [Item] {
        switch group {
        case .overdue: overdue
        case .today: today
        case .upcoming: upcoming
        case .someday: someday
        }
    }

    /// alle offenen Aufgaben
    public var openCount: Int { overdue.count + today.count + upcoming.count + someday.count }

    /// Zahl am Reiter: überfällig + heute
    public var urgentCount: Int { overdue.count + today.count }

    /// Gruppe einer offenen Aufgabe nach ihrem Zeitpunkt
    public static func group(dueAt: Date?, now: Date, calendar: Calendar = .current) -> Group {
        guard let dueAt else { return .someday }
        let startOfToday = calendar.startOfDay(for: now)
        if dueAt < startOfToday { return .overdue }
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
        return dueAt < startOfTomorrow ? .today : .upcoming
    }

    /// Nur die Zahl am Reiter, ohne Listen zu bauen
    public static func urgentCount(thoughts: [Thought], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
        var count = 0
        for thought in thoughts where thought.deletedAt == nil {
            for task in thought.tasks where !task.done {
                if let due = task.dueAt, due < startOfTomorrow { count += 1 }
            }
        }
        return count
    }
}

/// Fälligkeit einer Aufgabe in der Sammelsicht.
///
/// Der Wortlaut der Aufnahme („morgen“, „bis Freitag“) bleibt, solange er stimmt – am Tag der Aufnahme. Danach
/// wäre er irreführend („morgen“ unter „Heute“), dann zeigt die Liste den Tag aus `dueAt`: heute, morgen, gestern,
/// Wochentag (in den nächsten 2–6 Tagen) oder Datum. Eine Uhrzeit nur, wenn der Wortlaut eine Zahl enthält und der
/// Zeitpunkt nicht auf 0:00 oder 12:00 liegt (die Vorgaben der Datumserkennung ohne Uhrzeit).
public enum TaskDueLabel: Equatable, Sendable {
    case wording(String)
    case today(time: Date?)
    case tomorrow(time: Date?)
    case yesterday(time: Date?)
    case weekday(Date, time: Date?)
    case date(Date, time: Date?)

    public static func make(task: ThoughtTask, recordedAt: Date, now: Date = Date(),
                            calendar: Calendar = .current) -> TaskDueLabel? {
        let hint = task.dueHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wording = (hint?.isEmpty ?? true) ? nil : hint
        guard let due = task.dueAt else { return wording.map(TaskDueLabel.wording) }
        if let wording, calendar.isDate(recordedAt, inSameDayAs: now) { return .wording(wording) }
        let time: Date? = {
            guard let wording, wording.contains(where: \.isNumber) else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: due)
            let hour = parts.hour ?? 0, minute = parts.minute ?? 0
            return minute == 0 && (hour == 0 || hour == 12) ? nil : due
        }()
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return .today(time: time)
        case 1: return .tomorrow(time: time)
        case -1: return .yesterday(time: time)
        case 2...6: return .weekday(due, time: time)
        default: return .date(due, time: time)
        }
    }
}
