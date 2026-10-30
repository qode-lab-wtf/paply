import Foundation
import NaturalLanguage

/// Lange Gedanken in Teile schneiden (KONZEPT §6.2): ab 1 800 Transkript-Tokens Teile ≤ 1 400 Tokens.
/// Teil 1 bekommt den vollen Aufruf, Teile 2…n den Kurzaufruf (Titel und Thema stehen fest).
///
/// Geschnitten wird an der besten Grenze nahe der Wunschlänge (Teile möglichst gleich groß):
/// 1. Satzende, 2. vor Zögerlauten („ähm“, „uh“, „euh“) und Gliederungswörtern („und dann“, „zweitens“),
/// 3. vor Gesprächsmarkern („also“, „so“, „okay“, „anyway“, „alors“ …), 4. nach Komma, und erst zuletzt nach Länge.
/// Whisper-Rohtext hat oft gar keine Satzzeichen; dann tragen die Zögerlaute (e35: 24× „ähm“).
/// Pausen aus Whisper-Segmenten stehen nicht zur Verfügung (`source.json` speichert keine Segmente).
public enum PartSplitter {
    public static let threshold = 1_800
    public static let maxPartTokens = 1_400

    public struct Part: Sendable, Equatable {
        public var sentences: [ThoughtSource.Sentence]
        public var text: String
        public var tokens: Int
    }

    /// Grobe Schätzung wie beim Ledger (Mac `groq.js`): UTF-8-Bytes / 3.
    public static func estimateTokens(_ text: String) -> Int {
        (text.utf8.count + 2) / 3
    }

    public static func needsParts(_ transcript: String) -> Bool {
        estimateTokens(transcript) > threshold
    }

    /// Ein Teil, wenn kurz genug; sonst möglichst gleich große Teile ≤ `maxPartTokens`.
    public static func split(_ source: ThoughtSource, force: Bool = false) -> [Part] {
        let sentences = source.sentences.isEmpty ? [ThoughtSource.Sentence(id: "s0", text: source.text)] : source.sentences
        let total = estimateTokens(source.text)
        guard force || total > threshold else {
            return [Part(sentences: sentences, text: source.text, tokens: total)]
        }
        let words = Self.words(sentences, languages: source.languages)
        guard words.count > 1 else { return [Part(sentences: sentences, text: source.text, tokens: total)] }
        // Präfix-Bytes: Länge von words[a..<b] = prefix[b] - prefix[a] - 1 (Leerzeichen dazwischen)
        var prefix = [0]
        for word in words { prefix.append(prefix.last! + word.text.utf8.count + 1) }
        func tokens(_ a: Int, _ b: Int) -> Int { (max(0, prefix[b] - prefix[a] - 1) + 2) / 3 }

        let count = max(force ? 2 : 1, Int((Double(tokens(0, words.count)) / Double(maxPartTokens)).rounded(.up)))
        var cuts: [Int] = []
        var start = 0
        // `force` (Aufruf war trotz kurzem Transkript zu groß): mindestens zwei Teile
        while start < words.count - 1, tokens(start, words.count) > maxPartTokens || cuts.count + 1 < count {
            let remainingParts = max(1, count - cuts.count)
            let target = Double(tokens(start, words.count)) / Double(remainingParts)
            var best: (index: Int, score: Double)?
            var end = start + 1
            while end < words.count, tokens(start, end) <= maxPartTokens {
                let size = Double(tokens(start, end))
                if size >= target * 0.6 {
                    // Grenzgüte zählt vor der Nähe zur Wunschlänge; Länge allein nur als letzte Möglichkeit
                    let closeness = 1 - min(1, abs(size - target) / target)
                    let score = words[end].boundary * 10 + closeness
                    if best == nil || score > best!.score { best = (end, score) }
                }
                end += 1
            }
            let cut = best?.index ?? max(start + 1, end - 1)
            cuts.append(cut)
            start = cut
        }
        var parts: [Part] = []
        var from = 0
        for to in cuts + [words.count] where to > from {
            parts.append(part(words[from..<to]))
            from = to
        }
        return parts
    }

    // MARK: Wörter und Grenzen

