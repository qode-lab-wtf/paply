import Foundation
import Testing
@testable import PaplyKit

@Suite("Gedanken-Landkarte: Eingang und Flüge")
struct MapInboxTests {
    private static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func at(_ s: TimeInterval) -> Date { Self.t0.addingTimeInterval(s) }
    /// gleich bis auf Rundung (Date rechnet in Sekunden seit 2001)
    private func same(_ a: Date?, _ b: Date) -> Bool { a.map { abs($0.timeIntervalSince(b)) < 1e-4 } ?? false }

    @Test("Zustand der Kugel: Läuft etwas, wird geordnet – sonst der dringendste Grund")
    func status() {
        #expect(MapInboxStatus.of([ThoughtState]()) == nil)
        #expect(MapInboxStatus.of([.done, .empty]) == nil)
        #expect(MapInboxStatus.of([.waitingNetwork, .structuring]) == .ordering)
        #expect(MapInboxStatus.of([.waitingNetwork, .waitingKey]) == .key)
        #expect(MapInboxStatus.of([.waitingLimit, .needsAttention, .waitingNetwork]) == .attention)
        #expect(MapInboxStatus.of([.waitingBudget, .waitingLimit]) == .limit)
        #expect(MapInboxStatus.of([.waitingBudget]) == .budget)
        #expect(MapInboxStatus.isPending(.transcribed) && MapInboxStatus.isPending(.needsAttention))
        #expect(!MapInboxStatus.isPending(.done) && !MapInboxStatus.isPending(.empty))
    }

    @Test("Erstes Melden: Wer schon fertig ist, fliegt nicht")
    func firstObservationOnlyRemembers() {
        var landings = MapLandings()
        landings.observe(pending: ["a"], now: at(0))
        #expect(landings.count(at: at(0)) == 1)
        #expect(landings.place(animate: true, now: at(0)) { _ in "t" }.isEmpty)
    }

    @Test("Fertig: zählt weiter, bis die Karte ihn zeigt, dann fliegt er – die Zahl sinkt beim Abflug")
    func landsAfterLayout() {
        var landings = MapLandings()
        landings.observe(pending: ["a"], now: at(0))
        landings.observe(pending: [], now: at(1))
        #expect(landings.awaiting["a"] == at(1))
        #expect(landings.count(at: at(1)) == 1) // springt nicht auf 0, solange die Karte noch rechnet
        // Karte noch ohne ihn
        #expect(landings.place(animate: true, now: at(1.1)) { _ in nil }.isEmpty)
        let flights = landings.place(animate: true, now: at(1.2)) { $0 == "a" ? "t1" : nil }
        #expect(flights.count == 1 && flights[0].topicID == "t1" && same(flights[0].launch, at(1.2)))
        #expect(landings.count(at: at(1.2)) == 0)
        #expect(landings.unlanded(at: at(1.5)).map(\.id) == ["a"])
        #expect(landings.unlanded(at: at(1.2 + MapLandings.duration + 0.001)).isEmpty)
        #expect(landings.isRunning(at: at(1.2 + MapLandings.duration + 0.5)))
        #expect(!landings.isRunning(at: at(1.2 + MapLandings.duration + MapLandings.glow + 0.001)))
        #expect(flights[0].progress(at: at(1.2 + MapLandings.duration / 2)).map { abs($0 - 0.5) < 1e-4 } == true)
        #expect(flights[0].progress(at: at(1.1)) == nil)
    }

    @Test("Mehrere gleichzeitig: nacheinander, in der Reihenfolge, in der sie fertig wurden")
    func severalFlyOneAfterAnother() {
        var landings = MapLandings()
        landings.observe(pending: ["a", "b", "c"], now: at(0))
        landings.observe(pending: ["a"], now: at(1)) // b, c fertig
        landings.observe(pending: [], now: at(1.5)) // a fertig
        #expect(landings.count(at: at(1.5)) == 3)
        let flights = landings.place(animate: true, now: at(2)) { _ in "t" }
        #expect(flights.map(\.id) == ["b", "c", "a"])
        let step = MapLandings.stagger
        #expect(same(flights[0].launch, at(2)) && same(flights[1].launch, at(2 + step)) && same(flights[2].launch, at(2 + 2 * step)))
        #expect(landings.count(at: at(2.001)) == 2)
        #expect(landings.count(at: at(2.001 + step)) == 1)
        #expect(landings.count(at: at(2.001 + 2 * step)) == 0)
        #expect(landings.launched(at: at(2.001 + step)) == 2)
        // ein später Fertiger reiht sich hinten an
        landings.observe(pending: ["d"], now: at(2.1))
        landings.observe(pending: [], now: at(2.2))
        let late = landings.place(animate: true, now: at(2.2)) { _ in "u" }
        #expect(late.count == 1 && same(late[0].launch, at(2 + 3 * step)))
        // nächstes Ereignis: der nächste Abflug (c)
        #expect(same(landings.nextEvent(after: at(2.2)), at(2 + step)))
    }

    @Test("Viele auf einmal: dichter hintereinander, über die Grenze hinaus ohne Flug")
    func manyAtOnce() {
        var landings = MapLandings()
        let ids = (0..<30).map { "g\($0)" }
        landings.observe(pending: Set(ids), now: at(0))
        landings.observe(pending: [], now: at(1))
        let flights = landings.place(animate: true, now: at(1)) { _ in "t" }
        #expect(flights.count == MapLandings.maxFlights)
        let last = flights.map(\.launch).max()!
        #expect(last.timeIntervalSince(at(1)) <= MapLandings.spread)
        #expect(landings.awaiting.isEmpty) // der Rest erscheint einfach
        #expect(landings.count(at: at(1)) == MapLandings.maxFlights - 1)
    }

