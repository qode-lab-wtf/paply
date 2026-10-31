package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonWindowsTest {
    @Test fun onlyIdleWithoutHintBelongsToGrip() {
        for (phase in ButtonPolicy.Phase.entries) {
            assertEquals(phase != ButtonPolicy.Phase.IDLE, ButtonWindows.active(phase, null))
            assertTrue(ButtonWindows.active(phase, "Hinweis"))
        }
    }
    @Test fun repeatedRendersDoNotRestartExchange() {
        assertEquals(ButtonWindows.Change.KEEP, ButtonWindows.change(false, false))
        assertEquals(ButtonWindows.Change.KEEP, ButtonWindows.change(true, true))
    }
    @Test fun recordingAndIdleHintsUseSameExchangeInBothDirections() {
        for (phase in ButtonPolicy.Phase.entries) {
            val active = ButtonWindows.active(phase, "Hinweis")
            assertEquals(ButtonWindows.Change.OPEN, ButtonWindows.change(false, active))
            assertEquals(ButtonWindows.Change.CLOSE, ButtonWindows.change(active, false))
        }
    }
}
