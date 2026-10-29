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
    data class Box(val left: Int, val top: Int, val right: Int, val bottom: Int) {
        fun overlap(other: Box): Long = (minOf(right, other.right) - maxOf(left, other.left)).coerceAtLeast(0).toLong() *
            (minOf(bottom, other.bottom) - maxOf(top, other.top)).coerceAtLeast(0)
    }

    /** Ordered candidates; field avoidance takes precedence even when no completely free slot exists. */
    fun choose(left: Int, right: Int, safeTop: Int, keyboardTop: Int, width: Int, height: Int,
               gap: Int, field: Box?, obstacles: List<Box>, offset: Int = 0, fieldAnchorTop: Int? = field?.top): Box? {
        val bottommost = keyboardTop - gap - height
        if (bottommost < safeTop || width > right - left) return null
        val candidates = mutableListOf<Box>()
        fun add(y: Int) {
            if (y < safeTop) return
            val top = (y - offset.coerceAtLeast(0)).coerceIn(safeTop, bottommost)
            for (x in listOf(right - width, left)) candidates += Box(x, top, x + width, top + height)
        }
        fieldAnchorTop?.let { add(it - gap - height) }
        add(bottommost)
        var y = bottommost - height - gap
        while (y >= safeTop) { add(y); y -= height + gap }
        add(safeTop)
        // Also fit narrow free strips between controls, beyond the regular edge steps.
        (obstacles + listOfNotNull(field)).forEach { add(it.top - gap - height) }
        if (offset > 0) {
            choose(left, right, safeTop, keyboardTop, width, height, gap, field, obstacles, 0, fieldAnchorTop)?.let { candidates += it }
        }
        return candidates.distinct().minWithOrNull(compareBy<Box>(
            { field?.overlap(it) ?: 0L }, { candidate -> obstacles.sumOf { it.overlap(candidate) } }))
    }

    fun clearPath(from: Box, to: Box, field: Box?, obstacles: List<Box>): Boolean {
        val swept = Box(minOf(from.left, to.left), minOf(from.top, to.top),
            maxOf(from.right, to.right), maxOf(from.bottom, to.bottom))
        return (field?.overlap(swept) ?: 0L) == 0L && obstacles.none { it.overlap(swept) > 0 }
    }
}
