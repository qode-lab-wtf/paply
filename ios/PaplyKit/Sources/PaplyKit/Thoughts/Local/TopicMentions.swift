import Foundation
import NaturalLanguage
import Synchronization

/// Deterministische Hilfe vor der KI (KONZEPT §6.3): Kommt ein Name oder Stichwort eines **beschriebenen**
/// Themas im Transkript vor, ist das Thema ein starker Kandidat (`TopicIndexEntry.mentioned`).
///
/// - Begriffe: aussagekräftige Wörter aus Name und Beschreibung (`Topic.note`). Stoppwörter, Rechtsformen,
///   Anreden, allgemeine Rollenwörter („Firma“, „Kunden“), reine Zahlen und Wörter unter 3 Zeichen zählen nicht.
///   Stichwörter werden nicht gespeichert, sondern bei jedem Aufruf aus der Beschreibung abgeleitet – so bleibt
///   es bei einem Feld „Worum geht's?“.
/// - Vergleich an Wortgrenzen, ohne Groß/Klein und Akzente; Umlaute gelten als ä = ae = a, ß = ss.
/// - Nur echte Beugungsendungen, in beide Richtungen, nie ein bloßer Wortanfang („Reis“ ≠ „Reisen“,
///   „Fisch“ ≠ „Fischer“): -s ab 3 Zeichen Stamm („Kowalskis“, „Omas“), -es ab 4, -e und -en ab 5
///   („Rudervereine“), -n nach -e/-el/-er ab 4 („Reisen“ ← „Reise“), -er nur bei Eigennamen ab 4
///   (großgeschrieben, kein gewöhnliches Wort: „Beueler“ ← „Beuel“).
/// - Themen ohne Beschreibung bekommen keine Treffer (ihr Name zählt schon in der lokalen Passung).
///
/// Treffer sind nur Hinweise für die KI. Ein neues Thema leitet der Code nur bei eindeutiger Gleichheit um
/// (`describedMatch`).
public enum TopicMentions {
    /// Ein Begriff: Vergleichsformen und die Schreibweise aus Name/Beschreibung.
    public struct Term: Sendable, Equatable {
        public var original: String
        /// gefaltete Formen (ae- und a-Faltung)
        var forms: Set<String>
        /// gefaltete Grundformen (der Begriff ist selbst gebeugt, z. B. „Müllers“)
        var stems: Set<String>
    }

    /// Wörter eines Texts in Vergleichsform – für viele Themen nur einmal berechnen.
    public struct Haystack: Sendable {
        /// gefaltete Wörter
        var forms: Set<String> = []
        /// gefaltete Wörter und ihre Grundformen
        var keys: Set<String> = []

        public init(_ text: String) {
            for word in TextAnalysis.alphanumericRuns(text) {
                let wordForms = TopicMentions.forms(word)
                forms.formUnion(wordForms)
                keys.formUnion(wordForms)
                for base in TopicMentions.bases(word) { keys.formUnion(TopicMentions.forms(base)) }
            }
        }

        func contains(_ term: Term) -> Bool {
            !term.forms.isDisjoint(with: keys) || !term.stems.isDisjoint(with: forms)
        }
    }

    // MARK: Begriffe

    /// Begriffe eines beschriebenen Themas (Name + Beschreibung), in Reihenfolge, ohne Doppel.
    /// Ohne Beschreibung: leer.
    public static func terms(title: String, note: String?) -> [Term] {
        guard let note = Topic.normalizedNote(note) else { return [] }
        return words(title + " " + note)
    }

    public static func terms(_ topic: Topic) -> [Term] { terms(title: topic.title, note: topic.note) }

    /// Aussagekräftige Wörter eines beliebigen Texts (auch für Namen neuer Themen).
    static func words(_ text: String) -> [Term] {
        var result: [Term] = []
        var seen: Set<String> = []
        for word in TextAnalysis.alphanumericRuns(text) {
            guard let term = term(word), seen.insert(term.forms.sorted().joined(separator: "|")).inserted else { continue }
            result.append(term)
        }
        return result
    }

    static func term(_ word: String) -> Term? {
        let folded = Keywords.fold(word)
        guard folded.count >= minimumLength,
              folded.unicodeScalars.contains(where: TextAnalysis.isLetter),
              !folded.unicodeScalars.allSatisfy(TextAnalysis.isNumber) else { return nil }
        let forms = forms(word)
        guard forms.isDisjoint(with: stopwords), !Lexicon.fillers.contains(folded) else { return nil }
        return Term(original: word, forms: forms, stems: Set(bases(word).flatMap(Self.forms)))
    }

