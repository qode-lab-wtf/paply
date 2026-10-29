import BackgroundTasks
import UIKit

/// Lebensdauer der Auswertung. Der Audiostrom bleibt als Rückfall bereit, speichert aber nichts.
/// Eine inaktive Audiositzung allein garantiert unter iOS keine Hintergrundlaufzeit.
@MainActor
final class ConversationBackground {
    static let shared = ConversationBackground()
    static let identifier = "com.paply.ios.conversations"
    private var ids: Set<String> = []
    private var tasks: [String: BGTask] = [:]
    private var registered = false
    private var assertion: UIBackgroundTaskIdentifier = .invalid
    var isRunning: Bool { !ids.isEmpty }
    /// Warteschlange muss bei Ablauf abbrechen und ihren Stand sichern.
    var onExpiration: ((String) -> Void)?
    /// Nachzügler startet die persistierte Warteschlange und kehrt erst nach ihrem Ende zurück.
    var resumePending: (() async -> Void)?

    func bootstrap() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            Task { @MainActor in
                let work = Task { @MainActor in
                    await self.resumePending?()
                    task.setTaskCompleted(success: !Task.isCancelled)
                }
                task.expirationHandler = {
                    work.cancel()
                    Task { @MainActor in self.onExpiration?("") }
                }
            }
        }
    }

    func begin(id: String) {
        bootstrap()
        guard ids.insert(id).inserted else { return }
        if assertion == .invalid {
            assertion = UIApplication.shared.beginBackgroundTask(withName: "Gespräch auswerten") {
                Task { @MainActor in
                    for id in self.ids { self.onExpiration?(id) }
                    self.schedule()
                    self.endAssertion()
                }
            }
        }
        if #available(iOS 26.0, *) {
            let key = Self.identifier + ".continued." + id
            BGTaskScheduler.shared.register(forTaskWithIdentifier: key, using: .main) { task in
                Task { @MainActor in
                    guard self.ids.contains(id) else { task.setTaskCompleted(success: true); return }
                    self.tasks[id] = task
                    await SessionController.shared.pauseConversationProcessingInput()
                    if let continued = task as? BGContinuedProcessingTask {
                        continued.progress.totalUnitCount = 1000
                    }
                    task.expirationHandler = { Task { @MainActor in
                        self.onExpiration?(id)
                        self.end(id: id, success: false)
                        self.schedule()
                    } }
                }
            }
            let request = BGContinuedProcessingTaskRequest(identifier: key, title: "Gespräch auswerten", subtitle: "Paply ordnet deine Aufnahme")
            request.strategy = .fail
            do { try BGTaskScheduler.shared.submit(request) } catch { schedule() }
        } else { schedule() }
    }

    func progress(id: String, fraction: Double) {
        if #available(iOS 26.0, *), let task = tasks[id] as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = Int64(min(1, max(0, fraction)) * 1000)
        }
    }

    func end(id: String, success: Bool = true) {
        ids.remove(id)
        tasks.removeValue(forKey: id)?.setTaskCompleted(success: success)
        if ids.isEmpty {
            endAssertion()
            SessionController.shared.conversationWorkEnded()
        }
    }

    private func endAssertion() {
        if assertion != .invalid { UIApplication.shared.endBackgroundTask(assertion); assertion = .invalid }
    }
    func schedule() {
        let request = BGProcessingTaskRequest(identifier: Self.identifier)
        request.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(request)
    }
}
