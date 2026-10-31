import Foundation
import Testing
@testable import PaplyKit

struct IOSReviewRegressionTests {
    func context(_ server: MockServer) -> DictationPipeline.Context {
        var settings = PaplySettings()
        settings.spokenLanguages = ["de", "en"]
        settings.primaryLanguage = "de"
        return .init(client: server.client(), settings: settings, format: .wav, primer: nil,
                     bytes: Counter(), requestedSamples: Counter(), uploads: Counter())
    }

    @Test func emptyPreviousDoesNotChooseLanguage() async {
        let server = MockServer { request, _ in
            Groq.transcription("Noch ein Satz.", language: request.field("language") == nil ? "English" : "German")
        }
        let result = await DictationPipeline.transcribe([Int16](repeating: 1, count: 16000)[...], startSample: 0,
            vad: VoiceActivityDetector(), previous: .init(text: "", language: "en"), context: context(server))
        #expect(server.requests.map { $0.field("language") } == [nil, "de"])
        #expect(result.language == "de")
    }

    @Test(arguments: [true, false]) func noUnnecessaryPreviousWait(failure: Bool) async {
        let server = MockServer { _, _ in failure ? Groq.error(422) : Groq.transcription("English sentence.", language: "English") }
        let before = Task<DictationPipeline.ChunkResult, Never> {
            try? await Task.sleep(for: .seconds(30))
            return .init(text: "Vorstück", language: "de")
        }
        defer { before.cancel() }
        let ctx = context(server)
        let task = Task {
            await DictationPipeline.transcribe([Int16](repeating: 1, count: 6 * 16000)[...], startSample: 0,
                vad: VoiceActivityDetector(), previous: nil, context: ctx, previousTask: before)
        }
        defer { task.cancel() }
        let result = await awaitResult(task, timeout: .seconds(5))
        #expect(result != nil)
        #expect(server.requests.count == 1)
    }

    @Test func counterIncludesCheckAndRetry() async {
        let server = MockServer { request, index in
            if index == 0 { return Groq.error(500) }
            return Groq.transcription("Ein vollständiger Satz.", language: request.field("language") == nil ? "French" : "German")
        }
        let ctx = context(server)
        _ = await DictationPipeline.transcribe([Int16](repeating: 1, count: 32000)[...], startSample: 0,
            vad: VoiceActivityDetector(), previous: nil, context: ctx)
        #expect(server.requests.count == 3)
        #expect(ctx.requestedSamples.value == 96000)
        var outcome = DictationOutcome(raw: "Text")
        outcome.timings.audioSeconds = 2
        outcome.timings.requestedAudioSeconds = 6
        #expect(FileTranscriber.result(from: outcome, model: "m") == .success(text: "Text", languages: [], audioSeconds: 2, model: "m", requestedAudioSeconds: 6))
    }

    @Test(arguments: [("nb-NO", "no"), ("fil", "tl"), ("iw", "he"), ("in", "id"), ("ji", "yi"), ("jw", "jv")])
    func languageAliases(pair: (String, String)) async {
        #expect(LanguageGuard.expected(previous: pair.0, primary: "de") == pair.1)
        #expect(!LanguageGuard.needsCheck(expected: pair.0, detected: pair.1, userLanguages: [], spokenSeconds: 1))
        let server = MockServer { _, _ in Groq.transcription("Text") }
        _ = await server.client().transcribe(audio: AudioEncoder.encode([1, 2, 3]), model: "m", language: pair.0, prompt: nil)
        #expect(server.requests.first?.field("language") == pair.1)
    }

    @Test func checkDeadline() async {
        #expect(LanguageGuard.checkTimeout(firstSeconds: 2) == 9)
        #expect(LanguageGuard.checkTimeout(firstSeconds: 100) == 60)
        let result: Int? = await LanguageGuard.boundedCheck(firstSeconds: 0) {
            try? await Task.sleep(for: .seconds(30))
            return 42
        }
        #expect(result == nil)
    }

    @Test func appUsesSharedLanguageRulesAndCurrentCopy() throws {
        let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let environment = try String(contentsOf: ios.appendingPathComponent("App/Conversations/ConversationsEnvironment.swift"), encoding: .utf8)
        #expect(environment.contains("LanguageGuard.primary(AppSettings.shared.effectivePaply)"))
        #expect(environment.contains("CodeSwitchPrimer.userLanguages(AppSettings.shared.effectivePaply)"))
        #expect(!environment.contains("?? \"de\""))
        let settings = try String(contentsOf: ios.appendingPathComponent("App/UI/SettingsView.swift"), encoding: .utf8)
        #expect(settings.contains("Paply übersetzt nie."))
        #expect(!settings.contains("schreibt es in der Hauptsprache"))
        #expect(!settings.contains("Kurze Sätze schreibt Paply direkt"))
    }

