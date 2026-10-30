package com.paply.core

import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.Test

/** Remaining 14 FollowUp cases; six text cases are in FollowUpTextTests. */
class FollowUpTests {
    private fun detected(signal: FloatArray) =
        VoiceActivityDetector().also { it.process(signal) }.speechDetected

    @Test
    fun carPassingIsNoSpeech() {
        val car = Synth.ramp(Synth.brown(4.0, -30.0), -25.0, 0.0)
        expect(!detected(Synth.withFloor(Synth.silence(1.0) + car + Synth.silence(1.0))))
    }

    @Test
    fun mainsHumIsNoSpeech() {
        val hum =
            Synth.tones(3.0, listOf(50.0 to 1.0, 100.0 to 0.5, 150.0 to 0.3, 200.0 to 0.2), -30.0)
        expect(!detected(Synth.withFloor(Synth.silence(1.0) + hum + Synth.silence(1.0))))
        val hum60 = Synth.tones(3.0, listOf(60.0 to 1.0, 120.0 to 0.5, 180.0 to 0.3), -30.0)
        expect(!detected(Synth.withFloor(Synth.silence(1.0) + hum60 + Synth.silence(1.0))))
    }

    @Test
    fun softChordIsNoSpeech() {
        val chord =
            Synth.tones(
                3.0,
                listOf(
                    220.0 to 1.0,
                    277.18 to 1.0,
                    329.63 to 1.0,
                    440.0 to 0.4,
                    554.37 to 0.4,
                    659.26 to 0.4,
                ),
                -35.0,
            )
        expect(!detected(Synth.withFloor(Synth.silence(1.0) + chord + Synth.silence(1.0))))
    }

    @Test
    fun speechOverCarNoiseIsSpeech() {
        val rumble = Synth.brown(3.0, -34.0)
        val speech = Synth.speech(3.0, -34.0)
        val mixed = FloatArray(speech.size) { speech[it] + rumble[it] }
        expect(detected(Synth.withFloor(Synth.silence(1.0) + mixed + Synth.silence(1.0))))
    }

    @Test
    fun periodicityOfReferenceSignals() {
        fun value(signal: FloatArray) =
            VoiceActivityDetector.analyze(signal.copyOfRange(0, minOf(480, signal.size)))
                .periodicity
        expect(value(Synth.voice(0.03, -20.0)) > 0.8)
        expect(value(Synth.brown(0.03, -20.0)) < 0.6)
        expect(
            value(Synth.tones(0.03, listOf(50.0 to 1.0, 100.0 to 0.5, 150.0 to 0.3), -20.0)) < 0.6,
        )
    }

    private val raw = "Morgen besprechen wir gemeinsam unsere offenen Aufgaben."

    private suspend fun polish(s: MockServer) =
        PolishService(s.client(), s.catalog())
            .polish(raw, PolishPrompt.buildMessages(raw), "", PaplySettings())

