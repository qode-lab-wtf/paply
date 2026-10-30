import Foundation
import NaturalLanguage

/// Schlagwörter (KONZEPT §6.3): Lemmata (NLTagger) von Substantiven, Eigennamen und Verben, ohne
/// Stoppwörter, gefaltet (klein, Umlaute als ae/oe/ue wie der deutsche Lemmatisierer, ohne Akzente).
/// Gewichtung mit TF-IDF bzw. BM25 übernimmt der Index (`LocalIndex`).
public enum Keywords {
    /// Lemmata in Textreihenfolge (mit Wiederholungen, für Termhäufigkeiten).
    public static func terms(_ text: String, language: String?) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass, .lemma])
        tagger.string = text
        let whole = text.startIndex..<text.endIndex
        if let language, !language.isEmpty { tagger.setLanguage(NLLanguage(rawValue: language), range: whole) }
        var result: [String] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther, .joinNames]
        tagger.enumerateTags(in: whole, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { tag, range in
            guard let tag, keptClasses.contains(tag) else { return true }
            let word = String(text[range])
            let isName = nameClasses.contains(tag)
            let lemma = isName ? nil : tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            for part in split(lemma ?? word) {
                let folded = fold(part)
                guard isUseful(folded, original: part, isName: isName) else { continue }
                result.append(folded)
            }
            return true
        }
        return result
    }

    /// Häufigkeiten je Term.
    public static func counts(_ terms: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for term in terms { counts[term, default: 0] += 1 }
        return counts
    }

    /// Die wichtigsten Terme nach TF-IDF (`idf` liefert das Gewicht eines Terms in der Ablage).
    public static func top(_ counts: [String: Int], limit: Int, idf: (String) -> Double = { _ in 1 }) -> [String] {
        counts.map { (term: $0.key, weight: (1 + log(Double($0.value))) * idf($0.key)) }
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.term < $1.term }
            .prefix(limit)
            .map(\.term)
    }

    /// Vergleichsform: klein, ä/ö/ü → ae/oe/ue, ß → ss, übrige Akzente weg.
    public static func fold(_ word: String) -> String {
        var lower = TextAnalysis.normalizedLower(word)
        if lower.contains(where: { "äöüß".contains($0) }) {
            lower = lower.replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
                .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
        }
        return lower.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: Intern

    private static let keptClasses: Set<NLTag> = [.noun, .verb, .personalName, .placeName, .organizationName, .otherWord]
    private static let nameClasses: Set<NLTag> = [.personalName, .placeName, .organizationName]

    /// Bindestrich-Wörter und Mehrwortnamen in Teile zerlegen.
    private static func split(_ word: String) -> [String] {
        TextAnalysis.alphanumericRuns(word)
    }

    private static func isUseful(_ folded: String, original: String, isName: Bool) -> Bool {
        guard folded.unicodeScalars.contains(where: TextAnalysis.isLetter) else { return false }
        if folded.unicodeScalars.allSatisfy(TextAnalysis.isNumber) { return false }
        let acronym = original.count >= 2 && original == original.uppercased() && original != original.lowercased()
        guard folded.count >= 3 || (acronym && folded.count >= 2) || TextAnalysis.containsScriptioContinua(folded) else { return false }
        if !isName, stopwords.contains(folded) { return false }
        return !Lexicon.fillers.contains(folded)
    }

    /// Hilfs- und Modalverben, sehr allgemeine Verben/Substantive (de, en, fr, es, it), gefaltet.
    static let stopwords: Set<String> = Set([
        // Deutsch
        "sein", "haben", "werden", "können", "müssen", "sollen", "wollen", "dürfen", "mögen", "möchten",
        "machen", "tun", "geben", "gehen", "kommen", "sagen", "lassen", "meinen", "glauben", "denken", "finden",
        "wissen", "heißen", "bleiben", "stehen", "liegen", "brauchen", "sehen", "nehmen", "halten", "bringen",
        "ding", "dinge", "sache", "sachen", "mal", "art", "weise", "bisschen", "teil", "zeit", "jahr", "tag",
        "also", "halt", "eben", "quasi", "irgendwie", "okay", "gut", "ja", "nein", "doch", "noch", "schon",
        // Englisch
        "be", "have", "do", "will", "would", "can", "could", "shall", "should", "may", "might", "must",
        "get", "go", "make", "say", "want", "need", "think", "know", "let", "take", "see", "come", "give",
        "thing", "things", "stuff", "way", "lot", "kind", "sort", "time", "yeah", "okay", "like", "just",
        // Französisch, Spanisch, Italienisch (Hilfsverben)
        "être", "avoir", "faire", "aller", "pouvoir", "vouloir", "devoir", "chose",
        "ser", "estar", "haber", "tener", "hacer", "poder", "querer", "cosa",
        "essere", "avere", "fare", "andare", "potere", "volere", "dovere",
    ].map(fold))
}
