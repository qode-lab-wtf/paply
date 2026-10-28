import Foundation
import Testing
@testable import PaplyKit

// Aufgaben-Widgets: Momentaufnahme bauen (PaplyKit `TaskDigest`), Warteschlange anwenden (`TaskCompletionPlan`) und die
// Logik der Erweiterung (`TaskSnapshot` aus Shared/Core – über den Verweis `Shared/TaskSnapshot.swift` mitübersetzt,
// damit genau die Datei geprüft wird, die App und Widget benutzen).

@Suite("Aufgaben-Widgets")
struct TaskWidgetTests {
    /// feste Zone, damit Tagesgrenzen nicht vom Rechner abhängen
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }()

    /// Mi., 28.10.2026, 7:30 Berlin
    private var now: Date { date(2026, 10, 28, 7, 30) }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func task(_ id: String, due: Date? = nil, hint: String? = nil, hasTime: Bool? = nil, done: Bool = false,
                      doneAt: Date? = nil) -> ThoughtTask {
        ThoughtTask(id: id, text: "Aufgabe \(id)", dueHint: hint, dueAt: due, dueHasTime: hasTime, done: done, doneAt: doneAt, owner: .ai)
    }

    private func thought(_ id: String, created: Date? = nil, topic: String? = "t_a", tasks: [ThoughtTask], deleted: Date? = nil) -> Thought {
        Thought(id: id, createdAt: created ?? date(2026, 10, 26, 9), trigger: .app, state: .done, title: id, topicId: topic,
                tasks: tasks, deletedAt: deleted)
    }

    /// wie TaskWidgetSync.makeSnapshot (ohne Themenfarben)
    private func snapshot(_ digest: TaskDigest, at: Date) -> TaskSnapshot {
        TaskSnapshot(generatedAt: at, openCount: digest.openCount, urgentCount: digest.urgentCount, doneTodayAt: digest.doneToday,
                     dueDates: digest.dueDates,
                     items: digest.items.map {
                         TaskSnapshot.Item(thoughtID: $0.thoughtID, taskID: $0.taskID, text: $0.text, dueAt: $0.dueAt, hasTime: $0.hasTime,
                                           topicTitle: $0.topicID, topicColor: $0.topicID == nil ? nil : 0x5FB99A, topicSymbol: "wallet")
                     })
    }

    /// Alltag: überfällig, heute (mit/ohne Uhrzeit), morgen, später, ohne Datum, erledigt (heute/gestern), gelöscht
    private var sample: [Thought] {
        [
            thought("s_new", created: date(2026, 10, 28, 7), tasks: [
                task("heute8", due: date(2026, 10, 28, 8), hasTime: true),
                task("ohne1"),
                task("erledigtHeute", done: true, doneAt: date(2026, 10, 28, 6, 45)),
            ]),
            thought("s_old", created: date(2026, 10, 20, 9), tasks: [
                task("ueberfaellig", due: date(2026, 10, 27, 12)),
                task("heuteOhneZeit", due: date(2026, 10, 28, 12), hasTime: false),
                task("morgen", due: date(2026, 10, 29, 9), hasTime: true),
                task("spaeter", due: date(2026, 11, 12, 12)),
                task("ohne2"),
                task("erledigtGestern", done: true, doneAt: date(2026, 10, 27, 23, 59)),
            ]),
            thought("s_trash", tasks: [task("weg", due: date(2026, 10, 28, 9))], deleted: date(2026, 10, 27)),
        ]
    }

    // MARK: Momentaufnahme bauen

    @Test func digestListsNextTasksInAgendaOrder() {
        let digest = TaskDigest(thoughts: sample, now: now, calendar: calendar, limit: 5)
        #expect(digest.items.map(\.taskID) == ["ueberfaellig", "heute8", "heuteOhneZeit", "morgen", "spaeter"])
        #expect(digest.openCount == 7)
        #expect(digest.urgentCount == 3)
        #expect(digest.dueDates == [date(2026, 10, 27, 12), date(2026, 10, 28, 8), date(2026, 10, 28, 12), date(2026, 10, 29, 9),
                                    date(2026, 11, 12, 12)])
        // nur heute erledigte zählen für den Ring; der Papierkorb zählt nie
        #expect(digest.doneToday == [date(2026, 10, 28, 6, 45)])
        let all = TaskDigest(thoughts: sample, now: now, calendar: calendar, limit: 20)
        #expect(all.items.map(\.taskID) == ["ueberfaellig", "heute8", "heuteOhneZeit", "morgen", "spaeter", "ohne1", "ohne2"])
        #expect(!all.items.contains { $0.taskID == "weg" })
    }

    @Test func digestKnowsSpokenTimes() {
        let digest = TaskDigest(thoughts: sample, now: now, calendar: calendar, limit: 5)
        let hasTime = Dictionary(uniqueKeysWithValues: digest.items.map { ($0.taskID, $0.hasTime) })
        #expect(hasTime["heute8"] == true)
        #expect(hasTime["heuteOhneZeit"] == false)
        #expect(hasTime["ueberfaellig"] == false)
        // Altdaten ohne `dueHasTime`: der Wortlaut entscheidet (wie die Liste)
        let legacy = thought("s_l", tasks: [task("alt", due: date(2026, 10, 28, 8), hint: "morgen um 8 Uhr")])
        #expect(TaskDigest(thoughts: [legacy], now: now, calendar: calendar).items.first?.hasTime == true)
    }

    @Test func pendingCompletionsCountAsDone() {
        let tap = date(2026, 10, 28, 7, 20)
        let digest = TaskDigest(thoughts: sample, pending: [TaskKey(thoughtID: "s_new", taskID: "heute8"): tap], now: now,
                                calendar: calendar, limit: 5)
        #expect(!digest.items.contains { $0.taskID == "heute8" })
        #expect(digest.openCount == 6)
        #expect(digest.urgentCount == 2)
        #expect(digest.doneToday == [date(2026, 10, 28, 6, 45), tap])
        #expect(!digest.dueDates.contains(date(2026, 10, 28, 8)))
        // schon erledigte Aufgaben behalten ihren Zeitpunkt
        let again = TaskDigest(thoughts: sample, pending: [TaskKey(thoughtID: "s_new", taskID: "erledigtHeute"): tap], now: now,
                               calendar: calendar)
        #expect(again.doneToday == [date(2026, 10, 28, 6, 45)])
    }

    @Test func emptyAndAllDone() {
        let none = TaskDigest(thoughts: [], now: now, calendar: calendar)
        #expect(none.openCount == 0 && none.items.isEmpty && none.doneToday.isEmpty)
        let done = TaskDigest(thoughts: [thought("s_d", tasks: [task("a", done: true, doneAt: date(2026, 10, 28, 7))])], now: now,
                              calendar: calendar)
        #expect(done.openCount == 0)
        #expect(done.doneToday.count == 1)
    }

    // MARK: Warteschlange anwenden

    @Test func planAppliesOnlyOpenTasksOnce() {
        func request(_ id: String, _ thought: String, _ task: String, minute: Int) -> TaskCompletionPlan.Request {
            TaskCompletionPlan.Request(id: id, key: TaskKey(thoughtID: thought, taskID: task), at: date(2026, 10, 28, 7, minute))
        }
        let requests = [
            request("q2", "s_new", "heute8", minute: 2), // zweiter Tipp (doppelt)
            request("q1", "s_new", "heute8", minute: 1),
            request("q3", "s_old", "erledigtGestern", minute: 3), // schon erledigt
            request("q4", "s_trash", "weg", minute: 4), // Gedanke gelöscht
            request("q5", "s_gone", "x", minute: 5), // Gedanke fehlt
            request("q6", "s_old", "nichtda", minute: 6), // Aufgabe gelöscht
            request("q7", "s_old", "morgen", minute: 7),
        ]
        let plan = TaskCompletionPlan.make(requests, thoughts: sample)
        #expect(plan.apply.map(\.id) == ["q1", "q7"]) // frühester Tipp zählt
        #expect(Set(plan.ignored) == ["q2", "q3", "q4", "q5", "q6"])
        #expect(Set(plan.settled) == Set(requests.map(\.id)))
        // nach dem Anwenden: nochmal dieselbe Warteschlange → nichts mehr zu tun (idempotent)
        var after = sample
        for i in after.indices {
            for k in after[i].tasks.indices where plan.apply.contains(where: { $0.key == TaskKey(thoughtID: after[i].id, taskID: after[i].tasks[k].id) }) {
                after[i].tasks[k].done = true
            }
        }
        #expect(TaskCompletionPlan.make(requests, thoughts: after).apply.isEmpty)
        #expect(TaskCompletionPlan.make([], thoughts: sample) == TaskCompletionPlan.Result(apply: [], ignored: [], settled: []))
    }

    // MARK: Logik der Erweiterung (TaskSnapshot)

    @Test func countsFollowTheEntryDate() {
        let s = snapshot(TaskDigest(thoughts: sample, now: now, calendar: calendar), at: now)
        let atNow = s.counts(at: now, calendar: calendar)
        #expect(atNow == TaskSnapshot.Counts(open: 7, urgent: 3, doneToday: 1))
        #expect(atNow.focus == 3)
        #expect(abs(atNow.progress - 0.25) < 0.0001)
        // nach Mitternacht: „morgen“ ist heute fällig, der Ring beginnt bei 0
        let tomorrow = s.counts(at: date(2026, 10, 29, 0, 0), calendar: calendar)
        #expect(tomorrow == TaskSnapshot.Counts(open: 7, urgent: 4, doneToday: 0))
        // nichts fällig: Mitte zeigt alle offenen, Ring leer
        let calm = TaskSnapshot(generatedAt: now, openCount: 2, urgentCount: 0, doneTodayAt: [], dueDates: [date(2026, 11, 3)], items: [])
        #expect(calm.counts(at: now, calendar: calendar).focus == 2)
        #expect(calm.counts(at: now, calendar: calendar).progress == 0)
        // nichts mehr fällig, aber heute erledigt: Ring voll
        var full = calm
        full.doneTodayAt = [date(2026, 10, 28, 7)]
        #expect(full.counts(at: now, calendar: calendar).progress == 1)
    }

    @Test func completingInTheWidgetIsOptimisticAndIdempotent() throws {
        let s = snapshot(TaskDigest(thoughts: sample, now: now, calendar: calendar), at: now)
        let tap = TaskCompletion(thoughtID: "s_new", taskID: "heute8", at: date(2026, 10, 28, 7, 25), id: "q1")
        let next = try #require(s.completing(tap, calendar: calendar))
        #expect(!next.items.contains { $0.taskID == "heute8" })
        #expect(next.counts(at: now, calendar: calendar) == TaskSnapshot.Counts(open: 6, urgent: 2, doneToday: 2))
        // zweiter Tipp: keine Wirkung
        #expect(next.completing(tap, calendar: calendar) == nil)
        #expect(next.applying([tap, tap], calendar: calendar) == next)
        // Aufgabe ohne Datum: nur offen und Ring ändern sich
        let wide = snapshot(TaskDigest(thoughts: sample, now: now, calendar: calendar, limit: 20), at: now)
        let undated = try #require(wide.items.first { $0.dueAt == nil })
        let other = try #require(wide.completing(TaskCompletion(thoughtID: undated.thoughtID, taskID: undated.taskID, at: now),
                                                 calendar: calendar))
        #expect(other.counts(at: now, calendar: calendar) == TaskSnapshot.Counts(open: 6, urgent: 3, doneToday: 2))
        #expect(other.dueDates == wide.dueDates)
        // unbekannte Aufgabe (nicht unter den nächsten): nichts ändern
        #expect(s.completing(TaskCompletion(thoughtID: "s_x", taskID: "y", at: now), calendar: calendar) == nil)
    }

    @Test func optimisticSnapshotMatchesWhatTheAppWritesLater() throws {
        // Was das Widget sofort zeigt, muss zu dem passen, was die App nach dem Anwenden schreibt
        let s = snapshot(TaskDigest(thoughts: sample, now: now, calendar: calendar, limit: 5), at: now)
        let taps = [TaskCompletion(thoughtID: "s_old", taskID: "ueberfaellig", at: date(2026, 10, 28, 7, 21), id: "a"),
                    TaskCompletion(thoughtID: "s_new", taskID: "heute8", at: date(2026, 10, 28, 7, 22), id: "b")]
        let optimistic = s.applying(taps, calendar: calendar)
        let pending = Dictionary(uniqueKeysWithValues: taps.map { (TaskKey(thoughtID: $0.thoughtID, taskID: $0.taskID), $0.at) })
        let app = snapshot(TaskDigest(thoughts: sample, pending: pending, now: now, calendar: calendar, limit: 5), at: now)
        #expect(optimistic.openCount == app.openCount)
        #expect(optimistic.urgentCount == app.urgentCount)
        #expect(optimistic.doneTodayAt == app.doneTodayAt)
        #expect(optimistic.dueDates == app.dueDates)
        // die App rückt nach (bis zu 5), die Reihenfolge stimmt überein
        #expect(Array(app.items.prefix(optimistic.items.count)) == optimistic.items)
        #expect(app.items.count == 5)
    }

    @Test func dueLabelsAndLateness() throws {
        let s = snapshot(TaskDigest(thoughts: sample, now: now, calendar: calendar, limit: 20), at: now)
        func due(_ id: String, at: Date) throws -> TaskSnapshot.Item.Due? {
            try #require(s.items.first { $0.taskID == id }).due(at: at, calendar: calendar)
        }
        #expect(try due("ueberfaellig", at: now)?.day == .past(days: 1))
        #expect(try due("ueberfaellig", at: now)?.isLate == true)
        #expect(try due("heute8", at: now)?.day == .today)
        #expect(try due("heute8", at: now)?.isLate == false)
        // um 8:00 wird sie überfällig
        #expect(try due("heute8", at: date(2026, 10, 28, 8))?.isLate == true)
        // ohne Uhrzeit erst am nächsten Tag
        #expect(try due("heuteOhneZeit", at: date(2026, 10, 28, 23, 59))?.isLate == false)
        #expect(try due("heuteOhneZeit", at: date(2026, 10, 29, 0, 0))?.isLate == true)
        #expect(try due("morgen", at: now)?.day == .tomorrow)
        #expect(try due("morgen", at: now)?.showsTime == true)
        #expect(try due("morgen", at: date(2026, 10, 29, 0, 0))?.day == .today)
        #expect(try due("spaeter", at: now)?.day == .later)
        #expect(try due("spaeter", at: date(2026, 11, 8))?.day == .weekday)
        #expect(try due("ohne1", at: now) == nil)
    }

    @Test func timelineHasDueTimesAndMidnights() {
        let s = snapshot(TaskDigest(thoughts: sample, now: now, calendar: calendar, limit: 5), at: now)
        let dates = s.timelineDates(from: now, calendar: calendar)
        // jetzt, 8:00 (heute8 wird überfällig), 9:00 morgen (mit Uhrzeit), zwei Mitternächte; nichts ohne Uhrzeit
        #expect(dates == [now, date(2026, 10, 28, 8), date(2026, 10, 29, 0, 0), date(2026, 10, 29, 9), date(2026, 10, 30, 0, 0)])
        // Vergangenes zählt nicht
        let later = s.timelineDates(from: date(2026, 10, 28, 8, 30), calendar: calendar)
        #expect(!later.contains(date(2026, 10, 28, 8)))
        #expect(later.first == date(2026, 10, 28, 8, 30))
        #expect(s.timelineDates(from: now, calendar: calendar, limit: 2).count == 2)
        // Zeitumstellung: Mitternacht bleibt Mitternacht (29.3.2026, 2:00 → 3:00)
        let spring = TaskSnapshot.empty(at: date(2026, 3, 28, 22)).timelineDates(from: date(2026, 3, 28, 22), calendar: calendar)
        #expect(spring == [date(2026, 3, 28, 22), date(2026, 3, 29, 0, 0), date(2026, 3, 30, 0, 0)])
    }

    @Test func nextTimedIsTodayOnly() {
        let s = snapshot(TaskDigest(thoughts: sample, now: now, calendar: calendar, limit: 5), at: now)
        #expect(s.nextTimed(after: now, calendar: calendar)?.taskID == "heute8")
        // nach 8:00: die nächste mit Uhrzeit ist morgen – nicht „nächste“ in der Zeile
        #expect(s.nextTimed(after: date(2026, 10, 28, 8, 1), calendar: calendar) == nil)
        #expect(s.nextTimed(after: date(2026, 10, 29, 0, 0), calendar: calendar)?.taskID == "morgen")
    }

    @Test func roundTripAndSameContent() throws {
        let s = snapshot(TaskDigest(thoughts: sample, now: now, calendar: calendar), at: now.addingTimeInterval(0.123_456))
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(TaskSnapshot.self, from: data)
        #expect(back == s)
        var later = s
        later.generatedAt = s.generatedAt.addingTimeInterval(60)
        #expect(later.sameContent(as: s))
        later.openCount += 1
        #expect(!later.sameContent(as: s))
        #expect(!s.sameContent(as: nil))
        // Warteschlangen-Eintrag ebenso
        let c = TaskCompletion(thoughtID: "s_a", taskID: "k_b", at: now.addingTimeInterval(0.5))
        #expect(try JSONDecoder().decode(TaskCompletion.self, from: JSONEncoder().encode(c)) == c)
    }

    @Test func authSettingDefaultsToOn() {
        let suite = "paply.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(TaskWidgetSettings.requiresAuth(defaults))
        #expect(TaskWidgetSettings.requiresAuth(nil))
        defaults.set(false, forKey: TaskWidgetSettings.requireAuthKey)
        #expect(!TaskWidgetSettings.requiresAuth(defaults))
        #expect(TaskWidgetSettings.requireAuthKey == "paply.tasks.requireAuth")
    }
}
