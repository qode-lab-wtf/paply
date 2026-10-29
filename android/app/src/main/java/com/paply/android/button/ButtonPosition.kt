package com.paply.android.button

/** All inputs and outputs are physical screen pixels, including the IME bounds. */
internal object ButtonPosition {
    data class Horizontal(val width: Int, val rightMargin: Int)
    fun horizontal(screenWidth: Int, safeLeft: Int, safeRight: Int, margin: Int): Horizontal =
        Horizontal((screenWidth - safeLeft - safeRight - 2 * margin).coerceAtLeast(0), safeRight + margin)

    fun top(keyboardTop: Int, safeTop: Int, height: Int, gap: Int, offset: Int): Int? {
        val bottommost = keyboardTop - gap - height
        if (bottommost < safeTop) return null
        return (bottommost - offset.coerceAtLeast(0)).coerceIn(safeTop, bottommost)
    }
}
