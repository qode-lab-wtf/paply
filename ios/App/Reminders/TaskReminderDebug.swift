#if DEBUG
import Foundation
import PaplyKit
import UserNotifications

// Nur im Debug: Test-Mitteilung der Erinnerung zur Uhrzeit (Simulator, Bildschirmfotos).
//   -PaplyReminderTest [s]   nach s Sekunden (Standard 8) eine Erinnerung mit Beispieltext – gleicher Aufbau wie
//                            echte (Kategorie, Aktionen, Thema als Gruppe). Fragt vorher nach der Erlaubnis, falls nötig.
// Die Kennung beginnt mit „test/“: Der Abgleich lässt sie stehen, „Erledigt“ ändert keine Daten.
@MainActor
enum TaskReminderDebug {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    static func start() {
        guard let i = args.firstIndex(of: "-PaplyReminderTest") else { return }
        let seconds = (i + 1 < args.count ? Double(args[i + 1]) : nil) ?? 8
        Task {
            try? await Task.sleep(for: .seconds(1))
            await TaskReminders.shared.refreshAuthorization()
            if TaskReminders.shared.authorization == .notDetermined {
                await TaskReminders.shared.requestAuthorization()
            }
            scheduleTest(after: max(2, seconds - 1))
        }
    }

    static func scheduleTest(after seconds: TimeInterval) {
        let now = Date()
        let fireAt = Date(timeIntervalSince1970: (now.timeIntervalSince1970 + seconds).rounded(.up))
        let reminder = TaskReminder(id: "test/" + ThoughtIDs.thought(), thoughtID: "s_test", taskID: "k_test", fireAt: fireAt,
                                    dueAt: fireAt, snoozed: false, title: "Briefe bei Aram bearbeiten",
                                    body: "Arbeit · Post von Aram", threadID: "paply.topic.test")
        let request = TaskReminders.shared.request(for: reminder)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                Diag.log("reminders.test", ["seconds": .d(seconds)])
            } catch {
                Diag.log("reminders.test.failed", ["code": .i((error as NSError).code)])
            }
        }
    }
}
#endif
