import Foundation
import NaturalLanguage

/// Lokale Prüfung des KI-Ergebnisses (KONZEPT §6.7).
///
/// Grundsatz: feldweise zurückfallen statt alles verwerfen. Ein schlechter Titel kostet nicht die
/// Aufgaben. Verworfen wird alles nur, wenn das JSON nicht lesbar ist oder Titel und `clean_text`
/// beide leer sind (`finish_reason ≠ stop` prüft der Strukturierer vorher). Abgelehnte Felder
/// hinterlassen Codes in `rejections`, nie Text.
public enum ThoughtValidator {
    // MARK: Rohe Antwort (Schema §6.6)

    struct RawTopic: Decodable {
        var choice: String
        var id: String?
        var new_name: String?
        var symbol: String?
    }

    struct RawTask: Decodable {
        var text: String
        var quote: String
        var due_hint: String?
    }

    struct RawRelated: Decodable {
        var ref: String
        var kind: String
        var reason: String
        var confidence: String
    }

    struct RawAnswer: Decodable {
        var title: String
        var clean_text: String
        var topic: RawTopic
        var tasks: [RawTask]
        var related: [RawRelated]
    }

    struct RawPart: Decodable {
        var clean_text: String
        var tasks: [RawTask]
    }

    public enum Failure: Error, Sendable, Equatable {
        /// Antwort ist kein JSON nach Schema.
        case unreadable
        /// Titel und clean_text beide leer.
        case empty
    }

    public static let maxTasks = 5
    public static let maxRelated = 3
    public static let maxTitleLength = 60
    public static let maxTaskLength = 80
    public static let maxReasonLength = 60
    /// `medium` wird nur übernommen, wenn die lokale Vorauswahl mindestens so sicher war.
    public static let mediumLinkScore = 0.75

    // MARK: Ganzer Gedanke

    /// Prüft eine Antwort feldweise. `selfID`: ID des Gedankens selbst (kein Selbstbezug).
    public static func validate(json: String, input: StructureInput, aliases: ThoughtPrompt.Aliases,
                                selfID: String? = nil) -> Result<StructureResult, Failure> {
        guard let answer = try? JSONDecoder().decode(RawAnswer.self, from: Data(plainHyphens(json).utf8)) else { return .failure(.unreadable) }
        let rawTitle = answer.title.trimmed, rawText = answer.clean_text.trimmed
        guard !rawTitle.isEmpty || !rawText.isEmpty else { return .failure(.empty) }
        var rejections: [String] = []

        // clean_text: Sicherheitsnetz im Gedanken-Profil, sonst Rohtext (nil).
        var cleanText: String?
        if rawText.isEmpty {
            rejections.append("text:empty")
        } else if let reason = PolishSafetyNet.rejection(raw: input.transcript, result: rawText,
                                                         vocabulary: input.vocabulary, profile: .thought) {
            rejections.append("text:" + reason)
        } else {
            cleanText = rawText
        }

        // Titel
        let title: String
        if let checked = checkedTitle(rawTitle, transcript: input.transcript) {
            title = checked
        } else {
            rejections.append("title")
            title = fallbackTitle(cleanText ?? input.transcript)
        }

        let topic = checkedTopic(answer.topic, input: input, aliases: aliases, rejections: &rejections)
        let tasks = checkedTasks(answer.tasks, transcript: input.transcript, rejections: &rejections)
        let related = checkedRelated(answer.related, transcript: input.transcript, aliases: aliases, selfID: selfID,
                                     rejections: &rejections)
        return .success(StructureResult(title: title, cleanText: cleanText, topic: topic, tasks: tasks,
                                        related: related, rejections: rejections))
    }

    // MARK: Teile-Modus

    /// Prüft einen Folgeteil (`ThoughtPart`): nur `clean_text` und `tasks`. Titel leer, kein Thema.
    public static func validatePart(json: String, input: StructureInput) -> Result<StructureResult, Failure> {
        guard let part = try? JSONDecoder().decode(RawPart.self, from: Data(plainHyphens(json).utf8)) else { return .failure(.unreadable) }
        var rejections: [String] = []
        let rawText = part.clean_text.trimmed
        var cleanText: String?
        if rawText.isEmpty {
            rejections.append("text:empty")
        } else if let reason = PolishSafetyNet.rejection(raw: input.transcript, result: rawText,
                                                         vocabulary: input.vocabulary, profile: .thought) {
            rejections.append("text:" + reason)
        } else {
            cleanText = rawText
        }
        let tasks = checkedTasks(part.tasks, transcript: input.transcript, rejections: &rejections)
        return .success(StructureResult(title: "", cleanText: cleanText, topic: .none, tasks: tasks, related: [],
                                        rejections: rejections))
    }

