import Foundation

/// Sprachneutrale Zerlegung von Text für Sicherheitsnetz und Echo-Prüfung.
enum TextAnalysis {
    /// NFC, klein; türkisches i vereinheitlicht (U+0307 nach i entfernt, ı → i), damit
    /// „İstanbul“/„istanbul“/„ıstanbul“ und Groß-/Kleinschreibung gleich zählen.
    static func normalizedLower(_ text: String) -> String {
        let lower = text.precomposedStringWithCanonicalMapping.lowercased()
        guard lower.unicodeScalars.contains(where: { $0.value == 0x307 || $0.value == 0x131 }) else { return lower }
        var out = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in lower.unicodeScalars {
            if scalar.value == 0x307, previous == "i" { continue }
            let folded: Unicode.Scalar = scalar.value == 0x131 ? "i" : scalar
            out.append(folded)
            previous = folded
        }
        return String(out).precomposedStringWithCanonicalMapping
    }

    static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    static func isNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        isLetter(scalar) || isMark(scalar) || isNumber(scalar)
    }

    /// Schriften, die Wörter nicht mit Leerzeichen trennen (Chinesisch, Japanisch,
    /// Thai, Lao, Khmer, Myanmar). Koreanisch nutzt Leerzeichen und zählt nicht dazu.
    static func isScriptioContinua(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3005...0x3007, // 々 〆 〇
             0x3040...0x30FF, // Hiragana, Katakana
             0x31F0...0x31FF, // Katakana-Erweiterung
             0x3400...0x4DBF, // CJK Erweiterung A
             0x4E00...0x9FFF, // CJK Ideogramme
             0xF900...0xFAFF, // CJK Kompatibilität
             0xFF66...0xFF9D, // Halbbreite Katakana
             0x20000...0x2FA1F, // CJK Erweiterungen B ff.
             0x0E00...0x0E7F, // Thai
             0x0E80...0x0EFF, // Lao
             0x1000...0x109F, // Myanmar
             0x1780...0x17FF: // Khmer
            return true
        default:
            return false
        }
    }

    /// CJK-Satzzeichen (。、！？「」 …), nach denen ohne Leerzeichen weitergeschrieben wird.
    static func isContinuaPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        (0x3000...0x303F).contains(scalar.value) || (0xFF01...0xFF0F).contains(scalar.value)
            || (0xFF1A...0xFF20).contains(scalar.value)
    }

    static func containsScriptioContinua(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isScriptioContinua)
    }

    /// Wortlänge für die „≥ 4 Zeichen“-Regel; eine Hangul-Silbe zählt doppelt.
    static func weightedLength(_ word: String) -> Int {
        word.unicodeScalars.reduce(0) { $0 + ((0xAC00...0xD7A3).contains($1.value) ? 2 : 1) }
    }

    /// Maximale Folgen aus Buchstaben und kombinierenden Zeichen (Wörter ohne Ziffern).
    static func letterRuns(_ text: String) -> [String] {
        runs(text) { isLetter($0) || isMark($0) }.map(\.word)
    }

    /// Maximale Folgen aus Buchstaben, Zeichen und Ziffern.
    static func alphanumericRuns(_ text: String) -> [String] {
        runs(text, where: isWordScalar).map(\.word)
    }

    /// Wörter mit ihrem Bereich im übergebenen Text.
    static func runs(_ text: String, where belongs: (Unicode.Scalar) -> Bool) -> [(word: String, range: Range<String.Index>)] {
        var result: [(String, Range<String.Index>)] = []
        var start: String.Index?
        var index = text.unicodeScalars.startIndex
        while index != text.unicodeScalars.endIndex {
            let scalar = text.unicodeScalars[index]
            if belongs(scalar) {
                if start == nil { start = index }
            } else if let s = start {
                result.append((String(text.unicodeScalars[s..<index]), s..<index))
                start = nil
            }
            index = text.unicodeScalars.index(after: index)
        }
        if let s = start { result.append((String(text.unicodeScalars[s...]), s..<text.unicodeScalars.endIndex)) }
        return result
    }

    /// Inhaltseinheiten für die Inhalts- und Zusatzprüfung.
    ///
    /// - Schriften mit Leerzeichen: Wörter ab 4 Zeichen ohne Zögerlaute (wie Desktop).
    ///   Eine Hangul-Silbe zählt dabei doppelt (sie trägt 2–3 Laute; sonst fielen fast
    ///   alle koreanischen Wörter unter die Grenze).
    /// - Schriften ohne Leerzeichen (CJK/Thai …): überlappende Zeichen-Bigramme.
    ///   Begründung: Eine ganze Zeichenfolge zwischen zwei Satzzeichen wäre sonst ein
    ///   einziges „Wort“; schon ein korrigiertes Zeichen ließe dann den ganzen Satz als
    ///   „fehlend“ gelten. Bigramme (Standard der CJK-Volltextsuche) messen stattdessen,
    ///   wie viel des Zeichenbestands erhalten blieb: ein geändertes Zeichen kostet
    ///   höchstens zwei Einheiten, die 30-%-Grenze entspricht damit etwa 15 % geänderter
    ///   Zeichen – genug für Interpunktion und einzelne Hörfehler, zu wenig für eine
    ///   Umformulierung oder Übersetzung.
    static func contentUnits(_ text: String) -> [String] {
        var units: [String] = []
        for run in letterRuns(normalizedLower(text)) {
            var latin = String.UnicodeScalarView()
            var continua: [Unicode.Scalar] = []
            func flushLatin() {
                let word = String(latin)
                if weightedLength(word) >= 4, !Lexicon.fillers.contains(word) { units.append(word) }
                latin = String.UnicodeScalarView()
            }
            func flushContinua() {
                if continua.count == 1 {
                    units.append(String(String.UnicodeScalarView(continua)))
                } else if continua.count > 1 {
                    for i in 0..<(continua.count - 1) {
                        units.append(String(String.UnicodeScalarView([continua[i], continua[i + 1]])))
                    }
                }
                continua.removeAll()
            }
            for scalar in run.unicodeScalars {
                if isScriptioContinua(scalar) {
                    flushLatin()
                    continua.append(scalar)
                } else {
                    flushContinua()
                    latin.append(scalar)
                }
            }
            flushLatin()
            flushContinua()
        }
        return units
    }

    /// Anzahl der Verneinungen (Wortliste mehrerer Sprachen, englische n't-Kurzformen,
    /// CJK/Thai/Koreanische Verneinungszeichen).
    ///
    /// „no/non/nee/nein“: Am Satzanfang zählen sie immer – egal, ob danach ein Komma steht
    /// („Nein das passt“ = „Nein, das passt“) und weil sie in es/it/pt dort das Verb
    /// verneinen („No quiero“, „Non posso“). Mitten im Satz zählen sie nur, wenn kein
    /// Satzzeichen und kein Korrekturwort folgt („no problem“ ja, „…, no wait, …“ nein).
    static func negationCount(_ text: String) -> Int {
        let lower = normalizedLower(text)
        var count = 0
        for (word, range) in runs(lower, where: { isLetter($0) || isMark($0) }) {
            if Lexicon.negations.contains(word) {
                count += 1
            } else if Lexicon.answerNegators.contains(word),
                      isSentenceStart(lower, before: range.lowerBound) || isSentenceInternal(lower, after: range.upperBound) {
                count += 1
            }
        }
        count += Lexicon.contractedNegation.count(in: lower)
        for scalar in lower.unicodeScalars where Lexicon.negationScalars.contains(scalar) { count += 1 }
        for fragment in Lexicon.negationFragments {
            count += lower.components(separatedBy: fragment).count - 1
        }
        return count
    }

    /// Steht vor `index` nur Textbeginn, Satzende (. ! ? … :) oder öffnende Zeichen?
    private static func isSentenceStart(_ text: String, before index: String.Index) -> Bool {
        let opening: Set<Character> = [" ", "\t", "\n", "¡", "¿", "\"", "„", "“", "«", "(", "‚", "'"]
        let head = text[..<index].reversed().drop(while: opening.contains)
        guard let last = head.first else { return true }
        return [".", "!", "?", "…", ":"].contains(last)
    }

    /// Folgt nach `index` direkt (nur durch Leerzeichen getrennt) ein Wort, das keine
    /// Selbstkorrektur einleitet?
    private static func isSentenceInternal(_ text: String, after index: String.Index) -> Bool {
        let rest = text[index...].drop(while: { $0 == " " || $0 == "\t" })
        guard let first = rest.unicodeScalars.first, isLetter(first) else { return false }
        for phrase in Lexicon.correctionPhrases where rest.hasPrefix(phrase) {
            let after = rest.dropFirst(phrase.count)
            if after.isEmpty || !(after.unicodeScalars.first.map(isWordScalar) ?? false) { return false }
        }
        return true
    }
}
