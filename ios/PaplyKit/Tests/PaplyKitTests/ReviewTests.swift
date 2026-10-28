import Foundation
import Synchronization
import Testing
@testable import PaplyKit

// Tests zu den Punkten des Opus-Reviews (B1, W1–W8, K1–K10) und den Wünschen der App-Seite.

private func pipeline(_ server: MockServer, chunked: Bool = false, polish: Bool = true,
                      languages: [String] = ["de", "en"]) -> DictationPipeline {
    var settings = PaplySettings()
    settings.chunkedUpload = chunked
    settings.spokenLanguages = languages
    var options = PipelineOptions()
    options.polish = polish
    return DictationPipeline(settings: settings, recentRawDictations: [], options: options,
                             client: server.client(), catalog: ModelCatalog())
}

private func feed(_ pipeline: DictationPipeline, _ samples: [Float]) async {
    var offset = 0
    while offset < samples.count {
        await pipeline.append(Array(samples[offset..<min(offset + 1_600, samples.count)]))
        offset += 1_600
    }
}

private func echoPolish(_ request: MockServer.Request) -> MockServer.Reply {
    guard let messages = request.json?["messages"] as? [[String: String]],
          let user = messages.last?["content"],
          let payload = try? JSONDecoder().decode(PolishPrompt.UserPayload.self, from: Data(user.utf8)) else {
        return Groq.error(400)
    }
    return Groq.chat(payload.current_dictation)
}

/// Standard-Server: Modellliste, Echo-Polieren, feste Transkription.
private func standardServer(_ text: String = "Hallo zusammen.", transcriptionDelay: Double = 0,
                            chatDelay: Double = 0, modelsDelay: Double = 0) -> MockServer {
    MockServer { request, _ in
        if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish).delayed(modelsDelay) }
        if request.path.hasSuffix("/chat/completions") { return echoPolish(request).delayed(chatDelay) }
        return Groq.transcription(text).delayed(transcriptionDelay)
    }
}

private func waitUntil(_ seconds: Double = 3, _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
    while !condition() && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
}

@Suite struct PipelineGuaranteeTests {
    @Test func nothingIsUploadedBeforeSpeech() async {
        let server = MockServer { _, _ in Groq.transcription("Vielen Dank.") }
        let p = pipeline(server, chunked: true)
        // 24 s Klicks und einzelne Atemzüge mit langen Pausen: Pausen-Schnitte wären möglich.
        var audio: [Float] = []
        for seed in 1...6 {
            audio += Synth.clicks(2.5) + Synth.noise(0.5, dbfs: -32, seed: UInt64(seed)) + Synth.silence(1)
        }
        await feed(p, Synth.withFloor(audio))
        #expect(await !p.speechDetected)
        let outcome = await p.finish()
        #expect(outcome.text == "" && outcome.noSpeech)
        #expect(server.requests.isEmpty)
    }

    @Test func firstUploadOnlyAfterSpeech() async {
        let server = standardServer()
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.silence(13)))
        #expect(server.requests.isEmpty)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9)))
        #expect(await p.speechDetected)
        await waitUntil { server.requests("/audio/transcriptions").count == 1 }
        #expect(server.requests("/audio/transcriptions").count == 1)
        await p.cancel()
    }

    @Test func cancelAbortsRunningChunkUploadImmediately() async {
        let server = standardServer(transcriptionDelay: 10)
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9)))
        await waitUntil { server.requests("/audio/transcriptions").count == 1 }
        await p.cancel()
        // Unter Volllast der parallelen Tests dauert das Abbrechen mitunter über 1 s; 5 s liegen
        // weiter klar unter der Antwortzeit des Servers (10 s) und belegen den sofortigen Abbruch.
        await waitUntil(5) { server.stoppedCount > 0 }
        #expect(server.stoppedCount >= 1)
        #expect(await p.finish().text == "")
    }
}

