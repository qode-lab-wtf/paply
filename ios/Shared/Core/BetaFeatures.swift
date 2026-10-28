import Foundation

/// Beta „Gedanken & Aufgaben“ (Einstellungen → Beta). Ein Wert in den App-Group-Defaults für App, Tastatur und Widgets;
/// fehlt er, gilt AN (Entscheidung Allan). Ohne `AppGroup`, damit die Tests genau diese Datei mitübersetzen
/// (`PaplyKitTests/Shared/BetaFeatures.swift`). Lesen und Schreiben: `SharedSettings.betaThoughts`, in der App
/// `AppSettings.betaThoughts`.
///
/// - AN: alles wie gewohnt; die Reiter „Gedanken“ und „Aufgaben“ tragen ein ruhiges „Beta“.
/// - AUS: nur das Diktat (keine Reiter). Gedanken-Knopf, Steuerelement, Widget „Paply-Gedanke“, Kurzbefehl und
///   Aktionstaste nehmen nicht auf, sondern zeigen den Hinweis; keine Erinnerungen; Aufgaben-Widgets ruhig. Daten
///   bleiben unangetastet, schon aufgenommene Gedanken werden weiter geordnet.
enum BetaFeatures {
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
