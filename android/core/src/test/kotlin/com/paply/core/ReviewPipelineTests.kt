package com.paply.core

import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlinx.coroutines.*
import okhttp3.mockwebserver.*
import org.junit.Test

class ReviewPipelineTests {
    private fun pipeline(
        s: MockServer,
        chunked: Boolean = false,
        polish: Boolean = true,
        languages: List<String> = listOf("de", "en"),
    ) =
        s.pipeline(
            PaplySettings(chunkedUpload = chunked, spokenLanguages = languages),
            PipelineOptions(polish = polish),
        )

    @Test
    fun nothingIsUploadedBeforeSpeech() = runBlocking {
        MockServer { _, _ -> Groq.transcription("Vielen Dank.") }
            .use { s ->
                val p = pipeline(s, true)
                var audio = floatArrayOf()
                for (seed in 1..6) audio +=
                    Synth.clicks(2.5) + Synth.noise(0.5, -32.0, seed.toLong()) + Synth.silence(1.0)
                feed(p, Synth.withFloor(audio))
                expect(!p.speechDetected)
                val o = p.finish()
                expect(o.text == "" && o.noSpeech && s.requests.isEmpty())
            }
    }

    @Test
    fun firstUploadOnlyAfterSpeech() = runBlocking {
        standardServer().use { s ->
            val p = pipeline(s, true)
            feed(p, Synth.withFloor(Synth.silence(13.0)))
            expect(s.requests.isEmpty())
            feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9)))
            expect(p.speechDetected)
            eventually { s.requests("/audio/transcriptions").size == 1 }
            expect(s.requests("/audio/transcriptions").size == 1)
            p.cancel()
        }
    }

    @Test
    fun cancelAbortsRunningChunkUploadImmediately() = runBlocking {
        standardServer(transcriptionDelay = 10.0).use { s ->
            val p = pipeline(s, true)
            feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9)))
            eventually { s.requests("/audio/transcriptions").size == 1 }
            p.cancel()
            eventually(5000) { s.stoppedCount.get() > 0 }
            expect(s.stoppedCount.get() >= 1 && p.finish().text == "")
        }
    }

    @Test
    fun retryResendsOnlyTheFailedPart() = runBlocking {
        val online = AtomicBoolean(false)
        MockServer { r, i ->
            when {
                r.path!!.endsWith("/models") -> Groq.models(GroqModels.polish)
                r.path!!.endsWith("/chat/completions") -> echoPolish(r)
                i == 0 -> Groq.transcription("Erstes Stück.")
                online.get() -> Groq.transcription("Zweiter Teil.")
                else ->
                    MockResponse()
                        .setBody("interrupted response")
                        .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
            }
        }
            .use { s ->
                val p = pipeline(s, true)
                feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9)))
                eventually { s.requests("/audio/transcriptions").size == 1 }
                feed(p, Synth.withFloor(Synth.speech(4.0)))
                val failed = p.finish()
                expect(
                    failed.text == "" &&
                        failed.errorMessage!!.startsWith("Keine Verbindung") &&
                        !failed.noSpeech &&
                        p.canRetry,
                )
                val firstBody = s.requests("/audio/transcriptions")[0].bodySize
                val before = s.requests("/audio/transcriptions").size
                online.set(true)
                val o = p.retry()
                org.junit.Assert.assertTrue(
                    "outcome=$o, requests=${s.requests.map { it.path }}, failures=${s.networkFailures}",
                    o.text == "Erstes Stück. Zweiter Teil." &&
                        o.errorMessage == null &&
                        !p.canRetry,
                )
                val resent = s.requests("/audio/transcriptions").drop(before)
                expect(
                    resent.size == 1 && resent[0].bodySize < firstBody && o.timings.chunkCount == 1,
                )
                expect(
                    o.timings.uploadedBytes > 0 &&
                        o.timings.uploadedBytes < failed.timings.uploadedBytes + firstBody,
                )
            }
    }

    @Test
    fun retryAfterSuccessReturnsStoredResult() = runBlocking {
        standardServer().use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            val first = p.finish()
            val count = s.requests.size
            val again = p.retry()
            expect(
                again.text == first.text &&
                    again.text == "Hallo zusammen." &&
                    s.requests.size == count &&
                    !p.canRetry,
            )
        }
    }

    @Test
    fun retryBeforeFinishActsLikeFinishAndCancelPreservesSuccess() = runBlocking {
        standardServer().use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            expect(p.retry().text == "Hallo zusammen.")
            expect(p.finish().text == "Hallo zusammen.")
            p.cancel()
            expect(p.retry().text == "Hallo zusammen.")
        }
    }

    @Test
    fun releaseAudioKeepsResultButEndsRetry() = runBlocking {
        val online = AtomicBoolean(false)
        MockServer { r, _ ->
            when {
                r.path!!.endsWith("/models") -> Groq.models(GroqModels.polish)
                r.path!!.endsWith("/chat/completions") -> echoPolish(r)
                online.get() -> Groq.transcription("Hallo.")
                else ->
                    MockResponse()
                        .setBody("interrupted response")
                        .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
            }
        }
            .use { s ->
                val p = pipeline(s)
                feed(p, Synth.withFloor(Synth.speech(2.0)))
                p.finish()
                expect(p.canRetry)
                p.releaseAudio()
                expect(!p.canRetry)
                online.set(true)
                val o = p.retry()
                expect(o.text == "" && o.errorMessage == "Die Aufnahme ist nicht mehr verfügbar.")
            }
        standardServer().use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            p.finish()
            p.releaseAudio()
            expect(p.retry().text == "Hallo zusammen.")
        }
    }

    @Test
    fun releaseAudioDuringRecordingIsIgnored() = runBlocking {
        standardServer().use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            p.releaseAudio()
            expect(p.finish().text == "Hallo zusammen.")
        }
    }

    @Test
    fun twoConcurrentFinishCallsShareOneRun() = runBlocking {
        standardServer(transcriptionDelay = 0.2).use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            val a = async { p.finish() }
            val b = async { p.finish() }
            val c = async { p.retry() }
            expect(listOf(a.await(), b.await(), c.await()).all { it.text == "Hallo zusammen." })
            expect(
                s.requests("/audio/transcriptions").size == 1 &&
                    s.requests("/chat/completions").size == 1,
            )
        }
    }

    @Test
    fun cancelDuringPolish() = runBlocking {
        standardServer(chatDelay = 10.0).use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            val f = async { p.finish() }
            eventually { s.requests("/chat/completions").isNotEmpty() }
            val start = System.nanoTime()
            p.cancel()
            expect(f.await().text == "")
            expect(System.nanoTime() - start < 4_000_000_000)
        }
    }

    @Test
    fun cancelDuringFirstModelList() = runBlocking {
        // Android explicitly never waits for the first list. Keep transcription pending so cancel
        // happens while the same two requests are in flight; cold-cache progress is tested
        // separately.
        standardServer(transcriptionDelay = 10.0, modelsDelay = 10.0).use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            val f = async { p.finish() }
            eventually {
                s.requests("/audio/transcriptions").isNotEmpty() &&
                    s.requests("/models").isNotEmpty()
            }
            val start = System.nanoTime()
            p.cancel()
            expect(f.await().text == "")
            expect(System.nanoTime() - start < 4_000_000_000)
            expect(s.requests("/chat/completions").isEmpty())
        }
    }

    @Test
    fun cancelDuringFallbackUpload() = runBlocking {
        MockServer { r, i ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else if (i < 2) Groq.error(500) else Groq.transcription("Zu spät.").delayed(10.0)
        }
            .use { s ->
                val p = pipeline(s, true)
                feed(
                    p,
                    Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9) + Synth.speech(2.0)),
                )
                val f = async { p.finish() }
                eventually { s.requests("/audio/transcriptions").size == 3 }
                val start = System.nanoTime()
                p.cancel()
                val o = f.await()
                expect(System.nanoTime() - start < 7_000_000_000)
                expect(o.text == "" && o.errorMessage == null)
            }
    }

    @Test
    fun slowPreviousChunkStillSuppliesContext() = runBlocking {
        MockServer { r, i ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else if (i == 0) Groq.transcription("Vorheriger Text.").delayed(2.0)
            else Groq.transcription("Zweites Stück.")
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
                val start = System.nanoTime()
                eventually(20000) { s.requests("/audio/transcriptions").size == 2 }
                expect(System.nanoTime() - start < 20_000_000_000)
                expect(
                    s.requests("/audio/transcriptions")[1].field("prompt")?.contains("Vorheriger Text") ==
                        true,
                )
                p.cancel()
            }
    }

    @Test
    fun networkFailureStopsFurtherChunks() = runBlocking {
        MockServer { r, _ ->
            if (r.path!!.endsWith("/models")) Groq.models(GroqModels.polish)
            else
                MockResponse()
                    .setBody("interrupted response")
                    .setSocketPolicy(SocketPolicy.DISCONNECT_DURING_RESPONSE_BODY)
        }
            .use { s ->
                val p = pipeline(s, true)
                feed(p, Synth.withFloor(Synth.speech(11.0) + Synth.silence(0.9)))
                eventually { s.requests("/audio/transcriptions").size == 2 }
                delay(100)
                feed(
                    p,
                    Synth.withFloor(
                        Synth.speech(11.0) +
                            Synth.silence(0.9) +
                            Synth.speech(11.0) +
                            Synth.silence(0.9),
                    ),
                )
                delay(300)
                expect(s.requests("/audio/transcriptions").size == 2)
                expect(p.finish().errorMessage!!.startsWith("Keine Verbindung"))
                expect(s.requests("/audio/transcriptions").size == 4)
            }
    }

    @Test
    fun resetWhilePipelineIsAlive() = runBlocking {
        standardServer(transcriptionDelay = 0.4).use { s ->
            val p = pipeline(s)
            feed(p, Synth.withFloor(Synth.speech(2.0)))
            s.transport.reset()
            val f = async { p.finish() }
            eventually { s.requests("/audio/transcriptions").isNotEmpty() }
            s.transport.reset()
            val o = f.await()
            expect(o.text == "Hallo zusammen." && o.errorMessage == null)
        }
    }

    @Test
    fun quietSpeechOverCafeNoiseIsSpeech() = runBlocking {
        for (snr in listOf(10.0, 12.0, 14.0)) {
            val signal =
                Synth.withFloor(
                    Synth.silence(1.0) + Synth.speech(2.0, -40 + snr) + Synth.silence(1.0),
                    -40.0,
                )
            val v = VoiceActivityDetector()
            v.process(signal)
            expect(v.speechDetected)
            standardServer().use { s ->
                val p = pipeline(s)
                feed(p, signal)
                val o = p.finish()
                expect(o.text == "Hallo zusammen." && !o.noSpeech)
            }
        }
    }

    @Test
    fun noCutWhenSpeechGetsQuiet() {
        val a =
            Synth.withFloor(
                Synth.silence(2.0) + Synth.speech(12.0, -22.0) + Synth.speech(3.0, -52.0),
                -60.0,
            )
        val v = VoiceActivityDetector()
        val p = ChunkPlanner()
        val cuts = mutableListOf<IntRange>()
        for (offset in a.indices step 1600) {
            v.process(a.copyOfRange(offset, minOf(offset + 1600, a.size)))
            while (true) {
                val cut = p.nextCut(v) ?: break
                cuts += cut
            }
        }
        expect(cuts.isEmpty())
    }

    @Test
    fun floorFollowsChangingEnvironment() {
        val v = VoiceActivityDetector()
        v.process(Synth.noise(40.0, -60.0) + Synth.noise(40.0, -35.0, 9))
        expect(abs(v.floorDbfs + 35) < 3 && abs(v.floor(100) + 60) < 3)
    }
}
