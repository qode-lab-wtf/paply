import Foundation

/// Lokale Suche (KONZEPT §3.1): sofort, ohne Netz, ohne Groß-/Kleinschreibung und Akzente.
/// Mehrere Wörter gelten als UND, Wortanfänge zählen als Treffer. Durchsucht Titel, Text, Rohtext,
/// Aufgaben und Themennamen; liefert je Gedanke einen Ausschnitt mit Fundstellen (UTF-16).
public enum ThoughtSearch {
    /// Vergleichsform: klein, ohne Akzente, ß → ss.
    public static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.contains("ß") ? folded.replacingOccurrences(of: "ß", with: "ss") : folded
    }

    /// Suchwörter der Eingabe (gefaltet, ohne Satzzeichen).
    public static func tokens(_ query: String) -> [String] {
        var seen: Set<String> = []
        return TextAnalysis.alphanumericRuns(fold(query)).filter { seen.insert($0).inserted }
    }

    /// Gefaltete Wörter als Bytefolge „ w1 w2 … “: ein Wortanfang ist dann „ “ + Suchwort.
    static func haystack(_ text: String) -> [UInt8] {
        guard !text.isEmpty else { return [] }
        let words = TextAnalysis.alphanumericRuns(fold(text))
        guard !words.isEmpty else { return [] }
        return Array((" " + words.joined(separator: " ") + " ").utf8)
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        return haystack.withUnsafeBytes { h in
            needle.withUnsafeBytes { n in
                memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil
            }
        }
    }
}

/// Suchindex im RAM (≈ 3 KB je Gedanke). Die Oberfläche hält ihn aktuell (`upsert`/`remove`).
/// Jedes Feld wird beim Aufnehmen einmal gefaltet; die Suche selbst faltet nur die Anfrage.
public struct ThoughtSearchIndex: Sendable {
    /// Gewichte je Feld (Titel zählt am meisten)
    static let weights: [SearchHit.Field: Double] = [.title: 4, .topic: 3, .task: 2, .text: 1.5, .raw: 1]
    /// Reihenfolge für den Ausschnitt: zuerst der Fließtext, Titel und Thema stehen ohnehin in der Zeile
    static let snippetOrder: [SearchHit.Field] = [.text, .task, .raw, .title, .topic]

    /// Ein Feld: Originaltext, Wortbereiche darin, dieselben Wörter gefaltet, Bytefolge für die Suche.
    struct Field: Sendable {
        var kind: SearchHit.Field
        var weight: Double
        var text: String
        var words: [Range<String.Index>]
        var folded: [String]
        var haystack: [UInt8]

        init(_ kind: SearchHit.Field, _ text: String) {
            self.kind = kind
            weight = ThoughtSearchIndex.weights[kind] ?? 1
            self.text = text
            let runs = TextAnalysis.runs(text, where: TextAnalysis.isWordScalar)
            words = runs.map(\.range)
            let all = TextAnalysis.alphanumericRuns(ThoughtSearch.fold(text))
            // Falten ändert Wortgrenzen praktisch nie; sonst Wort für Wort
            folded = all.count == runs.count ? all : runs.map { ThoughtSearch.fold($0.word) }
            haystack = folded.isEmpty ? [] : Array((" " + folded.joined(separator: " ") + " ").utf8)
        }
    }

    struct Doc: Sendable {
        var id: String
        var createdAt: Date
        var fields: [Field]
    }

    private var docs: [Doc] = []
    private var positions: [String: Int] = [:]

    public init() {}

    public var count: Int { docs.count }

    public mutating func upsert(_ thought: Thought, topicName: String?, raw: String?) {
        var fields: [Field] = []
        if let title = thought.title, !title.isEmpty { fields.append(Field(.title, title)) }
        if let text = thought.text, !text.isEmpty { fields.append(Field(.text, text)) }
        for task in thought.tasks where !task.text.isEmpty { fields.append(Field(.task, task.text)) }
        if let topicName, !topicName.isEmpty { fields.append(Field(.topic, topicName)) }
        if let raw, !raw.isEmpty { fields.append(Field(.raw, raw)) }
        let doc = Doc(id: thought.id, createdAt: thought.createdAt, fields: fields.filter { !$0.haystack.isEmpty })
        if let position = positions[thought.id] {
            docs[position] = doc
        } else {
            positions[thought.id] = docs.count
            docs.append(doc)
        }
    }

    public mutating func remove(_ id: String) {
        guard let position = positions.removeValue(forKey: id) else { return }
        let last = docs.removeLast()
        if position < docs.count {
            docs[position] = last
            positions[last.id] = position
        }
    }