    // MARK: Treffer

    /// Begriffe des Themas, die im Text vorkommen (Schreibweise aus Name/Beschreibung).
    public static func matches(_ terms: [Term], in haystack: Haystack) -> [String] {
        terms.filter(haystack.contains).map(\.original)
    }

    public static func matches(_ topic: Topic, in text: String) -> [String] {
        matches(terms(topic), in: Haystack(text))
    }

    // MARK: Umleitung (Validator und Prozessor)

    /// Meint `name` – ein von der KI vorgeschlagenes **neues** Thema – eindeutig ein beschriebenes Thema? Nur dann
    /// leitet der Code um; eine falsche Umleitung wiegt schwerer als keine.
    /// 1. Der Name ist der Titel des Themas oder eine klare Variante davon (Groß/Klein, Umlaut, Plural/Genitiv).
    /// 2. Oder er besteht nur aus Eigennamen aus Titel oder Beschreibung – Wörter, die dort großgeschrieben stehen
    ///    und keine gewöhnlichen Wörter sind („Kowalski“, „Brandts“ ← „Brandt“), oder ein dort zusammenhängend
    ///    geschriebener Name aus mehreren Wörtern („Müller Bau“) – **und** das Transkript nennt mindestens einen
    ///    weiteren Begriff desselben Themas.
    ///
    /// Gewöhnliche Wörter („Köln“, „Pflege“, „Training“, „Garten“) leiten so nie um, Stammvergleiche ebenso wenig
    /// („Reisen“ ↛ „Reis“, „Fisch“ ↛ „Fischer“). Bei mehreren: Titel vor Eigennamen, dann das mit den meisten Gedanken.
    public static func describedMatch(_ name: String, transcript: String, among topics: [TopicIndexEntry]) -> TopicIndexEntry? {
        let nameTerms = words(name)
        guard !nameTerms.isEmpty else { return nil }
        let heard = Haystack(transcript)
        let spokenName = Haystack(name)
        var best: (entry: TopicIndexEntry, rank: Int)?
        for entry in topics {
            guard let note = Topic.normalizedNote(entry.about) else { continue }
            let rank: Int
            if isTitleVariant(name, of: entry.name) {
                rank = 0
            } else if consistsOfProperNames(nameTerms, title: entry.name, note: note),
                      words(entry.name + " " + note).contains(where: { !spokenName.contains($0) && heard.contains($0) }) {
                rank = 1
            } else {
                continue
            }
            if best == nil || rank < best!.rank || (rank == best!.rank && entry.count > best!.entry.count) {
                best = (entry, rank)
            }
        }
        return best?.entry
    }

    /// Gleich bis auf Groß/Klein, Umlaute, Akzente und Plural/Genitiv je Wort („brandt logistik“, „Gärten“ ↔ „Garten“).
    static func isTitleVariant(_ name: String, of title: String) -> Bool {
        let a = TextAnalysis.alphanumericRuns(name), b = TextAnalysis.alphanumericRuns(title)
        guard !a.isEmpty, a.count == b.count else { return false }
        return zip(a, b).allSatisfy { sameWord($0, $1, plural: true) }
    }

    /// Jedes Wort des Namens ist ein Eigenname des Themas, oder der Name steht dort zusammenhängend
    /// aus mehreren großgeschriebenen Wörtern. Verglichen wird genau (bis auf Groß/Klein, Umlaut) oder mit -s.
    static func consistsOfProperNames(_ nameTerms: [Term], title: String, note: String) -> Bool {
        let terms = words(title + " " + note)
        let properNames = terms.filter { isProperName($0.original) }
        if nameTerms.allSatisfy({ word in properNames.contains { sameWord(word.original, $0.original, plural: false) } }) {
            return true
        }
        guard nameTerms.count >= 2 else { return false }
        for phrase in namePhrases(title) + namePhrases(note) where phrase.count >= nameTerms.count {
            for start in 0...(phrase.count - nameTerms.count) {
                let window = phrase[start..<(start + nameTerms.count)]
                if zip(nameTerms, window).allSatisfy({ sameWord($0.original, $1.original, plural: false) }) { return true }
            }
        }
        return false
    }

    /// Eigenname: im Original großgeschrieben und kein gewöhnliches Wort (`CommonWords`).
    static func isProperName(_ word: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        return !CommonWords.contains(word)
    }

