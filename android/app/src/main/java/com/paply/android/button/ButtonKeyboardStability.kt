package com.paply.android.button

import android.graphics.Rect

internal class ButtonKeyboardStability {
    private var bounds: List<Rect>? = null
    private var since = 0L
    fun observe(next: List<Rect>, now: Long): Boolean {
        if (bounds != next) {
            bounds = next.map(::Rect)
            since = now
        }
        return next.isNotEmpty() && now - since >= 150
    }
}
