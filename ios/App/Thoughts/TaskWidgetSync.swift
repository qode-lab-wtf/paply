import Foundation
import Observation
import PaplyKit
import SwiftUI
import UIKit
import WidgetKit

/// Aufgaben-Widgets (Sperrbildschirm, Home) ↔ Gedanken der App.
///
/// - Momentaufnahme: Bei jeder Änderung der Gedanken oder Themen (entprellt 0,5 s) baut die App `tasks-snapshot.json`
///   (`TaskDigest` → `TaskSnapshot`) und lädt das Widget neu – nur wenn sich der Inhalt geändert hat (kein Spam), und
///   erst, wenn die Gedanken gelesen sind (sonst stünde kurz „Alles erledigt“ da).
/// - Vor dem ersten Entsperren nach einem Neustart schreibt sie nichts (`ProtectedData`).
/// - Warteschlange der im Widget abgehakten Aufgaben: angewandt sofort (Intent im App-Prozess, Darwin-Signal aus der
///   Erweiterung), nach dem Laden beim Start, im Vordergrund und im BGTask. Erst abhaken und speichern, dann die neue
///   Momentaufnahme schreiben, dann die Einträge löschen – so zeigt das Widget nie kurz wieder die alte Aufgabe.
/// - Schalter „Abhaken nur mit Face ID“ (`TaskWidgetSettings.requireAuthKey`) geändert → Widget neu laden (es wählt
///   danach den Intent).
@MainActor
final class TaskWidgetSync {
    static let shared = TaskWidgetSync()

    private var model: ThoughtsModel?
    private var bootstrapped = false
    private var wasLoaded = false
    private var debounce: Task<Void, Never>?
    private var queueRun: Task<Void, Never>?
    /// zuletzt geschriebener Inhalt (gleicher Inhalt → nicht neu schreiben)
    private var written: TaskSnapshot?
    private var requiresAuth: Bool?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Aus `didFinishLaunching` (nach `ThoughtsEnvironment.bootstrap()`).
    static func bootstrap() {
        shared.connect()
    }

