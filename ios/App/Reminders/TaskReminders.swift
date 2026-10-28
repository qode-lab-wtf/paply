// Erinnerung zur Uhrzeit: Aufgaben mit gesprochener Uhrzeit („morgen um 8 Briefe bearbeiten“) melden sich genau dann
// als Mitteilung – auf dem Sperrbildschirm mit „Erledigt“ und „In 1 Stunde“. Leitsatz: zuverlässig, kein Spam.
//
// - Welche Aufgaben, wann, Grenze 50, Abgleich alt → neu, „In 1 Stunde“: `TaskReminderPlan` (PaplyKit, getestet).
// - Abgleich: entprellt bei jeder Änderung der Aufgaben (ThoughtsModel), beim Start, im Vordergrund, nach neuer
//   Zeitzone und im BGTask. Nur Geändertes wird neu geplant. Erst wenn das Modell geladen ist – vorher wäre die Liste
//   leer und alles würde entfernt.
// - Der Stand „In 1 Stunde“ liegt in der geplanten Mitteilung selbst (userInfo), nicht in eigenen Dateien: Er gilt
//   damit auch, wenn die Aktion vor dem ersten Entsperren kam.
// - „Erledigt“ läuft im App-Prozess im Hintergrund: zuerst in eine kleine Warteschlange (ohne Dateischutz, nur
//   Kennungen), dann über dasselbe Modell abgehakt und gespeichert. Vor dem ersten Entsperren bleibt es in der
//   Warteschlange und wird danach angewendet. Idempotent.
// - Beta „Gedanken & Aufgaben“ aus (`AppSettings.betaThoughts`): nichts geplant, Geplantes und Zugestelltes entfernt,
//   „In 1 Stunde“ plant nicht neu. Umschalten gleicht sofort ab.
// - Erlaubnis: nie beim Start. Karte im Reiter „Aufgaben“ (`TaskReminderPromptSection`) oder Schalter in den
//   Einstellungen (`TaskReminderSettingsSection`).
import Foundation
import Observation
import PaplyKit
import UIKit
import UserNotifications
import WidgetKit

/// Schlüssel und Kennungen (ohne Akteur – auch der Delegate liest sie)
enum TaskReminderKeys {
    static let enabled = "paply.reminders.enabled"
    static let urgent = "paply.reminders.urgent"
    static let promptHiddenUntil = "paply.reminders.promptHiddenUntil"
    static let asked = "paply.reminders.asked"
    /// App-Group-Defaults: gilt auch für das Abhaken im Widget. Fehlt er, gilt „an“.
    static let requireAuth = TaskWidgetSettings.requireAuthKey

    static let category = "paply.task"
    static let doneAction = "paply.task.done"
    static let snoozeAction = "paply.task.snooze"

    // userInfo der Mitteilung
    static let stamp = "stamp"
    static let fireAt = "fireAt"
    static let dueAt = "dueAt"
    static let snoozed = "snoozed"
    static let thoughtID = "thoughtID"
    static let taskID = "taskID"
}

@MainActor
@Observable
final class TaskReminders {
    static let shared = TaskReminders()

    /// „Nicht jetzt“ blendet die Karte so lange aus
    static let promptPause: TimeInterval = 7 * 86_400

    /// Stand der Systemerlaubnis; nil = noch nicht gelesen
    private(set) var authorization: UNAuthorizationStatus?
    /// Schalter „Erinnerungen zur Uhrzeit“ (Standard an, wirkt erst mit Erlaubnis)
    private(set) var enabled = true
    /// Entwicklerbereich: „Erinnerungen dringlich“ (Zeitkritisch, bricht durch den Fokus)
    private(set) var urgent = false
    /// Entwicklerbereich: „Abhaken nur mit Face ID“
    private(set) var requireAuth = true
    private(set) var promptHiddenUntil: Date?
    /// Systemabfrage schon gezeigt
    private(set) var asked = false
    /// zuletzt geplant (Entwicklerbereich); nil = noch nicht abgeglichen
    private(set) var plannedCount: Int?

    @ObservationIgnored private let delegate = TaskReminderDelegate()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var settingsLoaded = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var reconcileAgain = false
    @ObservationIgnored private var nextReason = ""
    /// hält die App beim Abgleich nach dem Wechsel in den Hintergrund kurz wach
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    // MARK: Zustand

