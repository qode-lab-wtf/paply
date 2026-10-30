import AVFoundation
import Foundation

/// Kodiert 16-kHz-Mono-PCM für den Upload: FLAC (verlustfrei, etwa halb so groß wie WAV)
/// über AVAudioFile; schlägt das fehl, WAV-PCM16.
package enum AudioEncoder {
    package static let sampleRate = 16_000.0

    package struct Encoded: Sendable {
        package let data: Data
        package let fileName: String
        package let mimeType: String
        /// Dauer der Kodierung in ms.
        package let encodeMs: Double
        var isFLAC: Bool { mimeType == "audio/flac" }
    }

    package static func encode(_ samples: [Int16], preferFLAC: Bool = true) -> Encoded {
        encode(samples[...], preferFLAC: preferFLAC)
    }

    /// Kodiert direkt aus einem Ausschnitt (keine Kopie des Gesamtaudios beim Rückfall).
    package static func encode(_ samples: ArraySlice<Int16>, preferFLAC: Bool = true) -> Encoded {
        let start = DispatchTime.now()
        if preferFLAC, let data = try? flac(samples) {
            return Encoded(data: data, fileName: "audio.flac", mimeType: "audio/flac", encodeMs: elapsedMs(since: start))
        }
        return Encoded(data: wav(samples), fileName: "audio.wav", mimeType: "audio/wav", encodeMs: elapsedMs(since: start))
    }

    /// Temporäre FLAC-Dateien liegen hier und werden immer sofort gelöscht.
    static let temporaryPrefix = "paply-"

    /// FLAC über eine temporäre Datei, die in jedem Fall (Erfolg, Fehler) sofort gelöscht
    /// wird. Die Kodierung ist synchron – ein Abbruch kann keine Datei zurücklassen.
    static func flac(_ samples: ArraySlice<Int16>,
                     directory: URL = FileManager.default.temporaryDirectory) throws -> Data {
        guard !samples.isEmpty else { throw EncoderError.empty }
        let url = directory.appendingPathComponent("\(temporaryPrefix)\(UUID().uuidString).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitDepthHintKey: 16,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: .pcmFormatInt16, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.int16ChannelData?[0] else { throw EncoderError.buffer }
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: samples.count)
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            try file.write(from: buffer)
            file.close()
        }
        let data = try Data(contentsOf: url)
        // Kopfzeile prüfen: ein leerer/kaputter Container darf nie hochgeladen werden.
        guard data.count > 42, data.prefix(4) == Data("fLaC".utf8) else { throw EncoderError.invalid }
        return data
    }

    static func wav(_ samples: ArraySlice<Int16>) -> Data {
        let dataBytes = samples.count * 2
        var data = Data(capacity: 44 + dataBytes)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataBytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataBytes))
        // Apple-Plattformen sind Little-Endian: Speicherabbild = WAV-Format.
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    /// Float32 (−1…1) → Int16 mit Begrenzung.
    package static func int16(_ samples: [Float]) -> [Int16] {
        samples.map { value in
            let clamped = max(-1, min(1, value.isFinite ? value : 0))
            return Int16(clamped < 0 ? clamped * 32768 : clamped * 32767)
        }
    }

    enum EncoderError: Error { case empty, buffer, invalid }
}

func elapsedMs(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}
