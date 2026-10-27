import Foundation

/// Kompakter Themen-Index (KONZEPT §6.3, §6.10): alle aktiven Themen (≤ 24) nach lokaler Passung,
/// dazu vorläufige Themen der letzten 60 Tage (≤ 8). `hint` = die 3 wichtigsten Schlagwörter.
/// Beschriebene Themen mit Namens-Treffer (`TopicMentions`) stehen immer vorn, höchstens `maxMentioned`.
public enum TopicIndex {
    public static let maxActive = 24
    public static let maxProvisional = 8
    public static let maxMentioned = 8
    public static let provisionalWindow: TimeInterval = 60 * 24 * 3600
    /// Ruhende Themen (90 Tage ohne Gedanken) wandern in den Chips nach hinten.
    public static let dormantAfter: TimeInterval = 90 * 24 * 3600

    public struct Summary: Sendable, Equatable {
        public var topic: Topic
        public var count: Int
        public var lastActivity: Date?
        public var isActive: Bool
        public var memberIDs: [String]
    }

    /// aktiv = vom Nutzer angelegt oder ≥ 2 Gedanken (§7.3); sonst vorläufig
    public static func isActive(_ topic: Topic, count: Int) -> Bool {
        topic.owner == .user || count >= 2
    }

    /// Je nicht zusammengeführtem Thema: Anzahl (ohne gelöschte), letzte Aktivität, Mitglieder.
    public static func summaries(topics: [Topic], thoughts: [Thought]) -> [Summary] {
        var members: [String: [Thought]] = [:]
        for thought in thoughts where thought.deletedAt == nil && thought.state != .recording {
            guard let resolved = ThoughtStore.resolve(thought.topicId, in: topics) else { continue }
            members[resolved.id, default: []].append(thought)
        }
        return topics.filter { $0.mergedInto == nil }.map { topic in
            let list = members[topic.id] ?? []
            return Summary(topic: topic, count: list.count, lastActivity: list.map(\.createdAt).max(),
                           isActive: isActive(topic, count: list.count), memberIDs: list.map(\.id))
        }
    }

    /// Passung eines Themas zur Anfrage: Kosinus zum Schwerpunkt (falls vergleichbar) und
    /// TF-IDF-Kosinus der Schlagwörter (Mitglieder + Themenname + Beschreibung).
    struct Fit {
        var score: Double
        var hint: [String]
    }

    static func fit(summary: Summary, index: LocalIndex, queryTerms: [String: Int], queryVector: EmbeddingVector?,
                    mean: [Float]?, cosineFloor: Double) -> Fit {
        var terms: [String: Int] = [:]
        var sum: [Float]?
        var vectorCount = 0
        for id in summary.memberIDs {
            guard let entry = index[id] else { continue }
            for (term, count) in entry.terms { terms[term, default: 0] += count }
            if let query = queryVector, let vector = entry.vector, vector.isComparable(to: query) {
                if sum == nil { sum = [Float](repeating: 0, count: vector.values.count) }
                for i in 0..<vector.values.count { sum![i] += vector.values[i] }
                vectorCount += 1
            }
        }
        let nameTerms = TextAnalysis.letterRuns(summary.topic.title).map(Keywords.fold).filter { $0.count >= 3 }
        var hintTerms = terms
        for term in nameTerms { terms[term, default: 0] += 2 }
        // Beschreibung des Nutzers: zählt für die Passung, ist aber kein Hinweis (sie geht als `about` mit).
        if let note = summary.topic.describedNote {
            for term in Keywords.terms(note, language: nil) { terms[term, default: 0] += 1 }
        }
        let keyword = tfidfCosine(queryTerms, terms, index: index)
        var score = keyword
        if let query = queryVector, let sum, vectorCount > 0 {
            let centroid = sum.map { $0 / Float(vectorCount) }
            let cos = CandidateFinder.adjustedCosine(query.values, centroid, mean: mean, floor: cosineFloor)
            score = 0.6 * cos + 0.4 * keyword
        }
        for term in nameTerms { hintTerms[term] = nil } // der Name selbst ist kein Hinweis
        let hint = Keywords.top(hintTerms, limit: 3, idf: index.idf)
        return Fit(score: score, hint: hint)
    }

    static func tfidfCosine(_ a: [String: Int], _ b: [String: Int], index: LocalIndex) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        func weight(_ count: Int, _ term: String) -> Double { (1 + log(Double(count))) * index.idf(term) }
        var dot = 0.0, na = 0.0, nb = 0.0
        for (term, count) in a {
            let w = weight(count, term)
            na += w * w
            if let other = b[term] { dot += w * weight(other, term) }
        }
        for (term, count) in b {
            let w = weight(count, term)
            nb += w * w
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}
