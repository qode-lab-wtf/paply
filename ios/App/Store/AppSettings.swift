import Foundation
import Observation
import PaplyKit
import UIKit
import WidgetKit

/// Testschalter der Pipeline (PipelineOptions). Standard = PaplyKit-Standard.
struct PipelineTestOptions: Codable, Equatable, Sendable {
    var wav = false
    var codeSwitchPrimer = true
    var polish = true
    /// Wortgenaue Prüfung des Polierens (Ersetzungen/Einfügungen)
    var strictPolishCheck = true

    init() {}

    /// Fehlende Felder (ältere gespeicherte Werte) bekommen den Standard.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wav = try c.decodeIfPresent(Bool.self, forKey: .wav) ?? false
        codeSwitchPrimer = try c.decodeIfPresent(Bool.self, forKey: .codeSwitchPrimer) ?? true
        polish = try c.decodeIfPresent(Bool.self, forKey: .polish) ?? true
        strictPolishCheck = try c.decodeIfPresent(Bool.self, forKey: .strictPolishCheck) ?? true
    }

    var isDefault: Bool { self == PipelineTestOptions() }

    var pipelineOptions: PipelineOptions {
        var options = PipelineOptions()
        options.uploadFormat = wav ? .wav : .flac
        options.codeSwitchPrimer = codeSwitchPrimer
        options.polish = polish
        options.strictPolishCheck = strictPolishCheck
        return options
    }

    /// Kurzform fürs Protokoll, Standard „flac·primer·polish·strict“
    var logName: String {
        [
            wav ? "wav" : "flac",
            codeSwitchPrimer ? "primer" : "noPrimer",
            polish ? "polish" : "noPolish",
            strictPolishCheck ? "strict" : "loose",
        ].joined(separator: "·")
    }
}

/// Experiment: Mikro im Leerlauf anhalten, damit iOS in anderen Apps kein Mikro-Symbol zeigt.
/// Die AVAudioSession bleibt aktiv; nur die Engine hält an.
enum IdlePauseMode: String, CaseIterable, Codable, Sendable {
    /// aus (Standard): Engine läuft durch
    case off
    /// `engine.pause()`: Hardware bleibt eingerichtet, Tap bleibt – schnellster Wiederanlauf
    case pause
    /// `engine.stop()` + Tap entfernen: gibt alles frei, Wiederanlauf richtet neu ein
    case stop

    var label: String {
        switch self {
        case .off: "aus"
        case .pause: "pause()"
        case .stop: "stop()"
        }
    }
}

