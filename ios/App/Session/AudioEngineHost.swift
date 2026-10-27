@preconcurrency import AVFoundation
import Foundation

/// AVAudioSession + AVAudioEngine mit dauerhaftem Input-Tap.
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
@MainActor
final class AudioEngineHost {
    static let ioBuffer: TimeInterval = 0.1

    let processor = AudioTapProcessor()
    private(set) var engine = AVAudioEngine()
    private var tapInstalled = false

    var isRunning: Bool { engine.isRunning }

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

    // MARK: Sitzung

    func configureSession() throws(StartError) {
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

    func activateSession() throws(StartError) {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            throw .session(error as NSError)
        }
        preferBuiltInMic()
    }

    func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func preferBuiltInMic() {
        let session = AVAudioSession.sharedInstance()
        guard let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        if session.preferredInput?.uid != mic.uid {
            try? session.setPreferredInput(mic)
        }
    }

    // MARK: Engine

    /// Startet die Engine immer mit frisch ermitteltem Eingangsformat: Ein vorhandener Tap
    /// (z. B. nach einer Unterbrechung oder Routenwechsel) wird ersetzt.
    func startEngine() throws(StartError) {
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

    func stopEngine() {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// Nach Konfigurationswechsel (Format/Route): Tap mit neuem Format, dann wieder starten.
    func restartEngine() throws(StartError) {
        try startEngine()
    }

    /// Nach „Media Services were reset“: alles neu aufbauen.
    func rebuild() {
        stopEngine()
        engine = AVAudioEngine()
    }

    /// Bewusst nonisolated: Der Tap-Block läuft auf einem Audio-Thread und darf nicht
    /// als MainActor-Closure entstehen (Swift 6 prüft das zur Laufzeit).
    nonisolated private static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, processor: AudioTapProcessor) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            processor.process(buffer, arrivalNs: MonoClock.now())
        }
    }

    // MARK: Diagnose

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
            "engine": .b(engine.isRunning),
        ]
    }
}
