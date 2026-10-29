import Foundation
import AVFoundation
import Synchronization
import PaplyKit

/// Nur ein Platzhalter: Pegelfenster, keine echte Sprecheridentifikation.
private struct BenchDiarizer: SpeakerDiarizing {
    let embeddingModel = "bench-energy-placeholder"
    func voiceprint(audio: URL) async throws -> VoicePrint? { nil }
    func diarize(audio: URL, expectedSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization {
        let samples = try readWav(audio)
        var segments: [Diarization.Segment] = []
        for start in stride(from: 0, to: samples.count, by: 480) {
            let end = min(samples.count, start + 480)
            let energy = samples[start..<end].reduce(Float(0)) { $0 + $1 * $1 } / Float(end - start)
            if energy > 0.00001 {
                segments.append(.init(start: Double(start) / 16000, end: Double(end) / 16000, cluster: 0))
            }
        }
        progress(1)
        return .init(segments: segments, centroids: [0: [1, 0]],
                     speechSeconds: [0: segments.reduce(0) { $0 + $1.end - $1.start }], model: embeddingModel)
    }
}

func conversationsBench(_ path: String) async throws {
    let root = URL(fileURLWithPath: "/tmp/paply-gsp-k2-bench-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let audio = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: audio)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    guard duration <= 600 else { fail("Audio-Budget überschritten") }
    let ledger = TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: {
        var limits = TokenLedger.Limits()
        limits.dailyTokens = 40000
        limits.dailyAudioSeconds = 600
        return limits
    })
    let analyzer = ConversationAnalyzer(diarizer: BenchDiarizer(), ledger: ledger)
    let started = Date()
    let stages = Mutex<[String: Double]>([:])
    let input = ConversationAnalysisInput(id: "bench", audio: audio, workDirectory: root,
        recordedAt: started, expectedSpeakers: nil, gaps: [], mainLanguage: "de",
        vocabulary: [], topics: [], people: [], previous: nil)
    let outcome = await analyzer.analyze(input, apiKey: apiKey()) { progress in
        stages.withLock { values in
            let key = progress.stage.rawValue
            if values[key] == nil { values[key] = Date().timeIntervalSince(started) }
            if progress.stage == .speakers && progress.fraction == 1 { values["diarizationEnd"] = Date().timeIntervalSince(started) }
        }
    }
    let result: ConversationAnalysis?
    let status: Int
    switch outcome {
    case .done(let value): result = value; status = 0
    case .partial(let value, _, _, _): result = value; status = 1
    default: result = nil; status = 2
    }
    let elapsed = Date().timeIntervalSince(started)
    let times = stages.withLock { $0 }
    let pieces = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("whisper-") }.count
    let numbers: [String: Double] = [
        "status": Double(status), "duration": duration, "pieces": Double(pieces),
        "words": Double(result?.transcript?.utterances.reduce(0) { $0 + $1.text.split(separator: " ").count } ?? 0),
        "speakers": Double(result?.speakers.count ?? 0), "tokens": Double(result?.usage?.total ?? 0),
        "diarizationSeconds": times["diarizationEnd"] ?? 0,
        "transcriptionSeconds": (times["summary"] ?? elapsed) - (times["transcript"] ?? 0),
        "summarySeconds": elapsed - (times["summary"] ?? elapsed), "totalSeconds": elapsed
    ]
    print(String(decoding: try JSONSerialization.data(withJSONObject: numbers, options: [.sortedKeys]), as: UTF8.self))
}
