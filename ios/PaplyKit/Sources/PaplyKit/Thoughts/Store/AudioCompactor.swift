import AVFoundation
import Foundation

/// WAV → m4a (AAC 32 kbit/s mono) nach dem Verschriftlichen (KONZEPT §5.3).
///
/// Aufbewahrung (§5.3 Punkt 6, §7): Ton 30 Tage nach `done`, nur wenn `source.json` existiert;
/// nicht verarbeiteter Ton wird nie automatisch gelöscht; gelöschte Gedanken 30 Tage nach `deletedAt`.
public enum AudioCompactor {
    /// Ton bleibt so lange nach `done`
    public static let audioRetention: TimeInterval = 30 * 24 * 3600
    /// „Zuletzt gelöscht“ bleibt so lange
    public static let trashRetention: TimeInterval = 30 * 24 * 3600
    public static let bitRate = 32_000

    public enum Failure: Error, Sendable, Equatable {
        case empty
        case verification
    }

    /// Schreibt `m4a` (über eine Nachbardatei, erst nach Prüfung umbenannt). Die WAV bleibt unberührt.
    public static func compact(wav: URL, to m4a: URL) throws {
        let input = try AVAudioFile(forReading: wav)
        guard input.length > 0 else { throw Failure.empty }
        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: bitRate,
        ]
        let temp = m4a.deletingLastPathComponent()
            .appendingPathComponent(FileSafety.tempPrefix + UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            let output = try AVAudioFile(forWriting: temp, settings: settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else { throw Failure.empty }
            while input.framePosition < input.length {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
            output.close()
        }
        // Prüfen: lesbar und ungefähr gleich lang (AAC-Vor-/Nachlauf ≤ wenige ms)
        let check = try AVAudioFile(forReading: temp)
        let seconds = Double(check.length) / check.processingFormat.sampleRate
        let expected = Double(input.length) / format.sampleRate
        guard abs(seconds - expected) < 0.5 else { throw Failure.verification }
        FileSafety.applyProtection(temp)
        FileSafety.excludeFromBackup(temp)
        if FileSafety.exists(m4a) { try FileManager.default.removeItem(at: m4a) }
        try FileManager.default.moveItem(at: temp, to: m4a)
        FileSafety.excludeFromBackup(m4a)
    }
}
