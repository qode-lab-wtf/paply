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
    @Test fun fullFieldInsertionNeverPastesAfterSetText() {
        for ((initial, start, end, hint, expected) in listOf(
            Case("", -1, -1, false, "neu"),
            Case("Hinweis", -1, -1, true, "neu"),
            Case("Hallo", 5, 5, false, "Hallo neu"),
            Case("Hallo Welt", 5, 5, false, "Hallo neu Welt"),
            Case("Hallo alte Welt", 6, 10, false, "Hallo neu Welt"))) {
            for (selectionAccepted in listOf(false, true)) {
                var field = initial
                var clipboard = "Vorheriger Clip"
                var writes = 0
                val edit = edit(initial, start, end, hint = hint)
                val result = ButtonPolicy.insert(30, {true}, {error("commit")}, {
                    ButtonTextInsertion.apply(edit, { field = it; writes++; true },
                        { selectionAccepted }, {field})
                }, { clipboard = "neu"; field += "neu"; true })
                assertEquals(ButtonTextInsertion.Result.VERIFIED, result)
                assertEquals(expected, field)
                assertEquals(1, writes)
                assertEquals("Vorheriger Clip", clipboard)
            }
        }
    }
    private data class Case(val initial: String, val start: Int, val end: Int,
                            val hint: Boolean, val expected: String)

    @Test fun rejectedSetTextAloneAllowsClipboardFallback() {
        var field = "Hallo"
        var clipboard = "Vorheriger Clip"
        val result = ButtonPolicy.insert(30, {true}, {error("commit")}, {
            ButtonTextInsertion.apply(edit(field, 5), {false}, {error("selection")}, {error("read")})
        }, { clipboard = "neu"; field += " neu"; true })
        assertEquals(ButtonTextInsertion.Result.VERIFIED, result)
        assertEquals("Hallo neu", field)
        assertEquals("neu", clipboard)
    }

    @Test fun unexpectedOrUnavailableReadbackNeverPastesAgain() {
        for (actual in listOf("Hallo", "Hallo anders", null)) {
            var field = "Hallo"
            var writes = 0
            val result = ButtonPolicy.insert(30, {true}, {error("commit")}, {
                ButtonTextInsertion.apply(edit(field, 5), { field = actual.orEmpty(); writes++; true },
                    {false}, {actual})
            }, {error("Must not paste or touch clipboard after accepted SET_TEXT")})
            assertEquals(ButtonTextInsertion.Result.REVIEW, result)
            assertEquals(actual.orEmpty(), field)
            assertEquals(1, writes)
        }
    }

    @Test fun cursorAndReadbackExceptionsCannotUndoAcceptedWrite() {
        val edit = edit("Hallo", 5)
        assertEquals(ButtonTextInsertion.Result.VERIFIED,
            ButtonTextInsertion.apply(edit, {true}, {error("unsupported selection")}, {edit.text}))
        assertEquals(ButtonTextInsertion.Result.REVIEW,
            ButtonTextInsertion.apply(edit, {true}, {true}, {error("stale node")}))
    }

    @Test fun actionsAndReadbackAreOrdered() {
        val edit = edit("Hallo", 5)
        val calls = mutableListOf<String>()
        assertEquals(ButtonTextInsertion.Result.VERIFIED, ButtonTextInsertion.apply(edit,
            { calls += "text"; it == edit.text }, { calls += "cursor"; it == 9 },
            { calls += "read"; "HALLO NEU" }))
        assertEquals(listOf("text", "cursor", "read"), calls)
    }
}
