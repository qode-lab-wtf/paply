import Foundation
import Testing
@testable import PaplyKit

private let silence = VoiceActivityMeta(durationMs: 4000, measuredMs: 4000, speechMs: 0, peakDbfs: -90, floorDbfs: -90, maxGapMs: 40)
private var speech: VoiceActivityMeta { var m = silence; m.speechMs = 400; m.peakDbfs = -35; return m }
private func segment(_ text: String, _ noSpeech: Double? = 0.01, _ logprob: Double? = -0.1) -> WhisperSegment {
    WhisperSegment(text: text, avgLogprob: logprob, noSpeechProb: noSpeech)
}
private func filter(_ text: String?, _ segments: [WhisperSegment]? = nil, _ meta: VoiceActivityMeta? = nil, bypass: Bool = false) -> SilenceFilter.Result {
    SilenceFilter.filter(text: text, segments: segments, meta: meta, bypassLocalFilters: bypass)
}
private func with(_ meta: VoiceActivityMeta, _ change: (inout VoiceActivityMeta) -> Void) -> VoiceActivityMeta {
    var copy = meta
    change(&copy)
    return copy
}

/// Fenster mit gegebenen Pegeln (30 ms, aperiodisch) – entspricht Desktop `metaForLevels`.
private func metaForLevels(_ levels: [Double]) -> VoiceActivityMeta {
    var vad = VoiceActivityDetector()
    for level in levels { vad.appendFrame(dbfs: Float(max(-120, level)), periodicity: 0) }
    var meta = vad.meta()
    meta.voicedMs = nil // Desktop-Port: ohne Periodizitätsmessung
    return meta
}

/// Port von electron-menubar/audio/silence-filter.test.js (Fenster hier 30 statt 40 ms).
@Suite struct RelativeVoiceActivityTests {
    let thanks = (text: "Vielen Dank.", segments: [segment("Vielen Dank.", 0, -0.28)])

    @Test func skipsStationaryRoomNoise() {
        let meta = metaForLevels((0..<125).map { -50 + Double($0 % 5) - 2 })
        #expect(abs(meta.floorDbfs - -52) < 0.01)
        #expect(abs(meta.peakDbfs - -48) < 0.01)
        #expect(meta.speechMs == 0)
        #expect(SilenceFilter.shouldSkipTranscription(meta))
    }

    @Test func keepsSyllablesAboveRoomNoise() {
        let meta = metaForLevels((0..<110).map { -50 + Double($0 % 5) - 2 } + Array(repeating: -25, count: 15))
        #expect(meta.speechMs >= 400)
        #expect(!SilenceFilter.shouldSkipTranscription(meta))
        #expect(filter(thanks.text, thanks.segments, meta).text == "Vielen Dank.")
    }

    @Test func transcribesKeyboardClickButDropsThanksHallucination() {
        let meta = metaForLevels(Array(repeating: -55, count: 123) + Array(repeating: -30, count: 2))
        #expect(meta.speechMs == 60)
        #expect(meta.peakDbfs - meta.floorDbfs > 10)
        #expect(!SilenceFilter.shouldSkipTranscription(meta))
        #expect(filter(thanks.text, thanks.segments, meta).text == "")
    }

    @Test(arguments: [0, 5, 10])
    func keepsContinuousSpeech(phase: Int) {
        let meta = metaForLevels((0..<125).map { -35 + Double(($0 + phase) % 21) })
        #expect(meta.speechMs >= 250)
        #expect(!SilenceFilter.shouldSkipTranscription(meta))
        #expect(filter(thanks.text, thanks.segments, meta).text == "Vielen Dank.")
        #expect(filter("Das ist ein zusammenhängendes Diktat ohne Pausen.", nil, meta).text == "Das ist ein zusammenhängendes Diktat ohne Pausen.")
    }

    @Test func skipsDigitalSilence() {
        let meta = metaForLevels(Array(repeating: -.infinity, count: 125))
        #expect(meta.floorDbfs == -120 && meta.peakDbfs == -120 && meta.speechMs == 0)
        #expect(SilenceFilter.shouldSkipTranscription(meta))
    }

