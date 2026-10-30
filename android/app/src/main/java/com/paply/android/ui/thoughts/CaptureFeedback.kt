package com.paply.android.ui.thoughts

/** Presentation only: never changes recording, background processing or persisted errors. */
internal data class CaptureFeedback(val text: String, val saved: Boolean = false, val hideAfterMs: Long? = null)

internal fun captureFeedback(phase: String, message: String, requiresAction: Boolean = false): CaptureFeedback {
    if (phase in listOf("starting", "recording", "stopping") || requiresAction || message.isBlank()) {
        return CaptureFeedback(message)
    }
    // Audio is already durable here; processing may continue after the card closes.
    val saved = message == "Gedanke gespeichert" || message.startsWith("Gedanke gesichert")
    return CaptureFeedback(if (saved) "Gedanke gesichert" else message, saved, if (saved) 1900 else 3500)
}
