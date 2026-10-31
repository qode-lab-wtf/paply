import Foundation
import AVFoundation

public struct ConversationWhisperResult: Codable, Sendable, Equatable {
    public struct Segment: Codable, Sendable, Equatable { public var start: Double; public var end: Double; public var text: String; public var avg_logprob: Double? = nil }
    public var languageSpeechSeconds: [String: Double]? = nil
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
        languageSpeechSeconds = try values.decodeIfPresent([String: Double].self, forKey: .languageSpeechSeconds)
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
        if let language { fields.append(("language", LanguageGuard.code(language))) }
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
    struct Piece: Codable { var start: Int; var end: Int; var result: ConversationWhisperResult; var nextStart: Int? = nil; var spokenSeconds: Double? = nil }

    static func rawText(_ result: ConversationWhisperResult) -> String {
        result.segments.isEmpty ? result.words.map(\.word).joined(separator: " ") : result.segments.map(\.text).joined(separator: " ")
    }

    static func confidence(_ result: ConversationWhisperResult) -> Double? {
        LanguageGuard.confidence(result.segments.map { WhisperSegment(text: $0.text, start: $0.start, end: $0.end, avgLogprob: $0.avg_logprob) })
    }

    static func quietCut(_ samples: [Int16]) -> Int {
        let first = max(1, samples.count - 30 * 16000)
        let last = max(first + 1, samples.count - 16000)
        return stride(from: first, to: last, by: 480).min { a, b in
            func energy(_ start: Int) -> Double {
                samples[start..<min(samples.count, start + 480)].reduce(0) { $0 + Double($1) * Double($1) }
            }
            return energy(a) < energy(b)
        } ?? samples.count
    }

