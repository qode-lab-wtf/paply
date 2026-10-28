@preconcurrency import AVFoundation
import Foundation
import Observation
import PaplyKit
import UIKit

/// Kern von Phase 0: hält das Mikro im Hintergrund bereit, nimmt Diktate für Tastatur
/// und Schnelltaste auf, beantwortet Lebenszeichen und protokolliert alles Messbare.
@MainActor
@Observable
final class SessionController {
    static let shared = SessionController()

    struct ActiveInfo: Equatable {
        var id: String
        var source: DictationSource
        var startedAt: Date
    }

    enum Flash: Equatable {
        case starting
        case running(dictating: Bool)
        case failed(String)
    }

    // MARK: Anzeige (beobachtet)

    private(set) var status: SessionStatus = .off
    private(set) var startedAt: Date?
    private(set) var lastActivityAt: Date?
    private(set) var detail: String?
    private(set) var active: ActiveInfo?
    private(set) var processingCount = 0
    /// Experiment: Engine im Leerlauf angehalten (Sitzung bleibt aktiv)
    private(set) var idlePaused = false
    /// Kurzer Hinweis nach Start per URL („zurück zur vorherigen App“)
    var flash: Flash?

    var holdUntil: Date? {
        guard let last = lastActivityAt, let seconds = AppSettings.shared.holdDuration.seconds else { return nil }
        return last.addingTimeInterval(seconds)
    }

    // MARK: Intern

    @ObservationIgnored let audio = AudioEngineHost()
    @ObservationIgnored let monitor = DeviceMonitor()
    @ObservationIgnored private var dictation: ActiveDictation? {
        // Jeder Wechsel (Start, fertig, abgebrochen, verworfen, Unterbrechung, Sitzungsende) richtet den Schutz neu aus
        didSet { syncAlertShield(reason: dictation.map { "dictation-\($0.source.rawValue)" } ?? "dictation-end") }
    }
    /// Schutz vor Systemhinweisen an (= ein Diktat oder ein Gedanke nimmt auf). Nur `syncAlertShield` setzt ihn.
    @ObservationIgnored private var alertShieldOn = false
    /// Diktate nach „fertig“, bis das Ergebnis ausgeliefert ist
    @ObservationIgnored private var inFlight: [String: ActiveDictation] = [:]
    @ObservationIgnored private var lastPrewarmNs: UInt64 = 0
    /// Gescheiterte Tastatur-Diktate, die „Erneut versuchen“ noch senden kann (max. 10 Min)
    @ObservationIgnored private var retained: [String: ActiveDictation] = [:]
    private static let retainSeconds: Double = 600
    @ObservationIgnored private var shared = SessionState()
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var levelChannel: LevelChannel?
    @ObservationIgnored private var lastCommandNs: UInt64 = 0
    @ObservationIgnored private var lastShortcutSeq: UInt64 = 0
    @ObservationIgnored private var lastKeyboardContactNs: UInt64 = 0
    @ObservationIgnored private var housekeepingTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var bootstrapped = false
    @ObservationIgnored private var startTask: Task<Bool, Never>?
    /// Sitzung wurde nur für einen Gedanken gestartet (Fall B) und Diktat ist nicht in Gebrauch:
    /// Dann endet sie 5 Min. nach dem Gedanken (kein Dauer-Mikro, das niemand bestellt hat).
    @ObservationIgnored private var startedForThought = false
    @ObservationIgnored private var thoughtSessionEnd: Task<Void, Never>?
    static let thoughtOnlySessionSeconds: Double = 5 * 60
    /// Letzter gescheiterter Sitzungsstart (für das Gedanken-Protokoll `thought.start`, Spike S1)
    @ObservationIgnored private(set) var lastStartFailure: (stage: String, code: Int, fourCC: String)?
    @ObservationIgnored private var pauseTask: Task<Void, Never>?
    @ObservationIgnored private var lastHousekeepingTick = Date()
    /// Wann die App zuletzt aktiv wurde (für den Aufblitz-Bildschirm nach Start per URL)
    @ObservationIgnored var lastActivatedAt: Date?
    /// Mikro lieferte nur digitale Stille und ließ sich nicht neu starten (Hintergrund) oder
    /// der Neustart half nicht: Die Sitzung „muss neu starten“ (Status `.interrupted`).
    /// Die Tastatur öffnet dann die App; im Vordergrund startet das Mikro sofort neu.
    /// Warum die Sitzung neu starten muss: Mikro lieferte digitale Stille, oder zweimal hintereinander
    /// nichts verstanden (`NoSpeechStreak` – fängt auch einen lauten Eingang ohne Sprache).
    enum MicRestartCause: String {
        case silent, noSpeech
    }

    @ObservationIgnored private var micRestartCause: MicRestartCause?
    private var micSilent: Bool { micRestartCause != nil }
    /// Zwei abgeschlossene Aufnahmen ohne erkannte Sprache (≥ 2 s, ≤ 3 Min. auseinander) → Neustart
    @ObservationIgnored private var noSpeechStreak = NoSpeechStreak()
    @ObservationIgnored private var silenceRestartTask: Task<Void, Never>?
    /// Zeitpunkte der Neustarts wegen Stille (MonoClock) – höchstens zwei je Minute, keine Schleife
    @ObservationIgnored private var silenceRestarts: [UInt64] = []
    static let maxSilenceRestartsPerMinute = 2

    private init() {}

    // MARK: Start der App

    func bootstrap() {
        guard !bootstrapped else { return }
        bootstrapped = true
        // Alter Stand aus einem früheren Prozess gilt nicht mehr.
        shared = SessionState()
        publish()
        SharedIO.async {
            StorageCheck.migrateOldLayout()
            SharedStore.pruneResults()
            Self.removeStalePending()
        }
        // Echter Schreib-/Lesetest im gemeinsamen Speicher + Pfade und Größen ins Protokoll
        StorageCheck.shared.run(reason: "launch")
        // Live Activity aus einem abgestürzten Vorgänger nicht stehen lassen
        ShortcutBridge.endLeftoverActivities()
        _ = NetworkMonitor.shared

        let bus = DarwinBus.shared
        bus.observe(.command) { SessionController.shared.handleKeyboardCommand() }
        bus.observe(.ping) { SessionController.shared.handlePing() }
        bus.observe(.shortcut) { SessionController.shared.handleShortcutSignal() }
        registerAudioObservers()
        registerAppObservers()
        // Jeder Motorstart mit App-Zustand und Mikro-Freigabe ins Protokoll
        audio.onEngineStarted { reason, rate, channels in
            Task { @MainActor in SessionController.shared.logEngineStart(reason: reason, rate: rate, channels: channels) }
        }
        // Totes Mikro (≥ 1,5 s digitale Stille) bzw. wieder Ton
        audio.processor.setSilenceHandler { change in
            Task { @MainActor in SessionController.shared.handleMicSilence(change) }
        }
    }

    // MARK: Sitzung

    @discardableResult
    func startSession(trigger: String) async -> Bool {
        // Läuft gerade ein Neustart wegen stummen Mikros, erst sein Ergebnis abwarten
        if let silenceRestartTask { await silenceRestartTask.value }
        if (status == .ready || status == .recording), audio.isRunning { return true }
        // Läuft schon ein Start (z. B. Knopf und URL gleichzeitig), auf ihn warten
        if let startTask { return await startTask.value }
        let task = Task { await performStart(trigger: trigger) }
        startTask = task
        let ok = await task.value
        startTask = nil
        return ok
    }

    private func performStart(trigger: String) async -> Bool {
        if dictation != nil { cancelDictation(reason: "engine-dead") }
        let begin = MonoClock.now()

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .undetermined:
            // Im Hintergrund (Gedanken-Knopf Fall B) kann iOS nicht fragen – die Anfrage hinge.
            // Sofort scheitern; der Aufrufer holt die App nach vorne, dort kommt die Frage.
            guard UIApplication.shared.applicationState == .active else {
                return failStart(trigger: trigger, stage: "permission", code: 0, text: "Mikrofon noch nicht erlaubt – bitte in Paply bestätigen")
            }
            let granted = await AVAudioApplication.requestRecordPermission()
            Diag.log("mic.permission", ["granted": .b(granted)])
            if !granted { return failStart(trigger: trigger, stage: "permission", code: 0, text: "Mikrofon nicht erlaubt") }
        default:
            return failStart(trigger: trigger, stage: "permission", code: 0, text: "Mikrofon nicht erlaubt – in den iOS-Einstellungen freigeben")
        }

