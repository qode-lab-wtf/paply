import Foundation
import Synchronization
import Testing
@testable import PaplyKit

private func pipeline(_ server: MockServer, chunked: Bool = false, vocabulary: String = "",
                      history: [String] = []) -> DictationPipeline {
    var settings = PaplySettings()
    settings.chunkedUpload = chunked
    settings.vocabulary = vocabulary
    settings.spokenLanguages = ["de", "en"]
    return DictationPipeline(settings: settings, recentRawDictations: history,
                             client: server.client(), catalog: ModelCatalog())
}

private func feed(_ pipeline: DictationPipeline, _ samples: [Float]) async {
    var offset = 0
    while offset < samples.count {
        await pipeline.append(Array(samples[offset..<min(offset + 1_600, samples.count)]))
        offset += 1_600
    }
}

/// Polier-Modell gibt den Rohtext unverändert zurück (aus der Nachricht gelesen).
private func echoPolish(_ request: MockServer.Request) -> MockServer.Reply {
    guard let messages = request.json?["messages"] as? [[String: String]],
          let user = messages.last?["content"],
          let payload = try? JSONDecoder().decode(PolishPrompt.UserPayload.self, from: Data(user.utf8)) else {
        return Groq.error(400)
    }
    return Groq.chat(payload.current_dictation)
}

