import Foundation

/// Gesprochene Zahlen für das Gedanken-Profil (KONZEPT §6.7; Bewertungssatz README §7, Spannungen 1–3).
///
/// Whisper liefert Zahlen oft als Wörter, auch zusammengesetzt („achtundzwanzigsten“,
/// „siebenhundertfünfzig“, „twenty eight“). Ein guter `clean_text`, Titel oder Aufgabentext schreibt sie
/// als Ziffern. Die Diktat-Prüfung (`EditCheck`) kennt nur einzelne Zahlwörter und fasst Ziffern über
/// Satzzeichen zusammen – dort bleibt alles unverändert. Für Gedanken gilt stattdessen:
/// - Zahlen werden als **Werte** verglichen: Ziffern (mit Tausenderpunkt „6.500“; „15:30“, „1,5“ und
///   „28.12.“ sind getrennte Zahlen) und Zahlwörter (Deutsch zusammengesetzt mit Ordinalendungen,
///   Englisch mehrteilig).
/// - Jeder gesprochene Wert steht im Ergebnis (als Ziffer oder Wort), außer er wurde im Satz korrigiert
///   („38 Minuten nee warte 36“: die 38 darf fehlen).
/// - Jede Ziffer des Ergebnisses ist ein gesprochener Wert. Artikel („ein“, „one“), Aufzählungen
///   („erstens“), „erste/first/second“ und Monatsnamen zählen als Quelle, sind aber nicht verlangt.
package enum SpokenNumbers {
    package enum Kind: Sendable, Equatable {
        /// Ziffern im Text
        case digits
        /// Zahlwort („zwanzig“, „achtundzwanzigsten“, „twenty eight“)
        case word
        /// Quelle, keine Pflicht: Artikel, Aufzählung, „erste/first/second“, Monatsname
        case optional
    }

    package struct Token: Sendable, Equatable {
        package var value: Int
        package var kind: Kind
        /// Index des (ersten) Worts in `words(_:)`
        package var word: Int
    }

    // MARK: Prüfungen

    /// Zahlen bleiben erhalten (Gedanken-Profil des Sicherheitsnetzes).
    package static func preserved(raw: String, result: String) -> Bool {
        let rawWords = words(raw)
        let rawTokens = tokens(rawWords)
        let resultTokens = tokens(words(result))
        let found = Set(resultTokens.map(\.value))
        let corrected = correctedWords(rawWords, tokens: rawTokens)
        for token in rawTokens where token.kind != .optional {
            if !found.contains(token.value) && !corrected.contains(token.word) { return false }
        }
        let source = Set(rawTokens.map(\.value))
        return resultTokens.allSatisfy { $0.kind != .digits || source.contains($0.value) }
    }

    /// Ziffern in `text` (Titel, Aufgabe, Grund) stammen aus `source`.
    package static func digitsContained(_ text: String, in source: String) -> Bool {
        let available = values(source)
        return tokens(text).allSatisfy { $0.kind != .digits || available.contains($0.value) }
    }

    /// Ist das Wort Teil einer Zahl? Für den Inhaltsvergleich: Zahlwörter zählen dort nicht, sie prüft
    /// `preserved`. Monatsnamen und Artikel bleiben Inhalt.
    package static func isNumberWord(_ word: String) -> Bool {
        let lower = TextAnalysis.normalizedLower(word)
        if english[lower] != nil || lower == "hundred" || lower == "thousand" { return true }
        if enumerators[lower] != nil { return true }
        if articles.contains(lower) || months[lower] != nil { return false }
        return germanValue(lower) != nil
    }

    // MARK: Werte

    /// Alle Zahlen eines Texts in Reihenfolge.
    package static func tokens(_ text: String) -> [Token] { tokens(words(text)) }

    /// Werte, die ein Text als Quelle für Ziffern hergibt (alle Arten).
    package static func values(_ text: String) -> Set<Int> { Set(tokens(text).map(\.value)) }

    struct Word {
        var text: String
        var digits: Int?
    }

    /// Wörter und Ziffernfolgen (klein). „6.500“/„6 500“/„6’500“ = eine Zahl (Gruppen aus genau 3 Ziffern);
    /// „15:30“, „1,5“, „28.12.“ = getrennte Zahlen. Bindestriche trennen Wörter („twenty-eight“).
    static func words(_ text: String) -> [Word] {
        let scalars = Array(TextAnalysis.normalizedLower(text).unicodeScalars)
        func isDigit(_ s: Unicode.Scalar) -> Bool { ("0"..."9").contains(s) }
        let groupSeparators: Set<Unicode.Scalar> = [".", " ", "’", "'", "\u{202F}", "\u{00A0}"]
        var result: [Word] = []
        var i = 0
        while i < scalars.count {
            if isDigit(scalars[i]) {
                var digits = String.UnicodeScalarView()
                while i < scalars.count, isDigit(scalars[i]) { digits.append(scalars[i]); i += 1 }
                while i + 3 < scalars.count, groupSeparators.contains(scalars[i]) {
                    let group = scalars[(i + 1)...].prefix(while: isDigit)
                    guard group.count == 3 else { break }
                    digits.append(contentsOf: group)
                    i += 4
                }
                let text = String(digits)
                result.append(Word(text: text, digits: text.count <= 12 ? Int(text) : nil))
            } else if TextAnalysis.isLetter(scalars[i]) {
                var word = String.UnicodeScalarView()
                while i < scalars.count, TextAnalysis.isLetter(scalars[i]) || TextAnalysis.isMark(scalars[i]) {
                    word.append(scalars[i]); i += 1
                }
                result.append(Word(text: String(word), digits: nil))
            } else {
                i += 1
            }
        }
        return result
    }

    static func tokens(_ words: [Word]) -> [Token] {
        var tokens: [Token] = []
        var i = 0
        while i < words.count {
            if let value = words[i].digits {
                tokens.append(Token(value: value, kind: .digits, word: i))
                i += 1
                continue
            }
            if let (value, used) = englishSequence(words, from: i) {
                let single = used == 1 ? words[i].text : ""
                let optional = ["one", "first", "second"].contains(single)
                tokens.append(Token(value: value, kind: optional ? .optional : .word, word: i))
                i += used
                continue
            }
            if let token = germanToken(words[i].text, index: i) { tokens.append(token) }
            i += 1
        }
        return tokens
    }

    // MARK: Selbstkorrektur ohne Satzzeichen

    static let negators: Set<String> = ["nee", "nein", "ne", "nö", "no", "nope", "non"]
    /// Marker nach einem Verneiner („nee warte“, „nein Quatsch“, „no wait“)
    static let afterNegator: Set<String> = ["warte", "moment", "quatsch", "falsch", "sorry", "stopp", "wait", "scratch"]
    /// Marker, die allein reichen
    static let standalone: [[String]] = [["ich", "meine"], ["ich", "mein"], ["i", "mean"], ["scratch", "that"], ["korrektur"]]

    /// Wortindizes von Zahlen, die direkt danach korrigiert werden:
    /// Zahl, ≤ 5 Wörter, Marker, ≤ 3 Wörter, neue Zahl („38 Minuten nee warte 36“).
    static func correctedWords(_ words: [Word], tokens: [Token]) -> Set<Int> {
        let texts = words.map(\.text)
        var result: Set<Int> = []
        var i = 0
        while i < texts.count {
            var end: Int?
            if negators.contains(texts[i]) {
                if i + 1 < texts.count, afterNegator.contains(texts[i + 1]) {
                    end = i + 2
                } else if tokens.contains(where: { $0.word == i + 1 && $0.kind != .optional }) {
                    end = i + 1 // „38 nein 36“
                }
            } else if let marker = standalone.first(where: { i + $0.count <= texts.count && Array(texts[i..<(i + $0.count)]) == $0 }) {
                end = i + marker.count
            }
            guard let end else { i += 1; continue }
            let next = tokens.first { $0.word >= end && $0.word <= end + 3 && $0.kind != .optional }
            let previous = tokens.last { $0.word < i && $0.word >= i - 6 && $0.kind != .optional }
            if next != nil, let previous { result.insert(previous.word) }
            i = end
        }
        return result
    }

    // MARK: Englisch

    static let english: [String: Int] = {
        var map: [String: Int] = [:]
        let cardinals = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                         "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        for (value, word) in cardinals.enumerated() { map[word] = value }
        let ordinals = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh",
                        "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth"]
        for (value, word) in ordinals.enumerated() where !word.isEmpty { map[word] = value }
        for (value, word) in [(20, "twenty"), (30, "thirty"), (40, "forty"), (50, "fifty"), (60, "sixty"), (70, "seventy"),
                              (80, "eighty"), (90, "ninety")] {
            map[word] = value
            map[String(word.dropLast()) + "ieth"] = value
        }
        return map
    }()

    private enum Place { case none, unit, tens, hundred, thousand }

    /// Mehrteilige englische Zahl ab `start`: „twenty eight“, „seven hundred (and) fifty“,
    /// „two thousand twenty six“. Liefert Wert und Zahl der verbrauchten Wörter.
    private static func englishSequence(_ words: [Word], from start: Int) -> (Int, Int)? {
        var total = 0
        var current = 0
        var last = Place.none
        var k = start
        scan: while k < words.count, words[k].digits == nil {
            let w = words[k].text
            if let v = english[w] {
                switch last {
                case .none: current = v
                case .tens where (1...9).contains(v): current += v
                case .hundred, .thousand: current += v
                default: break scan
                }
                last = v >= 20 && v % 10 == 0 ? .tens : .unit
            } else if w == "hundred", last == .none || last == .unit || last == .tens {
                current = max(1, current) * 100
                last = .hundred
            } else if w == "thousand", last != .thousand {
                total += max(1, current) * 1000
                current = 0
                last = .thousand
            } else if w == "and", last == .hundred || last == .thousand, k + 1 < words.count, english[words[k + 1].text] != nil {
                k += 1
                continue
            } else {
                break
            }
            k += 1
        }
        guard last != .none else { return nil }
        return (total + current, k - start)
    }

    // MARK: Deutsch

    static let units: [String: Int] = ["eins": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6,
                                       "sieben": 7, "acht": 8, "neun": 9]
    static let teens: [String: Int] = ["zehn": 10, "elf": 11, "zwölf": 12, "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15,
                                       "sechzehn": 16, "siebzehn": 17, "achtzehn": 18, "neunzehn": 19]
    static let tens: [String: Int] = ["zwanzig": 20, "dreißig": 30, "vierzig": 40, "fünfzig": 50, "sechzig": 60,
                                      "siebzig": 70, "achtzig": 80, "neunzig": 90]
    static let articles: Set<String> = ["ein", "eine", "einen", "einem", "einer", "eines", "a", "an"]
    static let enumerators: [String: Int] = ["erstens": 1, "zweitens": 2, "drittens": 3, "viertens": 4, "fünftens": 5,
                                             "sechstens": 6, "siebtens": 7, "achtens": 8, "neuntens": 9, "zehntens": 10,
                                             "firstly": 1, "secondly": 2, "thirdly": 3]
    static let months: [String: Int] = {
        var map: [String: Int] = [:]
        let german = ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"]
        let english = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        for (index, name) in german.enumerated() { map[name] = index + 1 }
        for (index, name) in english.enumerated() { map[name] = index + 1 }
        map["jänner"] = 1
        return map
    }()
    /// Unregelmäßige Ordnungszahl-Stämme („erste“, „dritten“, „siebte“, „achte“)
    static let ordinalStems: [String: Int] = ["erst": 1, "dritt": 3, "siebt": 7, "acht": 8]

    private static func germanToken(_ word: String, index: Int) -> Token? {
        if articles.contains(word) { return Token(value: 1, kind: .optional, word: index) }
        if let value = enumerators[word] ?? months[word] { return Token(value: value, kind: .optional, word: index) }
        guard let value = germanValue(word) else { return nil }
        // „erste“ ist oft keine Zahl („erster Gedanke“) – Quelle, keine Pflicht.
        return Token(value: value, kind: value == 1 && word.hasPrefix("erst") ? .optional : .word, word: index)
    }

    /// „achtundzwanzigsten“ → 28, „zweitausendsechsundzwanzig“ → 2026, „vierzehnhundertfünfzig“ → 1450,
    /// „zweimal“ → 2, „elften“ → 11, „erste“ → 1.
    static func germanValue(_ word: String) -> Int? {
        guard word.count >= 3 else { return nil }
        if let value = cardinal(word) { return value }
        if word.hasSuffix("mal"), word.count > 5, let value = cardinal(String(word.dropLast(3))) { return value }
        for ending in ["e", "en", "er", "es", "em"] {
            for (stem, value) in ordinalStems where word == stem + ending { return value }
        }
        // Ordnungszahlen: ab 20 „-ste…“, darunter „-te…“
        for ending in ["sten", "ster", "stes", "stem", "ste", "ten", "ter", "tes", "tem", "te"] where word.hasSuffix(ending) {
            if let value = cardinal(String(word.dropLast(ending.count))), value > 1 { return value }
        }
        return nil
    }

    private static func cardinal(_ word: String) -> Int? {
        guard !word.isEmpty else { return nil }
        if let range = word.range(of: "tausend") {
            let head = String(word[..<range.lowerBound])
            let tail = String(word[range.upperBound...])
            let high = head.isEmpty || head == "ein" ? 1 : below1000(head)
            let low = tail.isEmpty ? 0 : below1000(tail.hasPrefix("und") ? String(tail.dropFirst(3)) : tail)
            guard let high, let low, high > 0 else { return nil }
            return high * 1000 + low
        }
        return below1000(word)
    }

    private static func below1000(_ word: String) -> Int? {
        if let range = word.range(of: "hundert") {
            let head = String(word[..<range.lowerBound])
            let tail = String(word[range.upperBound...])
            let high = head.isEmpty || head == "ein" ? 1 : below100(head)
            let low = tail.isEmpty ? 0 : below100(tail.hasPrefix("und") ? String(tail.dropFirst(3)) : tail)
            guard let high, let low, (1...99).contains(high) else { return nil }
            return high * 100 + low
        }
        return below100(word)
    }

    private static func below100(_ word: String) -> Int? {
        if let value = units[word] ?? teens[word] ?? tens[word] { return value }
        if let range = word.range(of: "und") {
            let unitWord = String(word[..<range.lowerBound])
            let tensWord = String(word[range.upperBound...])
            guard let unit = unitWord == "ein" ? 1 : units[unitWord], let ten = tens[tensWord] else { return nil }
            return ten + unit
        }
        return nil
    }
}
