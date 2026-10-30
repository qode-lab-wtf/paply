import Foundation

/// Prüft die Antwort des Polier-Modells (Port von electron-menubar/dictation/polish.js,
/// mehrsprachig erweitert). Bei Ablehnung behält der Aufrufer den Rohtext.
package enum PolishSafetyNet {
    private static let closedThinking = Pattern("<(think|analysis)\\b[^>]*>[\\s\\S]*?</\\1\\s*>", caseInsensitive: true)
    private static let leadingThinking = Pattern("^[\\s\\S]*?</(?:think|analysis)\\s*>", caseInsensitive: true)
    private static let openThinking = Pattern("<(?:think|analysis)\\b[\\s\\S]*$", caseInsensitive: true)
    private static let finalChannel = Pattern("(?:<\\|channel\\|>final(?:<\\|message\\|>|\\|>)|<\\|final\\|>)([\\s\\S]*)")
    private static let controlToken = Pattern("<\\|[^>]+\\|>")
    private static let analysisLeftover = Pattern("<\\|(?:channel\\|>analysis|start\\|>)", caseInsensitive: true)

    /// Entfernt Denk-/Analyse-Reste und Kanal-Marker; "" wenn nur Überlegung übrig bleibt.
    package static func finalPolishText(_ content: String?) -> String {
        guard let content else { return "" }
        var text = closedThinking.replacing(in: content)
        text = leadingThinking.replacingFirst(in: text)
        text = openThinking.replacing(in: text).trimmed
        if let final = finalChannel.firstGroup(in: text) {
            text = controlToken.replacing(in: final).trimmed
        }
        return analysisLeftover.matches(text) ? "" : text
    }

    static func contentWords(_ text: String) -> [String] {
        TextAnalysis.contentUnits(text)
    }

    static func negationCount(_ text: String) -> Int {
        TextAnalysis.negationCount(text)
    }

    /// Grund der Ablehnung (`PolishRejectionCode.rawValue`) oder nil.
    /// `strictEdits`: wortgenaue Prüfung von Ersetzungen/Einfügungen (W7).
    ///
    /// Enthält der Rohtext eine gesprochene Selbstkorrektur („um 15 Uhr, ich meine um 16 Uhr“),
    /// genügt es, wenn das Ergebnis gegen die aufgelöste Lesart („um 16 Uhr“) besteht – sonst
    /// fielen kurze, korrekt aufgelöste Korrekturen an Länge, Inhalt oder Zahlen durch.
    package static func rejection(raw: String, result: String, vocabulary: String = "", strictEdits: Bool = true) -> String? {
        rejection(raw: raw, result: result, vocabulary: vocabulary, strictEdits: strictEdits, limits: .dictation)
    }

    /// Prüfprofil. `.dictation` ist der Standard (unverändert); `.thought` gilt für das
    /// Aufräumen eines Gedankens (KONZEPT §6.7): Absätze und „• “-Aufzählungen sind erlaubt,
    /// Fehlstarts werden legitim umformuliert (keine Wortprüfung), dafür strengere Grenzen.
    package enum Profile: Sendable {
        case dictation, thought
    }

    package static func rejection(raw: String, result: String, vocabulary: String = "", profile: Profile) -> String? {
        switch profile {
        case .dictation:
            return rejection(raw: raw, result: result, vocabulary: vocabulary, strictEdits: true, limits: .dictation)
        case .thought:
            return rejection(raw: raw, result: result, vocabulary: vocabulary, strictEdits: false, limits: .thought)
        }
    }

    struct Limits {
        var lengthLow: Double
        var lengthHigh: Double
        var missingContent: Double
        var addedShare: Double
        /// „• “ und Zeilenumbrüche zählen nicht zur Länge.
        var ignoresLayout: Bool
        /// Gesprochene Rohform (Gedanken, Whisper ohne Satzzeichen): Zahlen als Werte inkl. zusammengesetzter
        /// Zahlwörter und Selbstkorrektur ohne Komma (`SpokenNumbers`); „nee“/„nein“ sind Einwürfe, keine
        /// Verneinung des Inhalts. Zahlwörter zählen nicht als Inhaltswörter.
        var spoken: Bool

        static let dictation = Limits(lengthLow: 0.7, lengthHigh: 1.3, missingContent: 0.3, addedShare: 0.15,
                                      ignoresLayout: false, spoken: false)
        static let thought = Limits(lengthLow: 0.55, lengthHigh: 1.15, missingContent: 0.25, addedShare: 0.10,
                                    ignoresLayout: true, spoken: true)
    }

    /// Verneinungen ohne die Einwürfe „nee“, „nein“, „nö“ (Gedanken-Profil).
    static func spokenNegationCount(_ text: String) -> Int {
        var stripped = text
        for (word, range) in TextAnalysis.runs(text, where: { TextAnalysis.isLetter($0) || TextAnalysis.isMark($0) }).reversed()
            where ["nee", "nein", "nö"].contains(TextAnalysis.normalizedLower(word)) {
            stripped.replaceSubrange(range, with: "")
        }
        return negationCount(stripped)
    }

    private static func rejection(raw: String, result: String, vocabulary: String, strictEdits: Bool, limits: Limits) -> String? {
        if result.isEmpty { return "empty" }
        if isMetaAnswer(result, raw: raw) { return "meta" }
        guard let reason = check(raw: raw, result: result, vocabulary: vocabulary, strictEdits: strictEdits,
                                 lengthReference: raw, limits: limits) else { return nil }
        if let resolved = EditCheck.resolvedSelfCorrection(raw),
           check(raw: resolved, result: result, vocabulary: vocabulary, strictEdits: strictEdits,
                 lengthReference: raw, limits: limits) == nil {
            return nil
        }
        return reason
    }

    /// Länge, Inhalt, Verneinung, Zahlen, Ersetzungen und Zusätze gegen einen Rohtext.
    /// Die Obergrenze der Länge gilt immer gegen den gesprochenen Rohtext.
    private static func check(raw: String, result: String, vocabulary: String, strictEdits: Bool,
                              lengthReference: String, limits: Limits) -> String? {
        let measured = limits.ignoresLayout
            ? result.replacingOccurrences(of: "• ", with: "").replacingOccurrences(of: "\n", with: "")
            : result
        let resultLength = Double(measured.unicodeScalars.count)
        let low = resultLength / Double(max(1, raw.trimmed.unicodeScalars.count))
        let high = resultLength / Double(max(1, lengthReference.trimmed.unicodeScalars.count))
        if low < limits.lengthLow || high > limits.lengthHigh { return "length" }

        // Zusammen-/Getrenntschreibung zählt nicht als fehlender Inhalt (K2).
        let (rawWords, resultWords) = EditCheck.compoundAligned(
            TextAnalysis.letterRuns(TextAnalysis.normalizedLower(raw)),
            TextAnalysis.letterRuns(TextAnalysis.normalizedLower(result)))
        var before = contentWords(rawWords.joined(separator: " "))
        var after = contentWords(resultWords.joined(separator: " "))
        if limits.spoken {
            before.removeAll(where: SpokenNumbers.isNumberWord)
            after.removeAll(where: SpokenNumbers.isNumberWord)
        }
        var remaining: [String: Int] = [:]
        for word in after { remaining[word, default: 0] += 1 }
        var missing = 0
        for word in before {
            if let count = remaining[word], count > 0 {
                remaining[word] = count - 1
            } else {
                missing += 1
            }
        }
        if !before.isEmpty && Double(missing) / Double(before.count) > limits.missingContent { return "content" }

        // Verneinung verschwunden oder hinzugekommen → Sinn gekippt.
        if limits.spoken {
            if spokenNegationCount(raw) != spokenNegationCount(result) { return "negation" }
        } else if negationCount(raw) != negationCount(result) {
            return "negation"
        }

        // Zahlen müssen erhalten bleiben („15 Uhr“ ≠ „16 Uhr“), neue Zahlen sind verboten.
        if limits.spoken {
            if !SpokenNumbers.preserved(raw: raw, result: result) { return "digits" }
        } else if !EditCheck.digitsPreserved(raw: raw, result: result) {
            return "digits"
        }

        if strictEdits, let reason = EditCheck.substitutionRejection(raw: raw, result: result, vocabulary: vocabulary) {
            return reason
        }

        // Neue Inhaltswörter begrenzen; Wörter der eigenen Begriffsliste dürfen als
        // Hörfehler-Korrektur auftauchen. Netto-Zuwachs zählt (Ersetzungen deckt „missing“).
        let allowed = Set(before).union(contentWords(vocabulary))
        let added = after.filter { !allowed.contains($0) }.count
        let limit = max(2, Int((Double(before.count) * limits.addedShare).rounded(.up)))
        return added - missing > limit ? "added" : nil
    }

    /// Meta-Antwort („Hier ist der korrigierte Text: …“) oder komplett in Anführungszeichen.
    /// Abweichung vom Desktop: Beginnt/umschließt schon der Rohtext so, ist es Inhalt –
    /// „Hier ist der Plan für morgen.“ bleibt dann polierbar.
    static func isMetaAnswer(_ result: String, raw: String) -> Bool {
        let rawTrimmed = raw.trimmed
        if Lexicon.metaAnswer.matches(result) && !Lexicon.metaAnswer.matches(rawTrimmed) { return true }
        if Lexicon.wrappedInQuotes.matches(result) && !Lexicon.wrappedInQuotes.matches(rawTrimmed) { return true }
        return false
    }
}
