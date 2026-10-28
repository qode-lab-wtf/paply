package com.paply.core

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.*
import org.junit.Test

class GroqClientTests {
    private val audio = AudioEncoder.Encoded(byteArrayOf(1, 2, 3, 4), "audio.flac", "audio/flac")
    private val raw = "Morgen besprechen wir gemeinsam unsere offenen Aufgaben."

    private fun messages() = PolishPrompt.buildMessages(raw)

    private suspend fun polish(
        s: MockServer,
        catalog: ModelCatalog = s.catalog(),
        warm: Boolean = true,
    ): PolishResult {
        val c = s.client()
        if (warm) catalog.models(c)
        return PolishService(c, catalog).polish(raw, messages(), "", PaplySettings())
    }

    @Test
    fun sendsMultipartFields() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hallo Welt.") }
            .use { s ->
                val c = s.client()
                val t = c.transcribe(audio, "whisper-large-v3", null, "Paply.")
                expect(t.text == " Hallo Welt." && t.language == "German" && t.segments?.size == 1)
                val r = s.requests.first()
                expect(r.method == "POST" && r.path == "/openai/v1/audio/transcriptions")
                expect(r.getHeader("Authorization") == "Bearer ${c.apiKey}")
                expect(
                    r.field("model") == "whisper-large-v3" &&
                        r.field("response_format") == "verbose_json" &&
                        r.field("temperature") == "0" &&
                        r.field("prompt") == "Paply." &&
                        r.field("language") == null,
                )
                expect(r.bodyText.contains("filename=\"audio.flac\"\r\nContent-Type: audio/flac"))
            }
    }

    @Test
    fun sendsLanguageOnlyWhenSet() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hello.") }
            .use { s ->
                s.client().transcribe(audio, "m", "en", null)
                expect(
                    s.requests.first().field("language") == "en" &&
                        s.requests.first().field("prompt") == null,
                )
            }
    }

    @Test
    fun retriesExactlyOnceAfterServerError() = runBlocking {
        MockServer { _, i ->
            if (i == 0) Groq.error(503) else Groq.transcription("Zweiter Versuch.")
        }
            .use { s ->
                val sent = AtomicInteger()
                val t =
                    s.client()
                        .transcribe(audio, "m", null, null, bytesSent = { sent.addAndGet(it) })
                expect(t.text == " Zweiter Versuch." && s.requests.size == 2 && sent.get() == 8)
            }
    }

    @Test
    fun givesUpAfterSecondFailure() = runBlocking {
        MockServer { _, _ -> Groq.error(500) }
            .use { s ->
                val f = failure { s.client().transcribe(audio, "m", null, null) }
                expect(
                    f.status == 500 &&
                        f.retryAfter == null &&
                        f.germanMessage.contains("gestört") &&
                        s.requests.size == 2,
                )
            }
    }

    @Test
    fun respectsRetryAfter() = runBlocking {
        MockServer { _, i ->
            if (i == 0) Groq.error(429, retryAfter = "0.3")
            else Groq.transcription("Nach Wartezeit.")
        }
            .use { s ->
                val start = System.nanoTime()
                expect(s.client().transcribe(audio, "m", null, null).text == " Nach Wartezeit.")
                expect(System.nanoTime() - start >= 300_000_000)
            }
    }

    @Test
    fun doesNotWaitForLongRetryAfter() = runBlocking {
        MockServer { _, _ -> Groq.error(429, retryAfter = "120") }
            .use { s ->
                val f = failure { s.client().transcribe(audio, "m", null, null) }
                expect(f.germanMessage.contains("Limit") && s.requests.size == 1)
            }
    }

    @Test
    fun deterministicErrorsAreNotRetried() = runBlocking {
        for (status in listOf(401, 403, 400, 413)) MockServer { _, _ -> Groq.error(status) }
            .use { s ->
                val f = failure { s.client().transcribe(audio, "m", null, null) }
                expect(s.requests.size == 1)
                if (status == 401 || status == 403) expect(f.germanMessage.contains("Schlüssel"))
            }
    }

    @Test
    fun connectionLossIsRetriedThenReported() = runBlocking {
        MockServer { _, _ ->
            MockResponse()
                .setBody("interrupted response")
                .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
        }
            .use { s ->
                val f = failure { s.client().transcribe(audio, "m", null, null) }
                org.junit.Assert.assertTrue(
                    "status=${f.status}, code=${f.code}, requests=${s.requests.size}, attempts=${s.attempts.size}, failures=${s.networkFailures}",
                    f.germanMessage.startsWith("Keine Verbindung") && s.requests.size == 2,
                )
            }
    }

    @Test
    fun toleratesBrokenSegments() = runBlocking {
        val p =
            GroqClient.parseTranscription(
                """{"text":"Hallo.","language":"German","segments":[null]}""",
            )
        expect(p.text == "Hallo." && p.segments == null)
        expect(failure { GroqClient.parseTranscription("kaputt") }.code == "invalid-response")
    }

    @Test
    fun retryAfterParsing() {
        expect(GroqClient.retryAfter("7") == 7.0)
        expect(GroqClient.retryAfter("0.5") == 0.5)
        expect(GroqClient.retryAfter(null) == null)
        expect(GroqClient.retryAfter("bald") == null)
    }

    @Test
    fun checksModelsOnceAndSendsQwenOptions() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models"))
                Groq.models(GroqModels.polish, GroqModels.polishFallback)
            else Groq.chat("<think>privat</think>$raw")
        }
            .use { s ->
                val cat = s.catalog()
                val a = polish(s, cat)
                val b = polish(s, cat)
                expect(
                    a.polished == raw &&
                        b.polished == raw &&
                        a.model == GroqModels.polish &&
                        s.requests("/models").size == 1,
                )
                val body = s.requests("/chat/completions").first().json
                expect(
                    body.string("model") == GroqModels.polish &&
                        body.number("temperature") == 0.0 &&
                        body.number("max_tokens") == 4096.0,
                )
                expect(
                    body.string("reasoning_effort") == "none" && body["reasoning_format"] == null,
                )
                val sent = body["messages"]!!.jsonArray.map { it.jsonObject }
                expect(sent.map { it.string("role") } == listOf("system", "user"))
                expect(sent[0].string("content") == PolishPrompt.systemPrompt)
            }
    }

    @Test
    fun fallsBackToGptOssWhenQwenIsMissing() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polishFallback)
            else Groq.chat(raw)
        }
            .use { s ->
                val r = polish(s)
                expect(r.polished == raw && r.model == GroqModels.polishFallback)
                val b = s.requests("/chat/completions").first().json
                expect(
                    b.string("reasoning_format") == "hidden" &&
                        b.string("reasoning_effort") == "low",
                )
            }
    }

    @Test
    fun ignoresInactiveModels() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models"))
                Groq.raw(
                    """{"data":[{"id":"${GroqModels.polish}","active":false},{"id":"${GroqModels.polishFallback}"}]}""",
                )
            else Groq.chat(raw)
        }
            .use { s -> expect(polish(s).model == GroqModels.polishFallback) }
    }

    @Test
    fun noUsableModelMeansRawText() = runBlocking {
        MockServer { _, _ -> Groq.models("openai/gpt-oss-20b") }
            .use { s ->
                val r = polish(s)
                expect(
                    r.polished == null &&
                        r.error == PolishFailureCode.modelUnavailable &&
                        s.requests("/chat/completions").isEmpty(),
                )
            }
    }

    @Test
    fun vanishedModelSwitchesToFallbackInTheSameDictation() = runBlocking {
        for (status in listOf(404, 400)) MockServer { r, i ->
            if (r.path!!.endsWith("/models"))
                Groq.models(GroqModels.polish, GroqModels.polishFallback)
            else if (i == 0) Groq.error(status, "model_decommissioned") else Groq.chat(raw)
        }
            .use { s ->
                val cat = s.catalog()
                val r = polish(s, cat)
                expect(r.polished == raw && r.model == GroqModels.polishFallback)
                expect(
                    polish(s, cat).model == GroqModels.polishFallback &&
                        s.requests("/models").size == 1,
                )
            }
    }

    @Test
    fun retriesOnceAfterServerError() = runBlocking {
        MockServer { r, i ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else if (i == 0) Groq.error(502) else Groq.chat(raw)
        }
            .use { s ->
                expect(polish(s).polished == raw && s.requests("/chat/completions").size == 2)
            }
    }

    @Test
    fun dailyLimitSwitchesToFallbackModelOnce() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models"))
                Groq.models(GroqModels.polish, GroqModels.polishFallback)
            else if (r.json.string("model") == GroqModels.polish)
                Groq.error(429, "rate_limit_exceeded", "432")
            else Groq.chat(raw)
        }
            .use { s ->
                val r = polish(s)
                expect(
                    r.polished == raw &&
                        r.model == GroqModels.polishFallback &&
                        s.requests("/chat/completions").size == 2,
                )
            }
    }

    @Test
    fun shortRateLimitIsRetriedOnSameModel() = runBlocking {
        MockServer { r, i ->
            if (r.path!!.endsWith("/models"))
                Groq.models(GroqModels.polish, GroqModels.polishFallback)
            else if (i == 0) Groq.error(429, retryAfter = "0.05") else Groq.chat(raw)
        }
            .use { s ->
                val r = polish(s)
                expect(r.polished == raw && r.model == GroqModels.polish)
            }
    }

    @Test
    fun twoFailuresMeanRawTextWithoutSensitiveDetails() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else
                MockResponse()
                    .setBody("interrupted response")
                    .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
        }
            .use { s ->
                val r = polish(s)
                expect(
                    r.polished == null &&
                        r.error == PolishFailureCode.network &&
                        s.requests("/chat/completions").size == 2,
                )
            }
    }

    @Test
    fun unreachableModelListStillTriesPreferredModel() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models"))
                MockResponse()
                    .setBody("interrupted response")
                    .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
            else Groq.chat(raw)
        }
            .use { s ->
                val r = polish(s, warm = false)
                expect(r.polished == raw && r.model == GroqModels.polish)
            }
    }

    @Test
    fun unsafeOutputIsRejected() = runBlocking {
        for ((output, reason) in
            listOf(
                "" to "empty",
                "Hier ist die Korrektur: $raw" to "meta",
                "Kurz." to "length",
                raw + raw to "length",
                "Heute diskutieren alle zusammen neue schwierige Projekte." to "content",
            )) {
            MockServer { r, _ ->
                if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
                else Groq.chat(output)
            }
                .use { s ->
                    val r = polish(s)
                    expect(r.polished == null && r.rejection == reason)
                    expect(s.requests("/chat/completions").size == 1)
                }
        }
    }

    @Test
    fun truncatedOutputIsRejected() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else Groq.chat(raw, "length")
        }
            .use { s ->
                val r = polish(s)
                expect(r.polished == null && r.rejection == "truncated")
            }
    }

    @Test
    fun parallelDictationsShareTheModelQuery() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish).delayed(0.2)
            else Groq.chat(raw)
        }
            .use { s ->
                val cat = s.catalog()
                val a = async { polish(s, cat, false) }
                val b = async { polish(s, cat, false) }
                expect(listOf(a.await(), b.await()).all { it.polished == raw })
                eventually { s.requests("/models").size == 1 }
                expect(s.requests("/models").size == 1)
            }
    }

    @Test
    fun staleModelListIsServedAndRefreshedInBackground() = runBlocking {
        val clock = FakeClock()
        MockServer { _, i ->
            if (i == 0) Groq.models(GroqModels.polish)
            else Groq.models(GroqModels.polishFallback).delayed(0.3)
        }
            .use { s ->
                val cat = s.catalog(clock)
                val c = s.client()
                expect(cat.models(c) == listOf(GroqModels.polish))
                expect(cat.models(c) == listOf(GroqModels.polish))
                expect(s.requests.size == 1)
                clock.millis += 301000
                val start = System.nanoTime()
                expect(cat.models(c) == listOf(GroqModels.polish))
                expect(System.nanoTime() - start < 200_000_000)
                eventually { cat.cachedModels(c) == listOf(GroqModels.polishFallback) }
                expect(s.requests.size == 2)
            }
    }

    @Test
    fun prewarmOnlyWarmsTheConnectionWhileTheListIsFresh() = runBlocking {
        val clock = FakeClock()
        MockServer { r, _ ->
            if (r.method == "HEAD") Groq.raw("", 404) else Groq.models(GroqModels.polish)
        }
            .use { s ->
                val cat = s.catalog(clock)
                val c = s.client()
                fun count(m: String) = s.requests.count { it.method == m }
                GroqConnection.prewarm(c, cat)
                expect(count("GET") == 1 && count("HEAD") == 0)
                GroqConnection.prewarm(c, cat)
                expect(count("GET") == 1 && count("HEAD") == 1)
                expect(s.requests.last().getHeader("Authorization") == null)
                clock.millis += 5 * 3600000
                GroqConnection.prewarm(c, cat)
                expect(count("GET") == 1 && count("HEAD") == 2)
                clock.millis += 2 * 3600000
                GroqConnection.prewarm(c, cat)
                expect(count("GET") == 2)
                GroqConnection.prewarm(c, cat, true)
                expect(count("GET") == 3)
            }
    }
}
