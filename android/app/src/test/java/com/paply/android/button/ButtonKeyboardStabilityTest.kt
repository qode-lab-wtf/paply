package com.paply.android.button

import android.graphics.Rect
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [30])
class ButtonKeyboardStabilityTest {
    @Test fun waitsForAllBoundsToRemainStableAndResetsOnHide() {
        val stability = ButtonKeyboardStability()
        val bounds = listOf(Rect(0, 600, 400, 1000))
        assertFalse(stability.observe(bounds, 0))
        assertFalse(stability.observe(bounds, 149))
        assertTrue(stability.observe(bounds, 150))
        val moved = listOf(Rect(0, 588, 400, 1000))
        assertFalse(stability.observe(moved, 160))
        assertFalse(stability.observe(moved, 309))
        assertTrue(stability.observe(moved, 310))
        assertFalse(stability.observe(emptyList(), 400))
        assertFalse(stability.observe(bounds, 500))
    }
}
