package com.paply.core

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class CoreReviewFixTests {
    private val spoken get() = Synth.withFloor(Synth.speech(2.0))

    @Test(timeout = 10000)
    fun cancellingFinishWaiterRetainsRunningWorkAndOtherWaiter() = runBlocking {
        standardServer(transcriptionDelay = 0.3).use { s ->
            val p = s.pipeline(options = PipelineOptions(polish = false))
            feed(p, spoken)
            val first = async { p.finish() }
            eventually { s.requests("/audio/transcriptions").isNotEmpty() }
            val second = async { p.finish() }
            first.cancelAndJoin()
            assertTrue(first.isCancelled)
            val result = withTimeout(3000) { p.retry() }
            assertEquals("Hallo zusammen.", result.raw)
            assertEquals(result, second.await())
            assertEquals(1, s.requests("/audio/transcriptions").size)
            assertEquals(0, s.stoppedCount.get())
        }
    }

    @Test(timeout = 10000)
    fun cancellingFinishWaiterRetainsAudioAndSuccessfulPlanForRetry() = runBlocking {
        MockServer { _, i ->
            when (i) {
                0 -> Groq.transcription("Das erste Stück.")
                1 -> Groq.error(401).delayed(0.3)
                else -> Groq.transcription("Und jetzt der Rest.")
            }
        }.use { s ->
            val p = s.pipeline(options = PipelineOptions(polish = false))
            feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9)))
            eventually { s.requests.size == 1 }
            feed(p, spoken)
            val waiter = async { p.finish() }
            eventually { s.requests.size == 2 }
            waiter.cancelAndJoin()
            assertEquals(DictationError.unauthorized, withTimeout(3000) { p.finish() }.error)
            assertTrue(p.canRetry)
            val result = withTimeout(3000) { p.retry() }
            assertEquals("Das erste Stück. Und jetzt der Rest.", result.raw)
            assertEquals(3, s.requests.size) // First successful piece is never re-uploaded.
            assertTrue(s.requests.last().bodySize < s.requests.first().bodySize)
        }
    }

    @Test(timeout = 10000)
    fun cancellingRetryWaiterAlsoRetainsSession() = runBlocking {
        MockServer { _, i ->
            if (i == 0) Groq.error(401) else Groq.transcription("Erneut erkannt.").delayed(0.3)
        }.use { s ->
            val p = s.pipeline(options = PipelineOptions(polish = false))
            feed(p, spoken)
            assertEquals(DictationError.unauthorized, p.finish().error)
            val waiter = async { p.retry() }
            eventually { s.requests.size == 2 }
            waiter.cancelAndJoin()
            assertEquals("Erneut erkannt.", withTimeout(3000) { p.retry() }.raw)
            assertEquals(2, s.requests.size)
        }
    }

    @Test(timeout = 10000)
    fun foreignEncoderExceptionBecomesRetryableOutcome() = runBlocking {
        standardServer().use { s ->
            val broken = AtomicBoolean(true)
            val encoder = object : AudioEncoding {
                override fun encode(samples: ShortArray, preferFLAC: Boolean): AudioEncoder.Encoded {
                    if (broken.get()) throw IllegalStateException("foreign encoder error")
                    return AudioEncoder.encode(samples, false)
                }
            }
            DictationPipeline(PaplySettings(chunkedUpload = false), s.client(), s.catalog(),
                PipelineOptions(polish = false), encoder = encoder).use { p ->
                feed(p, spoken)
                assertEquals(DictationError.network, p.finish().error)
                assertEquals(DictationError.network, p.retry().error)
                assertTrue(p.canRetry)
                broken.set(false)
                assertEquals("Hallo zusammen.", p.retry().raw)
                assertEquals(1, s.requests.size)
            }
        }
    }

    @Test(timeout = 10000)
    fun foreignExceptionInBackgroundChunkDoesNotHangFinish() = runBlocking {
        standardServer().use { s ->
            val calls = AtomicInteger()
            val encoder = object : AudioEncoding {
                override fun encode(samples: ShortArray, preferFLAC: Boolean): AudioEncoder.Encoded {
                    if (calls.getAndIncrement() == 0) throw AssertionError("chunk failure")
                    return AudioEncoder.encode(samples, false)
                }
            }
            DictationPipeline(PaplySettings(), s.client(), s.catalog(),
                PipelineOptions(polish = false), encoder = encoder).use { p ->
                feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9)))
                eventually { calls.get() > 0 }
                assertEquals("Hallo zusammen.", withTimeout(3000) { p.finish() }.raw)
                assertEquals(2, calls.get())
            }
        }
    }

    @Test(timeout = 10000)
    fun foreignTranscriptionExceptionBecomesFailureWithoutLeakingDetails() = runBlocking {
        standardServer().use { s ->
            val client = GroqClient("test", s.server.url("/"), diagnostic = {
                throw IllegalArgumentException("sensitive diagnostic details")
            })
            DictationPipeline(PaplySettings(), client, s.catalog(), PipelineOptions(polish = false)).use { p ->
                feed(p, spoken)
                val result = p.finish()
                assertEquals(DictationError.network, result.error)
                assertFalse(result.errorMessage!!.contains("sensitive"))
                assertTrue(p.canRetry)
                assertTrue(s.requests.isEmpty())
            }
        }
    }

    @Test(timeout = 10000)
    fun foreignPolishExceptionRetriesOnceThenReturnsRawText() = runBlocking {
        standardServer().use { s ->
            val attempts = AtomicInteger()
            val client = GroqClient("test", s.server.url("/"), diagnostic = {
                if (it == "polish.request") {
                    attempts.incrementAndGet()
                    throw IllegalStateException("foreign polish error")
                }
            }).also { it.retryDelaySeconds = 0.0 }
            DictationPipeline(PaplySettings(), client, s.catalog()).use { p ->
                feed(p, spoken)
                val result = p.finish()
                assertNull(result.error)
                assertEquals("Hallo zusammen.", result.text)
                assertEquals(result.raw, result.text)
                assertEquals(PolishFailureCode.network, result.polishFailure)
                assertEquals(2, attempts.get())
            }
        }
    }

    @Test(timeout = 10000)
    fun throwableInResponseParserResumesContinuation() = runBlocking {
        standardServer().use { s ->
            val client = s.client()
            val error = withTimeout(3000) {
                failure { client.send(client.request("models").build()) { throw AssertionError("parser") } }
            }
            assertEquals("invalid-response", error.code)
            assertEquals(1, s.requests.size)
        }
    }

    @Test(timeout = 10000)
    fun throwableInResponseBodyDoesNotHangPipelineFinish() = runBlocking {
        standardServer().use { s ->
            val http = GroqTransport.defaultHttp().newBuilder().addInterceptor { chain ->
                val response = chain.proceed(chain.request())
                val original = response.body!!
                response.newBuilder().body(object : okhttp3.ResponseBody() {
                    override fun contentType() = original.contentType()
                    override fun contentLength() = original.contentLength()
                    override fun source() = throw AssertionError("body read failure")
                    override fun close() = original.close()
                }).build()
            }.build()
            val client = GroqClient("test", s.server.url("/"), http = http).also { it.retryDelaySeconds = 0.0 }
            DictationPipeline(PaplySettings(), client, s.catalog(), PipelineOptions(polish = false)).use { p ->
                feed(p, spoken)
                assertEquals(DictationError.invalidResponse, withTimeout(3000) { p.finish() }.error)
            }
        }
    }

    @Test(timeout = 10000)
    fun invalidHeaderKeysAreUnauthorizedWithoutAnyHttp() = runBlocking {
        standardServer().use { s ->
            for (key in listOf("bad\u200bkey", "bad\nkey", "bad\tkey", "bad\u0000key", "bad\u007fkey", "")) {
                val client = GroqClient(key, s.server.url("/"))
                assertEquals(401, failure {
                    client.transcribe(AudioEncoder.encode(shortArrayOf(1), false), "m", null, null)
                }.status)
                DictationPipeline(PaplySettings(), client, s.catalog(), PipelineOptions(polish = false)).use { p ->
                    feed(p, spoken)
                    assertEquals(DictationError.unauthorized, p.finish().error)
                    assertEquals(DictationError.unauthorized, p.retry().error)
                }
                assertEquals(PolishFailureCode.unauthorized,
                    PolishService(client, s.catalog()).polish("Hallo.", emptyList(), "", PaplySettings()).error)
            }
            assertTrue(s.requests.isEmpty())
        }
    }

    @Test
    fun sanitizeApiKeyRemovesWhitespaceControlsAndZeroWidthCharacters() {
        val dirty = " \t\ng\u200bb\u200cc\u200dd\u2060e\ufefff\u00a0_\u0000-\u007f1\u00852\u034f3\ufe0f4\u3000"
        assertEquals("gbcdef_-1234", sanitizeApiKey(dirty))
        assertEquals("gsk_Test-123", sanitizeApiKey("gsk_Test-123"))
        assertEquals("", sanitizeApiKey("\r\n\t\u200b\ufeff"))
    }

    @Test(timeout = 10000)
    fun cancelAndCloseAfterSuccessPreserveResultAndFinishedState() = runBlocking {
        standardServer().use { s ->
            val states = CopyOnWriteArrayList<DictationState>()
            val p = s.pipeline(options = PipelineOptions(polish = false), onState = { states += it.state })
            feed(p, spoken)
            val outcome = p.finish()
            p.cancel()
            p.close()
            assertEquals(outcome, p.retry())
            assertEquals(outcome, p.finish())
            eventually { states.lastOrNull() == DictationState.finished }
            assertFalse(states.contains(DictationState.cancelled))
            assertEquals(1, s.requests.size)
        }
    }

    @Test(timeout = 10000)
    fun finishedObserverCanCloseBeforeFinishWaiterResumes() = runBlocking {
        standardServer().use { s ->
            val closed = CompletableDeferred<Unit>()
            lateinit var p: DictationPipeline
            p = s.pipeline(options = PipelineOptions(polish = false), onState = {
                if (it.state == DictationState.finished) { p.close(); closed.complete(Unit) }
            })
            feed(p, spoken)
            val outcome = p.finish()
            withTimeout(3000) { closed.await() }
            assertEquals("Hallo zusammen.", outcome.raw)
            assertNull(outcome.error)
            assertEquals(outcome, p.retry())
        }
    }

    @Test(timeout = 10000)
    fun blockingObserverDoesNotBlockAppendFinishOrCancel() = runBlocking {
        standardServer().use { s ->
            val entered = CompletableDeferred<Unit>()
            val release = CountDownLatch(1)
            val first = AtomicBoolean(true)
            val p = s.pipeline(options = PipelineOptions(polish = false), onState = {
                if (first.getAndSet(false)) { entered.complete(Unit); release.await(5, TimeUnit.SECONDS) }
            })
            try {
                p.append(shortArrayOf(1))
                withTimeout(3000) { entered.await() }
                withTimeout(1000) { withContext(Dispatchers.Default) { feed(p, spoken) } }
                assertEquals("Hallo zusammen.", withTimeout(3000) { p.finish() }.raw)
                withTimeout(1000) { withContext(Dispatchers.Default) { p.cancel() } }
            } finally { release.countDown(); p.close() }
        }
    }

    @Test(timeout = 10000)
    fun modelCatalogContentionDoesNotBlockAppendAtChunkBoundary() = runBlocking {
        standardServer().use { s ->
            val catalog = s.catalog()
            val entered = CompletableDeferred<Unit>()
            val release = CountDownLatch(1)
            val holder = launch(Dispatchers.IO) {
                synchronized(catalog) { entered.complete(Unit); release.await(5, TimeUnit.SECONDS) }
            }
            DictationPipeline(PaplySettings(), s.client(), catalog).use { p ->
                try {
                    entered.await()
                    val audio = Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9))
                    withTimeout(2000) { withContext(Dispatchers.Default) { feed(p, audio) } }
                } finally { release.countDown(); holder.join() }
                assertEquals("Hallo zusammen.", withTimeout(3000) { p.finish() }.raw)
            }
        }
    }

    @Test(timeout = 30000)
    fun appendRacesFinishAndCancelWithoutExceptionsOrHangs() = runBlocking {
        standardServer().use { s ->
            val audio = AudioEncoder.int16(spoken)
            val frame = audio.copyOfRange(0, 320)
            repeat(20) { iteration ->
                val p = s.pipeline(options = PipelineOptions(polish = false))
                p.append(audio)
                withTimeout(3000) {
                    val start = CompletableDeferred<Unit>()
                    val append = async(Dispatchers.Default) { start.await(); repeat(200) { p.append(frame) } }
                    val finish = async(Dispatchers.Default) { start.await(); p.finish() }
                    val cancel = async(Dispatchers.Default) { start.await(); if (iteration % 2 == 0) p.cancel() }
                    start.complete(Unit)
                    append.await(); cancel.await()
                    val result = finish.await()
                    assertTrue(result.error == null || result.error == DictationError.cancelled)
                    assertEquals(result, p.retry())
                }
                p.close()
            }
        }
    }

    @Test(timeout = 10000)
    fun allDeviceLanguagesAreRetainedInOrderAndSnapshotted() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Eine längere Aufnahme.", language = "German") }.use { s ->
            val languages = mutableListOf("fr-FR", "en-GB", "de-DE")
            val config = DictationConfiguration({ "test" }, deviceLanguages = languages)
            assertEquals(languages, config.deviceLanguages)
            DictationPipeline(config.settings(), s.client(), s.catalog(), PipelineOptions(polish = false),
                deviceLanguages = config.deviceLanguages).use { p ->
                languages.clear()
                feed(p, Synth.withFloor(Synth.speech(12.0)))
                assertEquals(listOf("de"), p.finish().languages)
                assertEquals(1, s.requests.size) // Third preferred language must not trigger a redo.
                assertEquals(WhisperPrompt.build("", null, CodeSwitchPrimer.text(listOf("fr", "en"))),
                    s.requests.single().field("prompt"))
            }
        }
    }

    @Test(timeout = 10000)
    fun firstDeviceLanguageIsUsedForShortSpeech() = runBlocking {
        standardServer().use { s ->
            DictationPipeline(PaplySettings(), s.client(), s.catalog(), PipelineOptions(polish = false),
                deviceLanguages = listOf("fr-FR", "en-GB", "de-DE")).use { p ->
                feed(p, spoken)
                assertEquals(listOf("fr"), p.finish().languages)
                assertEquals(listOf(null, "fr"), s.requests.map { it.field("language") })
            }
        }
    }

    @Test
    fun userPromptMatchesFoundationBytesForTypicalPayload() {
        // Captured with Foundation JSONEncoder on the MacBook, using the Swift source flags.
        val expected = """
            {
              "background_do_not_edit" : [
                "Vorher gesagt."
              ],
              "current_dictation" : "Bitte öffne /tmp/ä.txt.\nJetzt.",
              "custom_terms" : "Paply, Tailscale",
              "uncertain_segments" : [
                {
                  "avg_logprob" : -0.75,
                  "end" : 2,
                  "start" : 0,
                  "text" : " öffne /tmp/ä.txt"
                }
              ]
            }
        """.trimIndent()
        val actual = PolishPrompt.buildMessages("Bitte öffne /tmp/ä.txt.\nJetzt.", listOf("Vorher gesagt."),
            listOf(WhisperSegment(" öffne /tmp/ä.txt", 0.0, 2.0, -0.75)), "Paply;Tailscale").last().content
        assertArrayEquals(expected.toByteArray(Charsets.UTF_8), actual.toByteArray(Charsets.UTF_8))
    }

    @Test
    fun userPromptMatchesFoundationBytesForEmptyPayload() {
        val expected = "{\n  \"background_do_not_edit\" : [\n\n  ],\n  \"current_dictation\" : \"\",\n  \"uncertain_segments\" : [\n\n  ]\n}"
        assertArrayEquals(expected.toByteArray(Charsets.UTF_8),
            PolishPrompt.buildMessages("").last().content.toByteArray(Charsets.UTF_8))
    }
}
