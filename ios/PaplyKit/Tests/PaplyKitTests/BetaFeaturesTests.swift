import Foundation
import Testing
@testable import PaplyKit

// Beta „Gedanken & Aufgaben“: `BetaFeatures` aus Shared/Core (über den Verweis `Shared/BetaFeatures.swift` mitübersetzt,
// damit genau die Datei geprüft wird, die App, Tastatur und Widgets benutzen) und die Kennung der Erinnerung, die das
// Aufgaben-Widget beim Abhaken entfernt (`TaskReminderID` aus Shared/Core/TaskSnapshot.swift).

@Suite("Beta Gedanken & Aufgaben")
struct BetaFeaturesTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "paply.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func defaultsToOn() {
        #expect(BetaFeatures.thoughtsKey == "paply.beta.thoughts")
        // ohne App Group (Tastatur ohne Vollzugriff) und ohne gespeicherten Wert: an
        #expect(BetaFeatures.thoughtsEnabled(nil))
        withDefaults { defaults in
            #expect(BetaFeatures.thoughtsEnabled(defaults))
            defaults.set(false, forKey: BetaFeatures.thoughtsKey)
            #expect(!BetaFeatures.thoughtsEnabled(defaults))
            defaults.set(true, forKey: BetaFeatures.thoughtsKey)
            #expect(BetaFeatures.thoughtsEnabled(defaults))
            // fremder Typ unter dem Schlüssel: Standard
            defaults.set("aus", forKey: BetaFeatures.thoughtsKey)
            #expect(BetaFeatures.thoughtsEnabled(defaults))
        }
    }

    @Test func launchArgumentShowsOffWithoutSaving() {
        withDefaults { defaults in
            #expect(BetaFeatures.thoughtsAtLaunch(defaults, arguments: ["Paply"]))
            #if DEBUG
            #expect(!BetaFeatures.thoughtsAtLaunch(defaults, arguments: ["Paply", "-PaplyBetaOff"]))
            #expect(BetaFeatures.thoughtsOffArgument == "-PaplyBetaOff")
            #endif
            // nichts gespeichert: Widgets und Tastatur lesen weiter „an“
            #expect(defaults.object(forKey: BetaFeatures.thoughtsKey) == nil)
            defaults.set(false, forKey: BetaFeatures.thoughtsKey)
            #expect(!BetaFeatures.thoughtsAtLaunch(defaults, arguments: ["Paply"]))
        }
    }

    @Test func widgetUsesTheSameReminderIdentifierAsTheApp() {
        for (thought, task) in [("s_1", "k_1"), ("s_8F2A", "k_x-y"), ("s_a b", "k_ü")] {
            let id = TaskReminderID.identifier(thoughtID: thought, taskID: task)
            #expect(id == TaskReminderPlan.identifier(thoughtID: thought, taskID: task))
            let parsed = TaskReminderPlan.parse(id)
            #expect(parsed?.thoughtID == thought)
            #expect(parsed?.taskID == task)
        }
    }
}
