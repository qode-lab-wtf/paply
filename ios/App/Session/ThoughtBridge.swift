import ActivityKit
import AudioToolbox
import Foundation
import PaplyKit
import WidgetKit

// Verbindung Intents/Control/Live Activity ↔ ThoughtCapture (KONZEPT §3.5, §3.6, §5). Besitzer: H3.
//
// Live Activity: nur 3–4 Aktualisierungen je Gedanke (Start, Stopp, Ergebnis, ggf. Hinweis vor der
// 10-Min.-Grenze). Ergebnis-Phasen bleiben kurz stehen und enden dann sofort (die Dynamic Island
// zeigt beendete Activities nicht mehr). Alert nur bei „Nichts verstanden“.
@MainActor
enum ThoughtBridge {
    private static var bootstrapped = false
    /// Activity.id und zugehöriger Gedanke (Activity selbst ist nicht Sendable)
    private static var activityID: String?
    private static var activityThoughtID: String?
    private static var activityStartedAt = Date()
    private static var resultTimeout: Task<Void, Never>?
    private static var eventsTask: Task<Void, Never>?
    private static var lastCommandSeq: UInt64 = 0
    /// Warum ein leerer Gedanke leer blieb, wenn es am Mikro lag (statt „Nichts verstanden“)
    enum MicNote {
        /// nur digitale Stille
        case silent
        /// zweimal nichts verstanden – Mikro wird neu gestartet
        case restart

        /// Live Activity
        var activityText: String {
            switch self {
            case .silent: "Mikro war stumm – Paply öffnen, dann neu aufnehmen"
            case .restart: "Nichts verstanden – Mikro wird neu gestartet, bitte nochmal sprechen"
            }
        }

        /// Leiste in der App
        var barText: String {
            switch self {
            case .silent: "Mikro war stumm – bitte neu aufnehmen"
            case .restart: "Mikro neu gestartet – bitte nochmal sprechen"
            }
        }
    }

    private static var micNotes: [String: MicNote] = [:]