    @Test func keepsSpeechInLoudCafe() {
        let meta = metaForLevels((0..<110).map { -40 + Double($0 % 9) - 4 } + (0..<15).map { -28 + Double($0 % 6) * 2 })
        #expect(meta.speechMs >= 300) // Desktop: ≥ 400 bei 40-ms-Fenstern; hier 30 ms je Fenster
        #expect(!SilenceFilter.shouldSkipTranscription(meta))
        #expect(filter(thanks.text, thanks.segments, meta).text == "Vielen Dank.")
    }
}

@Suite struct SilenceFilterTests {
    @Test func skipsOnlyReliableStationarySignals() {
        #expect(SilenceFilter.shouldSkipTranscription(silence))
        #expect(!SilenceFilter.shouldSkipTranscription(speech))
        #expect(SilenceFilter.shouldSkipTranscription(with(silence) { $0.speechMs = 79; $0.peakDbfs = -85 }))
        #expect(!SilenceFilter.shouldSkipTranscription(with(silence) { $0.speechMs = 80; $0.peakDbfs = -85 }))
        #expect(!SilenceFilter.shouldSkipTranscription(with(silence) { $0.speechMs = 40; $0.peakDbfs = -35 }))
        #expect(!SilenceFilter.shouldSkipTranscription(with(silence) { $0.peakDbfs = -80 }))
        #expect(SilenceFilter.shouldSkipTranscription(with(silence) { $0.peakDbfs = -120; $0.floorDbfs = -120 }))
    }

    @Test func absoluteSpeechDurationIsNotDiluted() {
        let meta = with(silence) { $0.durationMs = 60000; $0.measuredMs = 60000; $0.speechMs = 400; $0.peakDbfs = -64 }
        #expect(!SilenceFilter.shouldSkipTranscription(meta))
        #expect(filter("Vielen Dank.", nil, meta).text == "Vielen Dank.")
    }

    @Test(arguments: [
        nil, with(silence) { $0.durationMs = 300; $0.measuredMs = 300 },
        with(silence) { $0.measuredMs = 3000 }, with(silence) { $0.maxGapMs = 120 },
        with(silence) { $0.speechMs = -1 }, with(silence) { $0.measuredMs = 5000 },
        with(silence) { $0.peakDbfs = .nan }, with(silence) { $0.durationMs = .infinity },
        with(silence) { $0.floorDbfs = -121 }, with(silence) { $0.floorDbfs = -80 },
    ] as [VoiceActivityMeta?])
    func unreliableMeasurementsNeverDropAnything(meta: VoiceActivityMeta?) {
        #expect(!SilenceFilter.shouldSkipTranscription(meta))
        #expect(filter("Vielen Dank.", nil, meta).text == "Vielen Dank.")
    }

    @Test func keepsIntentionalThanksWithActivity() {
        #expect(filter("Vielen Dank.", nil, speech).text == "Vielen Dank.")
        #expect(filter("Vielen Dank.", [segment("Vielen Dank.", 0.99)], speech).text == "Vielen Dank.")
    }

    @Test(arguments: ["Vielen Dank.", "DANKE!!!", "Bis zum nächsten Mal.", "Tschüss.", "Thank you.",
                      "Thanks for watching!", "  Vielen  Dank!  ",
                      // Mehrsprachige Ergänzungen
                      "Merci.", "Gracias.", "Grazie mille.", "Obrigado.", "Bedankt.", "Teşekkürler.",
                      "Dziękuję.", "ご視聴ありがとうございました", "Спасибо.", "you"])
    func dropsKnownPhrasesWithMeasuredSilence(text: String) {
        let result = filter(text, nil, silence)
        #expect(result.text == "" && result.reason == "known-silence-phrase")
        #expect(filter(text).text == text.trimmed)
    }

