import Foundation

enum SharedFile: String, Sendable {
    case session = "session.json"
    case keyboardCommand = "keyboard-command.json"
    case pendingText = "pending-text.json"
    case shortcutCommand = "shortcut-command.json"
    case shortcutAck = "shortcut-ack.json"
    case keyboardReport = "keyboard-report.json"
}

/// Kleine JSON-Dateien in der App Group. Geschrieben wird atomar (Umbenennen),
/// damit der andere Prozess nie eine halbe Datei liest.
enum SharedStore {
    static func url(_ file: SharedFile) -> URL? {
        AppGroup.containerURL?.appendingPathComponent(file.rawValue)
    }

    static func read<T: Decodable>(_ type: T.Type, _ file: SharedFile) -> T? {
        guard let url = url(file) else { return nil }
        return decode(type, at: url)
    }

    @discardableResult
    static func write<T: Encodable>(_ value: T, _ file: SharedFile) -> Bool {
        guard let url = url(file) else { return false }
        return encode(value, to: url)
    }

    static func remove(_ file: SharedFile) {
        guard let url = url(file) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Ergebnisse je Diktat

    static func resultURL(id: String) -> URL? {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return AppGroup.directory("results")?.appendingPathComponent("\(safe).json")
    }

    @discardableResult
    static func writeResult(_ result: DictationResult) -> Bool {
        guard let url = resultURL(id: result.dictationID) else { return false }
        return encode(result, to: url)
    }

    static func readResult(id: String) -> DictationResult? {
        guard let url = resultURL(id: id) else { return nil }
        return decode(DictationResult.self, at: url)
    }

    static func removeResult(id: String) {
        guard let url = resultURL(id: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Nicht abgeholte Ergebnisse nach einer Weile löschen (Text soll nicht liegen bleiben).
    static func pruneResults(olderThan age: TimeInterval = 10 * 60) {
        guard let dir = AppGroup.directory("results"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let limit = Date().addingTimeInterval(-age)
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date < limit { try? FileManager.default.removeItem(at: file) }
        }
    }

    // MARK: Hilfen

    private static func decode<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
