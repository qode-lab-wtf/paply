import Foundation

/// `prompt` für die Whisper-Transkription: eigene Begriffe plus (bei Stücken) das Ende des
/// vorigen Stücks. Whisper verarbeitet höchstens 224 Prompt-Tokens und schneidet sonst
/// stillschweigend vorne ab – deshalb hart und konservativ auf 200 geschätzte begrenzen.
enum WhisperPrompt {
    static let tokenLimit = 200
    /// Höchstanteile für Sprachwechsel-Beispiel und eigene Begriffe; der Rest (≥ 46 Tokens)
    /// gehört dem Ende des Vorstücks.
    static let primerTokenShare = 64
    static let vocabularyTokenShare = 90

    /// Konservative Token-Schätzung für den mehrsprachigen Whisper-Tokenizer (Byte-BPE):
    /// ASCII-Buchstaben/Ziffern ≥ 2 Zeichen je Token (real eher 3–4), jedes
    /// ASCII-Satzzeichen 1 Token, lateinische Sonderzeichen (Umlaute, Akzente) je 1 Token,
    /// seltenere Schriften mit 2-Byte-UTF-8 (Kyrillisch, Griechisch, Arabisch, Hebräisch …)
    /// je 2, alles darüber (CJK, Thai …) so viele Tokens wie UTF-8-Bytes.
    /// Jedes Wort zählt mindestens 1. Lieber kürzen als abgeschnitten werden.
    static func estimateTokens(_ text: String) -> Int {
        var total = 0
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            var asciiAlnum = 0
            var cost = 0
            for scalar in word.unicodeScalars {
                if scalar.isASCII, scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) {
                    asciiAlnum += 1
                } else {
                    cost += scalarCost(scalar)
                }
            }
            cost += (asciiAlnum + 1) / 2
            total += max(1, cost)
        }
        return total
    }

    static func scalarCost(_ scalar: Unicode.Scalar) -> Int {
        if scalar.isASCII || (0x80...0x24F).contains(scalar.value) { return 1 }
        if scalar.value < 0x800 { return 2 }
        return String(scalar).utf8.count
    }

    /// Baut den Prompt: Sprachwechsel-Beispiel, eigene Begriffe, Ende des Vorstücks (direkt
    /// vor dem neuen Audio, deshalb zuletzt). nil, wenn nichts zu senden ist.
    static func build(vocabulary: String, previousText: String?, primer: String? = nil) -> String? {
        var parts: [String] = []
        var used = 0
        if let primer = primer?.trimmed, !primer.isEmpty, estimateTokens(primer) <= primerTokenShare {
            parts.append(primer)
            used += estimateTokens(primer)
        }
        var vocab = PolishPrompt.vocabularyPrompt(vocabulary)
        if estimateTokens(vocab) > vocabularyTokenShare {
            vocab = truncateItems(vocab, budget: vocabularyTokenShare)
        }
        if !vocab.isEmpty {
            let item = vocab.hasSuffix(".") ? vocab : vocab + "."
            parts.append(item)
            used += estimateTokens(item)
        }
        if let previousText, !previousText.trimmed.isEmpty {
            let tail = tailWords(previousText.trimmed, budget: tokenLimit - used)
            if !tail.isEmpty { parts.append(tail) }
        }
        let prompt = parts.joined(separator: " ")
        return prompt.isEmpty ? nil : prompt
    }

    /// Ganze Begriffe von vorne übernehmen, solange das Budget reicht.
    static func truncateItems(_ vocab: String, budget: Int) -> String {
        var kept: [String] = []
        for item in vocab.components(separatedBy: ", ") {
            let candidate = (kept + [item]).joined(separator: ", ")
            if estimateTokens(candidate) > budget { break }
            kept.append(item)
        }
        return kept.joined(separator: ", ")
    }

    /// Ganze Wörter vom Ende übernehmen, solange das Budget reicht (Kontext direkt vor
    /// dem neuen Stück ist der wertvollste).
    static func tailWords(_ text: String, budget: Int) -> String {
        guard budget > 0 else { return "" }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        var used = 0
        var start = words.endIndex
        while start > words.startIndex {
            let cost = estimateTokens(String(words[start - 1]))
            if used + cost > budget { break }
            used += cost
            start -= 1
        }
        // Einzelnes überlanges Wort (z. B. CJK-Satz ohne Leerzeichen): Zeichen vom Ende.
        if start == words.endIndex, let last = words.last {
            var scalars: [Unicode.Scalar] = []
            var cost = 0
            for scalar in last.unicodeScalars.reversed() {
                let c = scalarCost(scalar)
                if cost + c > budget { break }
                cost += c
                scalars.insert(scalar, at: 0)
            }
            return String(String.UnicodeScalarView(scalars))
        }
        return words[start...].joined(separator: " ")
    }
}