    var isAllowed: Bool {
        switch authorization {
        case .authorized?, .provisional?, .ephemeral?: true
        default: false
        }
    }

    var isDenied: Bool { authorization == .denied }

    /// Schalter in den Einstellungen: an = erlaubt und eingeschaltet
    var isOn: Bool { isAllowed && enabled }

    /// Karte „Bei Uhrzeit erinnern?“: noch nie gefragt, nicht für 7 Tage weggeklickt, und es gibt eine offene Aufgabe
    /// mit Uhrzeit in der Zukunft.
    func offersPrompt(thoughts: [Thought], now: Date = Date()) -> Bool {
        guard settingsLoaded, authorization == .notDetermined, !asked else { return false }
        if let until = promptHiddenUntil, now < until { return false }
        return TaskReminderPlan.hasUpcoming(thoughts: thoughts, now: now)
    }

    // MARK: Start

    /// Aus `didFinishLaunching`: Der Delegate muss vor Ende des Starts gesetzt sein, sonst gehen Aktionen verloren.
    /// Fragt nie nach der Erlaubnis.
    func start() {
        guard !started else { return }
        started = true
        UNUserNotificationCenter.current().delegate = delegate
        registerCategory() // vor dem Entsperren mit „an“ (sicherer Standard), danach mit dem gespeicherten Wert
        ProtectedData.whenReadable { [weak self] _ in self?.becameReadable() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TaskReminders.shared.foreground() }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TaskReminders.shared.background() }
        })
        for name in [UIApplication.significantTimeChangeNotification, Notification.Name.NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TaskReminders.shared.scheduleReconcile("time") }
            })
        }
        Task { await refreshAuthorization() }
        #if DEBUG
        TaskReminderDebug.start()
        #endif
    }

    private func becameReadable() {
        loadSettings()
        registerCategory()
        observeModel()
        modelChanged()
        Task { await moveLockedCompletions() }
    }

    private func foreground() {
        Task {
            await refreshAuthorization()
            guard ProtectedData.isReadable else { return }
            await moveLockedCompletions()
            scheduleReconcile("foreground", delay: .milliseconds(300))
        }
    }

    /// In den Hintergrund (z. B. kurz vor der Uhrzeit abgehakt und gleich gesperrt): sofort abgleichen statt nach der
    /// Entprellung – sonst käme die Erinnerung der eben erledigten Aufgabe womöglich noch. Hält die App dafür kurz wach.
    private func background() {
        debounce?.cancel()
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "paply.reminders") {
            MainActor.assumeIsolated { TaskReminders.shared.endBackgroundTask() }
        }
        let held = backgroundTask
        Task {
            await reconcileNow(reason: "background")
            if backgroundTask == held { endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: TaskReminderKeys.enabled) as? Bool ?? true
        urgent = defaults.bool(forKey: TaskReminderKeys.urgent)
        promptHiddenUntil = defaults.object(forKey: TaskReminderKeys.promptHiddenUntil) as? Date
        asked = defaults.bool(forKey: TaskReminderKeys.asked)
        requireAuth = TaskWidgetSettings.requiresAuth(AppGroup.defaults)
        settingsLoaded = true
    }

    /// Jede Änderung an Gedanken, Aufgaben oder Themen (auch das Laden) → entprellt abgleichen
    private func observeModel() {
        let model = ThoughtsModel.shared
        withObservationTracking {
            _ = model.isLoaded
            _ = model.thoughts
            _ = model.topics
        } onChange: {
            Task { @MainActor in
                TaskReminders.shared.modelChanged()
                TaskReminders.shared.observeModel()
            }
        }
    }

    private func modelChanged() {
        guard ThoughtsModel.shared.isLoaded else { return }
        scheduleReconcile("change")
    }

    // MARK: Erlaubnis und Schalter

    func refreshAuthorization() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if status != authorization { authorization = status }
    }

    /// Systemabfrage (Karte „Erinnern“ oder Schalter). Erlaubt → Schalter an, sofort planen.
    func requestAuthorization() async {
        asked = true
        UserDefaults.standard.set(true, forKey: TaskReminderKeys.asked)
        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            granted = false
        }
        Diag.log("reminders.permission", ["granted": .b(granted)])
        if granted { setStored(enabled: true) }
        await refreshAuthorization()
        await reconcileNow(reason: "permission")
    }

    /// Schalter „Erinnerungen zur Uhrzeit“. An ohne Erlaubnis → Systemabfrage; verweigert → nichts (Hinweis zeigt den Weg).
    func setEnabled(_ on: Bool) {
        if on, authorization == .notDetermined {
            Task { await requestAuthorization() }
            return
        }
        guard !isDenied else { return }
        setStored(enabled: on)
        scheduleReconcile("setting", delay: .zero)
    }

    private func setStored(enabled on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: TaskReminderKeys.enabled)
    }

    /// „Nicht jetzt“: Karte 7 Tage ausblenden
    func dismissPrompt(now: Date = Date()) {
        let until = now.addingTimeInterval(Self.promptPause)
        promptHiddenUntil = until
        UserDefaults.standard.set(until, forKey: TaskReminderKeys.promptHiddenUntil)
        Diag.log("reminders.prompt.later")
    }

    /// Entwicklerbereich: „Erinnerungen dringlich“ – geplante werden neu geplant (Stempel ändert sich)
    func setUrgent(_ on: Bool) {
        urgent = on
        UserDefaults.standard.set(on, forKey: TaskReminderKeys.urgent)
        scheduleReconcile("urgent", delay: .zero)
    }

    /// Entwicklerbereich: „Abhaken nur mit Face ID“ – Kategorie neu registrieren (gilt auch für schon zugestellte)
    func setRequireAuth(_ on: Bool) {
        requireAuth = on
        AppGroup.defaults?.set(on, forKey: TaskReminderKeys.requireAuth)
        registerCategory()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// „Erledigt“ (Face ID nach Schalter) und „In 1 Stunde“ (ohne – harmlos, ändert keine Daten)
    private func registerCategory() {
        let done = UNNotificationAction(identifier: TaskReminderKeys.doneAction, title: "Erledigt",
                                        options: requireAuth ? [.authenticationRequired] : [],
                                        icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let snooze = UNNotificationAction(identifier: TaskReminderKeys.snoozeAction, title: "In 1 Stunde", options: [],
                                          icon: UNNotificationActionIcon(systemImageName: "clock"))
        let category = UNNotificationCategory(identifier: TaskReminderKeys.category, actions: [done, snooze],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: Abgleich

    /// Entprellt: viele Änderungen kurz hintereinander (Ordnen, Abhaken) = ein Abgleich
    func scheduleReconcile(_ reason: String, delay: Duration = .seconds(1)) {
        debounce?.cancel()
        debounce = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.reconcileNow(reason: reason)
        }
    }

    /// Sofort abgleichen (BGTask, Erlaubnis). Nie zwei gleichzeitig: Läuft schon einer, folgt genau ein weiterer, und
    /// der Aufrufer wartet, bis auch der fertig ist.
    func reconcileNow(reason: String) async {
        nextReason = reason
        if let running {
            reconcileAgain = true
            await running.value
            return
        }
        let run = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.reconcileAgain = false
                await self.reconcileOnce(reason: self.nextReason)
            } while self.reconcileAgain
            self.running = nil // im selben Schritt wie die letzte Prüfung: kein Aufruf geht verloren
        }
        running = run
        await run.value
    }

    private func reconcileOnce(reason: String) async {
        // Vor dem ersten Entsperren oder vor dem Laden wäre die Liste leer: dann nichts anfassen
        guard ProtectedData.isReadable, settingsLoaded else { return }
        // Beta „Gedanken & Aufgaben“ aus: keine Erinnerungen – alles Geplante und Zugestellte weg (braucht die Gedanken
        // nicht, also auch vor dem Laden)
        AppSettings.shared.reloadIfNeeded()
        let beta = AppSettings.shared.betaThoughts
        let model = ThoughtsModel.shared
        guard model.isLoaded || !beta else { return }
        let center = UNUserNotificationCenter.current()
        await refreshAuthorization()
        let allowed = isAllowed && enabled && beta
        var current: [String: String] = [:]
        var snoozes: [String: TaskReminderPlan.Snooze] = [:]
        for request in await center.pendingNotificationRequests() where TaskReminderPlan.parse(request.identifier) != nil {
            let info = request.content.userInfo
            current[request.identifier] = info[TaskReminderKeys.stamp] as? String ?? ""
            if info[TaskReminderKeys.snoozed] as? Bool == true, let at = info[TaskReminderKeys.fireAt] as? Double,
               let due = info[TaskReminderKeys.dueAt] as? Double {
                snoozes[request.identifier] = TaskReminderPlan.Snooze(fireAt: Date(timeIntervalSince1970: at),
                                                                      dueAt: Date(timeIntervalSince1970: due))
            }
        }
        let now = Date()
        let thoughts = model.thoughts
        let desired = allowed
            ? TaskReminderPlan.reminders(thoughts: thoughts, topic: { model.topic($0.topicId) }, snoozes: snoozes, now: now)
            : []
        let changes = TaskReminderPlan.changes(current: current, desired: desired, salt: salt)
        if !changes.remove.isEmpty { center.removePendingNotificationRequests(withIdentifiers: changes.remove) }
        var failed = 0
        for reminder in changes.schedule {
            do {
                try await center.add(request(for: reminder))
            } catch {
                failed += 1
            }
        }
        // schon zugestellte von erledigten, gelöschten oder weggeworfenen Aufgaben (Beta aus: alle)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        let stale = TaskReminderPlan.removableDelivered(delivered, thoughts: thoughts, featureOn: beta)
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
        plannedCount = desired.count
        guard !changes.isEmpty || !stale.isEmpty || reason != "change" else { return }
        Diag.log("reminders.reconcile", [
            "reason": .s(reason), "allowed": .b(allowed), "beta": .b(beta), "planned": .i(desired.count), "added": .i(changes.schedule.count),
            "removed": .i(changes.remove.count), "unchanged": .i(changes.unchanged), "staleDelivered": .i(stale.count),
            "failed": .i(failed), "snoozed": .i(desired.filter(\.snoozed).count),
        ])
    }

    /// Was die App über `TaskReminder.signature` hinaus in die Mitteilung schreibt
    private var salt: String {
        "|" + (urgent ? "dringlich" : "normal") + "|" + TimeZone.current.identifier
    }

    func request(for reminder: TaskReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = reminder.threadID
        content.categoryIdentifier = TaskReminderKeys.category
        content.interruptionLevel = urgent ? .timeSensitive : .active
        content.targetContentIdentifier = reminder.id
        content.userInfo = [
            TaskReminderKeys.stamp: reminder.signature + salt,
            TaskReminderKeys.fireAt: reminder.fireAt.timeIntervalSince1970,
            TaskReminderKeys.dueAt: reminder.dueAt.timeIntervalSince1970,
            TaskReminderKeys.snoozed: reminder.snoozed,
            TaskReminderKeys.thoughtID: reminder.thoughtID,
            TaskReminderKeys.taskID: reminder.taskID,
        ]
        // Kalender-Auslöser mit fester Zeitzone: genau dieser Zeitpunkt (wie die Liste ihn zeigt)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireAt)
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }

    // MARK: Aktionen aus der Mitteilung

    /// Was der Delegate aus der Antwort liest (Sendable)
    struct Response: Sendable {
        let action: String
        let requestID: String
        let title: String
        let body: String
        let threadID: String
        let dueAt: Date?
    }

    func handle(_ response: Response) async {
        Diag.log("reminders.action", ["action": .s(Self.actionName(response.action)), "app": .s(SessionController.appState),
                                      "readable": .b(ProtectedData.isReadable)])
        guard let ids = TaskReminderPlan.parse(response.requestID) else { return } // Test-Mitteilung
        switch response.action {
        case TaskReminderKeys.doneAction:
            await complete(thoughtID: ids.thoughtID, taskID: ids.taskID, id: response.requestID)
        case TaskReminderKeys.snoozeAction:
            await snooze(response, thoughtID: ids.thoughtID, taskID: ids.taskID)
        case UNNotificationDefaultActionIdentifier:
            open(thoughtID: ids.thoughtID, taskID: ids.taskID)
        default:
            break // weggewischt
        }
    }

    private static func actionName(_ action: String) -> String {
        switch action {
        case TaskReminderKeys.doneAction: "done"
        case TaskReminderKeys.snoozeAction: "snooze"
        case UNNotificationDefaultActionIdentifier: "open"
        case UNNotificationDismissActionIdentifier: "dismiss"
        default: "other"
        }
    }

    /// „Erledigt“: erst in die Warteschlange (übersteht Beenden und Sperre), dann über dasselbe Modell abhaken und
    /// speichern. Warteschlange und Abarbeiten = dieselben wie beim Abhaken im Widget (`TaskWidgetFiles`,
    /// `TaskWidgetSync.applyQueue`: nacheinander, idempotent, neue Momentaufnahme fürs Widget). Die App Group ist erst
    /// nach dem ersten Entsperren schreibbar; davor (nur möglich, wenn „Abhaken nur mit Face ID“ aus ist) hält eine
    /// eigene kleine Datei den Tipp bis zum Entsperren.
    private func complete(thoughtID: String, taskID: String, id: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        let completion = TaskCompletion(thoughtID: thoughtID, taskID: taskID)
        ProtectedData.check() // lädt ggf. Aufgeschobenes (Modell)
        guard ProtectedData.isReadable, TaskWidgetFiles.enqueue(completion) else {
            LockedCompletions.add(completion)
            Diag.log("reminders.done.locked")
            return
        }
        // wie der Intent im Widget: Aufgabe sofort aus der Momentaufnahme, Widgets gleich neu laden
        if TaskWidgetFiles.applyOptimistically(completion) { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.tasks) }
        // wartet, bis die Gedanken gelesen sind (Kaltstart im Hintergrund); sonst übernimmt es der Start
        await TaskWidgetSync.shared.applyQueue(reason: "reminder", wait: .seconds(15))
        scheduleReconcile("done", delay: .milliseconds(200))
    }

    /// Vor dem ersten Entsperren Abgehaktes in die gemeinsame Warteschlange und anwenden
    private func moveLockedCompletions() async {
        let locked = LockedCompletions.load()
        guard !locked.isEmpty, ProtectedData.isReadable else { return }
        var moved = 0
        for completion in locked where TaskWidgetFiles.enqueue(completion) {
            LockedCompletions.remove(completion)
            moved += 1
        }
        Diag.log("reminders.done.unlocked", ["count": .i(moved)])
        guard moved > 0 else { return }
        await TaskWidgetSync.shared.applyQueue(reason: "reminder-unlock", wait: .seconds(15))
        scheduleReconcile("done", delay: .milliseconds(200))
    }

    /// „In 1 Stunde“: dieselbe Mitteilung (gleiche Kennung) eine Stunde später. Braucht keine Daten der App – geht also
    /// auch vor dem ersten Entsperren; der Abgleich liest den Stand aus der geplanten Mitteilung.
    private func snooze(_ response: Response, thoughtID: String, taskID: String) async {
        // Beta „Gedanken & Aufgaben“ aus: nichts neu planen (die Mitteilung kam vor dem Ausschalten)
        guard AppSettings.shared.betaThoughts else {
            Diag.log("reminders.snooze.skipped", ["why": .s("beta-off")])
            return
        }
        // Nur für eine offene Aufgabe – keine Mitteilung zu Erledigtem
        guard await taskStillOpen(thoughtID: thoughtID, taskID: taskID) else {
            Diag.log("reminders.snooze.skipped", ["why": .s("not-open"), "loaded": .b(ThoughtsModel.shared.isLoaded)])
            return
        }
        let now = Date()
        let reminder = TaskReminder(id: response.requestID, thoughtID: thoughtID, taskID: taskID,
                                    fireAt: TaskReminderPlan.snoozed(from: now), dueAt: response.dueAt ?? now, snoozed: true,
                                    title: response.title, body: response.body, threadID: response.threadID)
        do {
            try await UNUserNotificationCenter.current().add(request(for: reminder))
        } catch {
            Diag.log("reminders.snooze.failed", ["code": .i((error as NSError).code)])
        }
    }

    /// Ist die Aufgabe noch offen (`TaskReminderPlan.maySnooze`)? Kaltstart im Hintergrund: bis zu 5 s auf die Gedanken
    /// warten; sonst entscheiden Warteschlange und Momentaufnahme (im Zweifel nein).
    private func taskStillOpen(thoughtID: String, taskID: String) async -> Bool {
        ProtectedData.check() // lädt ggf. Aufgeschobenes (Modell)
        let model = ThoughtsModel.shared
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while ProtectedData.isReadable, !model.isLoaded, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let readable = ProtectedData.isReadable
        let matches = { (c: TaskCompletion) in c.thoughtID == thoughtID && c.taskID == taskID }
        let queued = LockedCompletions.load().contains(where: matches)
            || (readable && TaskWidgetFiles.pendingCompletions().contains(where: matches))
        let inSnapshot: Bool? = readable
            ? TaskWidgetFiles.readSnapshot().map { $0.items.contains { $0.thoughtID == thoughtID && $0.taskID == taskID } }
            : nil
        let facts = TaskReminderPlan.SnoozeFacts(thoughts: model.isLoaded ? model.thoughts : nil, queued: queued,
                                                 inSnapshot: inSnapshot, locked: !readable)
        return TaskReminderPlan.maySnooze(thoughtID: thoughtID, taskID: taskID, facts: facts)
    }

    /// Antippen: Gedanke an der Aufgabe öffnen – über denselben App-Link wie das Widget (RootView.onOpenURL)
    private func open(thoughtID: String, taskID: String) {
        guard let url = PaplyURL.task(thoughtID: thoughtID, taskID: taskID) else { return }
        Task {
            // Beim Kaltstart aus der Mitteilung ist die Szene evtl. noch nicht vorne
            let begin = Date()
            while UIApplication.shared.applicationState != .active, Date().timeIntervalSince(begin) < 5 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            let opened = await UIApplication.shared.open(url)
            Diag.log("reminders.open", ["ok": .b(opened), "app": .s(SessionController.appState)])
        }
    }
}

