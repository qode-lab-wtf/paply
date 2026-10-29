import AppIntents
import SwiftUI
import WidgetKit

struct ConversationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "conversation-toggle", provider: ConversationControlValueProvider()) { on in
            ControlWidgetToggle("Gespräch", isOn: on, action: SetConversationRecordingIntent()) { _ in
                Label("Gespräch", systemImage: "person.2.wave.2")
            }.tint(.cyan)
        }
        .displayName("Paply-Gespräch")
        .description("Ein Druck nimmt auf, der nächste beendet das Gespräch.")
    }
}
struct ConversationControlValueProvider: ControlValueProvider {
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool {
        SharedStore.read(ConversationStateFile.self, .conversationState)?.recording ?? false
    }
}
