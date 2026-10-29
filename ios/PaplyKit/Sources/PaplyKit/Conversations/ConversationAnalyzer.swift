import Foundation

public struct ConversationAnalyzer: ConversationAnalyzing {
    private let diarizer: any SpeakerDiarizing
    private let transcriber: ConversationTranscriber
    private let summarizer: ConversationSummarizer
    public init(diarizer: any SpeakerDiarizing, ledger: TokenLedger) {
        self.diarizer = diarizer; transcriber = ConversationTranscriber(ledger: ledger); summarizer = ConversationSummarizer(ledger: ledger)
    }
    public init(diarizer: any SpeakerDiarizing, transcriber: ConversationTranscriber, summarizer: ConversationSummarizer) {
        self.diarizer = diarizer; self.transcriber = transcriber; self.summarizer = summarizer
    }
    struct CachedDiarization: Codable {
        struct Segment: Codable { var start: Double; var end: Double; var cluster: Int }
        var segments: [Segment]; var centroids: [Int: [Float]]; var speechSeconds: [Int: Double]; var model: String
        init(_ d: Diarization) { segments = d.segments.map { .init(start: $0.start, end: $0.end, cluster: $0.cluster) }; centroids = d.centroids; speechSeconds = d.speechSeconds; model = d.model }
        var value: Diarization { .init(segments: segments.map { .init(start: $0.start, end: $0.end, cluster: $0.cluster) }, centroids: centroids, speechSeconds: speechSeconds, model: model) }
    }
    public func analyze(_ input: ConversationAnalysisInput, apiKey: String, progress: @escaping @Sendable (ConversationProgress) -> Void) async -> ConversationAnalysisOutcome {
        var partial = ConversationAnalysis(stagesDone: [], speakers: [], speakerPrints: [:], transcript: nil, title: nil, summary: nil, tasks: [], topic: nil, audioSeconds: 0, usage: nil, model: nil)
        do {
            try FileSafety.createDirectory(input.workDirectory)
            progress(.init(stage: .speakers))
            let cache = input.workDirectory.appendingPathComponent("diarization.json")
            let diarization: Diarization
            if FileSafety.exists(cache) { diarization = try ThoughtJSON.decoder().decode(CachedDiarization.self, from: Data(contentsOf: cache)).value }
            else {
                diarization = try await diarizer.diarize(audio: input.audio, expectedSpeakers: input.expectedSpeakers) { progress(.init(stage: .speakers, fraction: $0)) }
                try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(CachedDiarization(diarization)), to: cache)
            }
            guard !diarization.segments.isEmpty else { return .empty }
            let preliminary = SpeakerAlignment.align(words: [], diarization: diarization)
            partial.stagesDone = [.speakers]; partial.speakers = preliminary.speakers; partial.speakerPrints = preliminary.prints
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .partial(partial, waiting: .waitingKey, retryAt: nil, message: "Groq-Schlüssel fehlt") }
            progress(.init(stage: .transcript))
            let whisper = try await transcriber.transcribe(audio: input.audio, workDirectory: input.workDirectory, apiKey: apiKey, mainLanguage: input.mainLanguage, vocabulary: input.vocabulary, gaps: input.gaps)
            guard !whisper.words.isEmpty else { return .empty }
            let aligned = SpeakerAlignment.align(words: whisper.words, diarization: diarization, gaps: input.gaps)
            var speakers = aligned.speakers
            for i in speakers.indices {
                if let old = input.previous?.speakers.first(where: { $0.id == speakers[i].id && $0.nameSource == .user }) { speakers[i] = old }
            }
            speakers = SpeakerIdentifier.identify(speakers, prints: aligned.prints, people: input.people)
            let transcript = ConversationTranscript(utterances: aligned.utterances, languages: [whisper.language ?? input.mainLanguage], model: "whisper-large-v3", createdAt: input.recordedAt)
            partial.stagesDone = [.speakers, .transcript]; partial.speakers = speakers; partial.speakerPrints = aligned.prints; partial.transcript = transcript; partial.audioSeconds = whisper.duration ?? 0
            progress(.init(stage: .summary))
            var result = try await summarizer.summarize(input, transcript: transcript, speakers: speakers, apiKey: apiKey)
            result.speakerPrints = aligned.prints; result.audioSeconds = partial.audioSeconds
            return .done(result)
        } catch {
            let state: ConversationState, retry: Date?, message: String
            switch error {
            case TokenLedger.Refusal.budget(let date): state = .waitingBudget; retry = date; message = "Kontingent erreicht"
            case TokenLedger.Refusal.minute(let date): state = .waitingLimit; retry = date; message = "Modell-Limit erreicht"
            case GroqFailure.http(429, _, let delay): state = .waitingLimit; retry = Date().addingTimeInterval(delay ?? 60); message = "Groq-Limit erreicht"
            case GroqFailure.http(let status, _, _) where status == 401 || status == 403: state = .waitingKey; retry = nil; message = "Groq-Schlüssel prüfen"
            case GroqFailure.network: state = .waitingNetwork; retry = Date().addingTimeInterval(60); message = "Wartet auf Netz"
            case is CancellationError, GroqFailure.cancelled: state = .captured; retry = nil; message = "Auswertung unterbrochen"
            default: return .failed(code: "analysis-failed")
            }
            return partial.stagesDone.isEmpty ? .wait(state, retryAt: retry, message: message) : .partial(partial, waiting: state, retryAt: retry, message: message)
        }
    }
}
