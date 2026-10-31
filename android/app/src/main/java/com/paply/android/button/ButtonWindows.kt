package com.paply.android.button

/** Desired owner; the service keeps the old surface until the new one has drawn. */
internal object ButtonWindows {
    enum class Change { KEEP, OPEN, CLOSE }
    fun active(phase: ButtonPolicy.Phase, hint: String?) = phase != ButtonPolicy.Phase.IDLE || hint != null
    fun change(wasActive: Boolean, active: Boolean) = when {
        wasActive == active -> Change.KEEP
        active -> Change.OPEN
        else -> Change.CLOSE
    }
}
