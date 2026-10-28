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
    /** Call sites pass fixed events, counts, enum names and booleans only. Never exceptions. */
    fun event(event: String) { if (BuildConfig.DEBUG) Log.d("Paply", event) }
}
class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("paply-private", Context.MODE_PRIVATE)
    var directTile: Boolean
        get() = BuildConfig.DEBUG && prefs.getBoolean("directTile", false)
        set(value) { prefs.edit { putBoolean("directTile", BuildConfig.DEBUG && value) } }
}
fun safeError(e: Throwable): String = when (e) {
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
