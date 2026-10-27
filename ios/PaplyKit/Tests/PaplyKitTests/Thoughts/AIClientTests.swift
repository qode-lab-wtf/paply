import Foundation
import Synchronization
import Testing
@testable import PaplyKit

private typealias F = AIFixture

private func request(_ model: String = ThoughtStructurer.primaryModel, effort: String = "low") -> StructuredChatRequest {
    let built = try! ThoughtPrompt.build(F.input())
    return StructuredChatRequest(model: model, system: built.system, user: built.user, schemaName: ThoughtSchema.name,
                                 schema: ThoughtSchema.data(ThoughtSchema.full),
                                 maxCompletionTokens: built.maxCompletionTokens, reasoningEffort: effort)
}

@Suite struct AIChatStructuredTests {
    @Test func requestBodyUsesStrictSchemaWithoutStream() async throws {
        let server = MockServer { _, _ in F.reply(F.answer()) }
        _ = await server.client().chatStructured(request())
        let body = try #require(server.requests("/chat/completions").first?.json)
        #expect(body["model"] as? String == "openai/gpt-oss-120b")
        #expect(body["temperature"] as? Double == 0.1)
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["max_completion_tokens"] as? Int == ThoughtPrompt.maxCompletionTokens(transcript: F.transcript))
        #expect(body["stream"] == nil)
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["json_schema"] as? [String: Any])
        #expect(schema["name"] as? String == "paply_thought" && schema["strict"] as? Bool == true)
        let inner = try #require(schema["schema"] as? [String: Any])
        #expect((inner["required"] as? [String])?.sorted() == ["clean_text", "related", "tasks", "title", "topic"])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
        #expect(messages[0]["content"] == ThoughtPrompt.system)
        #expect(server.requests.first?.timeout == 120)
    }

    @Test func successCarriesContentFinishAndUsage() async throws {
        let server = MockServer { _, _ in F.reply("{}", total: 3_412) }
        let response = try await server.client().chatStructured(request()).get()
        #expect(response == StructuredChatResponse(content: "{}", finishReason: "stop",
                                                   usage: TokenUsage(prompt: 2_512, completion: 900, total: 3_412)))
    }

    @Test func truncatedAnswerIsReportedNotHidden() async throws {
        let server = MockServer { _, _ in F.reply("{\"title\":", finish: "length") }
        #expect(try await server.client().chatStructured(request()).get().finishReason == "length")
    }

    @Test(arguments: [("0.5", 0.5), ("432", 432.0)])
    func rateLimitKeepsRetryAfter(header: String, seconds: Double) async {
        let server = MockServer { _, _ in Groq.error(429, code: "rate_limit_exceeded", headers: ["Retry-After": header]) }
        #expect(await server.client().chatStructured(request()) == .failure(.http(status: 429, code: "rate_limit_exceeded", retryAfter: seconds)))
        #expect(server.requests.count == 1)
    }

    @Test func schemaViolationKeepsGroqCode() async {
        let server = MockServer { _, _ in Groq.error(400, code: "json_validate_failed") }
        #expect(await server.client().chatStructured(request()) == .failure(.http(status: 400, code: "json_validate_failed", retryAfter: nil)))
    }

    /// Nur Prüfstand: `failed_generation` kommt über `chatStructuredDiagnosed`, `chatStructured` bleibt gleich.
    @Test func failedGenerationOnlyThroughTheDiagnosticCall() async {
        let server = MockServer { _, _ in
            .json(400, ["error": ["message": "Failed to validate JSON", "code": "json_validate_failed",
                                  "failed_generation": "{\"title\": 1}"]])
        }
        let expected = GroqFailure.http(status: 400, code: "json_validate_failed", retryAfter: nil)
        let diagnosed = await server.client().chatStructuredDiagnosed(request())
        #expect(diagnosed.result == .failure(expected))
        #expect(diagnosed.failedGeneration == "{\"title\": 1}")
        #expect(await server.client().chatStructured(request()) == .failure(expected))
        let ok = MockServer { _, _ in F.reply(F.answer()) }
        let fine = await ok.client().chatStructuredDiagnosed(request())
        #expect(fine.failedGeneration == nil)
        if case .success = fine.result {} else { Issue.record("Erfolg erwartet") }
    }

    @Test func unauthorizedAndNetwork() async {
        let unauthorized = MockServer { _, _ in Groq.error(401, code: "invalid_api_key") }
        #expect(await unauthorized.client().chatStructured(request()) == .failure(.http(status: 401, code: "invalid_api_key", retryAfter: nil)))
        let offline = MockServer { _, _ in .failure(.networkConnectionLost) }
        #expect(await offline.client().chatStructured(request()) == .failure(.network(code: URLError.networkConnectionLost.rawValue)))
    }
}