/// Einstellungen der App. PaplySettings liegen nur in der App (die Tastatur braucht sie nicht),
/// Sitzungs- und Testschalter in der App Group (SharedSettings).
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let transcriptionModels: [(id: String, label: String)] = [
        ("whisper-large-v3", "large-v3 (genauer)"),
        ("whisper-large-v3-turbo", "large-v3-turbo (schneller)"),
    ]

    /// Sprachen mit fertigem Sprachwechsel-Beispiel in PaplyKit (Auswahl in den Einstellungen)
    static let commonLanguages = ["de", "en", "fr", "es", "it", "pt", "nl", "tr", "pl"]

    private enum Key {
        static let settings = "paplySettings"
        static let testOptions = "pipelineTestOptions"
        static let spokenAuto = "spokenLanguagesAuto"
        static let spokenDetected = "spokenLanguagesDetected"
        static let idlePause = "idlePauseMode"
        static let developerMode = "developerMode"
    }

    var paply: PaplySettings {
        didSet { persist() }
    }

    var holdDuration: HoldDuration {
        didSet { save { SharedSettings.holdDuration = holdDuration } }
    }

    var autoOpenApp: Bool {
        didSet { save { SharedSettings.autoOpenApp = autoOpenApp } }
    }

    var logHostBundleID: Bool {
        didSet { save { SharedSettings.logHostBundleID = logHostBundleID } }
    }

    /// Beta „Gedanken & Aufgaben“ (Einstellungen → Beta; App Group, fehlt = an – `BetaFeatures`). Umschalten: Widgets
    /// neu laden, Erinnerungen abgleichen (aus = alle weg, Verschobenes bleibt gespeichert); aus beendet eine laufende
    /// Gedanken-Aufnahme (sie wird gesichert und geordnet) und bricht eine gerade beginnende ab (ohne Rest). Daten
    /// bleiben immer.
    var betaThoughts: Bool {
        didSet {
            guard betaThoughts != oldValue else { return }
            save { SharedSettings.betaThoughts = betaThoughts }
            Diag.log("settings.beta.thoughts", ["on": .b(betaThoughts)])
            WidgetCenter.shared.reloadAllTimelines()
            TaskReminders.shared.scheduleReconcile("beta", delay: .zero)
            if !betaThoughts { ThoughtCapture.shared.betaTurnedOff() }
        }
    }

    /// Versteckter Entwicklerbereich (5× auf die Version tippen)
    var developerMode: Bool {
        didSet { save { UserDefaults.standard.set(developerMode, forKey: Key.developerMode) } }
    }

    var idlePause: IdlePauseMode {
        didSet { save { UserDefaults.standard.set(idlePause.rawValue, forKey: Key.idlePause) } }
    }

    var testOptions: PipelineTestOptions {
        didSet {
            save { UserDefaults.standard.set(try? JSONEncoder().encode(testOptions), forKey: Key.testOptions) }
        }
    }

    /// „Sprachen, die du sprichst“: automatisch (Tastaturen + Gerätesprachen) oder eigene Liste
    /// (`paply.spokenLanguages`).
    var spokenLanguagesAuto: Bool {
        didSet { save { UserDefaults.standard.set(spokenLanguagesAuto, forKey: Key.spokenAuto) } }
    }

    /// Zuletzt im Vordergrund abgeleitete Sprachen (gespeichert, damit sie im Hintergrund gelten)
    private(set) var detectedSpokenLanguages: [String]

    private(set) var hasAPIKey: Bool
    /// Letzte 4 Zeichen zum Anzeigen – damit Views nicht bei jedem Zeichnen den Schlüsselbund lesen
    private(set) var apiKeySuffix: String?
    @ObservationIgnored private var cachedAPIKey: String?

    /// false = vor dem ersten Entsperren nach einem Neustart gelesen: UserDefaults lieferten nur
    /// Standardwerte. Bis `reloadIfNeeded()` wird NICHTS gespeichert – sonst überschrieben die leeren
    /// Werte die echten (z. B. die Eigenen Begriffe).
    @ObservationIgnored private(set) var isLoaded: Bool

    /// Gespeicherter Stand (UserDefaults, App Group, Schlüsselbund)
    private struct Stored {
        var paply: PaplySettings
        var holdDuration: HoldDuration
        var autoOpenApp: Bool
        var logHostBundleID: Bool
        var betaThoughts: Bool
        var testOptions: PipelineTestOptions
        var spokenLanguagesAuto: Bool
        var idlePause: IdlePauseMode
        var developerMode: Bool
        var detectedSpokenLanguages: [String]
        var apiKey: String?

        static func read() -> Stored {
            let defaults = UserDefaults.standard
            var paply = PaplySettings()
            if let data = defaults.data(forKey: Key.settings),
               let stored = try? JSONDecoder().decode(PaplySettings.self, from: data) {
                paply = stored
            }
            // V1: Sprache immer automatisch
            paply.language = nil
            var testOptions = PipelineTestOptions()
            if let data = defaults.data(forKey: Key.testOptions),
               let stored = try? JSONDecoder().decode(PipelineTestOptions.self, from: data) {
                testOptions = stored
            }
            return Stored(
                paply: paply,
                holdDuration: SharedSettings.holdDuration,
                autoOpenApp: SharedSettings.autoOpenApp,
                logHostBundleID: SharedSettings.logHostBundleID,
                betaThoughts: BetaFeatures.thoughtsAtLaunch(AppGroup.defaults, arguments: ProcessInfo.processInfo.arguments),
                testOptions: testOptions,
                spokenLanguagesAuto: defaults.object(forKey: Key.spokenAuto) as? Bool ?? true,
                idlePause: IdlePauseMode(rawValue: defaults.string(forKey: Key.idlePause) ?? "") ?? .off,
                developerMode: defaults.bool(forKey: Key.developerMode),
                detectedSpokenLanguages: defaults.stringArray(forKey: Key.spokenDetected) ?? [],
                apiKey: Keychain.readAPIKey()
            )
        }
    }

    private init() {
        isLoaded = ProtectedData.isReadable
        let stored = Stored.read()
        paply = stored.paply
        holdDuration = stored.holdDuration
        autoOpenApp = stored.autoOpenApp
        logHostBundleID = stored.logHostBundleID
        betaThoughts = stored.betaThoughts
        testOptions = stored.testOptions
        spokenLanguagesAuto = stored.spokenLanguagesAuto
        idlePause = stored.idlePause
        developerMode = stored.developerMode
        detectedSpokenLanguages = stored.detectedSpokenLanguages
        cachedAPIKey = stored.apiKey
        hasAPIKey = stored.apiKey != nil
        apiKeySuffix = stored.apiKey.map { String($0.suffix(4)) }
        if !isLoaded {
            Diag.log("settings.load.deferred")
            // erst nach dem init anmelden: `reloadIfNeeded` greift auf `shared` zu (SessionController)
            Task { @MainActor in
                ProtectedData.whenReadable { _ in AppSettings.shared.reloadIfNeeded() }
            }
        }
    }

    /// Nach dem ersten Entsperren: alles neu lesen, ohne zu schreiben (`isLoaded` ist dabei noch false).
    func reloadIfNeeded() {
        guard !isLoaded, ProtectedData.isReadable else { return }
        let stored = Stored.read()
        paply = stored.paply
        holdDuration = stored.holdDuration
        autoOpenApp = stored.autoOpenApp
        logHostBundleID = stored.logHostBundleID
        betaThoughts = stored.betaThoughts
        testOptions = stored.testOptions
        spokenLanguagesAuto = stored.spokenLanguagesAuto
        idlePause = stored.idlePause
        developerMode = stored.developerMode
        detectedSpokenLanguages = stored.detectedSpokenLanguages
        if let key = stored.apiKey {
            cachedAPIKey = key
            hasAPIKey = true
            apiKeySuffix = String(key.suffix(4))
        }
        isLoaded = true
        Diag.log("settings.load", ["afterUnlock": .b(true), "apiKey": .b(hasAPIKey)])
        SessionController.shared.refreshShared() // Tastatur: Schlüssel vorhanden?
    }

    /// Nur mit gelesenem Stand speichern.
    private func save(_ write: () -> Void) {
        guard isLoaded else {
            Diag.log("settings.save.skipped", ["why": .s("not-loaded")])
            return
        }
        write()
    }

    /// Aus dem Speicher; nur wenn noch nichts da ist (z. B. vor dem ersten Entsperren), erneut lesen.
    var apiKey: String? {
        if cachedAPIKey == nil, let key = Keychain.readAPIKey() {
            cachedAPIKey = key
            hasAPIKey = true
            apiKeySuffix = String(key.suffix(4))
        }
        return cachedAPIKey
    }

    /// Einstellungen, mit denen ein Diktat startet (Sprachen je nach Modus eingesetzt).
    var effectivePaply: PaplySettings {
        var settings = paply
        settings.spokenLanguages = effectiveSpokenLanguages
        return settings
    }

    var effectiveSpokenLanguages: [String] {
        spokenLanguagesAuto ? detectedSpokenLanguages : paply.spokenLanguages
    }

    /// Im Vordergrund aufrufen: aktive Tastaturen + bevorzugte Sprachen → Sprachcodes.
    /// Bleibt nur EINE Sprache und ist das nicht Englisch, kommt Englisch dazu: Englisch ist der
    /// häufigste eingestreute Sprachwechsel, und ohne zweite Sprache greift das
    /// Sprachwechsel-Beispiel (Schutz gegen verschluckte englische Sätze) nicht.
    func refreshDetectedSpokenLanguages() {
        reloadIfNeeded()
        guard isLoaded else { return }
        let keyboards = UITextInputMode.activeInputModes.compactMap(\.primaryLanguage)
        var detected = Self.languageCodes(keyboards + Locale.preferredLanguages)
        if detected.count == 1, detected[0] != "en" { detected.append("en") }
        guard detected != detectedSpokenLanguages else { return }
        detectedSpokenLanguages = detected
        UserDefaults.standard.set(detected, forKey: Key.spokenDetected)
        Diag.log("settings.spokenLanguages.detected", ["langs": .s(detected.joined(separator: ","))])
    }

    /// „de-DE“, „en_US“, „zh-Hans-CN“ → „de“, „en“, „zh“; ohne Emoji/„mul“, ohne Doppel.
    static func languageCodes(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        var codes: [String] = []
        for identifier in identifiers {
            let code = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() } ?? ""
            guard (2...3).contains(code.count), code.allSatisfy(\.isLetter),
                  !["mul", "und", "zxx"].contains(code), !identifier.lowercased().hasPrefix("emoji")
            else { continue }
            if seen.insert(code).inserted { codes.append(code) }
        }
        return codes
    }

    static func languageName(_ code: String) -> String {
        Locale(identifier: "de_DE").localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.deleteAPIKey()
        } else {
            Keychain.saveAPIKey(trimmed)
        }
        cachedAPIKey = Keychain.readAPIKey()
        hasAPIKey = cachedAPIKey != nil
        apiKeySuffix = cachedAPIKey.map { String($0.suffix(4)) }
        Diag.log("settings.apiKey", ["present": .b(hasAPIKey), "len": .i(trimmed.count)])
    }

    private func persist() {
        save {
            if let data = try? JSONEncoder().encode(paply) {
                UserDefaults.standard.set(data, forKey: Key.settings)
            }
        }
    }
}