    @Test(arguments: [true, false]) func conversationCheckFailure(cancel: Bool) async throws {
        let root = try ConversationCoreTests().root(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("audio.wav")
        let writer = try WAVWriter(url: audio); writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        let server = MockServer { request, index in
            if request.field("language") != nil && index == 1 {
                return cancel ? .failure(.cancelled) : Groq.error(429, headers: ["Retry-After": "0"])
            }
            return .json(200, ["words": [["word": "Bonjour", "start": 0, "end": 0.2]],
                "segments": [["text": "Bonjour", "start": 0, "end": 0.2, "avg_logprob": -0.2]], "language": "french"])
        }
        let ledger = ConversationLedger.make(root: root)
        let transcriber = ConversationTranscriber(ledger: ledger, client: server.client())
        do {
            _ = try await transcriber.transcribe(audio: audio, workDirectory: root.appendingPathComponent("work"), apiKey: "test", mainLanguage: "de", vocabulary: [])
            #expect(!cancel)
        } catch { #expect(cancel && error is CancellationError) }
        #expect(FileSafety.exists(root.appendingPathComponent("work/whisper-0.json")) == !cancel)
        #expect(server.requests.count == (cancel ? 2 : 3))
        #expect(await ledger.summary().audioSeconds == (cancel ? 10 : 20))
    }

    @Test(arguments: [true, false]) func thoughtsBookRequestedSeconds(live: Bool) async throws {
        let h = try Harness.make(transcriber: MockTranscriber([.success(text: "die tomaten gießen", languages: ["de"], audioSeconds: 2, model: "whisper-large-v3", requestedAudioSeconds: 6)]))
        defer { h.cleanup() }
        let id = try await h.capture(seconds: 2)
        if live {
            await h.processor.expectLiveTranscript(id)
            var timings = DictationTimings(audioSeconds: 2)
            timings.requestedAudioSeconds = 6
            await h.processor.liveTranscript(id, outcome: DictationOutcome(raw: "die tomaten gießen", languages: ["de"], timings: timings))
        }
        await h.run("test")
        let data = try Data(contentsOf: h.root.appendingPathComponent("ledger.json"))
        let records = try JSONDecoder().decode([TokenLedger.Record].self, from: data)
        #expect(records.filter { $0.unit == .audio }.reduce(0) { $0 + $1.amount } == 6)
        #expect(await h.store.source(id)?.audioSeconds == 2)
    }

    @Test func conversationMinuteRefusalRetriesCheck() async throws {
        let root = try ConversationCoreTests().root(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("audio.wav")
        let writer = try WAVWriter(url: audio); writer.append(StoreSupport.tone(seconds: 0.2)); _ = writer.close()
        let reservations = Box(0)
        let ledger = TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: {
            reservations.update { $0 += 1 }
            var limits = TokenLedger.Limits()
            limits.minuteRequests = reservations.value == 2 ? 0 : 100
            return limits
        }, now: { Date(timeIntervalSince1970: 0) })
        let server = MockServer { _, _ in .json(200, ["words": [["word": "Bonjour", "start": 0, "end": 0.2]], "segments": [], "language": "french"]) }
        let transcriber = ConversationTranscriber(ledger: ledger, client: server.client())
        _ = try await transcriber.transcribe(audio: audio, workDirectory: root.appendingPathComponent("work"), apiKey: "test", mainLanguage: "de", vocabulary: [])
        #expect(reservations.value == 3)
        #expect(server.requests.count == 2)
    }

    @Test func slowCheckKeepsFirstTranscript() async {
        let server = MockServer { request, _ in
            if request.field("language") != nil { return Groq.transcription("Übersetzter Text").delayed(120) }
            return Groq.transcription("Bonjour tout le monde", language: "French")
        }
        let ctx = context(server)
        let result = await DictationPipeline.transcribe([Int16](repeating: 1, count: 16000)[...], startSample: 0,
            vad: VoiceActivityDetector(), previous: nil, context: ctx)
        #expect(result.text == "Bonjour tout le monde")
        #expect(result.languageSource == .checkFailed)
    }

    @Test func emptyConversationCacheDoesNotSetLanguage() async throws {
        let root = try ConversationCoreTests().root(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("audio.wav")
        let writer = try WAVWriter(url: audio); writer.append(StoreSupport.tone(seconds: 0.4)); _ = writer.close()
        let work = root.appendingPathComponent("work"); try FileSafety.createDirectory(work)
        let empty = ConversationWhisperResult(words: [], segments: [], language: "fr", duration: 0.2)
        let piece = ConversationTranscriber.Piece(start: 0, end: 3200, result: empty, spokenSeconds: 0.2)
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(piece), to: work.appendingPathComponent("whisper-0.json"))
        let server = MockServer { _, _ in .json(200, ["words": [["word": "Hallo", "start": 0, "end": 0.2]], "segments": [], "language": "german"]) }
        let transcriber = ConversationTranscriber(ledger: ConversationLedger.make(root: root), client: server.client())
        let result = try await transcriber.transcribe(audio: audio, workDirectory: work, apiKey: "test", mainLanguage: "de", vocabulary: [])
        #expect(server.requests.count == 1)
        #expect(result.language == "de")
        #expect(result.languageSpeechSeconds?["fr"] == nil)
    }
}