    private func connect() {
        guard !bootstrapped else { return }
        bootstrapped = true
        DarwinBus.shared.observe(.taskCompleted) {
            Task { await TaskWidgetSync.shared.applyQueue(reason: "darwin") }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                await TaskWidgetSync.shared.applyQueue(reason: "foreground")
                TaskWidgetSync.shared.schedule()
            }
        })
        // neuer Tag, neue Zeitzone: „heute“ zählt neu – auch bei gleichem Inhalt schreiben, damit das Widget neu lädt
        observers.append(center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await TaskWidgetSync.shared.write(force: true) }
        })
        // Schalter „Abhaken nur mit Face ID“ (App-Group-Defaults, im Entwicklerbereich)
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in TaskWidgetSync.shared.checkAuthSetting() }
        })
        ProtectedData.whenReadable { _ in TaskWidgetSync.shared.start(ThoughtsModel.shared) }
    }

    private func start(_ model: ThoughtsModel) {
        guard self.model == nil else { return }
        self.model = model
        requiresAuth = TaskWidgetSettings.requiresAuth(AppGroup.defaults)
        track()
        if model.isLoaded { loaded() }
    }

    /// Gedanken, Themen und „gelesen“ beobachten (feuert einmal je Änderung, danach neu anmelden)
    private func track() {
        guard let model else { return }
        withObservationTracking {
            _ = model.taskThoughts
            _ = model.topics
            _ = model.isLoaded
        } onChange: {
            Task { @MainActor in TaskWidgetSync.shared.changed() }
        }
    }

    private func changed() {
        track()
        guard let model, model.isLoaded else { return }
        if !wasLoaded {
            loaded()
        } else {
            schedule()
        }
    }

    private func loaded() {
        wasLoaded = true
        Task {
            await applyQueue(reason: "launch")
            await write()
        }
    }

    // MARK: Momentaufnahme

    /// Entprellt schreiben (≈ 0,5 s nach der letzten Änderung)
    func schedule() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.write()
        }
    }

    /// Jetzt schreiben und das Widget neu laden. `force`: auch bei gleichem Inhalt (nach dem Anwenden der
    /// Warteschlange – die Erweiterung hat die Datei inzwischen selbst geändert).
    private func write(force: Bool = false) async {
        guard let model, model.isLoaded, ProtectedData.isReadable else { return }
        let snapshot = Self.makeSnapshot(model: model, pending: TaskWidgetFiles.pendingCompletions(), now: Date())
        checkAuthSetting()
        if !force, snapshot.sameContent(as: written) { return }
        written = snapshot
        let ok = await withCheckedContinuation { continuation in
            SharedIO.async { continuation.resume(returning: TaskWidgetFiles.writeSnapshot(snapshot)) }
        }
        guard ok else {
            Diag.log("tasks.widget.write.failed")
            written = nil
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.tasks)
    }

    /// Momentaufnahme aus einem Modell (auch für die Debug-Vorschau mit Beispieldaten). `pending` gilt als erledigt.
    static func makeSnapshot(model: ThoughtsModel, pending: [TaskCompletion], now: Date) -> TaskSnapshot {
        let keys = Dictionary(pending.map { (TaskKey(thoughtID: $0.thoughtID, taskID: $0.taskID), $0.at) }, uniquingKeysWith: min)
        let digest = TaskDigest(thoughts: model.taskThoughts, pending: keys, now: now, limit: TaskSnapshot.maxItems)
        let items = digest.items.map { item -> TaskSnapshot.Item in
            let topic = model.topic(item.topicID)
            return TaskSnapshot.Item(
                thoughtID: item.thoughtID,
                taskID: item.taskID,
                text: item.text,
                dueAt: item.dueAt,
                hasTime: item.hasTime,
                topicTitle: topic?.title,
                topicColor: topic.map { rgb(TopicPalette.baseColor(for: $0.id, scheme: .dark)) },
                topicSymbol: topic?.icon.rawValue
            )
        }
        return TaskSnapshot(generatedAt: now, openCount: digest.openCount, urgentCount: digest.urgentCount,
                            doneTodayAt: digest.doneToday, dueDates: Array(digest.dueDates.prefix(TaskSnapshot.maxDueDates)),
                            items: items)
    }

    private static func rgb(_ color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    // MARK: Warteschlange

    /// Im Widget Abgehaktes anwenden. Läuft nacheinander (nie zwei Durchgänge gleichzeitig). `wait`: so lange darauf
    /// warten, dass die Gedanken gelesen sind (Intent nach einem Kaltstart); sonst übernimmt das später der Start.
    func applyQueue(reason: String, wait: Duration = .zero) async {
        let previous = queueRun
        let run = Task { @MainActor [weak self] in
            await previous?.value
            await self?.drain(reason: reason, wait: wait)
        }
        queueRun = run
        await run.value
    }

    private func drain(reason: String, wait: Duration) async {
        let clock = ContinuousClock()
        let deadline = clock.now + wait
        while !(model?.isLoaded ?? false) || !ProtectedData.isReadable {
            guard clock.now < deadline else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let model else { return }
        let entries = TaskWidgetFiles.pendingCompletions()
        guard !entries.isEmpty else { return }
        let requests = entries.map {
            TaskCompletionPlan.Request(id: $0.id, key: TaskKey(thoughtID: $0.thoughtID, taskID: $0.taskID), at: $0.at)
        }
        let plan = TaskCompletionPlan.make(requests, thoughts: model.taskThoughts)
        for request in plan.apply {
            model.completeTask(request.key.thoughtID, request.key.taskID, at: request.at)
        }
        await model.flushWrites()
        // erst die neue Momentaufnahme (ohne die Aufgaben), dann die Einträge löschen
        await write(force: true)
        TaskWidgetFiles.removeCompletions(plan.settled)
        Diag.log("tasks.widget.applied", [
            "reason": .s(reason),
            "applied": .i(plan.apply.count),
            "ignored": .i(plan.ignored.count),
            "app": .s(SessionController.appState),
        ])
    }

    // MARK: Schalter

    private func checkAuthSetting() {
        let value = TaskWidgetSettings.requiresAuth(AppGroup.defaults)
        guard value != requiresAuth else { return }
        let first = requiresAuth == nil
        requiresAuth = value
        if !first { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.tasks) }
    }
}
