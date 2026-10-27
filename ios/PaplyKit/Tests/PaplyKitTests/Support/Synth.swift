import Foundation

/// Synthetisches 16-kHz-Testaudio.
enum Synth {
    static let rate = 16_000.0

    static func samples(_ seconds: Double) -> Int { Int(seconds * rate) }

    static func amplitude(rmsDbfs: Double) -> Float { Float(pow(10, rmsDbfs / 20)) }

    /// Deterministisches weißes Rauschen mit gegebenem RMS-Pegel.
    static func noise(_ seconds: Double, dbfs: Double, seed: UInt64 = 42) -> [Float] {
        var state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
        let scale = amplitude(rmsDbfs: dbfs) * 1.732 // Gleichverteilung: RMS = A/√3
        return (0..<samples(seconds)).map { _ in
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return (Float(Double(state % 2_000_001) / 1_000_000) - 1) * scale
        }
    }

    /// Stimmhafter „Vokal“: Grundton mit Obertönen (periodisch), RMS-Pegel `dbfs`.
    static func voice(_ seconds: Double, dbfs: Double, f0: Double = 140) -> [Float] {
        let n = samples(seconds)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            var v = 0.0
            for k in 1...8 { v += sin(2 * .pi * f0 * Double(k) * t) / Double(k) }
            out[i] = Float(v)
        }
        let rms = sqrt(out.reduce(0) { $0 + Double($1 * $1) } / Double(max(1, n)))
        let gain = Double(amplitude(rmsDbfs: dbfs)) / max(rms, 1e-9)
        return out.map { $0 * Float(gain) }
    }

    /// Sprechartige Folge: Silben (stimmhaft) mit kurzen Lücken wie zwischen Wörtern.
    static func speech(_ seconds: Double, dbfs: Double = -24, syllable: Double = 0.22, gap: Double = 0.09) -> [Float] {
        var out: [Float] = []
        var f0 = 120.0
        while Double(out.count) / rate < seconds {
            out += voice(syllable, dbfs: dbfs, f0: f0)
            out += [Float](repeating: 0, count: samples(gap))
            f0 = f0 >= 180 ? 120 : f0 + 15
        }
        return Array(out.prefix(samples(seconds)))
    }

    static func silence(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: samples(seconds)) }

    /// Raumrauschen unter das Signal mischen.
    static func withFloor(_ signal: [Float], dbfs: Double = -60, seed: UInt64 = 7) -> [Float] {
        let floor = noise(Double(signal.count) / rate, dbfs: dbfs, seed: seed)
        return zip(signal, floor).map { $0 + $1 }
    }

    /// Einzelne kurze Klicks (5 ms, laut) im Abstand `every`.
    static func clicks(_ seconds: Double, every: Double = 0.3, dbfs: Double = -10) -> [Float] {
        var out = silence(seconds)
        let length = samples(0.005)
        var position = samples(0.1)
        let a = amplitude(rmsDbfs: dbfs)
        while position + length < out.count {
            for i in 0..<length { out[position + i] = i % 2 == 0 ? a : -a }
            position += samples(every)
        }
        return out
    }

    /// Braunes Rauschen (Rumpeln, Auto), RMS-Pegel `dbfs`.
    static func brown(_ seconds: Double, dbfs: Double, seed: UInt64 = 5) -> [Float] {
        let white = noise(seconds, dbfs: 0, seed: seed)
        var out = [Float](repeating: 0, count: white.count)
        var accumulator: Float = 0
        for i in white.indices {
            accumulator = 0.995 * accumulator + white[i]
            out[i] = accumulator
        }
        return scaled(out, dbfs: dbfs)
    }

    /// Summe von Sinustönen (Frequenz, Amplitude), RMS-Pegel `dbfs`.
    static func tones(_ seconds: Double, _ partials: [(Double, Double)], dbfs: Double) -> [Float] {
        let n = samples(seconds)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            out[i] = Float(partials.reduce(0) { $0 + $1.1 * sin(2 * .pi * $1.0 * t) })
        }
        return scaled(out, dbfs: dbfs)
    }

    /// Lautstärke-Rampe (z. B. Auto fährt vorbei): von `from` auf `to` dB.
    static func ramp(_ signal: [Float], from: Double, to: Double) -> [Float] {
        let n = max(1, signal.count - 1)
        return signal.enumerated().map { i, v in v * Float(pow(10, (from + (to - from) * Double(i) / Double(n)) / 20)) }
    }

    static func scaled(_ signal: [Float], dbfs: Double) -> [Float] {
        let rms = sqrt(signal.reduce(0) { $0 + Double($1 * $1) } / Double(max(1, signal.count)))
        let gain = Float(Double(amplitude(rmsDbfs: dbfs)) / max(rms, 1e-12))
        return signal.map { $0 * gain }
    }
}
