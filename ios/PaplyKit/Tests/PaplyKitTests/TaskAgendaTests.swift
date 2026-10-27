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

    private func task(_ text: String, due: Date? = nil, hint: String? = nil, hasTime: Bool? = nil, done: Bool = false,
                      doneAt: Date? = nil) -> ThoughtTask {
        ThoughtTask(id: "k_" + text, text: text, dueHint: hint, dueAt: due, dueHasTime: hasTime, done: done, doneAt: doneAt, owner: .ai)
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

    /// Dritte Prüfrunde (Astra, Fable): Eine gesprochene Uhrzeit bleibt am Folgetag sichtbar – auch 0:00 und 12:00.
    @Test func spokenTimeIsKeptByTheResolver() {
        func label(_ hint: String, _ due: Date, _ hasTime: Bool) -> TaskDueLabel? {
            TaskDueLabel.make(task: task(hint, due: due, hint: hint, hasTime: hasTime), recordedAt: date(2026, 10, 26, 9),
                              now: now, calendar: calendar)
        }
        #expect(label("morgen um 12 Uhr", date(2026, 10, 27, 12), true) == .today(time: date(2026, 10, 27, 12)))
        #expect(label("morgen um 0 Uhr", date(2026, 10, 27, 0), true) == .today(time: date(2026, 10, 27, 0)))
        #expect(label("morgen um acht Uhr", date(2026, 10, 27, 8), true) == .today(time: date(2026, 10, 27, 8)))
        #expect(label("morgen um halb drei", date(2026, 10, 27, 14, 30), true) == .today(time: date(2026, 10, 27, 14, 30)))
        // ohne gesprochene Uhrzeit: Vorgabe der Erkennung (12:00, „früh“ 9:00) wird nie gezeigt
        #expect(label("morgen", date(2026, 10, 27, 12), false) == .today(time: nil))
        #expect(label("morgen früh", date(2026, 10, 27, 9), false) == .today(time: nil))
        // das Feld entscheidet, nicht der Wortlaut
        #expect(label("morgen um 15 Uhr", date(2026, 10, 27, 15), false) == .today(time: nil))
    }

    /// Ältere Aufgaben ohne `dueHasTime`: Der Wortlaut nennt eine Uhrzeit, und `dueAt` liegt genau auf ihr.
    @Test(arguments: [
        ("morgen um 12 Uhr", 12, 0, true),
        ("morgen um 0 Uhr", 0, 0, true),
        ("morgen um null Uhr", 0, 0, true),
        ("morgen um acht Uhr", 8, 0, true),
        ("morgen um halb drei", 14, 30, true),
        ("morgen um Viertel nach acht", 8, 15, true),
        ("tomorrow at 8", 8, 0, true),
        ("tomorrow at eight", 8, 0, true),
        // alte Auflösung ohne Zahlwörter: 12:00 statt 8:00 – lieber keine Uhrzeit als eine falsche
        ("morgen um acht Uhr", 12, 0, false),
        ("morgen um 7 Uhr früh", 19, 0, false),
        // keine Uhrzeit gesprochen
        ("morgen", 12, 0, false),
        ("morgen früh", 9, 0, false),
        ("morgen Mittag", 12, 0, false),
        ("am 27.", 12, 0, false),
    ])
    func olderTasksDecideByTheWording(hint: String, hour: Int, minute: Int, shown: Bool) {
        let due = date(2026, 10, 27, hour, minute)
        let label = TaskDueLabel.make(task: task("alt", due: due, hint: hint), recordedAt: date(2026, 10, 26, 9), now: now, calendar: calendar)
        #expect(label == .today(time: shown ? due : nil), "\(hint)")
    }

    @Test func midnightIsTheStartOfTheNextDay() {
        // „morgen um Mitternacht“ am 26. gesprochen = 28. um 0:00
        let midnight = task("Abgabe", due: date(2026, 10, 28, 0), hint: "morgen um Mitternacht")
        #expect(TaskDueLabel.make(task: midnight, recordedAt: date(2026, 10, 26, 9), now: now, calendar: calendar)
            == .tomorrow(time: date(2026, 10, 28, 0)))
    }
}