        // Sitzung und Engine auf der Audio-Queue starten – der Main-Thread bleibt frei.
        // War das Mikro stumm, alles neu aufbauen (Sitzung ab- und wieder anmelden, neue Engine).
        let fresh = micSilent
        if case .failure(let error) = await audio.start(fresh: fresh) {
            return failStart(trigger: trigger, stage: error.stage, code: error.code, text: "Mikro ließ sich nicht starten (\(error.fourCC.isEmpty ? String(error.code) : error.fourCC))", fourCC: error.fourCC)
        }

        sessionID = UUID().uuidString
        startedAt = Date()
        lastActivityAt = Date()
        status = .ready
        detail = nil
        idlePaused = false
        micRestartCause = nil
        publish()
        startHousekeeping()
        monitor.start()
        var fields: DiagFields = [
            "trigger": .s(trigger),
            "app": .s(Self.appState),
            "mic": .s(Self.micPermission),
            "fresh": .b(fresh),
            "ms": .ms(MonoClock.msSince(begin)),
            "hold": .s(AppSettings.shared.holdDuration.rawValue),
        ]
        fields.merge(audio.routeFields) { a, _ in a }
        Diag.log("session.start", fields)
        return true
    }

    private func failStart(trigger: String, stage: String, code: Int, text: String, fourCC: String = "") -> Bool {
        lastStartFailure = (stage, code, fourCC)
        Diag.log("session.start.failed", [
            "trigger": .s(trigger), "stage": .s(stage), "code": .i(code), "fourCC": .s(fourCC), "app": .s(Self.appState),
            "mic": .s(Self.micPermission),
        ])
        status = .off
        detail = text
        publish()
        return false
    }

    func stopSession(reason: String) {
        // „Ausschalten“ beendet auch einen laufenden Gedanken – gesichert, nie verworfen
        if ThoughtCapture.shared.active != nil { ThoughtCapture.shared.finish(.app) }
        guard status != .off || audio.isRunning else { return }
        cancelDictation(reason: "session-stop")
        micRestartCause = nil
        silenceRestartTask?.cancel()
        silenceRestartTask = nil
        silenceRestarts = []
        startedForThought = false
        thoughtSessionEnd?.cancel()
        pauseTask?.cancel()
        idlePaused = false
        audio.stop()
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        status = .off
        startedAt = nil
        sessionID = nil
        detail = nil
        resumeTask?.cancel()
        housekeepingTask?.cancel()
        housekeepingTask = nil
        publish()
        monitor.stop()
        var fields: DiagFields = ["reason": .s(reason), "durationS": .d(duration.rounded()), "app": .s(Self.appState)]
        fields.merge(ProcessMetrics.fields) { a, _ in a }
        Diag.log("session.stop", fields)
    }

    // MARK: Diktat

    enum BeginResult {
        case started
        case noAPIKey
        case notReady
    }

    @discardableResult
    func beginDictation(id: String, source: DictationSource, commandLatencyMs: Double? = nil) -> BeginResult {
        // Gedanken-Haken: Die Tastatur übernimmt – der Gedanke wird gesichert, nie verworfen.
        if ThoughtCapture.shared.active != nil { ThoughtCapture.shared.finish(.keyboardTookOver) }
        if source == .keyboard, startedForThought { keepSessionForDictation() }
        guard status == .ready || status == .recording, audio.isRunning || idlePaused else {
            reportDictationError(id: id, source: source, code: status == .interrupted ? .interrupted : .sessionNotReady)
            return .notReady
        }
        guard let apiKey = AppSettings.shared.apiKey else {
            reportDictationError(id: id, source: source, code: .noAPIKey)
            return .noAPIKey
        }
        if let current = dictation, !current.finishing {
            if current.source == .shortcut {
                Diag.log("dictation.shortcut.finishedByKeyboard", ["id": .s(current.shortID)])
                finishDictation(id: current.id)
            } else {
                cancelDictation(reason: "superseded")
            }
        }

        let pipeline = DictationPipeline(
            apiKey: apiKey,
            settings: AppSettings.shared.effectivePaply,
            recentRawDictations: HistoryStore.shared.recentRawDictations(),
            options: AppSettings.shared.testOptions.pipelineOptions
        )

        let (stream, continuation) = AsyncStream<TapFeed>.makeStream(bufferingPolicy: .unbounded)
        let feedTask = Task.detached(priority: .userInitiated) { [pipeline] in
            var reported = false
            for await item in stream {
                switch item {
                case .samples(let chunk):
                    await pipeline.append(chunk)
                    if !reported, await pipeline.speechDetected {
                        reported = true
                        await SessionController.shared.speechDetected(id: id)
                    }
                case .restart:
                    // Mikro wurde wegen digitaler Stille neu gestartet: stummen Anfang verwerfen
                    let dropped = await pipeline.discardSilentStart()
                    Diag.log("dictation.micRestart", ["id": .s(String(id.prefix(8))), "dropped": .b(dropped)])
                }
            }
        }
        let now = MonoClock.now()
        let entry = ActiveDictation(id: id, source: source, apiKey: apiKey, pipeline: pipeline, continuation: continuation, feedTask: feedTask, startedNs: now)
        entry.commandLatencyMs = commandLatencyMs
        dictation = entry

        if levelChannel == nil { levelChannel = LevelChannel.openWriter() }
        let prerollSamples = audio.processor.attach(owner: id, sink: { continuation.yield(.samples($0)) }, levels: levelChannel,
                                                    onRestart: { continuation.yield(.restart) })
        // Experiment: Engine war angehalten → im Hintergrund wieder starten (ohne Vorlauf).
        // Die Tastatur zeigt schon „Aufnahme“; bis zum ersten Sample kommt einfach nichts an.
        let resuming = idlePaused
        if resuming { resumeFromIdlePause(id: id) }

        status = .recording
        lastActivityAt = Date()
        active = ActiveInfo(id: id, source: source, startedAt: Date())
        shared.dictation = DictationStatus(id: id, source: source, phase: .recording, startedNs: now, speechDetected: false, errorCode: nil)
        publish()
        startWatchdog()
        Diag.log("dictation.start", [
            "id": .s(entry.shortID),
            "source": .s(source.rawValue),
            "prerollMs": .ms(Double(prerollSamples) / AudioTapProcessor.sampleRate * 1000),
            "cmdLatencyMs": .opt(commandLatencyMs),
            "app": .s(Self.appState),
            "levels": .b(levelChannel != nil),
            "fromIdlePause": .b(resuming),
        ])
        return .started
    }

    private func speechDetected(id: String) {
        noSpeechStreak.speechHeard()
        guard let current = dictation, current.id == id, !current.speechDetected else { return }
        current.speechDetected = true
        if shared.dictation?.id == id { shared.dictation?.speechDetected = true }
        publish()
        SharedIO.async { DarwinBus.shared.post(.speech) }
        // Vorwärmen erst bei echter Sprache (bloßes Durchschalten erzeugt keine Anfrage).
        // PaplyKit schickt dafür nur ein HEAD ohne Schlüssel. Höchstens alle 60 s: Eine
        // ungenutzte HTTP/2-Verbindung bleibt erfahrungsgemäß etwa eine Minute offen –
        // bei Diktaten in kürzerem Abstand steht sie noch, danach lohnt der neue Aufbau.
        let prewarm = lastPrewarmNs == 0 || MonoClock.msSince(lastPrewarmNs) > 60_000
        if prewarm {
            lastPrewarmNs = MonoClock.now()
            let apiKey = current.apiKey
            Task.detached(priority: .userInitiated) { await GroqConnection.prewarm(apiKey: apiKey) }
        }
        Diag.log("dictation.speech", ["id": .s(current.shortID), "afterMs": .ms(MonoClock.msSince(current.startedNs)), "prewarm": .b(prewarm)])
    }

    func finishDictation(id: String, asPending: Bool = false) {
        guard let entry = dictation, entry.id == id, !entry.finishing else {
            if let result = SharedStore.readResult(id: id) {
                // Ergebnis liegt schon da (Notification verpasst?) – nochmal melden
                Diag.log("dictation.finish.repost", ["id": .s(String(result.dictationID.prefix(8)))])
                SharedIO.async { DarwinBus.shared.post(.result) }
            } else {
                Diag.log("dictation.finish.unknown", ["id": .s(String(id.prefix(8)))])
            }
            return
        }
        entry.finishing = true
        entry.deliverAsPending = asPending
        inFlight[id] = entry
        let finishReceivedNs = MonoClock.now()
        if shared.dictation?.id == id { shared.dictation?.phase = .processing }
        processingCount += 1
        publish()

        Task {
            // Letzte Audio-Blöcke abwarten: Ein Block, der nach dem Tipp ankommt, enthält das Ende.
            let flushMs = await waitForFlush(after: finishReceivedNs + 20_000_000, maxMs: 300)
            entry.micStats = audio.processor.detach(owner: id)
            entry.continuation.finish()
            if dictation === entry {
                dictation = nil
                active = nil
                if status == .recording { status = .ready }
                stopWatchdog()
                publish()
                schedulePauseIfIdle(reason: "dictation-end")
            }
            await entry.feedTask.value
            let outcome = await entry.pipeline.finish()
            let canRetry = await entry.pipeline.canRetry
            deliver(outcome, for: entry, canRetry: canRetry, flushMs: flushMs, finishReceivedNs: finishReceivedNs)
        }
    }

    func cancelDictation(reason: String) {
        guard let entry = dictation else { return }
        let micStats = audio.processor.detach(owner: entry.id)
        entry.continuation.finish()
        entry.feedTask.cancel()
        let pipeline = entry.pipeline
        Task.detached { await pipeline.cancel() }
        dictation = nil
        active = nil
        if status == .recording { status = .ready }
        if shared.dictation?.id == entry.id { shared.dictation?.phase = .cancelled }
        stopWatchdog()
        publish()
        schedulePauseIfIdle(reason: "dictation-cancel")
        var cancelFields: DiagFields = [
            "id": .s(entry.shortID),
            "source": .s(entry.source.rawValue),
            "reason": .s(reason),
            "speech": .b(entry.speechDetected),
            "ms": .ms(MonoClock.msSince(entry.startedNs)),
        ]
        cancelFields.merge(micStats?.diagFields ?? [:]) { a, _ in a }
        Diag.log("dictation.cancel", cancelFields)
        if entry.source == .shortcut {
            ShortcutBridge.dictationCancelled(id: entry.id)
        }
    }

    private func waitForFlush(after targetNs: UInt64, maxMs: Double) async -> Double {
        let start = MonoClock.now()
        while audio.processor.lastArrivalNs < targetNs, MonoClock.msSince(start) < maxMs {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return MonoClock.msSince(start)
    }

    private func deliver(_ outcome: DictationOutcome, for entry: ActiveDictation, canRetry: Bool, flushMs: Double, finishReceivedNs: UInt64) {
        processingCount = max(0, processingCount - 1)
        inFlight[entry.id] = nil
        let t = outcome.timings
        let net = NetworkMonitor.shared.current
        let timings = ResultTimings(
            transcriptionDoneMs: t.transcriptionDoneMs,
            polishDoneMs: t.polishDoneMs,
            totalMs: t.totalMs,
            chunkCount: t.chunkCount,
            uploadedBytes: t.uploadedBytes,
            audioSeconds: t.audioSeconds,
            flushMs: flushMs,
            commandLatencyMs: entry.commandLatencyMs,
            model: entry.model,
            chunked: entry.chunked,
            net: net,
            options: entry.options
        )
        // „Nichts verstanden“ kommt nicht in den Verlauf.
        if !outcome.noSpeech, !outcome.raw.isEmpty || outcome.errorMessage != nil {
            HistoryStore.shared.add(id: entry.id, source: entry.source, outcome: outcome, timings: timings, retries: entry.retries)
        }
        // Nichts erkannt, weil das Mikro stumm war (nur digitale Stille): ehrlich sagen, nicht „Nichts verstanden“
        let silentMic = outcome.noSpeech && (entry.micStats?.wasSilent == true || micRestartCause == .silent)
        // Abgeschlossenes Diktat (nicht: Neuversuch) für „zweimal nichts verstanden“. true = Sitzung
        // ist jetzt „muss neu starten“ (App nicht vorne) → die Tastatur bietet den Neustart an.
        let micRestart = entry.retries == 0 && !silentMic
            && completedRecording(speech: entry.speechDetected, seconds: t.audioSeconds, kind: "dictation") == .marked
        if outcome.noSpeech {
            Diag.log("dictation.noSpeech", ["id": .s(entry.shortID), "source": .s(entry.source.rawValue),
                                            "audioS": .d((t.audioSeconds * 10).rounded() / 10), "micSilent": .b(silentMic)])
        }
        // Scheiterte es und hat die Pipeline das Audio noch, für „Erneut versuchen“ behalten
        // (nur Tastatur, max. 10 Min). Sonst Audio sofort freigeben – das Ergebnis bleibt.
        let keepForRetry = canRetry && entry.source == .keyboard && !entry.deliverAsPending
        if keepForRetry {
            retain(entry)
        } else {
            let pipeline = entry.pipeline
            Task.detached { await pipeline.releaseAudio() }
        }
        switch entry.source {
        case .keyboard where entry.deliverAsPending:
            // Tastatur war schon weg: nicht einsetzen, beim nächsten 🌐 einmal anbieten
            if !outcome.text.isEmpty {
                let pending = PendingText(id: entry.id, text: outcome.text, createdAt: Date())
                SharedIO.async { SharedStore.write(pending, .pendingText) }
            }
            Diag.log("dictation.deferred", ["id": .s(entry.shortID), "textLen": .i(outcome.text.count)])
        case .keyboard:
            let result = DictationResult(
                dictationID: entry.id,
                text: outcome.text,
                errorMessage: outcome.errorMessage,
                timings: timings,
                unpolished: outcome.polishError != nil,
                retryable: keepForRetry,
                noSpeech: outcome.noSpeech,
                micSilent: silentMic ? true : nil,
                micRestart: micRestart ? true : nil,
                finishReceivedNs: finishReceivedNs,
                writtenNs: MonoClock.now()
            )
            SharedIO.async {
                SharedStore.pruneResults() // nicht abgeholte Texte nicht liegen lassen
                SharedStore.writeResult(result)
                DarwinBus.shared.post(.result)
            }
        case .shortcut:
            ShortcutBridge.deliver(outcome, id: entry.id)
        }
        if shared.dictation?.id == entry.id {
            shared.dictation?.phase = outcome.errorMessage == nil ? .done : .failed
        }
        lastActivityAt = Date()
        publish()
        var fields: DiagFields = [
            "id": .s(entry.shortID),
            "source": .s(entry.source.rawValue),
            "textLen": .i(outcome.text.count),
            "rawLen": .i(outcome.raw.count),
            "polishedLen": .i(outcome.polished?.count ?? -1),
            "rejected": .opt(outcome.polishRejection),
            "error": .opt(outcome.errorMessage),
            "langs": .s(outcome.languages.joined(separator: ",")),
            // Sprachwache je Teil: auto (erkannt), short (direkt mitgeschickt), redo (neu), redo-failed, fixed
            "langGuard": .s(outcome.languageSources.joined(separator: ",")),
            "speech": .b(entry.speechDetected),
            "audioS": .d((t.audioSeconds * 10).rounded() / 10),
            "chunks": .i(t.chunkCount),
            "bytes": .i(t.uploadedBytes),
            "flushMs": .ms(flushMs),
            "transcribeMs": .opt(t.transcriptionDoneMs),
            "polishMs": .opt(t.polishDoneMs),
            "totalMs": .opt(t.totalMs),
            "appTotalMs": .ms(MonoClock.msSince(finishReceivedNs)),
            "model": .s(entry.model),
            "chunked": .b(entry.chunked),
            "net": .s(net),
            "opts": .s(entry.options),
            "polishError": .opt(outcome.polishError),
            "polishModel": .opt(outcome.polishModel),
            "noSpeech": .b(outcome.noSpeech),
            "retries": .i(entry.retries),
            "keptForRetry": .b(keepForRetry),
            // Pegel, die für die Tastatur geschrieben wurden (zuletzt angehängtes Diktat)
            "levelsWritten": .i(Int(levelChannel?.count ?? 0)),
            "deferred": .b(entry.deliverAsPending),
            "app": .s(Self.appState),
            "micSilent": .b(silentMic),
            "micRestart": .b(micRestart),
        ]
        fields.merge(audio.tapFields) { a, _ in a }
        // Pegel der Rohpuffer dieser Aufnahme (dBFS, −160 = exakt 0) und Zahl der Null-Puffer
        fields.merge(entry.micStats?.diagFields ?? [:]) { a, _ in a }
        Diag.log("dictation.result", fields)
    }

    // MARK: Experiment: Mikro im Leerlauf pausieren

    /// Engine anhalten, wenn das Experiment an ist, nichts aufnimmt und die App nicht vorne
    /// ist. Läuft eine Runde später, damit ein direkt folgendes Diktat (z. B. nach
    /// „superseded“) nicht erst angehalten und gleich wieder gestartet wird.
    func schedulePauseIfIdle(reason: String) {
        let mode = AppSettings.shared.idlePause
        guard mode != .off else { return }
        pauseTask?.cancel()
        pauseTask = Task {
            await Task.yield()
            guard !Task.isCancelled, status == .ready, dictation == nil, !idlePaused, !isThoughtActive,
                  UIApplication.shared.applicationState != .active
            else { return }
            idlePaused = true
            let begin = MonoClock.now()
            await audio.pauseInput(mode)
            Diag.log("session.idlePause", [
                "mode": .s(mode.rawValue), "reason": .s(reason), "ms": .ms(MonoClock.msSince(begin)),
                "engine": .b(audio.isRunning), "app": .s(Self.appState),
            ])
        }
    }

    /// Diktat startet bei angehaltener Engine: im Hintergrund wieder anwerfen. Gemessen wird
    /// die Dauer bis die Engine läuft und bis das erste Sample ankommt. Scheitert es, gilt
    /// „Mikro aus“ wie bei einer Unterbrechung (Tastatur zeigt es bzw. öffnet die App).
    private func resumeFromIdlePause(id: String) {
        pauseTask?.cancel()
        idlePaused = false
        let mode = AppSettings.shared.idlePause
        Task {
            let begin = MonoClock.now()
            let outcome = await audio.resumeInput()
            let startMs = MonoClock.msSince(begin)
            switch outcome {
            case .success:
                // erstes Sample abwarten (max. 2 s)
                while audio.processor.lastArrivalNs < begin, MonoClock.msSince(begin) < 2_000 {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                let gotSample = audio.processor.lastArrivalNs >= begin
                Diag.log("session.resumeFromPause", [
                    "ok": .b(gotSample), "mode": .s(mode.rawValue), "startMs": .ms(startMs),
                    "firstSampleMs": gotSample ? .ms(MonoClock.ms(from: begin, to: audio.processor.lastArrivalNs)) : .null,
                    "id": .s(String(id.prefix(8))), "app": .s(Self.appState),
                ])
                if !gotSample { failResume(id: id, reason: "no-samples") }
            case .failure(let error):
                Diag.log("session.resumeFromPause", [
                    "ok": .b(false), "mode": .s(mode.rawValue), "startMs": .ms(startMs),
                    "stage": .s(error.stage), "code": .i(error.code), "fourCC": .s(error.fourCC),
                    "id": .s(String(id.prefix(8))), "app": .s(Self.appState),
                ])
                failResume(id: id, reason: "start-failed")
            }
        }
    }

    private func failResume(id: String, reason: String) {
        // Erst „unterbrochen“ setzen, dann verwerfen: Die Tastatur sieht beides in einem Stand
        status = .interrupted
        detail = "Mikro aus – Paply einmal öffnen"
        if dictation?.id == id { cancelDictation(reason: "resume-\(reason)") } else { publish() }
    }

    // MARK: Erneut versuchen

    private func retain(_ entry: ActiveDictation) {
        retained[entry.id]?.expiry?.cancel()
        retained[entry.id] = entry
        let id = entry.id
        entry.expiry = Task {
            try? await Task.sleep(for: .seconds(Self.retainSeconds))
            guard !Task.isCancelled else { return }
            releaseRetained(id: id, reason: "expired")
        }
    }

    private func releaseRetained(id: String, reason: String) {
        guard let entry = retained.removeValue(forKey: id) else { return }
        entry.expiry?.cancel()
        let pipeline = entry.pipeline
        Task.detached { await pipeline.releaseAudio() }
        Diag.log("dictation.retry.released", ["id": .s(entry.shortID), "reason": .s(reason)])
    }

    /// „Erneut versuchen“ aus der Tastatur: dieselbe Pipeline sendet das ganze Audio nochmal.
    private func retryDictation(id: String) {
        let now = MonoClock.now()
        guard let entry = retained.removeValue(forKey: id) else {
            Diag.log("dictation.retry.unknown", ["id": .s(String(id.prefix(8)))])
            // Tastatur nicht warten lassen
            let result = DictationResult(
                dictationID: id, text: "", errorMessage: "Dieses Diktat ist nicht mehr da – bitte neu sprechen.",
                timings: ResultTimings(), retryable: false, finishReceivedNs: now, writtenNs: now
            )
            SharedIO.async {
                SharedStore.writeResult(result)
                DarwinBus.shared.post(.result)
            }
            return
        }
        entry.expiry?.cancel()
        entry.expiry = nil
        entry.retries += 1
        inFlight[id] = entry
        processingCount += 1
        if shared.dictation?.id == id { shared.dictation?.phase = .processing }
        publish()
        Diag.log("dictation.retry", ["id": .s(entry.shortID), "attempt": .i(entry.retries), "net": .s(NetworkMonitor.shared.current)])
        Task {
            let outcome = await entry.pipeline.retry()
            let canRetry = await entry.pipeline.canRetry
            deliver(outcome, for: entry, canRetry: canRetry, flushMs: 0, finishReceivedNs: now)
        }
    }

    private func reportDictationError(id: String, source: DictationSource, code: DictationErrorCode) {
        shared.dictation = DictationStatus(id: id, source: source, phase: .failed, startedNs: MonoClock.now(), speechDetected: false, errorCode: code)
        publish()
        Diag.log("dictation.refused", ["id": .s(String(id.prefix(8))), "source": .s(source.rawValue), "code": .s(code.rawValue), "status": .s(status.rawValue)])
    }

    // MARK: Tastatur (Darwin)

    private func handleKeyboardCommand() {
        guard let command = SharedStore.read(KeyboardCommand.self, .keyboardCommand), command.sentNs > lastCommandNs else { return }
        lastCommandNs = command.sentNs
        let now = MonoClock.now()
        markKeyboardContact(now)
        let latency = MonoClock.ms(from: command.sentNs, to: now)
        Diag.log("cmd.\(command.action.rawValue)", [
            "id": .s(String(command.dictationID.prefix(8))),
            "latencyMs": .ms(latency),
            "status": .s(status.rawValue),
            "app": .s(Self.appState),
        ])
        switch command.action {
        case .record:
            if let current = dictation, current.id == command.dictationID {
                publish() // schon dabei (z. B. nach Start per URL) – nur bestätigen
            } else {
                beginDictation(id: command.dictationID, source: .keyboard, commandLatencyMs: latency)
            }
        case .finish:
            finishDictation(id: command.dictationID)
        case .finishLater:
            deferDictation(id: command.dictationID)
        case .retry:
            retryDictation(id: command.dictationID)
        case .cancel:
            if dictation?.id == command.dictationID {
                cancelDictation(reason: "keyboard")
            } else {
                releaseRetained(id: command.dictationID, reason: "discarded")
            }
        }
    }

    /// Tastatur verschwand nach erkannter Sprache (oder beim Polieren): Ergebnis nicht
    /// einsetzen, sondern in den Verlauf und als wartenden Text für das nächste 🌐.
    private func deferDictation(id: String) {
        if let entry = dictation, entry.id == id, !entry.finishing {
            finishDictation(id: id, asPending: true)
        } else if let entry = inFlight[id] {
            entry.deliverAsPending = true
        } else {
            // Ergebnis kam evtl. schon, wurde aber nicht mehr abgeholt
            SharedIO.async {
                guard let result = SharedStore.readResult(id: id) else { return }
                SharedStore.removeResult(id: id)
                if !result.text.isEmpty {
                    SharedStore.write(PendingText(id: id, text: result.text, createdAt: Date()), .pendingText)
                }
                Diag.log("dictation.deferred", ["id": .s(String(id.prefix(8))), "textLen": .i(result.text.count), "late": .b(true)])
            }
        }
    }

    private func handlePing() {
        let now = MonoClock.now()
        markKeyboardContact(now)
        shared.pongNs = now
        publish(signal: false)
        SharedIO.async { DarwinBus.shared.post(.pong) }
    }

    private func markKeyboardContact(_ ns: UInt64) {
        // Nach Start per URL läuft eine Schonfrist (Kontakt liegt in der Zukunft) – nicht verkürzen.
        if ns > lastKeyboardContactNs { lastKeyboardContactNs = ns }
    }

    /// Wächter: Tastatur-Diktat ohne Lebenszeichen (Ping alle 2 s) → verwerfen.
    private func startWatchdog() {
        guard watchdogTask == nil else { return }
        watchdogTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let entry = dictation, entry.source == .keyboard, !entry.finishing else { continue }
                if MonoClock.ms(from: lastKeyboardContactNs, to: MonoClock.now()) > 10_000 {
                    cancelDictation(reason: "keyboard-silent")
                }
            }
        }
    }

    private func stopWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    // MARK: Schnelltaste aus dem Widget-Prozess

    private func handleShortcutSignal() {
        guard let command = SharedStore.read(ShortcutCommand.self, .shortcutCommand), command.seq > lastShortcutSeq else { return }
        lastShortcutSeq = command.seq
        Diag.log("shortcut.signal", ["latencyMs": .ms(MonoClock.msSince(command.sentNs)), "app": .s(Self.appState)])
        Task {
            let outcome = await ShortcutBridge.toggle(trigger: "widget-forward")
            let ack: ShortcutAck
            switch outcome {
            case .started: ack = ShortcutAck(seq: command.seq, outcome: .started, detail: nil, ackNs: MonoClock.now())
            case .stopped: ack = ShortcutAck(seq: command.seq, outcome: .stopped, detail: nil, ackNs: MonoClock.now())
            case .needsForeground(let text), .failed(let text):
                ack = ShortcutAck(seq: command.seq, outcome: .failed, detail: text, ackNs: MonoClock.now())
            }
            SharedIO.async {
                SharedStore.write(ack, .shortcutAck)
                DarwinBus.shared.post(.shortcutAck)
            }
        }
    }

    // MARK: URL (aus der Tastatur oder als Ausweg der Schnelltaste)

    func handleURL(_ url: URL) {
        guard url.scheme == PaplyURL.scheme else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let source = query["src"] ?? "?"
        var fields: DiagFields = [
            "path": .s("\(url.host ?? "")\(url.path)"),
            "src": .s(source),
            "app": .s(Self.appState),
            "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: MonoClock.now())),
        ]
        if let sent = query["t"].flatMap(UInt64.init) {
            fields["urlLatencyMs"] = .ms(MonoClock.msSince(sent))
        }
        Diag.log("url.open", fields)

        // Kam die App gerade erst nach vorne (aus der Tastatur einer anderen App), den
        // Aufblitz-Bildschirm zeigen. War sie schon offen (Tastatur in Paply selbst, z. B.
        // Testseite), still im Hintergrund starten – sonst deckte er die Oberfläche zu.
        let cameForward = UIApplication.shared.applicationState != .active
            || lastActivatedAt.map { Date().timeIntervalSince($0) < 2 } ?? true
        switch (url.host ?? "", url.path) {
        case ("session", "/start"):
            if cameForward { flash = .starting }
            Task {
                // Erst starten, wenn die App wirklich aktiv ist (Vorfall 27.10.2026, siehe waitUntilActive)
                await waitUntilActive(trigger: "url-\(source)")
                let ok = await startSession(trigger: "url-\(source)")
                guard ok else {
                    flash = .failed(detail ?? "Mikro ließ sich nicht starten")
                    return
                }
                var dictating = false
                if source == "kb", let id = query["id"], !id.isEmpty, dictation?.id != id {
                    switch beginDictation(id: id, source: .keyboard) {
                    case .started:
                        dictating = true
                        // Schonfrist: 60 s, bis die Tastatur wieder erscheint und sich meldet
                        lastKeyboardContactNs = MonoClock.now() + 50_000_000_000
                    case .noAPIKey:
                        flash = .failed("Bitte zuerst deinen Groq-Schlüssel in den Einstellungen eintragen.")
                        return
                    case .notReady:
                        flash = .failed(detail ?? "Das Mikro ist nicht bereit. Bitte nochmal versuchen.")
                        return
                    }
                } else if source == "shortcut" {
                    dictating = await ShortcutBridge.toggle(trigger: "url") == .started
                }
                // „Mikro ist an“ erst, wenn echter Ton kommt – so lange bleibt „Mikro startet …“ stehen
                // (meist 0,1–0,3 s). Ist es stumm, startet die Stille-Erkennung es hier im Vordergrund neu.
                let live = await waitForLiveMic(trigger: "url-\(source)")
                let stillFront = UIApplication.shared.applicationState == .active
                if live {
                    flash = cameForward && stillFront ? .running(dictating: dictating) : nil
                } else {
                    flash = cameForward && stillFront
                        ? .failed("Das Mikro liefert keinen Ton. Läuft gerade ein Anruf oder eine andere Aufnahme? Sonst Paply einmal ganz schließen und neu öffnen.")
                        : nil
                }
            }
        case ("session", "/stop"):
            stopSession(reason: "url")
        default:
            break
        }
    }

    // MARK: Totes Mikro (Vorfall 27.10.2026)
    //
    // Der Motor lief, die Tap-Puffer kamen pünktlich – aber kein Diktat und kein Gedanke fand Sprache.
    // Einziger Unterschied zu allen anderen Sitzungen des Tages: Sie startete per URL aus der Tastatur,
    // während die App noch „inactive“ war und gerade erst nach vorne kam. Deshalb:
    // 1. Start per URL erst, wenn die App aktiv ist, und „Mikro ist an“ erst bei echtem Ton.
    // 2. Liefert der laufende Motor 1,5 s nur digitale Stille, gilt das Mikro als tot: vorne sofort
    //    neu starten (laufende Aufnahme läuft nahtlos weiter), im Hintergrund „muss neu starten“.

    /// Start per URL aus der Tastatur: Die App ist dabei erst „inactive“ (sie kommt gerade nach vorne;
    /// `url.open` kam im Vorfall sogar vor `willEnterForeground`). Eine Aufnahme, die in diesem Moment
    /// startet, kann iOS stumm lassen. Darum warten, bis die App aktiv ist – typisch 0,3–0,5 s, der
    /// Aufblitz-Bildschirm steht dabei schon. Wird sie es nicht (Nutzer ist schon weg), nach 3 s
    /// trotzdem starten; dann greift die Stille-Erkennung.
    private func waitUntilActive(trigger: String) async {
        guard UIApplication.shared.applicationState != .active else { return }
        let begin = MonoClock.now()
        let from = Self.appState
        while UIApplication.shared.applicationState != .active, MonoClock.msSince(begin) < 3_000 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        Diag.log("session.waitActive", [
            "trigger": .s(trigger), "from": .s(from), "app": .s(Self.appState), "ms": .ms(MonoClock.msSince(begin)),
        ])
    }

    /// Nach dem Start im Vordergrund: Kommt echter Ton? Wartet höchstens 5 s – genug für die
    /// 1,5-s-Erkennung, einen Neustart und dessen erste Puffer. Ein gesundes Mikro liefert seinen
    /// ersten echten Puffer nach 0,1–0,3 s.
    private func waitForLiveMic(trigger: String) async -> Bool {
        let begin = MonoClock.now()
        var live = false
        while MonoClock.msSince(begin) < 5_000, status != .off {
            // echter Ton seit dem letzten Motorstart, und gerade keine längere Stille
            if !micSilent, audio.processor.heardSignal, audio.processor.silentMs < 500 {
                live = true
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        Diag.log("session.micCheck", [
            "trigger": .s(trigger), "live": .b(live), "ms": .ms(MonoClock.msSince(begin)),
            "restarts": .i(silenceRestarts.count), "app": .s(Self.appState), "mic": .s(Self.micPermission),
        ])
        return live
    }

    private func logEngineStart(reason: String, rate: Double, channels: Int) {
        Diag.log("audio.engineStart", [
            "reason": .s(reason), "app": .s(Self.appState), "mic": .s(Self.micPermission),
            "status": .s(status.rawValue), "inRate": .d(rate), "inCh": .i(channels),
        ])
    }

    private func handleMicSilence(_ change: MicSilenceDetector.Change) {
        var fields: DiagFields = [
            "app": .s(Self.appState), "mic": .s(Self.micPermission), "status": .s(status.rawValue),
            "dictating": .b(dictation != nil), "thought": .b(isThoughtActive), "idlePaused": .b(idlePaused),
        ]
        fields.merge(audio.routeFields) { a, _ in a }
        fields.merge(audio.tapFields) { a, _ in a }
        switch change {
        case .becameSilent:
            Diag.log("audio.micSilent", fields)
            // Unterbrechung o. Ä. hat schon übernommen, oder die Engine ist absichtlich angehalten
            guard status == .ready || status == .recording, !idlePaused else { return }
            if UIApplication.shared.applicationState == .active {
                restartSilentMic(trigger: "detected")
            } else {
                // Hintergrund: Neustart nicht erlaubt. „inactive“: didBecomeActive startet gleich neu.
                markMicSilent(reason: Self.appState)
            }
        case .becameAlive:
            Diag.log("audio.micAlive", fields)
            // Ton kam von selbst zurück (z. B. nach Siri): Markierung aufheben
            guard micRestartCause == .silent, status == .interrupted, silenceRestartTask == nil else { return }
            micRestartCause = nil
            status = dictation == nil ? .ready : .recording
            detail = nil
            publish()
        }
    }

    /// Vordergrund: Mikro sofort neu starten (Sitzung ab- und wieder anmelden, neue Engine). Eine
    /// laufende Aufnahme verwirft ihren stummen Ton und läuft nahtlos weiter. Höchstens zwei
    /// Neustarts je Minute – liefert das Mikro dann immer noch nichts, ehrlich „muss neu starten“.
    private func restartSilentMic(trigger: String, cause: MicRestartCause = .silent) {
        guard silenceRestartTask == nil, status != .off else { return }
        let now = MonoClock.now()
        silenceRestarts = silenceRestarts.filter { MonoClock.ms(from: $0, to: now) < 60_000 }
        guard silenceRestarts.count < Self.maxSilenceRestartsPerMinute else {
            Diag.log("audio.micSilent.giveUp", ["restarts": .i(silenceRestarts.count), "app": .s(Self.appState)])
            markMicSilent(reason: "restarts-exhausted", cause: cause)
            return
        }
        silenceRestarts.append(now)
        pauseTask?.cancel()
        let attempt = silenceRestarts.count
        silenceRestartTask = Task {
            let begin = MonoClock.now()
            // Nur digitale Stille verwirft den Anfang einer laufenden Aufnahme; bei „nichts verstanden“
            // liefert das Mikro Ton – davon darf nichts verloren gehen.
            let outcome = await audio.restartFresh(discardRecording: cause == .silent)
            var fields: DiagFields = [
                "trigger": .s(trigger), "attempt": .i(attempt), "ms": .ms(MonoClock.msSince(begin)),
                "app": .s(Self.appState), "mic": .s(Self.micPermission),
                "dictating": .b(dictation != nil), "thought": .b(isThoughtActive),
            ]
            switch outcome {
            case .success:
                micRestartCause = nil
                idlePaused = false
                if status != .off {
                    status = dictation == nil ? .ready : .recording
                    detail = nil
                }
                fields["ok"] = .b(true)
                Diag.log("audio.micSilent.restart", fields)
                silenceRestartTask = nil
                publish()
            case .failure(let error):
                fields["ok"] = .b(false)
                fields["stage"] = .s(error.stage)
                fields["code"] = .i(error.code)
                fields["fourCC"] = .s(error.fourCC)
                Diag.log("audio.micSilent.restart", fields)
                silenceRestartTask = nil
                markMicSilent(reason: "restart-failed", cause: cause)
            }
        }
    }

    enum StreakOutcome {
        case none, restarted, marked
    }

    /// Abgeschlossene Aufnahme (Diktat per „fertig“, Gedanke per „Fertig“) für die Regel „zweimal
    /// nichts verstanden“ (`NoSpeechStreak`). Abbrechen, Wischen und Durchschalten melden nichts.
    /// Löst die Regel aus: App vorne → Motor sofort neu starten; sonst „muss neu starten“ markieren
    /// (Tastatur öffnet beim nächsten 🌐 die App, ein Gedanke startet beim nächsten Druck neu).
    @discardableResult
    func completedRecording(speech: Bool, seconds: Double, kind: String) -> StreakOutcome {
        let now = Double(MonoClock.now()) / 1_000_000_000
        guard noSpeechStreak.completed(speech: speech, seconds: seconds, now: now) else { return .none }
        let fields: DiagFields = [
            "kind": .s(kind), "seconds": .d((seconds * 10).rounded() / 10), "app": .s(Self.appState),
            "status": .s(status.rawValue), "marked": .b(micSilent),
        ]
        Diag.log("session.noSpeechStreak", fields)
        // Läuft schon die nächste Aufnahme, nicht dazwischenfunken: scharf lassen, die nächste
        // abgeschlossene Aufnahme ohne Sprache löst im Leerlauf aus.
        if dictation != nil || isThoughtActive {
            noSpeechStreak.keepArmed(now: now)
            Diag.log("session.noSpeechStreak.deferred", ["kind": .s(kind)])
            return .none
        }
        guard status == .ready || status == .recording, !micSilent, silenceRestartTask == nil else { return .none }
        if UIApplication.shared.applicationState == .active {
            restartSilentMic(trigger: "no-speech", cause: .noSpeech)
            return .restarted
        }
        markMicSilent(reason: "no-speech-streak", cause: .noSpeech)
        return .marked
    }

    /// Sprache in einem Gedanken erkannt (setzt „zweimal nichts verstanden“ zurück).
    func noteSpeechHeard() {
        noSpeechStreak.speechHeard()
    }

    /// Mikro stumm und kein Neustart möglich: Die Sitzung „muss neu starten“. Die Tastatur nimmt
    /// beim nächsten 🌐 den Weg „App kurz öffnen“; ein laufendes Diktat endet mit „Mikro war stumm“
    /// (statt „Nichts verstanden“), ein laufender Gedanke wird gesichert und beendet.
    private func markMicSilent(reason: String, cause: MicRestartCause = .silent) {
        guard status != .off else { return }
        micRestartCause = cause
        status = .interrupted
        detail = reason == "restarts-exhausted" ? "Mikro hängt – Paply einmal schließen und neu öffnen"
            : cause == .silent ? "Mikro war stumm – Paply startet neu" : "Zweimal nichts verstanden – Paply startet das Mikro neu"
        Diag.log("session.micSilent", ["reason": .s(reason), "cause": .s(cause.rawValue), "app": .s(Self.appState),
                                        "dictating": .b(dictation != nil), "thought": .b(isThoughtActive)])
        if ThoughtCapture.shared.active != nil { ThoughtCapture.shared.finish(.micSilent) }
        // Erst den Status setzen, dann verwerfen: Die Tastatur sieht beides in einem Stand
        if dictation != nil { cancelDictation(reason: "mic-silent") }
        publish()
    }

    // MARK: Gemeinsamer Zustand

    private func publish(signal: Bool = true) {
        shared.status = status
        shared.sessionID = sessionID
        shared.startedAt = startedAt
        shared.lastActivityAt = lastActivityAt
        shared.holdUntil = holdUntil
        shared.pid = getpid()
        shared.updatedNs = MonoClock.now()
        shared.hasAPIKey = AppSettings.shared.hasAPIKey
        shared.detail = detail
        shared.micSilent = micSilent ? true : nil
        shared.micNoSpeech = micRestartCause == .noSpeech ? true : nil
        let snapshot = shared
        SharedIO.async {
            SharedStore.write(snapshot, .session)
            if signal { DarwinBus.shared.post(.state) }
        }
    }

    /// Nach Änderung des Schlüssels o. Ä. den Zustand neu veröffentlichen.
    func refreshShared() {
        publish()
    }

    // MARK: Schutz vor Systemhinweisen (nur während einer Aufnahme)

    /// Einzige Stelle, die den Schutz schaltet. Aufgerufen nach jedem Wechsel von `dictation` und
    /// `ThoughtCapture.active` (je per `didSet`). An, solange ein Diktat oder ein Gedanke aufnimmt –
    /// ein Anruf-Banner bricht die Aufnahme dann nicht ab. Sonst aus: In Bereitschaft unterbricht ein
    /// Anruf die Sitzung normal, mit Klingelton und Vibration (Gerätefund 28.10.).
    func syncAlertShield(reason: String) {
        let on = dictation != nil || isThoughtActive
        guard on != alertShieldOn else { return }
        alertShieldOn = on
        audio.setShieldFromAlerts(on)
        Diag.log("audio.alertShield", ["on": .b(on), "reason": .s(reason), "app": .s(Self.appState)])
    }

    // MARK: Haushalt (Bereithalte-Dauer, Messwerte)

    private func startHousekeeping() {
        housekeepingTask?.cancel()
        lastHousekeepingTick = Date()
        housekeepingTask = Task {
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                ticks += 1
                // War der Prozess ausgesetzt (z. B. ohne laufende Engine), kommt der Takt verspätet
                let gap = Date().timeIntervalSince(lastHousekeepingTick)
                lastHousekeepingTick = Date()
                if gap > 120 {
                    Diag.log("app.wasSuspended", ["gapS": .d(gap.rounded()), "idlePaused": .b(idlePaused)])
                }
                SharedIO.async { Self.removeStalePending() }
                if let until = holdUntil, Date() >= until, dictation == nil, processingCount == 0, !isThoughtActive, status != .off {
                    stopSession(reason: "hold-expired")
                    return
                }
                if status == .ready || status == .recording, !idlePaused {
                    await audio.refresh()
                    if !audio.isRunning {
                        Diag.log("engine.notRunning", ["status": .s(status.rawValue), "app": .s(Self.appState)])
                    }
                }
                if ticks % 10 == 0 { monitor.logMetrics(reason: "periodic") }
            }
        }
    }

    var metricsFields: DiagFields {
        var fields: DiagFields = ["status": .s(status.rawValue), "app": .s(Self.appState)]
        fields.merge(audio.tapFields) { a, _ in a }
        fields.merge(audio.routeFields) { a, _ in a }
        return fields
    }

    // MARK: Audio-Ereignisse

    private func registerAudioObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            let info = note.userInfo
            let type = info?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let reason = info?[AVAudioSessionInterruptionReasonKey] as? UInt
            let options = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                SessionController.shared.handleInterruption(type: type, reason: reason, options: options)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                SessionController.shared.handleRouteChange(reason: reason)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated { SessionController.shared.handleMediaServicesReset() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereLostNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated { Diag.log("audio.mediaServicesLost", ["status": .s(SessionController.shared.status.rawValue)]) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SessionController.shared.handleEngineConfigurationChange() }
        })
    }

    private func handleInterruption(type: UInt, reason: UInt?, options: UInt) {
        let began = type == AVAudioSession.InterruptionType.began.rawValue
        let reasonName: String = switch reason.flatMap(AVAudioSession.InterruptionReason.init(rawValue:)) {
        case .default?: "default"
        case .builtInMicMuted?: "builtInMicMuted"
        case .routeDisconnected?: "routeDisconnected"
        case nil: reason.map { "raw\($0)" } ?? "none"
        default: "raw\(reason ?? 0)"
        }
        if began {
            // Stand vor dem Beenden der Aufnahme (danach ist der Schutz schon aus)
            let shieldWasOn = alertShieldOn
            // Gedanken-Haken: bei Unterbrechung sichern (anders als beim Diktat nie verwerfen)
            if ThoughtCapture.shared.active != nil { ThoughtCapture.shared.finish(.interruption) }
            Diag.log("audio.interruption.began", [
                "reason": .s(reasonName), "status": .s(status.rawValue), "app": .s(Self.appState), "engine": .b(audio.isRunning),
                "alertShield": .b(shieldWasOn),
            ])
            if dictation != nil { cancelDictation(reason: "interruption") }
            if status != .off {
                status = .interrupted
                detail = "Unterbrochen"
                publish()
            }
            Task { await audio.refresh() }
        } else {
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            Diag.log("audio.interruption.ended", [
                "shouldResume": .b(shouldResume), "status": .s(status.rawValue), "app": .s(Self.appState), "engine": .b(audio.isRunning),
            ])
            if status == .interrupted { attemptResume(trigger: "interruption-ended", attempt: 1) }
        }
    }

    /// Nach einer Unterbrechung selbst wieder anlaufen (auch im Hintergrund). Erfolg oder
    /// Fehlercode wird protokolliert; nach drei Versuchen bleibt der Zustand „unterbrochen“.
    func attemptResume(trigger: String, attempt: Int) {
        // Stummes Mikro bei laufender Engine: Ein bloßes Fortsetzen hilft nicht – nur ein Neustart,
        // und den erlaubt iOS nur im Vordergrund (dort übernimmt `didBecomeActive`).
        if micSilent, audio.isRunning {
            if UIApplication.shared.applicationState == .active { restartSilentMic(trigger: trigger, cause: micRestartCause ?? .silent) }
            return
        }
        resumeTask?.cancel()
        resumeTask = Task {
            let begin = MonoClock.now()
            let outcome = await audio.resume() // auf der Audio-Queue
            guard status == .interrupted else { return } // inzwischen anders gelöst (z. B. neu gestartet)
            switch outcome {
            case .success:
                status = dictation == nil ? .ready : .recording
                detail = nil
                idlePaused = false
                micRestartCause = nil // Engine lief neu an; ist sie wieder stumm, meldet die Erkennung es erneut
                lastActivityAt = Date()
                publish()
                Diag.log("audio.resume.ok", ["trigger": .s(trigger), "attempt": .i(attempt), "app": .s(Self.appState), "ms": .ms(MonoClock.msSince(begin))])
                schedulePauseIfIdle(reason: "after-resume")
            case .failure(let error):
                Diag.log("audio.resume.failed", [
                    "trigger": .s(trigger), "attempt": .i(attempt), "stage": .s(error.stage),
                    "code": .i(error.code), "fourCC": .s(error.fourCC), "app": .s(Self.appState),
                ])
                let delays: [Double] = [2, 10, 30]
                if attempt <= delays.count {
                    try? await Task.sleep(for: .seconds(delays[attempt - 1]))
                    guard !Task.isCancelled, status == .interrupted else { return }
                    attemptResume(trigger: trigger, attempt: attempt + 1)
                } else {
                    detail = "Mikro aus – Paply einmal öffnen"
                    publish()
                }
            }
        }
    }

    private func handleRouteChange(reason: UInt) {
        let name: String = switch AVAudioSession.RouteChangeReason(rawValue: reason) {
        case .newDeviceAvailable?: "newDevice"
        case .oldDeviceUnavailable?: "oldDeviceGone"
        case .categoryChange?: "category"
        case .override?: "override"
        case .wakeFromSleep?: "wake"
        case .noSuitableRouteForCategory?: "noRoute"
        case .routeConfigurationChange?: "config"
        default: "raw\(reason)"
        }
        var fields: DiagFields = ["reason": .s(name), "status": .s(status.rawValue), "app": .s(Self.appState)]
        fields.merge(audio.routeFields) { a, _ in a }
        Diag.log("audio.route", fields)
        if status != .off { Task { await audio.preferBuiltInMic() } }
    }

    private func handleMediaServicesReset() {
        Diag.log("audio.mediaServicesReset", ["status": .s(status.rawValue), "app": .s(Self.appState)])
        guard status != .off else { return }
        cancelDictation(reason: "media-reset")
        Task {
            switch await audio.rebuildAndStart() {
            case .success:
                status = .ready
                detail = nil
                idlePaused = false
                micRestartCause = nil
                Diag.log("audio.mediaServicesReset.recovered")
                schedulePauseIfIdle(reason: "after-reset")
            case .failure(let error):
                status = .interrupted
                detail = "Mikro aus – Paply einmal öffnen"
                Diag.log("audio.mediaServicesReset.failed", ["stage": .s(error.stage), "code": .i(error.code), "fourCC": .s(error.fourCC)])
            }
            publish()
        }
    }

    private func handleEngineConfigurationChange() {
        Task {
            await audio.refresh()
            var fields: DiagFields = ["status": .s(status.rawValue), "engine": .b(audio.isRunning), "app": .s(Self.appState)]
            fields.merge(audio.routeFields) { a, _ in a }
            Diag.log("audio.engineConfigChange", fields)
            guard status == .ready || status == .recording, !audio.isRunning, !idlePaused else { return }
            switch await audio.restartEngine() {
            case .success:
                Diag.log("audio.engineRestart.ok")
            case .failure(let error):
                Diag.log("audio.engineRestart.failed", ["stage": .s(error.stage), "code": .i(error.code), "fourCC": .s(error.fourCC)])
                status = .interrupted
                detail = "Mikro aus – Paply einmal öffnen"
                publish()
            }
        }
    }

    // MARK: App-Ereignisse

    private func registerAppObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let session = SessionController.shared
                Diag.log("app.background", ["status": .s(session.status.rawValue), "engine": .b(session.audio.isRunning)])
                session.schedulePauseIfIdle(reason: "background")
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let session = SessionController.shared
                Diag.log("app.foreground", ["status": .s(session.status.rawValue), "engine": .b(session.audio.isRunning),
                                            "micSilent": .b(session.micSilent)])
                // Stummes Mikro bei laufender Engine wartet in attemptResume auf „aktiv“ (didBecomeActive)
                if session.status == .interrupted { session.attemptResume(trigger: "foreground", attempt: 1) }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let session = SessionController.shared
                // Im Hintergrund als stumm erkannt: jetzt (vorne, aktiv) darf das Mikro neu starten
                if session.micSilent, session.status == .interrupted {
                    session.attemptResume(trigger: "active", attempt: 1)
                }
            }
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Diag.log("app.terminate", ["status": .s(SessionController.shared.status.rawValue)])
                Diag.flush()
            }
        })
    }

    nonisolated private static func removeStalePending() {
        if let pending = SharedStore.read(PendingText.self, .pendingText), !pending.isFresh {
            SharedStore.remove(.pendingText)
        }
    }

    static var appState: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    /// Mikrofon-Freigabe fürs Protokoll
    nonisolated static var micPermission: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: "granted"
        case .denied: "denied"
        case .undetermined: "undetermined"
        @unknown default: "unknown"
        }
    }
}

