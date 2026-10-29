package com.paply.android.button

import org.junit.Assert.*
import org.junit.Test

class ButtonTextInsertionTest {
    private fun edit(text: String, start: Int, end: Int = start, dictated: String = "neu", hint: Boolean = false) =
        ButtonTextInsertion.compose(text, start, end, hint, dictated)!!
    @Test fun cursorAtBeginningMiddleAndEnd() {
        assertEquals(ButtonTextInsertion.Edit("neuHallo", 3), edit("Hallo", 0))
        assertEquals(ButtonTextInsertion.Edit("Hallo neu Welt", 9), edit("Hallo Welt", 5))
        assertEquals(ButtonTextInsertion.Edit("Hallo neu", 9), edit("Hallo", 5))
    }
    @Test fun replacesSelectionIncludingReversedSelection() {
        assertEquals(ButtonTextInsertion.Edit("Hallo neu Welt", 9), edit("Hallo alte Welt", 6, 10))
        assertEquals(edit("Hallo alte Welt", 6, 10), edit("Hallo alte Welt", 10, 6))
    }
    @Test fun emptyHintAndUnavailableSelection() {
        assertEquals(ButtonTextInsertion.Edit("neu", 3), edit("Hinweis", -1, hint = true))
        assertEquals(ButtonTextInsertion.Edit("neu", 3), edit("", -1))
        assertNull(ButtonTextInsertion.compose("privat", -1, -1, false, "neu"))
    }
    @Test fun spacingMatchesIme() {
        for ((before, dictated, expected) in listOf(
            Triple("Hallo ", "neu", "Hallo neu"), Triple("Hallo", ", Welt", "Hallo, Welt"),
            Triple("(", "neu", "(neu"), Triple("Hallo", " neu", "Hallo neu"),
            Triple("Hallo\n", "neu", "Hallo\nneu"))) {
            assertEquals(expected, edit(before, before.length, dictated = dictated).text)
        }
    }
    @Test fun lengthBoundary() {
        assertNotNull(ButtonTextInsertion.compose("a".repeat(5000), 5000, 5000, false, "neu"))
        assertNull(ButtonTextInsertion.compose("a".repeat(5001), 0, 0, false, "neu"))
    }
    @Test fun verificationRejectsTruncationAndUnchangedField() {
        assertTrue(ButtonTextInsertion.verified("Hallo neu Welt", "HALLO  neu\nWelt"))
        assertFalse(ButtonTextInsertion.verified("Hallo neu Welt", "Hallo neu"))
        assertFalse(ButtonTextInsertion.verified("Hallo neu Welt", "Hallo Welt"))
        assertFalse(ButtonTextInsertion.verified("Hallo neu Welt", null))
    }
    @Test fun actionsAndReadbackAreOrderedAndFailuresFallBack() {
        val edit = edit("Hallo", 5)
        val calls = mutableListOf<String>()
        assertTrue(ButtonTextInsertion.apply(edit, { calls += "text"; it == edit.text },
            { calls += "cursor"; it == 9 }, { calls += "read"; "HALLO NEU" }))
        assertEquals(listOf("text", "cursor", "read"), calls)
        assertFalse(ButtonTextInsertion.apply(edit, {false}, {error("selection")}, {error("read")}))
        assertFalse(ButtonTextInsertion.apply(edit, {true}, {true}, {"Hallo"}))
        assertFalse(ButtonTextInsertion.apply(edit, {true}, {false}, {edit.text}))
    }
}