    /// Zusammenhängend geschriebene Namen: Folgen großgeschriebener Wörter ohne Satzzeichen dazwischen, als Begriffe
    /// („Kunden Müller Bau und Kowalski“ → [Müller, Bau], [Kowalski]). Stoppwörter fallen heraus, trennen aber nicht.
    static func namePhrases(_ text: String) -> [[Term]] {
        var phrases: [[Term]] = []
        for segment in text.split(whereSeparator: { phraseBreakers.contains($0) || $0.isNewline }) {
            var run: [Term] = []
            for word in TextAnalysis.alphanumericRuns(String(segment)) {
                guard word.first?.isUppercase == true else {
                    if !run.isEmpty { phrases.append(run) }
                    run = []
                    continue
                }
                if let term = term(word) { run.append(term) }
            }
            if !run.isEmpty { phrases.append(run) }
        }
        return phrases
    }

    private static let phraseBreakers: Set<Character> = [",", ".", ";", ":", "!", "?", "(", ")", "[", "]", "{", "}", "/",
                                                         "\\", "|", "–", "—", "\"", "„", "“", "”", "‚", "‘", "’", "«", "»"]

    /// Gleiches Wort: gleiche Vergleichsform, sonst `plural` ? Plural/Genitiv (ohne Herkunfts-„-er“) : nur Genitiv-/Plural-s.
    static func sameWord(_ a: String, _ b: String, plural: Bool) -> Bool {
        let formsA = forms(a), formsB = forms(b)
        if !formsA.isDisjoint(with: formsB) { return true }
        func variants(_ word: String) -> Set<String> {
            let bases = plural ? bases(word, derivedNames: false) : sBase(word).map { [$0] } ?? []
            return Set(bases.flatMap(forms))
        }
        return !variants(a).isDisjoint(with: formsB) || !variants(b).isDisjoint(with: formsA)
    }

    // MARK: Vergleichsformen

    static let minimumLength = 3

    /// ae-Faltung (`Keywords.fold`) und a-Faltung („Müller“ → „mueller“, „muller“).
    static func forms(_ word: String) -> Set<String> {
        let ae = Keywords.fold(word)
        let plain = TextAnalysis.normalizedLower(word).replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        return [ae, plain]
    }

    /// Grundform ohne Genitiv-/Plural-s (Stamm ≥ 3 Zeichen).
    private static func sBase(_ word: String) -> String? {
        guard TextAnalysis.normalizedLower(word).hasSuffix("s"), word.count - 1 >= 3 else { return nil }
        return String(word.dropLast())
    }

    /// Grundformen von `word` für echte Beugungsendungen (Schreibweise wie im Original; die Mindestlänge gilt
    /// für den Stamm). `derivedNames`: auch die Herkunftsendung -er bei Eigennamen („Beueler“ → „Beuel“) – nie
    /// bei gewöhnlichen Wörtern („Fischer“ ↛ „Fisch“).
    static func bases(_ word: String, derivedNames: Bool = true) -> [String] {
        let lower = TextAnalysis.normalizedLower(word)
        let length = word.count
        func dropping(_ count: Int) -> String { String(word.dropLast(count)) }
        var result: [String] = []
        if let base = sBase(word) { result.append(base) }
        if lower.hasSuffix("es"), length - 2 >= 4 { result.append(dropping(2)) }
        if lower.hasSuffix("e"), length - 1 >= 5 { result.append(dropping(1)) }
        if lower.hasSuffix("en"), length - 2 >= 5, !lower.dropLast(2).hasSuffix("e") { result.append(dropping(2)) }
        if lower.hasSuffix("n"), length - 1 >= 4 {
            let stem = lower.dropLast()
            if stem.hasSuffix("e") || stem.hasSuffix("el") || stem.hasSuffix("er") { result.append(dropping(1)) }
        }
        if derivedNames, lower.hasSuffix("er"), length - 2 >= 4, word.first?.isUppercase == true {
            let stem = dropping(2)
            if !CommonWords.contains(stem) { result.append(stem) }
        }
        return result
    }

