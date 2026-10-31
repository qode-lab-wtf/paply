import AVFoundation
import Foundation

/// Warum eine Verschriftlichung scheiterte (nie Text).
public enum TranscriptionFailure: String, Sendable, Codable, Equatable, CaseIterable {
    case unauthorized, rateLimited, network, server, invalidResponse, modelMissing, rejected, unreadableAudio, cancelled
}

public enum TranscriptionResult: Sendable, Equatable {
    case success(text: String, languages: [String], audioSeconds: Double, model: String, requestedAudioSeconds: Double? = nil)
    case noSpeech
    case failure(TranscriptionFailure)
}

/// Verschriftlichen einer gesicherten Aufnahme (für Tests austauschbar).
public protocol ThoughtTranscribing: Sendable {
    func transcribe(audioURL: URL, apiKey: String, settings: PaplySettings) async -> TranscriptionResult
}

/// Dateiweg: WAV lesen → DictationPipeline (KONZEPT §5.3 Punkt 4): `chunkedUpload = false`,
/// `polish = false`, `append(alles)` → `finish()`. Teile ≤ 10 Min. übernimmt PaplyKit.
/// Die Pipeline reicht die gewählte Sprache jedes Teils an den nächsten weiter.
public struct FileTranscriber: ThoughtTranscribing {
    private let transport: GroqTransport
    private let baseURL: URL
    private let catalog: ModelCatalog

    public init() {
        self.init(transport: .shared, baseURL: GroqClient.defaultBaseURL, catalog: .shared)
    }

    package init(transport: GroqTransport, baseURL: URL, catalog: ModelCatalog) {
        self.transport = transport
        self.baseURL = baseURL
        self.catalog = catalog
    }

    public func transcribe(audioURL: URL, apiKey: String, settings: PaplySettings) async -> TranscriptionResult {
        guard let samples = Self.readSamples(audioURL) else { return .failure(.unreadableAudio) }
        guard !samples.isEmpty else { return .noSpeech }
        var settings = settings
        settings.chunkedUpload = false
        var options = PipelineOptions()
        options.polish = false
        let client = GroqClient(apiKey: apiKey, transport: transport, baseURL: baseURL)
        let pipeline = DictationPipeline(settings: settings, recentRawDictations: [], options: options,
                                         client: client, catalog: catalog)
        let block = 16_000
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + block)
            await pipeline.append(Array(samples[start..<end]))
            start = end
        }
        let outcome = await pipeline.finish()
        await pipeline.releaseAudio()
        return Self.result(from: outcome, model: settings.transcriptionModel)
    }

    /// Ergebnis einer DictationPipeline (Dateiweg oder Live-Pipeline der Aufnahme) einordnen.
    public static func result(from outcome: DictationOutcome, model: String) -> TranscriptionResult {
        if outcome.noSpeech { return .noSpeech }
        if let message = outcome.errorMessage { return .failure(classify(message)) }
        let raw = outcome.raw.trimmed
        guard !raw.isEmpty else { return .failure(.cancelled) } // abgebrochen: kein Text, keine Meldung
        return .success(text: raw, languages: outcome.languages, audioSeconds: outcome.timings.audioSeconds, model: model, requestedAudioSeconds: outcome.timings.requestedAudioSeconds)
    }

    /// Die Pipeline meldet Fehler nur als deutschen Text; die Texte stammen aus `GroqFailure.germanMessage`.
    static func classify(_ message: String) -> TranscriptionFailure {
        let fixed: [(GroqFailure, TranscriptionFailure)] = [
            (.http(status: 401, code: nil, retryAfter: nil), .unauthorized),
            (.http(status: 429, code: nil, retryAfter: nil), .rateLimited),
            (.http(status: 413, code: nil, retryAfter: nil), .rejected),
            (.http(status: 404, code: nil, retryAfter: nil), .modelMissing),
            (.network(code: 0), .network),
            (.invalidResponse, .invalidResponse),
            (.cancelled, .cancelled),
        ]
        for (failure, kind) in fixed where failure.germanMessage == message { return kind }
        let server = GroqFailure.http(status: 500, code: nil, retryAfter: nil).germanMessage
        if let cut = server.firstIndex(of: "("), message.hasPrefix(server[..<cut]) { return .server }
        let generic = GroqFailure.http(status: 400, code: nil, retryAfter: nil).germanMessage
        if let cut = generic.firstIndex(of: "("), message.hasPrefix(generic[..<cut]) { return .rejected }
        if message.contains("nicht mehr verfügbar") { return .unreadableAudio }
        return .server
    }

    /// 16 kHz mono Float aus der eigenen WAV bzw. m4a (andere Formate schreibt Paply nicht: nil).
    public static func readSamples(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) else { return nil }
        let format = file.processingFormat
        guard format.sampleRate == AudioEncoder.sampleRate, format.channelCount == 1 else { return nil }
        guard file.length > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
}
