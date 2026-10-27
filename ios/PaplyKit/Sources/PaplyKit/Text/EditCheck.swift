import Foundation

/// Wortgenaue Prüfungen des Sicherheitsnetzes: Ziffern (Zahlen dürfen sich nicht ändern)
/// und Ersetzungen/Einfügungen (nur kleine Hörfehler-Korrekturen erlaubt).
/// Gilt für Schriften mit Leerzeichen; CJK/Thai bleibt bei der Bigramm-Prüfung.
enum EditCheck {
    // MARK: Zahlen

    /// Zahlwörter (Grund- und Ordnungszahlen) mit ihrem Wert, mehrsprachig.
    static let numberWords: [String: Int] = {
        var map: [String: Int] = [:]
        func add(_ value: Int, _ words: String...) { for w in words { map[TextAnalysis.normalizedLower(w)] = value } }
        // Deutsch
        add(0, "null"); add(1, "eins", "ein", "eine", "einen", "einem", "einer", "eines")
        add(2, "zwei"); add(3, "drei"); add(4, "vier"); add(5, "fünf"); add(6, "sechs"); add(7, "sieben")
        add(8, "acht"); add(9, "neun"); add(10, "zehn"); add(11, "elf"); add(12, "zwölf"); add(13, "dreizehn")
        add(14, "vierzehn"); add(15, "fünfzehn"); add(16, "sechzehn"); add(17, "siebzehn"); add(18, "achtzehn")
        add(19, "neunzehn"); add(20, "zwanzig"); add(30, "dreißig"); add(40, "vierzig"); add(50, "fünfzig")
        add(60, "sechzig"); add(70, "siebzig"); add(80, "achtzig"); add(90, "neunzig"); add(100, "hundert")
        add(1000, "tausend")
        for (stem, value) in [("erst", 1), ("zweit", 2), ("dritt", 3), ("viert", 4), ("fünft", 5), ("sechst", 6),
                              ("siebt", 7), ("acht", 8), ("neunt", 9), ("zehnt", 10)] {
            for ending in ["e", "en", "er", "es", "em", "ens"] { add(value, stem + ending) }
        }
        // Englisch
        add(0, "zero"); add(1, "one", "first", "firstly"); add(2, "two", "second", "secondly"); add(3, "three", "third", "thirdly")
        add(4, "four", "fourth"); add(5, "five", "fifth"); add(6, "six", "sixth"); add(7, "seven"); add(8, "eight")
        add(9, "nine"); add(10, "ten"); add(11, "eleven"); add(12, "twelve"); add(13, "thirteen"); add(14, "fourteen")
        add(15, "fifteen"); add(16, "sixteen"); add(17, "seventeen"); add(18, "eighteen"); add(19, "nineteen")
        add(20, "twenty"); add(30, "thirty"); add(40, "forty"); add(50, "fifty"); add(60, "sixty"); add(70, "seventy")
        add(80, "eighty"); add(90, "ninety"); add(100, "hundred"); add(1000, "thousand")
        // Französisch, Spanisch, Italienisch, Portugiesisch, Niederländisch (Grundzahlen bis 10)
        add(1, "un", "une", "premier", "première", "uno", "una", "primero", "primera", "primo", "um", "uma", "één")
        add(2, "deux", "deuxième", "dos", "segundo", "due", "dois", "duas", "twee")
        add(3, "trois", "troisième", "tres", "tercero", "tre", "terzo", "três", "drie")
        add(4, "quatre", "cuatro", "quattro", "quatro"); add(5, "cinq", "cinco", "cinque", "vijf")
        add(7, "sept", "siete", "sette", "sete", "zeven"); add(8, "huit", "ocho", "otto", "oito")
        add(9, "neuf", "nueve", "nove"); add(10, "dix", "diez", "dieci", "dez", "tien")
        return map
    }()

