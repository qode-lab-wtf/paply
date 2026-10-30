import Foundation

/// Sprachwache je Stück (nur ohne feste Sprache in den Einstellungen).
///
/// Gerätefund: Whisper legt die Sprache pro Anfrage selbst fest und liegt bei kurzen
/// Stücken oft daneben („Hi, wie geht's“ → „en“, sogar „ru“). Bei falscher Sprache
/// übersetzt Whisper die Rede. Deshalb, ohne Raterei:
/// - Kurzes Stück (gesprochen ≤ `shortSpeechSeconds`, laut VAD – nicht die Audiolänge:
///   „Hi, wie geht's“ plus Pause waren 8,3 s Audio): Sprache direkt mitschicken – die des
///   Vorstücks derselben Aufnahme (so bleibt der kurze Rest eines englischen Diktats
///   englisch), sonst die Hauptsprache. Eine Anfrage.
/// - Längeres Stück: Whisper erkennt selbst. Ist die erkannte Sprache keine Nutzersprache,
///   einmal mit der Hauptsprache neu transkribieren und dieses Ergebnis nehmen.
enum LanguageGuard {
    /// Bis zu dieser gesprochenen Dauer wird die Sprache nicht erkannt, sondern mitgeschickt.
    static let shortSpeechSeconds = 5.0

    /// Wirksame Hauptsprache (Basiscode): die gewählte, solange sie unter den Nutzersprachen
    /// ist; sonst die erste iPhone-Sprache, wenn sie darunter ist (nicht die erste Tastatur);
    /// sonst die erste Nutzersprache.
    static func primary(chosen: String?, userLanguages: [String], device: String?) -> String? {
        let codes = userLanguages.map(CodeSwitchPrimer.baseCode).filter { !$0.isEmpty }
        for candidate in [chosen, device] {
            if let code = candidate.map(CodeSwitchPrimer.baseCode), codes.contains(code) { return code }
        }
        return codes.first
    }

    static func primary(_ settings: PaplySettings) -> String? {
        primary(chosen: settings.primaryLanguage, userLanguages: CodeSwitchPrimer.userLanguages(settings),
                device: Locale.preferredLanguages.first)
    }

    /// Erste Anfrage: mitgeschickte Sprache (nil = Whisper erkennt selbst) und ihre Herkunft.
    struct Request: Equatable {
        var language: String?
        var source: LanguageSource
    }

    /// `spokenSeconds`: gesprochene Dauer des Stücks (VAD); ohne Messwert die Audiolänge.
    static func firstRequest(fixed: String?, primary: String?, previous: String?, userLanguages: [String],
                             spokenSeconds: Double) -> Request {
        if let fixed = fixed?.trimmed, !fixed.isEmpty { return Request(language: fixed, source: .fixed) }
        guard spokenSeconds <= shortSpeechSeconds else { return Request(language: nil, source: .auto) }
        let codes = userLanguages.map(CodeSwitchPrimer.baseCode)
        if let previous = previous.map(CodeSwitchPrimer.baseCode), codes.contains(previous) {
            return Request(language: previous, source: .short)
        }
        if let primary { return Request(language: primary, source: .short) }
        return Request(language: nil, source: .auto)
    }

    /// Nach eigener Erkennung: die Hauptsprache, wenn die erkannte Sprache keine
    /// Nutzersprache ist (dann einmal neu transkribieren); sonst nil.
    static func redoLanguage(detected: String?, primary: String?, userLanguages: [String]) -> String? {
        guard let detected = detected.map(CodeSwitchPrimer.baseCode), !detected.isEmpty,
              let primary, detected != primary,
              !userLanguages.map(CodeSwitchPrimer.baseCode).contains(detected) else { return nil }
        return primary
    }
}
