import Foundation
import Testing
@testable import PaplyKit

@Suite("Gedanken-Landkarte: gemerkte Plätze")
struct MapAnchorFileTests {
    private func temporaryFile() -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paply-map-\(UUID().uuidString.prefix(8))", isDirectory: true)
        return (dir, dir.appendingPathComponent(MapAnchorFile.fileName))
    }

    @Test func roundTripIsExactAndSorted() throws {
        let (dir, url) = temporaryFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        let anchors = ["t_b": MapAnchor(x: -12.34, y: 56.78), "t_a": MapAnchor(x: 0.1, y: -0.2), "_none": MapAnchor(x: 300, y: 1e-3)]
        try MapAnchorFile.save(anchors, to: url) // legt den Ordner an
        #expect(MapAnchorFile.load(from: url) == .anchors(anchors))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.range(of: "\"_none\"")!.lowerBound < text.range(of: "\"t_a\"")!.lowerBound)
        // gleiche Plätze → gleiche Bytes
        let before = try Data(contentsOf: url)
        try MapAnchorFile.save(anchors, to: url)
        #expect(try Data(contentsOf: url) == before)
        // keine Reste angefangener Schreibvorgänge
        let rest = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(rest == [MapAnchorFile.fileName])
    }

    @Test func missingDamagedAndUnreadableAreDistinguished() throws {
        let (dir, url) = temporaryFile()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(MapAnchorFile.load(from: url) == .missing)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{nicht json".utf8).write(to: url)
        #expect(MapAnchorFile.load(from: url) == .damaged)
        try MapAnchorFile.save(["t": MapAnchor(x: 1, y: 2)], to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        #expect(MapAnchorFile.load(from: url) == .unreadable)
    }

    @Test func nonFiniteValuesAreNeverWritten() throws {
        let (dir, url) = temporaryFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        try MapAnchorFile.save(["ok": MapAnchor(x: 1, y: 1), "kaputt": MapAnchor(x: .infinity, y: 0)], to: url)
        #expect(MapAnchorFile.load(from: url) == .anchors(["ok": MapAnchor(x: 1, y: 1)]))
    }

    // MARK: Buchführung (`MapAnchorState`)

    /// Prüfer-Fall: Erst nicht lesbar (Karte zeichnet ohne Plätze, mit leeren Ankern gerechnet), dann gelingt das
    /// Nachladen. Die alte Anordnung darf danach nichts merken – der Mittelpunkt bleibt (400, 300), die Datei
    /// unverändert. Gespeichert wird nur, was wie in der App `remember` übernimmt.
    @Test func reloadInvalidatesOlderLayoutsAndTheFileStays() throws {
        let (dir, url) = temporaryFile()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let stored = ["t_a": MapAnchor(x: 400, y: 300)]
        try MapAnchorFile.save(stored, to: url)
        let before = try Data(contentsOf: url)
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        var state = MapAnchorState(inMemory: false)
        func rememberAndSave(_ anchors: [String: MapAnchor], revision: Int) throws -> Bool {
            guard state.remember(anchors, revision: revision) else { return false }
            #expect(state.mayWrite)
            try MapAnchorFile.save(state.anchors, to: url)
            return true
        }

        #expect(!state.isReady)
        let first = state.prepare(now: start), again = state.prepare(now: start)
        #expect(first == .readAfterUnlock && again == .nothing) // wartet schon
        #expect(try !rememberAndSave(["t_a": MapAnchor(x: 0, y: 0)], revision: state.revision)) // noch nicht gelesen

        // nicht lesbar: Karte zeichnet (ohne Plätze), gemerkt wird nie
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        state.apply(MapAnchorFile.load(from: url), now: start)
        #expect(state.phase == .blocked(since: start) && state.isReady && state.anchors.isEmpty && !state.mayWrite)
        let stale = state.revision
        #expect(try !rememberAndSave(["t_a": MapAnchor(x: 0, y: 0)], revision: stale))
        let early = state.prepare(now: start.addingTimeInterval(4))
        let retry = state.prepare(now: start.addingTimeInterval(MapAnchorState.retryInterval))
        #expect(early == .nothing && retry == .readNow)

        // Nachladen gelingt: neuer Stand, alte Anordnungen sind entwertet
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        state.apply(MapAnchorFile.load(from: url), now: start.addingTimeInterval(5))
        #expect(state.revision != stale && state.anchors == stored && state.mayWrite)
        #expect(try !rememberAndSave(["t_a": MapAnchor(x: 0, y: 0)], revision: stale)) // mit leeren Ankern gerechnet
        #expect(state.anchors == stored)
        #expect(try Data(contentsOf: url) == before)

        // mit dem aktuellen Stand gerechnet: wird gemerkt; unverändert: nichts zu tun
        let grown = ["t_a": MapAnchor(x: 400, y: 300), "t_b": MapAnchor(x: -80, y: 20)]
        #expect(try rememberAndSave(grown, revision: state.revision))
        #expect(MapAnchorFile.load(from: url) == .anchors(grown))
        #expect(try !rememberAndSave(grown, revision: state.revision))
        let later = state.prepare(now: start.addingTimeInterval(100))
        #expect(later == .nothing) // gelesen: nie erneut
    }

    @Test func missingOrDamagedFileMayBeWrittenAndInMemoryIsReadyAtOnce() {
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        for loaded in [MapAnchorFile.Loaded.missing, .damaged] {
            var state = MapAnchorState(inMemory: false)
            _ = state.prepare(now: start)
            state.apply(loaded, now: start)
            #expect(state.isReady && state.mayWrite && state.anchors.isEmpty)
            let taken = state.remember(["t": MapAnchor(x: 1, y: 2)], revision: state.revision)
            #expect(taken)
        }
        var memory = MapAnchorState(inMemory: true)
        let next = memory.prepare(now: start)
        let taken = memory.remember(["t": MapAnchor(x: 1, y: 2)], revision: memory.revision)
        #expect(memory.isReady && memory.mayWrite && next == .nothing && taken)
    }
}
