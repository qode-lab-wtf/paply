import Foundation

/// Reine Sprachentscheidung; jede erste Anfrage erkennt ohne Sprachvorgabe.
public enum LanguageGuard {
    public static func code(_ identifier: String) -> String {
        let base = CodeSwitchPrimer.baseCode(identifier)
        return ["nb": "no", "fil": "tl", "iw": "he", "in": "id", "ji": "yi", "jw": "jv"][base] ?? base
    }

    static func checkTimeout(firstSeconds: Double) -> Double { min(60, 2 * firstSeconds + 5) }

    static func boundedCheck<T: Sendable>(firstSeconds: Double, timeout: Duration? = nil, operation: @escaping @Sendable () async -> T) async -> T? {
        let task = Task { await operation() }
        defer { task.cancel() }
        return await awaitResult(task, timeout: timeout ?? .seconds(checkTimeout(firstSeconds: firstSeconds)))
    }
    static let shortSpeechSeconds = 5.0
    static let checkGap = 0.15

    /// Wirksame Hauptsprache (Basiscode): die gewählte, solange sie unter den Nutzersprachen
    /// ist; sonst die erste iPhone-Sprache, wenn sie darunter ist (nicht die erste Tastatur);
    /// sonst die erste Nutzersprache.
    static func primary(chosen: String?, userLanguages: [String], device: String?) -> String? {
        let codes = userLanguages.map(code).filter { !$0.isEmpty }
        for candidate in [chosen, device] {
            if let code = candidate.map(code), codes.contains(code) { return code }
        }
        return codes.first
    }

    public static func primary(_ settings: PaplySettings) -> String? {
        primary(chosen: settings.primaryLanguage, userLanguages: CodeSwitchPrimer.userLanguages(settings),
                device: Locale.preferredLanguages.first)
    }

    static func expected(previous: String?, primary: String?) -> String? {
        [previous, primary].compactMap { $0.map(code) }.first { !$0.isEmpty }
    }

    static func needsCheck(expected: String?, detected: String?, userLanguages: [String], spokenSeconds: Double) -> Bool {
        guard let expected = expected.map(code), !expected.isEmpty,
              let detected = detected.map(code), !detected.isEmpty,
              expected != detected else { return false }
        return spokenSeconds <= shortSpeechSeconds || !userLanguages.map(code).contains(detected)
    }

    enum Choice { case detected, expected }
    static func choose(detectedText: String, expectedText: String?, detectedConfidence: Double?, expectedConfidence: Double?, spokenSeconds: Double = 0) -> Choice {
        guard let expectedText else { return .detected }
        if normalize(detectedText) == normalize(expectedText) { return .expected }
        guard let detectedConfidence, let expectedConfidence else { return .detected }
        if spokenSeconds > shortSpeechSeconds { return expectedConfidence - detectedConfidence >= checkGap ? .expected : .detected }
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
