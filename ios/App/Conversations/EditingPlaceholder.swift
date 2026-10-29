import Foundation
import PaplyKit

/// PLATZHALTER: beim Zusammenführen durch die Kern-Implementierung ersetzen.
struct EditingPlaceholder: ConversationEditing {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Sprecher bearbeiten ist noch nicht verfügbar." }
    }
    func nameSpeaker(_ conversationID: String, speakerID: String, as identity: SpeakerIdentity, rememberVoice: Bool)
        async throws
    { throw Unavailable() }
    func rejectSuggestion(_ conversationID: String, speakerID: String) async throws { throw Unavailable() }
    func mergeSpeakers(_ conversationID: String, from: String, into: String) async throws { throw Unavailable() }
    func reassignUtterance(_ conversationID: String, utteranceID: String, to speakerID: String) async throws {
        throw Unavailable()
    }
    func rename(_ conversationID: String, title: String) async throws { throw Unavailable() }
}