/// Uhrzeit im Zeitausdruck (`SpokenTime`) und Auflösung zu `dueAt` (`DueDate`) – dritte Prüfrunde.
@Suite("Fälligkeit: gesprochene Uhrzeit")
struct SpokenTimeTests {
    @Test(arguments: [
        ("morgen um 12 Uhr", 12, 0), ("um 0 Uhr", 0, 0), ("um null Uhr", 0, 0), ("um 24 Uhr", 24, 0),
        ("Mitternacht", 24, 0), ("tomorrow at midnight", 24, 0), ("at noon", 12, 0),
        ("um acht Uhr", 8, 0), ("um acht", 8, 0), ("gegen acht", 8, 0), ("um zwölf", 12, 0), ("um ein Uhr", 13, 0),
        ("acht Uhr dreißig", 8, 30), ("um 8 Uhr 30", 8, 30), ("8:30", 8, 30), ("8.30 Uhr", 8, 30), ("um 8.30", 8, 30),
        ("15:45", 15, 45), ("Freitag 10 Uhr", 10, 0),
        ("halb drei", 14, 30), ("halb eins", 12, 30), ("halb neun", 8, 30), ("Viertel nach acht", 8, 15),
        ("Viertel vor neun", 8, 45), ("dreiviertel neun", 8, 45), ("drei viertel neun", 8, 45), ("um zehn nach acht", 8, 10),
        ("um fünf vor zwölf", 11, 55),
        ("at 8", 8, 0), ("at eight", 8, 0), ("at eight thirty", 8, 30), ("8 pm", 20, 0), ("8pm", 20, 0), ("12 am", 0, 0),
        ("12 pm", 12, 0), ("8 a.m.", 8, 0), ("8 o'clock", 8, 0), ("half past seven tonight", 19, 30), ("quarter to nine", 8, 45),
        ("ten past eight", 8, 10),
        // Tageszeit legt die Hälfte fest; ohne sie wie der Detektor: 1–7 Uhr = nachmittags
        ("um 7 Uhr früh", 7, 0), ("morgen früh um halb acht", 7, 30), ("abends um 8", 20, 0), ("heute Abend um neun", 21, 0),
        ("um 2 Uhr nachts", 2, 0), ("um 11 Uhr nachts", 23, 0), ("um 2 Uhr mittags", 14, 0), ("um 3", 15, 0), ("um 8 am Freitag", 8, 0),
    ])
    func spokenClockIsRead(text: String, hour: Int, minute: Int) {
        #expect(SpokenTime.find(in: text)?.clock == SpokenTime.Clock(hour: hour, minute: minute), "\(text)")
    }

    @Test(arguments: ["morgen", "morgen früh", "abends", "morgen Mittag", "am 10.11.", "am 10.11.2026", "am achten",
                      "in zwei Wochen", "on the 5th", "bis Ende November", "nächste Woche", "um den 10. herum", "Viertel acht",
                      "zweimal", "next week"])
    func noClockWithoutOne(text: String) {
        #expect(SpokenTime.find(in: text) == nil, "\(text)")
    }

    @Test func datesBesideTheClockStayAbsolute() {
        #expect(SpokenTime.find(in: "am 10.11. um 9") == SpokenTime.Found(clock: .init(hour: 9, minute: 0), otherDigits: true))
        #expect(SpokenTime.find(in: "morgen um 15 Uhr")?.otherDigits == false)
    }

    // MARK: Auflösung (NSDataDetector + gesprochene Uhrzeit), in der Zeitzone des Rechners wie der Detektor

    private let calendar = Calendar.current

    private func resolved(_ hint: String, reference: Date = Date(), now: Date = Date()) -> DueDate.Resolved? {
        DueDate.resolved(hint, reference: reference, now: now, calendar: calendar)
    }

    private func dayOffset(_ date: Date, from reference: Date = Date()) -> Int? {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: date)).day
    }

    @Test(arguments: [
        ("morgen um 12 Uhr", 1, 12, 0), ("morgen um 0 Uhr", 1, 0, 0), ("morgen um acht Uhr", 1, 8, 0),
        ("morgen um halb drei", 1, 14, 30), ("morgen um Viertel nach acht", 1, 8, 15), ("tomorrow at 8", 1, 8, 0),
        ("tomorrow at eight", 1, 8, 0), ("morgen um 7 Uhr früh", 1, 7, 0), ("morgen abend um 8", 1, 20, 0),
        ("morgen um Mitternacht", 2, 0, 0), ("tomorrow at midnight", 2, 0, 0), ("morgen um 24 Uhr", 2, 0, 0),
        ("übermorgen um 10 Uhr", 2, 10, 0),
        // aus den Läufen p4/p4b (e26, n03)
        ("morgen um acht", 1, 8, 0), ("morgen um 10 Uhr", 1, 10, 0),
    ])
    func resolverSetsTheSpokenTime(hint: String, days: Int, hour: Int, minute: Int) throws {
        let due = try #require(resolved(hint), "\(hint)")
        #expect(due.hasTime, "\(hint)")
        #expect(dayOffset(due.date) == days, "\(hint)")
        let parts = calendar.dateComponents([.hour, .minute], from: due.date)
        #expect(parts.hour == hour && parts.minute == minute, "\(hint): \(parts)")
    }

    @Test(arguments: ["morgen", "morgen früh", "morgen Mittag", "Freitag", "tomorrow",
                      // aus den Läufen p4/E1 (n02, e06, e07)
                      "morgen am besten vormittags", "bis Mittwoch", "before Thursday"])
    func resolverWithoutSpokenTime(hint: String) throws {
        let due = try #require(resolved(hint), "\(hint)")
        #expect(!due.hasTime, "\(hint)")
    }

    /// Offline verarbeitet: „morgen um 15 Uhr“ gilt ab der Aufnahme – Tag und Uhrzeit (bisher galt der Ausdruck wegen
    /// der Ziffern als festes Datum und sprang auf den Tag nach dem Verarbeiten).
    @Test func relativeDayWithTimeFollowsTheRecording() throws {
        let processed = Date()
        let recorded = processed.addingTimeInterval(-2 * 86_400)
        let due = try #require(DueDate.resolved("morgen um 15 Uhr", reference: recorded, now: processed, calendar: calendar))
        #expect(dayOffset(due.date, from: recorded) == 1)
        #expect(calendar.component(.hour, from: due.date) == 15 && due.hasTime)
    }
}
