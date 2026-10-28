package com.paply.android.settings

import android.annotation.SuppressLint
import android.content.Context
import android.view.inputmethod.InputMethodManager
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.Serializer
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Immutable settings captured once at recording start. No suspending accessor in the keyboard. */
data class DictationPrefs(
    val mainLanguage: String,
    val languages: List<String>,
    val vocabulary: String,
    val transcriptionModel: String,
    val chunkUpload: Boolean,
)

data class AppPreferences(
    val automaticLanguages: Boolean = true,
    val detectedLanguages: List<String> = listOf(Locale.getDefault().language),
    val manualLanguages: List<String> = emptyList(),
    val mainLanguage: String? = null,
    val vocabulary: String = "",
    val transcriptionModel: String = "whisper-large-v3",
    val chunkUpload: Boolean = true,
    val betaThoughts: Boolean = true,
    val developerMode: Boolean = false,
    val tileAdded: Boolean = false,
    internal val revision: Long = 0,
) {
    val languages: List<String> get() = if (automaticLanguages) detectedLanguages else manualLanguages
    fun dictationPrefs(): DictationPrefs = DictationPrefs(
        mainLanguage?.takeIf { it in languages } ?: Locale.getDefault().language.takeIf { it in languages }
            ?: languages.firstOrNull() ?: Locale.getDefault().language,
        languages.toList(), vocabulary, transcriptionModel, chunkUpload,
    )
}

/** One process-wide DataStore. Initial small local read happens once; snapshot() never waits for IO. */
class SettingsRepository private constructor(context: Context) {
    private val app = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val file = File(app.filesDir, "datastore/paply-settings.json")
    private val mutableError = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = mutableError.asStateFlow()
    private val initial = try {
        if (file.exists()) decode(file.readText()) else AppPreferences(detectedLanguages = detectLanguages())
    } catch (_: Exception) {
        mutableError.value = "Einstellungen konnten nicht gelesen werden. Bitte Paply neu öffnen."
        AppPreferences(detectedLanguages = detectLanguages())
    }
    private val mutableState = MutableStateFlow(initial)
    val state: StateFlow<AppPreferences> = mutableState.asStateFlow()
    private val store = DataStoreFactory.create(serializer = object : Serializer<AppPreferences> {
        override val defaultValue = initial
        override suspend fun readFrom(input: InputStream): AppPreferences = decode(input.readBytes().toString(Charsets.UTF_8))
        override suspend fun writeTo(t: AppPreferences, output: OutputStream) {
            output.write(encode(t).toByteArray(Charsets.UTF_8))
        }
    }, scope = scope, produceFile = { file })

    init {
        scope.launch {
            store.data.catch { mutableError.value = "Einstellungen konnten nicht gelesen werden. Bitte Paply neu öffnen." }
                .collect { publish(it) }
        }
    }

    /** Ready immediately after get(context), including after process death. Does not read the disk. */
    fun snapshot(): DictationPrefs = state.value.dictationPrefs()

    /** A completed call is persisted; concurrent edits are serialized by DataStore. */
    suspend fun update(transform: (AppPreferences) -> AppPreferences) {
        val saved = store.updateData { current ->
            val next = transform(current)
            if (next == current) current else next.copy(revision = current.revision + 1)
        }
        publish(saved)
        mutableError.value = null
    }

    private fun publish(next: AppPreferences) {
        // A delayed collector emission must never overwrite a newer completed update.
        mutableState.update { current -> if (next.revision >= current.revision) next else current }
    }

    suspend fun refreshDetectedLanguages() {
        val languages = detectLanguages()
        update { it.copy(detectedLanguages = languages) }
    }

    private fun detectLanguages(): List<String> {
        val locales = app.resources.configuration.locales
        val values = (0 until locales.size()).map { locales[it].language }.toMutableList()
        val manager = app.getSystemService(InputMethodManager::class.java)
        manager.enabledInputMethodList.forEach { ime ->
            manager.getEnabledInputMethodSubtypeList(ime, true).forEach { subtype ->
                val tag = subtype.languageTag.ifBlank {
                    @Suppress("DEPRECATION") val legacy = subtype.locale
                    legacy
                }
                values.add(tag.substringBefore('-').substringBefore('_').lowercase(Locale.ROOT))
            }
        }
        val result = values.filter { it.length in 2..3 && it.all(Char::isLetter) && it !in listOf("mul", "und", "zxx") }.distinct().toMutableList()
        if (result.isEmpty()) result.add(Locale.getDefault().language)
        if (result.size == 1 && result.first() != "en") result.add("en")
        return result
    }

    companion object {
        @SuppressLint("StaticFieldLeak") // Holds only applicationContext, never an Activity.
        @Volatile private var instance: SettingsRepository? = null
        fun get(context: Context): SettingsRepository = instance ?: synchronized(this) {
            instance ?: SettingsRepository(context).also { instance = it }
        }
        val commonLanguages = listOf("de", "en", "fr", "es", "it", "pt", "nl", "tr", "pl")
        fun languageName(code: String): String = Locale.forLanguageTag(code).getDisplayLanguage(Locale.GERMAN)
            .replaceFirstChar { it.titlecase(Locale.GERMAN) }

        private fun decode(text: String): AppPreferences {
            val o = JSONObject(text)
            fun list(key: String): List<String> = o.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getString(it) } }.orEmpty()
            return AppPreferences(o.optBoolean("automaticLanguages", true), list("detectedLanguages"), list("manualLanguages"),
                o.optString("mainLanguage").takeIf { it.isNotBlank() }, o.optString("vocabulary"),
                o.optString("transcriptionModel", "whisper-large-v3"), o.optBoolean("chunkUpload", true),
                o.optBoolean("betaThoughts", true), o.optBoolean("developerMode"), o.optBoolean("tileAdded"), o.optLong("revision"))
        }
        private fun encode(p: AppPreferences) = JSONObject().apply {
            put("automaticLanguages", p.automaticLanguages); put("detectedLanguages", JSONArray(p.detectedLanguages))
            put("manualLanguages", JSONArray(p.manualLanguages)); put("mainLanguage", p.mainLanguage ?: "")
            put("vocabulary", p.vocabulary); put("transcriptionModel", p.transcriptionModel); put("chunkUpload", p.chunkUpload)
            put("betaThoughts", p.betaThoughts); put("developerMode", p.developerMode); put("tileAdded", p.tileAdded); put("revision", p.revision)
        }.toString()
    }
}
