package com.paply.android.button

import com.paply.android.PaplyIme
import org.junit.Assert.*
import org.junit.Test

class ButtonAcceptanceFixTest {
    private fun choose(field: ButtonPosition.Box, obstacles: List<ButtonPosition.Box> = listOf(field),
                       keyboard: Int = 700, offset: Int = 0) =
        ButtonPosition.choose(8, 392, 24, keyboard, 72, 72, 8, field, obstacles, offset)!!

    @Test fun portraitChat() {
        val field = ButtonPosition.Box(10, 600, 300, 690)
        assertEquals(520, choose(field).top)
        assertEquals(320, choose(field).left)
    }
    @Test fun landscapeSendOnRight() {
        val field = ButtonPosition.Box(10, 50, 300, 190)
        val send = ButtonPosition.Box(310, 110, 392, 190)
        val result = choose(field, listOf(field, send), 200)
        assertEquals(0L, result.overlap(field))
        assertEquals(0L, result.overlap(send))
        assertEquals(24, result.top)
    }
    @Test fun largeEditorAvoidsFieldAtSide() {
        val field = ButtonPosition.Box(10, 24, 300, 690)
        assertEquals(0L, choose(field).overlap(field))
    }
    @Test fun searchAtTopDoesNotPushOntoField() {
        val field = ButtonPosition.Box(10, 24, 392, 80)
        assertEquals(620, choose(field).top)
        assertEquals(0L, choose(field, offset = 999).overlap(field))
    }
    @Test fun noFreeSpacePrioritizesFieldOverControls() {
        val field = ButtonPosition.Box(10, 200, 392, 690)
        val result = choose(field, listOf(ButtonPosition.Box(0, 0, 400, 700)))
        assertEquals(0L, result.overlap(field))
        assertEquals(120, result.top)
    }
    @Test fun completelyCoveredChoosesLeastFieldOverlap() {
        val field = ButtonPosition.Box(0, 24, 400, 700)
        assertNotNull(choose(field))
        assertNull(ButtonPosition.choose(0, 50, 24, 700, 72, 72, 8, field, emptyList()))
    }
    @Test fun animationMustNotCrossControlsOrField() {
        val from = ButtonPosition.Box(0, 0, 72, 72)
        val to = ButtonPosition.Box(0, 200, 72, 272)
        val obstacle = ButtonPosition.Box(0, 100, 72, 150)
        assertFalse(ButtonPosition.clearPath(from, to, obstacle, emptyList()))
        assertFalse(ButtonPosition.clearPath(from, to, null, listOf(obstacle)))
        assertTrue(ButtonPosition.clearPath(from, to, null, emptyList()))
    }
    @Test fun surroundingTextUsesStartOfForwardAndReverseSelection() {
        assertEquals(".", ButtonTextInsertion.beforeSelection(".selected", 1, 9))
        assertEquals(".", ButtonTextInsertion.beforeSelection(".selected", 9, 1))
        assertNull(ButtonTextInsertion.beforeSelection("selected", 0, 8))
        assertNull(ButtonTextInsertion.beforeSelection("", -1, -1))
    }
    @Test fun sharedSpacingForCommitAndSelectionStart() {
        for ((before, text, expected) in listOf(
            Triple("", "Hello", "Hello"), Triple("eight.", "Hello", " Hello"),
            Triple(" ", "Hello", "Hello"), Triple("\n", "Hello", "Hello"),
            Triple("(", "Hello", "Hello"), Triple("word", ",", ","))) {
            assertEquals(expected, PaplyIme.spaced(text, before.takeLast(1)))
            val current = before + "selected"
            assertEquals(before + expected, ButtonTextInsertion.compose(current, before.length,
                current.length, false, text)?.text)
        }
    }
    @Test fun transientLossAndRotationHaveBoundedGrace() {
        assertTrue(ButtonTargetGrace.waiting(100, 1800, 0, false, false))
        assertTrue(ButtonTargetGrace.waiting(1200, 1800, 0, true, false))
        assertFalse(ButtonTargetGrace.waiting(1800, 1800, 0, false, false))
        assertTrue(ButtonTargetGrace.waiting(100, 0, 0, true, false))
        assertFalse(ButtonTargetGrace.waiting(350, 0, 0, true, false))
        assertTrue(ButtonTargetGrace.waiting(1200, 1800, 0, false, true))
        assertFalse(ButtonTargetGrace.waiting(100, 1800, null, true, true))
    }
}
