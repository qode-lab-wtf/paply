import Foundation

/// Wert im Diagnoseprotokoll. Diktat-Texte gehören NIE hierher, nur Längen.
enum DiagValue: Sendable, Encodable, Equatable {
    case s(String)
    case i(Int)
    case d(Double)
    case b(Bool)
    case null

    static func opt(_ value: String?) -> DiagValue { value.map { .s($0) } ?? .null }
    static func opt(_ value: Double?) -> DiagValue { value.map { .d(($0 * 10).rounded() / 10) } ?? .null }
    /// Millisekunden auf eine Nachkommastelle
    static func ms(_ value: Double) -> DiagValue { .d((value * 10).rounded() / 10) }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .s(let v): try c.encode(v)
        case .i(let v): try c.encode(v)
        case .d(let v): try c.encode(v.isFinite ? v : 0)
        case .b(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

typealias DiagFields = [String: DiagValue]

/// JSONL-Protokoll im App-Group-Container: `Diagnostics/<Tag>-<Prozess>.jsonl`.
/// Jeder Prozess schreibt seine eigene Datei; die App führt sie zum Ansehen zusammen.
final class Diag: @unchecked Sendable {
    static let shared = Diag()

    static let directoryName = "Diagnostics"
    static let retentionDays = 14
    private static let maxFileBytes: UInt64 = 20 * 1024 * 1024

    private let queue = DispatchQueue(label: "paply.diag", qos: .utility)
    private let process = PaplyProcess.current
    private let pid = Int(getpid())
    // nur auf `queue` benutzt
    private var handle: FileHandle?
    private var handleDay: String?
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let stampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()

    private init() {}

    static func log(_ event: String, _ fields: DiagFields = [:]) {
        shared.write(event: event, fields: fields, mono: MonoClock.now(), date: Date())
    }

    /// Wartet, bis alles geschrieben ist (z. B. vor dem Teilen).
    static func flush() {
        shared.queue.sync {}
    }

    private func write(event: String, fields: DiagFields, mono: UInt64, date: Date) {
        queue.async { [self] in
            guard let line = encodeLine(event: event, fields: fields, mono: mono, date: date),
                  let handle = fileHandle(for: date)
            else { return }
            guard let end = try? handle.seekToEnd(), end < Self.maxFileBytes else { return }
            try? handle.write(contentsOf: line)
        }
    }

    private func encodeLine(event: String, fields: DiagFields, mono: UInt64, date: Date) -> Data? {
        var all = fields
        all["ts"] = .s(stampFormatter.string(from: date))
        all["mono"] = .i(Int(truncatingIfNeeded: mono))
        all["p"] = .s(process.rawValue)
        all["pid"] = .i(pid)
        all["ev"] = .s(event)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var data = try? encoder.encode(all) else { return nil }
        data.append(0x0A)
        return data
    }

    private func fileHandle(for date: Date) -> FileHandle? {
        let day = dayFormatter.string(from: date)
        // Wurde die Datei von einem anderen Prozess gelöscht (Aufbewahrung), neu öffnen
        if day == handleDay, let handle, !Self.isUnlinked(handle) { return handle }
        try? handle?.close()
        handle = nil
        handleDay = nil
        guard let dir = AppGroup.directory(Self.directoryName) else { return nil }
        let url = dir.appendingPathComponent("\(day)-\(process.rawValue).jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            pruneOldFiles(in: dir)
        }
        handle = try? FileHandle(forWritingTo: url)
        handleDay = day
        return handle
    }

    private func pruneOldFiles(in dir: URL) {
        let limit = Date().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if date < limit { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func isUnlinked(_ handle: FileHandle) -> Bool {
        var info = stat()
        return fstat(handle.fileDescriptor, &info) != 0 || info.st_nlink == 0
    }

    /// „Diagnose löschen“ in der App. Tastatur und Widgets halten ihre Datei offen –
    /// deshalb die heutigen Dateien nur auf 0 kürzen (sie schreiben dann einfach weiter)
    /// und nur ältere Tage wirklich löschen.
    static func deleteAll() {
        shared.queue.sync {
            guard let dir = AppGroup.directory(directoryName) else { return }
            let today = shared.dayFormatter.string(from: Date())
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                if file.lastPathComponent.hasPrefix(today) {
                    truncate(file.path, 0)
                } else {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
