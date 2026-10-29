package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonPositionTest {
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