    @Test("Ohne Bewegung: kein Flug, die Zahl sinkt sofort")
    func withoutMotion() {
        var landings = MapLandings()
        landings.observe(pending: ["a", "b"], now: at(0))
        landings.observe(pending: [], now: at(1))
        #expect(landings.place(animate: false, now: at(1)) { _ in "t" }.isEmpty)
        #expect(landings.count(at: at(1)) == 0)
        #expect(landings.flights.isEmpty)
    }

    @Test("Kommt nie auf die Karte (gelöscht): fällt nach einer Weile heraus")
    func patience() {
        var landings = MapLandings()
        landings.observe(pending: ["a"], now: at(0))
        landings.observe(pending: [], now: at(1))
        #expect(landings.count(at: at(2)) == 1)
        #expect(landings.nextEvent(after: at(2)).map { $0 > at(1 + MapLandings.patience) } == true)
        landings.observe(pending: [], now: at(1 + MapLandings.patience + 0.1))
        #expect(landings.count(at: at(1 + MapLandings.patience + 0.1)) == 0)
        #expect(landings.nextEvent(after: at(20)) == nil)
    }

    @Test("Wieder in Arbeit (Erneut ordnen): wartet nicht mehr, fliegt nicht")
    func backToWork() {
        var landings = MapLandings()
        landings.observe(pending: ["a", "b"], now: at(0))
        landings.observe(pending: [], now: at(1))
        _ = landings.place(animate: true, now: at(1)) { $0 == "a" ? "t" : nil }
        landings.observe(pending: ["a", "b"], now: at(1.1))
        #expect(landings.awaiting.isEmpty)
        #expect(landings.flights.isEmpty)
        #expect(landings.count(at: at(1.1)) == 2)
    }

    @Test("Aus dem Eingang gelöscht (Aufnahme ohne Sprache, Panel „Noch nicht geordnet“): sofort weg, kein Warten")
    func deletedWhilePending() {
        var landings = MapLandings()
        landings.observe(pending: ["a", "b"], now: at(0))
        landings.observe(pending: ["b"], existing: ["b"], now: at(1))
        #expect(landings.awaiting.isEmpty)
        #expect(landings.count(at: at(1)) == 1)
        landings.observe(pending: [], existing: [], now: at(2))
        #expect(landings.count(at: at(2)) == 0)
        #expect(landings.nextEvent(after: at(2)) == nil) // nichts zu wecken
    }

    @Test("Fertig, aber gelöscht, bevor die Karte ihn zeigt: fällt sofort heraus, nicht erst nach der Geduld")
    func deletedWhileAwaiting() {
        var landings = MapLandings()
        landings.observe(pending: ["a", "b"], now: at(0))
        landings.observe(pending: [], now: at(1))
        #expect(landings.count(at: at(1)) == 2)
        landings.observe(pending: [], existing: ["b"], now: at(1.5))
        #expect(Set(landings.awaiting.keys) == ["b"])
        #expect(landings.count(at: at(1.5)) == 1)
        #expect(landings.place(animate: true, now: at(1.6)) { _ in "t" }.map(\.id) == ["b"])
    }

    @Test("Gelöscht während des Flugs: Flug und Nachleuchten fallen weg, der Kreis zählt ihn nicht mehr")
    func deletedInFlight() {
        var landings = MapLandings()
        landings.observe(pending: ["a", "b"], now: at(0))
        landings.observe(pending: [], now: at(1))
        let flights = landings.place(animate: true, now: at(1)) { _ in "t" }
        #expect(flights.map(\.id) == ["a", "b"])
        // a ist in der Luft, b wartet noch auf den Abflug – beide gelöscht
        landings.observe(pending: [], existing: [], now: at(1.2))
        #expect(landings.flights.isEmpty)
        #expect(landings.unlanded(at: at(1.2)).isEmpty)
        #expect(landings.count(at: at(1.2)) == 0)
        #expect(!landings.isRunning(at: at(1.2)))
        #expect(landings.nextEvent(after: at(1.2)) == nil)
    }

    @Test("Nur einer von zwei Fliegenden gelöscht: der andere fliegt weiter wie geplant")
    func deletedInFlightKeepsOthers() {
        var landings = MapLandings()
        landings.observe(pending: ["a", "b"], now: at(0))
        landings.observe(pending: [], now: at(1))
        let flights = landings.place(animate: true, now: at(1)) { _ in "t" }
        landings.observe(pending: [], existing: ["b"], now: at(1.1))
        #expect(landings.flights.map(\.id) == ["b"])
        #expect(same(landings.flights.first?.launch, flights[1].launch))
        #expect(landings.count(at: at(1.1)) == 1) // b noch nicht abgeflogen
    }
}

private extension MapLandings {
    /// Melden, wenn alle bekannten Gedanken noch existieren
    mutating func observe(pending ids: Set<String>, now: Date) {
        let everyone = ids.union(pending).union(awaiting.keys).union(flights.map(\.id))
        observe(pending: ids, existing: everyone, now: now)
    }
}
