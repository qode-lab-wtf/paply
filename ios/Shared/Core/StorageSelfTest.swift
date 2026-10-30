import Foundation

/// Selbsttest des gemeinsamen Speichers: Jeder Prozess schreibt eine Markierung
/// (`selftest/<prozess>.json`), liest sie zurück und liest die des anderen Prozesses.
/// App: beim Start und auf Knopfdruck. Tastatur: bei jedem Erscheinen (mit Vollzugriff).
/// Ergebnis ins Protokoll; die App zeigt es im Entwicklerbereich.
enum StorageSelfTest {
    struct Mark: Codable, Sendable {
        var process: String
        var pid: Int32
        var date: Date
        /// Konnte dieser Prozess die Markierung des anderen lesen?
        var readOther: Bool
        var otherDate: Date?
    }

    struct Result: Sendable {
        var containerPath: String?
        var basePath: String?
        var wroteOwn = false
        var readBackOwn = false
        var other: Mark?
        var errors: [String] = []

        var ok: Bool { basePath != nil && wroteOwn && readBackOwn }
    }

    /// Läuft synchron (Datei-I/O) – nicht auf dem Main-Thread aufrufen.
    static func run(as process: PaplyProcess) -> Result {
        var result = Result()
        result.containerPath = AppGroup.containerURL?.path
        guard let dir = AppGroup.directory("selftest") else {
            result.errors.append(AppGroup.containerURL == nil ? "kein App-Group-Container" : "Ordner nicht anlegbar")
            log(result, process: process)
            return result
        }
        result.basePath = AppGroup.baseURL?.path
        let otherName = process == .app ? "kb" : "app"
        let ownURL = dir.appendingPathComponent("\(process.rawValue).json")
        let otherURL = dir.appendingPathComponent("\(otherName).json")

        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: otherURL) {
            result.other = try? decoder.decode(Mark.self, from: data)
            if result.other == nil { result.errors.append("Markierung von \(otherName) unlesbar") }
        }
        let mark = Mark(process: process.rawValue, pid: getpid(), date: Date(), readOther: result.other != nil, otherDate: result.other?.date)
        do {
            try JSONEncoder().encode(mark).write(to: ownURL, options: [.atomic])
            result.wroteOwn = true
        } catch {
            result.errors.append("schreiben: \((error as NSError).code)")
        }
        if let data = try? Data(contentsOf: ownURL), (try? decoder.decode(Mark.self, from: data)) != nil {
            result.readBackOwn = true
        } else {
            result.errors.append("zurücklesen fehlgeschlagen")
        }
        log(result, process: process)
        return result
    }

    private static func log(_ result: Result, process: PaplyProcess) {
        Diag.log(process == .app ? "storage.selftest" : "kb.selftest", [
            "ok": .b(result.ok),
            "container": .opt(result.containerPath),
            "base": .opt(result.basePath),
            "wrote": .b(result.wroteOwn),
            "readBack": .b(result.readBackOwn),
            "otherSeen": .b(result.other != nil),
            "otherAgeS": result.other.map { .d(Date().timeIntervalSince($0.date).rounded()) } ?? .null,
            "otherReadMine": result.other.map { .b($0.readOther) } ?? .null,
            "errors": .s(result.errors.joined(separator: "; ")),
        ])
    }

    /// Dateien unter `baseURL` mit Größe (für Protokoll und Anzeige), höchstens `limit`.
    static func inventory(limit: Int = 60) -> [(path: String, bytes: Int)] {
        guard let base = AppGroup.baseURL,
              let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return [] }
        var files: [(String, Int)] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            files.append((String(url.path.dropFirst(base.path.count + 1)), size))
            if files.count >= limit { break }
        }
        return files.sorted { $0.0 < $1.0 }
    }
}