@Suite struct PipelineTests {
    @Test func silenceSendsNothing() async {
        let server = MockServer { _, _ in Groq.transcription("Vielen Dank.") }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.silence(3)))
        #expect(await !p.speechDetected)
        let outcome = await p.finish()
        #expect(outcome.text == "" && outcome.errorMessage == nil)
        #expect(server.requests.isEmpty)
        #expect(outcome.timings.audioSeconds == 3)
    }

    @Test func clicksAndBreathSendNothing() async {
        let server = MockServer { _, _ in Groq.transcription("Vielen Dank.") }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.clicks(2) + Synth.noise(0.5, dbfs: -32) + Synth.silence(1)))
        let outcome = await p.finish()
        #expect(outcome.text == "")
        #expect(server.requests.isEmpty)
    }

    @Test func uncertainUploadWithPolish() async throws {
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return Groq.chat("Morgen besprechen wir die offenen Aufgaben.") }
            return Groq.transcription("morgen besprechen wir die offenen aufgaben", logprob: -0.7)
        }
        let p = pipeline(server, vocabulary: "Paply", history: ["Vorher gesagt."])
        await feed(p, Synth.withFloor(Synth.silence(0.5) + Synth.speech(3) + Synth.silence(0.5)))
        #expect(await p.speechDetected)
        let outcome = await p.finish()
        #expect(outcome.raw == "morgen besprechen wir die offenen aufgaben")
        #expect(outcome.polished == "Morgen besprechen wir die offenen Aufgaben.")
        #expect(outcome.text == outcome.polished)
        #expect(outcome.languages == ["de"])
        #expect(outcome.polishModel == GroqModels.polish)
        #expect(outcome.timings.chunkCount == 1)
        #expect(outcome.timings.uploadedBytes > 1000)
        let t = outcome.timings
        #expect(t.transcriptionDoneMs != nil && t.polishDoneMs != nil && t.totalMs != nil)
        #expect(t.transcriptionDoneMs! <= t.polishDoneMs! && t.polishDoneMs! <= t.totalMs!)

        let upload = try #require(server.requests("/audio/transcriptions").first)
        let prompt = try #require(upload.field("prompt"))
        #expect(prompt.hasPrefix("Kurzes Update: Das Meeting ist verschoben, and the new date is next Friday."))
        #expect(prompt.hasSuffix("Paply."))
        #expect(upload.bodyText.contains("audio/flac"))
        let user = try #require((server.requests("/chat/completions").first?.json?["messages"] as? [[String: String]])?.last?["content"])
        let payload = try JSONDecoder().decode(PolishPrompt.UserPayload.self, from: Data(user.utf8))
        #expect(payload.background_do_not_edit == ["Vorher gesagt."])
        #expect(payload.uncertain_segments.count == 1)
        #expect(payload.custom_terms == "Paply")
    }

    @Test func rejectedPolishKeepsRawText() async {
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return Groq.chat("Hier ist der Text: Ganz anders formuliert.") }
            return Groq.transcription("Bitte ruf mich morgen früh an.")
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        let outcome = await p.finish()
        #expect(outcome.text == "Bitte ruf mich morgen früh an.")
        #expect(outcome.polished == nil && outcome.polishRejection == "meta")
    }

    @Test func chunksAreUploadedDuringRecordingAndJoinedInOrder() async throws {
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            return Groq.transcription(["Erstes Stück endet hier.", "Zweites Stück folgt.", "Und der Rest."][min(index, 2)],
                                      language: index == 1 ? "English" : "German")
        }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9) + Synth.speech(11) + Synth.silence(0.9)))
        // Zwei Stücke sind schon vor finish() unterwegs.
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.requests("/audio/transcriptions").count == 2)
        await feed(p, Synth.withFloor(Synth.speech(3)))
        let outcome = await p.finish()
        #expect(outcome.raw == "Erstes Stück endet hier. Zweites Stück folgt. Und der Rest.")
        #expect(outcome.text == outcome.raw)
        #expect(outcome.languages == ["de", "en"])
        #expect(outcome.timings.chunkCount == 4)
        let uploads = server.requests("/audio/transcriptions")
        #expect(uploads.count == 4)
        // Kontext: das Ende des Vorstücks steht am Ende des Prompts.
        #expect(uploads[1].field("prompt")?.hasSuffix("Erstes Stück endet hier.") == true)
        #expect(uploads[2].field("prompt")?.hasSuffix("Zweites Stück folgt.") == true)
        // Sprachwache: lange Stücke erkennt Whisper selbst, der kurze Rest folgt dem (englischen) Vorstück.
        #expect(uploads[0].field("language") == nil && uploads[1].field("language") == nil)
        #expect(uploads[2].field("language") == nil)
        #expect(uploads[3].field("language") == "en")
        #expect(outcome.languageSources == ["auto", "auto", "check-expected"])
    }

    @Test func silentTailIsNotUploaded() async {
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            return Groq.transcription("Nur ein Stück.")
        }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(4)))
        let outcome = await p.finish()
        #expect(outcome.raw == "Nur ein Stück.")
        #expect(server.requests("/audio/transcriptions").count == 1)
    }

    @Test func failedChunkIsResentTogetherWithTheRest() async throws {
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            // Erstes Stück scheitert zweimal, danach funktioniert alles.
            if index < 2 { return Groq.error(500) }
            return Groq.transcription("Das gesamte Diktat in einem Stück.")
        }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9) + Synth.speech(3)))
        let outcome = await p.finish()
        #expect(outcome.raw == "Das gesamte Diktat in einem Stück.")
        #expect(outcome.errorMessage == nil)
        let uploads = server.requests("/audio/transcriptions")
        // Gescheitertes Stück + Rest in einem Teil, kein getrennter Rest-Upload.
        #expect(uploads.count == 3)
        #expect(uploads[2].body.count > uploads[0].body.count)
        #expect(outcome.timings.chunkCount == 1)
    }

    @Test func finalTranscriptionFailureIsReportedInGerman() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.error(401)
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        let outcome = await p.finish()
        #expect(outcome.text == "")
        #expect(outcome.errorMessage == "Ungültiger Groq-Schlüssel – bitte in den Einstellungen prüfen.")
        #expect(server.requests("/chat/completions").isEmpty)
    }

    /// Whisper-Antwort mit zwei Segmenten: echtes Diktat (0–2 s) und Echo über Stille (3–5 s).
    private static func twoSegments(_ spoken: String, _ echo: String) -> MockServer.Reply {
        .json(200, ["text": " \(spoken) \(echo)", "language": "German", "segments": [
            ["start": 0.0, "end": 2.0, "text": " " + spoken, "avg_logprob": -0.2, "no_speech_prob": 0.0],
            ["start": 3.0, "end": 5.0, "text": " " + echo, "avg_logprob": -0.4, "no_speech_prob": 0.0],
        ]])
    }

    @Test func vocabularyEchoOverSilenceIsRemoved() async {
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            return Self.twoSegments("Hallo zusammen.", "Paply, Tailscale.")
        }
        let p = pipeline(server, vocabulary: "Paply, Tailscale")
        await feed(p, Synth.withFloor(Synth.speech(2) + Synth.silence(3)))
        #expect(await p.finish().text == "Hallo zusammen.")
    }

    @Test func spokenVocabularyStays() async {
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            return Groq.transcription("Paply, Tailscale.")
        }
        let p = pipeline(server, vocabulary: "Paply, Tailscale")
        await feed(p, Synth.withFloor(Synth.speech(1.5)))
        #expect(await p.finish().text == "Paply, Tailscale.")
    }

    @Test func spokenPrimerSentenceStaysButEchoOverSilenceGoes() async {
        // B1: Wer „Ich schreibe dir später.“ diktiert, bekommt es auch.
        let spoken = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            return Groq.transcription("Ich schreibe dir später.")
        }
        let p1 = pipeline(spoken)
        await feed(p1, Synth.withFloor(Synth.speech(1.5)))
        let kept = await p1.finish()
        #expect(kept.text == "Ich schreibe dir später." && !kept.noSpeech)
        // Fast Stille im Zeitraum des Primer-Satzes: Echo, wird verworfen.
        let echo = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            return Self.twoSegments("Hallo zusammen.", "Ich schreibe dir später, see you tomorrow.")
        }
        let p2 = pipeline(echo)
        await feed(p2, Synth.withFloor(Synth.speech(2) + Synth.silence(3)))
        #expect(await p2.finish().text == "Hallo zusammen.")
    }

    @Test func echoOnlyMeansNoSpeech() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish)
                : .json(200, ["text": " see you tomorrow", "language": "German", "segments": [
                    ["start": 2.5, "end": 4.5, "text": " see you tomorrow", "avg_logprob": -0.4, "no_speech_prob": 0.0]]])
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(1) + Synth.silence(4)))
        let outcome = await p.finish()
        #expect(outcome.text == "" && outcome.noSpeech && outcome.errorMessage == nil)
        #expect(server.requests("/chat/completions").isEmpty)
    }

    @Test func artifactPhraseIsDropped() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.transcription("Untertitel der Amara.org-Community")
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        #expect(await p.finish().text == "")
    }

    @Test func cancelStopsRunningUploads() async throws {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.transcription("Zu spät.").delayed(5)
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        let finishing = Task { await p.finish() }
        try await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        await p.cancel()
        let outcome = await finishing.value
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(outcome.text == "" && outcome.errorMessage == nil)
        #expect(server.requests("/chat/completions").isEmpty)
    }

    @Test func cancelBeforeFinishDiscardsEverything() async {
        let server = MockServer { _, _ in Groq.transcription("Nie gesendet.") }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        await p.cancel()
        await feed(p, Synth.withFloor(Synth.speech(2)))
        #expect(await p.finish().text == "")
        #expect(server.requests.isEmpty)
    }

    @Test func wavFormatOption() async throws {
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            return Groq.transcription("Hallo.")
        }
        var options = PipelineOptions()
        options.uploadFormat = .wav
        let p = DictationPipeline(settings: PaplySettings(), recentRawDictations: [], options: options,
                                  client: server.client(), catalog: ModelCatalog())
        await feed(p, Synth.withFloor(Synth.speech(2)))
        _ = await p.finish()
        let upload = try #require(server.requests("/audio/transcriptions").first)
        #expect(upload.bodyText.contains("filename=\"audio.wav\""))
    }

    @Test func primerUsesUserLanguages() throws {
        let frEs = try #require(CodeSwitchPrimer.text(languages: ["fr-FR", "es"]))
        #expect(frEs.hasPrefix("Petit point : la réunion est reportée"))
        #expect(frEs.contains("y la nueva fecha es el viernes"))
        #expect(CodeSwitchPrimer.pair(["de-DE", "en-US"])! == ("de", "en"))
        // Nur eine Sprache mit Beispielsatz → kein Primer (kein erfundenes Sprachpaar).
        #expect(CodeSwitchPrimer.pair(["de-DE"]) == nil)
        #expect(CodeSwitchPrimer.pair(["sv-SE", "ja"]) == nil)
        #expect(CodeSwitchPrimer.pair(["sv-SE", "it-IT", "en"])! == ("it", "en"))
        for code in CodeSwitchPrimer.phrases.keys {
            for other in CodeSwitchPrimer.phrases.keys where other != code {
                let text = try #require(CodeSwitchPrimer.text(languages: [code, other]))
                #expect(WhisperPrompt.estimateTokens(text) <= WhisperPrompt.primerTokenShare, "\(code)/\(other)")
            }
        }
        // Kein Entwickler-Jargon mehr im Beispiel.
        for (code, phrase) in CodeSwitchPrimer.phrases {
            let all = (phrase.open + phrase.close).joined(separator: " ").lowercased()
            #expect(!all.contains("build") && !all.contains("deploy"), "\(code)")
        }
    }
}