    struct Word {
        var text: String
        var sentence: String
        /// Güte einer Grenze direkt vor diesem Wort (0 = nur nach Länge)
        var boundary: Double
    }

    /// Zögerlaute: hier beginnt fast immer ein neuer Gedankengang.
    static let hesitations: Set<String> = ["ähm", "äh", "öhm", "ähem", "ehm", "hm", "hmm", "mhm", "uh", "uhm", "umm", "erm",
                                           "euh", "euhm", "eeh", "ehh"]
    /// Englische Zögerlaute, die im Deutschen echte Wörter sind („um zu“, „er“).
    static let hesitationsNotGerman: Set<String> = ["um", "er", "eh"]
    /// Gliederung über zwei Wörter bzw. Aufzählung
    static let strongMarkers: [[String]] = [
        ["und", "dann"], ["und", "noch"], ["na", "ja"], ["and", "then"], ["and", "also"], ["so", "yeah"], ["et", "puis"],
        ["y", "luego"], ["e", "poi"],
    ]
    static let enumerations: Set<String> = ["erstens", "zweitens", "drittens", "viertens", "letztens", "first", "firstly",
                                            "second", "secondly", "third", "thirdly", "finally", "naja", "jedenfalls",
                                            "außerdem", "übrigens", "anyway", "anyways"]
    /// Gesprächsmarker: oft, aber nicht immer ein Neuanfang („also“ heißt auch „folglich“)
    static let markers: Set<String> = ["also", "so", "okay", "ok", "dann", "gut", "genau", "well", "alright", "right", "now",
                                       "alors", "donc", "bon", "enfin", "pues", "bueno", "entonces", "allora", "quindi",
                                       "comunque", "então", "bom", "dus", "nou"]

    static func words(_ sentences: [ThoughtSource.Sentence], languages: [String]) -> [Word] {
        let german = languages.contains { $0.hasPrefix("de") }
        var result: [Word] = []
        for sentence in sentences {
            let tokens = sentence.text.split(whereSeparator: \.isWhitespace).map(String.init)
            for (index, token) in tokens.enumerated() {
                let bare = TextAnalysis.normalizedLower(token).trimmingCharacters(in: .punctuationCharacters)
                let next = index + 1 < tokens.count
                    ? TextAnalysis.normalizedLower(tokens[index + 1]).trimmingCharacters(in: .punctuationCharacters) : ""
                var boundary = 0.0
                if index == 0 {
                    boundary = 4 // Satzanfang
                } else if let previous = tokens[index - 1].last, ".!?…".contains(previous) {
                    boundary = 4
                } else if hesitations.contains(bare) || (!german && hesitationsNotGerman.contains(bare)) {
                    boundary = 3
                } else if strongMarkers.contains([bare, next]) || enumerations.contains(bare) {
                    boundary = 3
                } else if markers.contains(bare) {
                    boundary = 2
                } else if let previous = tokens[index - 1].last, ",;:–".contains(previous) {
                    boundary = 1
                }
                result.append(Word(text: token, sentence: sentence.id, boundary: boundary))
            }
        }
        return result
    }

    private static func part(_ words: ArraySlice<Word>) -> Part {
        var sentences: [ThoughtSource.Sentence] = []
        for word in words {
            if let last = sentences.last, last.id == word.sentence {
                sentences[sentences.count - 1].text += " " + word.text
            } else {
                sentences.append(ThoughtSource.Sentence(id: word.sentence, text: word.text))
            }
        }
        let text = words.map(\.text).joined(separator: " ")
        return Part(sentences: sentences, text: text, tokens: estimateTokens(text))
    }

    /// Sätze mit IDs wie Mac `splitSentences`: „<Gedanken-ID>_s<i>“.
    public static func sentences(_ text: String, thoughtID: String) -> [ThoughtSource.Sentence] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [ThoughtSource.Sentence] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmed
            if !sentence.isEmpty { result.append(ThoughtSource.Sentence(id: "\(thoughtID)_s\(result.count)", text: sentence)) }
            return true
        }
        if result.isEmpty, !text.trimmed.isEmpty { result = [ThoughtSource.Sentence(id: "\(thoughtID)_s0", text: text.trimmed)] }
        return result
    }
}
