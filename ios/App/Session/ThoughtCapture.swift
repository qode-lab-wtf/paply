import Foundation
import Observation
import PaplyKit
import UIKit

// Aufnahme eines Gedankens (KONZEPT §5). Besitzer: H3.
//
// Erfassen ist heilig: Eintrag und WAV entstehen synchron vor jedem `await`, der Ton liegt auf der
// Platte, bevor irgendetwas ins Netz geht. Unterbrechung, Tastatur oder 10-Min.-Grenze sichern den
// Gedanken – verworfen wird nur auf ausdrücklichen Wunsch (`discard`).

enum ThoughtToggleOutcome: Sendable, Equatable {
    case started(String)
    case stopped(String)
    case ignored
    case needsForeground(String)
    case refused(String)
}

enum ThoughtFinishReason: String, Sendable {
    case button, liveActivity, app, interruption, keyboardTookOver, limit, storage
    /// Mikro lieferte nur digitale Stille und durfte im Hintergrund nicht neu starten
    case micSilent
}

@MainActor
@Observable
final class ThoughtCapture {
    static let shared = ThoughtCapture()

    struct Active: Equatable {
        let id: String
        let startedAt: Date
        var speechDetected: Bool
    }

    private(set) var active: Active?

    /// Letzter Stopp (für die Oberfläche, z. B. „Anruf – Aufnahme gesichert“)
    struct LastStop: Equatable {
        let id: String
        let reason: ThoughtFinishReason
        let at: Date
    }

    private(set) var lastStop: LastStop?
    var lastStopReason: ThoughtFinishReason? { lastStop?.reason }

    /// Zuletzt verworfener Gedanke (liegt in „Zuletzt gelöscht“). Die Oberfläche kann 10 s lang
    /// „Widerrufen“ anbieten (ThoughtsModel.restore).
    struct LastDiscard: Equatable {
        let id: String
        let at: Date
    }

    private(set) var lastDiscard: LastDiscard?

    /// Lock-Wert (0…1), für TimelineView – keine SwiftUI-Invalidierung je Sample.
    var level: Float { levelBox.value }

    /// Gesetzt von ThoughtBridge.connect (aus ThoughtsEnvironment.bootstrap) – dieselben Instanzen
    /// wie im ThoughtsModel. Ohne Store startet keine Aufnahme.
    @ObservationIgnored var store: ThoughtStore?
    @ObservationIgnored var processor: ThoughtProcessor?

    // MARK: Intern

    static let doublePressGuard: TimeInterval = 0.8
    static let stopAfterInterruptionWindow: TimeInterval = 3
    /// Sicherheitsgrenze (Allan, 27.10.): 10 Min. – alles bis dahin wird gespeichert und geordnet.
    static let limit: TimeInterval = 10 * 60
    /// Hinweis „Noch 1 Min.“ in der Live Activity
    static let warnAfter: TimeInterval = 9 * 60
    /// Die Live-Pipeline hält alle Samples im RAM; bei 10 Min. Grenze reicht sie bis zum Ende.
    static let livePipelineLimit: TimeInterval = 10 * 60

    @ObservationIgnored private let levelBox = ThoughtLevelBox()
    @ObservationIgnored private var recording: Recording?
    @ObservationIgnored private var lastInterruptionStop: (id: String, at: Date)?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Start läuft (Fall B kann Sekunden dauern) – ein zweiter Druck darf keine zweite Aufnahme starten
    @ObservationIgnored private var starting = false
    /// Gedanke, dessen Start gerade läuft: Eintrag und Live Activity gibt es schon, das Mikro noch nicht.
    @ObservationIgnored private(set) var startingID: String?
    /// „Fertig“/„Verwerfen“ aus der Live Activity während des Starts – ausgeführt, sobald er steht.
    private enum PendingStop {
        case finish(ThoughtFinishReason), discard

        var logName: String {
            switch self {
            case .finish(let reason): reason.rawValue
            case .discard: "discard"
            }
        }
    }
    @ObservationIgnored private var pendingStop: PendingStop?

