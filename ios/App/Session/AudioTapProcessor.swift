@preconcurrency import AVFoundation
import Foundation

/// Läuft im Audio-Tap (eigener Thread): wandelt auf 16 kHz mono Float32, hält den
/// Vorlauf (~0,5 s) und reicht während eines Diktats die Samples weiter.
/// Im Leerlauf wird nichts gespeichert oder gesendet – nur der Ringpuffer im Speicher.
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
    private var levels: LevelChannel?
    private var levelSum: Float = 0
    private var levelCount = 0
    /// Geschätztes Grundrauschen in dBFS: fällt sofort mit, steigt nur langsam (~1 dB/s).
    /// Wird auch im Leerlauf mitgeführt, damit das erste Diktat schon richtig skaliert.
    private var noiseFloorDb: Float = -60
    private var stats = TapStats()

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
        lock.lock()
        let samples = convert(buffer)
        updateStats(buffer: buffer, arrivalNs: arrivalNs)
        guard let samples, !samples.isEmpty else {
            lock.unlock()
            return
        }
        appendPreroll(samples)
        measureLevels(samples, arrivalNs: arrivalNs)
        let sink = self.sink
        if sink != nil { consumedUpTo = totalSamples } // gehört diesem Diktat
        lock.unlock()
        sink?(samples)
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
    @discardableResult
    func attach(owner: String, sink: @escaping @Sendable ([Float]) -> Void, levels: LevelChannel?) -> Int {
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
        levelSum = 0
        levelCount = 0
        return preroll.count
    }

    /// Löst nur, wenn der Empfänger noch diesem Diktat gehört.
    func detach(owner: String) {
        lock.lock()
        if sinkOwner == owner {
            consumedUpTo = totalSamples
            sink = nil
            sinkOwner = nil
            levels = nil
        }
        lock.unlock()
    }

    /// Nach Engine-Neustart oder Formatwechsel: Wandler neu, Vorlauf leeren.
    func reset() {
        lock.lock()
        converter = nil
        converterInput = nil
        prerollWrite = 0
        prerollFilled = 0
        consumedUpTo = totalSamples
        stats.lastArrivalNs = 0
        lock.unlock()
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