    @Test(arguments: ["Untertitel im Auftrag des ZDF, 2017", "Untertitelung des ZDF für funk",
                      "Untertitel im Auftrag des ZDF für funk, 2024", "Amara.org",
                      "Untertitel von der Amara.org-Community", "Copyright", "Copyright WDR 2023",
                      "Sous-titres réalisés par la communauté d'Amara.org",
                      "Subtítulos realizados por la comunidad de Amara.org", "Sottotitoli creati dalla comunità Amara.org",
                      "Субтитры сделал DimaTorzok", "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目"])
    func dropsArtifactsEvenWithoutMetadata(text: String) {
        #expect(filter(text).reason == "known-artifact-phrase")
        #expect(filter(text).text == "")
        #expect(filter(text, nil, speech).text == "")
    }

    @Test func keepsMentionsOfSubtitlesAmaraCopyright() {
        for text in ["Bitte Untertitel aktivieren.", "Öffne Amara.org.", "Bitte das Copyright im Dokument ergänzen."] {
            #expect(filter(text).text == text)
        }
    }

    @Test func ambiguousPhrasesUse120msLimitOnlyWithQuietFloor() {
        let segments = [segment("Vielen Dank.", 0, -0.28)]
        #expect(filter("Vielen Dank.", segments, with(speech) { $0.speechMs = 119 }).text == "")
        #expect(filter("Vielen Dank.", segments, with(speech) { $0.speechMs = 120 }).text == "Vielen Dank.")
        #expect(filter("Vielen Dank.", segments).text == "Vielen Dank.")
        #expect(filter("Vielen Dank.", segments, with(speech) { $0.speechMs = 100; $0.measuredMs = 2000 }).text == "Vielen Dank.")
    }

    @Test func separatesGroqSilenceAndSpeechOnlyByActivity() {
        let digitalSilence = [segment(" Vielen Dank.", 0, -0.28)]
        let spokenThanks = [segment(" Vielen Dank.", 0, -0.224)]
        #expect(filter(" Vielen Dank.", digitalSilence, silence).text == "")
        #expect(filter(" Vielen Dank.", spokenThanks, speech).text == "Vielen Dank.")
        #expect(filter(" Vielen Dank.", digitalSilence).text == "Vielen Dank.")
        let text = "Bitte schick mir die Unterlagen, vielen Dank."
        #expect(filter(text, [segment(text, 0, -0.059)], speech).text == text)
    }

    @Test(arguments: [-0.715, -0.556])
    func noiseAnswersAreTrivial(logprob: Double) {
        #expect(filter(" ...", [segment(" ...", 0, logprob)]).text == "")
    }

    @Test func keepsNormalDictationIncludingThanks() {
        let text = "Bitte schick mir den Bericht.\nVielen Dank."
        #expect(filter(text, [segment("Bitte schick mir den Bericht."), segment("Vielen Dank.")], silence).text == text)
        #expect(filter("Das ist ein normales Diktat.", nil, silence).text == "Das ist ein normales Diktat.")
    }

    @Test func dropsOnlySegmentsWithBothSilenceSignals() {
        let result = filter("Bitte morgen antworten. Vielen Dank.", [segment("Bitte morgen antworten."), segment("Vielen Dank.", 0.95, -1.5)])
        #expect(result.text == "Bitte morgen antworten." && result.droppedSegments == 1 && result.reason == nil)
    }

    @Test func dropsCompleteSilenceBySegments() {
        let result = filter("Erfundener Text", [segment("Erfundener Text", 0.8, -1.2)])
        #expect(result.text == "" && result.droppedSegments == 1 && result.reason == "no-speech-segments")
    }

    @Test(arguments: [(0.6, -1.5), (0.9, -1.0), (0.8, -0.1), (0.1, -2.0), (nil, -2.0), (0.99, nil), (1.1, -2.0)] as [(Double?, Double?)])
    func keepsSegmentsWithInsufficientSignals(probability: Double?, logprob: Double?) {
        let text = "Hallo, hier ist mein Diktat."
        #expect(filter(text, [WhisperSegment(text: text, avgLogprob: logprob, noSpeechProb: probability)]).text == text)
    }

    @Test func keepsAmbiguousPhrasesWithoutMetadata() {
        #expect(filter("Vielen Dank.", [segment("Vielen Dank.", 0.99)]).text == "Vielen Dank.")
        #expect(filter("Vielen Dank.", [segment("Vielen Dank.", 0.7)]).text == "Vielen Dank.")
    }

