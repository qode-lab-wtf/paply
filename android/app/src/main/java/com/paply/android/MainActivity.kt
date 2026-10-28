package com.paply.android

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import android.text.InputType
import android.view.inputmethod.InputMethodManager
import android.widget.*
import kotlinx.coroutines.*

class MainActivity : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var list: LinearLayout
    private lateinit var status: TextView
    private var retrying = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = column()
        // Target 37 draws edge-to-edge; keep setup controls clear of system bars.
        root.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars())
                view.setPadding(dp(20), dp(20) + bars.top, dp(20), dp(20) + bars.bottom)
            } else {
                @Suppress("DEPRECATION")
                view.setPadding(dp(20), dp(20) + insets.systemWindowInsetTop, dp(20), dp(20) + insets.systemWindowInsetBottom)
            }
            insets
        }
        root.addView(label("Paply", 32f))
        root.addView(label("Deine Stimme. Deine Worte.", 17f))
        root.addView(button("Mikro erlauben") { requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1) })
        root.addView(button("Benachrichtigungen erlauben") {
            if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2)
        })
        root.addView(button("Tastatur aktivieren") { startActivity(Intent(AndroidSettings.ACTION_INPUT_METHOD_SETTINGS)) })
        root.addView(button("Tastatur auswählen") { getSystemService(InputMethodManager::class.java).showInputMethodPicker() })
        val key = EditText(this).apply {
            hint = if (Settings(this@MainActivity).apiKey.isBlank()) "Groq-Schlüssel" else "Groq-Schlüssel gespeichert · ersetzen"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            setSingleLine(true)
        }
        root.addView(key)
        root.addView(button("Schlüssel speichern") {
            if (key.text.isNotBlank()) {
                Settings(this).apiKey = key.text.toString(); key.text.clear(); key.hint = "Groq-Schlüssel gespeichert"
            }
        })
        root.addView(label("Testfeld", 17f))
        root.addView(EditText(this).apply {
            hint = "Hier Paply als Tastatur wählen"; minLines = 2
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        })
        root.addView(button("Gedankenaufnahme öffnen") { startActivity(Intent(this, CaptureActivity::class.java)) })
        if (BuildConfig.DEBUG) root.addView(Switch(this).apply {
            text = getString(R.string.debug_direct_tile); isChecked = Settings(this@MainActivity).directTile
            setOnCheckedChangeListener { _, checked -> Settings(this@MainActivity).directTile = checked }
        })
        status = label("", 14f); root.addView(status)
        root.addView(label("Gedanken", 24f))
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }; root.addView(list)
        setContentView(ScrollView(this).apply { addView(root) })
        scope.launch { ThoughtState.current.collect { status.text = it.message; refreshThoughts() } }
    }
    override fun onResume() { super.onResume(); refreshThoughts() }
    private fun refreshThoughts() {
        if (!::list.isInitialized) return
        list.removeAllViews()
        val store = ThoughtStore(this)
        val entries = store.entries()
        if (entries.isEmpty()) list.addView(label("Noch keine Gedanken.", 16f))
        entries.forEach { entry ->
            val date = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT, java.text.DateFormat.SHORT).format(java.util.Date(entry.getLong("createdAt")))
            list.addView(label(date, 13f)); list.addView(label(entry.getString("text"), 18f))
        }
        val interrupted = store.interrupted()
        if (interrupted.isNotEmpty() && !ThoughtState.active) {
            list.addView(label("${interrupted.size} unterbrochene Aufnahme(n), ohne bestätigte Mikrofonprüfung. Werden nicht gesendet.", 14f))
            list.addView(button("Unterbrochene Aufnahmen löschen") { interrupted.forEach { store.discard(it) }; refreshThoughts() })
        }
        val pending = store.pending()
        if (pending.isNotEmpty() && !ThoughtState.active) {
            list.addView(label("${pending.size} Aufnahme(n) warten auf Verarbeitung.", 14f))
            list.addView(button(if (retrying) "Verarbeitung läuft …" else "Erneut versuchen") {
                if (retrying) return@button
                retrying = true
                scope.launch {
                    try {
                        for (file in pending) {
                            val duration = store.durationMs(file)
                            val raw = Settings(this@MainActivity).client().transcribe(file, duration / 1000.0)
                            if (raw.text.isNotBlank()) withContext(Dispatchers.IO) { store.save(file, raw.text, duration) }
                        }
                        status.setText(R.string.saved)
                    } catch (e: CancellationException) { throw e
                    } catch (e: Exception) { status.text = safeError(e)
                    } finally { retrying = false; refreshThoughts() }
                }
            })
            list.addView(button("Wartende Aufnahmen verwerfen") { if (!retrying) { pending.forEach { store.discard(it) }; refreshThoughts() } })
        }
    }
    override fun onDestroy() { scope.cancel(); super.onDestroy() }
}
