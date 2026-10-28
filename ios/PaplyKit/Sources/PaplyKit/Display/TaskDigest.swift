import Foundation

/// Gedanke + Aufgabe
public struct TaskKey: Hashable, Sendable {
    public let thoughtID: String
    public let taskID: String

    public init(thoughtID: String, taskID: String) {
        self.thoughtID = thoughtID
        self.taskID = taskID
    }
}

/// Inhalt der Aufgaben-Widgets (Sperrbildschirm, Home): Zahlen und die nächsten Aufgaben. Die App macht daraus die
/// Momentaufnahme in der App Group (`TaskSnapshot`, Shared/Core) – die Widget-Erweiterung kennt PaplyKit nicht.
///
/// Regeln:
/// - Gliederung und Reihenfolge wie der Reiter „Aufgaben“ (`TaskAgenda`): überfällig, heute, demnächst (je nach
///   Zeitpunkt), dann ohne Datum (neueste Gedanken zuerst). Die ersten `limit` sind die „nächsten“ Aufgaben.
/// - `openCount` = alle offenen, `urgentCount` = überfällig + heute (Zahl am Reiter).
/// - `doneToday` = Zeitpunkte der heute erledigten Aufgaben (für den Ring), aufsteigend.
/// - `dueDates` = Fälligkeiten aller offenen Aufgaben mit Datum, aufsteigend (das Widget zählt damit „heute“ selbst
///   für spätere Zeitpunkte, z. B. nach Mitternacht).
/// - `pending`: im Widget abgehakt, in der App noch nicht angewandt – gilt schon als erledigt (zum Zeitpunkt des Tipps).
///   So passt die Momentaufnahme der App immer zu dem, was das Widget nach dem Tipp zeigt.
/// - `hasTime` nach derselben Regel wie die Liste (`TaskDueLabel.spokenTime`).
public struct TaskDigest: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public let thoughtID: String
        public let taskID: String
        public let text: String
        public let dueAt: Date?
        public let hasTime: Bool
        /// gespeichertes Thema des Gedankens (Alias ungelöst)
        public let topicID: String?
    }

    public let openCount: Int
    public let urgentCount: Int
    public let doneToday: [Date]
    public let dueDates: [Date]
    public let items: [Item]

    public init(thoughts: [Thought], pending: [TaskKey: Date] = [:], now: Date = Date(), calendar: Calendar = .current,
                limit: Int = 5) {
        let patched = pending.isEmpty ? thoughts : thoughts.map { Self.completing($0, pending: pending) }
        let agenda = TaskAgenda(thoughts: patched, now: now, calendar: calendar, doneWindowDays: 1)
        let dated = agenda.overdue + agenda.today + agenda.upcoming
        openCount = agenda.openCount
        urgentCount = agenda.urgentCount
        dueDates = dated.compactMap(\.task.dueAt)
        let startOfToday = calendar.startOfDay(for: now)
        doneToday = agenda.recentlyDone.compactMap(\.task.doneAt).filter { $0 >= startOfToday }.sorted()
        items = (dated + agenda.someday).prefix(max(0, limit)).map { item in
            Item(thoughtID: item.thought.id, taskID: item.task.id, text: item.task.text, dueAt: item.task.dueAt,
                 hasTime: TaskDueLabel.spokenTime(of: item.task, calendar: calendar) != nil, topicID: item.thought.topicId)
        }
    }

    private static func completing(_ thought: Thought, pending: [TaskKey: Date]) -> Thought {
        var copy = thought
        for k in copy.tasks.indices where !copy.tasks[k].done {
            guard let at = pending[TaskKey(thoughtID: thought.id, taskID: copy.tasks[k].id)] else { continue }
            copy.tasks[k].done = true
            copy.tasks[k].doneAt = at
        }
        return copy
    }
}

/// Warteschlange der im Widget abgehakten Aufgaben anwenden – was abzuhaken ist und was danach aus der Warteschlange darf.
///
/// Regeln:
/// - Abgehakt wird nur eine offene Aufgabe eines vorhandenen Gedankens außerhalb von „Zuletzt gelöscht“. Gelöschte,
///   fehlende und schon erledigte werden ignoriert.
/// - Idempotent: Dieselbe Aufgabe zweimal in der Warteschlange wird einmal abgehakt (frühester Tipp zählt).
/// - Jeder angesehene Eintrag darf danach weg (`settled`) – auch ignorierte; die Aufrufer löschen erst, wenn das
///   Abhaken gespeichert ist.
/// - Nur mit vollständig geladenen Gedanken aufrufen – sonst sähe eine vorhandene Aufgabe wie gelöscht aus.
public enum TaskCompletionPlan {
    public struct Request: Sendable, Equatable {
        public let id: String
        public let key: TaskKey
        /// Zeitpunkt des Tipps
        public let at: Date

        public init(id: String, key: TaskKey, at: Date) {
            self.id = id
            self.key = key
            self.at = at
        }
    }

    public struct Result: Sendable, Equatable {
        /// abhaken, je Aufgabe einmal
        public var apply: [Request]
        /// ignoriert (fehlt, gelöscht, schon erledigt, doppelt)
        public var ignored: [String]
        /// alle angesehenen Einträge
        public var settled: [String]
    }

    public static func make(_ requests: [Request], thoughts: [Thought]) -> Result {
        let byID = Dictionary(thoughts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen: Set<TaskKey> = []
        var apply: [Request] = []
        var ignored: [String] = []
        for request in requests.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            guard seen.insert(request.key).inserted,
                  let thought = byID[request.key.thoughtID], thought.deletedAt == nil,
                  let task = thought.tasks.first(where: { $0.id == request.key.taskID }), !task.done
            else {
                ignored.append(request.id)
                continue
            }
            apply.append(request)
        }
        return Result(apply: apply, ignored: ignored, settled: requests.map(\.id))
    }
}