/// Ein laufendes Diktat: Pipeline + geordneter Zulauf der Samples.
/// Zulauf einer Aufnahme aus dem Audio-Tap: Samples oder „Mikro neu gestartet, stummen Anfang verwerfen“.
enum TapFeed: Sendable {
    case samples([Float])
    case restart
}

private final class ActiveDictation {
    let id: String
    let source: DictationSource
    let pipeline: DictationPipeline
    let continuation: AsyncStream<TapFeed>.Continuation
    let feedTask: Task<Void, Never>
    let startedNs: UInt64
    let apiKey: String
    /// Einstellungen beim Start (für die Auswertung je Kombination)
    let model: String
    let chunked: Bool
    var speechDetected = false
    var finishing = false
    var deliverAsPending = false
    var retries = 0
    /// Freigabe des behaltenen Audios nach 10 Min
    var expiry: Task<Void, Never>?
    /// Testvarianten der Pipeline beim Start, z. B. „flac·primer·polish“
    let options: String
    var commandLatencyMs: Double?
    /// Pegel der Rohpuffer (beim Lösen vom Tap ermittelt)
    var micStats: MicInputStats?

    var shortID: String { String(id.prefix(8)) }

    @MainActor
    init(id: String, source: DictationSource, apiKey: String, pipeline: DictationPipeline, continuation: AsyncStream<TapFeed>.Continuation, feedTask: Task<Void, Never>, startedNs: UInt64) {
        self.id = id
        self.source = source
        self.apiKey = apiKey
        self.model = AppSettings.shared.paply.transcriptionModel
        self.chunked = AppSettings.shared.paply.chunkedUpload
        self.options = AppSettings.shared.testOptions.logName
        self.pipeline = pipeline
        self.continuation = continuation
        self.feedTask = feedTask
        self.startedNs = startedNs
    }
}

