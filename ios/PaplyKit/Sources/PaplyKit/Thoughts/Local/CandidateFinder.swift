// GERÜST (G0.1, Koordinator). Besitzer: H2. Signatur aus KONZEPT.md §9.2 bitte nicht ändern.
import Foundation

/// Lokale Vorauswahl: Themen-Index + höchstens 7 Kandidaten (KONZEPT §6.3).
public struct CandidateFinder: CandidateFinding {
    public init() {}

    public func topicIndex(forText: String, languages: [String]) async -> (entries: [TopicIndexEntry], full: Bool) {
        ([], false)
    }

    public func candidates(forText: String, languages: [String], excluding: String) async -> [CandidateEntry] {
        []
    }

    public func didChange(_ thought: Thought) async {}
}
