import Foundation
import Testing
@testable import PaplyKit

// Regressionstests zur Opus-Nachprüfung (Punkte 1–11).

private func reject(_ raw: String, _ result: String, vocabulary: String = "") -> String? {
    PolishSafetyNet.rejection(raw: raw, result: result, vocabulary: vocabulary)
}

private func feed(_ pipeline: DictationPipeline, _ samples: [Float]) async {
    var offset = 0
    while offset < samples.count {
        await pipeline.append(Array(samples[offset..<min(offset + 1_600, samples.count)]))
        offset += 1_600
    }
}

@Suite struct EditAlignmentTests {
    /// Punkt 1: Wegfallende Wörter vor einer Korrektur verschieben die Zuordnung nicht mehr.
    @Test(arguments: [
        ("ich glaube äh das er morgen kommt und alles mitbringt", "Ich glaube, dass er morgen kommt und alles mitbringt."),
        ("ich äh hab das schon erledigt und abgeschickt", "Ich habe das schon erledigt und abgeschickt."),
        ("ich ich hab das Angebot gestern verschickt", "Ich habe das Angebot gestern verschickt."),
        ("die äh daten bank ist seit gestern wieder voll", "Die Datenbank ist seit gestern wieder voll."),
        ("ok dann machen wir das so wie besprochen", "Okay, dann machen wir das so wie besprochen."),
    ])
    func goodPolishesPass(raw: String, result: String) {
        #expect(reject(raw, result) == nil)
    }

    @Test func meaningChangesStillFail() {
        #expect(reject("Im Daily Morgan sollten wir klären, wer das übernimmt.",
                       "Im Daily Morning sollten wir klären, wer das übernimmt.") == "replaced")
        #expect(reject("Er braucht dafür äh ungefähr zwei Wochen, sagt er.",
                       "Er braucht dafür ungefähr zwei Woche, sagt er.") == "replaced")
        #expect(reject("Wir sammeln die Anfragen der Kunden auf einer eigenen Seite.",
                       "Wir sammeln die Anfragen der Kundinnen und Kunden auf einer eigenen Seite.") == "inserted")
        // Auch wenn davor ein Wort wegfällt, bleibt eine große Ersetzung eine Ersetzung.
        #expect(reject("ich äh treffe mich morgen mit Morgan im Büro am Bahnhof",
                       "Ich treffe mich morgen mit Morning im Büro am Bahnhof.") == "replaced")
    }
}

@Suite struct SentenceStartNegationTests {
    /// Punkt 2: Komma nach „Nein“/„No“ am Satzanfang ändert die Zählung nicht.
    @Test func commaAfterSentenceInitialNo() {
        #expect(reject("Nein das passt so leider nicht für uns.", "Nein, das passt so leider nicht für uns.") == nil)
        #expect(reject("Gut. No that does not work for the team.", "Gut. No, that does not work for the team.") == nil)
        #expect(TextAnalysis.negationCount("Nein das passt") == TextAnalysis.negationCount("Nein, das passt"))
        // Spanisch/Italienisch: „No/Non“ am Satzanfang verneint – Streichen fällt weiter auf.
        #expect(reject("No quiero ir mañana a la reunión.", "Quiero ir mañana a la reunión.") == "negation")
        #expect(reject("Non posso venire domani alla riunione.", "Posso venire domani alla riunione.") == "negation")
    }
}

@Suite struct LowFrequencyNoiseTests {
    private func detected(_ signal: [Float]) -> Bool {
        var vad = VoiceActivityDetector()
        vad.process(signal)
        return vad.speechDetected
    }

    /// Punkt 3: tieffrequenter Lärm ist keine Stimme.
    @Test func carPassingIsNoSpeech() {
        let car = Synth.ramp(Synth.brown(4, dbfs: -30), from: -25, to: 0)
        #expect(!detected(Synth.withFloor(Synth.silence(1) + car + Synth.silence(1))))
    }

    @Test func mainsHumIsNoSpeech() {
        let hum = Synth.tones(3, [(50, 1), (100, 0.5), (150, 0.3), (200, 0.2)], dbfs: -30)
        #expect(!detected(Synth.withFloor(Synth.silence(1) + hum + Synth.silence(1))))
        let hum60 = Synth.tones(3, [(60, 1), (120, 0.5), (180, 0.3)], dbfs: -30)
        #expect(!detected(Synth.withFloor(Synth.silence(1) + hum60 + Synth.silence(1))))
    }

    @Test func softChordIsNoSpeech() {
        let chord = Synth.tones(3, [(220, 1), (277.18, 1), (329.63, 1), (440, 0.4), (554.37, 0.4), (659.26, 0.4)], dbfs: -35)
        #expect(!detected(Synth.withFloor(Synth.silence(1) + chord + Synth.silence(1))))
    }

    @Test func speechOverCarNoiseIsSpeech() {
        let rumble = Synth.brown(3, dbfs: -34)
        let mixed = zip(Synth.speech(3, dbfs: -34), rumble).map { $0 + $1 }
        #expect(detected(Synth.withFloor(Synth.silence(1) + mixed + Synth.silence(1))))
    }

