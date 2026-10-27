// Besitzer: H2. Verdrahtung von ThoughtStore, ThoughtProcessor, Ledger und KI für die App (KONZEPT §9.1).
//
// - Ablage: `Library/Application Support/Gedanken` (gleicher Ort wie der S1-Rückfall, der so übernommen wird).
// - Auslöser der Warteschlange (§6.8): App-Start (`recover()`), Vordergrund, Netz zurück, Schlüssel geändert,
//   `retryAt` (Timer im Prozessor), Aufnahme beendet (ThoughtCapture), BGProcessingTask `com.paply.ios.thoughts`.
// - Diktat hat Vorrang: `isDictationBusy` = Diktat nimmt auf oder wird poliert (SessionController).
// - Während verarbeitet wird, hält `beginBackgroundTask` die App bis zu ≈ 30 s wach.
// - Vor dem ersten Entsperren nach einem Neustart (Fall B, BGTask) ist die Ablage nicht lesbar: Laden,
//   Reparieren, Aufräumen und Anstoßen warten dann auf das Entsperren (ProtectedData).
import BackgroundTasks
import Foundation
import Network
import Observation
import PaplyKit
import UIKit

@MainActor
enum ThoughtsEnvironment {
    static let backgroundTaskID = "com.paply.ios.thoughts"
    /// Entwicklerbereich (ThoughtsDevKeys in der Oberfläche)
    nonisolated static let modelKey = "paply.thoughts.model"
    nonisolated static let dailyTokensKey = "paply.thoughts.dailyTokens"

    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Gedanken", isDirectory: true)
    }()

    static let store: ThoughtStore = {
        do {
            return try ThoughtStore(root: root)
        } catch {
            preconditionFailure("Gedanken-Ablage ohne Dateipfad")
        }
    }()

    static let ledger = TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: { limits() })

    static let finder = CandidateFinder(store: store)

    static let processor = ThoughtProcessor(store: store, structurer: ThoughtStructurer(ledger: ledger), finder: finder,
                                            ledger: ledger, environment: processorEnvironment)

    static var backend: ThoughtsBackend {
        ThoughtsBackend(store: store, processor: processor, ledger: ledger, dailyTokens: { limits().dailyTokens })
    }

    /// Tagesbudget aus dem Entwicklerbereich (Standard 80 000)
    nonisolated static func limits() -> TokenLedger.Limits {
        var limits = TokenLedger.Limits()
        let daily = UserDefaults.standard.integer(forKey: dailyTokensKey)
        if daily > 0 { limits.dailyTokens = daily }
        return limits
    }

    /// Diktat nimmt auf oder wird poliert (Mac `isBusy`)
    static func isDictationBusy() -> Bool {
        SessionController.shared.active != nil || SessionController.shared.processingCount > 0
    }

    private static var processorEnvironment: ProcessorEnvironment {
        ProcessorEnvironment(
            apiKey: { await MainActor.run { AppSettings.shared.apiKey } },
            isOnline: { ThoughtsNetwork.shared.isOnline },
            isDictationBusy: { await MainActor.run { isDictationBusy() } },
            settings: { await MainActor.run { AppSettings.shared.effectivePaply } },
            uiLanguage: Locale.preferredLanguages.first.flatMap { $0.components(separatedBy: "-").first } ?? "de")
    }

    // MARK: Start

    private static var bootstrapped = false
    private static var observers: [NSObjectProtocol] = []
    private static var assertion: UIBackgroundTaskIdentifier = .invalid
    private static var eventsTask: Task<Void, Never>?
    /// Ablage gelesen, repariert, aufgeräumt. nil = noch nicht lesbar (vor dem ersten Entsperren);
    /// Anstoßen und Planen warten auf diese Aufgabe.
    private static var storageReady: Task<Void, Never>?

    /// Aus `application(_:didFinishLaunchingWithOptions:)` (BGTask muss vor Ende des Starts registriert sein).
    static func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        registerBackgroundTask()
        ThoughtBridge.connect(store: store, processor: processor)
        ThoughtsNetwork.shared.onReconnect = { Task { @MainActor in kick("network") } }
        ThoughtsNetwork.shared.start()
        observeKey()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in kick("foreground") }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await scheduleBackgroundProcessing() }
        })
        eventsTask = Task {
            for await event in processor.events {
                switch event {
                case .processing:
                    holdWhileProcessing()
                case .waiting:
                    // Fall B: Die App war nie vorne (kein didEnterBackground) – sonst plant niemand
                    Task { await scheduleBackgroundProcessing() }
                default:
                    break
                }
            }
        }
        ProtectedData.whenReadable { deferred in startStorage(deferred: deferred) }
    }

    /// Einmal, sobald die Ablage lesbar ist: beim Start sofort, nach einem Neustart erst nach dem Entsperren.
    private static func startStorage(deferred: Bool) {
        guard storageReady == nil else { return }
        storageReady = Task {
            // Was vor dem Entsperren schon angefasst wurde, nachladen (meldet es über `changes`)
            if deferred { await store.reloadIfNeeded() }
            let repaired = (try? await store.recover()) ?? []
            await store.housekeeping(now: Date())
            Diag.log("thoughts.start", ["repaired": .i(repaired.count), "afterUnlock": .b(deferred)])
        }
        kick(deferred ? "unlock" : "launch")
        _ = ThoughtsModel.shared // lädt im Hintergrund
    }

    static func kick(_ reason: String) {
        guard let ready = storageReady else {
            // Vielleicht inzwischen entsperrt: dann startet die Ablage und stößt selbst an
            ProtectedData.check()
            return
        }
        Task {
            await ready.value
            await processor.kick(reason: reason)
        }
    }

    /// Neuer bzw. geänderter Groq-Schlüssel: Wartende sofort versuchen.
    private static func observeKey() {
        withObservationTracking {
            _ = AppSettings.shared.apiKeySuffix
            _ = AppSettings.shared.hasAPIKey
        } onChange: {
            Task { @MainActor in
                kick("key")
                observeKey()
            }
        }
    }

    /// Nach dem Stopp ohne Sitzung: Verarbeitung bis zu ≈ 30 s im Hintergrund fortsetzen (R6).
    private static func holdWhileProcessing() {
        guard assertion == .invalid else { return }
        assertion = UIApplication.shared.beginBackgroundTask(withName: "thought-processing") {
            // Synchron im Handler beenden – sonst beendet iOS die App. Der Abbruch läuft danach.
            Task { await processor.cancelRunning() }
            endAssertion()
        }
        let held = assertion
        Task {
            await processor.waitUntilIdle()
            if assertion == held { endAssertion() } // nicht eine spätere, neue beenden
        }
    }

    private static func endAssertion() {
        guard assertion != .invalid else { return }
        UIApplication.shared.endBackgroundTask(assertion)
        assertion = .invalid
    }

    // MARK: BGProcessingTask

    /// Der Start-Block läuft auf der Hauptschlange (Swift-6-Isolationsprüfung: kein MainActor-Block auf fremder Queue).
    private static func registerBackgroundTask() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: .main) { task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = BackgroundTaskBox(task)
            Task { @MainActor in runBackgroundTask(box) }
        }
        Diag.log("thoughts.bgtask.register", ["ok": .b(registered)])
    }

    private static func runBackgroundTask(_ box: BackgroundTaskBox) {
        ProtectedData.check()
        guard let ready = storageReady else {
            // Vor dem ersten Entsperren: nichts lesbar. Nach dem Entsperren stößt der Start selbst an.
            Diag.log("thoughts.bgtask.run", ["locked": .b(true)])
            box.complete(success: false)
            return
        }
        Diag.log("thoughts.bgtask.run")
        let work = Task { @MainActor in
            await ready.value
            await processor.kick(reason: "background")
            await processor.waitUntilIdle()
            await store.housekeeping(now: Date())
            box.complete(success: !Task.isCancelled)
            await scheduleBackgroundProcessing()
        }
        let queue = ThoughtsEnvironment.processor
        box.onExpiration { // ruft das System auf beliebiger Queue: bewusst ohne MainActor
            work.cancel()
            Task { await queue.cancelRunning() }
            box.complete(success: false)
        }
    }

    /// Geplant, sobald etwas wartet (Netz nötig); frühestens zum nächsten `retryAt`.
    static func scheduleBackgroundProcessing() async {
        guard let ready = storageReady else { return } // vor dem Entsperren unbekannt
        await ready.value
        guard await processor.hasPendingWork() else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskID)
            return
        }
        let request = BGProcessingTaskRequest(identifier: backgroundTaskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = await processor.nextRetryDate()
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Diag.log("thoughts.bgtask.submit.failed", ["code": .i((error as NSError).code)])
        }
    }
}

/// BGTask über Isolationsgrenzen reichen; abgeschlossen wird genau einmal.
private final class BackgroundTaskBox: @unchecked Sendable {
    private let task: BGProcessingTask
    private let lock = NSLock()
    private var done = false

    init(_ task: BGProcessingTask) { self.task = task }

    func onExpiration(_ handler: @escaping @Sendable () -> Void) {
        task.expirationHandler = handler
    }

    func complete(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        task.setTaskCompleted(success: success)
    }
}

/// Netzstatus für die Warteschlange; meldet, wenn das Netz zurückkommt.
final class ThoughtsNetwork: @unchecked Sendable {
    static let shared = ThoughtsNetwork()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true
    private var started = false
    var onReconnect: (@Sendable () -> Void)?

    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return online
    }

    func start() {
        lock.lock()
        guard !started else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let now = path.status == .satisfied
            self.lock.lock()
            let was = self.online
            self.online = now
            let callback = self.onReconnect
            self.lock.unlock()
            if now, !was { callback?() }
        }
        monitor.start(queue: DispatchQueue(label: "paply.thoughts.network", qos: .utility))
    }
}
