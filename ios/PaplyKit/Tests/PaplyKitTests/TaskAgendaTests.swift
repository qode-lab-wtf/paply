import Foundation
import Testing
@testable import PaplyKit

@Suite("Oberfläche: Reiter Aufgaben")
struct TaskAgendaTests {
    /// feste Zone, damit Tagesgrenzen nicht vom Rechner abhängen
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    /// Di., 27.10.2026, 15:30 Berlin
    private var now: Date { date(2026, 10, 27, 15, 30) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func task(_ text: String, due: Date? = nil, hint: String? = nil, done: Bool = false, doneAt: Date? = nil) -> ThoughtTask {
        ThoughtTask(id: "k_" + text, text: text, dueHint: hint, dueAt: due, done: done, doneAt: doneAt, owner: .ai)
    }

    private func thought(_ id: String, created: Date, tasks: [ThoughtTask], deleted: Date? = nil) -> Thought {
        Thought(id: id, createdAt: created, trigger: .app, state: .done, title: id, tasks: tasks, deletedAt: deleted)
    }

    @Test func everyOpenTaskAppearsExactlyOnce() {
        // viele Gedanken mit vielen Aufgaben in allen Lagen – nichts darf fehlen oder doppelt sein
        var thoughts: [Thought] = []
        var expected: Set<String> = []
        for i in 0..<120 {
            var tasks: [ThoughtTask] = []
            for k in 0..<(i % 7) {
                let id = "\(i)-\(k)"
                let due: Date? = switch (i + k) % 4 {
                case 0: nil
                case 1: now.addingTimeInterval(-Double(k + 1) * 86_400) // überfällig
                case 2: now.addingTimeInterval(Double(k) * 3_600 - 7_200) // heute
                default: now.addingTimeInterval(Double(k + 1) * 86_400) // demnächst
                }
                let done = (i + k) % 9 == 0
                tasks.append(task(id, due: due, done: done, doneAt: done ? now.addingTimeInterval(-Double(i) * 3_600) : nil))
                if !done { expected.insert("k_" + id) }
            }
            thoughts.append(thought("s_\(i)", created: now.addingTimeInterval(-Double(i) * 50_000), tasks: tasks))
        }
        let agenda = TaskAgenda(thoughts: thoughts, now: now, calendar: calendar)
        let shown = TaskAgenda.Group.allCases.flatMap { agenda.items($0).map(\.task.id) }
        #expect(shown.count == expected.count)
        #expect(Set(shown) == expected)
        #expect(agenda.openCount == expected.count)
        #expect(Set(agenda.allDone.map(\.task.id)).isDisjoint(with: expected))
    }

    @Test func sameTaskIDInTwoThoughtsStaysTwoRows() {
        // z. B. nach einem künftigen Aufteilen einer Aufnahme: beide Zeilen bleiben eigenständig
        let shared = task("gleich", due: now)
        let agenda = TaskAgenda(thoughts: [thought("s_1", created: now, tasks: [shared]), thought("s_2", created: now, tasks: [shared])],
                                now: now, calendar: calendar)
        #expect(agenda.today.count == 2)
        #expect(Set(agenda.today.map(\.id)).count == 2)
    }

    @Test func groupsFollowTheCalendarDay() {
        let tasks = [
            task("gestern spät", due: date(2026, 10, 26, 23, 59)),
            task("heute früh", due: date(2026, 10, 27, 0, 0)),
            task("heute abend", due: date(2026, 10, 27, 23, 59)),
            task("morgen", due: date(2026, 10, 28, 0, 0)),
            task("ohne"),
        ]
        let agenda = TaskAgenda(thoughts: [thought("s_a", created: now, tasks: tasks)], now: now, calendar: calendar)
        #expect(agenda.overdue.map(\.task.text) == ["gestern spät"])
        #expect(agenda.today.map(\.task.text) == ["heute früh", "heute abend"])
        #expect(agenda.upcoming.map(\.task.text) == ["morgen"])
        #expect(agenda.someday.map(\.task.text) == ["ohne"])
        #expect(agenda.urgentCount == 3)
        #expect(TaskAgenda.urgentCount(thoughts: [thought("s_a", created: now, tasks: tasks)], now: now, calendar: calendar) == 3)
        #expect(TaskAgenda.group(dueAt: date(2026, 10, 28, 0, 0), now: now, calendar: calendar) == .upcoming)
        #expect(TaskAgenda.group(dueAt: nil, now: now, calendar: calendar) == .someday)
    }

    @Test func deletedThoughtsAndDoneTasksAreNotOpen() {
        let trash = thought("s_trash", created: now, tasks: [task("weg", due: now)], deleted: now)
        let live = thought("s_live", created: now, tasks: [task("offen", due: now), task("fertig", due: now, done: true, doneAt: now)])
        let agenda = TaskAgenda(thoughts: [trash, live], now: now, calendar: calendar)
        #expect(agenda.today.map(\.task.text) == ["offen"])
        #expect(agenda.allDone.map(\.task.text) == ["fertig"])
        #expect(agenda.urgentCount == 1)
        #expect(TaskAgenda.urgentCount(thoughts: [trash, live], now: now, calendar: calendar) == 1)
    }

    @Test func orderIsByDateThenStable() {
        let early = date(2026, 10, 30, 9)
        let a = thought("s_new", created: now, tasks: [task("b2", due: early), task("x1"), task("x2")])
        let b = thought("s_old", created: now.addingTimeInterval(-86_400), tasks: [task("b1", due: early), task("a", due: date(2026, 10, 29)), task("y")])
        let agenda = TaskAgenda(thoughts: [a, b], now: now, calendar: calendar)
        // gleicher Zeitpunkt: Reihenfolge der Eingabe (neueste Gedanken zuerst)
        #expect(agenda.upcoming.map(\.task.text) == ["a", "b2", "b1"])
        // ohne Datum: neueste Gedanken zuerst, Aufgaben in ihrer Reihenfolge
        #expect(agenda.someday.map(\.task.text) == ["x1", "x2", "y"])
    }

    @Test func doneWindowIsSevenCalendarDays() {
        let tasks = [
            task("heute", done: true, doneAt: date(2026, 10, 27, 8)),
            task("vor 6 Tagen", done: true, doneAt: date(2026, 10, 21, 0, 1)),
            task("vor 7 Tagen", done: true, doneAt: date(2026, 10, 20, 23, 59)),
            task("ohne Zeitpunkt", done: true),
        ]
        let agenda = TaskAgenda(thoughts: [thought("s_d", created: now, tasks: tasks)], now: now, calendar: calendar)
        #expect(agenda.recentlyDone.map(\.task.text) == ["heute", "vor 6 Tagen"])
        #expect(agenda.allDone.map(\.task.text) == ["heute", "vor 6 Tagen", "vor 7 Tagen", "ohne Zeitpunkt"])
    }

    // MARK: Fälligkeit

    @Test func wordingStaysOnTheDayOfRecording() {
        let t = task("Arzt", due: date(2026, 10, 28, 12), hint: "morgen")
        #expect(TaskDueLabel.make(task: t, recordedAt: date(2026, 10, 27, 9), now: now, calendar: calendar) == .wording("morgen"))
    }

    @Test func staleWordingBecomesTheDay() {
        // gestern aufgenommen: „morgen“ ist heute
        let t = task("Arzt", due: date(2026, 10, 27, 12), hint: "morgen")
        #expect(TaskDueLabel.make(task: t, recordedAt: date(2026, 10, 26, 9), now: now, calendar: calendar) == .today(time: nil))
        let tomorrow = task("Bank", due: date(2026, 10, 28, 12), hint: "übermorgen")
        #expect(TaskDueLabel.make(task: tomorrow, recordedAt: date(2026, 10, 26), now: now, calendar: calendar) == .tomorrow(time: nil))
        let overdue = task("Miete", due: date(2026, 10, 26, 12), hint: "morgen")
        #expect(TaskDueLabel.make(task: overdue, recordedAt: date(2026, 10, 25), now: now, calendar: calendar) == .yesterday(time: nil))
        let friday = task("Flug", due: date(2026, 10, 30, 12), hint: "Freitag")
        #expect(TaskDueLabel.make(task: friday, recordedAt: date(2026, 10, 25), now: now, calendar: calendar)
            == .weekday(date(2026, 10, 30, 12), time: nil))
        let later = task("Steuer", due: date(2026, 11, 10, 12), hint: "am 10. November")
        #expect(TaskDueLabel.make(task: later, recordedAt: date(2026, 10, 20), now: now, calendar: calendar)
            == .date(date(2026, 11, 10, 12), time: nil))
    }

    @Test func timeOnlyWhenSpoken() {
        let spoken = task("Anruf", due: date(2026, 10, 27, 15), hint: "morgen um 15 Uhr")
        #expect(TaskDueLabel.make(task: spoken, recordedAt: date(2026, 10, 26), now: now, calendar: calendar)
            == .today(time: date(2026, 10, 27, 15)))
        // Vorgabe der Datumserkennung ohne Uhrzeit (12:00) – keine Uhrzeit zeigen
        let noon = task("Post", due: date(2026, 10, 27, 12), hint: "am 27.")
        #expect(TaskDueLabel.make(task: noon, recordedAt: date(2026, 10, 20), now: now, calendar: calendar) == .today(time: nil))
    }

    @Test func withoutDateOnlyTheWording() {
        #expect(TaskDueLabel.make(task: task("a", hint: "bald"), recordedAt: date(2026, 10, 1), now: now, calendar: calendar) == .wording("bald"))
        #expect(TaskDueLabel.make(task: task("b", hint: "  "), recordedAt: now, now: now, calendar: calendar) == nil)
        #expect(TaskDueLabel.make(task: task("c"), recordedAt: now, now: now, calendar: calendar) == nil)
    }
}
