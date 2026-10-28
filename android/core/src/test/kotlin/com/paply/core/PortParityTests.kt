package com.paply.core

import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import okhttp3.mockwebserver.*
import org.junit.Assert.*
import org.junit.Test

/**
 * JVM-specific regressions at the platform boundaries, in addition to the 227 Swift declarations.
 */
class PortParityTests {
    @Test
    fun systemPromptMatchesSwiftBytes() {
        val sha =
            MessageDigest.getInstance("SHA-256")
                .digest(PolishPrompt.systemPrompt.toByteArray())
                .joinToString("") { "%02x".format(it.toInt() and 255) }
        assertEquals("1411af3d229cd5633e8a7e482fcc96ec5d89a978847536cf1ebcb1ebb69b0adc", sha)
    }

    @Test
    fun unicodeScalarBudgetsDoNotCountSurrogatePairsOrGraphemes() {
        assertEquals("a\u0308".repeat(100), PolishPrompt.vocabularyPrompt("a\u0308".repeat(150)))
        assertEquals("😀".repeat(200), PolishPrompt.vocabularyPrompt("😀".repeat(250)))
        assertNull(PolishSafetyNet.rejection("😀" + "-".repeat(9), "-".repeat(7)))
        assertEquals("length", PolishSafetyNet.rejection("😀" + "-".repeat(9), "-".repeat(6)))
        assertEquals(1, EditCheck.editDistance("😀", "a"))
    }

    @Test
    fun polishBudgetCountsUtf16Units() {
        assertEquals(12000, GroqModels.polishTokenBudget("😀".repeat(9000)))
    }

    @Test
    fun graphemeClustersAndScalarRangesRemainDistinct() {
        val family = "👨‍👩‍👧‍👦"
        assertEquals(1, family.characters().size)
        assertEquals(7, family.scalarCount)
        val text = "😀 e\u0301 𠀀𠀁𠀂"
        val tokens = TextAnalysis.runs(text, TextAnalysis::isWordScalar)
        assertEquals(listOf("e\u0301", "𠀀𠀁𠀂"), tokens.map { text.substring(it.start, it.end) })
        assertEquals(listOf("𠀀𠀁", "𠀁𠀂"), TextAnalysis.contentUnits("𠀀𠀁𠀂"))
    }

