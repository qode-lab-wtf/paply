package com.paply.android.history

import android.content.Context
import android.util.AtomicFile
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/** createdAt uses Unix epoch milliseconds, durationMs is audio duration, audioFile is an optional private path. */
enum class HistoryFailure(val message: String) {
    KEY("Schlüssel neu eintragen"), STORAGE_FULL("Speicher voll"),
    STORAGE("Speichern nicht möglich. Bitte freien Speicher prüfen."),
    MICROPHONE_BUSY("Mikro belegt"), MICROPHONE("Mikrofon nicht verfügbar"),
    AUDIO_MISSING("Audio fehlt"), CANCELLED("Neuversuch abgebrochen"), PROCESSING("Verarbeitung fehlgeschlagen"),
}
enum class HistoryStatus { OK, FAILED, PENDING }
data class HistoryEntry(
    val id: String,
    val createdAt: Long,
    val polished: String = "",
    val raw: String = "",
    val language: String? = null,
    val durationMs: Long = 0,
    val status: HistoryStatus = HistoryStatus.OK,
    val error: String? = null,
    val audioFile: String? = null,
    val failure: HistoryFailure? = null,
) {
    val text: String get() = polished.ifEmpty { raw }
}

/** App-private atomic JSON, newest first; iOS retention: 300 entries, upsert by ID. */
class HistoryStore internal constructor(context: Context, autoLoad: Boolean = true) {
    private val filesDir = context.applicationContext.filesDir
    private val file = File(filesDir, "history/history.json")
    private val atomic = AtomicFile(file)
    private val mutex = Mutex()
    private var loaded = false
    private var overflow = emptyList<HistoryEntry>()
    private val mutableEntries = MutableStateFlow<List<HistoryEntry>>(emptyList())
    val entries: StateFlow<List<HistoryEntry>> = mutableEntries.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = mutableError.asStateFlow()

    init {
        if (autoLoad) CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try { reload() } catch (_: Exception) {
                mutableError.value = "Der Verlauf konnte nicht gelesen werden. Deine Daten bleiben erhalten."
            }
        }
    }

    suspend fun reload() = withContext(Dispatchers.IO) { mutex.withLock { load() } }
    suspend fun add(entry: HistoryEntry) {
        require(entry.id.isNotBlank() && entry.durationMs >= 0)
        change { old -> (listOf(entry) + old.filter { it.id != entry.id }).sortedByDescending { it.createdAt } }
    }
    /** Async work must never recreate an entry the user deleted while it was running. */
    suspend fun updateIfPresent(entry: HistoryEntry): Boolean {
        var updated = false
        change { old -> old.map { if (it.id == entry.id) { updated = true; entry } else it } }
        return updated
    }
    suspend fun delete(ids: Set<String>) = change { list -> list.filterNot { it.id in ids } }
    suspend fun deleteAll() = change { emptyList() }

    /** Same polishing context as iOS: last 3 nonempty raws in 30 minutes, oldest first. */
    fun recentRawDictations(now: Long = System.currentTimeMillis()): List<String> = entries.value
        .filter { now - it.createdAt in 0 until 30 * 60 * 1000L && it.raw.isNotEmpty() }
        .take(3).asReversed().map { it.raw }

    private fun load() {
        if (loaded) return
        val values = if (file.exists() || File(file.path + ".bak").exists()) {
            try {
                val array = JSONArray(atomic.readFully().toString(Charsets.UTF_8))
                (0 until array.length()).mapNotNull { index ->
                    // One malformed row must never hide the other dictations.
                    try { decode(array.getJSONObject(index)).also { require(it.id.isNotBlank() && it.durationMs >= 0) } }
                    catch (_: org.json.JSONException) { null }
                    catch (_: IllegalArgumentException) { null }
                }.sortedByDescending { it.createdAt }
            } catch (_: org.json.JSONException) {
                quarantine(); emptyList()
            } catch (_: java.io.IOException) {
                quarantine(); emptyList()
            }
        } else emptyList()
        // Retain overflow until a successful write; merely reading never deletes audio.
        overflow = values.drop(LIMIT)
        mutableEntries.value = values.take(LIMIT)
        loaded = true
        mutableError.value = null
    }

    private suspend fun change(transform: (List<HistoryEntry>) -> List<HistoryEntry>) = withContext(Dispatchers.IO) {
        mutex.withLock {
            load()
            val old = entries.value + overflow
            val candidates = transform(old)
            val next = candidates.take(LIMIT)
            if (candidates == old && overflow.isEmpty()) return@withLock
            check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
            val output = atomic.startWrite()
            try {
                val json = JSONArray().apply { next.forEach { put(encode(it)) } }
                output.write(json.toString().toByteArray(Charsets.UTF_8))
                atomic.finishWrite(output)
            } catch (e: Exception) { atomic.failWrite(output); throw e }
            mutableEntries.value = next
            overflow = emptyList()
            mutableError.value = null
            // Only remove files once the new index is durable, and never follow an outside path.
            val retained = next.mapNotNull { audio(it.audioFile) }.toSet()
            (old + candidates).mapNotNull { audio(it.audioFile) }.distinct().filterNot { it in retained }.forEach {
                runCatching { it.delete() }
            }
        }
    }

    private fun audio(path: String?): File? = runCatching {
        if (path == null) return@runCatching null
        val dir = File(filesDir, "dictations").canonicalFile
        // Also reject a dictations directory symlink leading outside filesDir.
        if (!dir.toPath().startsWith(filesDir.canonicalFile.toPath())) return@runCatching null
        File(path).canonicalFile.takeIf { it.parentFile == dir && it.extension == "wav" }
    }.getOrNull()

    private fun quarantine() {
        listOf(file, File(file.path + ".bak"), File(file.path + ".new")).filter { it.exists() }.forEach { source ->
            var stamp = System.currentTimeMillis()
            var target = File(file.parentFile, "damaged-$stamp.json")
            while (target.exists()) { stamp++; target = File(file.parentFile, "damaged-$stamp.json") }
            check(source.renameTo(target)) { "Could not preserve damaged history" }
        }
    }

    companion object {
        const val LIMIT = 300
        @Volatile private var instance: HistoryStore? = null
        fun get(context: Context): HistoryStore = instance ?: synchronized(this) {
            instance ?: HistoryStore(context).also { instance = it }
        }
        private fun decode(o: JSONObject): HistoryEntry = HistoryEntry(
            o.getString("id"), o.getLong("createdAt"), o.optString("polished"), o.optString("raw"),
            o.optString("language").takeIf { it.isNotEmpty() }, o.optLong("durationMs"),
            HistoryStatus.valueOf(o.optString("status", "OK")),
            o.optString("error").takeIf { it.isNotEmpty() }, o.optString("audioFile").takeIf { it.isNotEmpty() },
            HistoryFailure.entries.firstOrNull { it.name == o.optString("failure") },
        )
        private fun encode(e: HistoryEntry): JSONObject = JSONObject().apply {
            put("id", e.id); put("createdAt", e.createdAt); put("polished", e.polished); put("raw", e.raw)
            put("language", e.language ?: ""); put("durationMs", e.durationMs); put("status", e.status.name)
            put("error", e.error ?: ""); put("audioFile", e.audioFile ?: ""); put("failure", e.failure?.name ?: "")
        }
    }
}
