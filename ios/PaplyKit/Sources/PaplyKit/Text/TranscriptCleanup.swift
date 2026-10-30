import Foundation

/// Nacharbeit an Whisper-Ergebnissen: Prompt-Echos entfernen und Stücke zusammenfügen.
enum TranscriptCleanup {
    /// Unter dieser stimmhaften Zeit je Wort gilt Text, der wörtlich im Prompt steht, als
    /// Echo. Gesprochene Wörter bringen etwa 100–250 ms Vokal je Wort mit; ein Echo bei
    /// Stille, Atmen oder Rascheln fast keine.
    static let voicedMsPerWord = 100.0

    /// Entfernt Segmente, die Whisper aus dem Prompt wiederholt hat, obwohl im Zeitraum kaum
    /// gesprochen wurde. Echte Diktate mit denselben Wörtern bleiben, weil sie stimmhafte
    /// Sprache mitbringen.
    /// - Sprachwechsel-Beispiel: ab 3 Wörtern am Stück (2 Wörter wie „bis morgen“ werden
    ///   oft wirklich gesagt – bei viel Lärm misst die VAD dann womöglich zu wenig Stimme).
    /// - Ende des Vorstücks: ab 2 Wörtern (Whisper setzt es gern an den Stückanfang).
    /// - Eigene Begriffe: ≥ 80 % der Wörter aus der Liste (wie Desktop).
    ///
    /// - voiced: stimmhafte Zeit (ms) zwischen zwei Zeitpunkten (Sekunden im Stück).
    static func removeEchoes(text: String, segments: [WhisperSegment], primer: String?, previousText: String?,
                             vocabulary: String, duration: Double,
                             voiced: (Double, Double) -> Double) -> (text: String, segments: [WhisperSegment]) {
        let primerWords = TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(primer ?? ""))
        let tailWords = TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(previousText ?? ""))
        let vocab = PolishPrompt.vocabularyPrompt(vocabulary)
        func isEcho(_ piece: String, from start: Double, to end: Double) -> Bool {
            let words = TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(piece))
            guard !words.isEmpty else { return false }
            let fromPrimer = words.count >= 3 && containsSequence(primerWords, words)
            let fromTail = words.count >= 2 && containsSequence(tailWords, words)
            let fromVocabulary = !vocab.isEmpty && PolishPrompt.isVocabularyEcho(piece, vocabulary: vocab)
            guard fromPrimer || fromTail || fromVocabulary else { return false }
            return voiced(max(0, start - 0.2), end + 0.2) < voicedMsPerWord * Double(words.count)
        }
        guard !segments.isEmpty else {
            return isEcho(text, from: 0, to: duration) ? ("", []) : (text, [])
        }
        let kept = segments.filter { !isEcho($0.text ?? "", from: $0.start ?? 0, to: $0.end ?? duration) }
        if kept.count == segments.count { return (text, segments) }
        return (kept.map { ($0.text ?? "").trimmed }.filter { !$0.isEmpty }.joined(separator: " "), kept)
    }

    static func containsSequence(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return true
        }
        return false
    }

    /// Fügt Stücktexte zusammen: CJK/Thai ohne Leerzeichen, sonst mit einem Leerzeichen.
    /// Wiederholt ein Stück am Anfang die letzten Wörter des Vorstücks (Whisper greift das
    /// Ende aus dem Prompt auf), wird die Wiederholung entfernt.
    static func join(_ texts: [String]) -> String {
        var out = ""
        for text in texts {
            var next = text.trimmed
            guard !next.isEmpty else { continue }
            if out.isEmpty { out = next; continue }
            next = removeRepeatedLead(previous: out, next: next)
            guard !next.isEmpty else { continue }
            let joinsTight = out.unicodeScalars.last.map(isContinuaEdge) == true
                && next.unicodeScalars.first.map(isContinuaEdge) == true
            out += joinsTight ? next : " " + next
        }
        return out
    }

    private static func isContinuaEdge(_ scalar: Unicode.Scalar) -> Bool {
        TextAnalysis.isScriptioContinua(scalar) || TextAnalysis.isContinuaPunctuation(scalar)
    }

    static func removeRepeatedLead(previous: String, next: String) -> String {
        let previousWords = TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(previous))
        let nextTokens = TextAnalysis.runs(next, where: TextAnalysis.isWordScalar)
        let limit = min(10, previousWords.count, nextTokens.count)
        guard limit >= 2 else { return next }
        for k in stride(from: limit, through: 2, by: -1) {
            let lead = nextTokens.prefix(k).map { TextAnalysis.normalizedLower($0.word) }
            guard Array(previousWords.suffix(k)) == lead else { continue }
            // Zwei kurze Wörter („und so“) können echt doppelt gesprochen sein.
            if k == 2, !lead.contains(where: { TextAnalysis.weightedLength($0) >= 4 }) { continue }
            let rest = next[nextTokens[k - 1].range.upperBound...]
                .drop(while: { !$0.isLetter && !$0.isNumber })
            return String(rest)
        }
        return next
    }
}
