import ActivityKit
import Foundation

/// Live Activity eines Gedankens (KONZEPT §3.5). Eigener Typ – die Diktat-Activity bleibt unverändert.
/// Auf dem Sperrbildschirm erscheinen nie Titel oder Text, höchstens der Themenname.
struct ThoughtActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// `discarded`: in der Live Activity verworfen (liegt in „Zuletzt gelöscht“)
        enum Phase: String, Codable, Hashable, Sendable { case recording, processing, saved, waiting, empty, failed, discarded }
        var phase: Phase
        var startedAt: Date
        var topicTitle: String?
        /// Schlüssel des Themen-Symbols = `TopicIcon.rawValue` (z. B. "map-pin"); Darstellung über
        /// `TopicGlyph` (Lucide, Shared/UI) – die Widget-Erweiterung kennt PaplyKit nicht
        var topicSymbol: String?
        /// `wifi.slash` / `hourglass` / `key`
        var waitSymbol: String?
        var note: String?
        /// „Noch 5 Min.“ (Sicherheitsgrenze 10 Min.)
        var warnLimit: Bool
    }

    var thoughtID: String
}
