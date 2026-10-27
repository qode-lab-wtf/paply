import Foundation

/// Deterministische Hilfe vor der KI (KONZEPT §6.3): Kommt ein Name oder Stichwort eines **beschriebenen**
/// Themas im Transkript vor, ist das Thema ein starker Kandidat (`TopicIndexEntry.mentioned`).
///
/// - Begriffe: aussagekräftige Wörter aus Name und Beschreibung (`Topic.note`). Stoppwörter, Rechtsformen,
///   Anreden, allgemeine Rollenwörter („Firma“, „Kunden“), reine Zahlen und Wörter unter 3 Zeichen zählen nicht.
///   Stichwörter werden nicht gespeichert, sondern bei jedem Aufruf aus der Beschreibung abgeleitet – so bleibt
///   es bei einem Feld „Worum geht's?“.
/// - Vergleich an Wortgrenzen, ohne Groß/Klein und Akzente; Umlaute gelten als ä = ae = a, ß = ss.
/// - Einfache Beugungen: Genitiv/Plural-„s“ („Kowalskis“, „Omas“) und ab 4 Zeichen Stamm „-e, -n, -en, -er,
///   -es, -ern, -ens“ („Vereine“, „Beueler“), in beide Richtungen.
/// - Themen ohne Beschreibung bekommen keine Treffer (ihr Name zählt schon in der lokalen Passung).
public enum TopicMentions {
    /// Ein Begriff: Vergleichsformen und die Schreibweise aus Name/Beschreibung.
    public struct Term: Sendable, Equatable {
        public var original: String
        /// gefaltete Formen (ae- und a-Faltung)
        var forms: Set<String>
        /// Stämme der Formen (der Begriff ist selbst gebeugt, z. B. „Müllers“)
        var stems: Set<String>
    }

    /// Wörter eines Texts in Vergleichsform – für viele Themen nur einmal berechnen.
    public struct Haystack: Sendable {
        /// gefaltete Wörter
        var forms: Set<String> = []
        /// gefaltete Wörter und ihre Stämme
        var keys: Set<String> = []

        public init(_ text: String) {
            for word in TextAnalysis.alphanumericRuns(text) {
                for form in TopicMentions.forms(word) {
                    forms.insert(form)
                    keys.insert(form)
                    keys.formUnion(TopicMentions.stems(form))
                }
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
        return Term(original: word, forms: forms, stems: Set(forms.flatMap(stems)))
    }

    // MARK: Treffer

    /// Begriffe des Themas, die im Text vorkommen (Schreibweise aus Name/Beschreibung).
    public static func matches(_ terms: [Term], in haystack: Haystack) -> [String] {
        terms.filter(haystack.contains).map(\.original)
    }

    public static func matches(_ topic: Topic, in text: String) -> [String] {
        matches(terms(topic), in: Haystack(text))
    }

    /// Meint `name` (z. B. ein von der KI vorgeschlagenes neues Thema) ein beschriebenes Thema?
    /// Ja, wenn jedes aussagekräftige Wort des Namens ein Begriff dieses Themas ist („Müller Bau“ bei
    /// „… Kunden Müller Bau …“). So zieht ein gemeinsamer Ort allein („Kita Beuel“ ↔ „… Beuel …“) nicht.
    /// Bei mehreren: das mit den meisten Gedanken.
    public static func describedMatch(_ name: String, among topics: [TopicIndexEntry]) -> TopicIndexEntry? {
        let nameWords = words(name)
        guard !nameWords.isEmpty else { return nil }
        var best: TopicIndexEntry?
        for entry in topics {
            let topicTerms = terms(title: entry.name, note: entry.about)
            guard !topicTerms.isEmpty else { continue }
            var haystack = Haystack("")
            for term in topicTerms {
                haystack.forms.formUnion(term.forms)
                haystack.keys.formUnion(term.forms)
                haystack.keys.formUnion(term.stems)
            }
            guard nameWords.allSatisfy(haystack.contains) else { continue }
            if best == nil || entry.count > best!.count { best = entry }
        }
        return best
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

    private static let longSuffixes = ["ern", "ens", "en", "er", "es", "e", "n"]

    /// Stämme für einfache Beugungen: „-s“ bei ≥ 3 Zeichen Rest, sonst ≥ 4 Zeichen Rest.
    static func stems(_ form: String) -> [String] {
        var result: [String] = []
        if form.hasSuffix("s"), form.count - 1 >= 3 { result.append(String(form.dropLast())) }
        for suffix in longSuffixes where form.hasSuffix(suffix) && form.count - suffix.count >= 4 {
            result.append(String(form.dropLast(suffix.count)))
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
