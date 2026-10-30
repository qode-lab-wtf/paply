package com.paply.core

import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.*
import org.junit.Assert.*
import org.junit.Test

/** Two text integration cases, seven client cases, key checks and the JVM codec boundary. */
class ReviewClientTests {
    @Test
    fun singleCJKCharacterIsAWord() = runBlocking {
        expect(
            !SilenceFilter.isTrivialTranscript("好") &&
                !SilenceFilter.isTrivialTranscript("是。") &&
                SilenceFilter.isTrivialTranscript("?"),
        )
        standardServer("好").use { s ->
            val p =
                s.pipeline(
                    PaplySettings(chunkedUpload = false, spokenLanguages = listOf("zh", "en")),
                )
            feed(p, Synth.withFloor(Synth.speech(1.0)))
            expect(p.finish().text == "好")
        }
    }

    @Test
    fun partialEchoSegmentsAreRemovedOnlyWithoutVoice() {
        val primer =
            "Kurzes Update: Das Meeting ist verschoben, and the new date is next Friday. Ich schreibe dir später, see you tomorrow."
        fun clean(echo: String, voiced: Double, tail: String? = null): String {
            val segments =
                listOf(
                    WhisperSegment(" Das Angebot ist raus.", 0.0, 2.0),
                    WhisperSegment(" $echo", 3.0, 4.0),
                )
            return TranscriptCleanup.removeEchoes(
                    "Das Angebot ist raus. $echo",
                    segments,
                    primer,
                    tail,
                    "",
                    4.0,
                ) { start, _ ->
                    if (start < 2.5) 900.0 else voiced
                }
                .text
        }
        expect(clean("see you tomorrow", 0.0) == "Das Angebot ist raus.")
        expect(clean("see you tomorrow", 600.0) == "Das Angebot ist raus. see you tomorrow")
        expect(clean("see you", 0.0) == "Das Angebot ist raus. see you")
        expect(clean("morgen früh", 0.0, "Wir treffen uns morgen früh") == "Das Angebot ist raus.")
    }