// MARK: - Gedanken-Haken (KONZEPT §9.2, H3; Review durch Koordinator)

extension SessionController {
    /// Gedanke hängt sich an den Audio-Strom. Fall A: Sitzung läuft (ggf. Engine aus dem
    /// Leerlauf fortsetzen). Fall B: keine Sitzung → im Hintergrund starten (AudioRecordingIntent).
    /// false = Mikro ließ sich nicht starten (Aufrufer holt die App nach vorne).
    func attachThought(id: String, sink: @escaping @Sendable ([Float]) -> Void,
                       onRestart: (@Sendable () -> Void)? = nil) async -> Bool {
        let begin = MonoClock.now()
        let ready = (status == .ready || status == .recording) && (audio.isRunning || idlePaused)
        let fall = ready ? "A" : "B"
        thoughtSessionEnd?.cancel()
        if !ready {
            guard await startSession(trigger: "thought-intent") else {
                Diag.log("thought.attach", ["id": .s(String(id.prefix(8))), "case": .s(fall), "ok": .b(false), "ms": .ms(MonoClock.msSince(begin))])
                return false
            }
            // Sitzung nur für den Gedanken? Dann später wieder aus (außer Diktat ist in Gebrauch).
            startedForThought = !dictationInUse
            Diag.log("session.thoughtOnly", ["on": .b(startedForThought), "dictationInUse": .b(!startedForThought)])
        }
        pauseTask?.cancel()
        if idlePaused {
            idlePaused = false
            if case .failure(let error) = await audio.resumeInput() {
                Diag.log("thought.attach", [
                    "id": .s(String(id.prefix(8))), "case": .s("A-paused"), "ok": .b(false),
                    "stage": .s(error.stage), "code": .i(error.code), "fourCC": .s(error.fourCC),
                ])
                return false
            }
        }
        // Vorlauf 0,5 s kommt mit (wie beim Diktat); Pegel rechnet ThoughtCapture selbst.
        let preroll = audio.processor.attach(owner: id, sink: sink, levels: nil, onRestart: onRestart)
        lastActivityAt = Date()
        publish()
        Diag.log("thought.attach", [
            "id": .s(String(id.prefix(8))), "case": .s(fall), "ok": .b(true),
            "prerollMs": .ms(Double(preroll) / AudioTapProcessor.sampleRate * 1000),
            "ms": .ms(MonoClock.msSince(begin)), "app": .s(Self.appState),
        ])
        return true
    }