    static func numberValue(_ word: String) -> Int? {
        if !word.isEmpty, word.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) { return Int(word) }
        return numberWords[word]
    }

    /// Mengenangabe, nach der sich das folgende Wort nicht ändern darf („zwei Wochen“).
    /// Wörter mit Wert 1 (ein/one/un …) sind meist Artikel und zählen nicht.
    static func isQuantity(_ word: String) -> Bool {
        guard let value = numberValue(word) else { return false }
        return value != 1 || word.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
    }

    enum NumberToken: Equatable {
        case digits(String)
        case word(Int)
    }

    /// Zahlen eines Texts in Reihenfolge. Ziffernfolgen, zwischen denen nur Leerzeichen
    /// oder Satzzeichen stehen (kein Buchstabe), gelten als eine Zahl: „15.30“ = „15:30“
    /// = „1530“, „0171 123 45 67“ = „01711234567“, „1.000“ = „1000“.
    static func numberTokens(_ text: String) -> [NumberToken] {
        let lower = TextAnalysis.normalizedLower(text)
        let scalars = Array(lower.unicodeScalars)
        var tokens: [NumberToken] = []
        var i = 0
        func isDigit(_ s: Unicode.Scalar) -> Bool { ("0"..."9").contains(s) }
        while i < scalars.count {
            if isDigit(scalars[i]) {
                var digits = String.UnicodeScalarView()
                while i < scalars.count {
                    if isDigit(scalars[i]) {
                        digits.append(scalars[i])
                        i += 1
                        continue
                    }
                    // Trenner überspringen, solange kein Buchstabe kommt; folgt eine Ziffer, weiterzählen.
                    var j = i
                    while j < scalars.count, !isDigit(scalars[j]), !TextAnalysis.isLetter(scalars[j]) { j += 1 }
                    if j < scalars.count, isDigit(scalars[j]) { i = j } else { break }
                }
                tokens.append(.digits(String(digits)))
            } else if TextAnalysis.isLetter(scalars[i]) {
                var word = String.UnicodeScalarView()
                while i < scalars.count, TextAnalysis.isLetter(scalars[i]) || TextAnalysis.isMark(scalars[i]) {
                    word.append(scalars[i]); i += 1
                }
                if let value = numberWords[String(word)] { tokens.append(.word(value)) }
            } else {
                i += 1
            }
        }
        return tokens
    }

    /// Zahlen bleiben erhalten:
    /// - jede Ziffernfolge des Rohtexts steht – in Reihenfolge – im Ergebnis, als gleiche
    ///   Ziffern oder als Zahlwort gleichen Werts („3.“ → „Drittens“);
    /// - im Ergebnis gibt es keine neuen Ziffern, außer für ein Zahlwort des Rohtexts
    ///   („drei Uhr“ → „3 Uhr“).
    /// Eine korrigierte Zahl („15 Uhr, ich meine 16 Uhr“) prüft `resolvedSelfCorrection`.
    static func digitsPreserved(raw: String, result: String) -> Bool {
        let rawTokens = numberTokens(raw)
        let available = numberTokens(result)
        var used = Set<Int>()
        var position = 0
        for case .digits(let group) in rawTokens {
            guard let match = (position..<available.count).first(where: { index in
                switch available[index] {
                case .digits(let d): return d == group
                case .word(let v): return Int(group) == v
                }
            }) else { return false }
            used.insert(match)
            position = match + 1
        }
        var rawWordValues: [Int] = rawTokens.compactMap { if case .word(let v) = $0 { return v } else { return nil } }
        for (index, token) in available.enumerated() where !used.contains(index) {
            guard case .digits(let d) = token else { continue }
            guard let value = Int(d), let k = rawWordValues.firstIndex(of: value) else { return false }
            rawWordValues.remove(at: k)
        }
        return true
    }

    // MARK: Selbstkorrektur

    /// Eindeutige Marker einer Selbstkorrektur (nicht „eigentlich“, „doch“, „enfin“ – die
    /// kommen auch ohne Korrektur vor). Ein Marker zählt nur nach Komma/Gedankenstrich.
    static let correctionMarkers: [[String]] = [
        "ich meine", "ich mein", "moment", "warte", "sorry", "sorri", "pardon", "entschuldigung",
        "i mean", "wait", "je veux dire", "attends", "quiero decir", "perdón", "espera", "o sea",
        "voglio dire", "scusa", "aspetta", "ik bedoel", "wacht", "quer dizer", "quero dizer",
        "znaczy", "czekaj", "przepraszam", "yani", "pardon",
    ].map { TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower($0)) }

    /// Rohtext in der aufgelösten Lesart einer gesprochenen Selbstkorrektur, oder nil.
    ///
    /// „… um 15 Uhr, ich meine um 16 Uhr.“ → „… um 16 Uhr.“: Entfernt werden der Marker
    /// (samt „nein/no“ davor) und so viele Wörter davor, wie die Ersatzangabe danach bis zum
    /// nächsten Satzzeichen hat (höchstens 6, nie über ein Satzende hinweg).
    static func resolvedSelfCorrection(_ raw: String) -> String? {
        let tokens = TextAnalysis.runs(raw, where: TextAnalysis.isWordScalar)
        let words = tokens.map { TextAnalysis.normalizedLower($0.word) }
        func between(_ a: Int, _ b: Int) -> Substring { raw[tokens[a].range.upperBound..<tokens[b].range.lowerBound] }
        func hasPunctuation(_ gap: Substring, _ marks: Set<Character>) -> Bool { gap.contains(where: marks.contains) }
        let clauseMarks: Set<Character> = [",", ".", ";", "!", "?", ":", "–", "—", "…"]
        let sentenceMarks: Set<Character> = [".", "!", "?", "…"]
        var cuts: [Range<String.Index>] = []
        var i = 0
        while i < words.count {
            guard let marker = correctionMarkers.first(where: { m in
                i + m.count <= words.count && Array(words[i..<(i + m.count)]) == m
            }) else { i += 1; continue }
            var start = i
            if start > 0, Lexicon.answerNegators.contains(words[start - 1]) { start -= 1 }
            let end = i + marker.count
            let precededByComma = start > 0 && hasPunctuation(between(start - 1, start), [",", "–", "—", "-", "…", ";"])
            guard precededByComma, end < words.count else { i = end; continue }
            var replacement = 1
            while end + replacement < words.count, replacement < 6,
                  !hasPunctuation(between(end + replacement - 1, end + replacement), clauseMarks) {
                replacement += 1
            }
            var spanStart = start
            while spanStart > 0, start - spanStart < replacement,
                  !hasPunctuation(between(spanStart - 1, spanStart), sentenceMarks) {
                spanStart -= 1
            }
            guard spanStart < start else { i = end; continue }
            cuts.append(tokens[spanStart].range.lowerBound..<tokens[end].range.lowerBound)
            i = end + replacement
        }
        guard !cuts.isEmpty else { return nil }
        var resolved = raw
        for cut in cuts.reversed() { resolved.removeSubrange(cut) }
        return resolved
    }

    // MARK: Ersetzungen und Einfügungen

    /// Optimal-String-Alignment-Abstand (Damerau-Levenshtein mit Vertauschung).
    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[x.count][y.count]
    }

    /// Kleine Hörfehler-Korrektur: Abstand ≤ max(1, ⌊kürzere Länge / 4⌋).
    static func isSmallCorrection(_ a: String, _ b: String) -> Bool {
        editDistance(a, b) <= max(1, min(a.unicodeScalars.count, b.unicodeScalars.count) / 4)
    }

    /// Schreibvarianten, die als gleich gelten.
    static let spellingVariants: [Set<String>] = [["ok", "okay", "okey", "oke", "okej", "okee"]]

    static func areVariants(_ a: String, _ b: String) -> Bool {
        spellingVariants.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Rohtext-Wörter für den Vergleich: Zögerlaute und direkte Doppelwörter („ich ich“)
    /// fallen weg – ihr Entfernen ist erwünscht und darf keine Ausrichtung verschieben.
    static func cleanedWords(_ words: [String]) -> [String] {
        var out: [String] = []
        for word in words where !Lexicon.fillers.contains(word) {
            if out.last == word { continue }
            out.append(word)
        }
        return out
    }

    /// Grund ("replaced"/"inserted") oder nil.
    ///
    /// Rohtext (ohne Zögerlaute und Doppelwörter) und Ergebnis werden wortweise per LCS
    /// ausgerichtet. In jeder Lücke bekommt jedes Ergebniswort das nächste passende Rohwort;
    /// übersprungene Rohwörter gelten als gelöscht (Selbstkorrektur, Wiederholung – die
    /// Inhaltsprüfung begrenzt das). Passend heißt: gleich, Schreibvariante („ok“/„okay“),
    /// kleine Hörfehler-Korrektur (Abstand ≤ max(1, ⌊Länge/4⌋)) oder Ziffer↔Zahlwort.
    /// Nach einer Mengenangabe („zwei Wochen“) darf sich das Wort gar nicht ändern.
    /// Ohne passendes Rohwort ist ein Ergebniswort nur als eigener Begriff, Umstellung oder
    /// kurzes Funktionswort erlaubt; sonst „replaced“ (Rohwörter übrig) bzw. „inserted“.
    static func substitutionRejection(raw: String, result: String, vocabulary: String) -> String? {
        if TextAnalysis.containsScriptioContinua(raw) || TextAnalysis.containsScriptioContinua(result) { return nil }
        let (r, h) = compoundAligned(
            cleanedWords(TextAnalysis.alphanumericRuns(expandContractions(TextAnalysis.normalizedLower(raw)))),
            TextAnalysis.alphanumericRuns(expandContractions(TextAnalysis.normalizedLower(result))))
        guard !r.isEmpty, !h.isEmpty, r.count * h.count <= 4_000_000 else { return nil }
        let custom = Set(TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(vocabulary)))
        let pairs = lcsPairs(r, h)

        var matchedRaw = Set<Int>()
        for (i, _) in pairs { matchedRaw.insert(i) }
        var movable: [String: Int] = [:]
        for (i, word) in r.enumerated() where !matchedRaw.contains(i) { movable[word, default: 0] += 1 }

        func numberEquivalent(_ a: String, _ b: String) -> Bool {
            if let va = numberValue(a), let vb = numberValue(b) { return va == vb }
            return false
        }
        func compatible(_ a: String, _ b: String) -> Bool {
            a == b || numberEquivalent(a, b) || areVariants(a, b) || isSmallCorrection(a, b)
        }
        func isContent(_ word: String) -> Bool {
            TextAnalysis.weightedLength(word) >= 4 && !Lexicon.fillers.contains(word) && numberValue(word) == nil
        }

        var previous = (raw: -1, result: -1)
        for (i, j) in pairs + [(r.count, h.count)] {
            let rawStart = previous.raw + 1
            let gapRaw = Array(r[rawStart..<i])
            let gapResult = Array(h[(previous.result + 1)..<j])
            previous = (i, j)
            if gapResult.isEmpty || gapRaw.joined() == gapResult.joined() { continue }
            var pointer = 0
            for b in gapResult {
                if let k = (pointer..<gapRaw.count).first(where: { compatible(gapRaw[$0], b) }) {
                    let a = gapRaw[k]
                    let before = rawStart + k - 1
                    if a != b, !numberEquivalent(a, b), !areVariants(a, b), before >= 0, isQuantity(r[before]) {
                        return "replaced"
                    }
                    pointer = k + 1
                    continue
                }
                if let count = movable[b], count > 0 { movable[b] = count - 1; continue }
                if custom.contains(b) { pointer = min(pointer + 1, gapRaw.count); continue }
                if !isContent(b) { continue }
                return pointer < gapRaw.count ? "replaced" : "inserted"
            }
        }
        return nil
    }

    /// Zusammen-/Getrenntschreibung angleichen: „daten bank“ ↔ „datenbank“, „design system“
    /// ↔ „designsystem“. Zwei benachbarte Wörter werden verbunden, wenn die andere Seite
    /// genau die Verbindung (und nicht beide Einzelwörter) enthält.
    static func compoundAligned(_ raw: [String], _ result: [String]) -> ([String], [String]) {
        func merge(_ words: [String], against other: Set<String>) -> [String] {
            var out: [String] = []
            var i = 0
            while i < words.count {
                if i + 1 < words.count, !(other.contains(words[i]) && other.contains(words[i + 1])),
                   other.contains(words[i] + words[i + 1]) {
                    out.append(words[i] + words[i + 1])
                    i += 2
                } else {
                    out.append(words[i])
                    i += 1
                }
            }
            return out
        }
        let r = merge(raw, against: Set(result))
        return (r, merge(result, against: Set(r)))
    }

    private static let contractions: [(Pattern, String)] = [
        (Pattern("\\bcan['’]t\\b"), "can not"), (Pattern("\\bcannot\\b"), "can not"),
        (Pattern("\\bwon['’]t\\b"), "will not"), (Pattern("n['’]t\\b"), " not"),
        (Pattern("['’]re\\b"), " are"), (Pattern("['’]ve\\b"), " have"), (Pattern("['’]ll\\b"), " will"),
        (Pattern("\\bi['’]m\\b"), "i am"),
    ]

    /// Englische Kurzformen ausschreiben, damit „don't“ ↔ „do not“ keine Ersetzung ist.
    static func expandContractions(_ text: String) -> String {
        guard text.contains("'") || text.contains("’") || text.contains("cannot") else { return text }
        var out = text
        for (pattern, replacement) in contractions { out = pattern.replacing(in: out, with: replacement) }
        return out
    }

    /// Indexpaare der längsten gemeinsamen Teilfolge.
    static func lcsPairs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        var table = [UInt16](repeating: 0, count: (n + 1) * (m + 1))
        func at(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[at(i, j)] = a[i] == b[j] ? table[at(i + 1, j + 1)] + 1 : max(table[at(i + 1, j)], table[at(i, j + 1)])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                pairs.append((i, j)); i += 1; j += 1
            } else if table[at(i + 1, j)] >= table[at(i, j + 1)] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
