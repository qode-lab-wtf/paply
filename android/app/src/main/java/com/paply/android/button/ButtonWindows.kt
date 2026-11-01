package com.paply.android.button

/** Settled visibility; exchanges keep the outgoing surface until the next has drawn. */
internal object ButtonWindows {
    enum class Change { KEEP, OPEN, CLOSE }
    data class Visibility(val gripVisible: Boolean, val activeVisible: Boolean,
                          val activeTouchable: Boolean, val hintOnly: Boolean)
    fun visibility(phase: ButtonPolicy.Phase, hint: String?): Visibility {
        val active = phase != ButtonPolicy.Phase.IDLE
        return Visibility(!active, active || hint != null, active, !active && hint != null)
    }
    fun change(wasActive: Boolean, active: Boolean) = when {
        wasActive == active -> Change.KEEP
        active -> Change.OPEN
        else -> Change.CLOSE
    }
}
