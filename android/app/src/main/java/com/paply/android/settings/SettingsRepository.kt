package com.paply.android.settings

import android.annotation.SuppressLint
import android.content.Context
import android.view.inputmethod.InputMethodManager
import androidx.datastore.core.DataStoreFactory
import androidx.datastore.core.CorruptionException
import androidx.datastore.core.Serializer
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
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
import org.json.JSONException

/** ISO-639-1 only, including Java's legacy aliases. Shared by detection and persisted settings. */
internal object LanguageCodes {
    private val aliases = mapOf("iw" to "he", "in" to "id", "ji" to "yi")
    private val iso = Locale.getISOLanguages().map { aliases[it] ?: it }.toSet()
    fun normalize(identifier: String): String? {
        val tag = identifier.trim().replace('_', '-').lowercase(Locale.ROOT)
        // Android developer pseudo-locales use real language prefixes, but are not spoken locales.
        if (tag == "en-xa" || tag == "ar-xb") return null
        val code = tag.substringBefore('-').let { aliases[it] ?: it }
        return code.takeIf { it in iso }
    }
    fun list(identifiers: List<String>): List<String> = identifiers.mapNotNull(::normalize).distinct()
    fun keyboard(mode: String, auxiliary: Boolean, identifier: String): String? =
        if (auxiliary || mode != "keyboard") null else normalize(identifier)
    /** iOS AppSettings.refreshDetectedSpokenLanguages: keyboards first, device languages second. */
    fun detected(keyboards: List<String>, device: List<String>): List<String> {
        val result = list(keyboards + device).ifEmpty { listOf("en") }
        return if (result.size == 1 && result.single() != "en") result + "en" else result
    }
}

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
    val detectedLanguages: List<String> = LanguageCodes.detected(emptyList(), listOf(Locale.getDefault().toLanguageTag())),
    val manualLanguages: List<String> = emptyList(),
    val mainLanguage: String? = null,
    val vocabulary: String = "",
    val transcriptionModel: String = "whisper-large-v3",
    val chunkUpload: Boolean = true,
    val betaThoughts: Boolean = true,
    val developerMode: Boolean = false,
    val tileAdded: Boolean = false,
    internal val revision: Long = 0,
    val paplyButton: Boolean = false,
    val buttonForeground: Boolean = false,
) {
    val languages: List<String> get() = if (automaticLanguages) detectedLanguages else manualLanguages
    fun dictationPrefs(): DictationPrefs = DictationPrefs(
        mainLanguage?.takeIf { it in languages } ?: LanguageCodes.normalize(Locale.getDefault().toLanguageTag())?.takeIf { it in languages }
            ?: languages.firstOrNull() ?: "en",
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
    private val store = DataStoreFactory.create(serializer = SettingsSerializer(initial),
        corruptionHandler = settingsCorruptionHandler(file, AppPreferences(detectedLanguages = detectLanguages())),
        scope = scope, produceFile = { file })

    init {
        scope.launch {
            store.data.catch { mutableError.value = "Einstellungen konnten nicht gelesen werden. Bitte Paply neu öffnen." }
                .collect { publish(it); mutableError.value = null }
        }
    }

    /** Ready immediately after get(context), including after process death. Does not read the disk. */
    fun snapshot(): DictationPrefs = state.value.dictationPrefs()

    /** A completed call is persisted; concurrent edits are serialized by DataStore. */
    suspend fun update(transform: (AppPreferences) -> AppPreferences) {
        val saved = store.updateData { current ->
            val next = transform(current).normalized()
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
        val device = (0 until locales.size()).map { locales[it].toLanguageTag() }
        val keyboards = mutableListOf<String>()
        val manager = app.getSystemService(InputMethodManager::class.java)
        manager.enabledInputMethodList.forEach { ime ->
            manager.getEnabledInputMethodSubtypeList(ime, true).forEach { subtype ->
                val tag = subtype.languageTag.ifBlank {
                    @Suppress("DEPRECATION") val legacy = subtype.locale
                    legacy
                }
                LanguageCodes.keyboard(subtype.mode, subtype.isAuxiliary, tag)?.let(keyboards::add)
            }
        }
        return LanguageCodes.detected(keyboards, device)
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

        internal fun decode(text: String): AppPreferences {
            val o = JSONObject(text)
            fun list(key: String): List<String> = o.optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getString(it) } }.orEmpty()
            return AppPreferences(o.optBoolean("automaticLanguages", true), list("detectedLanguages"), list("manualLanguages"),
                o.optString("mainLanguage").takeIf { it.isNotBlank() }, o.optString("vocabulary"),
                o.optString("transcriptionModel", "whisper-large-v3"), o.optBoolean("chunkUpload", true),
                o.optBoolean("betaThoughts", true), o.optBoolean("developerMode"), o.optBoolean("tileAdded"), o.optLong("revision"), o.optBoolean("paplyButton"), o.optBoolean("buttonForeground")).normalized()
        }
        internal fun encode(p: AppPreferences) = JSONObject().apply {
            put("automaticLanguages", p.automaticLanguages); put("detectedLanguages", JSONArray(p.detectedLanguages))
            put("manualLanguages", JSONArray(p.manualLanguages)); put("mainLanguage", p.mainLanguage ?: "")
            put("vocabulary", p.vocabulary); put("transcriptionModel", p.transcriptionModel); put("chunkUpload", p.chunkUpload)
            put("betaThoughts", p.betaThoughts); put("developerMode", p.developerMode); put("tileAdded", p.tileAdded); put("revision", p.revision); put("paplyButton", p.paplyButton); put("buttonForeground", p.buttonForeground)
        }.toString()
    }
}

private fun AppPreferences.normalized() = copy(detectedLanguages = LanguageCodes.list(detectedLanguages),
    manualLanguages = LanguageCodes.list(manualLanguages), mainLanguage = mainLanguage?.let(LanguageCodes::normalize))

internal class SettingsSerializer(override val defaultValue: AppPreferences) : Serializer<AppPreferences> {
    override suspend fun readFrom(input: InputStream): AppPreferences = try {
        SettingsRepository.decode(input.readBytes().toString(Charsets.UTF_8))
    } catch (e: JSONException) {
        throw CorruptionException("Invalid settings JSON", e)
    } catch (e: IllegalArgumentException) {
        throw CorruptionException("Invalid settings value", e)
    }
    override suspend fun writeTo(t: AppPreferences, output: OutputStream) {
        output.write(SettingsRepository.encode(t).toByteArray(Charsets.UTF_8))
    }
}

internal fun settingsCorruptionHandler(file: File, defaults: AppPreferences) = ReplaceFileCorruptionHandler<AppPreferences> {
    if (file.exists()) {
        var stamp = System.currentTimeMillis()
        var damaged = File(file.parentFile, "damaged-$stamp.json")
        while (damaged.exists()) { stamp++; damaged = File(file.parentFile, "damaged-$stamp.json") }
        check(file.renameTo(damaged)) { "Could not preserve damaged settings" }
    }
    defaults
}
