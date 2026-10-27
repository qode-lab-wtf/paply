// Besitzer: H2. Signatur aus KONZEPT.md §9.2 bitte nicht ändern.
import Foundation

// Hilfstypen der UI-Fassade (ThoughtsModel, §9.2), die §9.2 nennt, aber nicht ausformuliert.
// H2 darf Felder ergänzen; die vorhandenen bitte stabil lassen (H4 baut dagegen).

/// Vorschlag der Themenpflege: zwei Themen zusammenführen (§3.8, §6.10).
public struct TopicSuggestion: Sendable, Identifiable, Hashable, Codable {
    public var id: String { a + "|" + b }
    public var a: String
    public var b: String
    /// vorgeschlagener gemeinsamer Name (nil = Name von a behalten)
    public var name: String?
    /// kurzer Grund in einer Zeile
    public var reason: String

    public init(a: String, b: String, name: String?, reason: String) {
        self.a = a
        self.b = b
        self.name = name
        self.reason = reason
    }
}

/// Suchtreffer (§3.1): Gedanke + Ausschnitt mit Fundstellen.
public struct SearchHit: Sendable, Identifiable, Equatable {
    public enum Field: String, Sendable { case title, text, raw, task, topic }
    public var id: String { thoughtID }
    public var thoughtID: String
    public var field: Field
    /// kurzer Ausschnitt um den Treffer
    public var snippet: String
    /// Fundstellen im Ausschnitt (UTF-16-Bereiche, zum Hervorheben)
    public var ranges: [Range<Int>]
    public var score: Double

    public init(thoughtID: String, field: Field, snippet: String, ranges: [Range<Int>] = [], score: Double = 0) {
        self.thoughtID = thoughtID
        self.field = field
        self.snippet = snippet
        self.ranges = ranges
        self.score = score
    }
}

/// Für „Widerrufen“ (Löschen, Zusammenführen).
public struct UndoToken: Sendable, Hashable {
    public let id: String
    public init(id: String = UUID().uuidString) { self.id = id }
}

/// Verbrauch der letzten 24 h (Entwicklerbereich): Tokens und Audiosekunden laut Ledger.
public struct ThoughtsUsage: Sendable, Equatable {
    public var tokens: Int
    public var audioSeconds: Int
    public var requests: Int
    /// Tagesbudget (Tokens), gegen das gezählt wird
    public var dailyTokens: Int

    public init(tokens: Int, audioSeconds: Int, requests: Int, dailyTokens: Int) {
        self.tokens = tokens
        self.audioSeconds = audioSeconds
        self.requests = requests
        self.dailyTokens = dailyTokens
    }
}