@Suite struct RetryAndReleaseTests {
    @Test func retryResendsOnlyTheFailedPart() async throws {
        let online = Mutex(false)
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            // Erstes Stück klappt, danach fällt das Netz aus.
            if index == 0 { return Groq.transcription("Erstes Stück.") }
            return online.withLock { $0 } ? Groq.transcription("Zweiter Teil.") : .failure(.notConnectedToInternet)
        }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9)))
        await waitUntil { server.requests("/audio/transcriptions").count == 1 }
        await feed(p, Synth.withFloor(Synth.speech(4)))
        let failed = await p.finish()
        #expect(failed.text == "" && failed.errorMessage?.hasPrefix("Keine Verbindung") == true)
        #expect(!failed.noSpeech)
        #expect(await p.canRetry)
        let firstBody = server.requests("/audio/transcriptions")[0].body.count
        let before = server.requests("/audio/transcriptions").count
        online.withLock { $0 = true }
        let outcome = await p.retry()
        #expect(outcome.text == "Erstes Stück. Zweiter Teil." && outcome.errorMessage == nil)
        #expect(await !p.canRetry)
        // Nur der gescheiterte Rest wurde erneut gesendet – das erste Stück nicht.
        let resent = Array(server.requests("/audio/transcriptions").dropFirst(before))
        #expect(resent.count == 1)
        #expect(resent[0].body.count < firstBody)
        #expect(outcome.timings.chunkCount == 1)
        #expect(outcome.timings.uploadedBytes > 0 && outcome.timings.uploadedBytes < failed.timings.uploadedBytes + firstBody)
    }

    @Test func retryAfterSuccessReturnsStoredResult() async {
        let server = standardServer()
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        let first = await p.finish()
        let requests = server.requests.count
        let again = await p.retry()
        #expect(again.text == first.text && again.text == "Hallo zusammen.")
        #expect(server.requests.count == requests)
        #expect(await !p.canRetry)
    }

    @Test func retryBeforeFinishActsLikeFinishAndAfterCancelReturnsNothing() async {
        let server = standardServer()
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        #expect(await p.retry().text == "Hallo zusammen.")
        #expect(await p.finish().text == "Hallo zusammen.")
        await p.cancel()
        #expect(await p.retry().text == "")
    }

    @Test func releaseAudioKeepsResultButEndsRetry() async {
        let online = Mutex(false)
        let server = MockServer { request, _ in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if request.path.hasSuffix("/chat/completions") { return echoPolish(request) }
            return online.withLock { $0 } ? Groq.transcription("Hallo.") : .failure(.notConnectedToInternet)
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        _ = await p.finish()
        #expect(await p.canRetry)
        await p.releaseAudio()
        #expect(await !p.canRetry)
        online.withLock { $0 = true }
        let outcome = await p.retry()
        #expect(outcome.text == "" && outcome.errorMessage == "Die Aufnahme ist nicht mehr verfügbar.")

        let ok = standardServer()
        let q = pipeline(ok)
        await feed(q, Synth.withFloor(Synth.speech(2)))
        _ = await q.finish()
        await q.releaseAudio()
        #expect(await q.retry().text == "Hallo zusammen.")
    }

    @Test func releaseAudioDuringRecordingIsIgnored() async {
        let server = standardServer()
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        await p.releaseAudio()
        #expect(await p.finish().text == "Hallo zusammen.")
    }
}

@Suite struct ConcurrencyAndCancelTests {
    @Test func twoConcurrentFinishCallsShareOneRun() async {
        let server = standardServer(transcriptionDelay: 0.2)
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        async let a = p.finish()
        async let b = p.finish()
        async let c = p.retry()
        let results = await [a, b, c]
        #expect(results.allSatisfy { $0.text == "Hallo zusammen." })
        #expect(server.requests("/audio/transcriptions").count == 1)
        #expect(server.requests("/chat/completions").count == 1)
    }

    @Test func cancelDuringPolish() async {
        let server = standardServer(chatDelay: 10)
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        let finishing = Task { await p.finish() }
        await waitUntil { !server.requests("/chat/completions").isEmpty }
        let start = ContinuousClock.now
        await p.cancel()
        let outcome = await finishing.value
        #expect(ContinuousClock.now - start < .seconds(4))
        #expect(outcome.text == "")
    }

