import Foundation

/// Titel und Vorschau aus dem Rohtext, solange ein Gedanke noch nicht geordnet ist (Karten „Noch nicht
/// geordnet“). Aus „Ähm, also am wochenende die tomaten ausgeizen und die beete gießen“ wird
/// Titel „Am wochenende die tomaten ausgeizen und …“ und Vorschau „die beete gießen“.
///
/// - Zögerlaute (Füllwort-Lexikon) fallen überall weg, Gesprächspartikeln wie „also“, „ja“, „okay“ nur am Anfang.
/// - Der Titel endet nach höchstens `maxWords` Wörtern oder früher am Satzende; abgeschnitten → „ …“.
/// - Satzanfang groß; der Rest wird zur Vorschau (nach einem Satzende ebenfalls groß beginnend).
public enum RawTitle {
    public struct Parts: Sendable, Equatable {
        public let title: String
        public let rest: String

        public init(title: String, rest: String) {
            self.title = title
            self.rest = rest
        }
    }

    /// Partikeln, die am Anfang gesprochener Sätze nur Anlauf sind (immer weg)
    private static let leadingParticles: Set<String> = [
        "also", "ja", "naja", "okay", "ok", "okey", "ach", "achso", "genau", "und", "well", "and",
    ]

    /// Nur mit Komma dahinter Anlauf („So, …“, „Gut, …“) – sonst tragen sie Inhalt („So viele …“)
    private static let leadingWithComma: Set<String> = ["so", "gut", "nun", "na", "right", "alright", "jo"]

    private static let sentenceEnd: Set<Character> = [".", "!", "?", "…"]

    public static func split(_ raw: String, maxWords: Int = 6) -> Parts? {
        var words = raw.split(whereSeparator: \.isWhitespace).map(String.init).filter { !isFiller($0) }
        while words.count > 1, isLeadingParticle(words[0]) {
            words.removeFirst()
        }
        // nur Satzzeichen am Anfang (z. B. „–“ nach einem entfernten Füllwort)
        while let first = words.first, !first.contains(where: { $0.isLetter || $0.isNumber }) {
            words.removeFirst()
        }
        guard !words.isEmpty else { return nil }

        var count = 0
        var endedSentence = false
        for word in words {
            count += 1
            if let last = word.last, sentenceEnd.contains(last) {
                endedSentence = true
                break
            }
            if count == max(1, maxWords) { break }
        }
        let restWords = words.dropFirst(count)
        var title = words.prefix(count).joined(separator: " ")
        while let last = title.last, ".,;:–-…".contains(last) { title.removeLast() }
        title = capitalizedFirst(title)
        guard !title.isEmpty else { return nil }
        if !restWords.isEmpty, !endedSentence { title += " …" }
        var rest = restWords.joined(separator: " ")
        if endedSentence { rest = capitalizedFirst(rest) }
        return Parts(title: title, rest: rest)
    }

    // MARK: Hilfen

    private static func bare(_ word: String) -> String {
        TextAnalysis.normalizedLower(word.trimmingCharacters(in: .punctuationCharacters))
    }

    private static func isFiller(_ word: String) -> Bool {
        let core = bare(word)
        return !core.isEmpty && Lexicon.fillers.contains(core)
    }

    private static func isLeadingParticle(_ word: String) -> Bool {
        let core = bare(word)
        if leadingParticles.contains(core) { return true }
        return leadingWithComma.contains(core) && word.hasSuffix(",")
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let index = text.firstIndex(where: { $0.isLetter || $0.isNumber }), text[index].isLowercase else { return text }
        return text.replacingCharacters(in: index...index, with: text[index].uppercased())
    }
}
