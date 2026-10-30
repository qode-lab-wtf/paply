package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonVisibilityRegressionTest {
    @Test fun phaseAndAnchorMatrixAlwaysKeepsWorkAndHintsVisible() {
        val anchor = ButtonPosition.Box(272, 520, 392, 592)
        for (phase in ButtonPolicy.Phase.entries) for (hint in listOf(false, true)) {
            assertEquals(anchor, ButtonPosition.resolve(phase, hint, anchor, 392, 24, 120, 72, 8))
            val result = ButtonPosition.resolve(phase, hint, null, 392, 24, 120, 72, 8)
            if (phase == ButtonPolicy.Phase.IDLE && !hint) assertNull(result)
            else assertEquals(ButtonPosition.Box(272, 32, 392, 104), result)
        }
    }

    @Test fun wideClipboardNoticeFitsAfterWorkingBecomesIdle() {
        // 400 dp display: safe width 384; idle measurement permits 376.
        val field = ButtonPosition.Box(8, 600, 340, 690)
        assertNull(ButtonPosition.choose(16, 384, 24, 700, 376, 56, 16, field, emptyList()))
        val candidate = ButtonPosition.choose(8, 392, 24, 700, 376, 56, 8, field, emptyList())
        assertNotNull(candidate)
        assertEquals(candidate, ButtonPosition.resolve(ButtonPolicy.Phase.IDLE, true,
            candidate, 392, 24, 376, 56, 8))
    }

    @Test fun fullScreenImeCannotSwallowClipboardResult() {
        val ime = ButtonPosition.Box(0, 24, 800, 400)
        val candidate = ButtonPosition.choose(8, 792, 24, ime.top, 500, 72, 8,
            null, listOf(ime))
        assertNull(candidate)
        // The final delivery transitions WORKING -> IDLE while the notice timer still runs.
        for (phase in listOf(ButtonPolicy.Phase.WORKING, ButtonPolicy.Phase.IDLE)) {
            assertEquals(32, ButtonPosition.resolve(phase, true, candidate, 792, 24, 500, 72, 8)!!.top)
        }
    }

    @Test fun bannerIgnoredButSmallControlsAndAllEditorsRemainObstacles() {
        assertFalse(ButtonPosition.obstacle(360, 60, false, true, 160))
        assertFalse(ButtonPosition.obstacle(80, 200, false, true, 160))
        assertTrue(ButtonPosition.obstacle(160, 160, false, true, 160))
        assertTrue(ButtonPosition.obstacle(360, 300, true, false, 160))
        val field = ButtonPosition.Box(8, 600, 340, 690)
        val banner = ButtonPosition.Box(8, 450, 392, 590)
        val obstacles = listOf(banner).filter {
            ButtonPosition.obstacle(it.right - it.left, it.bottom - it.top, false, true, 160)
        }
        val reserved = ButtonPosition.choose(8, 392, 24, 700, 120, 72, 8, field, obstacles)!!
        assertEquals(520, reserved.top)
        val idle = ButtonPosition.window(reserved, 56, 56, 72)
        val recording = ButtonPosition.window(reserved, 120, 72, 72)
        // Logo occupies the rightmost square; X extends only to the left.
        assertEquals(idle.right - 28, recording.right - 36)
        assertEquals(idle.top + 28, recording.top + 36)
    }

    @Test fun landscapeFourLineFieldUsesLeftSideBeforeOverlappingCorner() {
        val field = ButtonPosition.Box(160, 50, 700, 215)
        val send = ButtonPosition.Box(710, 130, 792, 215)
        val result = ButtonPosition.choose(8, 792, 24, 230, 120, 72, 8, field, listOf(send))!!
        assertEquals(0L, result.overlap(field))
        assertEquals(0L, result.overlap(send))
        assertTrue(result.right <= field.left)
    }

    @Test fun fieldSwitchKeepsOldAnchorUntilNewOneSettles() {
        val stability = ButtonFieldStability(4)
        stability.observe(600, 0); stability.observe(600, 150)
        stability.reset(hold = true)
        assertEquals(600, stability.top)
        stability.observe(637, 200); stability.observe(637, 300)
        assertEquals(600, stability.top)
        stability.observe(637, 350)
        assertEquals(637, stability.top)
    }
}
