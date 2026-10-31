package com.paply.core

import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.*
import org.junit.Test

class PipelineTests {
    private fun pipeline(
        s: MockServer,
        chunked: Boolean = false,
        vocabulary: String = "",
        history: List<String> = emptyList(),
    ) =
        s.pipeline(
            PaplySettings(
                chunkedUpload = chunked,
                vocabulary = vocabulary,
                spokenLanguages = listOf("de", "en"),
            ),
            history = history,
        )

    @Test
    fun silenceSendsNothing() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Vielen Dank.") }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.silence(3.0)))
                expect(!p.speechDetected)
                val o = p.finish()
                expect(o.text == "" && o.errorMessage == null)
                expect(s.requests.isEmpty())
                expect(o.timings.audioSeconds == 3.0)
            }
    }

    @Test
    fun clicksAndBreathSendNothing() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Vielen Dank.") }
            .use { s ->
                val p = pipeline(s)
                feed(
                    p,
                    Synth.withFloor(
                        Synth.clicks(2.0) + Synth.noise(0.5, -32.0) + Synth.silence(1.0),
                    ),
                )
                expect(p.finish().text == "")
                expect(s.requests.isEmpty())
            }
    }

    @Test
    fun uncertainUploadWithPolish() = runBlocking {
        MockServer { r, _ ->
            when {
                r.path!!.endsWith("/models") -> Groq.models(GroqModels.polish)
                r.path!!.endsWith("/chat/completions") ->
                    Groq.chat("Morgen besprechen wir die offenen Aufgaben.")
                else ->
                    Groq.transcription(
                        "morgen besprechen wir die offenen aufgaben",
                        logprob = -0.7,
                    )
            }
        }
            .use { s ->
                val p = pipeline(s, vocabulary = "Paply", history = listOf("Vorher gesagt."))
                feed(
                    p,
                    Synth.withFloor(Synth.silence(0.5) + Synth.speech(3.0) + Synth.silence(0.5)),
                )
                expect(p.speechDetected)
                val o = p.finish()
                expect(
                    o.raw == "morgen besprechen wir die offenen aufgaben" &&
                        o.polished == "Morgen besprechen wir die offenen Aufgaben." &&
                        o.text == o.polished,
                )
                expect(
                    o.languages == listOf("de") &&
                        o.polishModel == GroqModels.polish &&
                        o.timings.chunkCount == 2 &&
                        o.timings.uploadedBytes > 1000,
                )
                val t = o.timings
                expect(t.transcriptionDoneMs!! <= t.polishDoneMs!! && t.polishDoneMs <= t.totalMs!!)
                val upload = s.requests("/audio/transcriptions").first()
                val prompt = requireNotNull(upload.field("prompt"))
                expect(
                    prompt.startsWith(
                        "Kurzes Update: Das Meeting ist verschoben, and the new date is next Friday.",
                    ) && prompt.endsWith("Paply."),
                )
                expect(
                    upload.bodyText.contains("audio/wav"),
                ) // JVM default, FLAC is an Android adapter.
                val user =
                    s.requests("/chat/completions")
                        .first()
                        .json["messages"]!!
                        .jsonArray
                        .last()
                        .jsonObject
                        .string("content")!!
                val payload = Json.parseToJsonElement(user).jsonObject
                expect(
                    payload["background_do_not_edit"]!!.jsonArray.map {
                        it.jsonPrimitive.content
                    } == listOf("Vorher gesagt."),
                )
                expect(
                    payload["uncertain_segments"]!!.jsonArray.size == 1 &&
                        payload.string("custom_terms") == "Paply",
                )
            }
    }

    @Test
    fun rejectedPolishKeepsRawText() = runBlocking {
        MockServer { r, _ ->
            when {
                r.path!!.endsWith("/models") -> Groq.models(GroqModels.polish)
                r.path!!.endsWith("/chat/completions") ->
                    Groq.chat("Hier ist der Text: Ganz anders formuliert.")
                else -> Groq.transcription("Bitte ruf mich morgen früh an.")
            }
        }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(2.0)))
                val o = p.finish()
                expect(
                    o.text == "Bitte ruf mich morgen früh an." &&
                        o.polished == null &&
                        o.polishRejection == "meta",
                )
            }
    }

    @Test
    fun chunksAreUploadedDuringRecordingAndJoinedInOrder() = runBlocking {
        MockServer { r, i ->
            when {
                r.path!!.endsWith("/models") -> Groq.models(GroqModels.polish)
                r.path!!.endsWith("/chat/completions") -> echoPolish(r)
                else ->
                    Groq.transcription(
                        listOf(
                            "Erstes Stück endet hier.",
                            "Zweites Stück folgt.",
                            "Und der Rest.",
                        )[minOf(i, 2)],
                        if (i == 1) "English" else "German",
                    )
            }
        }
            .use { s ->
                val p = pipeline(s, true)
                feed(
                    p,
                    Synth.withFloor(
                        Synth.speech(11.0) +
                            Synth.silence(0.9) +
                            Synth.speech(11.0) +
                            Synth.silence(0.9),
                    ),
                )
                eventually { s.requests("/audio/transcriptions").size == 2 }
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                val o = p.finish()
                expect(
                    o.raw == "Erstes Stück endet hier. Zweites Stück folgt. Und der Rest." &&
                        o.text == o.raw &&
                        o.languages == listOf("de", "en") &&
                        o.timings.chunkCount == 4,
                )
                val u = s.requests("/audio/transcriptions")
                expect(u.size == 4)
                expect(
                    u[1].field("prompt")!!.endsWith("Erstes Stück endet hier.") &&
                        u[2].field("prompt")!!.endsWith("Zweites Stück folgt."),
                )
                expect(
                    u[0].field("language") == null &&
                        u[1].field("language") == null &&
                        u[2].field("language") == null && u[3].field("language") == "en",
                )
                expect(o.languageSources == listOf("auto", "auto", "checked-expected"))
            }
    }

    @Test
    fun silentTailIsNotUploaded() = runBlocking {
        standardServer("Nur ein Stück.").use { s ->
            val p = pipeline(s, true)
            feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(4.0)))
            expect(p.finish().raw == "Nur ein Stück.")
            expect(s.requests("/audio/transcriptions").size == 1)
        }
    }

    @Test
    fun failedChunkIsResentTogetherWithTheRest() = runBlocking {
        MockServer { r, i ->
            when {
                r.path!!.endsWith("/models") -> Groq.models(GroqModels.polish)
                r.path!!.endsWith("/chat/completions") -> echoPolish(r)
                i < 2 -> Groq.error(500)
                else -> Groq.transcription("Das gesamte Diktat in einem Stück.")
            }
        }
            .use { s ->
                val p = pipeline(s, true)
                feed(
                    p,
                    Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9) + Synth.speech(3.0)),
                )
                val o = p.finish()
                val u = s.requests("/audio/transcriptions")
                expect(o.raw == "Das gesamte Diktat in einem Stück." && o.errorMessage == null)
                expect(u.size == 3 && u[2].bodySize > u[0].bodySize)
                expect(o.timings.chunkCount == 2)
            }
    }

    @Test
    fun finalTranscriptionFailureIsReportedInGerman() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish) else Groq.error(401)
        }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(2.0)))
                val o = p.finish()
                expect(
                    o.text == "" &&
                        o.errorMessage ==
                            "Ungültiger Groq-Schlüssel – bitte in den Einstellungen prüfen.",
                )
                expect(s.requests("/chat/completions").isEmpty())
            }
    }

    private fun twoSegments(spoken: String, echo: String) =
        Groq.raw(
            buildJsonObject {
                put("text", " $spoken $echo")
                put("language", "German")
                put(
                    "segments",
                    buildJsonArray {
                        for ((text, start, end) in
                            listOf(Triple(spoken, 0.0, 2.0), Triple(echo, 3.0, 5.0))) add(
                            buildJsonObject {
                                put("text", " $text")
                                put("start", start)
                                put("end", end)
                                put("avg_logprob", if (start == 0.0) -0.2 else -0.4)
                                put("no_speech_prob", 0.0)
                            },
                        )
                    },
                )
            }
                .toString(),
        )

    private fun echoServer(echo: String) = MockServer { r, _ ->
        when {
            r.path!!.endsWith("/models") -> Groq.models(GroqModels.polish)
            r.path!!.endsWith("/chat/completions") -> echoPolish(r)
            else -> twoSegments("Hallo zusammen.", echo)
        }
    }

    @Test
    fun vocabularyEchoOverSilenceIsRemoved() = runBlocking {
        echoServer("Paply, Tailscale.").use { s ->
            val p = pipeline(s, vocabulary = "Paply, Tailscale")
            feed(p, Synth.withFloor(Synth.speech(2.0) + Synth.silence(3.0)))
            expect(p.finish().text == "Hallo zusammen.")
        }
    }

    @Test
    fun spokenVocabularyStays() = runBlocking {
        standardServer("Paply, Tailscale.").use { s ->
            val p = pipeline(s, vocabulary = "Paply, Tailscale")
            feed(p, Synth.withFloor(Synth.speech(1.5)))
            expect(p.finish().text == "Paply, Tailscale.")
        }
    }

    @Test
    fun spokenPrimerSentenceStaysButEchoOverSilenceGoes() = runBlocking {
        standardServer("Ich schreibe dir später.").use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(1.5)))
            val o = p.finish()
            expect(o.text == "Ich schreibe dir später." && !o.noSpeech)
        }
        echoServer("Ich schreibe dir später, see you tomorrow.").use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0) + Synth.silence(3.0)))
            expect(p.finish().text == "Hallo zusammen.")
        }
    }

    @Test
    fun echoOnlyMeansNoSpeech() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else
                Groq.raw(
                    """{"text":" see you tomorrow","language":"German","segments":[{"start":2.5,"end":4.5,"text":" see you tomorrow","avg_logprob":-0.4,"no_speech_prob":0.0}]}""",
                )
        }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(1.0) + Synth.silence(4.0)))
                val o = p.finish()
                expect(o.text == "" && o.noSpeech && o.errorMessage == null)
                expect(s.requests("/chat/completions").isEmpty())
            }
    }

    @Test
    fun artifactPhraseIsDropped() = runBlocking {
        standardServer("Untertitel der Amara.org-Community").use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            expect(p.finish().text == "")
        }
    }

    @Test
    fun cancelStopsRunningUploads() = runBlocking {
        standardServer("Zu spät.", transcriptionDelay = 10.0).use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            val task = async { p.finish() }
            eventually { s.requests("/audio/transcriptions").isNotEmpty() }
            val start = System.nanoTime()
            p.cancel()
            val o = task.await()
            expect(System.nanoTime() - start < 2_000_000_000)
            expect(
                o.text == "" && o.errorMessage == null && s.requests("/chat/completions").isEmpty(),
            )
        }
    }

    @Test
    fun cancelBeforeFinishDiscardsEverything() = runBlocking {
        standardServer("Nie gesendet.").use { s ->
            val p = pipeline(s, true)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            p.cancel()
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            expect(p.finish().text == "" && s.requests.isEmpty())
        }
    }

    @Test
    fun wavFormatOption() = runBlocking {
        standardServer("Hallo.").use { s ->
            val p =
                s.pipeline(
                    options = PipelineOptions(uploadFormat = PipelineOptions.UploadFormat.wav),
                )
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            p.finish()
            expect(
                s.requests("/audio/transcriptions")
                    .first()
                    .bodyText
                    .contains("filename=\"audio.wav\""),
            )
        }
    }

    @Test
    fun primerUsesUserLanguages() {
        val text = requireNotNull(CodeSwitchPrimer.text(listOf("fr-FR", "es")))
        expect(
            text.startsWith("Petit point : la réunion est reportée") &&
                text.contains("y la nueva fecha es el viernes"),
        )
        expect(CodeSwitchPrimer.pair(listOf("de-DE", "en-US")) == ("de" to "en"))
        expect(CodeSwitchPrimer.pair(listOf("de-DE")) == null)
        expect(CodeSwitchPrimer.pair(listOf("sv-SE", "ja")) == null)
        expect(CodeSwitchPrimer.pair(listOf("sv-SE", "it-IT", "en")) == ("it" to "en"))
        for (a in CodeSwitchPrimer.phrases.keys) for (b in CodeSwitchPrimer.phrases.keys) if (
            a != b
        )
            expect(
                WhisperPrompt.estimateTokens(CodeSwitchPrimer.text(listOf(a, b))!!) <=
                    WhisperPrompt.primerTokenShare,
            )
        for (p in CodeSwitchPrimer.phrases.values) {
            val all = (p.open + p.close).joinToString(" ").lowercase()
            expect(!all.contains("build") && !all.contains("deploy"))
        }
    }
}
