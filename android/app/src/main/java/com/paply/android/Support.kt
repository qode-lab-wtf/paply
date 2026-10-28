package com.paply.android

import android.content.Context
import android.graphics.Color
import android.util.Log
import android.widget.*
import androidx.core.content.edit
import com.paply.core.GroqFailure

object Brand {
    val green = Color.rgb(0x22, 0xB4, 0x5F)
    val forest = Color.rgb(0x0F, 0x2C, 0x20)
    val text = Color.rgb(0xEE, 0xF5, 0xF0)
    val recordTop = Color.rgb(0x45, 0xE0, 0x86)
    val recordInk = Color.rgb(0x05, 0x21, 0x0F)
    val beak = Color.rgb(0xFF, 0xC2, 0x33)
}
object Diag {
    private val buffer = DiagnosticBuffer()
    /** Release and debug retain the same strictly filtered, process-local measurements. */
    fun event(event: String) {
        val safe = buffer.add(event) ?: return
        if (BuildConfig.DEBUG) Log.d("Paply", safe)
    }
    fun events(): List<String> = buffer.snapshot()
}

internal class DiagnosticBuffer {
    private val events = ArrayDeque<String>()
    @Synchronized fun add(line: String): String? {
        val tokens = line.split(' ')
        val name = tokens.firstOrNull()?.takeIf { it in allowedEvents } ?: return null
        val measurements = tokens.drop(1).mapNotNull { token ->
            val key = token.substringBefore('=')
            val value = token.substringAfter('=', "")
            if (key in allowedFields && (value == "true" || value == "false" ||
                    (number.matches(value) && value.toDoubleOrNull()?.isFinite() == true))) "$key=$value" else null
        }
        val safe = (listOf(name) + measurements).joinToString(" ")
        events.addLast(safe)
        while (events.size > 200) events.removeFirst()
        return safe
    }
    @Synchronized fun snapshot(): List<String> = events.toList().takeLast(200)

    companion object {
        private val number = Regex("[+-]?(?:[0-9]+(?:\\.[0-9]+)?)(?:[eE][+-]?[0-9]+)?")
        private val allowedFields = setOf("ms", "chars", "len", "bytes", "chunks", "voiced", "present", "on",
            "active", "silenced", "isClientSilenced", "audioDeleted", "fileDeleted", "valid", "invalid", "offline",
            "rms", "code", "rate", "usable", "value", "locked", "explicit", "count", "migrated", "sent",
            "tapToCommitMs", "confirmed", "tapToEditorMs", "success", "rebuilding", "panel", "rotation", "restarting",
            "speech", "audio", "totalMs", "flac", "wavBytes", "tokens", "tasks", "links", "parts", "topics",
            "candidates", "attempts", "waitS", "audioS", "textLen", "fallback", "promoted", "visible", "estimate")
        private val allowedEvents = setOf("diagnostics.export", "settings.apiKey", "settings.apiKey.check",
            "audio.start", "audio.interrupted", "audio.rebuilt", "audio.read.error", "audio.sample", "audio.error",
            "audio.trim.skipped", "audio.stop", "audio.released", "audio.flac.fallback", "audio.encode",
            "thought.notification", "thought.transcribe.begin", "thought.structure.begin", "thought.wait.dictation",
            "thought.migration.retained", "tile.click", "thought.recording.started", "thought.nudge", "thought.discard", "thought.handoff.failed",
            "thought.work.begin", "thought.work.end", "thought.work.retry", "thought.work.enqueued", "thoughts.recovered",
            "thought.groq", "thought.groq.ledger", "thought.structure.cached", "thought.transcribe.end",
            "thought.structure.end", "thought.wait", "thought.attention", "thought.empty",
            "ime.panel.created", "ime.field.changed", "ime.editor.start", "ime.recording", "ime.speech.haptic",
            "ime.commit", "ime.editor", "ime.delivery.save.failed", "ime.previous", "ime.hide", "ime.rotation.restored",
            "ime.audio.interrupted", "ime.discard", "dictation.retry", "dictation.saved", "dictation.recovery.failed",
            "network.changed")
    }
}
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("paply-private", Context.MODE_PRIVATE)
    var directTile: Boolean
        get() = BuildConfig.DEBUG && prefs.getBoolean("directTile", false)
        set(value) { prefs.edit { putBoolean("directTile", BuildConfig.DEBUG && value) } }
}
fun safeError(e: Throwable): String = when (e) {
    is MicrophoneBusyException -> "Mikro belegt · beende zuerst die andere Aufnahme."
    is SecurityException -> "Mikrofonzugriff nicht erlaubt. Bitte Paply einrichten."
    is GroqFailure -> when(e.status) {
        401, 403 -> "Groq-Schlüssel prüfen."
        429 -> "Groq-Limit erreicht. Später erneut versuchen."
        else -> "Verarbeitung fehlgeschlagen. Bitte erneut versuchen."
    }
    else -> "Aufnahme nicht möglich. Bitte Berechtigungen und Groq-Schlüssel prüfen."
}
fun Context.dp(value: Int) = (value * resources.displayMetrics.density).toInt()
fun Context.label(value: String, size: Float = 18f) = TextView(this).apply {
    text = value; textSize = size; setTextColor(Brand.text); setPadding(dp(4), dp(10), dp(4), dp(10))
}
fun Context.button(value: String, action: () -> Unit) = Button(this).apply { text = value; setOnClickListener { action() } }
fun Context.column() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(20), dp(20), dp(20), dp(20)); setBackgroundColor(Brand.forest) }
