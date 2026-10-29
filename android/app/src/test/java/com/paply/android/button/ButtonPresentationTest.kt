package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonPresentationTest {
    @Test fun allDeliveryCombinationsPreserveWarningsAndAnnounceEveryFallback() {
        for (bits in 0..31) {
            val accepted = bits and 1 != 0
            val retained = bits and 2 != 0
            val copied = bits and 4 != 0
            val fallback = bits and 8 != 0
            val review = bits and 16 != 0
            val message = ButtonPresentation.deliveryMessage(accepted, retained, copied, fallback, review)
            val base = when {
                review -> "Textfeld nimmt Text nicht sicher an. Bitte prüfen."
                !retained && !accepted && copied -> "Text in Zwischenablage. Jetzt einfügen; Verlauf nicht gespeichert."
                !retained && !accepted -> "Text konnte nicht gesichert werden. Bitte erneut versuchen."
                accepted -> null
                copied || fallback -> "Text in Zwischenablage. Feld lange drücken → Einfügen."
                else -> "Text nur im Verlauf. Dort kopieren und einsetzen."
            }
            assertEquals("combination $bits", if (fallback) "Text auch in der Zwischenablage" +
                (base?.let { ". $it" } ?: "") else base, message)
        }
    }
    @Test fun recordingWarningsAreOncePerSessionIncludingSkippedTicks() {
        val clock = ButtonRecordingWarning()
        assertEquals(ButtonRecordingWarning.Event.NONE, clock.observe(539_999))
        assertFalse(clock.amber(539_999))
        assertEquals(ButtonRecordingWarning.Event.MINUTE, clock.observe(540_000))
        assertTrue(clock.amber(540_000))
        assertEquals(ButtonRecordingWarning.Event.NONE, clock.observe(599_999))
        assertEquals(ButtonRecordingWarning.Event.LIMIT, clock.observe(600_000))
        assertEquals(ButtonRecordingWarning.Event.NONE, clock.observe(600_100, true))
        assertEquals(ButtonRecordingWarning.Event.LIMIT, ButtonRecordingWarning().observe(610_000))
        assertEquals(ButtonRecordingWarning.Event.LIMIT, ButtonRecordingWarning().observe(599_999, true))
        assertEquals(ButtonRecordingWarning.Event.MINUTE, ButtonRecordingWarning().observe(540_000))
    }
    @Test fun finishDiscardFinishRendersFreshVisibleControlsWithoutHint() {
        var phase = ButtonPolicy.Phase.IDLE
        fun step(event: ButtonPolicy.Event) { phase = ButtonPolicy.next(phase, event) }
        repeat(3) { round ->
            step(ButtonPolicy.Event.START); step(ButtonPolicy.Event.READY)
            for (hint in listOf(null, "Noch 1 Minute")) {
                val render = ButtonPresentation.render(phase, hint)
                assertEquals(72, render.sizeDp)
                assertTrue(render.cancel)
                assertEquals(hint, render.hint)
                assertEquals(ButtonPolicy.Phase.RECORDING, render.phase)
            }
            if (round == 1) step(ButtonPolicy.Event.DISCARD) else {
                step(ButtonPolicy.Event.FINISH)
                assertFalse(ButtonPresentation.render(phase, null).cancel)
                step(ButtonPolicy.Event.SUCCESS)
                assertNull(ButtonPresentation.render(phase, null).hint)
                step(ButtonPolicy.Event.RESULT)
            }
            assertEquals(56, ButtonPresentation.render(phase, null).sizeDp)
            assertFalse(ButtonPresentation.render(phase, null).cancel)
        }
    }
}