    /// Gedanke löst sich vom Audio-Strom (nach dem Nachlauf). Danach ggf. Leerlauf-Pause.
    /// Liefert die Pegel der Rohpuffer dieser Aufnahme (fürs Protokoll).
    @discardableResult
    func detachThought(id: String) -> MicInputStats? {
        let stats = audio.processor.detach(owner: id)
        lastActivityAt = Date()
        publish()
        schedulePauseIfIdle(reason: "thought-end")
        if startedForThought, !dictationInUse { scheduleThoughtSessionEnd() }
        return stats
    }

    /// Die Paply-Tastatur wurde schon zum Diktieren benutzt → normale Bereithalte-Einstellung.
    private var dictationInUse: Bool {
        HistoryStore.shared.entries.contains { $0.source == .keyboard }
    }

    /// 5 Min. nach dem Gedanken endet eine nur dafür gestartete Sitzung.
    private func scheduleThoughtSessionEnd() {
        thoughtSessionEnd?.cancel()
        thoughtSessionEnd = Task {
            try? await Task.sleep(for: .seconds(Self.thoughtOnlySessionSeconds))
            guard !Task.isCancelled, startedForThought, !isThoughtActive, dictation == nil, status != .off else { return }
            // Danach wird die App ausgesetzt: Wartet noch ein Gedanke (Netz, Kontingent), übernimmt ein
            // BGProcessingTask. In Fall B kam die App nie nach vorne, also gab es noch keinen.
            await ThoughtsEnvironment.scheduleBackgroundProcessing()
            guard !Task.isCancelled, startedForThought, !isThoughtActive, dictation == nil, status != .off else { return }
            stopSession(reason: "thought-session-end")
        }
        Diag.log("session.thoughtOnly.scheduledEnd", ["inS": .d(Self.thoughtOnlySessionSeconds)])
    }

