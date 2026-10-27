import Foundation

/// Gemerkte Plätze der Themen auf der Karte: kleine JSON-Datei, atomar geschrieben.
///
///     {"anchors":{"t_…":{"x":-12.5,"y":40}},"version":1}
///
/// Lesen unterscheidet „gibt es nicht“ (leere Karte, darf geschrieben werden) von „nicht lesbar“
/// (z. B. vor dem ersten Entsperren): Dann darf niemand die Datei überschreiben, sonst gingen die
/// Plätze verloren. Eine kaputte Datei zählt als leer – es sind nur Plätze, keine Inhalte.
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