    /// Was zur laufenden Aufnahme gehört (nur Main-Actor).
    private final class Recording {
        let id: String
        let trigger: ThoughtTrigger
        let startedAt: Date
        let startedNs: UInt64
        var placeholder: Thought
        let file: CaptureFile
        var live: LivePipeline?
        var finishing = false

        init(id: String, trigger: ThoughtTrigger, startedAt: Date, startedNs: UInt64, placeholder: Thought, file: CaptureFile) {
            self.id = id
            self.trigger = trigger
            self.startedAt = startedAt
            self.startedNs = startedNs
            self.placeholder = placeholder
            self.file = file
        }
    }

    private init() {}

    // MARK: Druck

    func toggle(trigger: ThoughtTrigger) async -> ThoughtToggleOutcome {
        let begin = MonoClock.now()
        // Zweiter Druck: stoppen – außer ganz frisch (Doppeldruck)
        if let current = active {
            if Date().timeIntervalSince(current.startedAt) < Self.doublePressGuard {
                Diag.log("thought.press.ignored", ["id": .s(Self.short(current.id)), "why": .s("double")])
                return .ignored
            }
            finish(.button)
            return .stopped(current.id)
        }
        // Kurz nach einer Unterbrechung („Siri, Paply fertig“) zählt der Druck als Stopp
        if let last = lastInterruptionStop, Date().timeIntervalSince(last.at) < Self.stopAfterInterruptionWindow {
            Diag.log("thought.press.ignored", ["id": .s(Self.short(last.id)), "why": .s("after-interruption")])
            return .stopped(last.id)
        }
        if starting {
            Diag.log("thought.press.ignored", ["why": .s("starting")])
            return .ignored
        }
        if SessionController.shared.active?.source == .keyboard {
            logStart(case: "-", ok: false, stage: "dictation", trigger: trigger, begin: begin)
            // Sonst wirkt der Knopf tot: kurz in der Live Activity sagen, warum nichts passiert
            ThoughtBridge.showNotice("Diktat läuft gerade", symbol: "keyboard")
            return .refused("Diktat läuft gerade")
        }
        // Vor dem ersten Entsperren nach einem Neustart: nichts anlegen, nichts speichern (Ablage wirkt leer)
        guard ProtectedData.isReadable else {
            logStart(case: "-", ok: false, stage: "before-first-unlock", trigger: trigger, begin: begin)
            ThoughtBridge.showNotice("Nach dem Neustart einmal entsperren", symbol: "lock")
            return .refused("Nach dem Neustart einmal entsperren")
        }
        // Inzwischen entsperrt, aber der Prozess hat es nicht mitbekommen: Aufgeschobenes jetzt laden
        ProtectedData.check()

        guard store != nil else {
            logStart(case: "-", ok: false, stage: "no-store", trigger: trigger, begin: begin)
            return .refused("Gedanken-Ablage nicht bereit")
        }
        starting = true
        defer {
            starting = false
            startingID = nil
            pendingStop = nil
        }

        // 1) Synchron: Eintrag + WAV anlegen (vor jedem await)
        let startedAt = Date()
        let prepared: (Thought, CaptureFile)
        do {
            prepared = try await beginCapture(trigger: trigger, at: startedAt)
        } catch {
            logStart(case: "-", ok: false, stage: "storage", trigger: trigger, begin: begin, code: (error as NSError).code)
            return .refused("Speicher voll · Gedanke nicht gestartet")
        }
        let (placeholder, file) = prepared
        let id = placeholder.id
        startingID = id
        guard let store else { return .refused("Gedanken-Ablage nicht bereit") }

        // 2) Live Activity zuerst (AudioRecordingIntent verlangt eine laufende Activity)
        ThoughtBridge.startActivity(id: id, startedAt: startedAt)

        // 3) Mikro: Fall A (Sitzung läuft) oder B (Sitzung im Hintergrund starten)
        let session = SessionController.shared
        let fall = (session.status == .ready || session.status == .recording) ? "A" : "B"
        let levelBox = levelBox
        let live = makeLivePipeline(id: id)
        let liveFeed = live?.continuation
        let sink: @Sendable ([Float]) -> Void = { samples in
            file.append(samples)
            liveFeed?.yield(.samples(samples))
            levelBox.update(with: samples)
        }
        // Mikro wegen digitaler Stille neu gestartet: Die Live-Pipeline verwirft den stummen Anfang.
        // Die WAV behält ihn (Stille stört den Dateiweg nicht; abschneiden ginge nur mit Umschreiben).
        let onRestart: @Sendable () -> Void = { liveFeed?.yield(.restart) }
        guard await session.attachThought(id: id, sink: sink, onRestart: onRestart) else {
            // Kein Mikro: Eintrag ohne Ton verwerfen (keine Leiche), App kurz nach vorne holen
            live?.cancel()
            file.discard()
            await store.discardCapture(id)
            ThoughtBridge.endActivity(id: id, immediately: true)
            let failure = session.lastStartFailure
            logStart(case: fall, ok: false, stage: failure?.stage ?? "attach", trigger: trigger, begin: begin,
                     code: failure?.code, fourCC: failure?.fourCC)
            // Während des Starts schon „Fertig“/„Verwerfen“ gedrückt: nicht nach vorne holen und neu starten
            if pendingStop != nil { return .stopped(id) }
            return .needsForeground(failure?.fourCC.isEmpty == false ? failure!.fourCC : "Mikro ließ sich nicht starten")
        }

        let rec = Recording(id: id, trigger: trigger, startedAt: startedAt, startedNs: begin, placeholder: placeholder, file: file)
        rec.live = live
        recording = rec
        // Läuft die Live-Pipeline, wartet die Warteschlange auf ihr Ergebnis (sonst Whisper doppelt)
        if live != nil { await processor?.expectLiveTranscript(id) }
        // Während des Wartens beendet (Unterbrechung, Tastatur): nicht wieder als laufend melden
        guard recording === rec, !rec.finishing else { return .stopped(id) }
        active = Active(id: id, startedAt: startedAt, speechDetected: false)
        ThoughtBridge.recordingChanged(id: id, startedAt: startedAt)
        startTicker(id: id)
        logStart(case: fall, ok: true, stage: "recording", trigger: trigger, begin: begin)
        // „Fertig“/„Verwerfen“ kam, während Fall B noch startete: jetzt ausführen
        if let pending = pendingStop {
            pendingStop = nil
            Diag.log("thought.pendingStop", ["id": .s(Self.short(id)), "action": .s(pending.logName)])
            switch pending {
            case .finish(let reason): finish(reason)
            case .discard: discard()
            }
            return .stopped(id)
        }
        return .started(id)
    }