    @Test func removedSegmentDoesNotTaintSpokenThanks() {
        #expect(filter("Amara.org Vielen Dank.", [segment("Amara.org", 0.99, -2), segment("Vielen Dank.", 0.01)]).text == "Vielen Dank.")
    }

    @Test(arguments: [nil, [], [WhisperSegment(text: nil, avgLogprob: -2, noSpeechProb: 0.99)]] as [[WhisperSegment]?])
    func fallsBackToTextWithUnusableSegments(segments: [WhisperSegment]?) {
        #expect(filter("Vielen Dank.", segments).text == "Vielen Dank.")
    }

    @Test func usesSegmentsWhenTextIsMissing() {
        #expect(filter(nil, [segment("Bitte morgen antworten.")]).text == "Bitte morgen antworten.")
    }

    @Test func trivialResults() {
        for text in ["", "  ", "...", "?"] { #expect(filter(text).text == "") }
    }

    @Test func validation() {
        #expect(SilenceFilter.validate(silence) == silence)
        #expect(SilenceFilter.validate(with(silence) { $0.speechMs = 5000 }) == nil)
    }

    @Test(arguments: [
        ("Danke.", -60.0, -25.0, 200.0, "Danke."), ("Tschüss.", -60, -25, 240, "Tschüss."),
        ("Vielen Dank.", -35, -20, 40, "Vielen Dank."), ("Vielen Dank.", -70, -65, 0, ""),
        ("Vielen Dank.", -55, -30, 80, ""), ("Vielen Dank.", -50, -38, 119, ""),
        ("Vielen Dank.", -50, -38, 120, "Vielen Dank."), ("Vielen Dank.", -45, -30, 40, "Vielen Dank."),
        ("Vielen Dank.", -35, -24, 400, ""), ("Vielen Dank.", -35, -23, 40, "Vielen Dank."),
    ])
    func reviewR1Boundaries(text: String, floor: Double, peak: Double, speechMs: Double, expected: String) {
        let meta = with(silence) { $0.durationMs = 600; $0.measuredMs = 600; $0.floorDbfs = floor; $0.peakDbfs = peak; $0.speechMs = speechMs }
        #expect(filter(text, nil, meta).text == expected)
    }

    @Test(arguments: [6.0, 7, 8, 9])
    func realDynamicIsNotSkipped(dynamic: Double) {
        #expect(!SilenceFilter.shouldSkipTranscription(with(silence) { $0.floorDbfs = -35; $0.peakDbfs = -35 + dynamic; $0.speechMs = 40 }))
    }

    @Test func shortPushToTalkWithoutReliableDuration() {
        #expect(filter("Danke.", nil, with(silence) { $0.durationMs = 300; $0.measuredMs = 300; $0.speechMs = 200; $0.peakDbfs = -20 }).text == "Danke.")
    }

    @Test func bypassIgnoresPhraseAndSegmentSilenceButNotArtifacts() {
        let result = filter("Danke.", [segment("Danke.", 0.99, -2)], silence, bypass: true)
        #expect(result.text == "Danke." && result.droppedSegments == 0 && result.reason == nil)
        for text in ["Amara.org", "Untertitel im Auftrag des ZDF, 2017", "Copyright WDR 2023", "...", "?"] {
            #expect(filter(text, nil, silence, bypass: true).text == "")
        }
    }

    // iOS-Ergänzung: Periodizität
    @Test func thanksWithoutAnyVoicingIsSilence() {
        let breathing = with(speech) { $0.speechMs = 600; $0.peakDbfs = -30; $0.voicedMs = 0 }
        #expect(filter("Vielen Dank.", nil, breathing).text == "")
        let spoken = with(breathing) { $0.voicedMs = 240 }
        #expect(filter("Vielen Dank.", nil, spoken).text == "Vielen Dank.")
        // Normale Diktate bleiben auch ohne Periodizität unangetastet.
        #expect(filter("Bitte ruf mich morgen an.", nil, breathing).text == "Bitte ruf mich morgen an.")
    }
}