    /// Die Tastatur diktiert in einer Sitzung, die ein Gedanke gestartet hat: ab jetzt gilt die
    /// normale Bereithalte-Einstellung.
    private func keepSessionForDictation() {
        startedForThought = false
        thoughtSessionEnd?.cancel()
        Diag.log("session.thoughtOnly", ["on": .b(false), "reason": .s("keyboard")])
    }

    /// Solange ein Gedanke aufnimmt: keine Leerlauf-Pause, kein Ablauf der Bereithalte-Dauer.
    var isThoughtActive: Bool { ThoughtCapture.shared.active != nil }

    /// Für ThoughtCapture: letzter Tap-Block (Nachlauf beim Stopp).
    var lastAudioArrivalNs: UInt64 { audio.processor.lastArrivalNs }
}

// MARK: - Pegel der Rohpuffer fürs Protokoll (nur Zahlen, nie Inhalte)

extension MicInputStats {
    /// dBFS auf eine Nachkommastelle; −160 = exakt 0. `rawHfRmsDb`: RMS der Differenzen (grober
    /// Hochpass) – zeigt, ob überhaupt Bewegung im Signal ist (Gleichanteil/Drift ≈ −160).
    var diagFields: DiagFields {
        func db(_ value: Double) -> DiagValue { .d((value * 10).rounded() / 10) }
        return [
            "rawPeakDb": db(peakDbfs),
            "rawRmsDb": db(rmsDbfs),
            "rawAcRmsDb": db(acRmsDbfs),
            "rawHfRmsDb": db(diffRmsDbfs),
            "convPeakDb": db(convertedPeakDbfs),
            "rawBuffers": .i(buffers),
            "zeroBuffers": .i(zeroBuffers),
            "silentBuffers": .i(silentBuffers),
            "offsetBuffers": .i(offsetBuffers),
            "micRestarts": .i(restarts),
        ]
    }
}