    /// Gehört `id` zur laufenden oder gerade startenden Aufnahme? (Live Activity „Fertig“/„Verwerfen“)
    func isCurrent(_ id: String) -> Bool {
        active?.id == id || startingID == id
    }

    /// Start läuft noch (Mikro nicht dran): Stopp bzw. Verwerfen vormerken. true = vorgemerkt.
    private func deferIfStarting(_ stop: PendingStop) -> Bool {
        guard let id = startingID, recording?.id != id else { return false }
        // Verwerfen gewinnt gegen ein vorgemerktes „Fertig“ (ausdrücklicher Wunsch)
        if case .discard = pendingStop { return true }
        pendingStop = stop
        Diag.log("thought.pendingStop.set", ["id": .s(Self.short(id)), "action": .s(stop.logName)])
        return true
    }

    /// Stoppt und sichert. Nie verwerfen (auch nicht bei Unterbrechung).
    func finish(_ reason: ThoughtFinishReason) {
        if deferIfStarting(.finish(reason)) { return }
        guard let rec = recording, !rec.finishing else { return }
        rec.finishing = true
        let stopNs = MonoClock.now()
        let id = rec.id
        if reason == .interruption { lastInterruptionStop = (id, Date()) }
        if reason == .micSilent { ThoughtBridge.markSilentMic(id: id) }
        lastStop = LastStop(id: id, reason: reason, at: Date())
        ticker?.cancel()
        ticker = nil
        active = nil
        levelBox.set(0)
        ThoughtBridge.recordingChanged(id: nil, startedAt: nil)
        ThoughtBridge.showProcessing(id: id, startedAt: rec.startedAt, note: Self.stopNote(reason))

        Task {
            // Letzte Blöcke abwarten (wie beim Diktat, max. 300 ms)
            let flushStart = MonoClock.now()
            while SessionController.shared.lastAudioArrivalNs < stopNs + 20_000_000, MonoClock.msSince(flushStart) < 300 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            let micStats = SessionController.shared.detachThought(id: id)
            // Ganze Aufnahme nur digitale Stille: Ergebnis „Mikro war stumm“ statt „Nichts verstanden“
            if micStats?.wasSilent == true { ThoughtBridge.markSilentMic(id: id) }
            let durationMs = rec.file.close()
            // Zustand `captured` + Dauer; ohne Ton (0 ms) entfernt der Store den Eintrag
            let saved: Thought?
            do {
                saved = try await store?.finishCapture(id, durationMs: durationMs)
            } catch {
                saved = nil
                Diag.log("thought.save.failed", ["id": .s(Self.short(id)), "code": .i((error as NSError).code)])
            }
            if recording === rec { recording = nil }
            var stopFields: DiagFields = [
                "id": .s(Self.short(id)), "reason": .s(reason.rawValue), "durationMs": .i(durationMs),
                "saved": .b(saved != nil), "live": .b(rec.live != nil), "app": .s(SessionController.appState),
                "micSilent": .b(micStats?.wasSilent == true || reason == .micSilent),
            ]
            // Pegel der Rohpuffer (dBFS, −160 = exakt 0) und Zahl der Null-Puffer – nie Inhalte
            stopFields.merge(micStats?.diagFields ?? [:]) { a, _ in a }
            Diag.log("thought.stop", stopFields)
            if saved == nil {
                ThoughtBridge.showResult(.empty(id))
            }
            // „Zweimal nichts verstanden“: nur abgeschlossene Gedanken („Fertig“) mit Live-Pipeline (VAD)
            if let live = rec.live, [.button, .liveActivity, .app].contains(reason) {
                let speech = await live.speechDetected()
                let outcome = SessionController.shared.completedRecording(speech: speech, seconds: Double(durationMs) / 1000, kind: "thought")
                if outcome != .none { ThoughtBridge.markMicRestart(id: id) }
            }
            // Live-Pipeline: Rohtext Sekunden nach dem Stopp an die Warteschlange, sonst Dateiweg
            if let live = rec.live, let processor {
                let outcome = await live.finish()
                await processor.liveTranscript(id, outcome: outcome)
            } else {
                await processor?.kick(reason: "captured")
            }
            if processor == nil {
                ThoughtBridge.showSavedWithoutProcessing(id: id, note: Self.stopNote(reason))
            }
        }
    }

