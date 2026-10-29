package com.paply.android.button

import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import com.paply.android.PaplyIme
import java.util.Locale

/** Field contents exist only for this insertion attempt; never persist or log them. */
internal object ButtonTextInsertion {
    const val MAX_FIELD_LENGTH = 5000
    enum class Result { VERIFIED, REVIEW, UNAVAILABLE }
    data class Edit(val text: String, val cursor: Int)

    fun compose(text: String, start: Int, end: Int, hint: Boolean, dictated: String): Edit? {
        val current = if (hint) "" else text
        if (current.length > MAX_FIELD_LENGTH || dictated.isBlank()) return null
        val from = if (hint || current.isEmpty()) 0 else minOf(start, end)
        val to = if (hint || current.isEmpty()) 0 else maxOf(start, end)
        if (from < 0 || to > current.length) return null
        val before = current.substring(0, from)
        val inserted = PaplyIme.spaced(dictated, before)
        return Edit(before + inserted + current.substring(to), before.length + inserted.length)
    }

    fun verified(expected: String, actual: String?): Boolean {
        fun normalize(value: String) = value.lowercase(Locale.ROOT).filterNot { it.isWhitespace() }
        return actual != null && normalize(expected) == normalize(actual)
    }

    fun apply(edit: Edit, setText: (String) -> Boolean, setSelection: (Int) -> Boolean,
              readBack: () -> String?): Result {
        if (!runCatching { setText(edit.text) }.getOrDefault(false)) return Result.UNAVAILABLE
        // SET_TEXT already changed the field. Neither cursor failures nor uncertain
        // readback may trigger another insertion (or overwrite the clipboard).
        runCatching { setSelection(edit.cursor) }
        return if (runCatching { verified(edit.text, readBack()) }.getOrDefault(false))
            Result.VERIFIED else Result.REVIEW
    }

    fun insert(node: AccessibilityNodeInfo?, dictated: String): Result {
        if (node == null || !node.refresh() || !node.isFocused || !node.isEditable || node.isPassword) return Result.UNAVAILABLE
        val edit = compose(node.text?.toString().orEmpty(), node.textSelectionStart,
            node.textSelectionEnd, node.isShowingHintText, dictated) ?: return Result.UNAVAILABLE
        return apply(edit, { text ->
            node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            })
        }, { cursor ->
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, cursor)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, cursor)
            })
        }, {
            if (node.refresh() && node.isFocused && node.isEditable && !node.isPassword)
                node.text?.toString() else null
        })
    }
}