    /// Beim App-Start (PaplyApp): Reste aufräumen, Weiterleitung aus dem Widget-Prozess empfangen.
    static func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        endLeftoverActivities()
        writeState(ThoughtStateFile(recording: false, id: nil, startedAt: nil))
        DarwinBus.shared.observe(.thoughtToggle) { ThoughtBridge.handleForwardedCommand() }
    }

    /// Für H2 (ThoughtsEnvironment): Speicher und Warteschlange anschließen.
    static func connect(store: ThoughtStore, processor: ThoughtProcessor) {
        ThoughtCapture.shared.store = store
        ThoughtCapture.shared.processor = processor
        eventsTask?.cancel()
        eventsTask = Task {
            for await event in processor.events {
                handle(event)
            }
        }
    }

    // MARK: Auslöser

    static func toggle(trigger: ThoughtTrigger) async -> ThoughtToggleOutcome {
        await ThoughtCapture.shared.toggle(trigger: trigger)
    }

    /// „Fertig“ in der Live Activity. Veraltete Activity (andere ID) → nur sie beenden.
    /// Startet Fall B noch, wird der Stopp vorgemerkt (ThoughtCapture führt ihn aus, sobald das Mikro dran ist).
    static func finishFromActivity(id: String) async {
        if ThoughtCapture.shared.isCurrent(id) {
            ThoughtCapture.shared.finish(.liveActivity)
        } else {
            Diag.log("thought.finish.stale", ["id": .s(ThoughtCapture.short(id))])
            endActivity(id: id, immediately: true)
        }
    }

    /// „Verwerfen“ in der Live Activity. Veraltete Activity → nur sie beenden.
    static func discardFromActivity(id: String) async {
        if ThoughtCapture.shared.isCurrent(id) {
            ThoughtCapture.shared.discard()
        } else {
            Diag.log("thought.discard.stale", ["id": .s(ThoughtCapture.short(id))])
            endActivity(id: id, immediately: true)
        }
    }

    /// Beta „Gedanken & Aufgaben“: Darf der Knopf etwas tun? An – ja; aus – nur eine noch laufende Aufnahme beenden.
    /// Liest den Stand nach dem ersten Entsperren neu (vorher gilt der Standard, die Aufnahme lehnt dann ohnehin ab).
    static func allowsToggle() -> Bool {
        ProtectedData.check()
        AppSettings.shared.reloadIfNeeded()
        return AppSettings.shared.betaThoughts || ThoughtCapture.shared.active != nil
    }

    /// Beta aus, Knopf gedrückt, Paply ist jetzt vorne: Hinweis mit dem Weg in die Einstellungen (RootView)
    static func showBetaHint() {
        Diag.log("thought.betaHint", ["app": .s(SessionController.appState)])
        BetaHint.shared.show()
    }

    /// Fall B gescheitert, die App ist jetzt vorne: hier klappt der Sitzungsstart. Bis hierher können Sekunden vergehen
    /// (Rückfrage von iOS): Ist Beta „Gedanken & Aufgaben“ inzwischen aus, startet nichts – das prüft `toggle` zentral,
    /// auch nach jedem `await` des Starts.
    static func startInForeground(trigger: ThoughtTrigger) async {
        guard ThoughtCapture.shared.active == nil else { return }
        let outcome = await ThoughtCapture.shared.toggle(trigger: trigger)
        Diag.log("thought.foreground.outcome", ["outcome": .s(String(describing: outcome))])
    }

    /// Widget-Prozess hat weitergeleitet (perform lief nicht in der App).
    private static func handleForwardedCommand() {
        guard let command = SharedStore.read(ThoughtCommand.self, .thoughtCommand), command.seq > lastCommandSeq else { return }
        lastCommandSeq = command.seq
        Diag.log("thought.forwarded", ["action": .s(command.action.rawValue), "latencyMs": .ms(MonoClock.msSince(command.seq))])
        Task {
            switch command.action {
            case .toggle:
                // Beta aus (die Erweiterung prüft das schon; hier nur zur Sicherheit): nicht aufnehmen
                guard allowsToggle() else {
                    Diag.log("thought.forwarded.betaOff")
                    return
                }
                _ = await toggle(trigger: ThoughtTrigger(rawValue: command.trigger) ?? .unknown)
            case .finish:
                if let id = command.thoughtID { await finishFromActivity(id: id) }
            case .discard:
                if let id = command.thoughtID { await discardFromActivity(id: id) }
            }
        }
    }

    // MARK: Zustand für Control und Widgets

    static func recordingChanged(id: String?, startedAt: Date?) {
        writeState(ThoughtStateFile(recording: id != nil, id: id, startedAt: startedAt))
    }

    private static func writeState(_ state: ThoughtStateFile) {
        SharedIO.async {
            SharedStore.write(state, .thoughtState)
            DarwinBus.shared.post(.thoughtState)
            // Sperrbildschirm-Widget erst nach dem Schreiben neu laden – es liest die Datei
            Task { @MainActor in WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.thought) }
        }
        ControlCenter.shared.reloadControls(ofKind: ControlKinds.thought)
    }

    // MARK: Live Activity

    static func startActivity(id: String, startedAt: Date) {
        // Es gibt nur eine Gedanken-Activity: eine noch laufende (voriger Gedanke) endet sofort
        if let previous = activityThoughtID { endActivity(id: previous, immediately: true) }
        resultTimeout?.cancel()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Diag.log("thought.activity.disabled")
            return
        }
        let state = content(.recording, startedAt: startedAt)
        do {
            let activity = try Activity.request(
                attributes: ThoughtActivityAttributes(thoughtID: id),
                content: ActivityContent(state: state, staleDate: startedAt.addingTimeInterval(ThoughtCapture.limit + 5 * 60)),
                pushType: nil
            )
            activityID = activity.id
            activityThoughtID = id
            activityStartedAt = startedAt
            Diag.log("thought.activity.start", ["id": .s(ThoughtCapture.short(id)), "app": .s(SessionController.appState)])
        } catch {
            let ns = error as NSError
            Diag.log("thought.activity.start.failed", ["domain": .s(ns.domain), "code": .i(ns.code), "app": .s(SessionController.appState)])
        }
    }

    static func warnLimit(id: String, startedAt: Date) {
        guard activityThoughtID == id else { return }
        var state = content(.recording, startedAt: startedAt)
        state.warnLimit = true
        alert(state, staleDate: startedAt.addingTimeInterval(ThoughtCapture.limit + 5 * 60), body: "Gedanke · noch 1 Min.")
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        Diag.log("thought.warnLimit", ["id": .s(ThoughtCapture.short(id)), "app": .s(SessionController.appState)])
    }

    /// App verlassen, Gedanke läuft weiter: Live Activity kurz oben zeigen (ohne Dynamic Island als
    /// Banner mit Sekundenzähler, „Fertig“ und „Verwerfen“) und einmal vibrieren.
    static func nudge(id: String, startedAt: Date, elapsed: TimeInterval) {
        // Vibration auch ohne Live Activity (in den Einstellungen abgeschaltet)
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        if activityThoughtID == id {
            let minutes = Int(elapsed / 60)
            alert(content(.recording, startedAt: startedAt), staleDate: startedAt.addingTimeInterval(ThoughtCapture.limit + 5 * 60),
                  body: minutes < 1 ? "Gedanke läuft" : "Gedanke läuft seit \(minutes) Min.")
        }
        Diag.log("thought.nudge", ["id": .s(ThoughtCapture.short(id)), "s": .i(Int(elapsed))])
    }

    /// Nach dem Stopp: „Wird geordnet …“. Kommt 45 s kein Ergebnis: „Gesichert · wird gleich geordnet“.
    static func showProcessing(id: String, startedAt: Date, note: String?) {
        guard activityThoughtID == id else { return }
        var state = content(.processing, startedAt: startedAt)
        state.note = note
        update(state, staleDate: Date().addingTimeInterval(10 * 60))
        resultTimeout?.cancel()
        resultTimeout = Task {
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, activityThoughtID == id else { return }
            var waiting = content(.waiting, startedAt: startedAt)
            waiting.waitSymbol = "hourglass"
            waiting.note = "Gesichert · wird gleich geordnet"
            finishActivity(id: id, state: waiting, dwell: 3, alert: nil)
        }
    }

    /// Nach „Verwerfen“: kurz „Verworfen“, dann weg.
    static func showDiscarded(id: String) {
        guard activityThoughtID == id else { return }
        var state = content(.discarded, startedAt: activityStartedAt)
        state.note = "Verworfen · wird nicht geordnet"
        finishActivity(id: id, state: state, dwell: 2, alert: nil)
    }

    /// Kurzer Hinweis ohne Aufnahme (z. B. Knopf während eines Tastatur-Diktats): 2 s, dann weg.
    /// Läuft gerade eine Gedanken-Activity, bleibt sie unangetastet.
    static func showNotice(_ note: String, symbol: String) {
        guard activityThoughtID == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        var state = content(.waiting, startedAt: Date())
        state.waitSymbol = symbol
        state.note = note
        do {
            let activity = try Activity.request(
                attributes: ThoughtActivityAttributes(thoughtID: "notice"),
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)),
                pushType: nil
            )
            let activityID = activity.id
            Task.detached {
                try? await Task.sleep(for: .seconds(2))
                guard let activity = Activity<ThoughtActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            Diag.log("thought.notice", ["symbol": .s(symbol)])
        } catch {
            Diag.log("thought.notice.failed", ["code": .i((error as NSError).code)])
        }
    }

    /// S1 ohne Warteschlange: kurz „Gesichert“ zeigen.
    static func showSavedWithoutProcessing(id: String, note: String?) {
        guard activityThoughtID == id else { return }
        var state = content(.saved, startedAt: activityStartedAt)
        state.note = note ?? "Gesichert"
        finishActivity(id: id, state: state, dwell: 3, alert: nil)
    }

    static func endActivity(id: String, immediately: Bool) {
        guard activityThoughtID == id, let activityID else { return }
        self.activityID = nil
        activityThoughtID = nil
        resultTimeout?.cancel()
        Task.detached {
            guard let activity = Activity<ThoughtActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        Diag.log("thought.activity.end", ["id": .s(ThoughtCapture.short(id)), "immediately": .b(immediately)])
    }

    /// Ergebnis ohne Warteschlangen-Ereignis zeigen (z. B. Aufnahme ohne Ton → „Nichts verstanden“).
    static func showResult(_ event: ProcessorEvent) {
        handle(event)
    }

    /// Das Mikro lieferte bei diesem Gedanken nur digitale Stille (ThoughtCapture).
    static func markSilentMic(id: String) {
        micNotes[id] = .silent
    }

    /// Nach diesem Gedanken wird das Mikro neu gestartet (zweimal nichts verstanden).
    static func markMicRestart(id: String) {
        if micNotes[id] == nil { micNotes[id] = .restart }
    }

    /// Lag es bei diesem (leeren) Gedanken am Mikro? Gibt die Markierung dabei frei.
    static func takeMicNote(id: String) -> MicNote? {
        micNotes.removeValue(forKey: id)
    }

    /// Ereignisse der Warteschlange (H2) → Phasen
    private static func handle(_ event: ProcessorEvent) {
        switch event {
        case .processing(let id):
            guard activityThoughtID == id else { return }
            update(content(.processing, startedAt: activityStartedAt), staleDate: Date().addingTimeInterval(10 * 60))
        case .saved(let id, let topicTitle, let topicIcon):
            var state = content(.saved, startedAt: activityStartedAt)
            state.topicTitle = topicTitle
            state.topicSymbol = topicIcon?.rawValue
            finishActivity(id: id, state: state, dwell: 4, alert: nil)
        case .waiting(let id, let thoughtState, let message):
            var state = content(.waiting, startedAt: activityStartedAt)
            state.waitSymbol = waitSymbol(for: thoughtState)
            state.note = message
            finishActivity(id: id, state: state, dwell: 3, alert: nil)
        case .empty(let id):
            var state = content(.empty, startedAt: activityStartedAt)
            // Stummes Mikro: ehrlich sagen, woran es lag (nicht „Nichts verstanden“)
            let note = micNotes[id]?.activityText ?? "Nichts verstanden – nichts gespeichert"
            state.note = note
            finishActivity(id: id, state: state, dwell: 4, alert: note)
        case .failed(let id, let message):
            var state = content(.failed, startedAt: activityStartedAt)
            state.note = message.isEmpty ? "Ton gesichert · Paply versucht es später" : message
            finishActivity(id: id, state: state, dwell: 3, alert: nil)
        }
    }

    /// Ergebnis zeigen, kurz stehen lassen, dann sofort beenden.
    private static func finishActivity(id: String, state: ThoughtActivityAttributes.ContentState, dwell: Double, alert: String?) {
        guard activityThoughtID == id, let activityID else { return }
        self.activityID = nil
        activityThoughtID = nil
        resultTimeout?.cancel()
        let stale = Date().addingTimeInterval(10 * 60)
        Task.detached {
            guard let activity = Activity<ThoughtActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
            let content = ActivityContent(state: state, staleDate: stale)
            if let alert {
                let configuration = AlertConfiguration(title: "Paply", body: LocalizedStringResource(stringLiteral: alert), sound: .default)
                await activity.update(content, alertConfiguration: configuration)
            } else {
                await activity.update(content)
            }
            try? await Task.sleep(for: .seconds(dwell))
            await activity.end(content, dismissalPolicy: .immediate)
        }
        Diag.log("thought.activity.result", ["id": .s(ThoughtCapture.short(id)), "phase": .s(state.phase.rawValue)])
    }

    /// Wie `update`, aber hervorgehoben: Dynamic Island klappt kurz auf, ohne sie erscheint ein Banner oben.
    private static func alert(_ state: ThoughtActivityAttributes.ContentState, staleDate: Date, body: String) {
        guard let activityID else { return }
        Task.detached {
            guard let activity = Activity<ThoughtActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
            let configuration = AlertConfiguration(title: "Paply", body: LocalizedStringResource(stringLiteral: body), sound: .default)
            await activity.update(ActivityContent(state: state, staleDate: staleDate), alertConfiguration: configuration)
        }
    }

    private static func update(_ state: ThoughtActivityAttributes.ContentState, staleDate: Date) {
        guard let activityID else { return }
        Task.detached {
            guard let activity = Activity<ThoughtActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
            await activity.update(ActivityContent(state: state, staleDate: staleDate))
        }
    }

    /// Übrig gebliebene Gedanken-Activities (Absturz) beim Start sofort beenden.
    private static func endLeftoverActivities() {
        Task.detached {
            let leftovers = Activity<ThoughtActivityAttributes>.activities
            for activity in leftovers { await activity.end(nil, dismissalPolicy: .immediate) }
            if !leftovers.isEmpty { Diag.log("thought.activity.leftover.ended", ["count": .i(leftovers.count)]) }
        }
    }

    private static func content(_ phase: ThoughtActivityAttributes.ContentState.Phase, startedAt: Date) -> ThoughtActivityAttributes.ContentState {
        ThoughtActivityAttributes.ContentState(phase: phase, startedAt: startedAt, topicTitle: nil, topicSymbol: nil,
                                               waitSymbol: nil, note: nil, warnLimit: false)
    }

    private static func waitSymbol(for state: ThoughtState) -> String {
        switch state {
        case .waitingNetwork: "wifi.slash"
        case .waitingKey: "key"
        default: "hourglass"
        }
    }
}
