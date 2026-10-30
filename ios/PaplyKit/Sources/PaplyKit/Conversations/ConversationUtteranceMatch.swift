import Foundation

/// Indizes sind nach einer Neuauswertung keine Identität.
enum ConversationUtteranceMatch {
    static func matches(_ old: ConversationUtterance, _ new: ConversationUtterance) -> Bool {
        let overlap = max(0, min(old.end, new.end) - max(old.start, new.start))
        guard overlap > 0, overlap >= 0.5 * max(old.end - old.start, new.end - new.start) else { return false }
        func tokens(_ text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        let a = tokens(old.text), b = tokens(new.text)
        if a == b { return !a.isEmpty }
        let shared = Set(a).intersection(Set(b)).count
        return Double(shared) / Double(max(Set(a).count, Set(b).count, 1)) >= 0.8
    }
}
