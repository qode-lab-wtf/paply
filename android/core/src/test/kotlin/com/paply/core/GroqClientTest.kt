package com.paply.core

import java.io.File
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import okhttp3.mockwebserver.*
import org.junit.Assert.*
import org.junit.Test

class GroqClientTest {
    private fun server(block: (MockWebServer, GroqClient) -> Unit) {
        MockWebServer().use { server -> server.start(); block(server, GroqClient("test-key", server.url("/"))) }
    }
    private fun response(body: String, code: Int = 200) = MockResponse().setResponseCode(code).setBody(body)
    private val catalog = """{"data":[{"id":"qwen/qwen3.8-27b"},{"id":"openai/gpt-oss-120b"}]}"""
    private fun chat(text: String, reason: String = "stop") = response("""{"choices":[{"message":{"content":"$text"},"finish_reason":"$reason"}]}""")
    private val raw = Transcript("Hallo, äh, Welt.", "german", emptyList())
    @Test fun multipartAndWavFormat() = server { s, c -> runBlocking {
        val file = File.createTempFile("paply", ".wav")
        try {
            WavWriter(file).use { it.append(shortArrayOf(1000, -1000), 2) }
            assertEquals(48, file.length())
            assertEquals("RIFF", file.readBytes().take(4).toByteArray().decodeToString())
            s.enqueue(response("""{"text":"Hallo Welt.","language":"german","segments":[]}"""))
            assertEquals("Hallo Welt.", c.transcribe(file, 1.0).text)
            val request = s.takeRequest(); val body = request.body.readUtf8()
            assertEquals("/audio/transcriptions", request.path)
            assertTrue(body.contains("whisper-large-v3")); assertTrue(body.contains("verbose_json"))
            assertFalse(body.contains("name=\"language\"")); assertFalse(body.contains("name=\"prompt\""))
        } finally { file.delete() }
    } }
    @Test fun verbatimPromptAndModelOptions() = server { s, c -> runBlocking {
        s.enqueue(response(catalog)); s.enqueue(chat("Hallo Welt."))
        val result = DictationPipeline(c).polish(raw)
        assertEquals("Hallo Welt.", result.text); assertNull(result.fallbackReason)
        s.takeRequest(); val body = s.takeRequest().body.readUtf8()
        assertTrue(body.contains("qwen/qwen3.8-27b")); assertTrue(body.contains("\"reasoning_effort\":\"none\""))
        assertTrue(body.contains("current_dictation")); assertTrue(body.contains("Lightly polish only the current dictation."))
    } }
    @Test fun missingModelUsesExactFallbackOnce() = server { s, c -> runBlocking {
        s.enqueue(response(catalog)); s.enqueue(response("""{"error":{"code":"model_not_found"}}""", 404)); s.enqueue(chat("Hallo Welt."))
        assertEquals(GroqModels.polishFallback, DictationPipeline(c).polish(raw).model)
        s.takeRequest(); s.takeRequest(); val body = s.takeRequest().body.readUtf8()
        assertTrue(body.contains("\"reasoning_format\":\"hidden\"")); assertTrue(body.contains("\"reasoning_effort\":\"low\""))
        assertEquals(3, s.requestCount)
    } }
    @Test fun longRateLimitUsesFallbackWithoutWaiting() = server { s, c -> runBlocking {
        s.enqueue(response(catalog)); s.enqueue(response("""{"error":{"message":"Please try again in 7m11.135s"}}""", 429)); s.enqueue(chat("Hallo Welt."))
        assertEquals(GroqModels.polishFallback, DictationPipeline(c).polish(raw).model)
    } }
    @Test fun truncatedAnswerFallsBackToRaw() = server { s, c -> runBlocking {
        s.enqueue(response(catalog)); s.enqueue(chat("Hallo", "length"))
        val result = DictationPipeline(c).polish(raw)
        assertEquals(raw.text, result.text); assertEquals("truncated", result.fallbackReason)
    } }
    @Test fun streamingCollectsAllChunks() = server { s, c -> runBlocking {
        s.enqueue(response("data: {\"choices\":[{\"delta\":{\"content\":\"Hallo \"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"Welt.\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n"))
        assertEquals("Hallo Welt.", c.chat(GroqModels.polish, raw).text)
    } }
    @Test fun brokenStreamRetriesOnceThenReturnsRaw() = server { s, c -> runBlocking {
        s.enqueue(response(catalog))
        repeat(2) { s.enqueue(response("data: {\"choices\":[{\"delta\":{\"content\":\"Hal\"}}]}\n")) }
        val result = DictationPipeline(c).polish(raw)
        assertEquals(raw.text, result.text); assertEquals(3, s.requestCount)
    } }
    @Test fun cancellationNeverBecomesRawFallback() = server { s, c -> runBlocking {
        s.enqueue(response(catalog)); s.enqueue(chat("Hallo Welt.").setBodyDelay(5, TimeUnit.SECONDS))
        val task = async { DictationPipeline(c).polish(raw) }
        withContext(Dispatchers.IO) { s.takeRequest(); s.takeRequest() }
        task.cancelAndJoin(); assertTrue(task.isCancelled)
    } }
    @Test fun unauthorizedIsNotRetried() = server { s, c -> runBlocking {
        s.enqueue(response(catalog)); s.enqueue(response("{}", 401))
        assertEquals("http-401", DictationPipeline(c).polish(raw).fallbackReason)
        assertEquals(2, s.requestCount)
    } }
    @Test fun quietEdgesKeepContextAndCorrectHeader() {
        val file = File.createTempFile("paply", ".wav")
        try {
            val samples = ShortArray(64000) { if (it in 32000 until 40000) 2000 else 0 }
            WavWriter(file).use { it.append(samples, samples.size) }
            assertEquals(24000L, trimQuietEdges(file, 32000, 40000))
            assertEquals(48044L, file.length())
            val bytes = file.readBytes()
            assertEquals(0, bytes[44].toInt())
            assertEquals(2000, (bytes[16044].toInt() and 255) or ((bytes[16045].toInt() and 255) shl 8))
            assertEquals(48000, (0..3).sumOf { (bytes[40+it].toInt() and 255) shl (8*it) })
        } finally { file.delete() }
    }
    @Test fun tokenBudgetMatchesIOS() {
        assertEquals(4096, GroqModels.tokenBudget("Hi"))
        assertEquals(32768, GroqModels.tokenBudget("a".repeat(100000)))
        assertEquals(431.135, retrySeconds("Please try again in 7m11.135s")!!, 0.001)
    }
}
