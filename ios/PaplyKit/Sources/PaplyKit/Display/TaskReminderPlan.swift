import Foundation

/// Eine geplante Mitteilung „Erinnerung zur Uhrzeit“ für eine Aufgabe.
public struct TaskReminder: Equatable, Sendable, Identifiable {
    /// stabil aus Gedanke + Aufgabe (`TaskReminderPlan.identifier`)
    public let id: String
    public let thoughtID: String
    public let taskID: String
    /// Zeitpunkt der Mitteilung: die Uhrzeit der Aufgabe, nach „In 1 Stunde“ der neue
    public let fireAt: Date
    /// Fälligkeit der Aufgabe, auf die sich die Mitteilung bezieht (bei „In 1 Stunde“ die ursprüngliche)
    public let dueAt: Date
    /// „In 1 Stunde“ gewählt
    public let snoozed: Bool
    /// Text der Aufgabe
    public let title: String
    /// „Thema · Titel des Gedankens“ (fehlt eins, nur das andere)
    public let body: String
    /// gruppiert die Mitteilungen eines Themas
    public let threadID: String

    public init(id: String, thoughtID: String, taskID: String, fireAt: Date, dueAt: Date, snoozed: Bool, title: String,
                body: String, threadID: String) {
        self.id = id
        self.thoughtID = thoughtID
        self.taskID = taskID
        self.fireAt = fireAt
        self.dueAt = dueAt
        self.snoozed = snoozed
        self.title = title
        self.body = body
        self.threadID = threadID
    }

    /// Alles, was die Mitteilung ausmacht. Gleiche Signatur = nichts neu planen.
    public var signature: String {
        [String(Int(fireAt.timeIntervalSince1970.rounded())), String(Int(dueAt.timeIntervalSince1970.rounded())),
         snoozed ? "s" : "-", threadID, title, body].joined(separator: "|")
    }
}

/// Erinnerung zur Uhrzeit (Mitteilung) – reine Logik, die App plant danach (`TaskReminders`).
///
/// Regeln:
/// - Eine Mitteilung bekommt nur eine offene Aufgabe eines Gedankens außerhalb von „Zuletzt gelöscht“ mit echter
///   Uhrzeit (`TaskDueLabel.spokenTime`: `dueHasTime`, für Altdaten dieselbe Regel wie die Liste) – genau zu dieser
///   Uhrzeit. Nur ein Tag: keine Mitteilung. Vergangenes wird nicht nachgeholt.
/// - „In 1 Stunde“ verschiebt nur die Mitteilung, nicht die Aufgabe. Es gilt, solange die Aufgabe offen ist und ihre
///   Fälligkeit dieselbe bleibt; eine neue Zeit ersetzt es. Die App speichert es dauerhaft (`keptSnoozes`): Es übersteht
///   Beta bzw. Erinnerungen aus und wieder an.
/// - iOS hält höchstens 64 geplante Mitteilungen: geplant werden die nächsten `limit` (50) nach Zeit.
/// - Abgleich: nur Neues und Geändertes planen, nicht mehr Gewünschtes entfernen, Gleiches unberührt lassen.
/// - Beta „Gedanken & Aufgaben“ aus: nichts gewünscht (alles Geplante fällt weg), zugestellte alle entfernen
///   (`removableDelivered`).
public enum TaskReminderPlan {
    public static let limit = 50
    public static let snoozeInterval: TimeInterval = 3_600
    /// Kennung aller Erinnerungen (andere Mitteilungen der App bleiben unberührt)
    public static let prefix = "task/"

    /// „In 1 Stunde“ verschoben (gespeichert; vor dem ersten Entsperren nur in der geplanten Mitteilung)
    public struct Snooze: Codable, Equatable, Sendable {
        public let fireAt: Date
        /// Fälligkeit der Aufgabe beim Verschieben
        public let dueAt: Date

        public init(fireAt: Date, dueAt: Date) {
            self.fireAt = fireAt
            self.dueAt = dueAt
        }
    }

    public struct Changes: Equatable, Sendable {
        /// neu oder geändert (gleiche Kennung ersetzt die alte Mitteilung)
        public var schedule: [TaskReminder] = []
        /// geplant, aber nicht mehr gewünscht
        public var remove: [String] = []
        /// geplant und unverändert
        public var unchanged = 0

        public var isEmpty: Bool { schedule.isEmpty && remove.isEmpty }
    }

    // MARK: Kennung

    /// `task/<Gedanke>/<Aufgabe>` – wie der App-Link `paply-ios://task/<Gedanke>/<Aufgabe>`
    public static func identifier(thoughtID: String, taskID: String) -> String {
        prefix + thoughtID + "/" + taskID
    }

    public static func parse(_ identifier: String) -> (thoughtID: String, taskID: String)? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let parts = identifier.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    // MARK: Auswahl

