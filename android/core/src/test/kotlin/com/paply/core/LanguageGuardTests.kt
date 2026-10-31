package com.paply.core

import kotlinx.coroutines.runBlocking
import org.junit.Test

class LanguageGuardTests {
    @Test fun aliasesAreSentAsWhisperCodes() = runBlocking {
        for ((device, whisper) in listOf("nb" to "no", "fil-PH" to "tl", "iw" to "he", "in" to "id", "ji" to "yi", "jw" to "jv")) {
            MockServer { _, _ -> Groq.transcription("A spoken sentence.", "English") }.use { server ->
                val p = pipeline(server, languages = listOf(device), primary = device)
                feed(p, Synth.withFloor(Synth.speech(2.0)))
                p.finish()
                expect(server.requests.map { it.field("language") } == listOf(null, whisper))
                p.close()
            }
        }
    }

    @Test fun emptyMiddlePieceKeepsLastTextLanguage() = runBlocking {
        MockServer { request, i ->
            when (i) {
                0 -> Groq.transcription("This is clearly English.", "English")
                1 -> Groq.transcription("", "German")
                else -> Groq.transcription("And another sentence.", if (request.field("language") == "en") "English" else "German")
            }
        }.use { server ->
            val p = pipeline(server, chunked = true)
            feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9) + Synth.speech(11.0) + Synth.silence(0.9) + Synth.speech(2.0)))
            val result = p.finish()
            expect(server.requests.last().field("language") == "en")
            expect(result.lastPieceLanguage == "en")
            p.close()
        }
    }

    @Test fun emptyLastPieceDoesNotExportItsLanguage() = runBlocking {
        MockServer { _, i -> if (i == 0) Groq.transcription("This is clearly English.", "English") else Groq.transcription("", "German") }.use { server ->
            val p = pipeline(server, chunked = true)
            feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9) + Synth.speech(11.0)))
            expect(p.finish().lastPieceLanguage == "en")
            p.close()
        }
    }

    @Test fun firstFailureReturnsWithoutCountercheck() = runBlocking {
        MockServer { _, _ -> Groq.error(401) }.use { server ->
            val p = pipeline(server)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            expect(p.finish().error != null)
            expect(server.requests.size == 1)
            p.close()
        }
    }

    @Test fun countercheckHasBoundedTimeAndCountsBothUploads() = runBlocking {
        expect(LanguageGuard.checkTimeoutMs(1200.0) == 7400L)
        expect(LanguageGuard.checkTimeoutMs(40000.0) == 60000L)
        MockServer { _, i ->
            Groq.transcription("On se voit ce soir.", "French").apply {
                if (i > 0) setBodyDelay(30, java.util.concurrent.TimeUnit.SECONDS)
            }
        }.use { server ->
            val p = pipeline(server)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            val started = System.nanoTime()
            val result = kotlinx.coroutines.withTimeout(12000) { p.finish() }
            expect((System.nanoTime() - started) / 1e9 < 12)
            expect(result.raw == "On se voit ce soir.")
            expect(result.languageSources == listOf("check-failed"))
            org.junit.Assert.assertEquals(4.0, result.timings.sentAudioSeconds, 0.001)
            p.close()
        }
    }

    private fun pipeline(
        s: MockServer,
        chunked: Boolean = false,
        languages: List<String> = listOf("de", "en"),
        primary: String? = "de",
        fixed: String? = null,
    ) =
        s.pipeline(
            PaplySettings(
                chunkedUpload = chunked,
                spokenLanguages = languages,
                primaryLanguage = primary,
                language = fixed,
            ),
            PipelineOptions(polish = false),
        )

    @Test
    fun primaryIsChosenElseFirstDeviceLanguageElseFirst() {
        val users = listOf("en", "de")
        expect(LanguageGuard.primary(null, users, "de-DE") == "de")
        expect(LanguageGuard.primary("en", users, "de-DE") == "en")
        expect(LanguageGuard.primary("fr", users, "de-DE") == "de")
        expect(LanguageGuard.primary(null, listOf("de-DE", "en"), "ja-JP") == "de")
        expect(LanguageGuard.primary(null, listOf("de-DE", "en"), null) == "de")
        expect(LanguageGuard.primary("en", emptyList(), "de") == null)
    }

    @Test
    fun previousLanguageIsNotRestrictedToOwnLanguages() {
        expect(LanguageGuard.expected("ar", "de") == "ar")
        expect(LanguageGuard.expected(null, "de") == "de")
    }

    @Test
    fun confidenceUsesDurationAndMinimumWeight() {
        val response = Transcription(segments = listOf(
            WhisperSegment(start = 0.0, end = 1.0, avgLogprob = -0.1),
            WhisperSegment(start = 1.0, end = 4.0, avgLogprob = -0.5),
            WhisperSegment(start = 4.0, end = 4.0, avgLogprob = -0.9),
        ))
        org.junit.Assert.assertEquals((-0.1 - 1.5 - 0.009) / 4.01, LanguageGuard.confidence(response)!!, 0.000001)
        expect(LanguageGuard.confidence(Transcription()) == null)
    }

    @Test
    fun equalTextWinsBeforeMissingConfidence() {
        expect(LanguageGuard.chooseExpected(Transcription(text = " Hallo Welt! "),
            Transcription(text = "hallo  welt.")))
        expect(!LanguageGuard.chooseExpected(Transcription(text = "Hallo"), null))
    }

    @Test
    fun shortFrenchRemainsFrench() = runBlocking {
        MockServer { r, _ ->
            if (r.field("language") == "de") Groq.transcription("Wir sehen uns heute Abend.", "German", -0.39)
            else Groq.transcription("On se voit ce soir.", "French", -0.08)
        }.use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(1.6)))
            val o = p.finish()
            expect(s.requests.map { it.field("language") } == listOf(null, "de"))
            expect(o.raw == "On se voit ce soir." && o.languages == listOf("fr"))
            expect(o.languageSources == listOf("checked-detected"))
        }
    }

    @Test
    fun settingsWithoutPrimaryLanguageStillDecode() {
        val d =
            PaplySettings.fromJson(
                """{"transcriptionModel":"whisper-large-v3","polishModel":"p","fallbackPolishModel":"f","vocabulary":"Paply","chunkedUpload":true,"spokenLanguages":["de","en"]}""",
            )
        expect(
            d.primaryLanguage == null &&
                d.spokenLanguages == listOf("de", "en") &&
                d.vocabulary == "Paply",
        )
        val settings = PaplySettings(primaryLanguage = "en")
        expect(PaplySettings.fromJson(settings.toJson()) == settings)
        expect(DictationOutcome.fromJson("""{"text":"Hallo"}""").languageSources.isEmpty())
    }

    @Test
    fun shortMatchingGermanIsSentOnceWithoutLanguage() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hi, wie geht's?") }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                val o = p.finish()
                val uploads = s.requests("/audio/transcriptions")
                expect(uploads.size == 1 && uploads[0].field("language") == null)
                expect(o.raw == "Hi, wie geht's?" && o.languages == listOf("de"))
                expect(o.languageSources == listOf("auto") && o.timings.chunkCount == 1)
            }
    }

    @Test
    fun matchingPrimaryIsDetectedWithoutLanguage() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hi, how are you?", "English") }
            .use { s ->
                val p = pipeline(s, primary = "en")
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                p.finish()
                expect(s.requests.first().field("language") == null)
            }
        MockServer { _, _ -> Groq.transcription("Hallo.") }
            .use { s ->
                val p = pipeline(s, primary = "fr")
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                p.finish()
                expect(
                    s.requests.first().field("language") ==
                        null,
                )
            }
    }

    @Test
    fun shortSpeechWithLongPauseCountsAsShort() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hi, wie geht's?") }
            .use { s ->
                val p = pipeline(s)
                feed(
                    p,
                    Synth.withFloor(Synth.silence(0.5) + Synth.speech(1.5) + Synth.silence(6.3)),
                )
                val o = p.finish()
                expect(o.timings.audioSeconds > 8)
                expect(s.requests.map { it.field("language") } == listOf<String?>(null))
                expect(o.languageSources == listOf("auto"))
            }
    }

    @Test
    fun longForeignPieceIsRedoneInThePrimaryLanguage() = runBlocking {
        MockServer { r, _ ->
            if (r.field("language") == "de")
                Groq.transcription("Guten Morgen, wie geht's dir heute?", language = "German")
            else Groq.transcription("Gutn morgn, kak dela segodnya?", "Russian")
        }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(12.0)))
                val o = p.finish()
                val u = s.requests
                expect(
                    u.size == 2 && u[0].field("language") == null && u[1].field("language") == "de",
                )
                expect(u[0].field("prompt") == u[1].field("prompt"))
                expect(
                    o.raw == "Guten Morgen, wie geht's dir heute?" &&
                        o.languages == listOf("de") &&
                        o.languageSources == listOf("checked-expected"),
                )
                expect(o.timings.chunkCount == 2 && o.timings.uploadedBytes > 2000)
            }
    }

    @Test
    fun failedShortCountercheckKeepsTheFirstResult() = runBlocking {
        MockServer { r, _ ->
            if (r.field("language") == "de") Groq.error(422)
            else Groq.transcription("Gutn morgn, kak dela segodnya?", "Russian")
        }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                val o = p.finish()
                expect(s.requests.size == 2 && o.errorMessage == null)
                expect(
                    o.raw == "Gutn morgn, kak dela segodnya?" &&
                        o.languages == listOf("ru") &&
                        o.languageSources == listOf("check-failed"),
                )
            }
    }

    @Test
    fun longPieceInAnotherUserLanguageStays() = runBlocking {
        MockServer { _, _ -> Groq.transcription("This is a longer English dictation.", "English") }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(12.0)))
                val o = p.finish()
                expect(s.requests.size == 1 && s.requests.first().field("language") == null)
                expect(o.languages == listOf("en") && o.languageSources == listOf("auto"))
            }
    }

    @Test
    fun shortRestFollowsTheLanguageOfThePreviousPiece() = runBlocking {
        MockServer { r, i ->
            if (i == 0) Groq.transcription("This part is clearly English.", "English")
            else
                Groq.transcription(
                    "And the rest.",
                    if (r.field("language") == "en") "English" else "German",
                )
        }
            .use { s ->
                val p = pipeline(s, chunked = true)
                feed(
                    p,
                    Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9) + Synth.speech(3.0)),
                )
                val o = p.finish()
                expect(
                    s.requests.size == 3 &&
                        s.requests[0].field("language") == null &&
                        s.requests[1].field("language") == null && s.requests[2].field("language") == "en",
                )
                expect(
                    o.raw == "This part is clearly English. And the rest." &&
                        o.languages == listOf("en") &&
                        o.languageSources == listOf("auto", "checked-expected"),
                )
            }
    }

    @Test
    fun legacyFixedLanguageDoesNotBypassDetection() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Privet, kak dela segodnya?", "Russian") }
            .use { s ->
                val p = pipeline(s, fixed = "ru")
                feed(p, Synth.withFloor(Synth.speech(12.0)))
                val o = p.finish()
                expect(s.requests.size == 1 && s.requests[0].field("language") == null)
                expect(o.languages == listOf("ru") && o.languageSources == listOf("auto"))
            }
    }
}
