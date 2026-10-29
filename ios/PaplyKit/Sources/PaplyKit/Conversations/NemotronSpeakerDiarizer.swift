import AVFoundation
import CoreML
import FluidAudio
import Foundation
import Darwin

/// Lokaler Nemotron-Motor. Der Ordner enthält fast128.mlmodelc und learnable_sil_emb.bin.
/// CAM++ liefert getrennt davon die lokal vergleichbaren Stimmabdrücke.
public enum SpeakerProcessingDeferred: Error { case thermal }

public struct NemotronSpeakerDiarizer: SpeakerDiarizing {
    public let embeddingModel = CAMVoiceEmbedding.modelID
    public let directory: URL
    private static var computeUnits: [MLComputeUnits] {
        #if os(iOS)
        var info = utsname(); uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        if machine.hasPrefix("iPhone"),
           let generation = Int(machine.dropFirst(6).split(separator: ",")[0]), generation <= 13 {
            // A12–A14: große monolithische Graphen nicht auf die ältere ANE zwingen.
            return [.cpuAndGPU, .cpuOnly]
        }
        #endif
        return [.all, .cpuAndGPU, .cpuOnly]
    }
    public init(directory: URL) { self.directory = directory }

    public func voiceprint(audio: URL) async throws -> VoicePrint? {
        let result = try await diarize(audio: audio, expectedSpeakers: nil) { _ in }
        let total = result.speechSeconds.values.reduce(0, +)
        guard let dominant = result.speechSeconds.max(by: { $0.value < $1.value }),
              dominant.value >= 8, dominant.value >= total * 0.9,
              let vector = result.centroids[dominant.key] else { return nil }
        return VoicePrint(vector: vector, model: embeddingModel, seconds: dominant.value, source: .enrollment)
    }