    /// Uhrzeit, zu der die Aufgabe erinnert (nil = keine Mitteilung, unabhängig von „jetzt“)
    public static func reminderTime(of task: ThoughtTask, in thought: Thought, calendar: Calendar = .current) -> Date? {
        guard thought.deletedAt == nil, !task.done else { return nil }
        return TaskDueLabel.spokenTime(of: task, calendar: calendar)
    }

    /// Die gewünschten Mitteilungen, früheste zuerst, höchstens `limit`.
    /// - Parameters:
    ///   - topic: aufgelöstes Thema eines Gedankens (Aliasse folgen dem Ziel), nil = ohne Thema
    ///   - snoozes: „In 1 Stunde“ nach Kennung
    public static func reminders(thoughts: [Thought], topic: (Thought) -> Topic?, snoozes: [String: Snooze] = [:],
                                 now: Date, limit: Int = limit, calendar: Calendar = .current) -> [TaskReminder] {
        var result: [TaskReminder] = []
        var seen: Set<String> = []
        for thought in thoughts {
            for task in thought.tasks {
                guard let due = reminderTime(of: task, in: thought, calendar: calendar) else { continue }
                let id = identifier(thoughtID: thought.id, taskID: task.id)
                guard seen.insert(id).inserted else { continue }
                var fireAt: Date?
                var snoozed = false
                if let snooze = snoozes[id], applies(snooze, due: due, now: now) {
                    fireAt = snooze.fireAt
                    snoozed = true
                } else if due > now {
                    fireAt = due
                }
                guard let fireAt else { continue }
                let resolved = topic(thought)
                result.append(TaskReminder(id: id, thoughtID: thought.id, taskID: task.id, fireAt: fireAt, dueAt: due,
                                           snoozed: snoozed, title: title(task), body: body(thought, topic: resolved),
                                           threadID: threadID(resolved)))
            }
        }
        result.sort { $0.fireAt != $1.fireAt ? $0.fireAt < $1.fireAt : $0.id < $1.id }
        return Array(result.prefix(max(0, limit)))
    }

    /// Gibt es eine offene Aufgabe mit Uhrzeit in der Zukunft? (Karte „Bei Uhrzeit erinnern?“)
    public static func hasUpcoming(thoughts: [Thought], now: Date, calendar: Calendar = .current) -> Bool {
        thoughts.contains { thought in
            thought.tasks.contains { task in
                guard let due = reminderTime(of: task, in: thought, calendar: calendar) else { return false }
                return due > now
            }
        }
    }

    // MARK: Abgleich

    /// Alt (geplant: Kennung → Stempel) gegen neu (gewünscht). Stempel = `signature + salt`; `salt` trägt, was die App
    /// zusätzlich in die Mitteilung schreibt (Dringlichkeit, Zeitzone) – ändert es sich, wird alles neu geplant.
    public static func changes(current: [String: String], desired: [TaskReminder], salt: String = "") -> Changes {
        var changes = Changes()
        var wanted: Set<String> = []
        for reminder in desired {
            wanted.insert(reminder.id)
            if current[reminder.id] == reminder.signature + salt {
                changes.unchanged += 1
            } else {
                changes.schedule.append(reminder)
            }
        }
        changes.remove = current.keys.filter { !wanted.contains($0) }.sorted()
        return changes
    }

    /// Schon zugestellte Mitteilungen, deren Aufgabe erledigt, gelöscht oder im Papierkorb ist (bzw. deren Gedanke).
    /// `thoughts` = alle bekannten Gedanken; fehlt eine Aufgabe darin, gilt sie als gelöscht.
    public static func stale(delivered ids: [String], thoughts: [Thought]) -> [String] {
        var open: Set<String> = []
        for thought in thoughts where thought.deletedAt == nil {
            for task in thought.tasks where !task.done {
                open.insert(identifier(thoughtID: thought.id, taskID: task.id))
            }
        }
        return ids.filter { parse($0) != nil && !open.contains($0) }
    }

    /// Schon zugestellte Erinnerungen, die weg sollen. Beta „Gedanken & Aufgaben“ aus (`featureOn` = false): alle
    /// Erinnerungen (`task/…`), auch die offener Aufgaben; an: nur die veralteten (`stale`). Andere Mitteilungen der
    /// App (z. B. `test/…`) bleiben immer.
    public static func removableDelivered(_ ids: [String], thoughts: [Thought], featureOn: Bool) -> [String] {
        featureOn ? stale(delivered: ids, thoughts: thoughts) : ids.filter { parse($0) != nil }
    }

    // MARK: „In 1 Stunde“

