import Foundation
import Testing
@testable import PaplyKit

@Suite("Erinnerung zur Uhrzeit")
struct TaskReminderPlanTests {
    /// feste Zone, damit Uhrzeiten nicht vom Rechner abhängen
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    /// Mi., 28.10.2026, 15:30 Berlin
    private var now: Date { date(2026, 10, 28, 15, 30) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func task(_ id: String, due: Date? = nil, hint: String? = nil, hasTime: Bool? = true, done: Bool = false,
                      text: String? = nil) -> ThoughtTask {
        ThoughtTask(id: id, text: text ?? "Aufgabe \(id)", dueHint: hint, dueAt: due, dueHasTime: hasTime, done: done,
                    doneAt: done ? now : nil, owner: .ai)
    }

    private func thought(_ id: String, title: String? = "Post von Aram", topic: String? = "t_arbeit", tasks: [ThoughtTask],
                         deleted: Date? = nil) -> Thought {
        Thought(id: id, createdAt: date(2026, 10, 27, 9), trigger: .app, state: .done, title: title, topicId: topic,
                tasks: tasks, deletedAt: deleted)
    }

    private let topics: [String: Topic] = [
        "t_arbeit": Topic(id: "t_arbeit", title: "Arbeit", icon: .briefcase, owner: .ai),
    ]

    private func plan(_ thoughts: [Thought], snoozes: [String: TaskReminderPlan.Snooze] = [:], now: Date? = nil,
                      limit: Int = TaskReminderPlan.limit) -> [TaskReminder] {
        TaskReminderPlan.reminders(thoughts: thoughts, topic: { topics[$0.topicId ?? ""] }, snoozes: snoozes,
                                   now: now ?? self.now, limit: limit, calendar: calendar)
    }

    // MARK: Auswahl

    @Test func onlyOpenFutureTasksWithSpokenTime() {
        let tomorrow8 = date(2026, 10, 29, 8)
        let tasks = [
            task("k_ja", due: tomorrow8),
            task("k_nurTag", due: date(2026, 10, 29, 12), hasTime: false),
            task("k_ohneDatum", due: nil, hasTime: nil),
            task("k_erledigt", due: tomorrow8, done: true),
            task("k_vorbei", due: date(2026, 10, 28, 15, 0)),
            task("k_genauJetzt", due: now),
        ]
        let reminders = plan([thought("s_1", tasks: tasks), thought("s_weg", tasks: [task("k_papierkorb", due: tomorrow8)], deleted: now)])
        #expect(reminders.map(\.taskID) == ["k_ja"])
        let only = try! #require(reminders.first)
        #expect(only.fireAt == tomorrow8)
        #expect(only.dueAt == tomorrow8)
        #expect(!only.snoozed)
    }

    /// Altdaten ohne `dueHasTime`: dieselbe Regel wie die Liste (Wortlaut + `dueAt` genau auf der Uhrzeit)
    @Test func olderTasksFollowTheListRule() {
        let tasks = [
            task("k_acht", due: date(2026, 10, 29, 8), hint: "morgen um acht Uhr", hasTime: nil),
            // alte Auflösung: „um acht“ als 12:00 – keine Uhrzeit, also keine Mitteilung
            task("k_falsch", due: date(2026, 10, 29, 12), hint: "morgen um acht Uhr", hasTime: nil),
            task("k_morgen", due: date(2026, 10, 29, 12), hint: "morgen", hasTime: nil),
        ]
        #expect(plan([thought("s_1", tasks: tasks)]).map(\.taskID) == ["k_acht"])
        // gleiche Regel wie die Anzeige
        for task in tasks {
            let shown = TaskDueLabel.make(task: task, recordedAt: date(2026, 10, 20), now: now, calendar: calendar)
            let hasTime: Bool = switch shown {
            case .tomorrow(let time)?: time != nil
            default: false
            }
            #expect(hasTime == (task.id == "k_acht"), "\(task.id)")
        }
    }

    @Test func contentIsTaskTopicAndThought() {
        let due = date(2026, 10, 29, 8)
        let reminders = plan([
            thought("s_1", tasks: [task("k_1", due: due, text: "  Briefe bei Aram bearbeiten ")]),
            thought("s_2", title: nil, tasks: [task("k_2", due: due)]),
            thought("s_3", topic: nil, tasks: [task("k_3", due: due)]),
            thought("s_4", title: "  ", topic: nil, tasks: [task("k_4", due: due)]),
        ])
        let byTask = Dictionary(uniqueKeysWithValues: reminders.map { ($0.taskID, $0) })
        #expect(byTask["k_1"]?.title == "Briefe bei Aram bearbeiten")
        #expect(byTask["k_1"]?.body == "Arbeit · Post von Aram")
        #expect(byTask["k_1"]?.threadID == "paply.topic.t_arbeit")
        #expect(byTask["k_2"]?.body == "Arbeit")
        #expect(byTask["k_3"]?.body == "Post von Aram")
        #expect(byTask["k_3"]?.threadID == "paply.topic.none")
        #expect(byTask["k_4"]?.body == "")
    }

    @Test func upcomingCardNeedsAFutureTimedOpenTask() {
        #expect(TaskReminderPlan.hasUpcoming(thoughts: [thought("s_1", tasks: [task("k_1", due: date(2026, 10, 29, 8))])], now: now, calendar: calendar))
        #expect(!TaskReminderPlan.hasUpcoming(thoughts: [thought("s_1", tasks: [task("k_1", due: date(2026, 10, 28, 8))])], now: now, calendar: calendar))
        #expect(!TaskReminderPlan.hasUpcoming(thoughts: [thought("s_1", tasks: [task("k_1", due: date(2026, 10, 29, 8), hasTime: false)])], now: now, calendar: calendar))
        #expect(!TaskReminderPlan.hasUpcoming(thoughts: [thought("s_1", tasks: [task("k_1", due: date(2026, 10, 29, 8), done: true)])], now: now, calendar: calendar))
        #expect(!TaskReminderPlan.hasUpcoming(thoughts: [], now: now, calendar: calendar))
    }

    // MARK: Kennung

    @Test func identifiersAreStableAndReadable() {
        let id = TaskReminderPlan.identifier(thoughtID: "s_abc", taskID: "k_def")
        #expect(id == "task/s_abc/k_def")
        #expect(TaskReminderPlan.parse(id)?.thoughtID == "s_abc")
        #expect(TaskReminderPlan.parse(id)?.taskID == "k_def")
        #expect(TaskReminderPlan.parse("task/s_abc") == nil)
        #expect(TaskReminderPlan.parse("task//k") == nil)
        #expect(TaskReminderPlan.parse("andere/s/k") == nil)
        // gleiche Daten, später erneut geplant: gleiche Kennung und Signatur – nichts wird neu geplant
        let thoughts = [thought("s_1", tasks: [task("k_1", due: date(2026, 10, 29, 8))])]
        let first = plan(thoughts)
        let second = plan(thoughts, now: now.addingTimeInterval(600))
        #expect(first == second)
        #expect(first.map(\.id) == ["task/s_1/k_1"])
        // dieselbe Aufgaben-ID in zwei Gedanken: zwei Mitteilungen
        let twice = plan([thought("s_1", tasks: [task("k_x", due: date(2026, 10, 29, 8))]),
                          thought("s_2", tasks: [task("k_x", due: date(2026, 10, 29, 8))])])
        #expect(Set(twice.map(\.id)).count == 2)
    }

    // MARK: Abgleich

    @Test func reconcileAddsChangesAndRemoves() {
        let due = date(2026, 10, 29, 8)
        let old = plan([thought("s_1", tasks: [task("k_bleibt", due: due), task("k_zeit", due: due), task("k_text", due: due),
                                               task("k_weg", due: due)])])
        let current = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0.signature) })
        let new = plan([thought("s_1", tasks: [
            task("k_bleibt", due: due),
            task("k_zeit", due: date(2026, 10, 29, 9)), // Zeit geändert
            task("k_text", due: due, text: "Neuer Text"), // Text geändert
            task("k_neu", due: due), // neu angelegt
            // k_weg gelöscht
        ])])
        let changes = TaskReminderPlan.changes(current: current, desired: new)
        #expect(Set(changes.schedule.map(\.taskID)) == ["k_zeit", "k_text", "k_neu"])
        #expect(changes.remove == ["task/s_1/k_weg"])
        #expect(changes.unchanged == 1)
        // noch einmal mit dem neuen Stand: nichts zu tun
        let after = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0.signature) })
        let again = TaskReminderPlan.changes(current: after, desired: new)
        #expect(again.isEmpty)
        #expect(again.unchanged == new.count)
        // anderer Stempel der App (z. B. „dringlich“ umgeschaltet): alles neu, nichts entfernt
        let salted = TaskReminderPlan.changes(current: after, desired: new, salt: "|dringlich")
        #expect(salted.schedule.count == new.count)
        #expect(salted.remove.isEmpty)
        let stamped = Dictionary(uniqueKeysWithValues: new.map { ($0.id, $0.signature + "|dringlich") })
        #expect(TaskReminderPlan.changes(current: stamped, desired: new, salt: "|dringlich").isEmpty)
    }

    @Test func doneDeletedOrTrashedRemovesPlanned() {
        let due = date(2026, 10, 29, 8)
        let before = plan([thought("s_1", tasks: [task("k_1", due: due), task("k_2", due: due)]),
                           thought("s_2", tasks: [task("k_3", due: due)])])
        let current = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.signature) })
        let after = plan([thought("s_1", tasks: [task("k_1", due: due, done: true)]), // erledigt, k_2 gelöscht
                          thought("s_2", tasks: [task("k_3", due: due)], deleted: now)]) // Gedanke gelöscht
        let changes = TaskReminderPlan.changes(current: current, desired: after)
        #expect(changes.schedule.isEmpty)
        #expect(changes.remove == ["task/s_1/k_1", "task/s_1/k_2", "task/s_2/k_3"])
        // wiederhergestellt: kommt zurück
        let restored = plan([thought("s_2", tasks: [task("k_3", due: due)])])
        #expect(TaskReminderPlan.changes(current: [:], desired: restored).schedule.map(\.id) == ["task/s_2/k_3"])
    }

    @Test func deliveredOfDoneOrDeletedTasksAreStale() {
        let thoughts = [
            thought("s_1", tasks: [task("k_offen", due: date(2026, 10, 28, 8)), task("k_erledigt", due: date(2026, 10, 28, 8), done: true)]),
            thought("s_2", tasks: [task("k_papierkorb", due: date(2026, 10, 28, 8))], deleted: now),
        ]
        let delivered = ["task/s_1/k_offen", "task/s_1/k_erledigt", "task/s_1/k_geloescht", "task/s_2/k_papierkorb",
                         "task/s_weg/k_1", "fremd"]
        #expect(TaskReminderPlan.stale(delivered: delivered, thoughts: thoughts)
            == ["task/s_1/k_erledigt", "task/s_1/k_geloescht", "task/s_2/k_papierkorb", "task/s_weg/k_1"])
    }

    // MARK: „In 1 Stunde“ nur für offene Aufgaben

    @Test func snoozeOnlyForOpenTasks() {
        let due = date(2026, 10, 28, 16)
        let thoughts = [
            thought("s_1", tasks: [task("k_offen", due: due), task("k_erledigt", due: due, done: true)]),
            thought("s_weg", tasks: [task("k_papierkorb", due: due)], deleted: now),
        ]
        func may(_ thought: String, _ task: String, thoughts: [Thought]? = thoughts, queued: Bool = false,
                 inSnapshot: Bool? = nil, locked: Bool = false) -> Bool {
            TaskReminderPlan.maySnooze(thoughtID: thought, taskID: task,
                                       facts: .init(thoughts: thoughts, queued: queued, inSnapshot: inSnapshot, locked: locked))
        }
        // Gedanken geladen: nur die offene Aufgabe
        #expect(may("s_1", "k_offen"))
        #expect(!may("s_1", "k_erledigt"))
        #expect(!may("s_1", "k_geloescht"))
        #expect(!may("s_weg", "k_papierkorb"))
        #expect(!may("s_fehlt", "k_1"))
        // schon zum Abhaken vorgemerkt (Widget, „Erledigt“) – auch wenn das Modell sie noch offen führt
        #expect(!may("s_1", "k_offen", queued: true))
        #expect(!may("s_1", "k_offen", thoughts: nil, queued: true, locked: true))
        // Gedanken noch nicht geladen: Momentaufnahme entscheidet, im Zweifel nicht
        #expect(may("s_1", "k_offen", thoughts: nil, inSnapshot: true))
        #expect(!may("s_1", "k_offen", thoughts: nil, inSnapshot: false))
        #expect(!may("s_1", "k_offen", thoughts: nil, inSnapshot: nil))
        // vor dem ersten Entsperren: Stand vom Planen (nur die Warteschlange zählt)
        #expect(may("s_1", "k_offen", thoughts: nil, inSnapshot: nil, locked: true))
    }

    // MARK: Beta „Gedanken & Aufgaben“ aus

    @Test func betaOffRemovesEveryDeliveredReminderButNothingElse() {
        let thoughts = [
            thought("s_1", tasks: [task("k_offen", due: date(2026, 10, 28, 8)), task("k_erledigt", due: date(2026, 10, 28, 8), done: true)]),
        ]
        let delivered = ["task/s_1/k_offen", "task/s_1/k_erledigt", "task/s_weg/k_1", "test/s_x", "fremd", "task/kaputt"]
        // aus: alle Erinnerungen, auch die der offenen Aufgabe – Test-Mitteilungen und Fremdes bleiben
        #expect(TaskReminderPlan.removableDelivered(delivered, thoughts: thoughts, featureOn: false)
            == ["task/s_1/k_offen", "task/s_1/k_erledigt", "task/s_weg/k_1"])
        // an: wie bisher nur die veralteten
        #expect(TaskReminderPlan.removableDelivered(delivered, thoughts: thoughts, featureOn: true)
            == TaskReminderPlan.stale(delivered: delivered, thoughts: thoughts))
        #expect(TaskReminderPlan.removableDelivered(delivered, thoughts: thoughts, featureOn: true)
            == ["task/s_1/k_erledigt", "task/s_weg/k_1"])
    }

    @Test func betaOffPlansNothingAndOnRestoresAll() {
        // So gleicht TaskReminders ab: aus → nichts gewünscht; wieder an → dieselben Erinnerungen wie vorher
        let due = date(2026, 10, 29, 8)
        let thoughts = [thought("s_1", tasks: [task("k_1", due: due), task("k_2", due: date(2026, 10, 30, 9))])]
        let planned = plan(thoughts)
        #expect(planned.count == 2)
        let current = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0.signature + "|normal") })
        let off = TaskReminderPlan.changes(current: current, desired: [], salt: "|normal")
        #expect(off.schedule.isEmpty)
        #expect(off.remove == ["task/s_1/k_1", "task/s_1/k_2"])
        // Daten unverändert → beim Einschalten ist alles wieder da
        let on = TaskReminderPlan.changes(current: [:], desired: plan(thoughts), salt: "|normal")
        #expect(on.schedule == planned)
        #expect(on.remove.isEmpty)
    }

    // MARK: Grenze

    @Test func plansOnlyTheNextFiftyByTime() {
        // 80 Aufgaben in gemischter Reihenfolge über mehrere Gedanken
        var thoughts: [Thought] = []
        for i in 0..<8 {
            let tasks = (0..<10).map { k in
                let minutes = ((i * 10 + k) * 37) % 80 // jede Minute 0…79 genau einmal
                return task("k_\(i)_\(k)", due: now.addingTimeInterval(Double(minutes + 1) * 3_600))
            }
            thoughts.append(thought("s_\(i)", tasks: tasks))
        }
        let reminders = plan(thoughts)
        #expect(reminders.count == 50)
        #expect(reminders.map(\.fireAt) == reminders.map(\.fireAt).sorted())
        #expect(reminders.first?.fireAt == now.addingTimeInterval(3_600))
        #expect(reminders.last?.fireAt == now.addingTimeInterval(50 * 3_600))
        // die 51. rückt nach, sobald eine frühere erledigt ist
        var fewer = thoughts
        let earliest = reminders[0]
        let index = fewer.firstIndex { $0.id == earliest.thoughtID }!
        let k = fewer[index].tasks.firstIndex { $0.id == earliest.taskID }!
        fewer[index].tasks[k].done = true
        let next = plan(fewer)
        #expect(next.count == 50)
        #expect(next.last?.fireAt == now.addingTimeInterval(51 * 3_600))
        let current = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0.signature) })
        let changes = TaskReminderPlan.changes(current: current, desired: next)
        #expect(changes.remove == [earliest.id])
        #expect(changes.schedule.count == 1)
        #expect(changes.unchanged == 49)
    }

    @Test func limitIsConfigurable() {
        let tasks = (0..<5).map { task("k_\($0)", due: now.addingTimeInterval(Double($0 + 1) * 60)) }
        #expect(plan([thought("s_1", tasks: tasks)], limit: 3).map(\.taskID) == ["k_0", "k_1", "k_2"])
        #expect(plan([thought("s_1", tasks: tasks)], limit: 0).isEmpty)
    }

    // MARK: „In 1 Stunde“

    @Test func snoozeMovesTheReminderByOneHour() {
        let fired = date(2026, 10, 28, 15, 0)
        let snoozedAt = date(2026, 10, 28, 15, 2)
        let later = TaskReminderPlan.snoozed(from: snoozedAt.addingTimeInterval(0.7))
        #expect(later == date(2026, 10, 28, 16, 2))
        let thoughts = [thought("s_1", tasks: [task("k_1", due: fired)])]
        let id = TaskReminderPlan.identifier(thoughtID: "s_1", taskID: "k_1")
        // ohne Verschieben: vergangen, nichts geplant
        #expect(plan(thoughts).isEmpty)
        // verschoben: bleibt beim Abgleich erhalten, obwohl die Aufgabe selbst schon fällig war
        let snoozes = [id: TaskReminderPlan.Snooze(fireAt: later, dueAt: fired)]
        let reminders = plan(thoughts, snoozes: snoozes)
        #expect(reminders.count == 1)
        #expect(reminders.first?.fireAt == later)
        #expect(reminders.first?.dueAt == fired)
        #expect(reminders.first?.snoozed == true)
        // nach dem Zustellen nicht noch einmal
        #expect(plan(thoughts, snoozes: snoozes, now: later.addingTimeInterval(1)).isEmpty)
    }

    @Test func snoozeEndsWhenTheTaskChanges() {
        let fired = date(2026, 10, 28, 15, 0)
        let later = date(2026, 10, 28, 16, 2)
        let id = TaskReminderPlan.identifier(thoughtID: "s_1", taskID: "k_1")
        let snoozes = [id: TaskReminderPlan.Snooze(fireAt: later, dueAt: fired)]
        // erledigt
        #expect(plan([thought("s_1", tasks: [task("k_1", due: fired, done: true)])], snoozes: snoozes).isEmpty)
        // Gedanke gelöscht
        #expect(plan([thought("s_1", tasks: [task("k_1", due: fired)], deleted: now)], snoozes: snoozes).isEmpty)
        // neue Zeit: die gilt, nicht das Verschieben
        let newDue = date(2026, 10, 30, 9)
        let moved = plan([thought("s_1", tasks: [task("k_1", due: newDue)])], snoozes: snoozes)
        #expect(moved.first?.fireAt == newDue)
        #expect(moved.first?.snoozed == false)
        // Fälligkeit nur in Sekundenbruchteilen anders (Speichern und Laden): Verschieben bleibt
        let reloaded = plan([thought("s_1", tasks: [task("k_1", due: fired.addingTimeInterval(0.4))])], snoozes: snoozes)
        #expect(reloaded.first?.fireAt == later)
    }

    @Test func snoozedReminderIsRescheduledOnlyOnce() {
        let fired = date(2026, 10, 28, 15, 0)
        let later = date(2026, 10, 28, 16, 2)
        let thoughts = [thought("s_1", tasks: [task("k_1", due: fired)])]
        let id = TaskReminderPlan.identifier(thoughtID: "s_1", taskID: "k_1")
        let snoozes = [id: TaskReminderPlan.Snooze(fireAt: later, dueAt: fired)]
        let desired = plan(thoughts, snoozes: snoozes)
        // die verschobene Mitteilung ist schon geplant (mit derselben Signatur): nichts zu tun
        let current = [id: desired[0].signature]
        #expect(TaskReminderPlan.changes(current: current, desired: desired).isEmpty)
        // Verschoben und nicht verschoben unterscheiden sich in der Signatur
        let plain = TaskReminder(id: id, thoughtID: "s_1", taskID: "k_1", fireAt: later, dueAt: fired, snoozed: false,
                                 title: desired[0].title, body: desired[0].body, threadID: desired[0].threadID)
        #expect(plain.signature != desired[0].signature)
    }
}