    /// Setzt Teil 1 (voller Aufruf) und die Folgeteile zusammen.
    /// - Text: Teile in Reihenfolge, getrennt durch eine Leerzeile. Ein abgelehnter Teil steht als
    ///   Rohtext dieses Teils da (Code `text:part<k>:…` bleibt). Sind alle Teile abgelehnt: nil.
    /// - Aufgaben: aneinandergehängt, doppelte (normalisiert) fallen weg, höchstens 10.
    /// - Titel, Thema, Verwandte aus Teil 1.
    public static func assemble(first: StructureResult, firstTranscript: String,
                                parts: [(result: StructureResult, transcript: String)]) -> StructureResult {
        var pieces: [String] = []
        var anyClean = first.cleanText != nil
        pieces.append(first.cleanText ?? firstTranscript.trimmed)
        var rejections = first.rejections
        var tasks = first.tasks
        for (offset, part) in parts.enumerated() {
            let k = offset + 2
            if let text = part.result.cleanText { pieces.append(text); anyClean = true } else { pieces.append(part.transcript.trimmed) }
            rejections += part.result.rejections.map { "part\(k):" + $0 }
            tasks += part.result.tasks
        }
        var seen = Set<String>()
        tasks = tasks.filter { seen.insert(normalizedForMatch($0.text)).inserted }
        return StructureResult(title: first.title, cleanText: anyClean ? pieces.joined(separator: "\n\n") : nil,
                               topic: first.topic, tasks: Array(tasks.prefix(10)), related: first.related,
                               rejections: rejections)
    }

    // MARK: Titel

    static let quoteCharacters: Set<Character> = ["\"", "'", "„", "“", "”", "‚", "‘", "’", "«", "»", "‹", "›", "「", "」", "『", "』"]

    /// Titel säubern und prüfen; nil = Ersatztitel nötig.
    static func checkedTitle(_ raw: String, transcript: String) -> String? {
        var title = (raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? "").trimmed
        title = String(title.drop(while: { quoteCharacters.contains($0) || $0 == " " }))
        // Kein Satzzeichen am Ende (Titel-Regel v2).
        while let last = title.last, quoteCharacters.contains(last) || ".…!?:;,–—-".contains(last) || last == " " {
            title.removeLast()
        }
        title = title.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        guard (1...maxTitleLength).contains(title.count) else { return nil }
        // Jede Zahl des Titels steht im Transkript.
        guard digitsContained(title, in: transcript) else { return nil }
        // Mindestens ein Inhaltswort stammt aus dem Transkript.
        guard sharesContentWord(title, with: transcript) else { return nil }
        return title
    }

    /// Ersatztitel: die ersten 6 Wörter des Textes (ohne Zögerlaute) + „…“.
    static func fallbackTitle(_ text: String) -> String {
        let words = text.replacingOccurrences(of: "• ", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !Lexicon.fillers.contains(TextAnalysis.normalizedLower($0.trimmingCharacters(in: .punctuationCharacters))) }
        guard !words.isEmpty else { return "…" }
        var head = words.prefix(6).joined(separator: " ")
        while let last = head.last, ",;:.".contains(last) { head.removeLast() }
        return words.count > 6 ? head + " …" : head
    }

    // MARK: Thema

