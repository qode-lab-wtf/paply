package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonPositionTest {
    @Test fun pillGrowsLeftAndStaysWithinBothScreenMargins() {
        for (screen in listOf(120, 240, 320, 1080, 2400)) {
            for (inset in listOf(0, 12, 24)) {
                val bounds = ButtonPosition.horizontal(screen, inset, inset, 8)
                for (desiredWidth in listOf(44, 180, 500, 10000)) {
                    val width = desiredWidth.coerceAtMost(bounds.width)
                    val right = screen - bounds.rightMargin
                    assertTrue(right <= screen - inset - 8)
                    assertTrue(right - width >= inset + 8)
                }
            }
        }
    }
    @Test fun screenCoordinatesStayAboveImeWithInsetsAndDrag() {
        // Portrait API-34 reproduction, landscape, cutout and larger density.
        for ((top, safe, height, gap) in listOf(listOf(1517, 63, 115, 21),
            listOf(650, 24, 44, 8), listOf(520, 90, 88, 16), listOf(1800, 120, 132, 24))) {
            assertEquals(top - height - gap, ButtonPosition.top(top, safe, height, gap, 0))
            for (offset in listOf(-500, 0, 100, 10000)) {
                val y = ButtonPosition.top(top, safe, height, gap, offset)!!
                assertTrue(y >= safe)
                assertTrue(y + height + gap <= top)
            }
        }
        assertNull(ButtonPosition.top(100, 80, 44, 8, 0))
    }
    private fun anchor(top: Int?, bottom: Int?, keyboard: Int = 760, safe: Int = 24) =
        ButtonPosition.anchor(keyboard, top, bottom, safe, 72, 8, 96, 200)
    @Test fun compactFieldsUseFieldAnchorInPortraitAndLandscape() {
        assertEquals(700, anchor(700, 750))
        assertEquals(580, anchor(580, 750))
        assertEquals(550, anchor(550, 750)) // exactly 200 dp
        assertEquals(760, anchor(549, 750))
        assertEquals(160, anchor(160, 220, keyboard = 260)) // landscape, keyboard at midpoint
        assertEquals(760, anchor(40, 90)) // search bar
        assertEquals(260, anchor(160, 220, keyboard = 260, safe = 100))
        assertEquals(760, anchor(null, null))
        assertEquals(760, anchor(900, 950))
        assertEquals(600, anchor(600, 664)) // exactly 96 dp
        assertEquals(760, anchor(600, 663))
    }
    @Test fun dragUsesCurrentAnchorRange() {
        assertEquals(596, ButtonPosition.maxOffset(700, 24, 72, 8))
        assertEquals(24, ButtonPosition.top(700, 24, 72, 8, 596))
        assertEquals(0, ButtonPosition.maxOffset(80, 24, 72, 8))
    }
    @Test fun screenInsetsCombineBarsAndCutout() {
        assertEquals(ButtonPosition.Insets(40, 60, 48), ButtonPosition.safeInsets(24, 0, 48, 40, 60, 0))
        val safe = ButtonPosition.safeInsets(24, 48, 0, 0, 0, 60)
        assertEquals(ButtonPosition.Horizontal(676, 68), ButtonPosition.horizontal(800, safe.left, safe.right, 8))
    }
}
