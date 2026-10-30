package com.paply.core

import kotlin.math.*
import org.junit.Test

class SilenceFilterTests {
    private val silence = VoiceActivityMeta(4000.0, 4000.0, 0.0, -90.0, -90.0, 40.0)
    private val speech
        get() = silence.copy(speechMs = 400.0, peakDbfs = -35.0)

    private fun segment(text: String, noSpeech: Double? = 0.01, logprob: Double? = -0.1) =
        WhisperSegment(text, avgLogprob = logprob, noSpeechProb = noSpeech)

    private fun filter(
        text: String?,
        segments: List<WhisperSegment>? = null,
        meta: VoiceActivityMeta? = null,
        bypass: Boolean = false,
    ) = SilenceFilter.filter(text, segments, meta, bypass)

    private fun metaForLevels(levels: List<Double>): VoiceActivityMeta {
        val v = VoiceActivityDetector()
        for (level in levels) v.appendFrame(max(-120.0, level).toFloat(), 0f)
        return v.meta().copy(voicedMs = null)
    }

    private val thanks = listOf(segment("Vielen Dank.", 0.0, -0.28))

    @Test
    fun skipsStationaryRoomNoise() {
        val m = metaForLevels((0 until 125).map { -50.0 + it % 5 - 2 })
        expect(abs(m.floorDbfs + 52) < 0.01)
        expect(abs(m.peakDbfs + 48) < 0.01)
        expect(m.speechMs == 0.0)
        expect(SilenceFilter.shouldSkipTranscription(m))
    }

    @Test
    fun keepsSyllablesAboveRoomNoise() {
        val m = metaForLevels((0 until 110).map { -50.0 + it % 5 - 2 } + List(15) { -25.0 })
        expect(m.speechMs >= 400)
        expect(!SilenceFilter.shouldSkipTranscription(m))
        expect(filter("Vielen Dank.", thanks, m).text == "Vielen Dank.")
    }

    @Test
    fun transcribesKeyboardClickButDropsThanksHallucination() {
        val m = metaForLevels(List(123) { -55.0 } + List(2) { -30.0 })
        expect(m.speechMs == 60.0 && m.peakDbfs - m.floorDbfs > 10)
        expect(!SilenceFilter.shouldSkipTranscription(m))
        expect(filter("Vielen Dank.", thanks, m).text == "")
    }

    @Test
    fun keepsContinuousSpeech() {
        for (phase in listOf(0, 5, 10)) {
            val m = metaForLevels((0 until 125).map { -35.0 + (it + phase) % 21 })
            expect(m.speechMs >= 250)
            expect(!SilenceFilter.shouldSkipTranscription(m))
            expect(filter("Vielen Dank.", thanks, m).text == "Vielen Dank.")
            val text = "Das ist ein zusammenhängendes Diktat ohne Pausen."
            expect(filter(text, null, m).text == text)
        }
    }

    @Test
    fun skipsDigitalSilence() {
        val m = metaForLevels(List(125) { Double.NEGATIVE_INFINITY })
        expect(m.floorDbfs == -120.0 && m.peakDbfs == -120.0 && m.speechMs == 0.0)
        expect(SilenceFilter.shouldSkipTranscription(m))
    }

    @Test
    fun keepsSpeechInLoudCafe() {
        val m =
            metaForLevels(
                (0 until 110).map { -40.0 + it % 9 - 4 } +
                    (0 until 15).map { -28.0 + (it % 6) * 2 },
            )
        expect(m.speechMs >= 300)
        expect(!SilenceFilter.shouldSkipTranscription(m))
        expect(filter("Vielen Dank.", thanks, m).text == "Vielen Dank.")
    }