    /// Was die App über die Aufgabe weiß, wenn „In 1 Stunde“ kommt (vielleicht im Hintergrund, Gedanken noch nicht gelesen)
    public struct SnoozeFacts: Equatable, Sendable {
        /// Gedanken, sobald gelesen; nil = noch nicht geladen
        public var thoughts: [Thought]?
        /// schon zum Abhaken vorgemerkt (Warteschlange von Widget und Mitteilung, auch die vor dem Entsperren)
        public var queued: Bool
        /// steht offen in der Momentaufnahme der Widgets; nil = nicht lesbar. Fehlen heißt nichts (dort stehen nur die
        /// nächsten fünf).
        public var inSnapshot: Bool?
        /// vor dem ersten Entsperren nach einem Neustart: Seit dem Planen konnte nur „Erledigt“ aus einer Mitteilung etwas
        /// ändern – und das steht in `queued`
        public var locked: Bool

        public init(thoughts: [Thought]?, queued: Bool, inSnapshot: Bool?, locked: Bool) {
            self.thoughts = thoughts
            self.queued = queued
            self.inSnapshot = inSnapshot
            self.locked = locked
        }
    }

    /// Darf „In 1 Stunde“ neu planen? Nur für eine offene Aufgabe: vorgemerkt, erledigt, gelöscht oder im Papierkorb →
    /// nein. Ohne geladene Gedanken entscheidet die Momentaufnahme; im Zweifel nicht neu planen (lieber keine Mitteilung
    /// zu einer erledigten Aufgabe). Ausnahme vor dem ersten Entsperren: Dann gilt der Stand vom Planen.
    public static func maySnooze(thoughtID: String, taskID: String, facts: SnoozeFacts) -> Bool {
        if facts.queued { return false }
        if let thoughts = facts.thoughts {
            guard let thought = thoughts.first(where: { $0.id == thoughtID }), thought.deletedAt == nil,
                  let task = thought.tasks.first(where: { $0.id == taskID }) else { return false }
            return !task.done
        }
        if facts.locked { return true }
        return facts.inSnapshot == true
    }

    /// Neuer Zeitpunkt nach „In 1 Stunde“ (auf ganze Sekunden)
    public static func snoozed(from now: Date) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970 + snoozeInterval).rounded(.down))
    }

    /// Gilt das Verschieben noch? Nur für dieselbe Fälligkeit (Sekundenbruchteile vom Speichern zählen nicht) und
    /// solange der neue Zeitpunkt in der Zukunft liegt.
    static func applies(_ snooze: Snooze, due: Date, now: Date) -> Bool {
        abs(snooze.dueAt.timeIntervalSince(due)) < 1 && snooze.fireAt > now
    }

    /// Verschobene Erinnerungen, die gespeichert bleiben – Eingabe für `reminders(snoozes:)`, unabhängig davon, ob
    /// gerade geplant werden darf (Beta oder Erinnerungen aus: Sie bleiben und gelten beim Einschalten wieder).
    /// - `stored`: gespeicherte; `pending`: aus geplanten Mitteilungen gelesene (so kommt ein „In 1 Stunde“ vor dem
    ///   ersten Entsperren in den Speicher). Je Kennung gilt das spätere Verschieben.
    /// - Weg fallen: abgelaufene, fremde Kennungen und – mit geladenen Gedanken (`thoughts`) – solche, deren Aufgabe
    ///   erledigt, gelöscht oder im Papierkorb ist oder eine neue Zeit hat. `thoughts` nil (noch nicht geladen): nur
    ///   Abgelaufenes fällt weg.
    public static func keptSnoozes(stored: [String: Snooze], pending: [String: Snooze] = [:], thoughts: [Thought]?,
                                   now: Date, calendar: Calendar = .current) -> [String: Snooze] {
        var merged = stored
        for (id, snooze) in pending where merged[id].map({ snooze.fireAt > $0.fireAt }) ?? true {
            merged[id] = snooze
        }
        merged = merged.filter { parse($0.key) != nil && $0.value.fireAt > now }
        guard let thoughts else { return merged }
        var due: [String: Date] = [:]
        for thought in thoughts {
            for task in thought.tasks {
                let id = identifier(thoughtID: thought.id, taskID: task.id)
                // erste Fundstelle zählt (wie `reminders`)
                guard due[id] == nil, merged[id] != nil, let time = reminderTime(of: task, in: thought, calendar: calendar)
                else { continue }
                due[id] = time
            }
        }
        return merged.filter { id, snooze in due[id].map { applies(snooze, due: $0, now: now) } ?? false }
    }

    // MARK: Inhalt

    static func title(_ task: ThoughtTask) -> String {
        task.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func body(_ thought: Thought, topic: Topic?) -> String {
        let parts = [topic?.title, thought.title].compactMap { value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        return parts.joined(separator: " · ")
    }

    static func threadID(_ topic: Topic?) -> String {
        "paply.topic." + (topic?.id ?? "none")
    }
}
