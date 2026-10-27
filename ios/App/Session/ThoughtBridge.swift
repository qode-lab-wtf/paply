import Foundation
import PaplyKit

// Verbindung Intents/Control/Live Activity ↔ ThoughtCapture (KONZEPT §3.5, §3.6, §5). Besitzer: H3.
@MainActor
enum ThoughtBridge {
    static func toggle(trigger: ThoughtTrigger) async -> ThoughtToggleOutcome {
        await ThoughtCapture.shared.toggle(trigger: trigger)
    }

    /// „Fertig“ in der Live Activity
    static func finishFromActivity(id: String) async {
        if ThoughtCapture.shared.active?.id == id { ThoughtCapture.shared.finish(.liveActivity) }
    }

    /// Fall B gescheitert: App ist jetzt vorne
    static func startInForeground(trigger: ThoughtTrigger) async {
        _ = await ThoughtCapture.shared.toggle(trigger: trigger)
    }
}
