package com.paply.android.button

internal object ButtonPolicy {
    fun visible(enabled: Boolean, focused: Boolean, editable: Boolean, password: Boolean, keyboard: Boolean) =
        enabled && focused && editable && !password && keyboard
    enum class Phase { IDLE, STARTING, RECORDING, WORKING }
    enum class Event { START, READY, FINISH, DISCARD, SILENCE, ERROR, FIELD_CHANGE, RESULT }
    fun next(phase: Phase, event: Event): Phase = when (event) {
        Event.START -> if (phase == Phase.IDLE) Phase.STARTING else phase
        Event.READY -> if (phase == Phase.STARTING) Phase.RECORDING else phase
        Event.FINISH, Event.FIELD_CHANGE -> if (phase == Phase.RECORDING) Phase.WORKING else phase
        else -> Phase.IDLE
    }
    // An IPC acknowledgement cannot be verified without reading private field contents.
    fun insert(api: Int, sameField: () -> Boolean, commit: () -> Boolean, paste: () -> Boolean): Boolean {
        if (!sameField()) return false
        if (api >= 33 && runCatching(commit).getOrDefault(false)) return true
        return sameField() && runCatching(paste).getOrDefault(false)
    }
}
