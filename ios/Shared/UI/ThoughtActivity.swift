import ActivityKit
import Foundation

/// Live Activity eines Gedankens (KONZEPT §3.5). Eigener Typ – die Diktat-Activity bleibt unverändert.
/// Auf dem Sperrbildschirm erscheinen nie Titel oder Text, höchstens der Themenname.
struct ThoughtActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable { case recording, processing, saved, waiting, empty, failed }
        var phase: Phase
        var startedAt: Date
        var topicTitle: String?
        /// SF-Symbol des Themas
        var topicSymbol: String?
        /// `wifi.slash` / `hourglass` / `key`
        var waitSymbol: String?
        var note: String?
        /// „Noch 5 Min.“ (Sicherheitsgrenze 30 Min.)
        var warnLimit: Bool
    }

    var thoughtID: String
}
