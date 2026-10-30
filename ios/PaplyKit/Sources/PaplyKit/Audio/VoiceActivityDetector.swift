import Accelerate
import Foundation

/// Sprachaktivitätserkennung für 16 kHz mono Float32.
///
/// Jedes 30-ms-Fenster liefert Pegel und Periodizität (normierte Autokorrelation im
/// Tonhöhenbereich 75–400 Hz): Vokale sind periodisch, Klicks, Atmen, Rascheln und
/// Lüfter nicht. Bewertet wird relativ zum Grundrauschen: 15. Perzentil der Pegel der
/// letzten 30 s. Jedes Fenster wird mit dem Grundrauschen von etwa 15 s nach ihm
/// gemessen, frühe Silben also auch rückwirkend am später erfassten Rauschen.
///
/// - stimmhaft: Pegel ≥ Grundrauschen + 6 dB und Periodizität ≥ 0,6 – trägt auch leise
///   Sprache in lauter Umgebung (10–14 dB über einem Café).
/// - aktiv: Pegel > Grundrauschen + 15 dB (mind. −65 dBFS) – Desktop-Kennzahl `speechMs`.
/// - hell-aktiv: aktiv und ≥ 8 % Nulldurchgänge (Schwerpunkt über ~600 Hz) – Flüstern und
///   stimmlose Laute; tieffrequentes Rumpeln (Auto, Lüfter) zählt nicht.
/// - Pause: Pegel < Grundrauschen + 10 dB und nicht stimmhaft – ein leiser werdender
///   Vokal ist nie Pause, deshalb kein Schnitt mitten im Wort.
///
/// `speechDetected` wird true (und bleibt es), sobald
/// - ≥ 150 ms stimmhafte Fenster in Folgen von ≥ 90 ms vorliegen (ein Klick ist kürzer,
///   Atmen ist nicht periodisch), oder
/// - innerhalb von 2,5 s mindestens 1 s hell-aktiv in ≥ 3 Abschnitten von je ≥ 90 ms liegt
///   (Flüstern ist nicht periodisch, hat aber Silbenstruktur; Atemzüge sind einzelne
///   Abschnitte im Abstand mehrerer Sekunden).
package struct VoiceActivityDetector: Sendable {
    package static let sampleRate = 16_000.0
    package static let frameLength = 480
    package static let frameMs = 30.0
    /// Absolute Untergrenze für Aktivität; die Schwelle folgt sonst dem Grundrauschen.
    static let absoluteThresholdDbfs = -65.0
    static let speechAboveFloorDb = 15.0
    static let voicedAboveFloorDb = 6.0
    static let pauseAboveFloorDb = 10.0
    static let voicedPeriodicity: Float = 0.6
    static let brightZeroCrossings: Float = 0.08

    static let minRunFrames = 3              // 90 ms: kürzer ist ein Klick
    static let voicedSpeechMs = 150.0
    static let whisperWindowFrames = 83      // 2,5 s
    static let whisperActiveFrames = 34      // ≈ 1 s
    static let whisperMinRuns = 3

    static let floorWindowFrames = 1_000     // 30 s
    static let floorStepFrames = 33          // Grundrauschen ~ jede Sekunde merken
    static let floorLookaheadSteps = 15      // ~15 s nach dem Fenster

    struct Frame: Sendable, Equatable {
        var dbfs: Float
        var periodicity: Float
        /// Anteil der Nulldurchgänge (0…1); hoch bei Rauschen/Zischlauten, niedrig bei Rumpeln.
        var zeroCrossings: Float = 0.5
    }

    private(set) var frames: [Frame] = []
    private var window: [Float] = []
    private var floorHistory: [Float] = []
    private var pending: [Float] = []
    private var latched = false
    package private(set) var peakDbfs: Double = -120

    package init() {}

    package var frameCount: Int { frames.count }
    var durationMs: Double { Double(frames.count) * Self.frameMs }
    /// Pegel des letzten Fensters (z. B. für eine Pegelanzeige).
    package var lastLevelDbfs: Double { frames.last.map { Double($0.dbfs) } ?? -120 }

    /// Aktuelles Grundrauschen: 15. Perzentil (nearest rank) der letzten 30 s.
    var floorDbfs: Double {
        guard !window.isEmpty else { return -120 }
        let rank = max(0, Int((Double(window.count) * 0.15).rounded(.up)) - 1)
        return Double(window[rank])
    }

    /// Grundrauschen, mit dem Fenster `index` bewertet wird.
    func floor(at index: Int) -> Float {
        let step = index / Self.floorStepFrames + Self.floorLookaheadSteps
        return step < floorHistory.count ? floorHistory[step] : Float(floorDbfs)
    }

    func isActive(_ index: Int) -> Bool {
        frames[index].dbfs > max(Float(Self.absoluteThresholdDbfs), floor(at: index) + Float(Self.speechAboveFloorDb))
    }

    /// Aktiv und breitbandig (Flüstern, stimmlose Laute), nicht tieffrequentes Rumpeln.
    func isBrightActive(_ index: Int) -> Bool {
        isActive(index) && frames[index].zeroCrossings >= Self.brightZeroCrossings
    }

    func isVoiced(_ index: Int) -> Bool {
        let frame = frames[index]
        return frame.periodicity >= Self.voicedPeriodicity
            && frame.dbfs >= max(Float(Self.absoluteThresholdDbfs - 5), floor(at: index) + Float(Self.voicedAboveFloorDb))
    }

    func isPause(_ index: Int) -> Bool {
        frames[index].dbfs < max(Float(Self.absoluteThresholdDbfs - 5), floor(at: index) + Float(Self.pauseAboveFloorDb))
            && !isVoiced(index)
    }

    /// true, sobald echte Sprache erkannt wurde (bleibt danach true).
    package var speechDetected: Bool { latched }

    package mutating func process(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { process($0) }
    }

    package mutating func process(_ samples: UnsafeBufferPointer<Float>) {
        var offset = 0
        let n = Self.frameLength
        if !pending.isEmpty {
            let take = min(n - pending.count, samples.count)
            pending.append(contentsOf: samples[0..<take])
            offset = take
            if pending.count == n {
                let frame = pending
                pending.removeAll(keepingCapacity: true)
                frame.withUnsafeBufferPointer { addFrame($0) }
            }
        }
        while offset + n <= samples.count {
            addFrame(UnsafeBufferPointer(rebasing: samples[offset..<(offset + n)]))
            offset += n
        }
        if offset < samples.count { pending.append(contentsOf: samples[offset...]) }
        if !latched, !frames.isEmpty {
            latched = hasSpeech(in: 0..<frames.count)
        }
    }

    /// Fügt ein bereits analysiertes Fenster hinzu (Tests, Desktop-Vergleich).
    mutating func appendFrame(dbfs: Float, periodicity: Float, zeroCrossings: Float = 0.5) {
        insert(Frame(dbfs: dbfs, periodicity: periodicity, zeroCrossings: zeroCrossings))
        if !latched { latched = hasSpeech(in: 0..<frames.count) }
    }

    private mutating func addFrame(_ samples: UnsafeBufferPointer<Float>) {
        insert(Self.analyze(samples))
    }

    private mutating func insert(_ frame: Frame) {
        frames.append(frame)
        // Sortiertes 30-s-Fenster: Perzentil billig (binäre Suche + memmove).
        window.insert(frame.dbfs, at: Self.lowerBound(window, frame.dbfs))
        if frames.count > Self.floorWindowFrames {
            let leaving = frames[frames.count - Self.floorWindowFrames - 1].dbfs
            let index = Self.lowerBound(window, leaving)
            if index < window.count, window[index] == leaving { window.remove(at: index) }
        }
        if frames.count % Self.floorStepFrames == 0 { floorHistory.append(Float(floorDbfs)) }
        peakDbfs = max(peakDbfs, Double(frame.dbfs))
    }

    private static func lowerBound(_ sorted: [Float], _ value: Float) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Stimmhafte Grundfrequenz 70–400 Hz → Verzögerungen 40…228 Abtastwerte.
    static let minPitchLag = Int(sampleRate / 400)
    static let maxPitchLag = Int(sampleRate / 70)

    /// RMS-Pegel (dBFS, mind. −120) und Periodizität (0…1) eines Fensters.
    ///
    /// Periodizität: normierte Autokorrelation nach einem Hochpass bei ~150 Hz (zweifach
    /// einpolig, 12 dB/Oktave). Gezählt werden nur echte Gipfel (lokale Maxima) nach dem
    /// ersten Nulldurchgang im Stimmbereich 70–400 Hz – ein bloß langsam abfallender
    /// Verlauf (Rumpeln, braunes Rauschen) ist keine Tonhöhe.
    ///
    /// Gemessen (Offline-Vergleich, Anteil Fenster ≥ 0,6): Stimme 10 dB über Rauschen 72 %,
    /// Stimme 6 dB **unter** Autolärm 65 % (ohne Filter 7 %); braunes Rauschen, Netzbrummen
    /// (50 Hz + Obertöne) und ein Dur-Akkord 0 %. Vorverzerrung (x[n] − 0,95·x[n−1]) wurde
    /// verworfen: Sie hebt Rauschen über die tiefen Stimm-Obertöne und senkte Stimme im
    /// Rauschen auf 0 %.
    static func analyze(_ input: UnsafeBufferPointer<Float>) -> Frame {
        let n = input.count
        guard n > 0, let base = input.baseAddress else { return Frame(dbfs: -120, periodicity: 0) }
        var mean: Float = 0
        vDSP_meanv(base, 1, &mean, vDSP_Length(n))
        guard mean.isFinite else { return Frame(dbfs: -120, periodicity: 0) }
        var x = [Float](repeating: 0, count: n)
        var negMean = -mean
        vDSP_vsadd(base, 1, &negMean, &x, 1, vDSP_Length(n))
        var meanSquare: Float = 0
        vDSP_measqv(x, 1, &meanSquare, vDSP_Length(n))
        let dbfs = max(-120, 10 * log10(Double(meanSquare)))
        guard dbfs.isFinite, dbfs > -75 else {
            return Frame(dbfs: Float(dbfs.isFinite ? dbfs : -120), periodicity: 0, zeroCrossings: 0)
        }
        var crossings = 0
        for i in 1..<n where (x[i - 1] < 0) != (x[i] < 0) { crossings += 1 }
        return Frame(dbfs: Float(dbfs), periodicity: periodicity(x), zeroCrossings: Float(crossings) / Float(max(1, n - 1)))
    }

    static func periodicity(_ signal: [Float]) -> Float {
        periodicityRaw(highPass(signal))
    }

    /// Zweifach einpoliger Hochpass bei ~150 Hz (a = RC/(RC + 1/16000)).
    static func highPass(_ signal: [Float]) -> [Float] {
        let a: Float = 0.9428
        var x = signal
        for _ in 0..<2 {
            var previousOut: Float = 0
            var previousIn = x.first ?? 0
            for i in x.indices {
                let input = x[i]
                let output = a * (previousOut + input - previousIn)
                x[i] = output
                previousOut = output
                previousIn = input
            }
        }
        return x
    }

    /// Echte Gipfel der normierten Autokorrelation (ohne Vorfilter).
    static func periodicityRaw(_ y: [Float]) -> Float {
        let n = y.count
        let maxLag = min(maxPitchLag + 1, n / 2)
        guard maxLag > minPitchLag + 1 else { return 0 }
        var prefix = [Float](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + y[i] * y[i] }
        var r = [Float](repeating: 0, count: maxLag + 1)
        y.withUnsafeBufferPointer { buffer in
            let p = buffer.baseAddress!
            for lag in 1...maxLag {
                let count = n - lag
                var dot: Float = 0
                vDSP_dotpr(p, 1, p + lag, 1, &dot, vDSP_Length(count))
                let denominator = ((prefix[count] - prefix[0]) * (prefix[n] - prefix[lag])).squareRoot()
                r[lag] = denominator > 0 ? dot / denominator : 0
            }
        }
        guard let firstZero = (1...maxLag).first(where: { r[$0] <= 0 }) else { return 0 }
        var best: Float = 0
        let first = max(minPitchLag, firstZero + 1)
        if first < maxLag {
            for lag in first..<maxLag where r[lag] > r[lag - 1] && r[lag] >= r[lag + 1] {
                best = max(best, r[lag])
            }
        }
        return best
    }

    struct Activity: Equatable {
        var speechMs: Double
        var voicedMs: Double
        /// Flüsterartige, silbige Aktivität ohne Periodizität gefunden.
        var whisperLike: Bool
        var peakDbfs: Double
        /// Anzahl hell-aktiver Folgen ab 90 ms.
        var activeRuns: Int = 0
    }

    /// Aktivität in einem Fensterbereich.
    func activity(in range: Range<Int>) -> Activity {
        let range = range.clamped(to: 0..<frames.count)
        var speechFrames = 0, voicedFrames = 0
        var activeStart = 0, activeLength = 0, voicedLength = 0
        var runs: [(start: Int, length: Int)] = []
        var peak: Float = -120
        for index in range {
            peak = max(peak, frames[index].dbfs)
            if isActive(index) { speechFrames += 1 }
            if isBrightActive(index) {
                if activeLength == 0 { activeStart = index }
                activeLength += 1
            } else {
                if activeLength >= Self.minRunFrames { runs.append((activeStart, activeLength)) }
                activeLength = 0
            }
            if isVoiced(index) {
                voicedLength += 1
            } else {
                if voicedLength >= Self.minRunFrames { voicedFrames += voicedLength }
                voicedLength = 0
            }
        }
        if activeLength >= Self.minRunFrames { runs.append((activeStart, activeLength)) }
        if voicedLength >= Self.minRunFrames { voicedFrames += voicedLength }
        return Activity(speechMs: Double(speechFrames) * Self.frameMs,
                        voicedMs: Double(voicedFrames) * Self.frameMs,
                        whisperLike: Self.hasSyllabicBurst(runs),
                        peakDbfs: Double(peak), activeRuns: runs.count)
    }

    /// Stimmhafte Zeit (ms) zwischen zwei Zeitpunkten (Sekunden ab Aufnahmebeginn).
    func voicedMs(fromSeconds start: Double, toSeconds end: Double) -> Double {
        let first = max(0, Int((start * 1000 / Self.frameMs).rounded(.down)))
        let last = min(frames.count, Int((end * 1000 / Self.frameMs).rounded(.up)))
        guard last > first else { return 0 }
        return activity(in: first..<last).voicedMs
    }

    /// Gibt es ein 2,5-s-Fenster mit ≥ 3 Abschnitten und zusammen ≈ ≥ 1 s Aktivität?
    static func hasSyllabicBurst(_ runs: [(start: Int, length: Int)]) -> Bool {
        var first = 0, active = 0
        for last in runs.indices {
            active += runs[last].length
            while first < last, runs[last].start + runs[last].length - runs[first].start > whisperWindowFrames {
                active -= runs[first].length
                first += 1
            }
            if last - first + 1 >= whisperMinRuns && active >= whisperActiveFrames { return true }
        }
        return false
    }

    /// Enthält der Bereich echte Sprache (gleiche Regel wie `speechDetected`)?
    package func hasSpeech(in range: Range<Int>) -> Bool {
        let a = activity(in: range)
        return a.voicedMs >= Self.voicedSpeechMs || a.whisperLike
    }

    /// Irgendeine Sprachspur: eine stimmhafte oder aktive Folge ab 90 ms. Für das letzte
    /// Stück nach dem letzten Schnitt – ein kurzes Schlusswort („Ja.“, ~120 ms Vokal) darf
    /// nicht verloren gehen; Halluzinationen fangen Stille- und Echo-Filter ab.
    func hasAnyActivity(in range: Range<Int>) -> Bool {
        let a = activity(in: range)
        return a.voicedMs >= Double(Self.minRunFrames) * Self.frameMs || a.activeRuns > 0
    }

    /// Länge der Pause (in Fenstern), die am Ende von `end` liegt.
    func trailingPauseFrames(endingAt end: Int) -> Int {
        var count = 0
        var index = min(end, frames.count) - 1
        while index >= 0, isPause(index) {
            count += 1
            index -= 1
        }
        return count
    }

    /// Desktop-kompatible Zusammenfassung (für den Stillefilter), optional für einen Bereich.
    func meta(frameRange: Range<Int>? = nil) -> VoiceActivityMeta {
        let range = (frameRange ?? 0..<frames.count).clamped(to: 0..<frames.count)
        let a = activity(in: range)
        let duration = Double(range.count) * Self.frameMs
        let peak = range.isEmpty ? -120 : a.peakDbfs
        return VoiceActivityMeta(
            durationMs: duration, measuredMs: duration, speechMs: a.speechMs,
            peakDbfs: peak, floorDbfs: min(floorDbfs, peak),
            maxGapMs: Self.frameMs, voicedMs: a.voicedMs)
    }
}