/// Mock-Strukturierer mit eigenem Ledger in einem Temp-Ordner.
private func structurer(_ server: MockServer, ledger: TokenLedger? = nil) -> ThoughtStructurer {
    ThoughtStructurer(ledger: ledger, transport: server.transport, baseURL: server.baseURL)
}

private func tempLedger(limits: TokenLedger.Limits = .init(), now: @escaping @Sendable () -> Date = Date.init) -> TokenLedger {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("paply-ledger-\(UUID().uuidString)/ledger.json")
    return TokenLedger(fileURL: url, limits: { limits }, now: now)
}

private func modelOf(_ request: MockServer.Request) -> String? { request.json?["model"] as? String }
private func effort(_ request: MockServer.Request) -> String? { request.json?["reasoning_effort"] as? String }

@Suite struct AIStructurerTests {
    @Test func successValidatesAndSettlesTheLedger() async throws {
        let server = MockServer { _, _ in F.reply(F.answer(), total: 3_412) }
        let ledger = tempLedger()
        let outcome = await structurer(server, ledger: ledger).structure(F.input(), apiKey: "test-placeholder")
        guard case .success(let result, let model, let usage) = outcome else { Issue.record("Erfolg erwartet: \(outcome)"); return }
        #expect(model == "openai/gpt-oss-120b" && usage.total == 3_412)
        #expect(result.topic == .existing("t_umzug") && result.cleanText == F.goodClean)
        #expect(await ledger.summary().tokens == 3_412)
    }

    @Test func shortRateLimitWaitsOnceOnTheSameModel() async {
        let server = MockServer { _, index in
            index == 0 ? Groq.error(429, headers: ["Retry-After": "0.1"]) : F.reply(F.answer())
        }
        let outcome = await structurer(server).structure(F.input(), apiKey: "test-placeholder")
        guard case .success(_, let model, _) = outcome else { Issue.record("Erfolg erwartet"); return }
        #expect(model == "openai/gpt-oss-120b")
        #expect(server.requests.map(modelOf) == ["openai/gpt-oss-120b", "openai/gpt-oss-120b"])
    }

    @Test func longRateLimitSwitchesTo20bOnce() async {
        let server = MockServer { request, _ in
            modelOf(request) == ThoughtStructurer.primaryModel ? Groq.error(429, headers: ["Retry-After": "600"]) : F.reply(F.answer())
        }
        let outcome = await structurer(server).structure(F.input(), apiKey: "test-placeholder")
        guard case .success(_, let model, _) = outcome else { Issue.record("Erfolg erwartet"); return }
        #expect(model == "openai/gpt-oss-20b")
    }