    @Test
    fun skipsOnlyReliableStationarySignals() {
        expect(SilenceFilter.shouldSkipTranscription(silence))
        expect(!SilenceFilter.shouldSkipTranscription(speech))
        expect(
            SilenceFilter.shouldSkipTranscription(silence.copy(speechMs = 79.0, peakDbfs = -85.0)),
        )
        expect(
            !SilenceFilter.shouldSkipTranscription(silence.copy(speechMs = 80.0, peakDbfs = -85.0)),
        )
        expect(
            !SilenceFilter.shouldSkipTranscription(silence.copy(speechMs = 40.0, peakDbfs = -35.0)),
        )
        expect(!SilenceFilter.shouldSkipTranscription(silence.copy(peakDbfs = -80.0)))
        expect(
            SilenceFilter.shouldSkipTranscription(
                silence.copy(peakDbfs = -120.0, floorDbfs = -120.0),
            ),
        )
    }

    @Test
    fun absoluteSpeechDurationIsNotDiluted() {
        val m =
            silence.copy(
                durationMs = 60000.0,
                measuredMs = 60000.0,
                speechMs = 400.0,
                peakDbfs = -64.0,
            )
        expect(!SilenceFilter.shouldSkipTranscription(m))
        expect(filter("Vielen Dank.", null, m).text == "Vielen Dank.")
    }

    @Test
    fun unreliableMeasurementsNeverDropAnything() {
        for (m in
            listOf(
                null,
                silence.copy(durationMs = 300.0, measuredMs = 300.0),
                silence.copy(measuredMs = 3000.0),
                silence.copy(maxGapMs = 120.0),
                silence.copy(speechMs = -1.0),
                silence.copy(measuredMs = 5000.0),
                silence.copy(peakDbfs = Double.NaN),
                silence.copy(durationMs = Double.POSITIVE_INFINITY),
                silence.copy(floorDbfs = -121.0),
                silence.copy(floorDbfs = -80.0),
            )) {
            expect(!SilenceFilter.shouldSkipTranscription(m))
            expect(filter("Vielen Dank.", null, m).text == "Vielen Dank.")
        }
    }

    @Test
    fun keepsIntentionalThanksWithActivity() {
        expect(filter("Vielen Dank.", null, speech).text == "Vielen Dank.")
        expect(
            filter("Vielen Dank.", listOf(segment("Vielen Dank.", 0.99)), speech).text ==
                "Vielen Dank.",
        )
    }

    @Test
    fun dropsKnownPhrasesWithMeasuredSilence() {
        for (text in
            listOf(
                "Vielen Dank.",
                "DANKE!!!",
                "Bis zum nächsten Mal.",
                "Tschüss.",
                "Thank you.",
                "Thanks for watching!",
                "  Vielen  Dank!  ",
                "Merci.",
                "Gracias.",
                "Grazie mille.",
                "Obrigado.",
                "Bedankt.",
                "Teşekkürler.",
                "Dziękuję.",
                "ご視聴ありがとうございました",
                "Спасибо.",
                "you",
            )) {
            val r = filter(text, null, silence)
            expect(r.text == "" && r.reason == "known-silence-phrase")
            expect(filter(text).text == text.trimmed())
        }
    }

    @Test
    fun dropsArtifactsEvenWithoutMetadata() {
        for (text in
            listOf(
                "Untertitel im Auftrag des ZDF, 2017",
                "Untertitelung des ZDF für funk",
                "Untertitel im Auftrag des ZDF für funk, 2024",
                "Amara.org",
                "Untertitel von der Amara.org-Community",
                "Copyright",
                "Copyright WDR 2023",
                "Sous-titres réalisés par la communauté d'Amara.org",
                "Subtítulos realizados por la comunidad de Amara.org",
                "Sottotitoli creati dalla comunità Amara.org",
                "Субтитры сделал DimaTorzok",
                "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目",
            )) {
            expect(filter(text).reason == "known-artifact-phrase")
            expect(filter(text).text == "")
            expect(filter(text, null, speech).text == "")
        }
    }

    @Test
    fun keepsMentionsOfSubtitlesAmaraCopyright() {
        for (text in
            listOf(
                "Bitte Untertitel aktivieren.",
                "Öffne Amara.org.",
                "Bitte das Copyright im Dokument ergänzen.",
            )) expect(filter(text).text == text)
    }

