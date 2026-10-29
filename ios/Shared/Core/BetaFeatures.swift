import Foundation

/// Beta „Gedanken & Aufgaben“ (Einstellungen → Beta). Ein Wert in den App-Group-Defaults für App, Tastatur und Widgets;
/// fehlt er, gilt AN (Entscheidung Allan). Ohne `AppGroup`, damit die Tests genau diese Datei mitübersetzen
/// (`PaplyKitTests/Shared/BetaFeatures.swift`). Lesen und Schreiben: `SharedSettings.betaThoughts`, in der App
/// `AppSettings.betaThoughts`.
///
/// - AN: alles wie gewohnt; die Reiter „Gedanken“ und „Aufgaben“ tragen ein ruhiges „Beta“.
/// - AUS: nur das Diktat (keine Reiter). Gedanken-Knopf, Steuerelement, Widget „Paply-Gedanke“, Kurzbefehl und
///   Aktionstaste nehmen nicht auf, sondern zeigen den Hinweis; keine Erinnerungen; Aufgaben-Widgets ruhig. Daten
///   bleiben unangetastet, schon aufgenommene Gedanken werden weiter geordnet. Eine gerade beginnende Aufnahme bricht
///   ab (`ThoughtStartGate`), verschobene Erinnerungen („In 1 Stunde“) bleiben gespeichert.
enum BetaFeatures {
    /// Beta „Gespräche“: fehlt der Wert, gilt im Debug AN und in TestFlight/Release AUS, bis Allans Gerätetest
    /// bestanden ist (29.10.: Zusammenführung in `feat/ios-v1`, Tester sollen es nicht ungefragt sehen).
    static let conversationsKey = "paply.beta.conversations"
    #if DEBUG
    static let conversationsDefault = true
    #else
    static let conversationsDefault = false
    #endif
    static func conversationsEnabled(_ defaults: UserDefaults?) -> Bool {
        defaults?.object(forKey: conversationsKey) as? Bool ?? conversationsDefault
    }

    static let thoughtsKey = "paply.beta.thoughts"

    /// Debug: Die App startet im Zustand AUS (nur ihr Prozess, nichts wird gespeichert; der Schalter wirkt weiter).
    static let thoughtsOffArgument = "-PaplyBetaOff"

    /// Hinweis, wenn bei AUS ein Gedanke aufgenommen werden soll (Siri/Kurzbefehl, Rückfrage von iOS)
    static let thoughtsOffMessage = "Gedanken sind Beta – in den Einstellungen unter Beta einschalten."

    static func thoughtsEnabled(_ defaults: UserDefaults?) -> Bool {
        defaults?.object(forKey: thoughtsKey) as? Bool ?? true
    }

    /// Startwert in der App: gespeicherter Wert, im Debug mit `-PaplyBetaOff` AUS
    static func thoughtsAtLaunch(_ defaults: UserDefaults?, arguments: [String]) -> Bool {
        #if DEBUG
        if arguments.contains(thoughtsOffArgument) { return false }
        #endif
        return thoughtsEnabled(defaults)
    }
}

/// Prüfpunkt beim Start einer Gedanken-Aufnahme (`ThoughtCapture.toggle`): vor dem Start und nach jedem `await`
/// (Speicher, Mikro, Warteschlange) muss Beta „Gedanken & Aufgaben“ noch an sein. Wird während des Starts
/// ausgeschaltet (`abort`), bleibt dieser Start abgebrochen – auch wenn Beta gleich wieder an ist.
struct ThoughtStartGate: Equatable, Sendable {
    private(set) var aborted = false

    /// Neuer Start: frischer Prüfpunkt
    mutating func begin() {
        aborted = false
    }

    /// Beta während des Starts ausgeschaltet
    mutating func abort() {
        aborted = true
    }

    /// Darf der Start weiterlaufen?
    func allows(betaOn: Bool) -> Bool {
        betaOn && !aborted
    }
}
