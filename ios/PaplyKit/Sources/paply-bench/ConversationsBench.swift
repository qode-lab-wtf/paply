import Foundation
import AVFoundation
import Synchronization
import PaplyKit

func conversationsBench(_ path: String) async throws {
    let root = URL(fileURLWithPath: "/tmp/paply-gsp-d-bench-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let audio = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: audio)
    let duration = Double(file.length) / file.processingFormat.sampleRate
    if ProcessInfo.processInfo.environment["PAPLY_CAM_ONLY"] == "1" {
        file.framePosition = AVAudioFramePosition((Double(ProcessInfo.processInfo.environment["PAPLY_CAM_OFFSET"] ?? "10") ?? 10) * 16000)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 128000)!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let values = try CAMVoiceEmbedding().embedding(samples: samples)
        print(String(decoding: try JSONEncoder().encode(values), as: UTF8.self))
        return
    }
    if ProcessInfo.processInfo.environment["PAPLY_DIARIZATION_ONLY"] == "1" {
        guard let models = ProcessInfo.processInfo.environment["PAPLY_SPEAKER_MODELS"] else { fail("PAPLY_SPEAKER_MODELS fehlt") }
        let start = Date()
        let result = try await NemotronSpeakerDiarizer(directory: URL(fileURLWithPath: models)).diarize(audio: audio, expectedSpeakers: nil) { _ in }
        let elapsed = Date().timeIntervalSince(start)
        let output: [String: Any] = ["speakers": result.speechSeconds.count, "seconds": elapsed,
            "duration": duration, "rtf": elapsed / max(0.001, duration),
            "segments": result.segments.map { ["start": $0.start, "end": $0.end, "speaker": String($0.cluster)] as [String: Any] }]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
        return
    }
    guard duration <= 600 else { fail("Audio-Budget überschritten") }
    let ledger = TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: {
        var limits = TokenLedger.Limits()
        limits.dailyTokens = 10000
        limits.dailyAudioSeconds = 600
        return limits
    })
    guard let modelPath = ProcessInfo.processInfo.environment["PAPLY_SPEAKER_MODELS"] else { fail("PAPLY_SPEAKER_MODELS fehlt") }
    let diarizer = NemotronSpeakerDiarizer(directory: URL(fileURLWithPath: modelPath))
    let analyzer = ConversationAnalyzer(diarizer: diarizer, ledger: ledger)
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