    @Test func cancelDuringFirstModelList() async {
        let server = standardServer(modelsDelay: 10)
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        let finishing = Task { await p.finish() }
        await waitUntil { !server.requests("/audio/transcriptions").isEmpty && !server.requests("/models").isEmpty }
        try? await Task.sleep(for: .milliseconds(150))
        let start = ContinuousClock.now
        await p.cancel()
        let outcome = await finishing.value
        #expect(ContinuousClock.now - start < .seconds(4))
        #expect(outcome.text == "")
        #expect(server.requests("/chat/completions").isEmpty)
    }

    @Test func cancelDuringFallbackUpload() async {
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            if index < 2 { return Groq.error(500) }
            return Groq.transcription("Zu spät.").delayed(10)
        }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9) + Synth.speech(2)))
        let finishing = Task { await p.finish() }
        await waitUntil { server.requests("/audio/transcriptions").count == 3 }
        let start = ContinuousClock.now
        await p.cancel()
        let outcome = await finishing.value
        // Server antwortet erst nach 10 s; 7 s Grenze belegt den Abbruch auch unter Testlast
        #expect(ContinuousClock.now - start < .seconds(7))
        #expect(outcome.text == "" && outcome.errorMessage == nil)
    }

    @Test func hangingChunkDoesNotBlockTheNext() async {
        let server = MockServer { request, index in
            if request.path.hasSuffix("/models") { return Groq.models(GroqModels.polish) }
            return index == 0 ? Groq.transcription("Hängt.").delayed(60) : Groq.transcription("Zweites Stück.")
        }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9) + Synth.speech(11) + Synth.silence(0.9)))
        let fed = ContinuousClock.now
        await waitUntil(20) { server.requests("/audio/transcriptions").count == 2 }
        #expect(server.requests("/audio/transcriptions").count == 2)
        // Das Vorstück hängt 60 s; das nächste Stück wartet nur ~1,5 s. Die Grenze von 20 s lässt
        // Raum für Volllast der parallelen Tests und liegt weiter klar unter den 60 s.
        #expect(ContinuousClock.now - fed < .seconds(20))
        // Ohne das Ende des hängenden Vorstücks im Prompt.
        #expect(server.requests("/audio/transcriptions")[1].field("prompt")?.contains("Hängt") != true)
        await p.cancel()
    }

    @Test func networkFailureStopsFurtherChunks() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : .failure(.notConnectedToInternet)
        }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9)))
        await waitUntil { server.requests("/audio/transcriptions").count == 2 }
        try? await Task.sleep(for: .milliseconds(100))
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9) + Synth.speech(11) + Synth.silence(0.9)))
        try? await Task.sleep(for: .milliseconds(300))
        // Nur das erste Stück (zwei Versuche); danach keine weiteren Stücke.
        #expect(server.requests("/audio/transcriptions").count == 2)
        let outcome = await p.finish()
        #expect(outcome.errorMessage?.hasPrefix("Keine Verbindung") == true)
        // Abschluss: ein einziger Rückfall-Teil (zwei Versuche).
        #expect(server.requests("/audio/transcriptions").count == 4)
    }

    @Test func resetWhilePipelineIsAlive() async {
        let server = standardServer(transcriptionDelay: 0.4)
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        server.transport.reset()                       // vor dem Abschluss
        let finishing = Task { await p.finish() }
        await waitUntil { !server.requests("/audio/transcriptions").isEmpty }
        server.transport.reset()                       // während eine Anfrage läuft
        let outcome = await finishing.value
        #expect(outcome.text == "Hallo zusammen." && outcome.errorMessage == nil)
    }
}

