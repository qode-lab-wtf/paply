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
) {
    val text: String get() = polished.ifEmpty { raw }
}

/** App-private atomic JSON, newest first; iOS retention: 300 entries, upsert by ID. */
class HistoryStore private constructor(context: Context) {
    private val file = File(context.applicationContext.filesDir, "history/history.json")
    private val atomic = AtomicFile(file)
    private val mutex = Mutex()
    private var loaded = false
    private val mutableEntries = MutableStateFlow<List<HistoryEntry>>(emptyList())
    val entries: StateFlow<List<HistoryEntry>> = mutableEntries.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = mutableError.asStateFlow()

    init {
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try { reload() } catch (_: Exception) {
                mutableError.value = "Der Verlauf konnte nicht gelesen werden. Deine Daten bleiben erhalten."
            }
        }
    }

    suspend fun reload() = withContext(Dispatchers.IO) { mutex.withLock { load() } }
    suspend fun add(entry: HistoryEntry) {
        require(entry.id.isNotBlank() && entry.durationMs >= 0)
        change { old -> (listOf(entry) + old.filter { it.id != entry.id }).sortedByDescending { it.createdAt }.take(LIMIT) }
    }
    suspend fun delete(ids: Set<String>) = change { list -> list.filterNot { it.id in ids } }
    suspend fun deleteAll() = change { emptyList() }

    /** Same polishing context as iOS: last 3 nonempty raws in 30 minutes, oldest first. */
    fun recentRawDictations(now: Long = System.currentTimeMillis()): List<String> = entries.value
        .filter { now - it.createdAt in 0 until 30 * 60 * 1000L && it.raw.isNotEmpty() }
        .take(3).asReversed().map { it.raw }

    private fun load() {
        // Unreadable/corrupt is not empty. No write is allowed until successful loading.
        if (loaded) return
        val values = if (file.exists() || File(file.path + ".bak").exists()) {
            val array = JSONArray(atomic.readFully().toString(Charsets.UTF_8))
            (0 until array.length()).map { decode(array.getJSONObject(it)) }.sortedByDescending { it.createdAt }.take(LIMIT)
        } else emptyList()
        mutableEntries.value = values
        loaded = true
        mutableError.value = null
    }

    private suspend fun change(transform: (List<HistoryEntry>) -> List<HistoryEntry>) = withContext(Dispatchers.IO) {
        mutex.withLock {
            load()
            val next = transform(entries.value)
            check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
            val output = atomic.startWrite()
            try {
                val json = JSONArray().apply { next.forEach { put(encode(it)) } }
                output.write(json.toString().toByteArray(Charsets.UTF_8))
                atomic.finishWrite(output)
            } catch (e: Exception) { atomic.failWrite(output); throw e }
            mutableEntries.value = next
            mutableError.value = null
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
        )
        private fun encode(e: HistoryEntry): JSONObject = JSONObject().apply {
            put("id", e.id); put("createdAt", e.createdAt); put("polished", e.polished); put("raw", e.raw)
            put("language", e.language ?: ""); put("durationMs", e.durationMs); put("status", e.status.name)
            put("error", e.error ?: ""); put("audioFile", e.audioFile ?: "")
        }
    }
}