    @Test
    fun multipartCarriesUTF8AndLineBreaks() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Hallo.") }
            .use { s ->
                s.client()
                    .transcribe(
                        AudioEncoder.Encoded(byteArrayOf(1, 2), "audio.flac", "audio/flac"),
                        "m",
                        null,
                        "Müller, 日本語\nzweite Zeile",
                    )
                val t = s.requests.first().bodyText
                expect(t.contains("name=\"prompt\"\r\nContent-Type: text/plain; charset=utf-8\r\n"))
                expect(
                    s.requests.first().field("prompt") == "Müller, 日本語\nzweite Zeile" &&
                        !t.contains("name=\"language\""),
                )
            }
    }

    @Test
    fun requestTimeouts() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else Groq.transcription("Hallo.")
        }
            .use { s ->
                s.client()
                    .transcribe(AudioEncoder.encode(shortArrayOf(1, 2, 3), false), "m", null, null)
                GroqConnection.checkKey(s.client())
                expect(
                    s.timeouts.first { it.first.endsWith("/audio/transcriptions") }.second == 30000,
                )
                expect(s.timeouts.first { it.first.endsWith("/models") }.second == 15000)
            }
    }

    @Test
    fun rateLimitedKeyIsValid() = runBlocking {
        MockServer { _, _ -> Groq.error(429, retryAfter = "60") }
            .use { s ->
                expect(
                    GroqConnection.checkKey(s.client()) == KeyCheck.Valid && s.requests.size == 1,
                )
            }
    }

    @Test
    fun plainJSONAnswerWorksToo() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else Groq.chatJSON("Morgen besprechen wir gemeinsam unsere offenen Aufgaben.")
        }
            .use { s ->
                val raw = "morgen besprechen wir gemeinsam unsere offenen aufgaben"
                val result =
                    PolishService(s.client(), s.catalog())
                        .polish(raw, PolishPrompt.buildMessages(raw), "", PaplySettings())
                expect(
                    result.polished == "Morgen besprechen wir gemeinsam unsere offenen Aufgaben.",
                )
                expect(
                    s.requests("/chat/completions").first().json["stream"]!!.jsonPrimitive.boolean,
                )
            }
    }

    @Test
    fun streamParser() = runBlocking {
        val p = ChatStreamParser()
        for (line in
            listOf(
                """data: {"choices":[{"delta":{"content":"Hal"},"finish_reason":null}]}""",
                "",
                """data: {"choices":[{"delta":{"content":"lo."},"finish_reason":"stop"}]}""",
                "data: [DONE]",
            )) if (p.consume(line) == ChatStreamParser.Step.done) break
        expect(p.completion() == ChatCompletion("Hallo.", "stop"))
        val broken = ChatStreamParser()
        broken.consume("""data: {"error":{"message":"x"}}""")
        expect(failure { broken.completion() }.code == "invalid-response")
    }

    @Test
    fun noPrimerWithOnlyOneKnownLanguage() = runBlocking {
        standardServer().use { s ->
            val p = s.pipeline(PaplySettings(chunkedUpload = false, spokenLanguages = listOf("de")))
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            p.finish()
            expect(s.requests("/audio/transcriptions").first().field("prompt") == null)
        }
    }

    @Test
    fun pollishFailureCodesAreStable() {
        expect(
            PolishFailureCode.entries.map { it.rawValue } ==
                listOf(
                    "disabled",
                    "model-unavailable",
                    "rate-limited",
                    "unauthorized",
                    "server-error",
                    "request-rejected",
                    "network",
                    "invalid-response",
                    "cancelled",
                ),
        )
        expect(
            GroqFailure(429).polishCode == PolishFailureCode.rateLimited &&
                GroqFailure().polishCode == PolishFailureCode.network,
        )
        expect(
            DictationOutcome(polishError = "rate-limited").polishFailure ==
                PolishFailureCode.rateLimited,
        )
        val d = DictationOutcome.fromJson("""{"text":"Hallo"}""")
        expect(d.text == "Hallo" && !d.noSpeech)
    }

    @Test
    fun outcomes() = runBlocking {
        MockServer { _, _ -> Groq.models(GroqModels.polish) }
            .use { s -> expect(GroqConnection.checkKey(s.client()) == KeyCheck.Valid) }
        MockServer { _, _ -> Groq.error(401, "invalid_api_key") }
            .use { s ->
                expect(
                    GroqConnection.checkKey(s.client()) == KeyCheck.Invalid && s.requests.size == 1,
                )
            }
        MockServer { _, _ ->
            MockResponse()
                .setBody("interrupted response")
                .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
        }
            .use { s -> expect(GroqConnection.checkKey(s.client()) == KeyCheck.Offline) }
        MockServer { _, _ -> Groq.error(500) }
            .use { s ->
                val r = GroqConnection.checkKey(s.client())
                expect(r is KeyCheck.Failed && r.message.contains("500") && s.requests.size == 2)
            }
        expect(GroqConnection.checkKey("  ") == KeyCheck.Invalid)
        expect(!GroqConnection.validate(""))
    }

    // AVAudioFile's temporary-file cleanup is not portable. Core writes no temporary codec files;
    // the future Android adapter owns cleanup. Exercise failure, bad container and empty paths
    // here.
    @Test
    fun flacFailureAndInvalidContainerFallBackWithoutTemporaryFiles() {
        val samples = AudioEncoder.int16(Synth.speech(1.0))
        for (codec in
            listOf(
                FlacEncoder { throw java.io.IOException("codec unavailable") },
                FlacEncoder { ByteArray(100) },
                FlacEncoder { "fLaC".toByteArray() },
            )) {
            val e = DefaultAudioEncoding(codec).encode(samples, true)
            expect(!e.isFLAC)
            assertArrayEquals(AudioEncoder.wav(samples), e.data)
        }
        var called = false
        val e =
            DefaultAudioEncoding(
                    FlacEncoder {
                        called = true
                        null
                    },
                )
                .encode(shortArrayOf(), true)
        expect(!called && !e.isFLAC && e.data.size == 44)
    }
}