@Suite struct NoiseAndCutTests {
    @Test(arguments: [10.0, 12.0, 14.0])
    func quietSpeechOverCafeNoiseIsSpeech(snr: Double) async {
        var vad = VoiceActivityDetector()
        vad.process(Synth.withFloor(Synth.silence(1) + Synth.speech(2, dbfs: -40 + snr) + Synth.silence(1), dbfs: -40))
        #expect(vad.speechDetected, "\(snr) dB")

        let server = standardServer()
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.silence(1) + Synth.speech(2, dbfs: -40 + snr) + Synth.silence(1), dbfs: -40))
        let outcome = await p.finish()
        #expect(outcome.text == "Hallo zusammen." && !outcome.noSpeech)
    }

    @Test func noCutWhenSpeechGetsQuiet() {
        // 12 s normal, dann 3 s leise, aber stimmhaft (8 dB über dem Rauschen): keine Pause.
        let audio = Synth.withFloor(Synth.silence(2) + Synth.speech(12, dbfs: -22) + Synth.speech(3, dbfs: -52), dbfs: -60)
        var vad = VoiceActivityDetector()
        var planner = ChunkPlanner()
        var cuts: [Range<Int>] = []
        var offset = 0
        while offset < audio.count {
            vad.process(Array(audio[offset..<min(offset + 1_600, audio.count)]))
            while let cut = planner.nextCut(vad) { cuts.append(cut) }
            offset += 1_600
        }
        #expect(cuts.isEmpty)
    }

    @Test func floorFollowsChangingEnvironment() {
        // 40 s leise (−60), dann 40 s laut (−35): Das Grundrauschen folgt nach ~30 s.
        var vad = VoiceActivityDetector()
        vad.process(Synth.noise(40, dbfs: -60) + Synth.noise(40, dbfs: -35, seed: 9))
        #expect(abs(vad.floorDbfs - -35) < 3)
        #expect(abs(Double(vad.floor(at: 100)) - -60) < 3)
    }
}

@Suite struct NetRuleTests {
    private func reject(_ raw: String, _ result: String, vocabulary: String = "") -> String? {
        PolishSafetyNet.rejection(raw: raw, result: result, vocabulary: vocabulary)
    }