    /// Funktionswörter, Anreden, Rechtsformen und allgemeine Rollenwörter (de, en), gefaltet.
    static let stopwords: Set<String> = {
        let list = [
            // Deutsch: Artikel, Pronomen, Präpositionen, Konjunktionen, Hilfsverben
            "der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "eines", "einem", "einen",
            "und", "oder", "aber", "auch", "noch", "nur", "sowie", "bzw", "usw", "etc", "inkl", "plus",
            "mit", "ohne", "für", "fuer", "von", "vom", "zum", "zur", "bei", "beim", "auf", "aus", "über", "unter",
            "nach", "vor", "seit", "bis", "gegen", "durch", "rund", "um", "ums", "als", "wie", "was", "wer", "wo",
            "ich", "mich", "mir", "mein", "meine", "meiner", "meines", "meinem", "meinen", "wir", "uns", "unser",
            "unsere", "unserer", "unseres", "unserem", "unseren", "sie", "ihr", "ihre", "ihren", "ihrem", "ihrer",
            "er", "ihn", "ihm", "sein", "seine", "seinen", "seinem", "seiner", "dein", "deine", "man", "alle", "alles",
            "bin", "ist", "sind", "war", "hat", "habe", "haben", "wird", "werden", "kann", "muss", "soll",
            "hier", "dort", "dazu", "davon", "dabei", "sonst", "sonstiges", "andere", "anderes", "weitere",
            // Anreden und Titel
            "herr", "herrn", "frau", "dr", "prof", "mr", "mrs", "ms", "sir",
            // Rechtsformen
            "gmbh", "mbh", "ug", "ag", "kg", "ohg", "gbr", "ev", "co", "inc", "ltd", "llc", "plc", "corp",
            // Allgemeine Rollen- und Ordnungswörter, die in Beschreibungen vorkommen
            "firma", "firmen", "unternehmen", "kunde", "kunden", "kundin", "kundinnen", "auftraggeber",
            "projekt", "projekte", "thema", "themen", "sache", "sachen", "dinge", "zeug", "kram", "privat",
            "arbeit", "job", "team", "chef", "chefin", "kollege", "kollegen", "kollegin", "kolleginnen",
            "ansprechpartner", "ansprechpartnerin", "kontakt", "kontakte", "person", "personen", "leute",
            "mitglied", "mitglieder", "verein", "gruppe", "name", "namen", "betreff", "allgemein",
            // Englisch
            "the", "and", "or", "of", "for", "with", "from", "to", "at", "in", "on", "by", "my", "our", "your",
            "his", "her", "its", "their", "is", "are", "was", "be", "all", "any", "about", "also", "via", "per",
            "company", "client", "clients", "customer", "customers", "project", "projects", "team", "work",
            "stuff", "things", "people", "contact", "contacts", "club", "group", "member", "members",
        ]
        return Set(list.flatMap { forms($0) })
    }()
}

/// Gewöhnliche Wörter (de, en) – trennt Eigennamen („Kowalski“, „Brandt“) von Alltagswörtern („Pflege“, „Garten“).
///
/// Quelle ist der Wortschatz der eingebauten Wort-Embeddings (`NLEmbedding.wordEmbedding`, auf dem Gerät, ohne Netz;
/// Deutsch ≈ 49 000 Wörter in Originalschreibung, Englisch ≈ 57 000 klein). Zusammensetzungen zählen mit, wenn
/// ihr hinterer Teil (≥ 4 Buchstaben, vorn ≥ 3) ein gewöhnliches Substantiv ist („Arzttermine“, „Ruderverein“).
/// Der Wortschatz kennt auch bekannte Namen („Köln“, „Müller“) – im Zweifel gilt ein Wort als gewöhnlich, dann leitet
/// der Code nicht um. Fehlt der Wortschatz ganz, gilt jedes Wort als gewöhnlich.
enum CommonWords {
    private struct State {
        var loaded = false
        var german: NLEmbedding?
        var english: NLEmbedding?
        var known: [String: Bool] = [:]
    }

    /// NLEmbedding ist nicht threadsicher: alles unter einer Sperre, Ergebnisse gemerkt.
    private static let state = Mutex(State())
    private static let maxRemembered = 4_000

    static func contains(_ word: String) -> Bool {
        state.withLock { current in
            if let known = current.known[word] { return known }
            if !current.loaded {
                current.german = NLEmbedding.wordEmbedding(for: .german)
                current.english = NLEmbedding.wordEmbedding(for: .english)
                current.loaded = true
            }
            let result = lookup(word, german: current.german, english: current.english)
            if current.known.count >= maxRemembered { current.known.removeAll(keepingCapacity: true) }
            current.known[word] = result
            return result
        }
    }

    private static func lookup(_ word: String, german: NLEmbedding?, english: NLEmbedding?) -> Bool {
        guard let german, let english else { return true }
        let lower = TextAnalysis.normalizedLower(word)
        let noun = capitalized(lower)
        if german.contains(word) || german.contains(lower) || german.contains(noun) || english.contains(lower) { return true }
        let letters = Array(lower)
        guard letters.count >= 7 else { return false }
        for start in 3...(letters.count - 4) where german.contains(capitalized(String(letters[start...]))) {
            return true
        }
        return false
    }

    private static func capitalized(_ lower: String) -> String {
        guard let first = lower.first else { return lower }
        return first.uppercased() + lower.dropFirst()
    }
}
