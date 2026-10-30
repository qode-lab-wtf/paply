import Foundation

// Erkennung eines „toten“ Mikros (Vorfall 27.10.2026, 22:12–22:15: der Motor lief, die Tap-Puffer
// kamen pünktlich, aber keine Aufnahme enthielt verwertbaren Ton).
//
// Ein echtes Mikro liefert nie digitale Stille: Selbst in einem stillen Raum rauschen Kapsel und
// Wandler deutlich über −120 dBFS. Reine Nullen, ein stehender Gleichanteil oder Werte unter
// −120 dBFS bedeuten: iOS hat den Eingang stummgeschaltet (z. B. weil die Sitzung in einem
// Zustand startete, in dem die App nicht aufnehmen durfte) oder die Hardware liefert nichts.
//
// Reine Logik ohne AVFoundation – die App misst damit jeden Rohpuffer im Audio-Tap.

/// Pegel eines Rohpuffers (vor der Umwandlung auf 16 kHz). Nur Zahlen, nie Inhalte.
public struct MicBufferLevel: Sendable, Equatable {
    /// Anzahl gemessener Abtastwerte (über alle Kanäle)
    public var samples = 0
    /// größter Betrag
    public var peak: Float = 0
    /// Σx² (für RMS)
    public var sumSquares: Double = 0
    /// Σ(x − Mittelwert)² je Kanal – RMS ohne Gleichanteil
    public var acSumSquares: Double = 0
    /// Σ(x[n] − x[n−1])² – grober Hochpass (+6 dB/Okt.): zeigt, ob überhaupt Bewegung im Signal ist
    public var diffSumSquares: Double = 0
    /// Alle Werte exakt 0
    public var allZero = true
    /// NaN oder ±∞ (ein echtes Mikro liefert das nie)
    public var nonFinite = 0

    public init() {}

    /// Misst einen Kanal (bzw. verschränkte Daten) eines Rohpuffers.
    public static func measure(_ x: UnsafeBufferPointer<Float>) -> MicBufferLevel {
        var level = MicBufferLevel()
        let n = x.count
        guard n > 0 else { return level }
        level.samples = n
        var sum = 0.0
        var finite = 0
        for value in x {
            guard value.isFinite else {
                level.nonFinite += 1
                continue
            }
            finite += 1
            let v = Double(value)
            sum += v
            level.sumSquares += v * v
            let magnitude = abs(value)
            if magnitude > level.peak { level.peak = magnitude }
            if value != 0 { level.allZero = false }
        }
        if level.nonFinite > 0 { level.allZero = false }
        let mean = finite > 0 ? sum / Double(finite) : 0
        var previous: Float?
        for value in x where value.isFinite {
            let ac = Double(value) - mean
            level.acSumSquares += ac * ac
            if let previous {
                let d = Double(value) - Double(previous)
                level.diffSumSquares += d * d
            }
            previous = value
        }
        return level
    }

    /// Zweiten Kanal desselben Puffers hinzunehmen.
    public mutating func merge(_ other: MicBufferLevel) {
        samples += other.samples
        peak = max(peak, other.peak)
        sumSquares += other.sumSquares
        acSumSquares += other.acSumSquares
        diffSumSquares += other.diffSumSquares
        allZero = allZero && other.allZero
        nonFinite += other.nonFinite
    }

    /// RMS ohne Gleichanteil in dBFS (−160 = exakt nichts).
    public var acRmsDbfs: Double { MicLevel.dbfs(meanSquare: samples > 0 ? acSumSquares / Double(samples) : 0) }

    /// Gleichanteil ≥ 10 dB über dem Wechselanteil und über −60 dBFS. Ein funktionierendes Mikro
    /// (iOS filtert den Gleichanteil weg) liefert das praktisch nie. Nur fürs Protokoll – die
    /// Selbstheilung greift erst bei digitaler Stille.
    public var isOffsetDominated: Bool {
        guard samples > 0 else { return false }
        let n = Double(samples)
        let ac = acSumSquares / n
        let dc = max(0, sumSquares - acSumSquares) / n
        return dc > 1e-6 && dc > 10 * ac
    }

