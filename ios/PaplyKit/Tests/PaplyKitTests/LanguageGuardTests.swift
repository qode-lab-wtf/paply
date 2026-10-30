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

    @Test func shortPiecesSendTheLanguage() {
        let users = ["de", "en"]
        func first(_ previous: String?, _ seconds: Double, fixed: String? = nil, primary: String? = "de") -> LanguageGuard.Request {
            LanguageGuard.firstRequest(fixed: fixed, primary: primary, previous: previous,
                                       userLanguages: users, spokenSeconds: seconds)
        }
        #expect(first(nil, 1.2) == .init(language: "de", source: .short))
        #expect(first(nil, LanguageGuard.shortSpeechSeconds) == .init(language: "de", source: .short))
        // Rest eines englischen Diktats bleibt englisch.
        #expect(first("en", 2) == .init(language: "en", source: .short))
        // Vorstück in fremder Sprache zählt nicht.
        #expect(first("ru", 2) == .init(language: "de", source: .short))
        #expect(first(nil, 5.1) == .init(language: nil, source: .auto))
        #expect(first("en", 8) == .init(language: nil, source: .auto))
        #expect(first(nil, 3, primary: nil) == .init(language: nil, source: .auto))
        // Feste Sprache: wie bisher, unabhängig von der Länge.
        #expect(first("en", 3, fixed: "fr") == .init(language: "fr", source: .fixed))
        #expect(first(nil, 30, fixed: "fr") == .init(language: "fr", source: .fixed))
    }

    @Test func onlyForeignLanguagesAreRedone() {
        let users = ["de-DE", "en"]
        #expect(LanguageGuard.redoLanguage(detected: "ru", primary: "de", userLanguages: users) == "de")
        #expect(LanguageGuard.redoLanguage(detected: "en", primary: "de", userLanguages: users) == nil)
        #expect(LanguageGuard.redoLanguage(detected: "de", primary: "de", userLanguages: users) == nil)
        #expect(LanguageGuard.redoLanguage(detected: nil, primary: "de", userLanguages: users) == nil)
        #expect(LanguageGuard.redoLanguage(detected: "ru", primary: nil, userLanguages: []) == nil)
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

    @Test func shortPieceIsSentOnceWithThePrimaryLanguage() async throws {
        let server = MockServer { _, _ in Groq.transcription("Hi, wie geht's?") }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(3)))
        let outcome = await p.finish()
        let uploads = server.requests("/audio/transcriptions")
        #expect(uploads.count == 1)
        #expect(uploads.first?.field("language") == "de")
        #expect(outcome.raw == "Hi, wie geht's?" && outcome.languages == ["de"])
        #expect(outcome.languageSources == ["short"])
        #expect(outcome.timings.chunkCount == 1)
    }

    @Test func chosenPrimaryLanguageIsUsedWhileListed() async {
        let server = MockServer { _, _ in Groq.transcription("Hi, how are you?", language: "English") }
        let p = pipeline(server, primary: "en")
        await feed(p, Synth.withFloor(Synth.speech(3)))
        _ = await p.finish()
        #expect(server.requests("/audio/transcriptions").first?.field("language") == "en")
        // Nicht mehr in der Liste: wieder die Standardregel (erste iPhone-Sprache bzw. erste Nutzersprache).
        let other = MockServer { _, _ in Groq.transcription("Hallo.") }
        let q = pipeline(other, primary: "fr")
        await feed(q, Synth.withFloor(Synth.speech(3)))
        _ = await q.finish()
        let fallback = LanguageGuard.primary(chosen: nil, userLanguages: ["de", "en"], device: Locale.preferredLanguages.first)
        #expect(other.requests("/audio/transcriptions").first?.field("language") == fallback)
    }

    @Test func shortSpeechWithLongPauseCountsAsShort() async {
        // Gerätefund: „Hi, wie geht's“ plus Pause = 8,3 s Audio, aber kaum gesprochen.
        let server = MockServer { _, _ in Groq.transcription("Hi, wie geht's?") }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.silence(0.5) + Synth.speech(1.5) + Synth.silence(6.3)))
        let outcome = await p.finish()
        #expect(outcome.timings.audioSeconds > 8)
        #expect(server.requests("/audio/transcriptions").map { $0.field("language") } == ["de"])
        #expect(outcome.languageSources == ["short"])
    }

    @Test func longForeignPieceIsRedoneInThePrimaryLanguage() async throws {
        let server = MockServer { request, _ in
            request.field("language") == "de"
                ? Groq.transcription("Guten Morgen, wie geht's dir heute?", language: "German")
                : Groq.transcription("Gutn morgn, kak dela segodnya?", language: "Russian")
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
        #expect(outcome.languages == ["de"] && outcome.languageSources == ["redo"])
        #expect(outcome.timings.chunkCount == 2)
        #expect(outcome.timings.uploadedBytes > 2 * 1000)
    }

    @Test func failedRedoKeepsTheFirstResult() async {
        let server = MockServer { request, _ in
            request.field("language") == "de" ? Groq.error(422)
                : Groq.transcription("Gutn morgn, kak dela segodnya?", language: "Russian")
        }
        let p = pipeline(server)
        await feed(p, Synth.withFloor(Synth.speech(12)))
        let outcome = await p.finish()
        #expect(server.requests("/audio/transcriptions").count == 2)
        #expect(outcome.errorMessage == nil)
        #expect(outcome.raw == "Gutn morgn, kak dela segodnya?")
        #expect(outcome.languages == ["ru"] && outcome.languageSources == ["redo-failed"])
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
        #expect(uploads.count == 2)
        #expect(uploads[0].field("language") == nil)
        #expect(uploads[1].field("language") == "en")
        #expect(outcome.raw == "This part is clearly English. And the rest.")
        #expect(outcome.languages == ["en"] && outcome.languageSources == ["auto", "short"])
    }

    @Test func fixedLanguageBypassesTheGuard() async {
        let server = MockServer { _, _ in Groq.transcription("Privet, kak dela segodnya?", language: "Russian") }
        let p = pipeline(server, fixed: "ru")
        await feed(p, Synth.withFloor(Synth.speech(12)))
        let outcome = await p.finish()
        let uploads = server.requests("/audio/transcriptions")
        #expect(uploads.count == 1 && uploads.first?.field("language") == "ru")
        #expect(outcome.languages == ["ru"] && outcome.languageSources == ["fixed"])
    }
}
