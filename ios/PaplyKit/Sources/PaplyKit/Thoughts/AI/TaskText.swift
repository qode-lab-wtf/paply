import Foundation

/// Form des Aufgabentexts, deterministisch nach der KI (ab Prompt v4, KONZEPT §6.7).
///
/// Leitsatz: Diese Regeln dürfen den Sinn nie ändern. Im Zweifel bleibt der Text, wie er ist – lieber ein doppelter
/// Zeitausdruck als eine falsche Aufgabe. Nur Weglassen am Rand und Großschreiben, nie umformulieren. Was übrig bleibt,
/// ist eine Teilmenge der Wörter der KI; die Prüfung gegen das Zitat (Wörter, Ziffern, Verneinung) gilt unverändert.
///
/// 1. Zeitausdruck doppelt: Steht `due_hint` wörtlich und zusammenhängend (ohne Groß/Klein und Satzzeichen) ganz am
///    Anfang oder ganz am Ende, fällt er weg – nur wenn alles gilt (dritte Prüfrunde):
///    a) Keine Verneinung im ganzen Text und im `due_hint` („nicht morgen anrufen“, „Kein Termin morgen“, „Anna
///       anrufen, aber nicht morgen“ bleiben).
///    b) Das Nachbarwort auf der verbleibenden Seite steht in keiner Sperrliste: Bindewort, Gradpartikel, Präposition,
///       Zahl oder Tageszeit („morgen früh und abends gießen“, „morgen nur Anna anrufen“, „Kuchen backen für morgen“).
///       Am Ende zusätzlich kein Artikel und kein Begleiter, der den Ausdruck regiert („… nächsten Freitag“).
///    c) Danach bleiben mindestens 2 Wörter („Freitag absagen“, „Weihnachten planen“ bleiben).
///    d) `due_hint` nennt einen Zeitpunkt oder eine Frist, keinen Zeitraum: nicht mit „bis“, „ab“, „seit“, „von“,
///       „until“ … („Urlaub verlängern bis Freitag“: Der Endtermin kann zum Objekt gehören). Ob „bis Freitag“ eine Frist
///       oder ein Endtermin ist, steht nicht sicher im Text – also nie streichen. „bis spätestens …“ ist eine Frist.
///    e) Nur am Ende: Der verbleibende Text enthält keine Präposition. Sonst kann der Ausdruck an ihr hängen („Frau
///       Brandt fragen wegen Ausmessen am Samstag“: Samstag ist das Ausmessen, nicht das Fragen).
///    Aus der Mitte fällt nie etwas weg („Reisepass bis Ende November verlängern“ bleibt).
/// 2. Füllwort am Rand: „noch“, „mal“, „eben“ am Anfang nur vor einem großgeschriebenen Wort oder einem bestimmten
///    Artikel („noch Milch kaufen“, „noch die Belege prüfen“). So bleiben „noch nicht bezahlen“, „noch einen Termin
///    machen“ und „noch mal anrufen“ unberührt. Am Ende nur kleingeschrieben direkt nach einem kleingeschriebenen
///    Infinitiv („Anna anrufen mal“); „erst mal“, „nicht mal“, „nächstes Mal“ bleiben. Nie mit einer Verneinung im
///    selben Teilsatz („noch Milch nicht kaufen“ = noch nicht; „noch Bescheid sagen: Vertrag nicht verlängern“ darf).
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

    // MARK: Verneinung

    /// Verneinungen, die `TextAnalysis.negationCount` nicht oder nur an bestimmten Stellen zählt („ohne“, „no“ mitten
    /// im Satz, „dont“ ohne Apostroph)
    static let extraNegations: Set<String> = folded([
        "ohne", "without", "no", "nein", "nee", "non", "nope", "dont", "doesnt", "didnt", "cant", "wont", "isnt",
        "arent", "wasnt", "shouldnt", "mustnt", "neednt", "havent", "hasnt",
    ])

    /// Enthält der Text irgendeine Verneinung? Dann bleibt er, wie er ist.
    static func isNegated(_ text: String) -> Bool {
        TextAnalysis.negationCount(text) > 0 || words(text).contains(where: extraNegations.contains)
    }

    // MARK: Zeitausdruck

    /// Bindewörter, Gradpartikeln, Präpositionen: Steht eins neben dem Zeitausdruck, gehört er zu mehr als der ganzen
    /// Aufgabe („morgen früh und abends“, „statt morgen“, „morgen nur …“, „für morgen“). Gilt auf beiden Seiten.
    static let blockedNeighbors: Set<String> = folded([
        // Sperrliste des Bauleiters
        "und", "oder", "bzw", "aber", "sondern", "statt", "anstatt", "erst", "nur", "bis", "ab", "seit", "für", "wegen",
        "am", "an", "zum", "zur", "vor", "nach", "and", "or", "but", "instead", "until", "by", "for", "before", "after",
        // gleiche Art
        "beziehungsweise", "sowie", "als", "außer", "sonst", "anstelle", "zwischen", "von", "vom", "spätestens",
        "frühestens", "schon", "bereits", "wenn", "falls", "sobald", "bevor", "nachdem", "ob", "dass", "than", "rather",
        "except", "nor", "only", "already", "if", "when", "once", "unless", "between", "from", "since", "till", "til",
        "latest", "earliest",
        // Tageszeiten und Zeitwörter: Der Ausdruck war nur ein Teil der Zeitangabe („morgen | Abend …“)
        "heute", "morgen", "übermorgen", "gestern", "früh", "morgens", "vormittag", "vormittags", "mittag", "mittags",
        "nachmittag", "nachmittags", "abend", "abends", "nacht", "nachts", "uhr", "um", "halb", "viertel", "woche",
        "wochenende", "monat", "jahr", "today", "tomorrow", "tonight", "morning", "afternoon", "evening", "night",
        "noon", "midnight", "week", "weekend", "month", "year", "pm",
        "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonnabend", "sonntag",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ])

    /// Präpositionen (für Regel e und als Wort vor dem Ausdruck am Ende)
    static let prepositions: Set<String> = folded([
        "wegen", "für", "über", "von", "vom", "vor", "nach", "bis", "ab", "an", "am", "ans", "auf", "zu", "zum", "zur",
        "seit", "ohne", "mit", "um", "in", "im", "ins", "bei", "beim", "gegen", "aus", "unter", "zwischen", "während",
        "innerhalb", "binnen", "bezüglich", "for", "about", "of", "to", "at", "on", "by", "until", "before", "after",
        "from", "since", "with", "into", "regarding", "during", "within", "between",
    ])

    /// Artikel und Begleiter, die einen folgenden Zeitausdruck regieren („den Freitag“, „nächsten Freitag“)
    static let governingDeterminers: Set<String> = folded([
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines", "nächste",
        "nächsten", "nächster", "nächstes", "übernächste", "übernächsten", "kommende", "kommenden", "kommender",
        "kommendes", "diese", "diesen", "dieser", "dieses", "diesem", "jede", "jeden", "jeder", "jedes", "jedem",
        "letzte", "letzten", "letzter", "letztes", "vorige", "vorigen", "the", "a", "an", "next", "this", "every",
        "each", "last", "coming", "following",
    ])

    /// Anfang eines Zeitraums: „bis Freitag“, „ab Montag“, „von … bis …“ – der Endtermin kann zum Objekt gehören.
    static let spanWords: Set<String> = folded([
        "bis", "ab", "seit", "von", "vom", "während", "über", "until", "till", "til", "from", "since", "through", "thru",
        "during", "throughout",
    ])

    /// Der Ausdruck ist eine Frist trotz Zeitraum-Wort („bis spätestens Freitag“)
    static let deadlineWords: Set<String> = folded(["spätestens"])

    /// `due_hint` nennt einen Zeitpunkt oder eine Frist (Regel d)
    static func isPointInTime(_ hint: String) -> Bool {
        let words = words(hint)
        guard !words.contains(where: deadlineWords.contains) else { return true }
        return !words.contains(where: spanWords.contains)
    }

    /// Entfernt den Zeitausdruck am Anfang oder am Ende, wenn die Regeln a–e es sicher erlauben; sonst bleibt alles.
    static func removingTimeExpression(_ hint: String, from words: [String]) -> [String] {
        let target = ThoughtValidator.normalizedForMatch(hint)
        let text = words.joined(separator: " ")
        guard !target.isEmpty, words.count > 1, !isNegated(text), !isNegated(hint), isPointInTime(hint) else { return words }
        func matches(_ range: Range<Int>) -> Bool {
            ThoughtValidator.normalizedForMatch(words[range].joined(separator: " ")) == target
        }
        let count = words.count
        // Anfang: „morgen | Anna anrufen“
        for k in 1..<count where matches(0..<k) {
            let rest = Array(words.dropFirst(k))
            let real = rest.filter(isRealWord)
            guard real.count >= 2, let neighbor = real.first, !isBlocked(neighbor) else { return words }
            return rest
        }
        // Ende: „Anna anrufen | morgen“
        for k in 1..<count where matches((count - k)..<count) {
            let rest = Array(words.dropLast(k))
            let real = rest.filter(isRealWord)
            guard real.count >= 2, let neighbor = real.last, !isBlocked(neighbor), !governingDeterminers.contains(key(neighbor)),
                  !real.map(key).contains(where: prepositions.contains) else { return words }
            return rest
        }
        return words
    }

    /// Nachbarwort aus der Sperrliste, eine Zahl („3.“, „zwölf“) oder ein Zahlwort
    private static func isBlocked(_ word: String) -> Bool {
        blockedNeighbors.contains(key(word)) || word.contains(where: \.isNumber) || SpokenNumbers.isNumberWord(bare(word))
    }

    /// Wort mit Buchstabe oder Ziffer (nicht „–“)
    private static func isRealWord(_ word: String) -> Bool {
        word.contains { $0.isLetter || $0.isNumber }
    }

    /// Vergleichsform eines Worts (klein, ohne Akzente und Satzzeichen); „bzw.“ → „bzw“
    private static func key(_ word: String) -> String {
        ThoughtValidator.normalizedForMatch(word).replacingOccurrences(of: " ", with: "")
    }

    private static func words(_ text: String) -> [String] {
        ThoughtValidator.normalizedForMatch(text).split(separator: " ").map(String.init)
    }

    private static func folded(_ list: [String]) -> Set<String> {
        Set(list.map(ThoughtValidator.normalizedForMatch))
    }

    // MARK: Füllwörter

    static func removingEdgeFillers(_ words: [String]) -> [String] {
        var words = words
        if words.count >= 2, edgeFillers.contains(bare(words[0]).lowercased()) {
            let next = bare(words[1])
            if next.first?.isUppercase == true || definiteArticles.contains(next.lowercased()),
               !isNegated(firstClause(words.dropFirst())) {
                words.removeFirst()
            }
        }
        if words.count >= 2, let last = words.last, edgeFillers.contains(bare(last)), isInfinitive(words[words.count - 2]),
           !isNegated(lastClause(words.dropLast())) {
            words.removeLast()
        }
        return words
    }

    /// Teilsatz-Grenze: Wort endet auf „,“ „;“ „:“ oder ist ein Gedankenstrich
    private static func endsClause(_ word: String) -> Bool {
        word.last.map { ",;:".contains($0) } == true || ["–", "—", "-"].contains(word)
    }

    /// Erster Teilsatz („Bescheid sagen:“ in „Bescheid sagen: Vertrag nicht verlängern“)
    private static func firstClause(_ words: ArraySlice<String>) -> String {
        var clause: [String] = []
        for word in words {
            clause.append(word)
            if endsClause(word) { break }
        }
        return clause.joined(separator: " ")
    }

    /// Letzter Teilsatz
    private static func lastClause(_ words: ArraySlice<String>) -> String {
        var clause: [String] = []
        for word in words.reversed() {
            if endsClause(word) { break }
            clause.insert(word, at: 0)
        }
        return clause.joined(separator: " ")
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
