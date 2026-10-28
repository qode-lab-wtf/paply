import AppIntents
import Foundation
import UserNotifications
import WidgetKit

// Abhaken im Aufgaben-Widget (Home-Bildschirm, StandBy). Liegt in App und Widget-Erweiterung.
//
// Ablauf (`TaskIntentRunner`):
// 1. Erledigung als eigene Datei in die Warteschlange der App Group (`task-completions/`) – dauerhaft, bevor irgendetwas
//    anderes passiert.
// 2. Momentaufnahme sofort optimistisch anpassen: Aufgabe raus, Zahl eins weniger, Ring eins weiter.
// 3. App wendet die Warteschlange an. `LiveActivityIntent` lässt `perform()` im App-Prozess laufen (iOS startet die App
//    dafür im Hintergrund, wie beim Gedanken-Widget) – dann sofort, samt Speichern und neuer Momentaufnahme. Landet es
//    doch in der Erweiterung, weckt ein Darwin-Signal die laufende App; sonst wendet sie beim nächsten Start, im
//    Vordergrund oder im BGTask an (`TaskWidgetSync`).
// 4. Die Erinnerung zur Uhrzeit der Aufgabe (`task/<Gedanke>/<Aufgabe>`) wird entfernt, geplant wie zugestellt.
// Ein zweiter Tipp auf dieselbe Aufgabe hat keine Wirkung (sie steht nicht mehr in der Momentaufnahme; die App hakt sie
// höchstens einmal ab). Widerrufen gibt es im Widget nicht – dafür ist die App da.
//
// Gesperrtes Gerät: Die Freigabe ist statisch (App-Intents-Metadaten werden beim Bauen gelesen), deshalb zwei
// Fassungen. Standard ist `CompleteTaskIntent` (nur entsperrt, Face ID): Home-Widgets erscheinen auch in StandBy auf
// dem gesperrten Gerät – ohne Freigabe könnte jeder am Nachttisch Aufgaben abhaken. Abhaken ändert Daten des Nutzers;
// Lesen bleibt über `.privacySensitive()` geregelt. Wer das nicht will, schaltet im Entwicklerbereich „Abhaken nur mit
// Face ID“ aus (`TaskWidgetSettings.requireAuthKey`) – dann nimmt das Widget `CompleteTaskQuickIntent`.

/// Aufgabe im Widget abhaken – nur entsperrt (Standard).
struct CompleteTaskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Aufgabe abhaken" }
    static var description: IntentDescription { IntentDescription("Hakt eine Aufgabe aus dem Paply-Widget ab.") }
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Gedanke")
    var thoughtID: String

    @Parameter(title: "Aufgabe")
    var taskID: String

    init() {}

    init(thoughtID: String, taskID: String) {
        self.thoughtID = thoughtID
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        await TaskIntentRunner.complete(thoughtID: thoughtID, taskID: taskID, intent: "complete")
        return .result()
    }
}

/// Dasselbe ohne Entsperren (Schalter „Abhaken nur mit Face ID“ aus).
struct CompleteTaskQuickIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Aufgabe abhaken (ohne Entsperren)" }
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    @Parameter(title: "Gedanke")
    var thoughtID: String

    @Parameter(title: "Aufgabe")
    var taskID: String

    init() {}

    init(thoughtID: String, taskID: String) {
        self.thoughtID = thoughtID
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        await TaskIntentRunner.complete(thoughtID: thoughtID, taskID: taskID, intent: "quick")
        return .result()
    }
}

/// Gemeinsamer Ablauf beider Intents – protokolliert den Prozess (nie den Text der Aufgabe).
enum TaskIntentRunner {
    static func complete(thoughtID: String, taskID: String, intent: String) async {
        let completion = TaskCompletion(thoughtID: thoughtID, taskID: taskID)
        let queued = TaskWidgetFiles.enqueue(completion)
        // Ohne Eintrag in der Warteschlange nichts vorgaukeln: Die Aufgabe bliebe sonst nur scheinbar erledigt.
        let optimistic = queued && TaskWidgetFiles.applyOptimistically(completion)
        Diag.log("tasks.intent", [
            "intent": .s(intent),
            "process": .s(PaplyProcess.current.rawValue),
            "queued": .b(queued),
            "optimistic": .b(optimistic),
        ])
        guard queued else { return }
        // Erinnerung zur Uhrzeit dieser Aufgabe (geplant, verschoben oder schon zugestellt) gleich mit entfernen – geht
        // in der Erweiterung wie in der App. Der Abgleich der App käme sonst erst nach dem Anwenden.
        let reminderID = TaskReminderID.identifier(thoughtID: thoughtID, taskID: taskID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        center.removeDeliveredNotifications(withIdentifiers: [reminderID])
        #if PAPLY_APP
        // Widget gleich mit der angepassten Momentaufnahme zeigen, dann echt anwenden (wartet notfalls, bis die
        // Gedanken nach einem Kaltstart gelesen sind)
        if optimistic { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.tasks) }
        await TaskWidgetSync.shared.applyQueue(reason: "intent", wait: .seconds(8))
        #else
        DarwinBus.shared.post(.taskCompleted)
        #endif
    }
}
