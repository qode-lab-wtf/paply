import AVFoundation
import Foundation

/// Additiver Lesezugang zur vorhandenen Sprachaktivitätserkennung für App-Mithörer.
public enum SpeechRegions {
    public static func read(_ url: URL) throws -> [Range<Double>] {
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_000)
        else { return [] }
        var detector = VoiceActivityDetector()
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { break }
            detector.process(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
        }
        guard detector.speechDetected else { return [] }
        var regions: [Range<Double>] = []
        var start: Int?
        for frame in 0..<detector.frameCount {
            if !detector.isPause(frame) {
                if start == nil { start = frame }
            } else if let first = start {
                regions.append(Double(first) * 0.03..<Double(frame) * 0.03)
                start = nil
            }
        }
        if let start { regions.append(Double(start) * 0.03..<Double(detector.frameCount) * 0.03) }
        return regions
    }
}
