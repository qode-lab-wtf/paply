import Foundation

/// Gemerkte Plätze der Themen auf der Karte: kleine JSON-Datei, atomar geschrieben.
///
///     {"anchors":{"t_…":{"x":-12.5,"y":40}},"version":1}
///
/// Lesen unterscheidet „gibt es nicht“ (leere Karte, darf geschrieben werden) von „nicht lesbar“
/// (z. B. vor dem ersten Entsperren): Dann darf niemand die Datei überschreiben, sonst gingen die
/// Plätze verloren (`MapAnchorState`). Eine kaputte Datei zählt als leer – es sind nur Plätze, keine Inhalte.
public enum MapAnchorFile {
    public static let fileName = "map-anchors.json"

    public enum Loaded: Sendable, Equatable {
        case missing
        case anchors([String: MapAnchor])
        case unreadable
        case damaged
    }

    private struct Payload: Codable {
        var version: Int
        var anchors: [String: MapAnchor]
    }

    public static func load(from url: URL) -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return .damaged }
        let valid = payload.anchors.filter { $0.value.x.isFinite && $0.value.y.isFinite }
        return .anchors(valid)
    }

    /// Atomar (Nachbardatei, fsync, rename), Schlüssel sortiert – gleiche Plätze ergeben gleiche Bytes.
    public static func save(_ anchors: [String: MapAnchor], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Payload(version: 1, anchors: anchors.filter { $0.value.x.isFinite && $0.value.y.isFinite }))
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) { try FileSafety.createDirectory(directory) }
        try FileSafety.writeAtomically(data, to: url)
    }
}

/// Buchführung der gemerkten Plätze, ohne Datei und Zeitplan: wann die Karte zeichnet, wann sie Plätze merkt und
/// wann geschrieben werden darf. Die App (`MapAnchors`) hält sie auf dem Hauptthread und liest bzw. schreibt die Datei.
///
/// - `revision` steigt mit jedem Lesen. Eine Anordnung, die mit einer älteren Revision gerechnet wurde (etwa mit leeren
///   Plätzen, solange die Datei nicht lesbar war), darf danach nichts mehr merken – sonst überschriebe sie die eben
///   gelesenen Plätze.
/// - Gemerkt (und damit geschrieben) wird nur, wenn die Datei wirklich gelesen wurde oder es keine bzw. nur eine
///   kaputte gibt – nie nach `.unreadable`.
public struct MapAnchorState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// noch nicht angefragt
        case idle
        /// wartet auf das erste Entsperren
        case waiting
        /// gelesen (oder keine bzw. kaputte Datei): darf schreiben
        case loaded
        /// Datei da, aber nicht lesbar: nie schreiben
        case blocked(since: Date)
    }

    /// Was nach `prepare` zu tun ist
    public enum Next: Sendable, Equatable {
        case nothing
        /// lesen, sobald die Daten lesbar sind (nach dem ersten Entsperren)
        case readAfterUnlock
        case readNow
    }

    /// Nach einem Lesefehler frühestens so spät erneut lesen
    public static let retryInterval: TimeInterval = 5

    public private(set) var phase: Phase
    /// aktuelle Plätze (leer, solange nichts gelesen ist)
    public private(set) var anchors: [String: MapAnchor] = [:]
    /// steigt mit jedem Lesen
    public private(set) var revision = 0
    /// Plätze gelesen (oder stehen fest): erst dann zeichnet die Karte
    public private(set) var isReady: Bool

    /// `inMemory`: ohne Datei (Beispieldaten) – sofort bereit, merkt nur im Speicher.
    public init(inMemory: Bool) {
        phase = inMemory ? .loaded : .idle
        isReady = inMemory
    }

    /// Darf der gemerkte Stand geschrieben werden?
    public var mayWrite: Bool { phase == .loaded }

    /// Lesen anstoßen; mehrfach aufrufbar. Nach einem Lesefehler frühestens nach `retryInterval` erneut.
    public mutating func prepare(now: Date) -> Next {
        switch phase {
        case .idle:
            phase = .waiting
            return .readAfterUnlock
        case .blocked(let since) where now.timeIntervalSince(since) >= Self.retryInterval:
            return .readNow
        default:
            return .nothing
        }
    }

    /// Ergebnis eines Lesevorgangs übernehmen. Jedes Lesen entwertet alle vorher gerechneten Anordnungen.
    public mutating func apply(_ loaded: MapAnchorFile.Loaded, now: Date) {
        switch loaded {
        case .anchors(let stored):
            anchors = stored
            phase = .loaded
        case .missing, .damaged:
            anchors = [:]
            phase = .loaded
        case .unreadable:
            phase = .blocked(since: now)
        }
        revision &+= 1
        isReady = true
    }

    /// Neuer vollständiger Stand aus einer Anordnung, die mit den Plätzen der Revision `revision` gerechnet wurde.
    /// true = übernommen, bitte speichern. Abgelehnt: nicht gelesen, ältere Revision oder nichts geändert.
    public mutating func remember(_ new: [String: MapAnchor], revision: Int) -> Bool {
        guard phase == .loaded, revision == self.revision, new != anchors else { return false }
        anchors = new
        return true
    }
}
