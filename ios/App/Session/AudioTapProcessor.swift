import Accelerate
@preconcurrency import AVFoundation
import Foundation
import PaplyKit

/// Läuft im Audio-Tap (eigener Thread): wandelt auf 16 kHz mono Float32, hält den
/// Vorlauf (~0,5 s) und reicht während eines Diktats die Samples weiter.
/// Im Leerlauf wird nichts gespeichert oder gesendet – nur der Ringpuffer im Speicher.
///
/// Jeder Rohpuffer wird außerdem gemessen (nur Zahlen): Liefert der Motor 1,5 s lang nur
/// digitale Stille, gilt das Mikro als tot (`MicSilenceDetector`, Vorfall 27.10.2026) –
/// der Wechsel geht an `silenceHandler`. Während einer Aufnahme sammeln sich die Pegel
/// in `MicInputStats` fürs Protokoll.
final class AudioTapProcessor: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    static let prerollSamples = 8_000 // 0,5 s
    /// ~33 ms je Pegelwert → ~30 Hz
    private static let levelWindow = 533

    private let lock = NSLock()
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    // Alles Folgende nur unter `lock`
    private var converter: AVAudioConverter?
    private var converterInput: AVAudioFormat?
    private var preroll = [Float](repeating: 0, count: prerollSamples)
    private var prerollWrite = 0
    private var prerollFilled = 0
    /// Alle Samples seit Start (laufender Zähler) und Grenze, bis zu der sie schon einem
    /// Diktat gehören. Der Vorlauf liefert nur Samples dahinter – sonst landeten die letzten
    /// 0,5 s eines Diktats auch im direkt folgenden.
    private var totalSamples = 0
    private var consumedUpTo = 0
    private var sink: (@Sendable ([Float]) -> Void)?
    private var sinkOwner: String?
    private var listener: (@Sendable ([Float]) -> Void)?
    private var listenerOwner: String?
    private var levels: LevelChannel?
    private var levelSum: Float = 0
    private var levelCount = 0
    /// Geschätztes Grundrauschen in dBFS: fällt sofort mit, steigt nur langsam (~1 dB/s).
    /// Wird auch im Leerlauf mitgeführt, damit das erste Diktat schon richtig skaliert.
    private var noiseFloorDb: Float = -60
    private var stats = TapStats()
    /// Totes Mikro? (zählt seit dem letzten Motorstart)
    private var silence = MicSilenceDetector()
    private var silenceHandler: (@Sendable (MicSilenceDetector.Change) -> Void)?
    /// Pegel der laufenden Aufnahme (seit `attach`)
    private var recording = MicInputStats()
    /// Nach einem Neustart wegen stummen Mikros: Die Aufnahme verwirft vor dem ersten neuen
    /// Block ihren bisherigen (stummen) Ton – gemeldet im Tap-Thread, also in Reihenfolge.
    private var pendingDiscard = false
    private var onRestart: (@Sendable () -> Void)?

    struct TapStats: Sendable {
        var buffers = 0
        var lastFrames = 0
        var inputSampleRate: Double = 0
        var inputChannels = 0
        var lastArrivalNs: UInt64 = 0
        /// gleitender Mittelwert des Abstands zwischen Tap-Blöcken
        var meanIntervalMs: Double = 0
        var conversionErrors = 0
    }

    // MARK: Tap

    func process(_ buffer: AVAudioPCMBuffer, arrivalNs: UInt64) {
        let raw = Self.measure(buffer) // reine Rechnung, außerhalb des Locks
        let seconds = buffer.format.sampleRate > 0 ? Double(buffer.frameLength) / buffer.format.sampleRate : 0
        lock.lock()
        let change = silence.feed(raw, seconds: seconds)
        let handler = change == nil ? nil : silenceHandler
        if sink != nil { recording.add(raw) }
        let samples = convert(buffer)
        updateStats(buffer: buffer, arrivalNs: arrivalNs)
        guard let samples, !samples.isEmpty else {
            lock.unlock()
            if let change { handler?(change) }
            return
        }
        appendPreroll(samples)
        measureLevels(samples, arrivalNs: arrivalNs)
        let sink = self.sink
        var restart: (@Sendable () -> Void)?
        if sink != nil {
            consumedUpTo = totalSamples // gehört diesem Diktat
            var peak: Float = 0
            samples.withUnsafeBufferPointer { vDSP_maxmgv($0.baseAddress!, 1, &peak, vDSP_Length($0.count)) }
            recording.convertedPeak = max(recording.convertedPeak, peak)
            if pendingDiscard { restart = onRestart }
        }
        pendingDiscard = false
        listener?(samples) // Nur weiterreichen; kein eigener Puffer, unabhängig vom Diktat.
        lock.unlock()
        if let change { handler?(change) }
        restart?()
        sink?(samples)
    }

    /// Pegel eines Rohpuffers über alle Kanäle (nur Float-Formate; sonst leer = nicht bewertet).
    private static func measure(_ buffer: AVAudioPCMBuffer) -> MicBufferLevel {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let data = buffer.floatChannelData else { return MicBufferLevel() }
        let channels = Int(buffer.format.channelCount)
        if buffer.format.isInterleaved {
            return MicBufferLevel.measure(UnsafeBufferPointer(start: data[0], count: frames * channels))
        }
        var level = MicBufferLevel()
        for channel in 0..<channels {
            level.merge(MicBufferLevel.measure(UnsafeBufferPointer(start: data[channel], count: frames)))
        }
        return level
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let format = buffer.format
        if converter == nil || converterInput != format {
            converter = AVAudioConverter(from: format, to: outputFormat)
            converterInput = format
        }
        guard let converter, buffer.frameLength > 0 else { return nil }
        let ratio = outputFormat.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        let feed = OneShotFeed(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if let next = feed.take() {
                inputStatus.pointee = .haveData
                return next
            }
            inputStatus.pointee = .noDataNow
            return nil
        }
        guard status != .error, let channel = out.floatChannelData?[0] else {
            stats.conversionErrors += 1
            return nil
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }

    private func updateStats(buffer: AVAudioPCMBuffer, arrivalNs: UInt64) {
        if stats.lastArrivalNs > 0 {
            let interval = MonoClock.ms(from: stats.lastArrivalNs, to: arrivalNs)
            stats.meanIntervalMs = stats.meanIntervalMs == 0 ? interval : stats.meanIntervalMs * 0.95 + interval * 0.05
        }
        stats.buffers += 1
        stats.lastFrames = Int(buffer.frameLength)
        stats.inputSampleRate = buffer.format.sampleRate
        stats.inputChannels = Int(buffer.format.channelCount)
        stats.lastArrivalNs = arrivalNs
    }

    private func appendPreroll(_ samples: [Float]) {
        totalSamples += samples.count
        let n = preroll.count
        if samples.count >= n {
            preroll = Array(samples.suffix(n))
            prerollWrite = 0
            prerollFilled = n
            return
        }
        for sample in samples {
            preroll[prerollWrite] = sample
            prerollWrite = (prerollWrite + 1) % n
        }
        prerollFilled = min(n, prerollFilled + samples.count)
    }

    /// Vorlauf ohne Samples, die schon einem Diktat gehörten (älteste zuerst).
    private func orderedPreroll() -> [Float] {
        let n = preroll.count
        let count = min(prerollFilled, max(0, totalSamples - consumedUpTo))
        guard count > 0 else { return [] }
        let start = (prerollWrite - count + n) % n
        var out = [Float]()
        out.reserveCapacity(count)
        for i in 0..<count { out.append(preroll[(start + i) % n]) }
        return out
    }

    /// Pegel je ~33 ms: RMS → dBFS, bezogen aufs Grundrauschen. 3 dB über dem Rauschen = 0,
    /// +30 dB = 1; die Wurzel hebt leise Stimme sichtbar an. Geschrieben wird nur, solange
    /// ein Diktat einen Pegel-Kanal angehängt hat.
    private func measureLevels(_ samples: [Float], arrivalNs: UInt64) {
        var remaining = samples.count
        for sample in samples {
            levelSum += sample * sample
            levelCount += 1
            remaining -= 1
            guard levelCount >= Self.levelWindow else { continue }
            let rms = (levelSum / Float(levelCount)).squareRoot()
            let db = 20 * log10(max(rms, 1e-7))
            levelSum = 0
            levelCount = 0
            if db < noiseFloorDb {
                noiseFloorDb = max(db, -80)
            } else {
                noiseFloorDb = min(noiseFloorDb + 0.033, -25)
            }
            guard let levels else { continue }
            let linear = min(1, max(0, (db - noiseFloorDb - 3) / 30))
            let level = linear.squareRoot()
            let offsetNs = UInt64(Double(remaining) / Self.sampleRate * 1_000_000_000)
            levels.push(level: level, ns: arrivalNs > offsetNs ? arrivalNs - offsetNs : arrivalNs)
        }
    }

    // MARK: Steuerung (vom Main-Thread)

    /// Hängt einen Empfänger an und gibt ihm zuerst den Vorlauf – unter dem Lock,
    /// damit kein Tap-Block dazwischenrutscht (lückenlos, ohne Doppel).
    /// Liefert die Länge des Vorlaufs in Samples.
    ///
    /// `onRestart` meldet (im Tap-Thread, direkt vor dem ersten neuen Block), dass das Mikro
    /// wegen digitaler Stille neu gestartet wurde: Der bisherige Ton war stumm und darf weg.
    @discardableResult
    func attach(owner: String, sink: @escaping @Sendable ([Float]) -> Void, levels: LevelChannel?,
                onRestart: (@Sendable () -> Void)? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }
        // Hängt noch ein Diktat (z. B. im Nachlauf nach „fertig“), gehört alles Bisherige ihm.
        if self.sink != nil { consumedUpTo = totalSamples }
        // Alten Empfänger lösen und Pegel-Datei neu beginnen – unter dem Lock, damit der
        // Tap keinen Pegel des vorigen Diktats mehr hineinschreibt.
        self.levels = nil
        levels?.begin(tag: LevelChannel.tag(for: owner))
        let preroll = orderedPreroll()
        if !preroll.isEmpty { sink(preroll) }
        consumedUpTo = totalSamples
        self.sink = sink
        self.sinkOwner = owner
        self.levels = levels
        self.onRestart = onRestart
        pendingDiscard = false
        recording = MicInputStats()
        levelSum = 0
        levelCount = 0
        return preroll.count
    }

    /// Löst nur, wenn der Empfänger noch diesem Diktat gehört. Liefert die Pegel der Aufnahme.
    @discardableResult
    func detach(owner: String) -> MicInputStats? {
        lock.lock()
        defer { lock.unlock() }
        guard sinkOwner == owner else { return nil }
        consumedUpTo = totalSamples
        sink = nil
        sinkOwner = nil
        levels = nil
        onRestart = nil
        pendingDiscard = false
        return recording
    }

    /// Dauerhafter Mithörer, auch über reset hinweg. Lösen wartet den letzten Aufruf ab.
    func attachListener(owner: String, sink: @escaping @Sendable ([Float]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        listenerOwner = owner
        listener = sink
    }

    func detachListener(owner: String) {
        lock.lock()
        defer { lock.unlock() }
        guard listenerOwner == owner else { return }
        listener = nil
        listenerOwner = nil
    }

    /// Nach Engine-Neustart oder Formatwechsel: Wandler neu, Vorlauf leeren, Stille-Zählung neu.
    func reset() {
        lock.lock()
        converter = nil
        converterInput = nil
        prerollWrite = 0
        prerollFilled = 0
        consumedUpTo = totalSamples
        stats.lastArrivalNs = 0
        silence.reset()
        lock.unlock()
    }

    // MARK: Totes Mikro

    /// Wird einmal beim Start der App gesetzt; Aufruf im Tap-Thread.
    func setSilenceHandler(_ handler: @escaping @Sendable (MicSilenceDetector.Change) -> Void) {
        lock.lock()
        silenceHandler = handler
        lock.unlock()
    }

    /// Vor einem Neustart wegen stummen Mikros: Die angehängte Aufnahme verwirft ihren
    /// bisherigen Ton, sobald der neue Motor liefert, und läuft dann nahtlos weiter.
    func prepareSilenceRestart() {
        lock.lock()
        if sink != nil {
            pendingDiscard = true
            recording.restarts += 1
        }
        lock.unlock()
    }

    /// Seit dem letzten Motorstart kam echter Ton (mindestens ein Puffer ohne digitale Stille).
    var heardSignal: Bool {
        lock.lock()
        defer { lock.unlock() }
        return silence.heardSignal
    }

    /// Wie lange die laufende Stille schon dauert (ms).
    var silentMs: Double {
        lock.lock()
        defer { lock.unlock() }
        return silence.silentSeconds * 1000
    }

    var currentStats: TapStats {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    var lastArrivalNs: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return stats.lastArrivalNs
    }
}

/// Gibt den Puffer genau einmal an den Wandler (der Input-Block ist @Sendable).
private final class OneShotFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
