import Foundation

/// Form des Aufgabentexts, deterministisch nach der KI (ab Prompt v4, KONZEPT §6.7).
///
/// Nur Weglassen am Rand und Großschreiben – nie umformulieren, nie eine Verneinung entfernen. Was danach übrig
/// bleibt, ist eine Teilmenge der Wörter der KI; die Prüfung gegen das Zitat (Wörter, Ziffern, Verneinung) gilt
/// also unverändert.
///
/// 1. Zeitausdruck doppelt: Steht `due_hint` wörtlich und zusammenhängend (ohne Groß/Klein und Satzzeichen) im
///    Text, fällt er weg – am Anfang, am Ende oder (ab v5) in der Mitte, wenn danach mindestens 2 Wörter bleiben
///    („morgen einkaufen gehen“ + „morgen“ → „Einkaufen gehen“; „Reisepass bis Ende November verlängern“ +
///    „bis Ende November“ → „Reisepass verlängern“). Nicht, wenn er eine Verneinung enthält („nicht vor Freitag“), und
///    nicht direkt nach einem Wort, das ihn regiert („Anna wegen Freitag anrufen“, „Kuchen für morgen backen“).
/// 2. Füllwort am Rand: „noch“, „mal“, „eben“ am Anfang, nur vor einem großgeschriebenen Wort oder einem bestimmten
///    Artikel („noch Milch kaufen“, „noch die Belege prüfen“). So bleiben „noch nicht bezahlen“, „noch einen
///    Termin machen“ und „noch mal anrufen“ unberührt. Am Ende nur kleingeschrieben direkt nach einem
///    kleingeschriebenen Infinitiv („Anna anrufen mal“); „erst mal“, „nicht mal“, „nächstes Mal“ bleiben.
/// 3. Erster Buchstabe groß, außer das erste Wort trägt schon einen Großbuchstaben im Inneren („iPhone“, „eBay“).
///    Ziffern am Anfang bleiben („3 Kartons bestellen“), Umlaute werden groß („Übergabe …“).
///
/// Bleibt danach nichts Sinnvolles übrig (kein Buchstabe, keine Ziffer), gilt der Text der KI (nur großgeschrieben).
enum TaskText {
    /// Bewusst klein. Nicht dabei: „einmal“ (auch Zahlwort), „nochmal“ (= wieder), „halt“ („Halt machen“),
    /// „bitte“, „just“ (Marken wie „Just Eat“) – die übernimmt der Prompt.
    static let edgeFillers: Set<String> = ["noch", "mal", "eben"]
    static let definiteArticles: Set<String> = ["der", "die", "das", "den", "dem", "des"]

    static func tidy(_ raw: String, dueHint: String?) -> String {
        let original = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var words = original.split(separator: " ").map(String.init)
        if let dueHint { words = removingTimeExpression(dueHint, from: words) }
        words = removingEdgeFillers(words)
        var text = words.joined(separator: " ")
        text = trimmingEdgePunctuation(text)
        if !text.contains(where: { $0.isLetter || $0.isNumber }) { text = original }
        return capitalizedFirstLetter(text)
    }

    // MARK: Zeitausdruck

    /// Präpositionen und Artikel, die einen folgenden Zeitausdruck regieren: Fiele er weg, bliebe das Wort allein
    /// stehen („Anna wegen anrufen“). Dann bleibt der Text, wie er ist.
    static let governing: Set<String> = [
        "wegen", "für", "über", "von", "vom", "vor", "nach", "bis", "ab", "an", "am", "auf", "zu", "zum", "zur", "seit",
        "ohne", "mit", "um", "in", "im", "bei", "beim", "gegen", "der", "die", "das", "den", "dem", "des", "ein", "eine",
        "einen", "einem", "einer", "eines", "for", "about", "of", "to", "at", "on", "by", "until", "before", "after",
        "from", "since", "the", "a", "an",
    ]

    /// Entfernt den Zeitausdruck am Anfang, am Ende oder in der Mitte (Vergleich in der Form der Zitat-Prüfung).
    static func removingTimeExpression(_ hint: String, from words: [String]) -> [String] {
        let target = ThoughtValidator.normalizedForMatch(hint)
        guard !target.isEmpty, TextAnalysis.negationCount(hint) == 0, words.count > 1 else { return words }
        func matches(_ range: Range<Int>) -> Bool {
            ThoughtValidator.normalizedForMatch(words[range].joined(separator: " ")) == target
        }
        /// Das Wort vor der Stelle regiert sie nicht
        func free(before index: Int) -> Bool {
            index == 0 || !governing.contains(bare(words[index - 1]).lowercased())
        }
        let count = words.count
        for k in 1..<count where matches(0..<k) {
            return Array(words.dropFirst(k))
        }
        for k in 1..<count where matches((count - k)..<count) && free(before: count - k) {
            return Array(words.dropLast(k))
        }
        for start in 1..<count {
            for end in (start + 1)..<count where matches(start..<end) && free(before: start) && count - (end - start) >= 2 {
                var result = words
                result.removeSubrange(start..<end)
                // eingeschobener Zeitausdruck „Reisepass, bis Ende November, verlängern“: das Komma-Paar fällt mit
                if words[end - 1].hasSuffix(","), result[start - 1].hasSuffix(",") { result[start - 1].removeLast() }
                return result
            }
        }
        return words
    }

    // MARK: Füllwörter

    static func removingEdgeFillers(_ words: [String]) -> [String] {
        var words = words
        if words.count >= 2, edgeFillers.contains(bare(words[0]).lowercased()) {
            let next = bare(words[1])
            if next.first?.isUppercase == true || definiteArticles.contains(next.lowercased()) {
                words.removeFirst()
            }
        }
        if words.count >= 2, let last = words.last, edgeFillers.contains(bare(last)), isInfinitive(words[words.count - 2]) {
            words.removeLast()
        }
        return words
    }

    /// Kleingeschriebenes deutsches Verb im Infinitiv („anrufen“, „ändern“, „sammeln“), keine Verneinung
    private static func isInfinitive(_ word: String) -> Bool {
        let word = bare(word)
        guard word.count >= 4, word == word.lowercased(), !edgeFillers.contains(word),
              TextAnalysis.negationCount(word) == 0 else { return false }
        return word.hasSuffix("en") || word.hasSuffix("rn") || word.hasSuffix("ln")
    }

    /// Wort ohne Satzzeichen am Rand („noch,“ → „noch“)
    private static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    private static func trimmingEdgePunctuation(_ text: String) -> String {
        var text = text
        while let first = text.first, ",;:–—-".contains(first) || first == " " { text.removeFirst() }
        while let last = text.last, ",;:–—-".contains(last) || last == " " { text.removeLast() }
        return text
    }

    // MARK: Großschreibung

    static func capitalizedFirstLetter(_ text: String) -> String {
        guard let index = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return text }
        let first = text[index]
        guard first.isLetter, first.isLowercase else { return text }
        // „iPhone“, „eBay-Konto“, „macOS“: schon bewusst geschrieben („schufa-Auskunft“ wird groß)
        let word = text[index...].prefix(while: { !$0.isWhitespace && $0 != "-" })
        guard !word.dropFirst().contains(where: \.isUppercase) else { return text }
        let upper = String(first).uppercased()
        guard upper.count == 1 else { return text } // „ß“ → „SS“: lieber so lassen
        var result = text
        result.replaceSubrange(index...index, with: upper)
        return result
    }
}