    @Test
    fun ambiguousPhrasesUse120msLimitOnlyWithQuietFloor() {
        expect(filter("Vielen Dank.", thanks, speech.copy(speechMs = 119.0)).text == "")
        expect(filter("Vielen Dank.", thanks, speech.copy(speechMs = 120.0)).text == "Vielen Dank.")
        expect(filter("Vielen Dank.", thanks).text == "Vielen Dank.")
        expect(
            filter("Vielen Dank.", thanks, speech.copy(speechMs = 100.0, measuredMs = 2000.0))
                .text == "Vielen Dank.",
        )
    }

    @Test
    fun separatesGroqSilenceAndSpeechOnlyByActivity() {
        val digital = listOf(segment(" Vielen Dank.", 0.0, -0.28))
        val spoken = listOf(segment(" Vielen Dank.", 0.0, -0.224))
        expect(filter(" Vielen Dank.", digital, silence).text == "")
        expect(filter(" Vielen Dank.", spoken, speech).text == "Vielen Dank.")
        expect(filter(" Vielen Dank.", digital).text == "Vielen Dank.")
        val t = "Bitte schick mir die Unterlagen, vielen Dank."
        expect(filter(t, listOf(segment(t, 0.0, -0.059)), speech).text == t)
    }

    @Test
    fun noiseAnswersAreTrivial() {
        for (p in listOf(-0.715, -0.556)) expect(
            filter(" ...", listOf(segment(" ...", 0.0, p))).text == "",
        )
    }

    @Test
    fun keepsNormalDictationIncludingThanks() {
        val t = "Bitte schick mir den Bericht.\nVielen Dank."
        expect(
            filter(
                    t,
                    listOf(segment("Bitte schick mir den Bericht."), segment("Vielen Dank.")),
                    silence,
                )
                .text == t,
        )
        expect(
            filter("Das ist ein normales Diktat.", null, silence).text ==
                "Das ist ein normales Diktat.",
        )
    }

    @Test
    fun dropsOnlySegmentsWithBothSilenceSignals() {
        val r =
            filter(
                "Bitte morgen antworten. Vielen Dank.",
                listOf(segment("Bitte morgen antworten."), segment("Vielen Dank.", 0.95, -1.5)),
            )
        expect(r.text == "Bitte morgen antworten." && r.droppedSegments == 1 && r.reason == null)
    }

    @Test
    fun dropsCompleteSilenceBySegments() {
        val r = filter("Erfundener Text", listOf(segment("Erfundener Text", 0.8, -1.2)))
        expect(r.text == "" && r.droppedSegments == 1 && r.reason == "no-speech-segments")
    }

    @Test
    fun keepsSegmentsWithInsufficientSignals() {
        val text = "Hallo, hier ist mein Diktat."
        for ((p, l) in
            listOf(
                0.6 to -1.5,
                0.9 to -1.0,
                0.8 to -0.1,
                0.1 to -2.0,
                null to -2.0,
                0.99 to null,
                1.1 to -2.0,
            )) expect(filter(text, listOf(segment(text, p, l))).text == text)
    }

    @Test
    fun keepsAmbiguousPhrasesWithoutMetadata() {
        for (p in listOf(0.99, 0.7)) expect(
            filter("Vielen Dank.", listOf(segment("Vielen Dank.", p))).text == "Vielen Dank.",
        )
    }

    @Test
    fun removedSegmentDoesNotTaintSpokenThanks() {
        expect(
            filter(
                    "Amara.org Vielen Dank.",
                    listOf(segment("Amara.org", 0.99, -2.0), segment("Vielen Dank.", 0.01)),
                )
                .text == "Vielen Dank.",
        )
    }

