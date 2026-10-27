import PaplyKit
import SwiftUI

// Ablauf einer Aufnahme in der App (KONZEPT §3.4, §5): große Ansicht, Leiste und ihre Zustände.
// Aufnahme selbst: ThoughtCapture (H3). Was danach passiert, liest die Leiste aus ThoughtsModel.

/// Die Schnittstelle von ThoughtCapture (§9.2), damit die Oberfläche im Debug auch mit einer
/// gespielten Aufnahme gezeigt werden kann.
@MainActor
protocol CaptureDriving: AnyObject {
    var active: ThoughtCapture.Active? { get }
    /// 0…1, Lock-Wert – wird je Bild gelesen, nie beobachtet
    var level: Float { get }
    /// letzter Stopp mit Grund (Anruf, Knopf, Live Activity …)
    var lastStop: ThoughtCapture.LastStop? { get }
    /// zuletzt verworfener Gedanke (liegt in „Zuletzt gelöscht“, 10 s widerrufbar)
    var lastDiscard: ThoughtCapture.LastDiscard? { get }
    func toggle(trigger: ThoughtTrigger) async -> ThoughtToggleOutcome
    func finish(_ reason: ThoughtFinishReason)
    func discard()
}

extension ThoughtCapture: CaptureDriving {}

@MainActor
@Observable
final class CaptureFlow {
    /// Was die Aufnahme-Leiste zeigt (§3.4)
    enum Bar: Equatable {
        case hidden
        case recording
        case ordering(String)
        case saved(String)
        case waiting(String, icon: Lucide, text: String)
        case nothing
        case note(String)
        /// verworfen – 10 s „Widerrufen“
        case discarded(String)
    }

    static let fabSource = "capture.fab"
    static let barSource = "capture.bar"

    let driver: any CaptureDriving

    /// große Aufnahme-Ansicht sichtbar
    var showBig = false
    /// Quelle des Zoom-Übergangs (Knopf, Leiste oder die neue Zeile)
    var zoomSource = CaptureFlow.fabSource
    private(set) var bar: Bar = .hidden
    /// Start aus der App läuft (Fall B kann Sekunden dauern)
    private(set) var isStarting = false
    /// Start abgelehnt – Text für die große Ansicht
    private(set) var startError: String?
    /// „Fertig“ in der großen Ansicht gedrückt (Häkchen, „Wird geordnet …“)
    private(set) var finishing: String?
    /// Aufnahme endete ohne „Fertig“ hier (Anruf, Knopf, Live Activity), während die Ansicht offen war
    private(set) var stoppedElsewhere = false
    /// Text dazu, je nach Grund („Anruf – Aufnahme gesichert“)
    private(set) var stopNote = "Aufnahme gesichert"
    /// zählt hoch, wenn der Gedanke gespeichert ist, während die große Ansicht offen ist (Haptik)
    private(set) var savedPulse = 0
    /// zählt hoch bei „Nichts verstanden“ (Schütteln + Warnung)
    private(set) var nothingPulse = 0
    /// zählt hoch bei „Fertig“ in der Leiste (Haptik)
    private(set) var barStopPulse = 0
    /// zuletzt aufgenommener Gedanke, dessen Verarbeitung die Leiste verfolgt
    private(set) var trackedID: String?

    @ObservationIgnored private var trackedSeen = false
    @ObservationIgnored private var trackedSince = Date()
    @ObservationIgnored private var discarding = false
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var lostTask: Task<Void, Never>?

    init(driver: any CaptureDriving) {
        self.driver = driver
    }

    // MARK: Aktionen der Oberfläche

    /// Aufnahme-Knopf bzw. Leiste: große Ansicht zeigen, ggf. Aufnahme starten.
    func openBig(source: String = CaptureFlow.fabSource) {
        zoomSource = source
        startError = nil
        stoppedElsewhere = false
        finishing = nil
        showBig = true
        if driver.active == nil { start() }
    }

    private func start() {
        guard !isStarting else { return }
        isStarting = true
        Task {
            let outcome = await driver.toggle(trigger: .app)
            isStarting = false
            switch outcome {
            case .started:
                let defaults = UserDefaults.standard
                defaults.set(defaults.integer(forKey: CaptureView.hintKey) + 1, forKey: CaptureView.hintKey)
            case .refused(let message), .needsForeground(let message):
                startError = message.isEmpty ? "Das Mikro ließ sich nicht starten." : message
            case .ignored, .stopped:
                if driver.active == nil { showBig = false }
            }
        }
    }

