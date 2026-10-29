import Foundation
import Observation
import PaplyKit

@MainActor
enum ConversationLearning {
    private static let gate = ConversationLearningGate(directory: ConversationsEnvironment.profiles.learningDirectory)
    static func refresh() async {
        let allowed = ConversationsEnvironment.voiceLearningAllowed
        gate.configure(enabled: allowed)
        await ThoughtsEnvironment.store.setAudioReleaseHook(allowed ? gate.hook(ConversationsEnvironment.profiles.learningHook()) : nil)
    }
    static func observe() {
        withObservationTracking {
            _ = AppSettings.shared.betaConversations
        } onChange: {
            Task { @MainActor in
                await refresh()
                observe()
            }
        }
    }
}
