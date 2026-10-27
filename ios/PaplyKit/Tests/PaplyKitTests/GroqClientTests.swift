import Foundation
import Synchronization
import Testing
@testable import PaplyKit

private let audio = AudioEncoder.Encoded(data: Data([1, 2, 3, 4]), fileName: "audio.flac", mimeType: "audio/flac", encodeMs: 0)
private let raw = "Morgen besprechen wir gemeinsam unsere offenen Aufgaben."

private func messages(_ text: String = raw) -> [ChatMessage] {
    PolishPrompt.buildMessages(text: text, history: [], segments: [], vocabulary: "")
}

@Suite struct TranscriptionClientTests {
    @Test func sendsMultipartFields() async throws {
        let server = MockServer { _, _ in Groq.transcription("Hallo Welt.") }
        let result = await server.client().transcribe(audio: audio, model: "whisper-large-v3", language: nil, prompt: "Paply.")
        let transcription = try result.get()
        #expect(transcription.text == " Hallo Welt.")
        #expect(transcription.language == "German")
        #expect(transcription.segments?.count == 1)
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/openai/v1/audio/transcriptions")
        #expect(request.headers["Authorization"] == "Bearer test-placeholder")
        #expect(request.field("model") == "whisper-large-v3")
        #expect(request.field("response_format") == "verbose_json")
        #expect(request.field("temperature") == "0")
        #expect(request.field("prompt") == "Paply.")
        #expect(request.field("language") == nil)
        #expect(request.bodyText.contains("filename=\"audio.flac\"\r\nContent-Type: audio/flac"))
    }

    @Test func sendsLanguageOnlyWhenSet() async throws {
        let server = MockServer { _, _ in Groq.transcription("Hello.") }
        _ = await server.client().transcribe(audio: audio, model: "m", language: "en", prompt: nil)
        let request = try #require(server.requests.first)
        #expect(request.field("language") == "en")
        #expect(request.field("prompt") == nil)
    }

    @Test func retriesExactlyOnceAfterServerError() async throws {
        let server = MockServer { _, index in index == 0 ? Groq.error(503) : Groq.transcription("Zweiter Versuch.") }
        let sent = Mutex(0)
        let result = await server.client().transcribe(audio: audio, model: "m", language: nil, prompt: nil,
                                                      bytesSent: { n in sent.withLock { $0 += n } })
        #expect(try result.get().text == " Zweiter Versuch.")
        #expect(server.requests.count == 2)
        #expect(sent.withLock { $0 } == 8)
    }

    @Test func givesUpAfterSecondFailure() async {
        let server = MockServer { _, _ in Groq.error(500) }
        let result = await server.client().transcribe(audio: audio, model: "m", language: nil, prompt: nil)
        guard case .failure(let failure) = result else { Issue.record("Fehler erwartet"); return }
        #expect(failure == .http(status: 500, code: nil, retryAfter: nil))
        #expect(failure.germanMessage.contains("gestört"))
        #expect(server.requests.count == 2)
    }

    @Test func respectsRetryAfter() async throws {
        let server = MockServer { _, index in
            index == 0 ? Groq.error(429, headers: ["Retry-After": "0.3"]) : Groq.transcription("Nach Wartezeit.")
        }
        let start = ContinuousClock.now
        let result = await server.client().transcribe(audio: audio, model: "m", language: nil, prompt: nil)
        #expect(try result.get().text == " Nach Wartezeit.")
        #expect(ContinuousClock.now - start >= .milliseconds(300))
    }

    @Test func doesNotWaitForLongRetryAfter() async {
        let server = MockServer { _, _ in Groq.error(429, headers: ["Retry-After": "120"]) }
        let result = await server.client().transcribe(audio: audio, model: "m", language: nil, prompt: nil)
        guard case .failure(let failure) = result else { Issue.record("Fehler erwartet"); return }
        #expect(failure.germanMessage.contains("Limit"))
        #expect(server.requests.count == 1)
    }

