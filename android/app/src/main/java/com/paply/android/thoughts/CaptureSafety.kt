package com.paply.android.thoughts

import com.paply.android.CaptureResult
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Cache only successful initialization; a failed disk read must remain retryable. */
internal class RetryableReady<T : Any>(private val initialize: suspend () -> T) {
    private val mutex = Mutex()
    private var value: T? = null
    suspend fun get(): T = mutex.withLock { value ?: initialize().also { value = it } }
}

internal class VisibilityCache {
    private var checkedAt = Long.MIN_VALUE
    private var value = false
    @Synchronized fun invalidate() { checkedAt = Long.MIN_VALUE }
    @Synchronized fun get(now: Long, query: () -> Boolean): Boolean {
        if (checkedAt == Long.MIN_VALUE || now - checkedAt >= 1000) {
            value = query(); checkedAt = now
        }
        return value
    }
}

/** A repost can appear asynchronously; absence on the following tick ends capture. */
internal class RecordingVisibilityGuard {
    private var repostAt: Long? = null
    fun dismissed(now: Long, repost: () -> Unit): Boolean = runCatching {
        repost(); repostAt = now; true
    }.getOrDefault(false)
    fun check(now: Long, cardVisible: Boolean, allowed: () -> Boolean,
        posted: () -> Boolean, repost: () -> Unit): Boolean = runCatching {
        if (!allowed()) return@runCatching cardVisible
        if (posted()) { repostAt = null; return@runCatching true }
        val pending = repostAt
        if (pending != null) return@runCatching now - pending < 500
        repost(); repostAt = now
        true
    }.getOrDefault(false)
}

internal fun captureEndMessage(discard: Boolean, result: CaptureResult) = when {
    discard -> "Verworfen"
    result.durationMs <= 0 && result.file.length() <= 44 -> "Nichts gespeichert"
    !result.usable && result.error == null -> "Nichts gespeichert"
    else -> "Gedanke gesichert · wird geordnet"
}
