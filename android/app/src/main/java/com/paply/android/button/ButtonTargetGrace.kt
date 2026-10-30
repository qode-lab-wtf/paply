package com.paply.android.button

/** Rotation can temporarily remove both the input window and its accessibility node. */
internal object ButtonTargetGrace {
    fun waiting(now: Long, rotationUntil: Long, missingSince: Long?, eligible: Boolean, same: Boolean): Boolean =
        (!same || !eligible) && now < rotationUntil ||
            (missingSince != null && now - missingSince < 350)
}