    /// Treffer absteigend nach Gewicht, bei Gleichstand neueste zuerst. Prüfen und Ausschnitte laufen
    /// parallel über alle Kerne (reine Arbeit je Gedanke).
    public func search(_ query: String, limit: Int = 300) -> [SearchHit] {
        let tokens = ThoughtSearch.tokens(query)
        guard !tokens.isEmpty, !docs.isEmpty else { return [] }
        let needles = tokens.map { Array((" " + $0).utf8) }
        let list = docs
        let evaluated = Parallel.map(list.count) { Self.evaluate(list[$0], needles: needles) }
        var matches: [(doc: Int, score: Double, hits: [Int])] = []
        for (index, result) in evaluated.enumerated() {
            if let result { matches.append((index, result.score, result.hits)) }
        }
        matches.sort { a, b in
            a.score != b.score ? a.score > b.score : list[a.doc].createdAt > list[b.doc].createdAt
        }
        let top = Array(matches.prefix(limit))
        let hits = Parallel.map(top.count) { index -> SearchHit? in
            let match = top[index]
            let doc = list[match.doc]
            let field = Self.snippetField(doc.fields, hits: match.hits)
            let snippet: (text: String, ranges: [Range<Int>]) = field.map { Self.snippet($0, tokens: tokens) } ?? ("", [])
            return SearchHit(thoughtID: doc.id, field: field?.kind ?? .text, snippet: snippet.text, ranges: snippet.ranges, score: match.score)
        }
        return hits.compactMap { $0 }
    }

    /// UND über alle Suchwörter; je Wort zählt das beste Feld.
    static func evaluate(_ doc: Doc, needles: [[UInt8]]) -> Evaluation? {
        var score = 0.0
        var hits = [Int](repeating: 0, count: doc.fields.count)
        for needle in needles {
            var best = 0.0
            for index in doc.fields.indices where ThoughtSearch.contains(doc.fields[index].haystack, needle) {
                hits[index] += 1
                best = max(best, doc.fields[index].weight)
            }
            if best == 0 { return nil }
            score += best
        }
        return Evaluation(score: score, hits: hits)
    }

    struct Evaluation: Sendable {
        var score: Double
        var hits: [Int]
    }

    /// Feld mit den meisten Treffern; bei Gleichstand nach `snippetOrder`.
    static func snippetField(_ fields: [Field], hits: [Int]) -> Field? {
        var best: (field: Field, hits: Int, order: Int)?
        for (index, field) in fields.enumerated() where hits[index] > 0 {
            let order = snippetOrder.firstIndex(of: field.kind) ?? snippetOrder.count
            if best == nil || hits[index] > best!.hits || (hits[index] == best!.hits && order < best!.order) {
                best = (field, hits[index], order)
            }
        }
        return best?.field
    }

    /// Ausschnitt um den ersten Treffer (≈ 120 Zeichen, an Wortgrenzen) und Fundstellen darin (UTF-16).
    static func snippet(_ field: Field, tokens: [String], before: Int = 30, length: Int = 120) -> (text: String, ranges: [Range<Int>]) {
        let text = field.text
        guard !field.words.isEmpty else { return (text, []) }
        func matching(_ index: Int) -> String? {
            tokens.filter { field.folded[index].hasPrefix($0) }.max { $0.count < $1.count }
        }
        let first = field.folded.indices.first { matching($0) != nil } ?? 0
        var startWord = 0
        if text.distance(from: text.startIndex, to: field.words[first].lowerBound) > before {
            startWord = first
            var k = first
            while k > 0, text.distance(from: field.words[k - 1].lowerBound, to: field.words[first].lowerBound) <= before {
                k -= 1
                startWord = k
            }
        }
        let start = startWord == 0 ? text.startIndex : field.words[startWord].lowerBound
        var endWord = field.words.count - 1
        var end = text.endIndex
        if text.distance(from: start, to: text.endIndex) > length {
            endWord = startWord
            while endWord + 1 < field.words.count, text.distance(from: start, to: field.words[endWord + 1].upperBound) <= length {
                endWord += 1
            }
            end = field.words[endWord].upperBound
        }
        let prefix = start == text.startIndex ? "" : "…"
        let suffix = end == text.endIndex ? "" : "…"
        let body = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        let offset = prefix.utf16.count
        var ranges: [Range<Int>] = []
        for index in startWord...endWord {
            guard let token = matching(index) else { continue }
            let word = field.words[index]
            let lower = offset + text.utf16.distance(from: start, to: word.lowerBound)
            let upperIndex = text.index(word.lowerBound, offsetBy: token.count, limitedBy: word.upperBound) ?? word.upperBound
            ranges.append(lower..<(lower + text.utf16.distance(from: word.lowerBound, to: min(upperIndex, word.upperBound))))
        }
        return (prefix + body + suffix, ranges)
    }
}
