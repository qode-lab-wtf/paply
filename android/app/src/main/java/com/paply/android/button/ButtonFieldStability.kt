package com.paply.android.button

import kotlin.math.abs

/** Hold the last accepted position while a growing editor settles (like the IME, 150 ms).
 * Tolerance also permits settling when accessibility reports a few pixels of jitter. */
internal class ButtonFieldStability(private val tolerance: Int) {
    private var candidate: Int? = null
    private var since = 0L
    var top: Int? = null; private set

    fun reset() { candidate = null; top = null; since = 0L }

    fun observe(next: Int?, now: Long) {
        if (next == null) { reset(); return }
        val pending = candidate
        if (pending == null || abs(next - pending) > tolerance) {
            candidate = next
            since = now
        }
        if (now - since >= 150 && (top == null || abs(candidate!! - top!!) > tolerance)) {
            top = candidate
        }
    }
}
