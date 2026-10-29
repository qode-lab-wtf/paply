import Foundation
import AVFoundation

public struct ConversationWhisperResult: Codable, Sendable, Equatable {
    public struct Segment: Codable, Sendable, Equatable { public var start: Double; public var end: Double; public var text: String }
    public var words: [ConversationWord]
    public var segments: [Segment]
    public var language: String?
    public var duration: Double?
    public init(words: [ConversationWord], segments: [Segment], language: String?, duration: Double?) {
        self.words = words; self.segments = segments; self.language = language; self.duration = duration
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        words = try values.decodeIfPresent([ConversationWord].self, forKey: .words) ?? []
        segments = try values.decodeIfPresent([Segment].self, forKey: .segments) ?? []
        language = try values.decodeIfPresent(String.self, forKey: .language)
        duration = try values.decodeIfPresent(Double.self, forKey: .duration)
    }
}

extension GroqClient {
    /// Eigener Endpunktpfad; der Diktat-Aufruf bleibt unberührt.
    package func transcribeConversation(audio: AudioEncoder.Encoded, language: String?, vocabulary: [String]) async -> Result<ConversationWhisperResult, GroqFailure> {
        guard audio.data.count < 25_000_000 else { return .failure(.http(status: 413, code: nil, retryAfter: nil)) }
        var prompt = ""
        for term in vocabulary {
            let next = prompt.isEmpty ? term : prompt + ", " + term
            if PartSplitter.estimateTokens(next) > 200 { break }; prompt = next
        }
        var fields = [("model", "whisper-large-v3"), ("response_format", "verbose_json"), ("temperature", "0"), ("timestamp_granularities[]", "word"), ("timestamp_granularities[]", "segment"), ("prompt", prompt)]
        if let language { fields.append(("language", language)) }
        let boundary = UUID().uuidString
        var request = request("audio/transcriptions", method: "POST")
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipart(boundary: boundary, fields: fields, audio: audio)
        return await send(request).flatMap { data in
            do { return .success(try JSONDecoder().decode(ConversationWhisperResult.self, from: data)) }
            catch { return .failure(.invalidResponse) }
        }
    }
}

public actor ConversationTranscriber {
    private let ledger: TokenLedger
    private let transport: GroqTransport
    private let baseURL: URL
    public init(ledger: TokenLedger) { self.ledger = ledger; transport = .shared; baseURL = GroqClient.defaultBaseURL }
    init(ledger: TokenLedger, client: GroqClient) { self.ledger = ledger; transport = client.transport; baseURL = client.baseURL }
    private var busy = false
    struct Piece: Codable { var start: Int; var end: Int; var result: ConversationWhisperResult }

    /// `final == false`: nur bis zur letzten abgeschlossenen Sprechpause. Wiederholung liest fertige Stücke von Platte.
    public func transcribe(audio: URL, workDirectory: URL, apiKey: String, mainLanguage: String, vocabulary: [String], gaps: [ConversationGap] = [], final: Bool = true) async throws -> ConversationWhisperResult {
        guard !busy else { throw ThoughtStoreError.unavailable }
        busy = true; defer { busy = false }
        try FileSafety.createDirectory(workDirectory)
        let file = try AVAudioFile(forReading: audio, commonFormat: .pcmFormatInt16, interleaved: false)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1 else { throw WAVWriter.WAVError.notWAV }
        let total = Int(file.length)
        var offset = 0, index = 0, words: [ConversationWord] = [], segments: [ConversationWhisperResult.Segment] = [], languages: [String] = []
        while offset < total {
            try Task.checkCancellation()
            let cache = workDirectory.appendingPathComponent("whisper-\(index).json")
            let piece: Piece
            if FileSafety.exists(cache) {
                piece = try ThoughtJSON.decoder().decode(Piece.self, from: Data(contentsOf: cache))
                guard piece.start == offset, piece.end > offset, piece.end <= total else { throw ThoughtStoreError.unavailable }
            } else {
                let count = min(600 * 16000, total - offset)
                file.framePosition = AVAudioFramePosition(offset)
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count))!
                try file.read(into: buffer)
                let samples = Array(UnsafeBufferPointer(start: buffer.int16ChannelData![0], count: Int(buffer.frameLength)))
                var vad = VoiceActivityDetector(), planner = ChunkPlanner(), lastCut = 0
                planner.minChunkSeconds = 60
                for start in stride(from: 0, to: samples.count, by: 480) {
                    vad.process(samples[start..<min(samples.count, start + 480)].map { Float($0) / 32768 })
                    if let cut = planner.nextCut(vad) { lastCut = cut.upperBound * 480 }
                }
                let end: Int
                if final && offset + count == total { end = total }
                else if lastCut > 0 { end = offset + lastCut }
                else if !final { break }
                else { end = offset + count }
                let gap = gaps.map { Int($0.at * 16000) }.filter { $0 > offset && $0 < end }.min()
                let cut = gap ?? end
                let encoded = AudioEncoder.encode(samples.prefix(cut - offset)[...])
                let reservation = try await ledger.reserve(model: "whisper-large-v3", amount: max(10, (cut - offset + 15999) / 16000), unit: .audio)
                let client = GroqClient(apiKey: apiKey, transport: transport, baseURL: baseURL)
                let response = await client.transcribeConversation(audio: encoded, language: cut - offset < 30 * 16000 ? mainLanguage : nil, vocabulary: vocabulary)
                switch response {
                case .success(let result):
                    let duration = Double(cut - offset) / 16000
                    guard result.words.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.end <= duration + 0.1 }) else { throw GroqFailure.invalidResponse }
                    piece = Piece(start: offset, end: cut, result: result)
                    try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(piece), to: cache)
                    await ledger.settle(reservation, actual: max(10, Int(ceil(Double(cut - offset) / 16000))))
                case .failure(let failure):
                    if case .http(let status, _, _) = failure, [401,403,404,429].contains(status) { await ledger.settle(reservation, actual: 0) }
                    throw failure
                }
            }
            let shift = Double(offset) / 16000
            for var word in piece.result.words { word.start += shift; word.end += shift; words.append(word) }
            for var segment in piece.result.segments { segment.start += shift; segment.end += shift; segments.append(segment) }
            if let language = piece.result.language, !languages.contains(language) { languages.append(language) }
            offset = piece.end; index += 1
        }
        return ConversationWhisperResult(words: words, segments: segments, language: languages.first, duration: Double(offset) / 16000)
    }
}
