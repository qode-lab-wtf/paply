import Foundation

/// Reine Sprachentscheidung; jede erste Anfrage erkennt ohne Sprachvorgabe.
enum LanguageGuard {
    static let shortSpeechSeconds = 5.0
    static let checkGap = 0.15

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

    static func expected(previous: String?, primary: String?) -> String? {
        [previous, primary].compactMap { $0.map(CodeSwitchPrimer.baseCode) }.first { !$0.isEmpty }
    }

    static func needsCheck(expected: String?, detected: String?, userLanguages: [String], spokenSeconds: Double) -> Bool {
        guard let expected = expected.map(CodeSwitchPrimer.baseCode), !expected.isEmpty,
              let detected = detected.map(CodeSwitchPrimer.baseCode), !detected.isEmpty,
              expected != detected else { return false }
        return spokenSeconds <= shortSpeechSeconds || !userLanguages.map(CodeSwitchPrimer.baseCode).contains(detected)
    }

    enum Choice { case detected, expected }
    static func choose(detectedText: String, expectedText: String?, detectedConfidence: Double?, expectedConfidence: Double?) -> Choice {
        guard let expectedText else { return .detected }
        if normalize(detectedText) == normalize(expectedText) { return .expected }
        guard let detectedConfidence, let expectedConfidence else { return .detected }
        return detectedConfidence - expectedConfidence >= checkGap ? .detected : .expected
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Vor allen Text-/Stillefiltern auf der rohen Antwort messen.
    static func confidence(_ segments: [WhisperSegment]?) -> Double? {
        guard let segments, !segments.isEmpty else { return nil }
        var sum = 0.0, weight = 0.0
        for segment in segments {
            guard let probability = segment.avgLogprob, probability.isFinite else { return nil }
            let duration = max(0.01, (segment.end ?? 0) - (segment.start ?? 0))
            guard duration.isFinite else { return nil }
            sum += probability * duration; weight += duration
        }
        return sum / weight
    }
}