    @Test func digitsMustSurvive() {
        let raw = "Wir treffen uns am Donnerstag um 15 Uhr im großen Besprechungsraum."
        #expect(reject(raw, "Wir treffen uns am Donnerstag um 16 Uhr im großen Besprechungsraum.") == "digits")
        // Neue Ziffern sind verboten („15“ → „15:00“).
        #expect(reject(raw, "Wir treffen uns am Donnerstag um 15:00 Uhr im großen Besprechungsraum.") == "digits")
        #expect(reject("Das kostet 1.000 Euro pro Monat für das ganze Team.", "Das kostet 1000 Euro pro Monat für das ganze Team.") == nil)
        #expect(reject("3. Müssen wir noch klären, wie wir mit den Anfragen umgehen.",
                       "Drittens müssen wir noch klären, wie wir mit den Anfragen umgehen.") == nil)
        #expect(EditCheck.digitsPreserved(raw: "Zimmer 12 und 14", result: "Zimmer 12 und 41") == false)
        #expect(EditCheck.digitsPreserved(raw: "um drei Uhr", result: "um 3 Uhr"))
    }

    @Test func selfCorrectionWithNoIsAllowed() {
        #expect(reject("Please send the quarterly report to the whole marketing team on Monday, no wait, on Tuesday.",
                       "Please send the quarterly report to the whole marketing team on Tuesday.") == nil)
        #expect(reject("Envoie le rapport trimestriel à toute l'équipe marketing lundi, non, enfin mardi.",
                       "Envoie le rapport trimestriel à toute l'équipe marketing mardi.") == nil)
        #expect(reject("Schick den neuen Quartalsbericht bitte noch heute an das ganze Marketingteam und die Geschäftsführung am Montag, nein Moment, am Dienstag.",
                       "Schick den neuen Quartalsbericht bitte noch heute an das ganze Marketingteam und die Geschäftsführung am Dienstag.") == nil)
        // Satzinterne Verneinung zählt weiter.
        #expect(reject("That is really no problem for the whole team at all.",
                       "That is really a problem for the whole team at all.") == "negation")
        // Am Satzanfang zählt „No“ immer (es/it: „No quiero“); die Auflösung prüft die
        // Selbstkorrektur-Lesart.
        #expect(TextAnalysis.negationCount("No, I mean Tuesday.") == 1)
        #expect(TextAnalysis.negationCount("Meet on Monday, no, I mean Tuesday.") == 0)
        #expect(TextAnalysis.negationCount("Non posso venire domani.") == 1)
    }

    @Test func compoundsAndHyphens() {
        #expect(reject("Die daten bank für das Projekt ist leider schon voll.",
                       "Die Datenbank für das Projekt ist leider schon voll.") == nil)
        #expect(reject("Das neue Designsystem ist seit Montag im Projekt verfügbar.",
                       "Das neue Design-System ist seit Montag im Projekt verfügbar.") == nil)
    }

    @Test func turkishDottedAndDotlessI() {
        #expect(TextAnalysis.normalizedLower("İSTANBUL") == TextAnalysis.normalizedLower("istanbul"))
        #expect(TextAnalysis.normalizedLower("ıstanbul") == "istanbul")
        #expect(reject("istanbul'da yarın buluşalım mı, hayır değil mi", "İstanbul'da yarın buluşalım mı, hayır değil mi?") == nil)
    }

    @Test func meaningChangingReplacementsAreCaught() {
        #expect(reject("Im Daily Morgan sollten wir klären, wer das übernimmt.",
                       "Im Daily Morning sollten wir klären, wer das übernimmt.") == "replaced")
        #expect(reject("Er braucht dafür ungefähr zwei Wochen, sagt er.",
                       "Er braucht dafür ungefähr zwei Woche, sagt er.") == "replaced")
        #expect(reject("Wir sammeln die Anfragen der Kunden auf einer eigenen Seite.",
                       "Wir sammeln die Anfragen der Kundinnen und Kunden auf einer eigenen Seite.") == "inserted")
        #expect(reject("Ich schlage vor, dass wir dafür eine eigene Seite anlegen.",
                       "Ich schlage vor, dass wir dazu eine eigene Seite anlegen.") == "replaced")
    }

    @Test func goodCorrectionsPass() {
        #expect(reject("Das Buckend ist fertig, die Schnittstelle ist dokumentiert und alle Endpunkte haben Tests.",
                       "Das Backend ist fertig, die Schnittstelle ist dokumentiert und alle Endpunkte haben Tests.") == nil)
        #expect(reject("Für das Unboarding brauchen wir außerdem noch die finalen Screenshots und einen Text.",
                       "Für das Onboarding brauchen wir außerdem noch die finalen Screenshots und einen Text.") == nil)
        #expect(reject("Ich habe den pull request gemerget, aber der Build läuft nicht.",
                       "Ich habe den Pull Request gemerged, aber der Build läuft nicht.") == nil)
        // Größere Korrektur nur als eigener Begriff.
        let raw = "Bitte installiere heute Abend Cooper Netties auf dem neuen Server im Rechenzentrum und prüfe danach alle Dienste."
        let fixed = "Bitte installiere heute Abend Kubernetes auf dem neuen Server im Rechenzentrum und prüfe danach alle Dienste."
        #expect(reject(raw, fixed) != nil)
        #expect(reject(raw, fixed, vocabulary: "Kubernetes") == nil)
        // Umstellung ist kein neues Wort.
        #expect(reject("morgen gehen wir gemeinsam essen und danach ins Kino", "Gemeinsam gehen wir morgen essen und danach ins Kino.") == nil)
    }

    @Test func arabicAndHebrewNegation() {
        #expect(reject("أنا لا أريد الذهاب غدا إلى الاجتماع الكبير", "أنا أريد الذهاب غدا إلى الاجتماع الكبير") == "negation")
        #expect(reject("אני לא יכול לבוא מחר לפגישה הגדולה", "אני יכול לבוא מחר לפגישה הגדולה") == "negation")
    }

    @Test func hesitationsOnly() {
        #expect(Lexicon.fillers.contains("ähm") && Lexicon.fillers.contains("euh") && Lexicon.fillers.contains("yyy"))
        for word in ["like", "also", "este", "vale", "tipo", "pronto", "genre", "gewoon", "şey", "znaczy"] {
            #expect(!Lexicon.fillers.contains(TextAnalysis.normalizedLower(word)), "\(word)")
        }
    }
}

@Suite struct TextJoinTests {
    @Test func cjkJoinsWithoutSpace() {
        #expect(TranscriptCleanup.join(["我明天去开会。", "然后回家。"]) == "我明天去开会。然后回家。")
        #expect(TranscriptCleanup.join(["明日は会議", "です。"]) == "明日は会議です。")
        #expect(TranscriptCleanup.join(["Hello there.", "See you."]) == "Hello there. See you.")
        #expect(TranscriptCleanup.join(["会议。", "Then we go."]) == "会议。 Then we go.")
    }

