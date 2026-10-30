import ActivityKit
import Foundation

/// Live Activity – nur während eines Schnelltasten-Diktats (nie im Leerlauf).
struct DictationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case recording
            case polishing
            case done
            case failed
        }

        var phase: Phase
        var startedAt: Date
        /// kurzer Hinweis, z. B. „In der Zwischenablage“
        var note: String?
    }

    var dictationID: String
}
