@preconcurrency import AVFoundation
import Foundation

/// AVAudioSession + AVAudioEngine mit dauerhaftem Input-Tap.
///
/// Alle Aufrufe an Sitzung und Engine laufen auf einer eigenen seriellen Queue:
/// `setActive`, `setCategory`, `setPreferredInput` und `engine.start()` können je
/// 50–500 ms blockieren und gehören nicht auf den Main-Thread. Der Main-Thread sieht
/// nur einen Schnappschuss (`isRunning`).
///
/// Sitzungs-Entscheidung (im Testplan geprüft):
/// - `.playAndRecord`, Modus `.default`, `.mixWithOthers`: Musik anderer Apps läuft weiter.
/// - Bluetooth NUR `.allowBluetoothA2DP`, kein HFP: AirPods bleiben für Musik in voller
///   Qualität (A2DP kann kein Mikro, also nimmt das eingebaute Mikro auf). Mit HFP würde
///   iOS beim Aktivieren der Sitzung auf Telefonqualität umschalten – den ganzen Tag.
/// - `.defaultToSpeaker`: Ohne Kopfhörer liefe sonst auch fremde Musik über die Hörmuschel.
/// - bevorzugter Eingang: eingebautes Mikro.
/// - IO-Puffer fest ~100 ms: wenig Aufwachen im Leerlauf (Akku). Ein Wechsel beim Aufnehmen
///   könnte die Engine umkonfigurieren; die Pegel laufen trotzdem flüssig (Zeitstempel,
///   leicht verzögert gezeichnet). Wirksamer Puffer und Tap-Abstand stehen im Protokoll.
final class AudioEngineHost: @unchecked Sendable {
    static let ioBuffer: TimeInterval = 0.1

    let processor = AudioTapProcessor()

    private let queue = DispatchQueue(label: "paply.audio-engine", qos: .userInitiated)
    // Nur auf `queue` benutzt
    private var engine = AVAudioEngine()
    private var tapInstalled = false
    // Schnappschuss für den Main-Thread
    private let snapshotLock = NSLock()
    private var runningSnapshot = false

    enum StartError: Error {
        case noInput
        case session(NSError)
        case engine(NSError)

        var code: Int {
            switch self {
            case .noInput: -1
            case .session(let e), .engine(let e): e.code
            }
        }

        var fourCC: String {
            let value = UInt32(truncatingIfNeeded: code)
            let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
            guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return "" }
            return String(decoding: bytes, as: UTF8.self)
        }