    @Test
    fun normalizationIsIndependentOfJvmLocale() {
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("tr-TR"))
            assertEquals("istanbul", TextAnalysis.normalizedLower("İSTANBUL"))
            assertEquals("é", TextAnalysis.normalizedLower("E\u0301"))
            assertEquals("en", CodeSwitchPrimer.baseCode("EN-US"))
        } finally {
            Locale.setDefault(previous)
        }
    }

    @Test
    fun regexUsesUnicodeBoundariesAndWhitespace() {
        assertTrue(Pattern("\\büber\\b").matches("über!"))
        assertFalse(Pattern("\\büber\\b").matches("xüber"))
        assertTrue(Pattern("^here\\s+is", true).matches("HERE\u00a0IS"))
        assertEquals(1, Lexicon.contractedNegation.count("don't—"))
        assertEquals(0, Lexicon.contractedNegation.count("don'té"))
        assertEquals("Wort", "\u0085\u00a0Wort\u202f\u3000".trimmed())
        assertEquals(4, WhisperPrompt.estimateTokens("ab\u00a0cd\u2028ef\u0085gh"))
    }

    @Test
    fun numericParsingUsesSwift64BitIntegers() {
        assertEquals(9223372036854775807L, EditCheck.numberValue("9223372036854775807"))
        assertNull(EditCheck.numberValue("9223372036854775808"))
        assertTrue(EditCheck.isQuantity("2147483648"))
        assertFalse(EditCheck.digitsPreserved("1234567890123456789", "1234567890123456790"))
    }

    @Test
    fun foundationWhitespaceAndSwiftCharacterSplittingRemainDistinct() {
        // Golden values checked with Foundation/Swift on the MacBook, including U+200B.
        assertEquals("Wort", "\u200bWort\u200b".trimmed())
        assertEquals(listOf("a", "b"), "a \u0301b".words())
        assertEquals(listOf("a\u200bb"), "a\u200bb".words())
        assertEquals(listOf("a", "b"), "a\r\nb".words())
        assertEquals(2, WhisperPrompt.estimateTokens("a \u0301b"))
        assertEquals("-\u0301de", CodeSwitchPrimer.baseCode("-\u0301de"))
        assertEquals("de", CodeSwitchPrimer.baseCode("_-DE-de"))
        assertEquals(
            ChatStreamParser.Step.done,
            ChatStreamParser().consume("data:\u200b[DONE]\u200b"),
        )
        assertFalse(0x2028.isFoundationSpace())
        assertTrue(0x2028.isUnicodeWhitespace())
    }

    @Test
    fun roundingAndSignalThresholdsMatchAtBoundaries() {
        val v = VoiceActivityDetector()
        repeat(100) { v.appendFrame(-50f, 0f) }
        v.appendFrame(-35f, 0f)
        v.appendFrame(-34.999f, 0f)
        assertFalse(v.isActive(100))
        assertTrue(v.isActive(101))
        repeat(3) { v.appendFrame(-44f, 0.6f) }
        assertTrue(v.isVoiced(102))
        val p =
            ChunkPlanner().apply {
                minChunkSeconds = 0.015
                pauseSeconds = 0.075
            }
        val measured = VoiceActivityDetector()
        repeat(5) { measured.appendFrame(-24f, 0.9f) }
        repeat(20) { measured.appendFrame(-80f, 0f) }
        assertEquals(
            6,
            p.nextCut(measured)!!.last + 1,
        ) // 2.5 pause frames round to 3; half is integer 1.
        assertArrayEquals(
            shortArrayOf(-16384, 16383, 0, 0),
            AudioEncoder.int16(
                floatArrayOf(-0.5f, 0.5f, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY),
            ),
        )
    }

    @Test
    fun coldOrHangingCatalogNeverGatesPolishing() = runBlocking {
        standardServer(modelsDelay = 10.0).use { s ->
            val p =
                s.pipeline(
                    PaplySettings(chunkedUpload = false, spokenLanguages = listOf("de", "en")),
                )
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            val result = withTimeout(2000) { p.finish() }
            assertEquals("Hallo zusammen.", result.text)
            eventually { s.requests("/models").size == 1 }
            assertEquals(1, s.requests("/chat/completions").size)
        }
    }

    @Test
    fun cancelledCatalogWaiterDoesNotCancelSharedFetch() = runBlocking {
        MockServer { _, _ -> Groq.models(GroqModels.polish).delayed(0.25) }
            .use { s ->
                val catalog = s.catalog()
                val client = s.client()
                val a = async { catalog.models(client) }
                val b = async { catalog.models(client) }
                eventually { s.requests.size == 1 }
                a.cancelAndJoin()
                assertEquals(listOf(GroqModels.polish), b.await())
                assertEquals(1, s.requests.size)
            }
    }

    @Test
    fun resetCannotBeUndoneByAnOldCatalogResponse() = runBlocking {
        MockServer { _, i -> if (i == 0) Groq.models("old").delayed(0.2) else Groq.models("new") }
            .use { s ->
                val cat = s.catalog()
                val c = s.client()
                val first = async { cat.models(c) }
                eventually { s.requests.size == 1 }
                cat.reset()
                assertEquals(listOf("new"), cat.models(c))
                assertEquals(listOf("old"), first.await())
                assertEquals(listOf("new"), cat.cachedModels(c))
            }
    }

    @Test
    fun cacheExpiresAtFiveMinutesAndIsKeyScoped() = runBlocking {
        MockServer { _, _ -> Groq.models(GroqModels.polish) }
            .use { s ->
                val clock = FakeClock()
                val cat = s.catalog(clock)
                val c = s.client()
                cat.models(c)
                clock.millis = 299999
                cat.cachedModels(c)
                assertEquals(1, s.requests.size)
                clock.millis = 300000
                cat.cachedModels(c)
                eventually { s.requests.size == 2 }
                val other = GroqClient("another-offline-key", s.server.url("/openai/v1/"))
                cat.models(other)
                assertEquals(3, s.requests.size)
                assertEquals(24, ModelCatalog.fingerprint(c.apiKey).length)
                assertFalse(ModelCatalog.fingerprint(c.apiKey).contains(c.apiKey))
            }
    }

    @Test
    fun successfulInvalidJsonDoesNotResendAudio() = runBlocking {
        MockServer { _, _ -> Groq.raw("broken") }
            .use { s ->
                val sent = AtomicInteger()
                val f = failure {
                    s.client()
                        .transcribe(
                            AudioEncoder.encode(shortArrayOf(1), false),
                            "m",
                            null,
                            null,
                            bytesSent = { sent.incrementAndGet() },
                        )
                }
                assertEquals("invalid-response", f.code)
                assertEquals(1, sent.get())
                assertEquals(1, s.requests.size)
            }
    }

    @Test
    fun transportRetryIsCountedEvenIfSocketFailsBeforeServerReceivesIt() = runBlocking {
        MockServer { _, _ -> MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST) }
            .use { s ->
                val sent = AtomicInteger()
                val f = failure {
                    s.client()
                        .transcribe(
                            AudioEncoder.encode(shortArrayOf(1), false),
                            "m",
                            null,
                            null,
                            bytesSent = { sent.incrementAndGet() },
                        )
                }
                assertEquals("network", f.code)
                assertEquals(2, sent.get())
            }
    }

    @Test
    fun retryAfterHeaderDateAndPrecedence() = runBlocking {
        val clock = FakeClock(0)
        assertEquals(7.0, GroqClient.retryAfter("Thu, 01 Jan 1970 00:00:07 GMT", 0)!!, 0.0)
        assertEquals(0.0, GroqClient.retryAfter("Thu, 01 Jan 1970 00:00:07 GMT", 8000)!!, 0.0)
        assertNull(GroqClient.retryAfter("NaN"))
        assertNull(GroqClient.retryAfter("-1"))
        MockServer { _, i ->
            if (i == 0) Groq.error(429, retryAfter = "0.5", message = "Please try again in 5m")
            else Groq.transcription("Hallo.")
        }
            .use { s ->
                s.client(clock = clock)
                    .transcribe(AudioEncoder.encode(shortArrayOf(1), false), "m", null, null)
                assertEquals(listOf(0.5), clock.sleeps)
            }
    }

    @Test
    fun retryTextStopsAtFirstInvalidCharacter() {
        assertEquals(3723.0, retrySeconds("Please try again in 1h2m3s. More 2m later")!!, 0.0)
        assertEquals(60.0, retrySeconds("Please try again in 1m 7s")!!, 0.0)
        assertNull(retrySeconds("Please try again in soon 1s"))
        assertNull(retrySeconds("Please try again in -1s"))
    }

    @Test
    fun sseRateLimitTypeAndPartialTextCannotLeak() = runBlocking {
        val p = ChatStreamParser()
        p.consume("""data: {"choices":[{"delta":{"content":"partial"}}]}""")
        p.consume(
            """data: {"error":{"type":"rate_limit_tokens","message":"Please try again in 0.2s"}}""",
        )
        val f = failure { p.completion() }
        assertEquals(429, f.status)
        assertEquals(0.2, f.retryAfter!!, 0.0)
        assertFalse(f.message!!.contains("partial"))
    }

    @Test
    fun optionalWhisperFieldsAreStrictlyTypedButTolerant() {
        val t =
            GroqClient.parseTranscription(
                """{"text":17,"duration":"3","language":false,"segments":[{"text":"Hi","start":"1","end":2,"avg_logprob":"-4","no_speech_prob":0.2}]}""",
            )
        assertNull(t.text)
        assertNull(t.duration)
        assertNull(t.language)
        val s = t.segments!!.single()
        assertEquals("Hi", s.text)
        assertNull(s.start)
        assertEquals(2.0, s.end!!, 0.0)
        assertNull(s.avgLogprob)
    }

    @Test
    fun keyCheckUsesExactlyOneRetryForTransientFailures() = runBlocking {
        MockServer { _, i -> if (i == 0) Groq.error(503) else Groq.models("m") }
            .use { s ->
                val clock = FakeClock()
                assertEquals(KeyCheck.Valid, GroqConnection.checkKey(s.client(clock = clock)))
                assertEquals(listOf(0.01), clock.sleeps)
                assertEquals(2, s.requests.size)
            }
    }

    @Test
    fun unreachableHintStillTriesHttp() = runBlocking {
        MockServer { _, _ -> Groq.transcription("HTTP succeeds.") }.use { s ->
            val clock = FakeClock()
            val c = GroqClient("offline", s.server.url("/"), clock = clock,
                reachability = NetworkReachability { false })
            val result = c.transcribe(AudioEncoder.encode(shortArrayOf(1), false), "m", null, null)
            assertEquals(" HTTP succeeds.", result.text)
            assertEquals(1, s.requests.size)
            assertTrue(clock.sleeps.isEmpty())
        }
    }

    @Test
    fun languageDetectorIsOnlyUsedForMissingLanguageWithTwoWords() = runBlocking {
        val calls = mutableListOf<String>()
        val detector = LanguageDetector {
            calls += it
            "fr-FR"
        }
        assertNull(detectLanguage("Bonjour", detector))
        assertEquals("fr", detectLanguage("Bonjour tout", detector))
        assertEquals(listOf("Bonjour tout"), calls)
        MockServer { _, _ -> Groq.raw("""{"text":"Bonjour tout le monde."}""") }
            .use { s ->
                val p =
                    DictationPipeline(
                        PaplySettings(language = "fr", chunkedUpload = false),
                        s.client(),
                        s.catalog(),
                        PipelineOptions(polish = false),
                        detector = detector,
                    )
                p.use {
                    feed(it, Synth.withFloor(Synth.speech(2.0)))
                    assertEquals(listOf("fr"), it.finish().languages)
                }
            }
    }

    @Test
    fun pcm16SessionApiReportsOrderedStatesAndIdempotentFinish() = runBlocking {
        standardServer().use { s ->
            val states = CopyOnWriteArrayList<DictationState>()
            val p =
                s.pipeline(PaplySettings(chunkedUpload = false), onState = { states += it.state })
            val pcm = AudioEncoder.int16(Synth.withFloor(Synth.speech(2.0)))
            for (offset in pcm.indices step 333) p.append(
                pcm.copyOfRange(offset, minOf(offset + 333, pcm.size)),
            )
            val first = p.finish()
            assertEquals(first, p.finish())
            assertEquals("Hallo zusammen.", first.text)
            eventually { states.lastOrNull() == DictationState.finished }
            assertEquals(
                listOf(
                    DictationState.recording,
                    DictationState.transcribing,
                    DictationState.polishing,
                    DictationState.finished,
                ),
                states.distinct(),
            )
            val count = s.requests.size
            p.append(pcm)
            assertEquals(first, p.finish())
            assertEquals(count, s.requests.size)
        }
    }

    @Test
    fun observerCanCancelReentrantlyWithoutStartingNetworkWork() = runBlocking {
        standardServer().use { s ->
            val cancelled = CompletableDeferred<Unit>()
            lateinit var p: DictationPipeline
            p =
                s.pipeline(
                    onState = {
                        if (it.state == DictationState.recording && it.speechDetected) {
                            p.cancel()
                            cancelled.complete(Unit)
                        }
                    },
                )
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            withTimeout(3000) { cancelled.await() }
            assertEquals(DictationError.cancelled, p.finish().error)
            assertTrue(s.requests.isEmpty())
        }
    }

    @Test
    fun outcomesRoundTripAndDefaultsMatch() {
        val o =
            DictationOutcome(
                "Hi",
                "hi",
                "Hi",
                languages = listOf("en"),
                timings = DictationTimings(1.0, 2.0, 3.0, 2, 50, 4.0),
                polishModel = GroqModels.polish,
                languageSources = listOf("short"),
            )
        assertEquals(o, DictationOutcome.fromJson(o.toJson()))
        assertEquals(DictationOutcome(), DictationOutcome.fromJson("{}"))
    }

    @Test
    fun pendingAudioLongerThanTenMinutesIsSplitAtQuietestTail() = runBlocking {
        MockServer { _, i ->
            Groq.transcription(if (i == 0) "Erster langer Teil." else "Zweiter langer Teil.")
        }
            .use { s ->
                val lengths = mutableListOf<Int>()
                val encoder = AudioEncoding { pcm, _ ->
                    lengths += pcm.size
                    AudioEncoder.encode(shortArrayOf(1, 2, 3), false)
                }
                val p =
                    DictationPipeline(
                        PaplySettings(chunkedUpload = false, spokenLanguages = listOf("de", "en")),
                        s.client(),
                        s.catalog(),
                        PipelineOptions(polish = false),
                        encoder = encoder,
                    )
                p.use {
                    val second = Synth.voice(0.2, -24.0) + Synth.silence(0.8)
                    // Same synthetic second repeated; no remote bytes beyond the injected tiny
                    // codec output.
                    repeat(620) { p.append(second) }
                    val o = it.finish()
                    assertEquals("Erster langer Teil. Zweiter langer Teil.", o.raw)
                    assertEquals(2, lengths.size)
                    assertEquals(620 * 16000, lengths.sum())
                    assertTrue(lengths.all { size -> size <= 600 * 16000 })
                    assertTrue(lengths[0] in (570 * 16000)..(600 * 16000))
                    assertEquals(2, o.timings.chunkCount)
                }
            }
    }
}