    static func checkedTopic(_ raw: RawTopic, input: StructureInput, aliases: ThoughtPrompt.Aliases,
                             rejections: inout [String]) -> TopicDecision {
        switch raw.choice {
        case "existing":
            guard let alias = raw.id?.trimmed, let entry = aliases.topics[alias] else {
                rejections.append("topic:alias")
                return .none
            }
            return .existing(entry.topicID)
        case "new":
            guard let name = raw.new_name?.trimmed, !name.isEmpty else {
                rejections.append("topic:name")
                return .none
            }
            // Doppel-Schranke: Nur ein Name, der dem Titel eines vorhandenen Themas ohne Zweifel gleich ist, leitet
            // um – beschrieben oder nicht. Namen aus Beschreibungen sind nur Hinweise (`mentioned`), unscharfe Nähe
            // nur ein späterer Vorschlag. Mehrere gleich gute Titel: der Code entscheidet nicht, und ein weiteres
            // gleichnamiges Thema entsteht auch nicht.
            let same = TopicHygiene.sameNamed(name, among: input.topics)
            if same.count == 1 {
                rejections.append("topic:duplicate")
                return .existing(same[0].topicID)
            }
            if same.count > 1 {
                rejections.append("topic:ambiguous")
                return .none
            }
            if input.topicsFull {
                rejections.append("topic:full")
                return .none
            }
            guard TopicHygiene.isValidNewName(name) else {
                rejections.append("topic:name")
                return .none
            }
            return .new(name: name, icon: raw.symbol.flatMap(TopicIcon.init(rawValue:)) ?? .sparkles)
        case "none":
            return .none
        default:
            rejections.append("topic:choice")
            return .none
        }
    }

    // MARK: Aufgaben

    static func checkedTasks(_ raw: [RawTask], transcript: String, rejections: inout [String]) -> [TaskDraft] {
        if raw.count > maxTasks { rejections.append("tasks:limit") }
        var result: [TaskDraft] = []
        var seen = Set<String>()
        for task in raw.prefix(maxTasks) {
            guard let quote = locateQuote(task.quote, in: transcript) else { rejections.append("task:quote"); continue }
            let text = task.text.trimmed.replacingOccurrences(of: "\n", with: " ")
            guard (2...maxTaskLength).contains(text.count) else { rejections.append("task:text"); continue }
            guard taskWordsGrounded(text, quote: quote) else { rejections.append("task:words"); continue }
            guard digitsContained(text, in: quote) else { rejections.append("task:digits"); continue }
            guard effectiveNegations(text) == effectiveNegations(quote) else { rejections.append("task:negation"); continue }
            var due: String?
            if let hint = task.due_hint?.trimmed, !hint.isEmpty {
                if normalizedForMatch(quote).contains(normalizedForMatch(hint)), !normalizedForMatch(hint).isEmpty {
                    due = hint
                } else {
                    rejections.append("task:due")
                }
            }
            guard seen.insert(normalizedForMatch(text)).inserted else { rejections.append("task:duplicate"); continue }
            result.append(TaskDraft(text: text, quote: quote, dueHint: due))
        }
        return result
    }

    /// Erinnerungsfloskeln: Ihre Verneinung gehört nicht zur Handlung („nicht vergessen, Milch …“).
    static let reminderPhrases: [String] = [
        "nicht vergessen", "vergiss nicht", "vergessen sie nicht", "nicht zu vergessen", "vergesst nicht",
        "don't forget", "do not forget", "dont forget", "n'oublie pas", "n'oubliez pas", "no olvides", "no olvidar",
        "non dimenticare", "não esquecer", "não esqueças", "niet vergeten", "vergeet niet", "nie zapomnij",
        "unutma", "unutmayın",
    ].map { TextAnalysis.normalizedLower($0).replacingOccurrences(of: "’", with: "'") }

