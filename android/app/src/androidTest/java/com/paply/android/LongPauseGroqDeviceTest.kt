package com.paply.android

import androidx.test.platform.app.InstrumentationRegistry
import com.paply.android.settings.KeyVault
import com.paply.android.settings.SettingsRepository
import com.paply.core.PaplySettings
import com.paply.thoughts.processing.FileTranscriber
import com.paply.thoughts.processing.TranscriptionResult
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Explicit opt-in only. The hard request cap runs BEFORE Groq sends, including transport retries. */
class LongPauseGroqDeviceTest {
    @Test fun capturedPauseWithAtMostTwoRequests() = runBlocking {
        assumeTrue("Requires separate explicit Groq budget approval",
            InstrumentationRegistry.getArguments().getString("groqEvidence") == "approved-two-requests")
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val input = File(app.filesDir, "imefix-evidence.wav")
        check(input.isFile)
        val calls = AtomicInteger()
        val prefs = SettingsRepository.get(app).snapshot()
        val transcriber = FileTranscriber(diagnostic = {
            if (it == "thought.groq count=1") check(calls.incrementAndGet() <= 2) { "Evidence request budget exhausted" }
        })
        val result = transcriber.transcribe(input.toPath(), requireNotNull(KeyVault(app).read()),
            PaplySettings(transcriptionModel = prefs.transcriptionModel, primaryLanguage = "de", spokenLanguages = listOf("de", "en")))
        val proof = JSONObject().put("attemptedRequests", calls.get()).put("actualRequestsAtMost", minOf(calls.get(), 2))
            .put("file", input.name).put("bytes", input.length())
        if (result is TranscriptionResult.Success) {
            proof.put("text", result.text).put("languages", org.json.JSONArray(result.languages)).put("audioSeconds", result.audioSeconds)
        } else proof.put("result", result.toString())
        File(app.filesDir, "imefix-groq-proof.json").writeText(proof.toString())
        assertTrue(result is TranscriptionResult.Success)
        assertEquals(2, calls.get())
        result as TranscriptionResult.Success
        assertTrue(result.text.contains("Tomaten", ignoreCase = true))
        assertTrue(result.text.contains("Erde", ignoreCase = true))
        assertFalse(result.text.contains("I write", ignoreCase = true))
        assertFalse(result.text.contains("Instead of", ignoreCase = true))
    }
}
