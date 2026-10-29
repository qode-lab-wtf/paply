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
}