    @Test func periodicityOfReferenceSignals() {
        func value(_ signal: [Float]) -> Float {
            Array(signal.prefix(480)).withUnsafeBufferPointer { VoiceActivityDetector.analyze($0).periodicity }
        }
        #expect(value(Synth.voice(0.03, dbfs: -20)) > 0.8)
        #expect(value(Synth.brown(0.03, dbfs: -20)) < 0.6)
        #expect(value(Synth.tones(0.03, [(50, 1), (100, 0.5), (150, 0.3)], dbfs: -20)) < 0.6)
    }
}

@Suite struct StreamCompletenessTests {
    private func sse(_ lines: [String]) -> MockServer.Reply {
        .raw(200, Data(lines.map { $0 + "\n\n" }.joined().utf8), headers: ["Content-Type": "text/event-stream"])
    }
    private let raw = "Morgen besprechen wir gemeinsam unsere offenen Aufgaben."

    /// Punkt 4: Stream ohne [DONE] und ohne finish_reason ist unvollständig.
    @Test func cutStreamIsRetriedThenReported() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish)
                : self.sse(["data: {\"choices\":[{\"delta\":{\"content\":\"Morgen besprechen\"},\"finish_reason\":null}]}"])
        }
        let result = await PolishService(client: server.client(), catalog: ModelCatalog()).polish(
            text: raw, messages: PolishPrompt.buildMessages(text: raw, history: [], vocabulary: ""), vocabulary: "",
            settings: PaplySettings())
        #expect(result.polished == nil && result.error == .invalidResponse)
        #expect(server.requests("/chat/completions").count == 2)
    }

    @Test(arguments: ["length", "content_filter"])
    func irregularFinishIsTruncated(reason: String) async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.chat(self.raw, finish: reason)
        }
        let result = await PolishService(client: server.client(), catalog: ModelCatalog()).polish(
            text: raw, messages: PolishPrompt.buildMessages(text: raw, history: [], vocabulary: ""), vocabulary: "",
            settings: PaplySettings())
        #expect(result.polished == nil && result.rejection == "truncated")
    }

    @Test func doneWithoutFinishReasonIsComplete() {
        var parser = ChatStreamParser()
        _ = parser.consume("data: {\"choices\":[{\"delta\":{\"content\":\"Hallo.\"}}]}")
        _ = parser.consume("data: [DONE]")
        #expect(parser.completion() == .success(ChatCompletion(content: "Hallo.", finishReason: nil)))
    }

    /// Punkt 8: nur an \n trennen; U+2028/U+2029/NEL im JSON-Text bleiben erhalten, \r wird entfernt.
    @Test func unicodeLineSeparatorsInsideJSON() async {
        let content = "Erste\u{2028}zweite\u{2029}dritte\u{0085}vierte"
        let event = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": content], "finish_reason": "stop"]]])
        let body = Data("data: ".utf8) + event + Data("\r\n\r\ndata: [DONE]\r\n\r\n".utf8)
        let server = MockServer { _, _ in .raw(200, body, headers: ["Content-Type": "text/event-stream"]) }
        let result = await server.client().chat(model: GroqModels.polish, messages: [], maxTokens: 10)
        #expect(result == .success(ChatCompletion(content: content, finishReason: "stop")))
    }

    /// Punkt 9: `"error": null` ist kein Fehler; Limit im Stream wie HTTP 429 → Ausweichmodell.
    @Test func nullErrorIsIgnored() {
        var parser = ChatStreamParser()
        _ = parser.consume("data: {\"error\":null,\"choices\":[{\"delta\":{\"content\":\"Ok.\"},\"finish_reason\":\"stop\"}]}")
        _ = parser.consume("data: [DONE]")
        #expect(parser.completion() == .success(ChatCompletion(content: "Ok.", finishReason: "stop")))
    }

    @Test func rateLimitInsideStreamSwitchesToFallback() async {
        let limit = "data: {\"error\":{\"message\":\"Rate limit reached for model on tokens per day (TPD): Limit 200000. Please try again in 7m11.5s.\",\"type\":\"tokens\",\"code\":\"rate_limit_exceeded\"}}"
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish, GroqModels.polishFallback) }
            return request.json?["model"] as? String == GroqModels.polish ? self.sse([limit]) : Groq.chat(self.raw)
        }
        let result = await PolishService(client: server.client(), catalog: ModelCatalog()).polish(
            text: raw, messages: PolishPrompt.buildMessages(text: raw, history: [], vocabulary: ""), vocabulary: "",
            settings: PaplySettings())
        #expect(result.polished == raw && result.model == GroqModels.polishFallback)
        var parser = ChatStreamParser()
        _ = parser.consume(limit)
        #expect(parser.completion() == .failure(.http(status: 429, code: "rate_limit_exceeded", retryAfter: 431.5)))
        #expect(GroqClient.retryAfter(message: "Please try again in 1h2m3s") == 3723)
        #expect(GroqClient.retryAfter(message: "kein Hinweis") == nil)
    }
}