    /// „Fertig“ in der großen Ansicht: Häkchen, 0,6 s „Wird geordnet …“, dann zurück in die Leiste, die
    /// zeigt, wie der Gedanke geordnet wird (die Startseite ist eine Karte, keine Liste mehr).
    func finishFromBig() {
        guard let active = driver.active, finishing == nil else { return }
        finishing = active.id
        driver.finish(.app)
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PaplyHoldDone") { return }
            #endif
            zoomSource = CaptureFlow.barSource
            showBig = false
            try? await Task.sleep(for: .seconds(0.5))
            finishing = nil
        }
    }

    /// „Fertig“ in der Leiste
    func finishFromBar() {
        guard driver.active != nil else { return }
        barStopPulse += 1
        driver.finish(.app)
    }

    /// Verwerfen (nach Rückfrage ab 5 s)
    func discard() {
        discarding = true
        driver.discard()
        trackedID = nil
    }

    /// Verworfen (App oder Live Activity): 10 s „Widerrufen“ in der Leiste
    func discardChanged(_ discard: ThoughtCapture.LastDiscard?) {
        guard let discard, Date().timeIntervalSince(discard.at) < 10 else { return }
        discarding = false
        trackedID = nil
        lostTask?.cancel()
        setBar(.discarded(discard.id), hideAfter: max(1, 10 - Date().timeIntervalSince(discard.at)))
    }

    /// „Widerrufen“ in der Leiste wurde getippt
    func discardUndone() {
        setBar(.hidden)
    }

    func closeBig() {
        showBig = false
    }

    // MARK: Beobachtung (CaptureTracker ruft das auf)

    func activeChanged(from old: ThoughtCapture.Active?, to new: ThoughtCapture.Active?) {
        if let new, old?.id != new.id {
            hideTask?.cancel()
            lostTask?.cancel()
            discarding = false
            stoppedElsewhere = false
            trackedID = new.id
            trackedSeen = false
            setBar(.recording)
            // Fall B gescheitert: die App wurde gerade dafür nach vorne geholt → direkt groß zeigen
            if !showBig, let activated = SessionController.shared.lastActivatedAt, Date().timeIntervalSince(activated) < 3 {
                zoomSource = CaptureFlow.barSource
                showBig = true
            }
        } else if new == nil, let old {
            if discarding {
                discarding = false
                return
            }
            trackedID = old.id
            trackedSeen = false
            trackedSince = Date()
            setBar(.ordering(old.id))
            if showBig, finishing == nil {
                // Anruf, Knopf im Sperrbildschirm, Live Activity: kurz sagen, dann schließen
                stopNote = Self.stopText(driver.lastStop?.id == old.id ? driver.lastStop?.reason : nil)
                stoppedElsewhere = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    if stoppedElsewhere { showBig = false }
                }
            }
            lostTask?.cancel()
            lostTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, let self, self.trackedID == old.id, !self.trackedSeen else { return }
                self.trackedID = nil
                self.setBar(.hidden)
            }
        }
    }

    /// Zustand des verfolgten Gedankens im Modell (nil = nicht (mehr) vorhanden)
    func trackedChanged(state: ThoughtState?, topic: Topic?) {
        guard let id = trackedID, driver.active == nil else { return }
        guard let state else {
            if trackedSeen {
                // war da und ist weg: nichts verstanden, nichts gespeichert
                trackedID = nil
                nothingPulse += 1
                setBar(.nothing, hideAfter: 3)
            }
            return
        }
        trackedSeen = true
        lostTask?.cancel()
        switch state {
        case .recording, .captured, .transcribing, .transcribed, .structuring:
            setBar(.ordering(id))
        case .done:
            if showBig { savedPulse += 1 }
            trackedID = nil
            setBar(.saved(id), hideAfter: 2)
        case .waitingNetwork, .waitingKey, .waitingLimit, .waitingBudget, .needsAttention:
            trackedID = nil
            let note = Self.waitNote(state)
            setBar(.waiting(id, icon: note.icon, text: note.text), hideAfter: 3)
        case .empty:
            trackedID = nil
            nothingPulse += 1
            setBar(.nothing, hideAfter: 3)
        }
    }

    private static func waitNote(_ state: ThoughtState) -> (icon: Lucide, text: String) {
        switch state {
        case .waitingNetwork: (.wifiOff, "Gesichert · wartet auf Netz")
        case .waitingKey: (.keyRound, "Gesichert · Groq-Schlüssel fehlt")
        case .waitingLimit: (.hourglass, "Gesichert · Groq-Limit")
        case .waitingBudget: (.hourglass, "Gesichert · Kontingent erreicht")
        default: (.triangleAlert, "Ton gesichert · Paply versucht es später")
        }
    }

    /// Warum die Aufnahme ohne „Fertig“ hier endete (§3.4, §3.7)
    private static func stopText(_ reason: ThoughtFinishReason?) -> String {
        switch reason {
        case .interruption: "Anruf – Aufnahme gesichert"
        case .keyboardTookOver: "Diktat übernimmt – Aufnahme gesichert"
        case .limit: "Nach 10 Min. gespeichert"
        case .storage: "Speicher voll · bisheriger Ton gesichert"
        case .liveActivity, .button, .app, nil: "Aufnahme gesichert"
        }
    }

    private func setBar(_ value: Bar, hideAfter seconds: Double? = nil) {
        hideTask?.cancel()
        if bar != value {
            withAnimation(.paplyBouncy) { bar = value }
        }
        guard let seconds else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.bar == value else { return }
            withAnimation(.paplySmooth) { self.bar = .hidden }
        }
    }

    #if DEBUG
    /// Nur für Bildschirmfotos (ThoughtsDebug)
    func debugShow(_ value: Bar) { bar = value }
    #endif
}

/// Unsichtbar: meldet Wechsel der Aufnahme und des verfolgten Gedankens an den Ablauf. Eigene
/// Ansicht, damit nur sie bei jeder Modelländerung neu rechnet.
struct CaptureTracker: View {
    let flow: CaptureFlow
    @Environment(ThoughtsModel.self) private var model

    private struct Tracked: Equatable {
        var id: String?
        var state: ThoughtState?
        var topicID: String?
    }

    var body: some View {
        let id = flow.trackedID
        let thought = id.flatMap { model.thought($0) }
        let tracked = Tracked(id: id, state: thought?.state, topicID: thought?.topicId)
        Color.clear
            .onChange(of: flow.driver.active, initial: true) { old, new in
                flow.activeChanged(from: old, to: new)
            }
            .onChange(of: flow.driver.lastDiscard) { _, new in
                flow.discardChanged(new)
            }
            .onChange(of: tracked) { _, new in
                guard new.id != nil else { return }
                flow.trackedChanged(state: new.state, topic: model.topic(new.topicID))
            }
            .accessibilityHidden(true)
    }
}