    public func diarize(audio: URL, expectedSpeakers: Int?,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization {
        let directory = directory
        let worker = Task.detached(priority: .utility) {
            var lastError: any Error = ThoughtStoreError.unavailable
            // CoreML entscheidet innerhalb des erlaubten Rechenwegs über die tatsächliche Platzierung.
            for units in Self.computeUnits {
                try Task.checkCancellation()
                do { return try Self.process(audio: audio, directory: directory, units: units, progress: progress) }
                catch SpeakerProcessingDeferred.thermal { throw SpeakerProcessingDeferred.thermal }
                catch { lastError = error }
            }
            try Task.checkCancellation()
            throw lastError
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func checkThermal() throws {
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            throw SpeakerProcessingDeferred.thermal
        }
    }

    private static func process(audio: URL, directory: URL, units: MLComputeUnits,
                                progress: @Sendable (Double) -> Void) throws -> Diarization {
        try checkThermal()
        let config = Nemotron3Config.fast128
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        let model = try MLModel(contentsOf: directory.appendingPathComponent(config.modelFileName), configuration: configuration)
        let silence = try Data(contentsOf: directory.appendingPathComponent("learnable_sil_emb.bin"))
        guard silence.count == 512 * MemoryLayout<Float>.size else { throw ThoughtStoreError.unavailable }
        let embedding = silence.withUnsafeBytes { bytes in
            (0..<512).map { Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
        let models = try Nemotron3Models(config: config, model: model, silenceEmbedding: embedding)
        let engine = Nemotron3Diarizer(config: config, models: models)
        let file = try AVAudioFile(forReading: audio)
        guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 160_000)
        else { throw ThoughtStoreError.unavailable }
        var turns = NemotronTurnAccumulator()
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try checkThermal()
            try autoreleasepool {
                try file.read(into: buffer)
                guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { throw ThoughtStoreError.unavailable }
                engine.appendAudio(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
                for chunk in try engine.processBufferedAudio() {
                    try turns.append(chunk.probabilities, frames: chunk.frameCount)
                }
            }
            progress(min(0.99, Double(file.framePosition) / Double(max(1, file.length))))
        }
        for chunk in try engine.finishStream() { try turns.append(chunk.probabilities, frames: chunk.frameCount) }
        let segments = turns.finish()
        guard !segments.isEmpty else { throw ThoughtStoreError.unavailable }
        var seconds: [Int: Double] = [:]
        for segment in segments { seconds[segment.cluster, default: 0] += segment.end - segment.start }
        let embedder = try CAMVoiceEmbedding()
        var centroids: [Int: [Float]] = [:]
        for cluster in seconds.keys.sorted() {
            var clean: [Range<Double>] = []
            for segment in segments where segment.cluster == cluster {
                var parts = [segment.start..<segment.end]
                for other in segments where other.cluster != cluster {
                    parts = parts.flatMap { part -> [Range<Double>] in
                        guard other.start < part.upperBound, other.end > part.lowerBound else { return [part] }
                        var remaining: [Range<Double>] = []
                        if other.start > part.lowerBound { remaining.append(part.lowerBound..<other.start) }
                        if other.end < part.upperBound { remaining.append(other.end..<part.upperBound) }
                        return remaining
                    }
                }
                clean += parts.filter { $0.upperBound - $0.lowerBound >= 3 }
            }
            let windows = clean.flatMap { range -> [Range<Double>] in
                stride(from: range.lowerBound, to: range.upperBound - 2.99, by: 8).map { $0..<min($0 + 8, range.upperBound) }
            }.sorted { $0.lowerBound < $1.lowerBound }
            let count = min(5, windows.count)
            let selected = (0..<count).map { windows[count == 1 ? 0 : $0 * (windows.count - 1) / (count - 1)] }
            var prints: [VoicePrint] = []
            for range in selected {
                try Task.checkCancellation()
                file.framePosition = AVAudioFramePosition(range.lowerBound * 16000)
                let count = min(128000, Int((range.upperBound - range.lowerBound) * 16000))
                try file.read(into: buffer, frameCount: AVAudioFrameCount(count))
                guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { continue }
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                prints.append(VoicePrint(vector: try embedder.embedding(samples: samples), model: CAMVoiceEmbedding.modelID,
                                         seconds: Double(buffer.frameLength) / 16000, source: .conversation))
            }
            let consistent = prints.allSatisfy { a in prints.allSatisfy { b in
                SpeakerThresholds.cosine(a.vector, b.vector) >= SpeakerThresholds.learning
            } }
            if consistent { centroids[cluster] = SpeakerThresholds.enrollmentCentroid(prints) }
        }
        progress(1)
        return Diarization(segments: segments, centroids: centroids, speechSeconds: seconds, model: CAMVoiceEmbedding.modelID)
    }
}

/// Behält nur offene Turns, nicht die Frame-Wahrscheinlichkeiten einer ganzen Aufnahme.
struct NemotronTurnAccumulator {
    private var frame = 0
    private var starts = Array<Int?>(repeating: nil, count: 8)
    private var segments: [Diarization.Segment] = []
    mutating func append(_ probabilities: [Float], frames: Int) throws {
        guard frames >= 0, frames <= Int.max / 8, probabilities.count == frames * 8, probabilities.allSatisfy({ $0.isFinite }) else { throw ThoughtStoreError.unavailable }
        for local in 0..<frames {
            for speaker in 0..<8 {
                if probabilities[local * 8 + speaker] > 0.5 {
                    if starts[speaker] == nil { starts[speaker] = frame }
                } else { close(speaker) }
            }
            frame += 1
        }
    }
    private mutating func close(_ speaker: Int) {
        guard let start = starts[speaker] else { return }
        if frame - start >= 5 {
            segments.append(.init(start: Double(start) / 100, end: Double(frame) / 100, cluster: speaker))
        }
        starts[speaker] = nil
    }
    mutating func finish() -> [Diarization.Segment] {
        for speaker in 0..<8 { close(speaker) }
        return segments.sorted { $0.start == $1.start ? $0.cluster < $1.cluster : $0.start < $1.start }
    }
}
