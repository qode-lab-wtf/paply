import AppIntents
import Foundation

struct ToggleConversationIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Paply-Gespräch an/aus" }
    func perform() async throws -> some IntentResult {
        #if PAPLY_APP
        guard await AppSettings.shared.betaConversations else {
            throw ThoughtIntentError.refused("Aktiviere Gespräche in den Beta-Einstellungen.")
        }
        if !(await ConversationCapture.shared.toggle(trigger: .shortcut)) {
            try await requestToContinueInForeground("Paply öffnet kurz das Mikro.") {
                _ = await ConversationCapture.shared.toggle(trigger: .shortcut)
            }
        }
        #else
        try await ConversationIntentForward.toggle()
        #endif
        return .result()
    }
}
struct SetConversationRecordingIntent: SetValueIntent, AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource { "Paply-Gespräch" }
    @Parameter(title: "Aufnahme") var value: Bool
    init() {}
    func perform() async throws -> some IntentResult {
        #if PAPLY_APP
        guard await AppSettings.shared.betaConversations else {
            throw ThoughtIntentError.refused("Aktiviere Gespräche in den Beta-Einstellungen.")
        }
        if !(await ConversationCapture.shared.toggle(trigger: .control)) {
            try await requestToContinueInForeground("Paply öffnet kurz das Mikro.") {
                _ = await ConversationCapture.shared.toggle(trigger: .control)
            }
        }
        #else
        try await ConversationIntentForward.toggle()
        #endif
        return .result()
    }
}
struct FinishConversationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Gespräch fertig" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Gespräch") var conversationID: String
    init() {}
    init(id: String) { conversationID = id }
    func perform() async throws -> some IntentResult {
        #if PAPLY_APP
        await MainActor.run {
            if ConversationCapture.shared.active?.id == conversationID { ConversationCapture.shared.finish() }
        }
        #else
        ConversationIntentForward.send(id: conversationID)
        #endif
        return .result()
    }
}
#if PAPLY_APP
extension ToggleConversationIntent: ForegroundContinuableIntent {}
extension SetConversationRecordingIntent: ForegroundContinuableIntent {}
#endif

enum ConversationIntentForward {
    static func send(id: String? = nil) {
        SharedStore.write(ConversationCommand(sequence: UUID(), finishID: id), .conversationCommand)
        DarwinBus.shared.post(.conversationToggle)
    }
    static func toggle() async throws {
        guard BetaFeatures.conversationsEnabled(AppGroup.defaults) else {
            throw ThoughtIntentError.refused("Aktiviere Gespräche in den Beta-Einstellungen.")
        }
        let before = SharedStore.read(ConversationStateFile.self, .conversationState)?.recording ?? false
        send()
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            if (SharedStore.read(ConversationStateFile.self, .conversationState)?.recording ?? false) != before { return }
        }
        throw ThoughtIntentError.refused("Öffne Paply einmal, dann klappt der Knopf.")
    }
}

struct PauseConversationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Gespräch pausieren oder fortsetzen" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Gespräch") var conversationID: String
    @Parameter(title: "Pause") var paused: Bool
    init() {}
    init(id: String, paused: Bool) { conversationID = id; self.paused = paused }
    func perform() async throws -> some IntentResult {
        #if PAPLY_APP
        await MainActor.run {
            if ConversationCapture.shared.active?.id == conversationID { ConversationCapture.shared.setPaused(paused) }
        }
        #else
        SharedStore.write(ConversationCommand(sequence: UUID(), finishID: conversationID, paused: paused), .conversationCommand)
        DarwinBus.shared.post(.conversationToggle)
        #endif
        return .result()
    }
}
