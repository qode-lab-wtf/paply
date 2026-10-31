package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonEdgeTest {
    @Test fun bothEdgesRespectLandscapeInsetsAndOnlyMoveVertically() {
        val safe = ButtonPosition.safeInsets(24, 48, 0, 0, 0, 60)
        for (right in listOf(false, true)) {
            val x = ButtonPosition.edge(safe.left, 800 - safe.right, 44, right)
            val obstacle = ButtonPosition.Box(x, 480, x + 44, 560)
            val slot = ButtonPosition.choose(safe.left, 800 - safe.right, 24, 600,
                44, 56, 8, null, listOf(obstacle), fieldAnchorTop = 568, onRight = right)!!
            assertEquals(if (right) 696 else 48, slot.left)
            assertEquals(0L, slot.overlap(obstacle))
            assertTrue(slot.bottom <= obstacle.top)
        }
    }
    @Test fun activeRingHasEightDpEdgeGapAndCancelMirrorsInward() {
        for (right in listOf(false, true)) {
            val circle = ButtonPresentation.logoCenter(80f, 1f, right)
            assertEquals(8f, if (right) 80f - circle - 36f else circle - 36f)
            val circleInWindow = circle + if (ButtonPresentation.cancelBeforeLogo(right)) 48 else 0
            val cancelCenter = if (ButtonPresentation.cancelBeforeLogo(right)) 24f else 104f
            assertEquals(right, cancelCenter < circleInWindow)
            val idle = ButtonPresentation.logoCenter(44f, 0f, right)
            assertEquals(0f, if (right) 44f - idle - 12f else idle - 12f)
        }
    }
    @Test fun dragClampsAndSwitchesAtPhysicalMidpoint() {
        assertEquals(0, ButtonPosition.dragOffset(20, 100, 400))
        assertEquals(400, ButtonPosition.dragOffset(20, -900, 400))
        assertEquals(120, ButtonPosition.dragOffset(20, -100, 400))
        assertFalse(ButtonPosition.rightSide(399f, 800))
        assertTrue(ButtonPosition.rightSide(400f, 800))
    }
    @Test fun dimOnlyAfterThreeSecondsWithoutTouchAndNeverDuringWork() {
        assertEquals(1f, ButtonPresentation.idleAlpha(ButtonPolicy.Phase.IDLE, false, 2999))
        assertEquals(.6f, ButtonPresentation.idleAlpha(ButtonPolicy.Phase.IDLE, false, 3000))
        assertEquals(1f, ButtonPresentation.idleAlpha(ButtonPolicy.Phase.IDLE, true, 9000))
        for (phase in ButtonPolicy.Phase.entries.filter { it != ButtonPolicy.Phase.IDLE })
            assertEquals(1f, ButtonPresentation.idleAlpha(phase, false, 9000))
        assertEquals(1f, ButtonPresentation.idleAlpha(ButtonPolicy.Phase.IDLE, false, 0))
    }
    @Test fun preferencesDoNotReuseOldOffsets() {
        assertEquals("edge-offset-v2", ButtonPosition.OFFSET_KEY)
        assertEquals("edge-right-v2", ButtonPosition.SIDE_KEY)
        assertNotEquals("field-offset-v1", ButtonPosition.OFFSET_KEY)
    }
}