    @Test(arguments: [401, 403, 400, 413])
    func deterministicErrorsAreNotRetried(status: Int) async {
        let server = MockServer { _, _ in Groq.error(status) }
        let result = await server.client().transcribe(audio: audio, model: "m", language: nil, prompt: nil)
        guard case .failure(let failure) = result else { Issue.record("Fehler erwartet"); return }
        #expect(server.requests.count == 1)
        if status == 401 || status == 403 { #expect(failure.germanMessage.contains("Schlüssel")) }
    }

    @Test func connectionLossIsRetriedThenReported() async {
        let server = MockServer { _, _ in .failure(.networkConnectionLost) }
        let result = await server.client().transcribe(audio: audio, model: "m", language: nil, prompt: nil)
        guard case .failure(let failure) = result else { Issue.record("Fehler erwartet"); return }
        #expect(failure.germanMessage.hasPrefix("Keine Verbindung"))
        #expect(server.requests.count == 2)
    }

    @Test func toleratesBrokenSegments() {
        let data = Data(#"{"text":"Hallo.","language":"German","segments":[null]}"#.utf8)
        let parsed = GroqClient.parseTranscription(data)
        #expect(parsed?.text == "Hallo.")
        #expect(parsed?.segments == nil)
        #expect(GroqClient.parseTranscription(Data("kaputt".utf8)) == nil)
    }

    @Test func retryAfterParsing() {
        func response(_ value: String?) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 429, httpVersion: nil,
                            headerFields: value.map { ["Retry-After": $0] } ?? [:])!
        }
        #expect(GroqClient.retryAfter(response("7")) == 7)
        #expect(GroqClient.retryAfter(response("0.5")) == 0.5)
        #expect(GroqClient.retryAfter(response(nil)) == nil)
        #expect(GroqClient.retryAfter(response("bald")) == nil)
    }
}

@Suite struct PolishServiceTests {
    private func service(_ server: MockServer) -> PolishService {
        PolishService(client: server.client(), catalog: ModelCatalog())
    }

