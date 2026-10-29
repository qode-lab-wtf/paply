package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonFieldStabilityTest {
    @Test fun waitsForSettledBoundsAndHoldsPreviousPositionDuringGrowth() {
        val state = ButtonFieldStability(4)
        state.observe(700, 0)
        state.observe(700, 149)
        assertNull(state.top)
        state.observe(700, 150)
        assertEquals(700, state.top)
        state.observe(650, 200)
        state.observe(600, 300)
        state.observe(600, 449)
        assertEquals(700, state.top)
        state.observe(600, 450)
        assertEquals(600, state.top)
    }
    @Test fun ignoresJitterButAcceptsChangesOverFourPixels() {
        val state = ButtonFieldStability(4)
        state.observe(700, 0)
        state.observe(702, 150)
        assertEquals(700, state.top)
        state.observe(704, 400)
        assertEquals(700, state.top)
        state.observe(695, 500)
        state.observe(696, 650)
        assertEquals(695, state.top)
    }
    @Test fun fieldChangeOrMissingBoundsClearsOldPosition() {
        val state = ButtonFieldStability(4)
        state.observe(700, 0)
        state.observe(700, 150)
        state.reset()
        assertNull(state.top)
        state.observe(600, 200)
        state.observe(600, 350)
        assertEquals(600, state.top)
        state.observe(null, 400)
        assertNull(state.top)
    }
}