    @Test
    fun fallsBackToTextWithUnusableSegments() {
        for (s in
            listOf(
                null,
                emptyList(),
                listOf(WhisperSegment(null, avgLogprob = -2.0, noSpeechProb = 0.99)),
            )) expect(filter("Vielen Dank.", s).text == "Vielen Dank.")
    }

    @Test
    fun usesSegmentsWhenTextIsMissing() {
        expect(
            filter(null, listOf(segment("Bitte morgen antworten."))).text ==
                "Bitte morgen antworten.",
        )
    }

    @Test
    fun trivialResults() {
        for (text in listOf("", "  ", "...", "?")) expect(filter(text).text == "")
    }

    @Test
    fun validation() {
        expect(SilenceFilter.validate(silence) == silence)
        expect(SilenceFilter.validate(silence.copy(speechMs = 5000.0)) == null)
    }

    @Test
    fun reviewR1Boundaries() {
        data class Case(
            val text: String,
            val floor: Double,
            val peak: Double,
            val speech: Double,
            val expected: String,
        )
        for ((text, floor, peak, speechMs, expected) in
            listOf(
                Case("Danke.", -60.0, -25.0, 200.0, "Danke."),
                Case("Tschüss.", -60.0, -25.0, 240.0, "Tschüss."),
                Case("Vielen Dank.", -35.0, -20.0, 40.0, "Vielen Dank."),
                Case("Vielen Dank.", -70.0, -65.0, 0.0, ""),
                Case("Vielen Dank.", -55.0, -30.0, 80.0, ""),
                Case("Vielen Dank.", -50.0, -38.0, 119.0, ""),
                Case("Vielen Dank.", -50.0, -38.0, 120.0, "Vielen Dank."),
                Case("Vielen Dank.", -45.0, -30.0, 40.0, "Vielen Dank."),
                Case("Vielen Dank.", -35.0, -24.0, 400.0, ""),
                Case("Vielen Dank.", -35.0, -23.0, 40.0, "Vielen Dank."),
            )) {
            expect(
                filter(
                        text,
                        null,
                        silence.copy(
                            durationMs = 600.0,
                            measuredMs = 600.0,
                            floorDbfs = floor,
                            peakDbfs = peak,
                            speechMs = speechMs,
                        ),
                    )
                    .text == expected,
            )
        }
    }

    @Test
    fun realDynamicIsNotSkipped() {
        for (d in listOf(6.0, 7.0, 8.0, 9.0)) expect(
            !SilenceFilter.shouldSkipTranscription(
                silence.copy(floorDbfs = -35.0, peakDbfs = -35 + d, speechMs = 40.0),
            ),
        )
    }

    @Test
    fun shortPushToTalkWithoutReliableDuration() {
        expect(
            filter(
                    "Danke.",
                    null,
                    silence.copy(
                        durationMs = 300.0,
                        measuredMs = 300.0,
                        speechMs = 200.0,
                        peakDbfs = -20.0,
                    ),
                )
                .text == "Danke.",
        )
    }

    @Test
    fun bypassIgnoresPhraseAndSegmentSilenceButNotArtifacts() {
        val r = filter("Danke.", listOf(segment("Danke.", 0.99, -2.0)), silence, true)
        expect(r.text == "Danke." && r.droppedSegments == 0 && r.reason == null)
        for (text in
            listOf(
                "Amara.org",
                "Untertitel im Auftrag des ZDF, 2017",
                "Copyright WDR 2023",
                "...",
                "?",
            )) expect(filter(text, null, silence, true).text == "")
    }

    @Test
    fun thanksWithoutAnyVoicingIsSilence() {
        val breathing = speech.copy(speechMs = 600.0, peakDbfs = -30.0, voicedMs = 0.0)
        expect(filter("Vielen Dank.", null, breathing).text == "")
        expect(
            filter("Vielen Dank.", null, breathing.copy(voicedMs = 240.0)).text == "Vielen Dank.",
        )
        expect(
            filter("Bitte ruf mich morgen an.", null, breathing).text ==
                "Bitte ruf mich morgen an.",
        )
    }
}