    @Test func checksModelsOnceAndSendsQwenOptions() async throws {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish, GroqModels.polishFallback)
                : Groq.chat("<think>privat</think>" + raw)
        }
        let service = service(server)
        let first = await service.polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        let second = await service.polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(first.polished == raw && second.polished == raw)
        #expect(first.model == GroqModels.polish)
        #expect(server.requests("/models").count == 1)
        let body = try #require(server.requests("/chat/completions").first?.json)
        #expect(body["model"] as? String == GroqModels.polish)
        #expect(body["temperature"] as? Double == 0)
        #expect(body["max_tokens"] as? Int == 4096)
        #expect(body["reasoning_effort"] as? String == "none")
        #expect(body["reasoning_format"] == nil)
        let sent = try #require(body["messages"] as? [[String: String]])
        #expect(sent.map { $0["role"] } == ["system", "user"])
        #expect(sent[0]["content"] == PolishPrompt.systemPrompt)
    }

    @Test func fallsBackToGptOssWhenQwenIsMissing() async throws {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polishFallback) : Groq.chat(raw)
        }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == raw && result.model == GroqModels.polishFallback)
        let body = try #require(server.requests("/chat/completions").first?.json)
        #expect(body["reasoning_format"] as? String == "hidden")
        #expect(body["reasoning_effort"] as? String == "low")
    }

    @Test func ignoresInactiveModels() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models")
                ? .json(200, ["data": [["id": GroqModels.polish, "active": false], ["id": GroqModels.polishFallback]]])
                : Groq.chat(raw)
        }
        #expect(await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings()).model == GroqModels.polishFallback)
    }

    @Test func noUsableModelMeansRawText() async {
        let server = MockServer { _, _ in Groq.models("openai/gpt-oss-20b") }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == nil && result.error == .modelUnavailable)
        #expect(server.requests("/chat/completions").isEmpty)
    }

    @Test(arguments: [404, 400])
    func vanishedModelSwitchesToFallbackInTheSameDictation(status: Int) async throws {
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish, GroqModels.polishFallback) }
            return index == 0 ? Groq.error(status, code: "model_decommissioned") : Groq.chat(raw)
        }
        let service = service(server)
        let result = await service.polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == raw && result.model == GroqModels.polishFallback)
        // Das nächste Diktat nutzt direkt das Ausweichmodell.
        let next = await service.polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(next.model == GroqModels.polishFallback)
        #expect(server.requests("/models").count == 1)
    }

    @Test func retriesOnceAfterServerError() async {
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            return index == 0 ? Groq.error(502) : Groq.chat(raw)
        }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == raw)
        #expect(server.requests("/chat/completions").count == 2)
    }

    @Test func dailyLimitSwitchesToFallbackModelOnce() async throws {
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish, GroqModels.polishFallback) }
            let model = request.json?["model"] as? String
            return model == GroqModels.polish
                ? Groq.error(429, code: "rate_limit_exceeded", headers: ["Retry-After": "432"]) : Groq.chat(raw)
        }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == raw && result.model == GroqModels.polishFallback)
        #expect(server.requests("/chat/completions").count == 2)
    }

    @Test func shortRateLimitIsRetriedOnSameModel() async {
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish, GroqModels.polishFallback) }
            return index == 0 ? Groq.error(429, headers: ["Retry-After": "0.05"]) : Groq.chat(raw)
        }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == raw && result.model == GroqModels.polish)
    }

    @Test func twoFailuresMeanRawTextWithoutSensitiveDetails() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : .failure(.networkConnectionLost)
        }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == nil)
        #expect(result.error == .network)
        #expect(server.requests("/chat/completions").count == 2)
    }

    @Test func unreachableModelListStillTriesPreferredModel() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? .failure(.notConnectedToInternet) : Groq.chat(raw)
        }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == raw && result.model == GroqModels.polish)
    }

    @Test(arguments: [("", "empty"), ("Hier ist die Korrektur: " + raw, "meta"), ("Kurz.", "length"),
                      (raw + raw, "length"), ("Heute diskutieren alle zusammen neue schwierige Projekte.", "content")])
    func unsafeOutputIsRejected(output: String, reason: String) async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.chat(output)
        }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == nil && result.rejection == reason)
    }

    @Test func truncatedOutputIsRejected() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.chat(raw, finish: "length")
        }
        let result = await service(server).polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        #expect(result.polished == nil && result.rejection == "truncated")
    }

    @Test func parallelDictationsShareTheModelQuery() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish).delayed(0.2) : Groq.chat(raw)
        }
        let service = service(server)
        async let a = service.polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        async let b = service.polish(text: raw, messages: messages(), vocabulary: "", settings: PaplySettings())
        let results = await [a, b]
        #expect(results.allSatisfy { $0.polished == raw })
        #expect(server.requests("/models").count == 1)
    }

    @Test func staleModelListIsServedAndRefreshedInBackground() async throws {
        let now = Mutex(Date(timeIntervalSince1970: 0))
        let catalog = ModelCatalog(now: { now.withLock { $0 } })
        let server = MockServer { _, index in
            index == 0 ? Groq.models(GroqModels.polish) : Groq.models(GroqModels.polishFallback).delayed(0.3)
        }
        let client = server.client()
        #expect(await catalog.models(client) == [GroqModels.polish])
        #expect(await catalog.models(client) == [GroqModels.polish])
        #expect(server.requests("/models").count == 1)
        now.withLock { $0 = $0.addingTimeInterval(301) }
        // Veraltet: sofort die alte Liste, Auffrischung läuft im Hintergrund.
        let start = ContinuousClock.now
        #expect(await catalog.models(client) == [GroqModels.polish])
        #expect(ContinuousClock.now - start < .milliseconds(200))
        let deadline = ContinuousClock.now + .seconds(5)
        var refreshed = await catalog.models(client)
        while refreshed != [GroqModels.polishFallback] && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            refreshed = await catalog.models(client)
        }
        #expect(server.requests("/models").count == 2)
        #expect(refreshed == [GroqModels.polishFallback])
    }

    @Test func prewarmOnlyWarmsTheConnectionWhileTheListIsFresh() async {
        let now = Mutex(Date(timeIntervalSince1970: 0))
        let catalog = ModelCatalog(now: { now.withLock { $0 } })
        let server = MockServer { request, _ in
            request.method == "HEAD" ? .raw(404, Data()) : Groq.models(GroqModels.polish)
        }
        let client = server.client()
        func count(_ method: String) -> Int { server.requests("/models").filter { $0.method == method }.count }
        await GroqConnection.prewarm(client, catalog: catalog)          // leer → Liste laden
        #expect(count("GET") == 1 && count("HEAD") == 0)
        await GroqConnection.prewarm(client, catalog: catalog)          // frisch → nur HEAD
        #expect(count("GET") == 1 && count("HEAD") == 1)
        #expect(server.requests.last?.headers["Authorization"] == nil)
        now.withLock { $0 = $0.addingTimeInterval(5 * 3600) }
        await GroqConnection.prewarm(client, catalog: catalog)          // 5 h → weiter nur HEAD
        #expect(count("GET") == 1 && count("HEAD") == 2)
        now.withLock { $0 = $0.addingTimeInterval(2 * 3600) }
        await GroqConnection.prewarm(client, catalog: catalog)          // > 6 h → Liste neu
        #expect(count("GET") == 2)
        await GroqConnection.prewarm(client, catalog: catalog, refreshModels: true)
        #expect(count("GET") == 3)
    }
}
