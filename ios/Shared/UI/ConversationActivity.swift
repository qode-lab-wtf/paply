import ActivityKit
import Foundation

struct ConversationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable { case recording, paused, processing, done, waiting, failed }
        var phase: Phase
        var startedAt: Date
        var elapsed: Double = 0
        var pausedAt: Date?
        var stage: String?
        var note: String?
        var caption: String {
            if let note { return note }
            switch phase {
            case .recording: return "Gespräch"
            case .paused: return pausedAt.map { "Pausiert seit " + $0.formatted(date: .omitted, time: .shortened) } ?? "Pausiert"
            case .processing: return stage ?? "Wird ausgewertet …"
            case .done: return "Fertig"
            case .waiting: return "Gesichert – geht später weiter"
            case .failed: return "Gesichert – bitte Paply öffnen"
            }
        }
    }
    var conversationID: String
}

struct ConversationStateFile: Codable, Sendable {
    var recording: Bool
    var id: String?
}
struct ConversationCommand: Codable, Sendable {
    var sequence: UUID
    var finishID: String?
    var paused: Bool? = nil
}
