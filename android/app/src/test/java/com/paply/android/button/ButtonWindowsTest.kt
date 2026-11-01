package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonWindowsTest {
    @Test fun idleWithoutHintShowsOnlyGrip() {
        assertEquals(ButtonWindows.Visibility(true, false, false, false),
            ButtonWindows.visibility(ButtonPolicy.Phase.IDLE, null))
    }
    @Test fun idleHintLeavesGripUsableAndCannotInterceptTouches() {
        assertEquals(ButtonWindows.Visibility(true, true, false, true),
            ButtonWindows.visibility(ButtonPolicy.Phase.IDLE, "Hinweis"))
    }
    @Test fun activePhasesOwnControlsWithAndWithoutHints() {
        for (phase in ButtonPolicy.Phase.entries.filter { it != ButtonPolicy.Phase.IDLE }) {
            for (hint in listOf(null, "Hinweis")) {
                assertEquals(ButtonWindows.Visibility(false, true, true, false),
                    ButtonWindows.visibility(phase, hint))
            }
        }
    }
    @Test fun repeatedRendersDoNotRestartExchange() {
        assertEquals(ButtonWindows.Change.KEEP, ButtonWindows.change(false, false))
        assertEquals(ButtonWindows.Change.KEEP, ButtonWindows.change(true, true))
    }
    @Test fun idleHintDoesNotExchangeWindows() {
        val idle = ButtonWindows.visibility(ButtonPolicy.Phase.IDLE, null)
        val hint = ButtonWindows.visibility(ButtonPolicy.Phase.IDLE, "Hinweis")
        assertEquals(ButtonWindows.Change.KEEP, ButtonWindows.change(idle.activeTouchable, hint.activeTouchable))
        assertEquals(ButtonWindows.Change.KEEP, ButtonWindows.change(hint.activeTouchable, idle.activeTouchable))
    }
    @Test fun recordingFromHintAndReturnToHintUseNormalExchange() {
        val hint = ButtonWindows.visibility(ButtonPolicy.Phase.IDLE, "Hinweis")
        for (phase in ButtonPolicy.Phase.entries.filter { it != ButtonPolicy.Phase.IDLE }) {
            val active = ButtonWindows.visibility(phase, null)
            assertEquals(ButtonWindows.Change.OPEN, ButtonWindows.change(hint.activeTouchable, active.activeTouchable))
            assertEquals(ButtonWindows.Change.CLOSE, ButtonWindows.change(active.activeTouchable, hint.activeTouchable))
        }
    }
}