    @Test
    fun cutStreamIsRetriedThenReported() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else
                Groq.raw(
                    """data: {"choices":[{"delta":{"content":"Morgen besprechen"},"finish_reason":null}]}""" +
                        "\n\n",
                )
        }
            .use { s ->
                val r = polish(s)
                expect(r.polished == null && r.error == PolishFailureCode.invalidResponse)
                expect(s.requests("/chat/completions").size == 2)
            }
    }

    @Test
    fun irregularFinishIsTruncated() = runBlocking {
        for (reason in listOf("length", "content_filter")) MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else Groq.chat(raw, reason)
        }
            .use { s ->
                val r = polish(s)
                expect(r.polished == null && r.rejection == "truncated")
            }
    }

    @Test
    fun doneWithoutFinishReasonIsComplete() {
        val p = ChatStreamParser()
        p.consume("""data: {"choices":[{"delta":{"content":"Hallo."}}]}""")
        p.consume("data: [DONE]")
        expect(p.completion() == ChatCompletion("Hallo.", null))
    }

    @Test
    fun unicodeLineSeparatorsInsideJSON() = runBlocking {
        val content = "Erste\u2028zweite\u2029dritte\u0085vierte"
        val event = buildJsonObject {
            put(
                "choices",
                buildJsonArray {
                    add(
                        buildJsonObject {
                            put("delta", buildJsonObject { put("content", content) })
                            put("finish_reason", "stop")
                        },
                    )
                },
            )
        }
        MockServer { _, _ -> Groq.raw("data: $event\r\n\r\ndata: [DONE]\r\n\r\n") }
            .use { s ->
                expect(
                    s.client().chat(GroqModels.polish, emptyList(), 10) ==
                        ChatCompletion(content, "stop"),
                )
            }
    }

    @Test
    fun nullErrorIsIgnored() {
        val p = ChatStreamParser()
        p.consume(
            """data: {"error":null,"choices":[{"delta":{"content":"Ok."},"finish_reason":"stop"}]}""",
        )
        p.consume("data: [DONE]")
        expect(p.completion() == ChatCompletion("Ok.", "stop"))
    }

    @Test
    fun rateLimitInsideStreamSwitchesToFallback() = runBlocking {
        val limit =
            """data: {"error":{"message":"Rate limit reached for model on tokens per day (TPD): Limit 200000. Please try again in 7m11.5s.","type":"tokens","code":"rate_limit_exceeded"}}"""
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models"))
                Groq.models(GroqModels.polish, GroqModels.polishFallback)
            else if (r.json.string("model") == GroqModels.polish) Groq.raw(limit + "\n\n")
            else Groq.chat(raw)
        }
            .use { s ->
                val r = polish(s)
                expect(r.polished == raw && r.model == GroqModels.polishFallback)
                val p = ChatStreamParser()
                p.consume(limit)
                val f = failure { p.completion() }
                expect(f.status == 429 && f.code == "rate_limit_exceeded" && f.retryAfter == 431.5)
                expect(retrySeconds("Please try again in 1h2m3s") == 3723.0)
                expect(retrySeconds("kein Hinweis") == null)
            }
    }

    @Test
    fun shortFinalWordIsUploaded() = runBlocking {
        MockServer { r, i ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else Groq.transcription(if (i == 0) "Bitte schick mir das Angebot." else "Ja.")
        }
            .use { s ->
                val p = s.pipeline(options = PipelineOptions(polish = false))
                feed(
                    p,
                    Synth.withFloor(
                        Synth.speech(11.0) +
                            Synth.silence(0.9) +
                            Synth.voice(0.12, -24.0) +
                            Synth.silence(0.4),
                    ),
                )
                val o = p.finish()
                expect(
                    s.requests("/audio/transcriptions").size == 2 &&
                        o.text == "Bitte schick mir das Angebot. Ja.",
                )
            }
    }

    @Test
    fun clicksAfterLastCutAreNotUploaded() = runBlocking {
        standardServer("Erstes Stück.").use { s ->
            val p = s.pipeline(options = PipelineOptions(polish = false))
            feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9) + Synth.clicks(2.0)))
            p.finish()
            expect(s.requests("/audio/transcriptions").size == 1)
        }
    }

    @Test
    fun timeoutScalesWithAudio() = runBlocking {
        expect(GroqClient.transcriptionTimeout(null) == 30.0)
        expect(GroqClient.transcriptionTimeout(60.0) == 30.0)
        expect(GroqClient.transcriptionTimeout(600.0) == 65.0)
        MockServer { _, _ -> Groq.transcription("Hallo.") }
            .use { s ->
                s.client()
                    .transcribe(
                        AudioEncoder.encode(shortArrayOf(1, 2, 3), false),
                        "m",
                        null,
                        null,
                        1200.0,
                    )
                expect(s.timeouts.first().second == 115000)
            }
    }
}