    @Test func singleCJKCharacterIsAWord() async {
        #expect(!SilenceFilter.isTrivialTranscript("好"))
        #expect(!SilenceFilter.isTrivialTranscript("是。"))
        #expect(SilenceFilter.isTrivialTranscript("?"))
        let server = standardServer("好")
        let p = pipeline(server, languages: ["zh", "en"])
        await feed(p, Synth.withFloor(Synth.speech(1)))
        #expect(await p.finish().text == "好")
    }

    @Test func repeatedLeadAtChunkBoundaryIsRemoved() {
        #expect(TranscriptCleanup.join(["Wir treffen uns morgen früh im Büro.", "morgen früh im Büro und dann gehen wir essen."])
                == "Wir treffen uns morgen früh im Büro. und dann gehen wir essen.")
        // Zwei kurze Wörter können echt doppelt gesprochen sein.
        #expect(TranscriptCleanup.join(["Das ist so.", "ist so gut."]) == "Das ist so. ist so gut.")
    }

    @Test func partialEchoSegmentsAreRemovedOnlyWithoutVoice() {
        let primer = "Kurzes Update: Das Meeting ist verschoben, and the new date is next Friday. Ich schreibe dir später, see you tomorrow."
        func clean(_ echo: String, voiced: Double, tail: String? = nil) -> String {
            let segments = [WhisperSegment(text: " Das Angebot ist raus.", start: 0, end: 2),
                            WhisperSegment(text: " " + echo, start: 3, end: 4)]
            return TranscriptCleanup.removeEchoes(text: "Das Angebot ist raus. \(echo)", segments: segments, primer: primer,
                                                  previousText: tail, vocabulary: "", duration: 4,
                                                  voiced: { start, _ in start < 2.5 ? 900 : voiced }).text
        }
        // Teil-Echo des Beispielsatzes (3 Wörter) über Stille: weg; gesprochen: bleibt.
        #expect(clean("see you tomorrow", voiced: 0) == "Das Angebot ist raus.")
        #expect(clean("see you tomorrow", voiced: 600) == "Das Angebot ist raus. see you tomorrow")
        // Zwei Wörter aus dem Beispielsatz bleiben immer (oft wirklich gesagt).
        #expect(clean("see you", voiced: 0) == "Das Angebot ist raus. see you")
        // Ende des Vorstücks: schon ab zwei Wörtern ein Echo.
        #expect(clean("morgen früh", voiced: 0, tail: "Wir treffen uns morgen früh") == "Das Angebot ist raus.")
    }
}