        var stage: String {
            switch self {
            case .noInput: "input"
            case .session: "session"
            case .engine: "engine"
            }
        }
    }

    typealias Outcome = Result<Void, StartError>

    /// Letzter bekannter Zustand der Engine (nach jedem Ablauf aktualisiert).
    var isRunning: Bool {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return runningSnapshot
    }

    // MARK: Abläufe (laufen auf der Audio-Queue, der Aufrufer wartet nur asynchron)

    /// Sitzung einrichten, aktivieren und Engine mit frischem Tap starten.
    func start() async -> Outcome {
        await onQueue { host in
            do throws(StartError) {
                try host.configureSession()
                try host.activateSession()
                try host.startEngine()
                return .success(())
            } catch {
                host.stopEngine()
                return .failure(error)
            }
        }
    }

    /// Nach Unterbrechung: Sitzung wieder aktivieren, Engine neu starten, falls sie steht.
    func resume() async -> Outcome {
        await onQueue { host in
            do throws(StartError) {
                try host.activateSession()
                if !host.engine.isRunning { try host.startEngine() }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    /// Nach Konfigurationswechsel (Format/Route): Tap mit neuem Format, dann wieder starten.
    func restartEngine() async -> Outcome {
        await onQueue { host in
            do throws(StartError) {
                try host.startEngine()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    /// Nach „Media Services were reset“: Engine neu bauen, alles neu einrichten.
    func rebuildAndStart() async -> Outcome {
        await onQueue { host in
            host.stopEngine()
            host.engine = AVAudioEngine()
            do throws(StartError) {
                try host.configureSession()
                try host.activateSession()
                try host.startEngine()
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    /// Stoppen ohne zu warten. Wird sofort in die Queue gestellt, damit ein direkt
    /// folgender `start()` sicher danach läuft.
    func stop() {
        queue.async { [self] in
            stopEngine()
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            snapshotLock.lock()
            runningSnapshot = false
            snapshotLock.unlock()
        }
    }

    func preferBuiltInMic() async {
        await onQueue { host in host.applyBuiltInMic() }
    }

    // MARK: Experiment „Mikro im Leerlauf pausieren“ (Sitzung bleibt aktiv, kein setActive(false))

    /// Engine anhalten. `.pause`: `engine.pause()` – IO-Einheit bleibt eingerichtet, Tap bleibt;
    /// das hat die besten Chancen, im Hintergrund wieder anzulaufen (kein Neuaufbau, kein
    /// Formatwechsel). `.stop`: `engine.stop()` und Tap entfernen – gibt alles frei, der
    /// Wiederanlauf baut neu auf. Der Vorlauf wird geleert (er wäre beim nächsten Diktat alt).
    func pauseInput(_ mode: IdlePauseMode) async {
        await onQueue { host in
            switch mode {
            case .off: return
            case .pause: host.engine.pause()
            case .stop: host.stopEngine()
            }
            host.processor.reset()
        }
    }

    /// Engine nach dem Anhalten wieder starten – ohne die Sitzung neu zu aktivieren.
    func resumeInput() async -> Outcome {
        await onQueue { host in
            do throws(StartError) {
                if host.tapInstalled {
                    host.engine.prepare()
                    do {
                        try host.engine.start()
                    } catch {
                        throw .engine(error as NSError)
                    }
                } else {
                    try host.startEngine()
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    /// Nur den Schnappschuss auffrischen (z. B. nach einer Unterbrechung).
    func refresh() async {
        await onQueue { _ in }
    }

    private func onQueue<T: Sendable>(_ body: @escaping @Sendable (AudioEngineHost) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let value = body(self)
                let running = engine.isRunning
                snapshotLock.lock()
                runningSnapshot = running
                snapshotLock.unlock()
                continuation.resume(returning: value)
            }
        }
    }

    // MARK: Auf der Queue

    private func configureSession() throws(StartError) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
        } catch {
            throw .session(error as NSError)
        }
        try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try? session.setPreferredIOBufferDuration(Self.ioBuffer)
    }

    private func activateSession() throws(StartError) {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            throw .session(error as NSError)
        }
        applyBuiltInMic()
    }

    private func applyBuiltInMic() {
        let session = AVAudioSession.sharedInstance()
        guard let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        if session.preferredInput?.uid != mic.uid {
            try? session.setPreferredInput(mic)
        }
    }

    /// Startet die Engine immer mit frisch ermitteltem Eingangsformat: Ein vorhandener Tap
    /// (z. B. nach einer Unterbrechung oder Routenwechsel) wird ersetzt.
    private func startEngine() throws(StartError) {
        if engine.isRunning { engine.stop() }
        let input = engine.inputNode
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw .noInput }
        processor.reset()
        Self.installTap(on: input, format: format, processor: processor)
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw .engine(error as NSError)
        }
    }

    private func stopEngine() {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// Der Tap-Block läuft auf einem Audio-Thread; er entsteht hier in nicht isoliertem
    /// Kontext und greift nur auf den thread-sicheren Prozessor zu.
    private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, processor: AudioTapProcessor) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            processor.process(buffer, arrivalNs: MonoClock.now())
        }
    }

    // MARK: Diagnose (thread-sicher lesbar)

    var routeFields: DiagFields {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        return [
            "in": .s(route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")),
            "out": .s(route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")),
            "ioBufMs": .ms(session.ioBufferDuration * 1000),
            "rate": .d(session.sampleRate),
            "otherAudio": .b(session.isOtherAudioPlaying),
        ]
    }

    var tapFields: DiagFields {
        let stats = processor.currentStats
        return [
            "tapBuffers": .i(stats.buffers),
            "tapFrames": .i(stats.lastFrames),
            "tapIntervalMs": .ms(stats.meanIntervalMs),
            "inRate": .d(stats.inputSampleRate),
            "inCh": .i(stats.inputChannels),
            "convErrors": .i(stats.conversionErrors),
            "engine": .b(isRunning),
        ]
    }
}