    /// Digitale Stille: exakt 0, nur Gleichanteil oder Wechselanteil unter −120 dBFS – oder
    /// unbrauchbare Werte (NaN/∞). Ein leerer Puffer ist nie „still“ (nichts gemessen).
    public var isDigitalSilence: Bool {
        guard samples > 0 else { return false }
        return allZero || nonFinite > 0 || acRmsDbfs < MicSilenceDetector.thresholdDbfs
    }
}

public enum MicLevel {
    /// Untergrenze im Protokoll: −160 dBFS heißt „exakt 0“.
    public static let floorDbfs = -160.0

    public static func dbfs(meanSquare: Double) -> Double {
        guard meanSquare.isFinite, meanSquare > 0 else { return floorDbfs }
        return max(floorDbfs, 10 * log10(meanSquare))
    }

    public static func dbfs(peak: Float) -> Double {
        guard peak.isFinite, peak > 0 else { return floorDbfs }
        return max(floorDbfs, 20 * log10(Double(peak)))
    }
}

/// Merkt sich, ob der laufende Motor seit ≥ 1,5 s nur digitale Stille liefert („totes Mikro“).
///
/// Jeder Puffer mit echtem Ton setzt die Zählung zurück. Gemeldet werden nur Wechsel:
/// `.becameSilent` einmal nach 1,5 s Stille, `.becameAlive`, sobald danach wieder Ton kommt.
/// Nach einem Motor-Neustart `reset()` – auch die ersten Puffer eines neuen Motors zählen dann neu.
public struct MicSilenceDetector: Sendable, Equatable {
    public static let thresholdDbfs = -120.0
    public static let silentAfterSeconds = 1.5

    public enum Change: Sendable, Equatable {
        case becameSilent
        case becameAlive
    }

    /// Mikro gilt gerade als tot
    public private(set) var isSilent = false
    /// Dauer der laufenden Stille (Sekunden)
    public private(set) var silentSeconds = 0.0
    /// Seit dem letzten `reset()` kam mindestens ein Puffer mit echtem Ton
    public private(set) var heardSignal = false

    public init() {}

    /// Einen Puffer bewerten. `seconds` = Dauer des Puffers.
    public mutating func feed(_ level: MicBufferLevel, seconds: Double) -> Change? {
        guard level.samples > 0, seconds > 0 else { return nil }
        if level.isDigitalSilence {
            silentSeconds += seconds
            // kleine Toleranz: 15 × 0,1 s ergibt in Gleitkomma knapp unter 1,5
            if !isSilent, silentSeconds >= Self.silentAfterSeconds - 1e-6 {
                isSilent = true
                return .becameSilent
            }
            return nil
        }
        silentSeconds = 0
        heardSignal = true
        if isSilent {
            isSilent = false
            return .becameAlive
        }
        return nil
    }

    public mutating func reset() {
        self = MicSilenceDetector()
    }
}

/// Pegel über eine ganze Aufnahme (Diktat oder Gedanke) – fürs Protokoll, nie Inhalte.
public struct MicInputStats: Sendable, Equatable {
    public private(set) var buffers = 0
    /// Puffer mit exakt 0 in allen Werten
    public private(set) var zeroBuffers = 0
    /// Puffer mit digitaler Stille (exakt 0, nur Gleichanteil, < −120 dBFS oder NaN)
    public private(set) var silentBuffers = 0
    /// Puffer, in denen ein Gleichanteil den Ton um ≥ 10 dB überragt (Verdacht: Wandler ohne Mikro)
    public private(set) var offsetBuffers = 0
    public private(set) var samples = 0
    public private(set) var peak: Float = 0
    public private(set) var sumSquares: Double = 0
    public private(set) var acSumSquares: Double = 0
    public private(set) var diffSumSquares: Double = 0
    /// Spitze nach der Umwandlung auf 16 kHz (zeigt eine kaputte Umwandlung)
    public var convertedPeak: Float = 0
    /// Neustarts wegen stummen Mikros während der Aufnahme
    public var restarts = 0

