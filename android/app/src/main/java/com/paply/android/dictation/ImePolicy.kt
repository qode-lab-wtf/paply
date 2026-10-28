package com.paply.android.dictation

import com.paply.android.MicrophoneBusyException
import com.paply.android.history.HistoryFailure
import java.util.Locale

/** Pure decisions shared by lifecycle/UI code and regression tests. */
internal object ImePolicy {
    const val MAX_MS = 600_000L
    const val WARNING_MS = 540_000L
    fun fieldChanged(restarting: Boolean, sameIdentity: Boolean, rotating: Boolean) =
        !rotating && (!restarting || !sameIdentity)
    fun readback(expected: String, actual: String?): Boolean? {
        fun normalized(s: String) = s.replace(Regex("[\\s\\p{Z}]+"), " ").trim().lowercase(Locale.ROOT)
        return if (actual != null && normalized(actual).endsWith(normalized(expected))) true else null
    }
    fun storageFailure(error: Throwable) = failure(error).takeIf { it == HistoryFailure.STORAGE_FULL } ?: HistoryFailure.STORAGE
    fun failure(error: Throwable): HistoryFailure = when {
        error is MicrophoneBusyException -> HistoryFailure.MICROPHONE_BUSY
        error is KeyAccessException || error is java.security.GeneralSecurityException -> HistoryFailure.KEY
        generateSequence(error) { it.cause }.any { (it is android.system.ErrnoException && it.errno == android.system.OsConstants.ENOSPC) || (it is java.io.IOException && (it.message.orEmpty().contains("ENOSPC") || it.message.orEmpty().contains("No space left on device"))) } -> HistoryFailure.STORAGE_FULL
        error is java.io.IOException || error is StorageAccessException -> HistoryFailure.STORAGE
        else -> HistoryFailure.MICROPHONE
    }
}
internal class KeyAccessException(cause: Throwable? = null) : Exception("key", cause)
internal class StorageAccessException(cause: Throwable? = null) : Exception("storage", cause)

/** Callback state is authoritative between bounded platform refreshes. */
internal class RecordingConfigPoll {
    private var last = Long.MIN_VALUE
    fun due(now: Long): Boolean {
        if (last != Long.MIN_VALUE && now - last < 1000) return false
        last = now
        return true
    }
}