    /// Ausdrücklich verwerfen (große Aufnahme-Ansicht oder „Verwerfen“ in der Live Activity).
    /// Ehrlich: Während der Aufnahme können schon Stücke an Whisper gegangen sein (Live-Pipeline).
    /// Ab dem Verwerfen bricht sie ab (laufende Uploads werden gestoppt), es folgt kein weiterer
    /// Upload und keine Strukturierung – die Warteschlange überspringt gelöschte Gedanken.
    /// Nicht endgültig: Der Gedanke landet mit Ton in „Zuletzt gelöscht“ (`deletedAt`), die
    /// Oberfläche kann ihn wiederherstellen; dann wird er normal geordnet.
    func discard() {
        if deferIfStarting(.discard) { return }
        guard let rec = recording, !rec.finishing else { return }
        rec.finishing = true
        let id = rec.id
        ticker?.cancel()
        ticker = nil
        active = nil
        levelBox.set(0)
        SessionController.shared.detachThought(id: id)
        rec.live?.cancel()
        lastDiscard = LastDiscard(id: id, at: Date())
        ThoughtBridge.recordingChanged(id: nil, startedAt: nil)
        ThoughtBridge.showDiscarded(id: id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            // Live-Erwartung aufheben: Ein Wiederherstellen ordnet dann sofort über den Dateiweg.
            if rec.live != nil { await processor?.cancelLiveTranscript(id) }
            let durationMs = rec.file.close()
            // Sichern und in „Zuletzt gelöscht“ in EINEM Schritt: Die Warteschlange sieht den Gedanken
            // nie als `captured` ohne `deletedAt`. Nach Wiederherstellen wird normal geordnet.
            // Ohne Ton (0 ms) entfernt der Store den Eintrag ganz.
            var inTrash = false
            if let store {
                do {
                    try await store.finishCapture(id, durationMs: durationMs, deletedAt: Date())
                    inTrash = durationMs > 0
                } catch {
                    Diag.log("thought.discard.failed", ["id": .s(Self.short(id)), "code": .i((error as NSError).code)])
                }
            }
            if recording === rec { recording = nil }
            Diag.log("thought.discard", [
                "id": .s(Self.short(id)), "durationMs": .i(durationMs), "inTrash": .b(inTrash),
                "app": .s(SessionController.appState),
            ])
        }
    }

