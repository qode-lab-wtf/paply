import Foundation

/// Dateien der Aufgaben-Widgets in der App Group (`Library/Application Support/Paply`, wie `SharedStore`):
/// - `tasks-snapshot.json` – Momentaufnahme (`TaskSnapshot`). Schreibt die App; nach einem Tipp im Widget passt die
///   Erweiterung sie sofort optimistisch an.
/// - `task-completions/<id>.json` – Warteschlange: je abgehakte Aufgabe eine eigene Datei. So schreiben App und
///   Erweiterung nie gleichzeitig in dieselbe Liste (kein Lesen-Ändern-Schreiben zwischen zwei Prozessen). Die App
///   wendet die Einträge an und löscht danach genau die angesehenen.
///
/// Geschrieben wird atomar (Umbenennen), mit der Schutzklasse „bis zur ersten Anmeldung“ wie die übrigen Dateien: Nach
/// dem ersten Entsperren lesbar, auch bei gesperrtem Gerät (Sperrbildschirm-Widget); vor dem ersten Entsperren nach
/// einem Neustart weder les- noch schreibbar – die App schreibt dann nicht (`ProtectedData`), das Widget zeigt „–“.
enum TaskWidgetFiles {
    static let snapshotName = "tasks-snapshot.json"
    static let queueName = "task-completions"

    static var snapshotURL: URL? { AppGroup.baseURL?.appendingPathComponent(snapshotName) }

    /// Stand der Momentaufnahme
    enum Load: Sendable {
        case ready(TaskSnapshot)
        /// noch nie geschrieben (App seit dem Update nicht geöffnet) bzw. keine App Group
        case missing
        /// Datei da, aber nicht lesbar – vor dem ersten Entsperren nach einem Neustart
        case unreadable
    }

    // MARK: Momentaufnahme

    static func loadSnapshot() -> Load {
        guard let url = snapshotURL else { return .missing }
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        guard let snapshot = try? JSONDecoder().decode(TaskSnapshot.self, from: data),
              snapshot.version <= TaskSnapshot.formatVersion else { return .missing }
        return .ready(snapshot)
    }

    static func readSnapshot() -> TaskSnapshot? {
        if case .ready(let snapshot) = loadSnapshot() { return snapshot }
        return nil
    }

    /// Momentaufnahme mit der Warteschlange darüber – so sieht das Widget eine abgehakte Aufgabe nie wieder
    /// auftauchen, auch wenn die App noch einen älteren Stand geschrieben hat.
    static func loadCurrent(calendar: Calendar = .current) -> Load {
        let load = loadSnapshot()
        guard case .ready(let snapshot) = load else { return load }
        let pending = pendingCompletions()
        return .ready(pending.isEmpty ? snapshot : snapshot.applying(pending, calendar: calendar))
    }

    @discardableResult
    static func writeSnapshot(_ snapshot: TaskSnapshot) -> Bool {
        guard let url = snapshotURL else { return false }
        return write(snapshot, to: url)
    }

    /// Im Widget-Prozess nach dem Tipp: Aufgabe sofort aus der Momentaufnahme nehmen. Schreibt die App genau jetzt
    /// einen neueren Stand, gewinnt der (vor dem Schreiben noch einmal vergleichen); die Warteschlange liegt ohnehin
    /// darüber. false = nichts geändert (Aufgabe stand nicht mehr drin, oder keine Datei).
    @discardableResult
    static func applyOptimistically(_ completion: TaskCompletion, calendar: Calendar = .current) -> Bool {
        for _ in 0..<2 {
            guard let before = readSnapshot() else { return false }
            guard let next = before.completing(completion, calendar: calendar) else { return false }
            guard readSnapshot() == before else { continue }
            return writeSnapshot(next)
        }
        return false
    }

    // MARK: Warteschlange

    static var queueURL: URL? { AppGroup.directory(queueName) }

    @discardableResult
    static func enqueue(_ completion: TaskCompletion) -> Bool {
        guard let dir = queueURL else { return false }
        return write(completion, to: dir.appendingPathComponent(fileName(completion.id)))
    }

    /// Alle wartenden Einträge, ältester Tipp zuerst. Unlesbare Dateien bleiben liegen (nach dem Entsperren lesbar).
    static func pendingCompletions() -> [TaskCompletion] {
        guard let dir = queueURL,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? decoder.decode(TaskCompletion.self, from: $0) } }
            .sorted { ($0.at, $0.id) < ($1.at, $1.id) }
    }

    static func removeCompletions(_ ids: [String]) {
        guard let dir = queueURL else { return }
        for id in ids { try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName(id))) }
    }

    // MARK: Hilfen

    private static func fileName(_ id: String) -> String {
        id.filter { $0.isLetter || $0.isNumber || $0 == "-" } + ".json"
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}