    static func effectiveNegations(_ text: String) -> Int {
        let lower = TextAnalysis.normalizedLower(text).replacingOccurrences(of: "’", with: "'")
        let reminders = reminderPhrases.reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }
        return max(0, TextAnalysis.negationCount(text) - reminders)
    }

    /// Kleine Füllwörter, die ein Aufgabentext ohne Beleg enthalten darf.
    static let taskStopwords: Set<String> = Set([
        "der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "und", "oder", "für", "mit",
        "von", "zu", "zum", "zur", "im", "in", "an", "am", "auf", "bei", "wegen", "noch", "the", "a", "an", "and", "or",
        "for", "with", "to", "of", "in", "on", "at", "le", "la", "les", "un", "une", "de", "du", "des", "et", "pour",
        "el", "los", "las", "y", "para", "con", "il", "lo", "gli", "e", "per", "o", "os", "as", "um", "uma", "het", "een",
        "en", "voor", "met",
    ].map(TextAnalysis.normalizedLower))

    /// Inhaltswörter des Aufgabentexts ⊆ Wörter/Lemmata des Zitats + höchstens 1 weiteres.
    static func taskWordsGrounded(_ text: String, quote: String) -> Bool {
        let quoteForms = wordForms(quote)
        var ungrounded = 0
        for word in TextAnalysis.letterRuns(TextAnalysis.normalizedLower(text)) where word.count >= 2 {
            if taskStopwords.contains(word) { continue }
            if matches(word, quoteForms) { continue }
            ungrounded += 1
            if ungrounded > 1 { return false }
        }
        return true
    }

    // MARK: Verwandte

    static func checkedRelated(_ raw: [RawRelated], transcript: String, aliases: ThoughtPrompt.Aliases, selfID: String?,
                               rejections: inout [String]) -> [RelatedDraft] {
        if raw.count > maxRelated { rejections.append("related:limit") }
        var result: [RelatedDraft] = []
        var seen = Set<String>()
        for link in raw.prefix(maxRelated) {
            guard let candidate = aliases.candidates[link.ref.trimmed] else { rejections.append("related:ref"); continue }
            guard candidate.thoughtID != selfID else { rejections.append("related:self"); continue }
            guard let kind = LinkKind(rawValue: link.kind) else { rejections.append("related:kind"); continue }
            let reason = link.reason.trimmed.replacingOccurrences(of: "\n", with: " ")
            guard (1...maxReasonLength).contains(reason.count) else { rejections.append("related:reason"); continue }
            let known = transcript + " " + candidate.title + " " + candidate.excerpt
            guard digitsContained(reason, in: known) else { rejections.append("related:digits"); continue }
            switch link.confidence {
            case "high": break
            case "medium" where candidate.localScore >= mediumLinkScore: break
            default: rejections.append("related:confidence"); continue
            }
            guard seen.insert(candidate.thoughtID).inserted else { continue }
            result.append(RelatedDraft(thoughtID: candidate.thoughtID, kind: kind, reason: reason))
        }
        return result
    }

    // MARK: Hilfen

    /// gpt-oss schreibt Bindestriche oft als U+2011 (geschützt) oder U+2010. Für Suche, Kopieren und
    /// Anzeige gilt der normale Bindestrich (E1: „RevenueCat‑Dashboard“, „Kita‑Rechnungen“).
    static func plainHyphens(_ json: String) -> String {
        json.replacingOccurrences(of: "\u{2011}", with: "-").replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\\u2011", with: "-").replacingOccurrences(of: "\\u2010", with: "-")
    }

    /// Vergleichsform für Zitate: klein, ohne Akzente, ohne Satzzeichen, Leerraum zusammengefasst.
    static func normalizedForMatch(_ text: String) -> String {
        tokens(text).map(\.word).joined(separator: " ")
    }

    /// Wörter (Buchstaben/Ziffern) in Vergleichsform mit ihrem Bereich im Original.
    static func tokens(_ text: String) -> [(word: String, range: Range<String.Index>)] {
        TextAnalysis.runs(text, where: TextAnalysis.isWordScalar).map { run in
            (TextAnalysis.normalizedLower(run.word).folding(options: .diacriticInsensitive, locale: nil), run.range)
        }
    }

    /// Findet das Zitat im Transkript und gibt die echte Stelle zurück: wörtlich (normalisiert),
    /// sonst unscharf (Token-LCS ≥ 0,9). nil = nicht belegt.
    static func locateQuote(_ quote: String, in transcript: String) -> String? {
        let q = tokens(quote).map(\.word)
        guard !q.isEmpty else { return nil }
        let t = tokens(transcript)
        guard t.count >= 1 else { return nil }
        let words = t.map(\.word)
        func span(_ start: Int, _ end: Int) -> String {
            String(transcript[t[start].range.lowerBound..<t[end].range.upperBound])
        }
        if q.count <= words.count {
            for start in 0...(words.count - q.count) where words[start..<(start + q.count)].elementsEqual(q) {
                return span(start, start + q.count - 1)
            }
        }
        // Unscharf: bestes Fenster ähnlicher Länge.
        var best: (score: Double, start: Int, end: Int)?
        let lengths = max(1, q.count - 2)...(q.count + 2)
        for length in lengths where length <= words.count {
            for start in 0...(words.count - length) {
                let window = Array(words[start..<(start + length)])
                let common = lcsLength(window, q)
                let score = Double(common) / Double(max(q.count, length))
                if score >= 0.9, best == nil || score > best!.score {
                    best = (score, start, start + length - 1)
                }
            }
        }
        if let best { return span(best.start, best.end) }
        return elidedSpan(quote, words: words, span: span)
    }

    /// Längste Spanne für ein Zitat mit Auslassung („die Screenshots für den App Store … bis zur Einreichung“):
    /// jedes Stück wörtlich und in Reihenfolge, zusammen höchstens `maxElidedSpan` Wörter. Zurück kommt die
    /// echte, zusammenhängende Stelle des Transkripts.
    static let maxElidedSpan = 30

    private static func elidedSpan(_ quote: String, words: [String], span: (Int, Int) -> String) -> String? {
        let pieces = quote.replacingOccurrences(of: "...", with: "…").split(separator: "…")
            .map { tokens(String($0)).map(\.word) }.filter { !$0.isEmpty }
        guard pieces.count >= 2 else { return nil }
        func find(_ piece: [String], from: Int) -> Int? {
            guard from + piece.count <= words.count else { return nil }
            return (from...(words.count - piece.count)).first { words[$0..<($0 + piece.count)].elementsEqual(piece) }
        }
        var starts = 0
        while let first = find(pieces[0], from: starts) {
            var end = first + pieces[0].count
            var complete = true
            for piece in pieces.dropFirst() {
                guard let next = find(piece, from: end), next + piece.count - first <= maxElidedSpan else { complete = false; break }
                end = next + piece.count
            }
            if complete { return span(first, end - 1) }
            starts = first + 1
        }
        return nil
    }

    static func lcsLength(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                current[j + 1] = x == y ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Alle Zahlen von `text` stehen in `source` (gleiche Ziffern oder Zahlwort gleichen Werts, auch
    /// zusammengesetzt: „28.“ ← „achtundzwanzigsten“, „20 Kartons“ ← „zwanzig Kartons“).
    static func digitsContained(_ text: String, in source: String) -> Bool {
        SpokenNumbers.digitsContained(text, in: source)
    }

    /// Wortformen eines Texts: normalisierte Wörter plus Lemmata (NaturalLanguage, wo verfügbar).
    static func wordForms(_ text: String) -> Set<String> {
        var forms = Set(TextAnalysis.letterRuns(TextAnalysis.normalizedLower(text)))
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if let lemma = tag?.rawValue, !lemma.isEmpty { forms.insert(TextAnalysis.normalizedLower(lemma)) }
            return true
        }
        return forms
    }

    /// Wort passt zu einer Form: gleich, gleiches Lemma, oder gemeinsamer Anfang ≥ 4 Zeichen,
    /// der höchstens 3 Zeichen kürzer ist als das kürzere Wort (Beugung: „anrufen“/„anrufe“).
    static func matches(_ word: String, _ forms: Set<String>) -> Bool {
        if forms.contains(word) { return true }
        for lemma in wordForms(word) where forms.contains(lemma) { return true }
        let w = Array(word.unicodeScalars)
        for form in forms {
            let f = Array(form.unicodeScalars)
            let shorter = min(w.count, f.count)
            guard shorter >= 4 else { continue }
            var common = 0
            while common < shorter, w[common] == f[common] { common += 1 }
            if common >= 4, common >= shorter - 3 { return true }
        }
        return false
    }

    /// Hat der Titel mindestens ein Inhaltswort (≥ 3 Buchstaben, kein Füllwort) aus dem Transkript?
    /// Schriften ohne Leerzeichen: mindestens ein gemeinsames Zeichenpaar.
    static func sharesContentWord(_ title: String, with transcript: String) -> Bool {
        if TextAnalysis.containsScriptioContinua(title) {
            let units = Set(TextAnalysis.contentUnits(transcript))
            return TextAnalysis.contentUnits(title).contains(where: units.contains)
        }
        let forms = wordForms(transcript)
        for word in TextAnalysis.letterRuns(TextAnalysis.normalizedLower(title))
        where TextAnalysis.weightedLength(word) >= 3 && !taskStopwords.contains(word) && !Lexicon.fillers.contains(word) {
            if matches(word, forms) { return true }
        }
        return false
    }
}
