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
}
