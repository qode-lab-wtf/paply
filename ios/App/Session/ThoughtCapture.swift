import Foundation
import Observation
import PaplyKit
import UIKit

// Aufnahme eines Gedankens (KONZEPT §5). Besitzer: H3.
//
// Erfassen ist heilig: Eintrag und WAV entstehen synchron vor jedem `await`, der Ton liegt auf der
// Platte, bevor irgendetwas ins Netz geht. Unterbrechung, Tastatur oder 30-Min.-Grenze sichern den
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

    /// Lock-Wert (0…1), für TimelineView – keine SwiftUI-Invalidierung je Sample.
    var level: Float { levelBox.value }

    /// Von H2 gesetzt (ThoughtsEnvironment), sobald Speicher und Warteschlange stehen.
    /// Ohne Store schreibt der S1-Rückfall WAV + Platzhalter; ohne Prozessor gibt es keine
    /// Live-Pipeline (also keinen Netzverkehr).
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
            return .refused("Diktat läuft gerade")
        }
        guard Self.protectedFilesWritable() else {
            logStart(case: "-", ok: false, stage: "before-first-unlock", trigger: trigger, begin: begin)
            return .refused("Nach dem Neustart einmal entsperren")
        }

        starting = true
        defer { starting = false }

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
            liveFeed?.yield(samples)
            levelBox.update(with: samples)
        }
        guard await session.attachThought(id: id, sink: sink) else {
            // Kein Mikro: Eintrag ohne Ton verwerfen (keine Leiche), App kurz nach vorne holen
            live?.cancel()
            file.discard()
            await removePlaceholder(placeholder)
            ThoughtBridge.endActivity(id: id, immediately: true)
            let failure = session.lastStartFailure
            logStart(case: fall, ok: false, stage: failure?.stage ?? "attach", trigger: trigger, begin: begin,
                     code: failure?.code, fourCC: failure?.fourCC)
            return .needsForeground(failure?.fourCC.isEmpty == false ? failure!.fourCC : "Mikro ließ sich nicht starten")
        }

        recording = Recording(id: id, trigger: trigger, startedAt: startedAt, startedNs: begin, placeholder: placeholder, file: file)
        recording?.live = live
        active = Active(id: id, startedAt: startedAt, speechDetected: false)
        ThoughtBridge.recordingChanged(id: id, startedAt: startedAt)
        startTicker(id: id)
        logStart(case: fall, ok: true, stage: "recording", trigger: trigger, begin: begin)
        return .started(id)
    }

    /// Stoppt und sichert. Nie verwerfen (auch nicht bei Unterbrechung).
    func finish(_ reason: ThoughtFinishReason) {
        guard let rec = recording, !rec.finishing else { return }
        rec.finishing = true
        let stopNs = MonoClock.now()
        let id = rec.id
        if reason == .interruption { lastInterruptionStop = (id, Date()) }
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
            SessionController.shared.detachThought(id: id)
            let durationMs = rec.file.close()
            var thought = rec.placeholder
            thought.state = .captured
            thought.durationMs = durationMs
            thought.updatedAt = Date()
            let saved = await save(thought)
            if recording === rec { recording = nil }
            Diag.log("thought.stop", [
                "id": .s(Self.short(id)), "reason": .s(reason.rawValue), "durationMs": .i(durationMs),
                "saved": .b(saved), "store": .b(store != nil), "live": .b(rec.live != nil),
                "app": .s(SessionController.appState),
            ])
            // Live-Pipeline: Rohtext Sekunden nach dem Stopp an die Warteschlange
            if let live = rec.live, let processor {
                let outcome = await live.finish()
                await processor.liveTranscript(id, outcome: outcome)
            } else {
                await processor?.kick(reason: "captured")
            }
            if processor == nil {
                // S1: ohne Warteschlange nur „Gesichert“ zeigen
                ThoughtBridge.showSavedWithoutProcessing(id: id, note: Self.stopNote(reason))
            }
        }
    }

    /// Ausdrücklich verwerfen (große Aufnahme-Ansicht). Ton und Eintrag weg.
    func discard() {
        guard let rec = recording, !rec.finishing else { return }
        rec.finishing = true
        let id = rec.id
        ticker?.cancel()
        ticker = nil
        active = nil
        levelBox.set(0)
        SessionController.shared.detachThought(id: id)
        rec.live?.cancel()
        rec.file.discard()
        recording = nil
        ThoughtBridge.recordingChanged(id: nil, startedAt: nil)
        ThoughtBridge.endActivity(id: id, immediately: true)
        let placeholder = rec.placeholder
        Task { await removePlaceholder(placeholder) }
        Diag.log("thought.discard", ["id": .s(Self.short(id)), "durationS": .d(Date().timeIntervalSince(rec.startedAt).rounded())])
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
        case .limit: "Nach 10 Min. gespeichert"
        case .storage: "Speicher voll · bisheriger Ton gesichert"
        default: nil
        }
    }

    // MARK: Speicher (Store von H2, sonst S1-Rückfall)

    private func beginCapture(trigger: ThoughtTrigger, at date: Date) async throws -> (Thought, CaptureFile) {
        if let store {
            do {
                let (thought, writer) = try await store.beginCapture(trigger: trigger, at: date)
                return (thought, CaptureFile(writer: writer))
            } catch ThoughtStoreError.notImplemented {
                // Gerüst: weiter mit dem Rückfall
            }
        }
        return try SpikeCaptureStore.begin(trigger: trigger, at: date)
    }

    private func save(_ thought: Thought) async -> Bool {
        if let store {
            do {
                try await store.save(thought)
                return true
            } catch ThoughtStoreError.notImplemented {
            } catch {
                Diag.log("thought.save.failed", ["id": .s(Self.short(thought.id)), "code": .i((error as NSError).code)])
                return false
            }
        }
        return SpikeCaptureStore.save(thought)
    }

    private func removePlaceholder(_ thought: Thought) async {
        if let store {
            var empty = thought
            empty.state = .empty
            empty.deletedAt = Date()
            if (try? await store.save(empty)) != nil { return }
        }
        SpikeCaptureStore.remove(thought.id)
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

    /// Nach einem Neustart ohne Entsperren sind Dateien (und Schlüsselbund) nicht verfügbar.
    private static func protectedFilesWritable() -> Bool {
        guard let dir = SpikeCaptureStore.root else { return false }
        let probe = dir.appendingPathComponent(".probe")
        do {
            try Data([1]).write(to: probe, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
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

/// Ziel der Samples: WAVWriter (H2) oder S1-Rückfall.
final class CaptureFile: Sendable {
    private let appendBlock: @Sendable ([Float]) -> Void
    private let closeBlock: @Sendable () -> Int
    private let discardBlock: @Sendable () -> Void

    init(writer: WAVWriter) {
        appendBlock = { writer.append($0) }
        closeBlock = { writer.close() }
        discardBlock = { _ = writer.close() }
    }

    init(append: @escaping @Sendable ([Float]) -> Void, close: @escaping @Sendable () -> Int, discard: @escaping @Sendable () -> Void) {
        appendBlock = append
        closeBlock = close
        discardBlock = discard
    }

    func append(_ samples: [Float]) { appendBlock(samples) }
    func close() -> Int { closeBlock() }
    func discard() { discardBlock() }
}

/// Live-Verschriftlichung während der Aufnahme (ohne Polieren, mit Stücken).
final class LivePipeline: @unchecked Sendable {
    let continuation: AsyncStream<[Float]>.Continuation
    private let pipeline: DictationPipeline
    private let feed: Task<Void, Never>
    private(set) var abandoned = false

    init(pipeline: DictationPipeline) {
        self.pipeline = pipeline
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        feed = Task.detached(priority: .userInitiated) { [pipeline] in
            for await chunk in stream { await pipeline.append(chunk) }
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

// MARK: - S1-Rückfall (entfällt, sobald ThoughtStore von H2 steht)

/// Minimaler Speicher für den Spike: `Application Support/Gedanken/thoughts/<id>/thought.json`
/// (Platzhalter, Format §7.3, Zeiten in ms) und `audio.wav` (16 kHz mono Int16).
enum SpikeCaptureStore {
    static let root: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Gedanken", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return dir
    }()

    static func folder(_ id: String) -> URL? {
        root?.appendingPathComponent("thoughts", isDirectory: true).appendingPathComponent(id, isDirectory: true)
    }

    static func begin(trigger: ThoughtTrigger, at date: Date) throws -> (Thought, CaptureFile) {
        let thought = Thought(createdAt: date, trigger: trigger, state: .recording,
                              audio: Thought.AudioInfo(file: "audio.wav"), updatedAt: date)
        guard let dir = folder(thought.id) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try write(thought, to: dir)
        let wav = try SpikeWAVFile(url: dir.appendingPathComponent("audio.wav"))
        let file = CaptureFile(append: { wav.append($0) }, close: { wav.close() }, discard: { wav.discard() })
        return (thought, file)
    }

    static func save(_ thought: Thought) -> Bool {
        guard let dir = folder(thought.id) else { return false }
        return (try? write(thought, to: dir)) != nil
    }

    static func remove(_ id: String) {
        guard let dir = folder(id) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    private static func write(_ thought: Thought, to dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(thought).write(to: dir.appendingPathComponent("thought.json"),
                                          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// WAV-Datei mit eigener serieller Queue; der Kopf wird beim Schließen ergänzt.
final class SpikeWAVFile: @unchecked Sendable {
    private let queue = DispatchQueue(label: "paply.thought-wav", qos: .userInitiated)
    private let url: URL
    private let handle: FileHandle
    // nur auf `queue`
    private var sampleCount = 0
    private var lastSync = 0
    private var closed = false

    init(url: URL) throws {
        self.url = url
        guard FileManager.default.createFile(atPath: url.path, contents: Self.header(dataBytes: 0),
                                             attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        else { throw CocoaError(.fileWriteUnknown) }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        handle = try FileHandle(forWritingTo: url)
        _ = try handle.seekToEnd()
    }

    /// blockiert nie (Audio-Thread)
    func append(_ samples: [Float]) {
        queue.async { [self] in
            guard !closed else { return }
            var data = Data(capacity: samples.count * 2)
            for sample in samples {
                var value = Int16(max(-1, min(1, sample)) * Float(Int16.max)).littleEndian
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
            try? handle.write(contentsOf: data)
            sampleCount += samples.count
            // alle 2 s auf die Platte (Absturz verliert höchstens ~2 s)
            if sampleCount - lastSync >= 32_000 {
                lastSync = sampleCount
                try? handle.synchronize()
            }
        }
    }

    /// Kopf ergänzen, schließen; Dauer in ms
    func close() -> Int {
        queue.sync {
            guard !closed else { return sampleCount / 16 }
            closed = true
            try? handle.seek(toOffset: 0)
            try? handle.write(contentsOf: Self.header(dataBytes: sampleCount * 2))
            try? handle.synchronize()
            try? handle.close()
            return sampleCount / 16
        }
    }

    func discard() {
        _ = close()
        try? FileManager.default.removeItem(at: url)
    }

    private static func header(dataBytes: Int) -> Data {
        var data = Data()
        func put(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        put("RIFF"); u32(UInt32(36 + dataBytes)); put("WAVE")
        put("fmt "); u32(16); u16(1); u16(1); u32(16_000); u32(32_000); u16(2); u16(16)
        put("data"); u32(UInt32(dataBytes))
        return data
    }
}
