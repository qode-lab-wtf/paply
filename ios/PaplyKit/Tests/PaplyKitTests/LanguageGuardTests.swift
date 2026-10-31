import Foundation
import Testing
@testable import PaplyKit

/// Hauptsprache fest „de“, damit die Tests nicht von den Sprachen des Rechners abhängen.
private func pipeline(_ server: MockServer, chunked: Bool = false, languages: [String] = ["de", "en"],
                      primary: String? = "de", fixed: String? = nil) -> DictationPipeline {
    var settings = PaplySettings()
    settings.chunkedUpload = chunked
    settings.spokenLanguages = languages
    settings.primaryLanguage = primary
    settings.language = fixed
    var options = PipelineOptions()
    options.polish = false
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

@Suite struct LanguageGuardTests {
    // MARK: Reine Logik

    @Test func primaryIsChosenElseFirstDeviceLanguageElseFirst() {
        let users = ["en", "de"] // z. B. erste Tastatur Englisch
        #expect(LanguageGuard.primary(chosen: nil, userLanguages: users, device: "de-DE") == "de")
        #expect(LanguageGuard.primary(chosen: "en", userLanguages: users, device: "de-DE") == "en")
        // Gewählte nicht mehr in der Liste: wieder die Standardregel.
        #expect(LanguageGuard.primary(chosen: "fr", userLanguages: users, device: "de-DE") == "de")
        // iPhone-Sprache nicht unter den Nutzersprachen: die erste Nutzersprache.
        #expect(LanguageGuard.primary(chosen: nil, userLanguages: ["de-DE", "en"], device: "ja-JP") == "de")
        #expect(LanguageGuard.primary(chosen: nil, userLanguages: ["de-DE", "en"], device: nil) == "de")
        #expect(LanguageGuard.primary(chosen: "en", userLanguages: [], device: "de") == nil)
    }

    @Test func settingsWithoutPrimaryLanguageStillDecode() throws {
        let old = #"{"transcriptionModel":"whisper-large-v3","polishModel":"p","fallbackPolishModel":"f","vocabulary":"Paply","chunkedUpload":true,"spokenLanguages":["de","en"]}"#
        let decoded = try JSONDecoder().decode(PaplySettings.self, from: Data(old.utf8))
        #expect(decoded.primaryLanguage == nil && decoded.spokenLanguages == ["de", "en"] && decoded.vocabulary == "Paply")
        var settings = PaplySettings()
        settings.primaryLanguage = "en"
        let roundTrip = try JSONDecoder().decode(PaplySettings.self, from: JSONEncoder().encode(settings))
        #expect(roundTrip == settings)
        // Älteres Ergebnis ohne Sprachquellen.
        let outcome = try JSONDecoder().decode(DictationOutcome.self, from: Data(#"{"text":"Hallo"}"#.utf8))
        #expect(outcome.languageSources.isEmpty)
    }

    // MARK: Pipeline

    @Test func shortMatchingPieceIsSentOnceWithoutLanguage() async throws {
        let server = MockServer { _, _ in Groq.transcription("Hi, wie geht's?") }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(3)))
        let outcome = await p.finish()
        let uploads = server.requests("/audio/transcriptions")
        #expect(uploads.count == 1)
        #expect(uploads.first?.field("language") == nil)
        #expect(outcome.raw == "Hi, wie geht's?" && outcome.languages == ["de"])
        #expect(outcome.languageSources == ["auto"])
        #expect(outcome.timings.chunkCount == 1)
    }

    @Test func shortSpeechWithLongPauseCountsAsShort() async {
        // Gerätefund: „Hi, wie geht's“ plus Pause = 8,3 s Audio, aber kaum gesprochen.
        let server = MockServer { _, _ in Groq.transcription("Hi, wie geht's?") }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.silence(0.5) + Synth.speech(1.5) + Synth.silence(6.3)))
        let outcome = await p.finish()
        #expect(outcome.timings.audioSeconds > 8)
        #expect(server.requests("/audio/transcriptions").map { $0.field("language") } == [nil])
        #expect(outcome.languageSources == ["auto"])
    }

    @Test func longForeignPieceIsRedoneInThePrimaryLanguage() async throws {
        let server = MockServer { request, _ in
            request.field("language") == "de"
                ? Groq.transcription("Guten Morgen, wie geht's dir heute?", language: "German")
                : Groq.transcription("Gutn morgn, kak dela segodnya?", language: "Russian", logprob: -0.8)
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(12)))
        let outcome = await p.finish()
        let uploads = server.requests("/audio/transcriptions")
        #expect(uploads.count == 2)
        #expect(uploads[0].field("language") == nil)
        #expect(uploads[1].field("language") == "de")
        // Gleicher Prompt, gleiches Audio.
        #expect(uploads[1].field("prompt") == uploads[0].field("prompt"))
        #expect(outcome.raw == "Guten Morgen, wie geht's dir heute?")
        #expect(outcome.languages == ["de"] && outcome.languageSources == ["check-expected"])
        #expect(outcome.timings.chunkCount == 2)
        #expect(outcome.timings.uploadedBytes > 2 * 1000)
    }

    @Test func failedRedoKeepsTheFirstResult() async {
        let server = MockServer { request, _ in
            request.field("language") == "de" ? Groq.error(422)
                : Groq.transcription("Gutn morgn, kak dela segodnya?", language: "Russian", logprob: -0.8)
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(2)))
        let outcome = await p.finish()
        #expect(server.requests("/audio/transcriptions").count == 2)
        #expect(outcome.errorMessage == nil)
        #expect(outcome.raw == "Gutn morgn, kak dela segodnya?")
        #expect(outcome.languages == ["ru"] && outcome.languageSources == ["check-failed"])
    }

    @Test func longPieceInAnotherUserLanguageStays() async {
        let server = MockServer { _, _ in Groq.transcription("This is a longer English dictation.", language: "English") }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(12)))
        let outcome = await p.finish()
        let uploads = server.requests("/audio/transcriptions")
        #expect(uploads.count == 1 && uploads.first?.field("language") == nil)
        #expect(outcome.languages == ["en"] && outcome.languageSources == ["auto"])
    }

    @Test func shortRestFollowsTheLanguageOfThePreviousPiece() async throws {
        let server = MockServer { request, index in
            index == 0 ? Groq.transcription("This part is clearly English.", language: "English")
                : Groq.transcription("And the rest.", language: request.field("language") == "en" ? "English" : "German")
        }
        let p = pipeline(server, chunked: true)
        await feed(p, Synth.withFloor(Synth.speech(11) + Synth.silence(0.9) + Synth.speech(3)))
        let outcome = await p.finish()
        let uploads = server.requests("/audio/transcriptions")
        #expect(uploads.count == 3)
        #expect(uploads[0].field("language") == nil)
        #expect(uploads[1].field("language") == nil)
        #expect(uploads[2].field("language") == "en")
        #expect(outcome.raw == "This part is clearly English. And the rest.")
        #expect(outcome.languages == ["en"] && outcome.languageSources == ["auto", "check-expected"])
    }

    @Test func shortFrenchRemainsFrench() async {
        let server = MockServer { request, _ in
            request.field("language") == "de"
                ? Groq.transcription("Wir sehen uns heute Abend.", logprob: -0.39)
                : Groq.transcription("On se voit ce soir.", language: "French", logprob: -0.08)
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(1.6)))
        let outcome = await p.finish()
        #expect(server.requests("/audio/transcriptions").map { $0.field("language") } == [nil, "de"])
        #expect(outcome.raw == "On se voit ce soir.")
        #expect(outcome.languages == ["fr"])
    }

    @Test func confidenceIsDurationWeightedAndMissingFailsClosed() {
        #expect(LanguageGuard.confidence([.init(text: "a", start: 0, end: 1, avgLogprob: -0.125), .init(text: "b", start: 1, end: 4, avgLogprob: -0.625)]) == -0.5)
        #expect(LanguageGuard.confidence([.init(text: "a")]) == nil)
        #expect(LanguageGuard.expected(previous: "ar", primary: "de") == "ar")
        #expect(LanguageGuard.choose(detectedText: "  BONJOUR !", expectedText: "bonjour", detectedConfidence: nil, expectedConfidence: nil) == .expected)
    }

    @Test func reportLanguageUsesSpeechShare() {
        #expect(ConversationSummarizer.reportLanguage(["fr": 80, "de": 20], primary: "de") == "fr")
        #expect(ConversationSummarizer.reportLanguage(["fr": 79, "de": 21], primary: "de") == "de")
        #expect(ConversationSummarizer.reportLanguage(nil, primary: "en") == "en")
    }
}
