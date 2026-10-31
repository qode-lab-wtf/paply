package com.paply.thoughts

import com.paply.core.*
import com.paply.thoughts.processing.*
import com.paply.thoughts.store.WAVWriter
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.*
import org.junit.Assert.*
import org.junit.Test

class StreamingTranscriberTests {
    private fun voice() = FloatArray(16000) { i ->
        if (i % 4800 > 3500) 0f else (0.04 * kotlin.math.sin(i * .1) * (.55 + .45 * kotlin.math.sin(i * .003))).toFloat()
    }
    @Test fun tenMinuteWavStreamsSilenceAndKeepsOriginalDuration() = runBlocking {
        val file = Files.createTempFile("ten-minute", ".wav")
        try {
            WAVWriter(file).also { w -> repeat(600) { w.append(if (it < 3) voice() else FloatArray(16000)) }; w.close() }
            WavePcm(file).use { input ->
                assertEquals(600 * 16000, input.size)
                assertEquals(16000, input.read(599 * 16000, 600 * 16000).size)
            }
            MockWebServer().use { server ->
                server.enqueue(MockResponse().setBody("""{"text":"Morgen Blumen gießen.","language":"de"}"""))
                ModelCatalog().use { catalog ->
                    val result = FileTranscriber(baseURL = server.url("/"), catalog = catalog)
                        .transcribe(file, "fake", PaplySettings(primaryLanguage = "de", spokenLanguages = listOf("de")))
                    assertTrue(result is TranscriptionResult.Success)
                    assertEquals(600.0, (result as TranscriptionResult.Success).audioSeconds, 0.001)
                    assertEquals(1, server.requestCount)
                    assertTrue(server.takeRequest(2, TimeUnit.SECONDS)!!.bodySize < 4 * 32000 + 4096)
                }
            }
        } finally { Files.deleteIfExists(file) }
    }
    @Test fun continuousSpeechIsSplitIntoBoundedUploadsWithoutDroppingDuration() = runBlocking {
        val file = Files.createTempFile("continuous", ".wav")
        try {
            WAVWriter(file).also { w -> repeat(65) { w.append(voice()) }; w.close() }
            MockWebServer().use { server ->
                repeat(2) { server.enqueue(MockResponse().setBody("""{"text":"Teil ${it + 1}.","language":"de"}""")) }
                ModelCatalog().use { catalog ->
                    val result = FileTranscriber(baseURL = server.url("/"), catalog = catalog)
                        .transcribe(file, "fake", PaplySettings(primaryLanguage = "de", spokenLanguages = listOf("de"))) as TranscriptionResult.Success
                    assertEquals(65.0, result.audioSeconds, 0.001)
                    assertEquals("Teil 1. Teil 2.", result.text)
                    assertEquals(2, server.requestCount)
                    repeat(2) { assertTrue(server.takeRequest().bodySize <= 60 * 32000 + 4096) }
                }
            }
        } finally { Files.deleteIfExists(file) }
    }
    @Test fun foreignPreviousPieceIsExpectedAcrossPipelineRuns() = runBlocking {
        val file = Files.createTempFile("foreign-pieces", ".wav")
        try {
            WAVWriter(file).also { w -> repeat(65) { w.append(voice()) }; w.close() }
            MockWebServer().use { server ->
                server.dispatcher = object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse {
                        val body = request.body.readUtf8()
                        val checked = body.contains("name=\"language\"")
                        return MockResponse().setBody(if (checked)
                            """{"text":"Falsche Übersetzung.","language":"de","segments":[{"start":0,"end":3,"avg_logprob":-0.7}]}"""
                        else """{"text":"On se voit ce soir.","language":"fr","segments":[{"start":0,"end":3,"avg_logprob":-0.1}]}""")
                    }
                }
                ModelCatalog().use { catalog ->
                    val result = FileTranscriber(baseURL = server.url("/"), catalog = catalog)
                        .transcribe(file, "fake", PaplySettings(primaryLanguage = "de", spokenLanguages = listOf("de"))) as TranscriptionResult.Success
                    assertEquals(listOf("fr"), result.languages)
                    // First piece needs a German check; next piece expects French and needs none.
                    assertEquals(3, server.requestCount)
                    assertFalse(server.takeRequest().body.readUtf8().contains("name=\"language\""))
                    assertTrue(server.takeRequest().body.readUtf8().contains("name=\"language\""))
                    assertFalse(server.takeRequest().body.readUtf8().contains("name=\"language\""))
                }
            }
        } finally { Files.deleteIfExists(file) }
    }

    @Test fun truncatedAndUnalignedDataNeverReachesNetwork() = runBlocking {
        val file = Files.createTempFile("broken", ".wav")
        try {
            WAVWriter(file).also { it.append(voice()); it.close() }
            java.io.RandomAccessFile(file.toFile(), "rw").use { it.setLength(it.length() - 1) }
            assertEquals(TranscriptionResult.Failure(TranscriptionFailure.unreadableAudio),
                FileTranscriber().transcribe(file, "unused", PaplySettings()))
        } finally { Files.deleteIfExists(file) }
    }
}
