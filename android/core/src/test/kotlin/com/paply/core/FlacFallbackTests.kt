package com.paply.core

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class FlacFallbackTests {
    private val encoder = DefaultAudioEncoding(FlacEncoder { "fLaC".toByteArray() + ByteArray(100) })
    private fun pipeline(server: MockServer, flac: Boolean = true) = DictationPipeline(
        PaplySettings(chunkedUpload = false, language = "de", vocabulary = "Paply"), server.client(), server.catalog(),
        PipelineOptions(polish = false, uploadFormat = if (flac) PipelineOptions.UploadFormat.flac else PipelineOptions.UploadFormat.wav),
        encoder = encoder)

    @Test fun audioRejectionRetriesSameRequestOnceAsWav() = runBlocking {
        for (code in listOf("invalid_audio", "invalid_request_error", null)) {
            MockServer { _, i -> if (i == 0) Groq.error(400, code) else Groq.transcription("Bitte morgen anrufen.") }.use { server ->
                pipeline(server).use { pipeline ->
                    feed(pipeline, Synth.withFloor(Synth.speech(2.0)))
                    val outcome = pipeline.finish()
                    assertEquals("Bitte morgen anrufen.", outcome.text)
                    val requests = server.requests("/audio/transcriptions")
                    assertEquals(2, requests.size)
                    assertTrue(requests[0].bodyText.contains("filename=\"audio.flac\""))
                    assertTrue(requests[1].bodyText.contains("filename=\"audio.wav\""))
                    assertTrue(requests[1].bodyText.contains("RIFF"))
                    for (field in listOf("model", "language", "prompt", "response_format"))
                        assertEquals(requests[0].field(field), requests[1].field(field))
                    assertTrue(outcome.timings.uploadedBytes > 104)
                }
            }
        }
    }
    @Test fun wavRejectionEndsFallbackWithoutLooping() = runBlocking {
        MockServer { _, _ -> Groq.error(400, "invalid_audio") }.use { server ->
            pipeline(server).use { pipeline ->
                feed(pipeline, Synth.withFloor(Synth.speech(2.0)))
                assertTrue(pipeline.finish().text.isEmpty())
                assertEquals(2, server.requests("/audio/transcriptions").size)
            }
        }
    }
    @Test fun wavAndNonAudioFailuresDoNotFallback() = runBlocking {
        for ((status, code, flac) in listOf(Triple(400, "invalid_audio", false),
            Triple(400, "model_decommissioned", true), Triple(400, "invalid_language", true), Triple(401, "unauthorized", true))) {
            MockServer { _, _ -> Groq.error(status, code) }.use { server ->
                pipeline(server, flac).use { pipeline ->
                    feed(pipeline, Synth.withFloor(Synth.speech(2.0)))
                    assertTrue(pipeline.finish().text.isEmpty())
                    assertEquals(1, server.requests("/audio/transcriptions").size)
                }
            }
        }
    }
}
