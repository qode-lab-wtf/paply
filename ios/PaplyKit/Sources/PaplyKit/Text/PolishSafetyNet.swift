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
        if result.isEmpty { return "empty" }
        if isMetaAnswer(result, raw: raw) { return "meta" }
        guard let reason = check(raw: raw, result: result, vocabulary: vocabulary, strictEdits: strictEdits,
                                 lengthReference: raw) else { return nil }
        if let resolved = EditCheck.resolvedSelfCorrection(raw),
           check(raw: resolved, result: result, vocabulary: vocabulary, strictEdits: strictEdits,
                 lengthReference: raw) == nil {
            return nil
        }
        return reason
    }

    /// Länge, Inhalt, Verneinung, Zahlen, Ersetzungen und Zusätze gegen einen Rohtext.
    /// Die Obergrenze der Länge gilt immer gegen den gesprochenen Rohtext.
    private static func check(raw: String, result: String, vocabulary: String, strictEdits: Bool,
                              lengthReference: String) -> String? {
        let resultLength = Double(result.unicodeScalars.count)
        let low = resultLength / Double(max(1, raw.trimmed.unicodeScalars.count))
        let high = resultLength / Double(max(1, lengthReference.trimmed.unicodeScalars.count))
        if low < 0.7 || high > 1.3 { return "length" }

        // Zusammen-/Getrenntschreibung zählt nicht als fehlender Inhalt (K2).
        let (rawWords, resultWords) = EditCheck.compoundAligned(
            TextAnalysis.letterRuns(TextAnalysis.normalizedLower(raw)),
            TextAnalysis.letterRuns(TextAnalysis.normalizedLower(result)))
        let before = contentWords(rawWords.joined(separator: " "))
        let after = contentWords(resultWords.joined(separator: " "))
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
        if !before.isEmpty && Double(missing) / Double(before.count) > 0.3 { return "content" }

        // Verneinung verschwunden oder hinzugekommen → Sinn gekippt.
        if negationCount(raw) != negationCount(result) { return "negation" }

        // Zahlen müssen erhalten bleiben („15 Uhr“ ≠ „16 Uhr“), neue Zahlen sind verboten.
        if !EditCheck.digitsPreserved(raw: raw, result: result) { return "digits" }

        if strictEdits, let reason = EditCheck.substitutionRejection(raw: raw, result: result, vocabulary: vocabulary) {
            return reason
        }

        // Neue Inhaltswörter begrenzen; Wörter der eigenen Begriffsliste dürfen als
        // Hörfehler-Korrektur auftauchen. Netto-Zuwachs zählt (Ersetzungen deckt „missing“).
        let allowed = Set(before).union(contentWords(vocabulary))
        let added = after.filter { !allowed.contains($0) }.count
        let limit = max(2, Int((Double(before.count) * 0.15).rounded(.up)))
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
