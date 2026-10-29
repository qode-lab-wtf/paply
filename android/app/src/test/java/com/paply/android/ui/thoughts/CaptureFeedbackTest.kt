package com.paply.android.ui.thoughts

import org.junit.Assert.*
import org.junit.Test

class CaptureFeedbackTest {
    @Test fun durableAudioAndProcessedResultShareOneConfirmationAndTimer() {
        val audio = captureFeedback("idle", "Gedanke gesichert · wird geordnet")
        assertEquals(audio, captureFeedback("idle", "Gedanke gespeichert"))
        assertEquals("Gedanke gesichert", audio.text)
        assertTrue(audio.saved)
        assertEquals(1900L, audio.hideAfterMs)
    }
    @Test fun informationalFailuresAndWaitingStatesExpireEvenInIdle() {
        listOf("Groq-Schlüssel fehlt", "Gedanke wartet – Schlüssel/Netz prüfen", "Nichts gespeichert", "Verworfen")
            .forEach { assertEquals(3500L, captureFeedback("idle", it).hideAfterMs) }
    }
    @Test fun recordingAndPermissionActionsNeverExpire() {
        listOf("starting", "recording", "stopping").forEach {
            assertNull(captureFeedback(it, "Benachrichtigungen sind aus").hideAfterMs)
        }
        assertNull(captureFeedback("idle", "Mikrofonzugriff erlauben", requiresAction = true).hideAfterMs)
        assertNull(captureFeedback("idle", "").hideAfterMs)
    }
}
