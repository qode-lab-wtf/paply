import Foundation

/// Gemeinsamer Speicher von App, Tastatur und Widgets.
/// Die Gruppen-ID kommt aus der Info.plist (`PaplyAppGroup` = `$(PAPLY_APP_GROUP)`),
/// damit das Bundle-Präfix beim Bauen umstellbar bleibt.
enum AppGroup {
    static let identifier: String = Bundle.main.object(forInfoDictionaryKey: "PaplyAppGroup") as? String ?? ""

    /// Bundle-ID der Tastatur (aus der Info.plist), z. B. für die Höhenmessung.
    static let keyboardBundleID: String = Bundle.main.object(forInfoDictionaryKey: "PaplyKeyboardBundleID") as? String ?? ""

    /// nil, wenn die App Group fehlt – oder in der Tastatur ohne Vollzugriff.
    static var containerURL: URL? {
        guard !identifier.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults? {
        guard !identifier.isEmpty else { return nil }
        return UserDefaults(suiteName: identifier)
    }

    /// Paplys Dateien im Container: `Library/Application Support/Paply`. Bewusst unter
    /// `Library/` – devicectl zeigt (und kopiert) bei App-Group-Containern nur diesen Teil.
    /// Wird einmal je Prozess angelegt; nil ohne App Group (oder Tastatur ohne Vollzugriff).
    static let baseURL: URL? = {
        guard let container = containerURL else { return nil }
        let url = container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Paply", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            return nil
        }
    }()

    /// Unterordner in `baseURL` (wird bei Bedarf angelegt).
    static func directory(_ name: String) -> URL? {
        guard let base = baseURL else { return nil }
        let url = base.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}

/// URL-Schema der App (eigener Name, damit es nicht mit anderen „paply“-Apps kollidiert).
enum PaplyURL {
    static let scheme = "paply-ios"

    /// Start der Sitzung aus der Tastatur; `id` = Diktat, das sofort beginnt.
    static func sessionStart(dictationID: String, sentNs: UInt64) -> URL? {
        URL(string: "\(scheme)://session/start?src=kb&id=\(dictationID)&t=\(sentNs)")
    }
}

/// In welchem Prozess läuft der Code gerade?
enum PaplyProcess: String, Sendable {
    case app
    case keyboard = "kb"
    case widgets = "wg"

    static let current: PaplyProcess = {
        let id = Bundle.main.bundleIdentifier ?? ""
        if id.hasSuffix(".keyboard") { return .keyboard }
        if id.hasSuffix(".widgets") { return .widgets }
        return .app
    }()
}