@Suite struct ClientDetailTests {
    @Test func multipartCarriesUTF8AndLineBreaks() throws {
        let audio = AudioEncoder.Encoded(data: Data([1, 2]), fileName: "audio.flac", mimeType: "audio/flac", encodeMs: 0)
        let body = GroqClient.multipart(boundary: "b", fields: [("prompt", "Müller, 日本語\nzweite Zeile")], audio: audio)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"prompt\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nMüller, 日本語\nzweite Zeile\r\n--b"))
        #expect(!text.contains("name=\"language\""))
    }

    @Test func requestTimeouts() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish) : Groq.transcription("Hallo.")
        }
        _ = await server.client().transcribe(audio: AudioEncoder.encode([1, 2, 3], preferFLAC: false), model: "m",
                                             language: nil, prompt: nil)
        _ = await GroqConnection.checkKey(server.client())
        #expect(server.requests("/audio/transcriptions").first?.timeout == 30)
        #expect(server.requests("/models").first?.timeout == 15)
    }

    @Test func rateLimitedKeyIsValid() async {
        let server = MockServer { _, _ in Groq.error(429, headers: ["Retry-After": "60"]) }
        #expect(await GroqConnection.checkKey(server.client()) == .valid)
        #expect(server.requests.count == 1)
    }

    @Test func plainJSONAnswerWorksToo() async {
        let server = MockServer { request, _ in
            request.path.hasSuffix("/models") ? Groq.models(GroqModels.polish)
                : Groq.chatJSON("Morgen besprechen wir gemeinsam unsere offenen Aufgaben.")
        }
        let service = PolishService(client: server.client(), catalog: ModelCatalog())
        let raw = "morgen besprechen wir gemeinsam unsere offenen aufgaben"
        let result = await service.polish(text: raw, messages: PolishPrompt.buildMessages(text: raw, history: [], vocabulary: ""),
                                          vocabulary: "", settings: PaplySettings())
        #expect(result.polished == "Morgen besprechen wir gemeinsam unsere offenen Aufgaben.")
        #expect(server.requests("/chat/completions").first?.json?["stream"] as? Bool == true)
    }

    @Test func streamParser() {
        var parser = ChatStreamParser()
        for line in ["data: {\"choices\":[{\"delta\":{\"content\":\"Hal\"},\"finish_reason\":null}]}",
                     "", "data: {\"choices\":[{\"delta\":{\"content\":\"lo.\"},\"finish_reason\":\"stop\"}]}", "data: [DONE]"] {
            if parser.consume(line) == .done { break }
        }
        #expect(parser.completion() == .success(ChatCompletion(content: "Hallo.", finishReason: "stop")))
        var broken = ChatStreamParser()
        _ = broken.consume("data: {\"error\":{\"message\":\"x\"}}")
        #expect(broken.completion() == .failure(.invalidResponse))
    }

    @Test func noPrimerWithOnlyOneKnownLanguage() async {
        let server = standardServer()
        let p = pipeline(server, languages: ["de"])
        await feed(p, Synth.withFloor(Synth.speech(2)))
        _ = await p.finish()
        #expect(server.requests("/audio/transcriptions").first?.field("prompt") == nil)
    }

    @Test func pollishFailureCodesAreStable() {
        #expect(PolishFailureCode.allCases.map(\.rawValue) == ["disabled", "model-unavailable", "rate-limited", "unauthorized",
                                                               "server-error", "request-rejected", "network", "invalid-response", "cancelled"])
        #expect(GroqFailure.http(status: 429, code: nil, retryAfter: nil).polishCode == .rateLimited)
        #expect(GroqFailure.network(code: -1009).polishCode == .network)
        var outcome = DictationOutcome()
        outcome.polishError = "rate-limited"
        #expect(outcome.polishFailure == .rateLimited)
        let decoded = try? JSONDecoder().decode(DictationOutcome.self, from: Data(#"{"text":"Hallo"}"#.utf8))
        #expect(decoded?.text == "Hallo" && decoded?.noSpeech == false)
    }
}

@Suite struct KeyCheckTests {
    @Test func outcomes() async {
        let valid = MockServer { _, _ in Groq.models(GroqModels.polish) }
        #expect(await GroqConnection.checkKey(valid.client()) == .valid)
        let invalid = MockServer { _, _ in Groq.error(401, code: "invalid_api_key") }
        #expect(await GroqConnection.checkKey(invalid.client()) == .invalid)
        #expect(invalid.requests.count == 1)
        let offline = MockServer { _, _ in .failure(.notConnectedToInternet) }
        #expect(await GroqConnection.checkKey(offline.client()) == .offline)
        let broken = MockServer { _, _ in Groq.error(500) }
        guard case .failed(let message) = await GroqConnection.checkKey(broken.client()) else {
            Issue.record("failed erwartet"); return
        }
        #expect(message.contains("500"))
        #expect(broken.requests.count == 2)
        #expect(await GroqConnection.checkKey(apiKey: "  ") == .invalid)
        #expect(await !GroqConnection.validate(apiKey: ""))
    }
}

@Suite struct TempFileTests {
    @Test func flacLeavesNoFilesOnSuccessOrFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("paply-tmp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = AudioEncoder.int16(Synth.speech(1))
        _ = try AudioEncoder.flac(samples[...], directory: directory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(throws: (any Error).self) { try AudioEncoder.flac([Int16]()[...], directory: directory) }
        #expect(throws: (any Error).self) {
            try AudioEncoder.flac(samples[...], directory: directory.appendingPathComponent("fehlt"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