    // MARK: Zeitgrenzen und Sprache

    /// Jede Sekunde: Sprache erkannt? 9 Min. Hinweis, 10 Min. harte Grenze (§5.4).
    private func startTicker(id: String) {
        ticker?.cancel()
        ticker = Task {
            var warned = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let rec = recording, rec.id == id, var current = active else { return }
                let elapsed = Date().timeIntervalSince(rec.startedAt)
                if !current.speechDetected, await rec.live?.speechDetected() ?? levelBox.heardSpeech {
                    current.speechDetected = true
                    active = current
                    SessionController.shared.noteSpeechHeard()
                }
                if !warned, elapsed >= Self.warnAfter {
                    warned = true
                    ThoughtBridge.warnLimit(id: id, startedAt: rec.startedAt)
                }
                if elapsed >= Self.limit {
                    finish(.limit)
                    return
                }
                if let live = rec.live, elapsed >= Self.livePipelineLimit, !live.abandoned {
                    // Speicher: die Live-Pipeline hält alle Samples im RAM – ab hier gilt der Dateiweg
                    live.cancel()
                    rec.live = nil
                    Diag.log("thought.live.abandoned", ["id": .s(Self.short(id))])
                }
            }
        }
    }

    private static func stopNote(_ reason: ThoughtFinishReason) -> String? {
        switch reason {
        case .interruption: "Gesichert · Anruf hat unterbrochen"
        case .keyboardTookOver: "Gesichert – Diktat hat übernommen"
        case .limit: "Nach 10 Min. gespeichert"
        case .storage: "Speicher voll · bisheriger Ton gesichert"
        case .micSilent: "Mikro war stumm – Aufnahme beendet"
        default: nil
        }
    }

    // MARK: Speicher (ThoughtStore, H2)

    private func beginCapture(trigger: ThoughtTrigger, at date: Date) async throws -> (Thought, CaptureFile) {
        guard let store else { throw CocoaError(.fileNoSuchFile) }
        let (thought, writer) = try await store.beginCapture(trigger: trigger, at: date)
        return (thought, CaptureFile(writer: writer))
    }

    // MARK: Live-Pipeline (§5.3.2)

    private func makeLivePipeline(id: String) -> LivePipeline? {
        // Nur mit Warteschlange (H2), Schlüssel und Netz – sonst gilt nach dem Stopp der Dateiweg.
        guard processor != nil, let apiKey = AppSettings.shared.apiKey, NetworkMonitor.shared.current != "none" else { return nil }
        var options = PipelineOptions()
        options.polish = false
        var settings = AppSettings.shared.effectivePaply
        settings.chunkedUpload = true
        return LivePipeline(pipeline: DictationPipeline(apiKey: apiKey, settings: settings, options: options))
    }

    // MARK: Protokoll

    private func logStart(case fall: String, ok: Bool, stage: String, trigger: ThoughtTrigger, begin: UInt64,
                          code: Int? = nil, fourCC: String? = nil) {
        Diag.log("thought.start", [
            "case": .s(fall),
            "ok": .b(ok),
            "stage": .s(stage),
            "code": code.map { .i($0) } ?? .null,
            "fourCC": .opt(fourCC),
            "process": .s(PaplyProcess.current.rawValue),
            "locked": .b(!UIApplication.shared.isProtectedDataAvailable),
            "trigger": .s(trigger.rawValue),
            "app": .s(SessionController.appState),
            "ms": .ms(MonoClock.msSince(begin)),
        ])
    }

    static func short(_ id: String) -> String { String(id.prefix(10)) }
}

