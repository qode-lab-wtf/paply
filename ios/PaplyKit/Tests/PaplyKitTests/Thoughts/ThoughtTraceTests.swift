import Foundation
import Testing
@testable import PaplyKit

private typealias F = AIFixture

/// Diagnose der Gedanken-Verarbeitung (`ThoughtTrace` → `Diag.log`): Beginn/Ende mit Dauer, Groq-Aufrufe,
/// Wartegründe – nie Inhalte.
@Suite("Gedanken-Diagnose")
struct ThoughtTraceTests {
    /// Wörter, die in keinem Ereignis stehen dürfen (Rohtext, Titel, Text, Thema, Aufgabe des Gedankens).
    static let content = ["tomaten", "garten", "gießen", "Tomaten gießen"]

    static func assertNoContent(_ recorder: TraceRecorder, extra: [String] = []) {
        for value in recorder.strings {
            for word in content + extra {
                #expect(!value.lowercased().contains(word.lowercased()), "Inhalt im Protokoll: \(value)")
            }
        }
    }

    @Test func processingLogsBeginEndAndDurationsButNeverContent() async throws {
        let recorder = TraceRecorder()
        let h = try Harness.make(trace: recorder.trace)
        defer { h.cleanup() }
        let id = try await h.capture(seconds: 2)
        await h.run()
        #expect(await h.thought(id)?.state == .done)
        let short = ThoughtTrace.short(id)
        #expect(recorder.events.map(\.name) == ["thought.transcribe.begin", "thought.transcribe.end",
                                                "thought.structure.begin", "thought.structure.end"])
        let begin = try #require(recorder.named("thought.transcribe.begin").first)
        #expect(begin["id"] == .s(short) && begin["model"] != nil && begin["audioS"] != nil)
        let transcribed = try #require(recorder.named("thought.transcribe.end").first)
        #expect(transcribed["result"] == .s("ok") && transcribed["live"] == .b(false))
        #expect(transcribed["textLen"] == .i("ähm also die Tomaten im Garten muss ich morgen gießen".count))
        #expect(transcribed["langs"] == .s("de"))
        if case .d(let ms)? = transcribed["ms"] { #expect(ms >= 0) } else { Issue.record("ms fehlt") }
        let started = try #require(recorder.named("thought.structure.begin").first)
        #expect(started["parts"] == .i(1) && started["textLen"] != nil)
        let ended = try #require(recorder.named("thought.structure.end").first)
        #expect(ended["result"] == .s("ok") && ended["model"] == .s("openai/gpt-oss-120b") && ended["fallback"] == .b(false))
        #expect(ended["tokens"] == .i(3_000) && ended["tasks"] == .i(1) && ended["topic"] == .s("new"))
        #expect(ended["textIsRaw"] == .b(false))
        if case .d(let ms)? = ended["ms"] { #expect(ms >= 0) } else { Issue.record("ms fehlt") }
        Self.assertNoContent(recorder)
    }

    @Test func waitingReasonsAreLogged() async throws {
        let recorder = TraceRecorder()
        let flags = Box<Flags?>(nil)
        // Diktat läuft zuerst; nach der ersten Pause ist es fertig
        let h = try Harness.make(onSleep: { flags.value?.busy = false }, trace: recorder.trace)
        flags.value = h.flags
        defer { h.cleanup() }
        h.flags.online = false
        let id = try await h.capture()
        await h.run()
        let wait = try #require(recorder.named("thought.wait").first)
        #expect(wait["id"] == .s(ThoughtTrace.short(id)) && wait["state"] == .s("waitingNetwork"))
        h.flags.online = true
        h.flags.busy = true
        await h.run()
        #expect(await h.thought(id)?.state == .done)
        let dictation = try #require(recorder.named("thought.wait.dictation").first)
        #expect(dictation["id"] == .s(ThoughtTrace.short(id)) && dictation["ms"] != nil)
        Self.assertNoContent(recorder)
    }

    @Test func emptyAndUnusableAreLoggedAsCodes() async throws {
        let recorder = TraceRecorder()
        let h = try Harness.make(structurer: MockStructurer([.unusable(code: "invalid_output")]),
                                 transcriber: MockTranscriber([.noSpeech]), trace: recorder.trace)
        defer { h.cleanup() }
        _ = try await h.capture()
        await h.run()
        #expect(recorder.named("thought.transcribe.end").first?["result"] == .s("noSpeech"))
        #expect(recorder.named("thought.empty").count == 1)
        _ = try await h.capture()
        await h.run()
        let ended = try #require(recorder.named("thought.structure.end").last)
        #expect(ended["result"] == .s("raw") && ended["code"] == .s("invalid_output"))
        Self.assertNoContent(recorder)
    }

    /// Groq-Aufrufe: Modell, Status, Tokens, nächster Schritt; die Kurz-ID setzt der Prozessor (Task-Local).
    @Test func structurerLogsEveryCallWithStatusTokensAndNextStep() async {
        let recorder = TraceRecorder()
        let server = MockServer { request, _ in
            request.json?["model"] as? String == ThoughtStructurer.primaryModel
                ? Groq.error(429, code: "rate_limit_exceeded", headers: ["Retry-After": "600"]) : F.reply(F.answer(), total: 3_412)
        }
        let structurer = ThoughtStructurer(ledger: nil, transport: server.transport, baseURL: server.baseURL, trace: recorder.trace)
        let outcome = await ThoughtTrace.$thoughtID.withValue("s_abcdef12") {
            await structurer.structure(F.input(), apiKey: "test-placeholder")
        }
        guard case .success = outcome else { Issue.record("Erfolg erwartet: \(outcome)"); return }
        let calls = recorder.named("thought.groq")
        #expect(calls.count == 2)
        #expect(calls.first?["model"] == .s("openai/gpt-oss-120b") && calls.first?["status"] == .s("http-429"))
        #expect(calls.first?["groqCode"] == .s("rate_limit_exceeded") && calls.first?["retryAfterS"] == .d(600))
        #expect(calls.first?["next"] == .s("fallback"))
        #expect(calls.last?["model"] == .s("openai/gpt-oss-20b") && calls.last?["status"] == .s("ok"))
        #expect(calls.last?["tokens"] == .i(3_412) && calls.last?["valid"] == .b(true) && calls.last?["next"] == .s("done"))
        #expect(calls.last?["finish"] == .s("stop") && calls.last?["effort"] == .s("low"))
        #expect(calls.allSatisfy { $0["id"] == .s("s_abcdef12") && $0["ms"] != nil })
        // Ein Gedanke über die Wohnung in der Oranienstraße: nichts davon im Protokoll
        Self.assertNoContent(recorder, extra: ["Oranienstraße", "Wohnung", "Makler", "Unterlagen", "Schufa"])
    }

    @Test func invalidOutputRetriesWithMediumAndLogsBothCalls() async {
        let recorder = TraceRecorder()
        let server = MockServer { _, index in index == 0 ? Groq.error(400, code: "json_validate_failed") : F.reply(F.answer()) }
        let structurer = ThoughtStructurer(ledger: nil, transport: server.transport, baseURL: server.baseURL, trace: recorder.trace)
        _ = await structurer.structure(F.input(), apiKey: "test-placeholder")
        let calls = recorder.named("thought.groq")
        #expect(calls.map { $0["status"] } == [.s("http-400"), .s("ok")])
        #expect(calls.map { $0["next"] } == [.s("medium"), .s("done")])
        #expect(calls.map { $0["effort"] } == [.s("low"), .s("medium")])
    }

    @Test func ledgerRefusalIsAWaitingReason() async {
        let recorder = TraceRecorder()
        var small = TokenLedger.Limits()
        small.dailyTokens = 100
        let limits = small
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paply-trace-\(UUID().uuidString)/ledger.json")
        let ledger = TokenLedger(fileURL: url, limits: { limits })
        let server = MockServer { _, _ in F.reply(F.answer()) }
        let structurer = ThoughtStructurer(ledger: ledger, transport: server.transport, baseURL: server.baseURL, trace: recorder.trace)
        #expect(await structurer.structure(F.input(), apiKey: "test-placeholder") == .unusable(code: "budget_small"))
        #expect(recorder.named("thought.groq.ledger").first?["reason"] == .s("tooSmall"))
        #expect(recorder.named("thought.groq").isEmpty)
    }
}