@Suite struct ShortTailTests {
    /// Punkt 5: Ein kurzes Schlusswort nach dem letzten Schnitt wird hochgeladen.
    @Test func shortFinalWordIsUploaded() async {
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            return Groq.transcription(index == 0 ? "Bitte schick mir das Angebot." : "Ja.")
        }
        var settings = PaplySettings()
        settings.spokenLanguages = ["de", "en"]
        var options = PipelineOptions()
        options.polish = false
        let p = DictationPipeline(settings: settings, recentRawDictations: [], options: options,
                                  client: server.client(), catalog: ModelCatalog())
        // 11 s Rede, Pause (Schnitt), dann ein kurzes „Ja“ (120 ms Vokal) und kurze Stille.
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9) + Synth.voice(0.12, dbfs: -24) + Synth.silence(0.4)))
        let outcome = await p.finish()
        #expect(server.requests("/audio/transcriptions").count == 2)
        #expect(outcome.text == "Bitte schick mir das Angebot. Ja.")
    }

    @Test func clicksAfterLastCutAreNotUploaded() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.transcription("Erstes Stück.")
        }
        var options = PipelineOptions()
        options.polish = false
        let p = DictationPipeline(settings: PaplySettings(), recentRawDictations: [], options: options,
                                  client: server.client(), catalog: ModelCatalog())
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9) + Synth.clicks(2)))
        _ = await p.finish()
        #expect(server.requests("/audio/transcriptions").count == 1)
    }
}

@Suite struct NumberFormatTests {
    /// Punkt 6: Ziffernfolgen mit Leerzeichen/Satzzeichen/Doppelpunkt werden zusammengezogen.
    @Test func formattingOfNumbersIsAllowed() {
        #expect(reject("Wir treffen uns morgen um 15.30 Uhr am Haupteingang vom Büro.",
                       "Wir treffen uns morgen um 15:30 Uhr am Haupteingang vom Büro.") == nil)
        #expect(reject("Meine Handynummer lautet 0171 123 45 67, ruf gern jederzeit an.",
                       "Meine Handynummer lautet 0171 1234567, ruf gern jederzeit an.") == nil)
        #expect(EditCheck.digitsPreserved(raw: "um 15.30 Uhr", result: "um 15:31 Uhr") == false)
    }

    @Test func newNumbersAreForbidden() {
        #expect(EditCheck.digitsPreserved(raw: "Das kostet viel.", result: "Das kostet 100 Euro.") == false)
        #expect(EditCheck.digitsPreserved(raw: "um drei Uhr", result: "um 3 Uhr"))
    }

    @Test func spokenSelfCorrectionOfANumber() {
        // Kurzer Satz: ohne aufgelöste Lesart fiele er an Länge und Inhalt durch.
        #expect(reject("Wir treffen uns um 15 Uhr, ich meine um 16 Uhr.", "Wir treffen uns um 16 Uhr.") == nil)
        #expect(reject("Ruf mich um 9 an, sorry, um 10 an.", "Ruf mich um 10 an.") == nil)
        #expect(reject("Treffen am Montag, nein Moment, am Dienstag.", "Treffen am Dienstag.") == nil)
        // Ohne Marker darf keine Zahl fehlen …
        #expect(reject("Wir treffen uns um 15 Uhr und dann um 16 Uhr.", "Wir treffen uns um 16 Uhr.") != nil)
        // … und die Ersatzzahl muss im Ergebnis stehen.
        #expect(reject("Wir treffen uns um 15 Uhr, ich meine um 16 Uhr.", "Wir treffen uns um 17 Uhr.") != nil)
        // „wait“ ohne Komma ist keine Korrektur.
        #expect(EditCheck.resolvedSelfCorrection("I can't wait to see you at 5 tomorrow.") == nil)
        #expect(EditCheck.resolvedSelfCorrection("Wir treffen uns um 15 Uhr, ich meine um 16 Uhr.") == "Wir treffen uns um 16 Uhr.")
    }
}

@Suite struct TranscriptionTimeoutTests {
    /// Punkt 7: Leerlauf-Timeout wächst mit der Audiolänge.
    @Test func timeoutScalesWithAudio() async {
        #expect(GroqClient.transcriptionTimeout(audioSeconds: nil) == 30)
        #expect(GroqClient.transcriptionTimeout(audioSeconds: 60) == 30)
        #expect(GroqClient.transcriptionTimeout(audioSeconds: 600) == 65)
        let server = MockServer { _, _ in Groq.transcription("Hallo.") }
        _ = await server.client().transcribe(audio: AudioEncoder.encode([1, 2, 3], preferFLAC: false), model: "m",
                                             language: nil, prompt: nil, audioSeconds: 1200)
        #expect(server.requests.first?.timeout == 115)
    }
}
