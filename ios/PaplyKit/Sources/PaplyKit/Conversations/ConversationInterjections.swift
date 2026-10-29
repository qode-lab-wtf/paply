import Foundation

/// Plattformneutrale Regeln aus MESSUNG.md; unabhängig vom Embedding-Modell.
enum ConversationInterjections {
    static let groupPause = 0.8
    static let majority = 0.7
    static let clearMargin = 0.6
    // Kleine gemeinsame Liste für Deutsch und Englisch, keine allgemeinen Stoppwörter.
    static let sounds: Set<String> = ["mhm", "hm", "hmm", "mm", "äh", "ähm", "aha", "uh", "um", "uhm", "mmh"]
    static let lexical: Set<String> = ["ja", "genau", "okay", "ok", "stimmt", "klar", "richtig", "yes", "yeah", "right", "sure", "yep"]
    static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }
    static func isSound(_ text: String) -> Bool {
        let words = tokens(text)
        return !words.isEmpty && words.allSatisfy { sounds.contains($0) }
    }
    static func isLexical(_ text: String) -> Bool {
        let words = tokens(text)
        return !words.isEmpty && words.count <= 2 && words.allSatisfy { lexical.contains($0) }
    }
    static func eligible(_ utterance: ConversationUtterance) -> Bool {
        utterance.uncertain && utterance.speakerOwner != .user && (1...6).contains(tokens(utterance.text).count)
    }
}
