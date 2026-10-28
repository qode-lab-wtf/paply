package com.paply.core

import kotlinx.coroutines.runBlocking
import org.junit.Test

class LanguageGuardTests {
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
    fun shortPiecesSendTheLanguage() {
        fun first(
            previous: String?,
            seconds: Double,
            fixed: String? = null,
            primary: String? = "de",
        ) = LanguageGuard.firstRequest(fixed, primary, previous, listOf("de", "en"), seconds)
        expect(first(null, 1.2) == LanguageGuard.Request("de", LanguageSource.short))
        expect(
            first(null, LanguageGuard.shortSpeechSeconds) ==
                LanguageGuard.Request("de", LanguageSource.short),
        )
        expect(first("en", 2.0) == LanguageGuard.Request("en", LanguageSource.short))
        expect(first("ru", 2.0) == LanguageGuard.Request("de", LanguageSource.short))
        expect(first(null, 5.1) == LanguageGuard.Request(null, LanguageSource.auto))
        expect(first("en", 8.0) == LanguageGuard.Request(null, LanguageSource.auto))
        expect(first(null, 3.0, primary = null) == LanguageGuard.Request(null, LanguageSource.auto))
        expect(first("en", 3.0, fixed = "fr") == LanguageGuard.Request("fr", LanguageSource.fixed))
        expect(first(null, 30.0, fixed = "fr") == LanguageGuard.Request("fr", LanguageSource.fixed))
    }

    @Test
    fun onlyForeignLanguagesAreRedone() {
        val users = listOf("de-DE", "en")
        expect(LanguageGuard.redoLanguage("ru", "de", users) == "de")
        for (d in listOf("en", "de", null)) expect(
            LanguageGuard.redoLanguage(d, "de", users) == null,
        )
        expect(LanguageGuard.redoLanguage("ru", null, emptyList()) == null)
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
    fun shortPieceIsSentOnceWithThePrimaryLanguage() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hi, wie geht's?") }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                val o = p.finish()
                val uploads = s.requests("/audio/transcriptions")
                expect(uploads.size == 1 && uploads[0].field("language") == "de")
                expect(o.raw == "Hi, wie geht's?" && o.languages == listOf("de"))
                expect(o.languageSources == listOf("short") && o.timings.chunkCount == 1)
            }
    }

    @Test
    fun chosenPrimaryLanguageIsUsedWhileListed() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hi, how are you?", "English") }
            .use { s ->
                val p = pipeline(s, primary = "en")
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                p.finish()
                expect(s.requests.first().field("language") == "en")
            }
        MockServer { _, _ -> Groq.transcription("Hallo.") }
            .use { s ->
                val p = pipeline(s, primary = "fr")
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                p.finish()
                expect(
                    s.requests.first().field("language") ==
                        LanguageGuard.primary(null, listOf("de", "en"), "de-DE"),
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
                expect(s.requests.map { it.field("language") } == listOf("de"))
                expect(o.languageSources == listOf("short"))
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
                        o.languageSources == listOf("redo"),
                )
                expect(o.timings.chunkCount == 2 && o.timings.uploadedBytes > 2000)
            }
    }

    @Test
    fun failedRedoKeepsTheFirstResult() = runBlocking {
        MockServer { r, _ ->
            if (r.field("language") == "de") Groq.error(422)
            else Groq.transcription("Gutn morgn, kak dela segodnya?", "Russian")
        }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(12.0)))
                val o = p.finish()
                expect(s.requests.size == 2 && o.errorMessage == null)
                expect(
                    o.raw == "Gutn morgn, kak dela segodnya?" &&
                        o.languages == listOf("ru") &&
                        o.languageSources == listOf("redo-failed"),
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
                    s.requests.size == 2 &&
                        s.requests[0].field("language") == null &&
                        s.requests[1].field("language") == "en",
                )
                expect(
                    o.raw == "This part is clearly English. And the rest." &&
                        o.languages == listOf("en") &&
                        o.languageSources == listOf("auto", "short"),
                )
            }
    }

    @Test
    fun fixedLanguageBypassesTheGuard() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Privet, kak dela segodnya?", "Russian") }
            .use { s ->
                val p = pipeline(s, fixed = "ru")
                feed(p, Synth.withFloor(Synth.speech(12.0)))
                val o = p.finish()
                expect(s.requests.size == 1 && s.requests[0].field("language") == "ru")
                expect(o.languages == listOf("ru") && o.languageSources == listOf("fixed"))
            }
    }
}
