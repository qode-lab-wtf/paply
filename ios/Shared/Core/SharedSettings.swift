import Foundation

/// Wie lange die App das Mikro nach der letzten Nutzung bereit hält.
enum HoldDuration: String, CaseIterable, Codable, Sendable, Identifiable {
    case untilRestart
    case hours8
    case hour1
    case minutes15

    var id: String { rawValue }

    /// nil = bis Neustart
    var seconds: TimeInterval? {
        switch self {
        case .untilRestart: nil
        case .hours8: 8 * 3600
        case .hour1: 3600
        case .minutes15: 15 * 60
        }
    }

    var label: String {
        switch self {
        case .untilRestart: "bis Neustart"
        case .hours8: "8 Stunden"
        case .hour1: "1 Stunde"
        case .minutes15: "15 Minuten"
        }
    }
}

/// Gemessene Tastaturhöhen (Testseite in der App). Alle Werte in Punkt.
struct KeyboardHeights: Codable, Sendable, Equatable {
    /// Gesamthöhe von Apples Tastatur (Frame aus keyboardWillChangeFrame)
    var applePortrait: Double?
    var appleLandscape: Double?
    /// Gesamthöhe der Paply-Tastatur (Frame) und gleichzeitig gemeldete eigene View-Höhe
    var paplyFramePortrait: Double?
    var paplyViewPortrait: Double?
    var paplyFrameLandscape: Double?
    var paplyViewLandscape: Double?
    var measuredAt: Date?

    /// Zielhöhe für die Paply-View: Apples Frame minus der Leiste, die iOS unter
    /// Drittanbieter-Tastaturen zeichnet (🌐/Mikro auf Face-ID-iPhones).
    func targetViewHeight(landscape: Bool) -> Double? {
        let apple = landscape ? appleLandscape : applePortrait
        let frame = landscape ? paplyFrameLandscape : paplyFramePortrait
        let view = landscape ? paplyViewLandscape : paplyViewPortrait
        guard let apple else { return nil }
        guard let frame, let view else { return nil }
        let systemBar = max(0, frame - view)
        return apple - systemBar
    }
}

/// Einstellungen, die mehrere Prozesse brauchen (App-Group-UserDefaults).
enum SharedSettings {
    private enum Key {
        static let holdDuration = "holdDuration"
        static let autoOpenApp = "autoOpenApp"
        static let keyboardHeights = "keyboardHeights"
        static let logHostBundleID = "logHostBundleID"
    }

    static var holdDuration: HoldDuration {
        get { HoldDuration(rawValue: AppGroup.defaults?.string(forKey: Key.holdDuration) ?? "") ?? .untilRestart }
        set { AppGroup.defaults?.set(newValue.rawValue, forKey: Key.holdDuration) }
    }

    /// Testvariante: A (true, Standard) öffnet die App automatisch, B zeigt „Paply starten“.
    static var autoOpenApp: Bool {
        get { AppGroup.defaults?.object(forKey: Key.autoOpenApp) as? Bool ?? true }
        set { AppGroup.defaults?.set(newValue, forKey: Key.autoOpenApp) }
    }

    /// EXPERIMENTELL (Standard aus): Die Tastatur liest die Bundle-ID der Host-App über
    /// private Felder und protokolliert sie nur. Kein Rücksprung, keine weitere Nutzung.
    static var logHostBundleID: Bool {
        get { AppGroup.defaults?.bool(forKey: Key.logHostBundleID) ?? false }
        set { AppGroup.defaults?.set(newValue, forKey: Key.logHostBundleID) }
    }

    /// Beta „Gedanken & Aufgaben“ (fehlt = an). App schreibt, Widgets und Tastatur lesen (`BetaFeatures`).
    static var betaThoughts: Bool {
        get { BetaFeatures.thoughtsEnabled(AppGroup.defaults) }
        set { AppGroup.defaults?.set(newValue, forKey: BetaFeatures.thoughtsKey) }
    }

    static var keyboardHeights: KeyboardHeights {
        get {
            guard let data = AppGroup.defaults?.data(forKey: Key.keyboardHeights),
                  let value = try? JSONDecoder().decode(KeyboardHeights.self, from: data)
            else { return KeyboardHeights() }
            return value
        }
        set {
            AppGroup.defaults?.set(try? JSONEncoder().encode(newValue), forKey: Key.keyboardHeights)
        }
    }
}

/// Standardhöhen der Paply-View (ohne die System-Leiste darunter), falls noch nicht gemessen.
/// Schätzwerte für iOS 18 mit Vorschlagsleiste: Apple-Frame minus ~75 pt System-Leiste
/// auf Face-ID-iPhones. Werden durch die Messung auf der Testseite ersetzt.
enum KeyboardHeightTable {
    static func defaultViewHeight(screenWidth: Double, screenHeight: Double, landscape: Bool) -> Double? {
        guard !landscape else { return nil } // Querformat: Systemstandard, bis gemessen
        let longSide = max(screenWidth, screenHeight)
        switch longSide {
        case ..<700: return 260 // SE / 8 (Touch ID, keine System-Leiste)
        case ..<800: return 271 // 8 Plus
        case ..<890: return 261 // X … 16 Pro (5,4"–6,3")
        default: return 271 // Plus / Max (6,5"–6,9")
        }
    }
}
