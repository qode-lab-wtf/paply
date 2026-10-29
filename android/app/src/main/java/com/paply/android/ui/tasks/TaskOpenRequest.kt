package com.paply.android.ui.tasks

/** A new request must navigate even when the user opens the same task again after going back. */
data class TaskOpenRequest(val thoughtID: String, val taskID: String, val requestID: Long = System.nanoTime()) {
    private val consumed = java.util.concurrent.atomic.AtomicBoolean(false)
    fun claim(): Boolean = consumed.compareAndSet(false, true)
}