    static func join(_ previous: [ConversationWord], _ incoming: [ConversationWord]) -> [ConversationWord] {
        var result = previous
        func normalized(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        var used = Set<Int>()
        for word in incoming {
            var low = 0, high = previous.count
            while low < high {
                let mid = (low + high) / 2
                if previous[mid].start < word.start - 0.5 { low = mid + 1 } else { high = mid }
            }
            let candidates = (low..<previous.count).prefix { previous[$0].start < word.start + 0.5 }
            let duplicate = candidates.last { index in
                guard !used.contains(index) else { return false }
                let old = previous[index]
                guard abs(old.start - word.start) < 0.5, min(old.end, word.end) - max(old.start, word.start) >= -0.1 else { return false }
                let a = normalized(old.word)
                let b = normalized(word.word)
                let overlap = min(old.end, word.end) - max(old.start, word.start)
                let fragment = min(a.count, b.count) >= 2 && (a.hasPrefix(b) || b.hasPrefix(a)) &&
                    overlap >= min(old.end - old.start, word.end - word.start) * 0.5
                return (a == b || fragment) && abs(old.start - word.start) < 0.5 && overlap >= -0.1
            }
            if let duplicate {
                if normalized(word.word).count >= normalized(result[duplicate].word).count {
                    result[duplicate] = word
                }
                used.insert(duplicate)
            } else {
                result.append(word)
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// `final == false`: nur bis zur letzten abgeschlossenen Sprechpause. Wiederholung liest fertige Stücke von Platte.
    public func transcribe(audio: URL, workDirectory: URL, apiKey: String, mainLanguage: String, vocabulary: [String], userLanguages: [String] = [], gaps: [ConversationGap] = [], final: Bool = true) async throws -> ConversationWhisperResult {
        let started = Date()
        defer { ConversationDiagnostics.record("conversation.whisper.duration", ["ms": Int(Date().timeIntervalSince(started) * 1000)]) }
        guard !busy else { throw ThoughtStoreError.unavailable }
        busy = true; defer { busy = false }
        try FileSafety.createDirectory(workDirectory)
        let file = try AVAudioFile(forReading: audio, commonFormat: .pcmFormatInt16, interleaved: false)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1 else { throw WAVWriter.WAVError.notWAV }
        let total = Int(file.length)
        var offset = 0, index = 0, words: [ConversationWord] = [], segments: [ConversationWhisperResult.Segment] = [], languages: [String] = []
        var previousLanguage: String?
        var languageSeconds: [String: Double] = [:]
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
                else { end = offset + Self.quietCut(samples) }
                let gap = gaps.map { Int($0.at * 16000) }.filter { $0 > offset && $0 < end }.min()
                let cut = gap ?? end
                let encoded = AudioEncoder.encode(samples.prefix(cut - offset)[...])
                var pieceVAD = VoiceActivityDetector()
                pieceVAD.process(samples.prefix(cut - offset).map { Float($0) / 32768 })
                let spoken = pieceVAD.frameCount == 0 ? Double(cut - offset) / 16000 : pieceVAD.activity(in: 0..<pieceVAD.frameCount).speechMs / 1000
                let expected = LanguageGuard.expected(previous: previousLanguage, primary: mainLanguage)
                let result: ConversationWhisperResult = try await ConversationRetry.run {
                let reservation = try await ledger.reserve(model: "whisper-large-v3", amount: max(10, (cut - offset + 15999) / 16000), unit: .audio)
                let client = GroqClient(apiKey: apiKey, transport: transport, baseURL: baseURL)
                let firstStarted = Date()
                let response = await client.transcribeConversation(audio: encoded, language: nil, vocabulary: vocabulary)
                switch response {
                case .success(var result):
                    result.language = GroqModels.languageCode(result.language)
                    if LanguageGuard.needsCheck(expected: expected, detected: result.language, userLanguages: userLanguages, spokenSeconds: spoken) {
                        let firstSeconds = Date().timeIntervalSince(firstStarted)
                        await ledger.settle(reservation, actual: max(10, (cut - offset + 15999) / 16000))
                        let amount = max(10, (cut - offset + 15999) / 16000)
                        let ledger = ledger
                        let check = await LanguageGuard.boundedCheck(firstSeconds: firstSeconds) {
                            do {
                                return try await ConversationRetry.run {
                                    let ticket = try await ledger.reserve(model: "whisper-large-v3", amount: amount, unit: .audio)
                                    let response = await client.transcribeConversation(audio: encoded, language: expected, vocabulary: vocabulary)
                                    switch response {
                                    case .success(let second):
                                        await ledger.settle(ticket, actual: amount)
                                        return Result<ConversationWhisperResult, GroqFailure>.success(second)
                                    case .failure(let failure):
                                        await ledger.settle(ticket, actual: 0)
                                        throw failure
                                    }
                                }
                            } catch let failure as GroqFailure { return .failure(failure) }
                            catch is CancellationError { return .failure(.cancelled) }
                            catch { return .failure(.invalidResponse) }
                        }
                        if Task.isCancelled { throw CancellationError() }
                        if case .failure(.cancelled) = check { throw CancellationError() }
                        if case .success(let second) = check,
                           LanguageGuard.choose(detectedText: Self.rawText(result), expectedText: Self.rawText(second),
                                                detectedConfidence: Self.confidence(result), expectedConfidence: Self.confidence(second), spokenSeconds: spoken) == .expected {
                            result = second; result.language = expected
                        }
                    }

                    let duration = Double(cut - offset) / 16000
                    guard result.words.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start }) else { throw GroqFailure.invalidResponse }
                    result.words = result.words.map { .init(word: $0.word, start: min(duration, $0.start), end: min(duration, $0.end)) }
                    result.segments = result.segments.map { .init(start: max(0, min(duration, $0.start)), end: max(0, min(duration, $0.end)), text: $0.text) }
                    await ledger.settle(reservation, actual: max(10, Int(ceil(Double(cut - offset) / 16000))))
                    return result
                case .failure(let failure):
                    await ledger.settle(reservation, actual: 0)
                    throw failure
                }
                }
                let overlap = lastCut == 0 && gap == nil && cut < total
                piece = Piece(start: offset, end: cut, result: result, nextStart: overlap ? cut - 32000 : nil, spokenSeconds: spoken)
                try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(piece), to: cache)
            }
            let shift = Double(offset) / 16000
            let incoming = piece.result.words.map { word in
                ConversationWord(word: word.word, start: word.start + shift, end: word.end + shift)
            }
            words = Self.join(words, incoming)
            for var segment in piece.result.segments { segment.start += shift; segment.end += shift; segments.append(segment) }
            if !piece.result.words.isEmpty, let language = GroqModels.languageCode(piece.result.language) {
                previousLanguage = language
                if !languages.contains(language) { languages.append(language) }
                let speech = piece.spokenSeconds ?? piece.result.segments.reduce(0) { $0 + max(0, $1.end - $1.start) }
                languageSeconds[language, default: 0] += speech
            }
            offset = piece.nextStart ?? piece.end; index += 1
        }
        var result = ConversationWhisperResult(words: words, segments: segments, language: languages.first, duration: Double(offset) / 16000)
        result.languageSpeechSeconds = languageSeconds
        return result
    }
}
