package com.paply.thoughts

import com.paply.core.*
import com.paply.thoughts.processing.*
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.*
import org.junit.Assert.*
import org.junit.Test

class LongPauseTranscriberTests {
    private fun voice(seconds: Int) = FloatArray(seconds * 16000) { i ->
        if (i % 4800 > 3500) 0f else (0.04 * kotlin.math.sin(i * .1) * (0.55 + .45 * kotlin.math.sin(i * .003))).toFloat()
    }
    private fun field(request: RecordedRequest, name: String): String? {
        val marker = "name=\"$name\"\r\n"
        val text = request.body.clone().readUtf8()
        val at = text.indexOf(marker)
        if (at < 0) return null
        val rest = text.substring(at + marker.length)
        val value = if (rest.startsWith("\r\n")) rest.substring(2) else rest.substringAfter("\r\n\r\n")
        return value.substringBefore("\r\n")
    }

    @Test fun speechTwoMinutesSilenceSpeechUsesTwoAutomaticRequests() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("""{"text":"Tomaten pflanzen.","language":"de"}"""))
            server.enqueue(MockResponse().setBody("""{"text":"Erde kaufen.","language":"de"}"""))
            val audio = voice(3) + FloatArray(120 * 16000) + voice(3)
            ModelCatalog().use { catalog ->
                val result = FileTranscriber(baseURL = server.url("/"), catalog = catalog, decoder = { audio })
                    .transcribe(Path.of("unused.wav"), "test", PaplySettings(primaryLanguage = "de", spokenLanguages = listOf("de", "en")))
                assertTrue(result is TranscriptionResult.Success)
                assertEquals("Tomaten pflanzen. Erde kaufen.", (result as TranscriptionResult.Success).text)
                assertEquals(126.0, result.audioSeconds, 0.001)
                assertEquals(2, server.requestCount)
                repeat(2) {
                    val request = server.takeRequest(2, TimeUnit.SECONDS)!!
                    assertEquals("/audio/transcriptions", request.path)
                    assertNull(field(request, "language"))
                    // 120 s cannot be in either lossless PCM upload (JVM fallback = WAV).
                    assertTrue(request.bodySize < 4 * 16000 * 2 + 4096)
                }
            }
        }
    }

    @Test fun foreignLanguageOnLongThoughtPieceIsRetriedJustLikeDictation() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("""{"text":"Falsche Sprache.","language":"Russian"}"""))
            server.enqueue(MockResponse().setBody("""{"text":"Die Tomaten stehen auf dem Balkon.","language":"German"}"""))
            val audio = FloatArray(8000) + voice(10) + FloatArray(8000)
            ModelCatalog().use { catalog ->
                val result = FileTranscriber(baseURL = server.url("/"), catalog = catalog, decoder = { audio })
                    .transcribe(Path.of("unused.wav"), "test", PaplySettings(primaryLanguage = "de", spokenLanguages = listOf("de", "en")))
                assertTrue(result is TranscriptionResult.Success)
                assertEquals(2, server.requestCount)
                assertNull(field(server.takeRequest(), "language"))
                assertEquals("de", field(server.takeRequest(), "language"))
            }
        }
    }
}