// MARK: - Bausteine (thread-sicher)

/// Pegel als Lock-Wert: der Audio-Thread schreibt, die Oberfläche liest per TimelineView.
final class ThoughtLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Float = 0
    private var floorDb: Float = -60
    private var loudWindows = 0

    var value: Float {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// grobe Sprach-Erkennung ohne Live-Pipeline (nur für die Oberfläche)
    var heardSpeech: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loudWindows >= 4
    }

    func set(_ value: Float) {
        lock.lock()
        current = value
        loudWindows = 0
        lock.unlock()
    }

    /// RMS → dBFS, bezogen aufs Grundrauschen (wie die Tastatur-Welle).
    func update(with samples: [Float]) {
        guard !samples.isEmpty else { return }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let db = 20 * log10(max((sum / Float(samples.count)).squareRoot(), 1e-7))
        lock.lock()
        floorDb = db < floorDb ? max(db, -80) : min(floorDb + 0.1, -25)
        let level = min(1, max(0, (db - floorDb - 3) / 30)).squareRoot()
        current = level
        if level > 0.45 { loudWindows += 1 }
        lock.unlock()
    }
}

/// Ziel der Samples: der WAVWriter des Stores (eigene serielle Queue, blockiert nie).
final class CaptureFile: Sendable {
    private let writer: WAVWriter

    init(writer: WAVWriter) {
        self.writer = writer
    }

    func append(_ samples: [Float]) { writer.append(samples) }
    func close() -> Int { writer.close() }
    /// Datei schließen; das Löschen übernimmt `ThoughtStore.discardCapture`.
    func discard() { _ = writer.close() }
}

/// Live-Verschriftlichung während der Aufnahme (ohne Polieren, mit Stücken).
final class LivePipeline: @unchecked Sendable {
    let continuation: AsyncStream<TapFeed>.Continuation
    private let pipeline: DictationPipeline
    private let feed: Task<Void, Never>
    private(set) var abandoned = false

    init(pipeline: DictationPipeline) {
        self.pipeline = pipeline
        let (stream, continuation) = AsyncStream<TapFeed>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        feed = Task.detached(priority: .userInitiated) { [pipeline] in
            for await item in stream {
                switch item {
                case .samples(let chunk): await pipeline.append(chunk)
                case .restart: await pipeline.discardSilentStart()
                }
            }
        }
    }

    func speechDetected() async -> Bool { await pipeline.speechDetected }

    func finish() async -> DictationOutcome {
        continuation.finish()
        await feed.value
        return await pipeline.finish()
    }

    func cancel() {
        abandoned = true
        continuation.finish()
        feed.cancel()
        let pipeline = pipeline
        Task.detached { await pipeline.cancel() }
    }
}
