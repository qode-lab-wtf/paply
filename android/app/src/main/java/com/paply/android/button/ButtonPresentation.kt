package com.paply.android.button

/** Pure decisions shared by service rendering and regression tests. */
internal object ButtonPresentation {
    fun deliveryMessage(accepted: Boolean, retained: Boolean, copied: Boolean,
                        clipboardFallback: Boolean, review: Boolean): String? {
        val message = when {
            review -> "Textfeld nimmt Text nicht sicher an. Bitte prüfen."
            !retained && !accepted -> if (copied) "Text in Zwischenablage. Jetzt einfügen; Verlauf nicht gespeichert."
                else "Text konnte nicht gesichert werden. Bitte erneut versuchen."
            accepted -> null
            copied || clipboardFallback -> "Text in Zwischenablage. Feld lange drücken → Einfügen."
            else -> "Text nur im Verlauf. Dort kopieren und einsetzen."
        }
        return if (clipboardFallback) listOfNotNull("Text auch in der Zwischenablage", message).joinToString(". ") else message
    }

    data class Render(val sizeDp: Int, val hint: String?, val cancel: Boolean, val phase: ButtonPolicy.Phase)
    fun render(phase: ButtonPolicy.Phase, hint: String?) = Render(
        if (phase == ButtonPolicy.Phase.IDLE) 56 else 72, hint,
        phase == ButtonPolicy.Phase.STARTING || phase == ButtonPolicy.Phase.RECORDING, phase)
}

internal class ButtonRecordingWarning {
    enum class Event { NONE, MINUTE, LIMIT }
    private var warned = false
    private var ended = false
    fun observe(elapsed: Long, limitReached: Boolean = false): Event = when {
        !ended && (limitReached || elapsed >= 600_000) -> { ended = true; warned = true; Event.LIMIT }
        !warned && elapsed >= 540_000 -> { warned = true; Event.MINUTE }
        else -> Event.NONE
    }
    fun amber(elapsed: Long) = elapsed >= 540_000
}