    @Test func bothModelsLimitedMeansWaitingLimitForAtLeast15Minutes() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let server = MockServer { _, _ in Groq.error(429, headers: ["Retry-After": "120"]) }
        let ledger = tempLedger(now: { now })
        let outcome = await ThoughtStructurer(ledger: ledger, transport: server.transport, baseURL: server.baseURL, now: { now })
            .structure(F.input(), apiKey: "test-placeholder")
        #expect(outcome == .wait(.waitingLimit, retryAt: now.addingTimeInterval(900), message: "Groq-Limit · später erneut"))
        #expect(server.requests.count == 2)
        // 429 wird mit 0 abgerechnet.
        #expect(await ledger.summary().tokens == 0)
    }

    @Test func missingModelFallsBackThenGivesUp() async {
        let fallback = MockServer { request, _ in
            modelOf(request) == ThoughtStructurer.primaryModel ? Groq.error(404, code: "model_not_found") : F.reply(F.answer())
        }
        guard case .success(_, let model, _) = await structurer(fallback).structure(F.input(), apiKey: "test-placeholder") else {
            Issue.record("Erfolg erwartet"); return
        }
        #expect(model == "openai/gpt-oss-20b")
        let gone = MockServer { _, _ in Groq.error(404, code: "model_not_found") }
        #expect(await structurer(gone).structure(F.input(), apiKey: "test-placeholder") == .unusable(code: "model_missing"))
    }

    @Test func schemaFailureRetriesOnceWithMediumEffort() async {
        let server = MockServer { _, index in index == 0 ? Groq.error(400, code: "json_validate_failed") : F.reply(F.answer()) }
        guard case .success = await structurer(server).structure(F.input(), apiKey: "test-placeholder") else {
            Issue.record("Erfolg erwartet"); return
        }
        #expect(server.requests.map(effort) == ["low", "medium"])
    }

    @Test func truncatedOrUnreadableTwiceIsUnusable() async {
        let truncated = MockServer { _, _ in F.reply("{\"title\":", finish: "length") }
        #expect(await structurer(truncated).structure(F.input(), apiKey: "test-placeholder") == .unusable(code: "invalid_output"))
        #expect(truncated.requests.map(effort) == ["low", "medium"])
        let garbage = MockServer { _, _ in F.reply("kein json") }
        #expect(await structurer(garbage).structure(F.input(), apiKey: "test-placeholder") == .unusable(code: "invalid_output"))
        let empty = MockServer { _, _ in F.reply(F.answer(title: "", clean: "")) }
        #expect(await structurer(empty).structure(F.input(), apiKey: "test-placeholder") == .unusable(code: "invalid_output"))
    }

    @Test func unauthorizedMeansWaitingKeyAndSettlesWithZero() async {
        let server = MockServer { _, _ in Groq.error(401, code: "invalid_api_key") }
        let ledger = tempLedger()
        #expect(await structurer(server, ledger: ledger).structure(F.input(), apiKey: "test-placeholder")
                == .wait(.waitingKey, retryAt: nil, message: "Groq-Schlüssel prüfen"))
        #expect(await ledger.summary().tokens == 0)
        #expect(await structurer(server).structure(F.input(), apiKey: "  ")
                == .wait(.waitingKey, retryAt: nil, message: "Groq-Schlüssel fehlt"))
        #expect(server.requests.count == 1)
    }

    @Test func networkLossMeansWaitingNetworkAndKeepsTheEstimate() async throws {
        let server = MockServer { _, _ in .failure(.networkConnectionLost) }
        let ledger = tempLedger()
        #expect(await structurer(server, ledger: ledger).structure(F.input(), apiKey: "test-placeholder")
                == .wait(.waitingNetwork, retryAt: nil, message: "Wartet auf Netz"))
        let built = try ThoughtPrompt.build(F.input())
        #expect(await ledger.summary().tokens == built.estimate)
        let broken = MockServer { _, _ in Groq.error(503) }
        #expect(await structurer(broken).structure(F.input(), apiKey: "test-placeholder")
                == .wait(.waitingNetwork, retryAt: nil, message: "Groq ist gerade gestört"))
    }

    @Test func fullLedgerWaitsWithoutRequest() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var small = TokenLedger.Limits()
        small.dailyTokens = 9_000
        let ledger = tempLedger(limits: small, now: { now })
        _ = try await ledger.reserve(model: "x", amount: 7_000, unit: .tokens)
        let server = MockServer { _, _ in F.reply(F.answer()) }
        let outcome = await structurer(server, ledger: ledger).structure(F.input(), apiKey: "test-placeholder")
        #expect(outcome == .wait(.waitingBudget, retryAt: now.addingTimeInterval(86_400), message: "Gedanken-Budget für heute erreicht"))
        #expect(server.requests.isEmpty)
        var tiny = TokenLedger.Limits()
        tiny.dailyTokens = 1_000
        #expect(await structurer(server, ledger: tempLedger(limits: tiny)).structure(F.input(), apiKey: "test-placeholder")
                == .unusable(code: "budget_small"))
    }

    @Test func hugeTranscriptIsTooLarge() async {
        let transcript = String(repeating: "Das ist ein sehr langer Gedanke über die Wohnung. ", count: 500)
        let server = MockServer { _, _ in F.reply(F.answer()) }
        #expect(await structurer(server).structure(F.input(transcript: transcript), apiKey: "test-placeholder") == .unusable(code: "too_large"))
        #expect(server.requests.isEmpty)
    }

    @Test func partModeUsesThePartPromptAndSchema() async throws {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: [
            "clean_text": F.goodClean, "tasks": [F.task("Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken")],
        ]), as: UTF8.self)
        let server = MockServer { _, _ in F.reply(json) }
        let outcome = await structurer(server).structure(F.input(part: (index: 2, count: 3)), apiKey: "test-placeholder")
        guard case .success(let result, _, _) = outcome else { Issue.record("Erfolg erwartet"); return }
        #expect(result.cleanText == F.goodClean && result.tasks.count == 1 && result.title.isEmpty)
        let body = try #require(server.requests.first?.json)
        let schema = (body["response_format"] as? [String: Any])?["json_schema"] as? [String: Any]
        #expect(schema?["name"] as? String == "paply_thought_part")
        let system = (body["messages"] as? [[String: String]])?.first?["content"] ?? ""
        #expect(system.hasPrefix("This is part 2 of 3 of one long spoken thought.") && !system.contains("RELATED"))
    }

    @Test func neverUsesQwen() async {
        let server = MockServer { _, index in index < 3 ? Groq.error(429, headers: ["Retry-After": "900"]) : F.reply(F.answer()) }
        _ = await structurer(server).structure(F.input(), apiKey: "test-placeholder")
        #expect(server.requests.allSatisfy { modelOf($0)?.hasPrefix("openai/gpt-oss") == true })
    }

    /// Entwicklerbereich `paply.thoughts.model` (Wunsch H2): Modell und Ausweich per Closure, je Gedanke gelesen.
    @Test func modelsComeFromTheClosure() async {
        let chosen = Mutex(ThoughtStructurer.Models(primary: "openai/gpt-oss-20b", fallback: nil))
        let server = MockServer { _, _ in F.reply(F.answer()) }
        let configured = ThoughtStructurer(ledger: nil, transport: server.transport, baseURL: server.baseURL,
                                           models: { chosen.withLock { $0 } })
        guard case .success(_, let first, _) = await configured.structure(F.input(), apiKey: "test-placeholder") else {
            Issue.record("Erfolg erwartet"); return
        }
        #expect(first == "openai/gpt-oss-20b")
        chosen.withLock { $0 = .standard }
        guard case .success(_, let second, _) = await configured.structure(F.input(), apiKey: "test-placeholder") else {
            Issue.record("Erfolg erwartet"); return
        }
        #expect(second == ThoughtStructurer.primaryModel)
        #expect(server.requests.map { modelOf($0) } == ["openai/gpt-oss-20b", ThoughtStructurer.primaryModel])
    }

    @Test func withoutFallbackA404GivesUpAtOnce() async {
        let server = MockServer { _, _ in Groq.error(404, code: "model_not_found") }
        let configured = ThoughtStructurer(ledger: nil, transport: server.transport, baseURL: server.baseURL,
                                           models: { .init(primary: "openai/gpt-oss-20b", fallback: "openai/gpt-oss-20b") })
        #expect(await configured.structure(F.input(), apiKey: "test-placeholder") == .unusable(code: "model_missing"))
        #expect(server.requests.count == 1)
    }

    /// `now` = Aufnahmezeit (`recordedAt`), auch wenn die Uhr schon weiter ist.
    @Test func nowIsTheRecordingTimeWhenKnown() async throws {
        let server = MockServer { _, _ in F.reply(F.answer()) }
        let recorded = Date(timeIntervalSince1970: 1_793_095_200)
        let configured = ThoughtStructurer(ledger: nil, transport: server.transport, baseURL: server.baseURL,
                                           now: { recorded.addingTimeInterval(2 * 86_400) })
        var input = F.input()
        input.recordedAt = recorded
        _ = await configured.structure(input, apiKey: "test-placeholder")
        let messages = try #require(server.requests.first?.json?["messages"] as? [[String: Any]])
        let user = try #require(messages.last?["content"] as? String)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(user.utf8)) as? [String: Any])
        #expect(json["now"] as? String == ThoughtPrompt.nowLabel(recorded, uiLanguage: "de"))
    }

    /// v2: Ohne `recordedAt` trägt die Nutzer-Nachricht `now` aus der Uhr des Strukturierers.
    @Test func requestCarriesNowFromTheClock() async throws {
        let server = MockServer { _, _ in F.reply(F.answer()) }
        let clock = Date(timeIntervalSince1970: 1_793_095_200)
        let configured = ThoughtStructurer(ledger: nil, transport: server.transport, baseURL: server.baseURL, now: { clock })
        _ = await configured.structure(F.input(), apiKey: "test-placeholder")
        let messages = try #require(server.requests.first?.json?["messages"] as? [[String: Any]])
        let user = try #require(messages.last?["content"] as? String)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(user.utf8)) as? [String: Any])
        #expect(json["now"] as? String == ThoughtPrompt.nowLabel(clock, uiLanguage: "de"))
    }
}