/// Mitteilungen im Vordergrund zeigen und Aktionen weiterreichen. Läuft auf beliebigen Threads: liest nur Werte aus und
/// gibt sie an den MainActor.
final class TaskReminderDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // auch bei offener App: Erinnerung ist Erinnerung
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let content = request.content
        let due = (content.userInfo[TaskReminderKeys.dueAt] as? Double).map { Date(timeIntervalSince1970: $0) }
        let value = TaskReminders.Response(action: response.actionIdentifier, requestID: request.identifier,
                                           title: content.title, body: content.body, threadID: content.threadIdentifier,
                                           dueAt: due)
        await TaskReminders.shared.handle(value)
    }
}

/// „Erledigt“ aus der Mitteilung vor dem ersten Entsperren nach einem Neustart: Dann ist weder die App Group noch die
/// Ablage schreibbar. Eine kleine Datei ohne Dateischutz (nur Kennungen, kein Text) hält es bis zum Entsperren; danach
/// wandert es in die gemeinsame Warteschlange (`TaskWidgetFiles`). Mit „Abhaken nur mit Face ID“ (Standard) kommt
/// es gar nicht dazu – Face ID setzt das Entsperren voraus.
@MainActor
enum LockedCompletions {
    /// Älteres verfällt (Aufgabe vermutlich längst anders erledigt)
    private static let maxAge: TimeInterval = 30 * 86_400

    private static let url: URL = ThoughtsEnvironment.root.deletingLastPathComponent()
        .appendingPathComponent("Erinnerungen", isDirectory: true)
        .appendingPathComponent("erledigt-gesperrt.json")

    static func load() -> [TaskCompletion] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([TaskCompletion].self, from: data) else { return [] }
        let limit = Date().addingTimeInterval(-maxAge)
        return entries.filter { $0.at > limit }
    }

    static func add(_ completion: TaskCompletion) {
        var entries = load()
        guard !entries.contains(where: { $0.thoughtID == completion.thoughtID && $0.taskID == completion.taskID }) else { return }
        entries.append(completion)
        save(entries)
    }

    static func remove(_ completion: TaskCompletion) {
        let rest = load().filter { $0.id != completion.id }
        if rest.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            save(rest)
        }
    }

    private static func save(_ entries: [TaskCompletion]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.none])
            try JSONEncoder().encode(entries).write(to: url, options: [.atomic, .noFileProtection])
        } catch {
            Diag.log("reminders.queue.failed", ["code": .i((error as NSError).code)])
        }
    }
}
