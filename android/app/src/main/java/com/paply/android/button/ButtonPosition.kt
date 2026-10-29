package com.paply.android.button

/** All inputs and outputs are physical screen pixels, including the IME bounds. */
internal object ButtonPosition {
    data class Horizontal(val width: Int, val rightMargin: Int)
    fun horizontal(screenWidth: Int, safeLeft: Int, safeRight: Int, margin: Int): Horizontal =
        Horizontal((screenWidth - safeLeft - safeRight - 2 * margin).coerceAtLeast(0), safeRight + margin)

    /** Screen coordinates; only compact editors adjacent to the keyboard get a field anchor. */
    fun anchor(keyboardTop: Int, fieldTop: Int?, fieldBottom: Int?, safeTop: Int,
               height: Int, gap: Int, proximity: Int, maxFieldHeight: Int): Int =
        if (fieldTop != null && fieldBottom != null &&
            fieldBottom >= fieldTop && fieldBottom - fieldTop <= maxFieldHeight &&
            keyboardTop - fieldBottom in 0..proximity && fieldTop - height - gap >= safeTop)
            fieldTop else keyboardTop

    fun maxOffset(anchor: Int, safeTop: Int, height: Int, gap: Int): Int =
        (anchor - gap - height - safeTop).coerceAtLeast(0)

    data class Insets(val top: Int, val left: Int, val right: Int)
    fun safeInsets(top: Int, left: Int, right: Int, cutTop: Int, cutLeft: Int, cutRight: Int) =
        Insets(maxOf(top, cutTop), maxOf(left, cutLeft), maxOf(right, cutRight))

    fun top(keyboardTop: Int, safeTop: Int, height: Int, gap: Int, offset: Int): Int? {
        val bottommost = keyboardTop - gap - height
        if (bottommost < safeTop) return null
        return (bottommost - offset.coerceAtLeast(0)).coerceIn(safeTop, bottommost)
    }
}