    public init() {}

    public mutating func add(_ level: MicBufferLevel) {
        guard level.samples > 0 else { return }
        buffers += 1
        if level.allZero { zeroBuffers += 1 }
        if level.isDigitalSilence { silentBuffers += 1 }
        if level.isOffsetDominated { offsetBuffers += 1 }
        samples += level.samples
        peak = max(peak, level.peak)
        sumSquares += level.sumSquares
        acSumSquares += level.acSumSquares
        diffSumSquares += level.diffSumSquares
    }

    public var peakDbfs: Double { MicLevel.dbfs(peak: peak) }
    public var rmsDbfs: Double { MicLevel.dbfs(meanSquare: samples > 0 ? sumSquares / Double(samples) : 0) }
    public var acRmsDbfs: Double { MicLevel.dbfs(meanSquare: samples > 0 ? acSumSquares / Double(samples) : 0) }
    public var diffRmsDbfs: Double { MicLevel.dbfs(meanSquare: samples > 0 ? diffSumSquares / Double(samples) : 0) }
    public var convertedPeakDbfs: Double { MicLevel.dbfs(peak: convertedPeak) }

    /// Die ganze Aufnahme war digitale Stille (mindestens 3 Puffer, damit ein einzelner
    /// Anlaufpuffer eines frisch gestarteten Motors nicht zählt).
    public var wasSilent: Bool { buffers >= 3 && silentBuffers == buffers }
}

/// Zweite Regel für ein unbrauchbares Mikro, die auch einen lauten Eingang ohne Sprache fängt
/// (Vorfall 27.10.2026: wohl ein Gleichanteil statt Nullen – die Stille-Erkennung sah ihn nicht):
/// Zwei abgeschlossene Aufnahmen hintereinander, beide ohne erkannte Sprache (VAD), beide
/// mindestens 2 s lang und höchstens 3 Minuten auseinander → Mikro neu starten.
///
/// - „Abgeschlossen“ meldet nur der Aufrufer (Tipp auf „fertig“, Gedanke „Fertig“) – Abbrechen,
///   Wischen und Durchschalten zählen nicht.
/// - Kürzere Aufnahmen ohne Sprache zählen nicht mit und unterbrechen die Folge auch nicht.
/// - Jede erkannte Sprache setzt zurück. Ein Fehlalarm kostet nur ein kurzes Aufblitzen der App.
public struct NoSpeechStreak: Sendable, Equatable {
    public static let minSeconds = 2.0
    public static let windowSeconds = 180.0
    public static let needed = 2

    /// Zeitpunkte (monotone Sekunden) der zählenden Aufnahmen ohne Sprache
    public private(set) var times: [Double] = []

    public init() {}

    /// Sprache erkannt (auch in einer Aufnahme, die später abgebrochen wird).
    public mutating func speechHeard() {
        times = []
    }

    /// Eine abgeschlossene Aufnahme melden. `seconds` = Länge des Tons, `now` = monotone Sekunden.
    /// true = jetzt neu starten (die Folge beginnt danach von vorn).
    public mutating func completed(speech: Bool, seconds: Double, now: Double) -> Bool {
        if speech {
            times = []
            return false
        }
        guard seconds >= Self.minSeconds - 1e-9 else { return false }
        times = times.filter { now - $0 <= Self.windowSeconds }
        times.append(now)
        guard times.count >= Self.needed else { return false }
        times = []
        return true
    }

    /// Ausgelöst, aber gerade läuft eine neue Aufnahme: scharf lassen – die nächste abgeschlossene
    /// Aufnahme ohne Sprache löst wieder aus (Neustart nie mitten in eine laufende Aufnahme).
    public mutating func keepArmed(now: Double) {
        times = Array(repeating: now, count: Self.needed - 1)
    }
}
