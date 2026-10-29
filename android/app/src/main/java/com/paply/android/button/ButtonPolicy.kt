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
    // API 33+ keeps the existing IME path; older supported releases use the focused node.
    fun insert(api: Int, sameField: () -> Boolean, commit: () -> Boolean,
               setText: () -> ButtonTextInsertion.Result, paste: () -> Boolean): ButtonTextInsertion.Result {
        if (!sameField()) return ButtonTextInsertion.Result.UNAVAILABLE
        if (api >= 33 && runCatching(commit).getOrDefault(false)) return ButtonTextInsertion.Result.VERIFIED
        if (api in 29..32) {
            val result = runCatching(setText).getOrDefault(ButtonTextInsertion.Result.UNAVAILABLE)
            if (result != ButtonTextInsertion.Result.UNAVAILABLE) return result
        }
        return if (sameField() && runCatching(paste).getOrDefault(false)) ButtonTextInsertion.Result.VERIFIED
            else ButtonTextInsertion.Result.UNAVAILABLE
    }
}
