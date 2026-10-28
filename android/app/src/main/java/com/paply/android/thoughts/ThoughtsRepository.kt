package com.paply.android.thoughts

import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import com.paply.android.Diag
import com.paply.android.ThoughtState as CaptureState
import com.paply.android.dictation.AndroidLanguageDetector
import com.paply.android.dictation.DictationRuntime
import com.paply.android.settings.KeyVault
import com.paply.android.settings.SettingsRepository
import com.paply.core.PaplySettings
import com.paply.thoughts.*
import com.paply.thoughts.ai.ThoughtStructurer
import com.paply.thoughts.budget.TokenLedger
import com.paply.thoughts.local.CandidateFinder
import com.paply.thoughts.local.TopicIndex
import com.paply.thoughts.model.TopicSuggestion
import com.paply.thoughts.processing.*
import com.paply.thoughts.store.ThoughtStore
import java.io.File
import java.time.Instant
import java.util.Locale
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex

/** App boundary for the next UI stage. All actions finish only after the core's atomic commit. */
class ThoughtsRepository private constructor(private val app: Context) {
    internal val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    internal val workMutex = Mutex()
    private val mutableThoughts = MutableStateFlow<List<Thought>>(emptyList())
    val thoughts = mutableThoughts.asStateFlow()
    private val mutableDeleted = MutableStateFlow<List<Thought>>(emptyList())
    val deleted = mutableDeleted.asStateFlow()
    private val mutableTopics = MutableStateFlow<List<Topic>>(emptyList())
    val topics = mutableTopics.asStateFlow()
    data class TaskEntry(val thought: Thought, val task: ThoughtTask)
    private val mutableTasks = MutableStateFlow<List<TaskEntry>>(emptyList())
    val tasks = mutableTasks.asStateFlow()
    enum class Phase { RECORDING, WAITING, PROCESSED, ERROR }
    data class Status(val phase: Phase, val message: String?, val audioExpiresAt: Instant? = null)
    private val mutableStatus = MutableStateFlow<Map<String, Status>>(emptyMap())
    val status = mutableStatus.asStateFlow()
    val recording = CaptureState.current.asStateFlow()
    private val mutableSuggestions = MutableStateFlow<List<TopicSuggestion>>(emptyList())
    val suggestions = mutableSuggestions.asStateFlow()
    private val mutableLoaded = MutableStateFlow(false)
    val isLoaded = mutableLoaded.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val error = mutableError.asStateFlow()
    private val mutableUsage = MutableStateFlow<TokenLedger.Summary?>(null)
    val usage = mutableUsage.asStateFlow()
    private val manager = app.getSystemService(ConnectivityManager::class.java)
    private val keyPrefs = app.getSharedPreferences("paply-key-vault", Context.MODE_PRIVATE)
    // Hold a strong listener reference; SharedPreferences only holds it weakly.
    private val keyListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "ciphertext" || key == null) kick("key")
    }
    internal data class Backend(val store: ThoughtStore, val ledger: TokenLedger, val finder: CandidateFinder)
    private val ready = scope.async {
        val root = File(app.filesDir, "thoughts")
        val store = ThoughtStore(root.toPath())
        // Subscribe before loading so writes during first publication cannot be lost.
        scope.launch { store.changes.collect { publish(store) } }
        val migrated = LegacyThoughtMigration.run(root, store)
        CaptureDiscardJournal.recover(root, store)
        val recovered = store.recover()
        store.housekeeping(Instant.now())
        Diag.event("thoughts.recovered migrated=$migrated count=${recovered.size}")
        publish(store)
        val ledger = TokenLedger(root.toPath().resolve("ledger.json"))
        mutableUsage.value = ledger.summary()
        mutableLoaded.value = true
        Backend(store, ledger, CandidateFinder(store, detector = AndroidLanguageDetector(app)))
    }
    init {
        keyPrefs.registerOnSharedPreferenceChangeListener(keyListener)
        scope.launch {
            SettingsRepository.get(app).state.map { it.betaThoughts }.distinctUntilChanged().collect {
                com.paply.android.ThoughtWidget.updateAll(app)
                android.service.quicksettings.TileService.requestListeningState(app,
                    android.content.ComponentName(app, com.paply.android.ThoughtTile::class.java))
            }
        }
        manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { kick("network") }
        })
        scope.launch {
            try { ready.await(); ThoughtWork.installMaintenance(app); kick("launch") }
            catch (_: Exception) { mutableError.value = "Gedanken konnten nicht geladen werden. Die Dateien bleiben erhalten." }
        }
    }
    internal suspend fun backend(): Backend = ready.await()
    internal fun online() = manager.getNetworkCapabilities(manager.activeNetwork)
        ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
    internal fun dictationBusy() = DictationRuntime.isBusy
    internal fun settings(): PaplySettings {
        val prefs = SettingsRepository.get(app).snapshot()
        return PaplySettings(transcriptionModel = prefs.transcriptionModel, vocabulary = prefs.vocabulary,
            primaryLanguage = prefs.mainLanguage, spokenLanguages = prefs.languages, chunkedUpload = false)
    }
    internal fun processor(b: Backend): ThoughtProcessor = ThoughtProcessor(
        b.store, ThoughtStructurer(b.ledger, trace = trace), b.finder, b.ledger,
        ProcessorEnvironment(apiKey = { KeyVault(app).read() }, isOnline = { online() },
            isDictationBusy = { dictationBusy() }, settings = { settings() }, uiLanguage = Locale.getDefault().language),
        TopicIndex, b.finder, options = ThoughtProcessor.Options(autoRetry = false), trace = trace,
        languageDetector = AndroidLanguageDetector(app),
    )
    fun kick(reason: String = "foreground") {
        scope.launch {
            try {
                val b = ready.await()
                val hygieneDue = com.paply.thoughts.ai.TopicHygiene.isSuggestionDue(
                    TopicIndex.summaries(b.store.topics(), b.store.all()).count { it.isActive }, b.store.topicsInfo().lastHygieneAt)
                if (hygieneDue || b.store.all().any { it.deletedAt == null && (ThoughtProcessor.isInFlight(it.state) || ThoughtProcessor.isWaiting(it.state)) }) {
                    ThoughtWork.enqueue(app)
                    Diag.event("thought.work.enqueued reason=$reason")
                }
            } catch (_: Exception) { mutableError.value = "Verarbeitung wartet. Bitte Paply erneut öffnen." }
        }
    }
    internal suspend fun publish() = publish(backend().store)
    internal suspend fun publish(store: ThoughtStore) = withContext(Dispatchers.IO) {
        val all = store.all()
        val visible = all.filter { it.deletedAt == null && it.state != ThoughtState.empty && it.state != ThoughtState.recording }.sortedByDescending { it.createdAt }
        mutableThoughts.value = visible
        mutableDeleted.value = all.filter { it.deletedAt != null }.sortedByDescending { it.deletedAt }
        val summaries = TopicIndex.summaries(store.topics(), all)
        mutableTopics.value = summaries.sortedByDescending { it.lastActivity ?: it.topic.createdAt }.map { it.topic }
        mutableTasks.value = visible.flatMap { t -> t.tasks.map { TaskEntry(t, it) } }
            .sortedWith(compareBy<TaskEntry> { it.task.done }.thenBy { it.task.dueAt ?: Instant.MAX }.thenByDescending { it.thought.createdAt })
        mutableStatus.value = all.associate { t -> t.id to Status(when (t.state) {
            ThoughtState.recording -> Phase.RECORDING
            ThoughtState.done -> Phase.PROCESSED
            ThoughtState.needsAttention -> Phase.ERROR
            else -> Phase.WAITING
        }, t.status.message, if (t.audio != null) t.createdAt.plusSeconds(AUDIO_RETENTION_SECONDS) else null) }
        mutableSuggestions.value = store.pendingSuggestions()
    }
    internal suspend fun refreshUsage() { mutableUsage.value = backend().ledger.summary() }
    internal suspend fun markDiscard(id: String) = withContext(Dispatchers.IO) {
        CaptureDiscardJournal.mark(File(app.filesDir, "thoughts"), id)
    }
    internal suspend fun discardCapture(id: String) = withContext(Dispatchers.IO) {
        CaptureDiscardJournal.discard(File(app.filesDir, "thoughts"), backend().store, id)
    }
    suspend fun source(id: String): ThoughtSource? = withContext(Dispatchers.IO) { backend().store.source(id) }
    suspend fun thought(id: String): Thought? = withContext(Dispatchers.IO) { backend().store.thought(id) }
    private suspend fun change(id: String, edit: (Thought) -> Thought) = withContext(Dispatchers.IO) {
        val b = backend(); val result = b.store.update(id, edit); publish(b.store); result
    }
    suspend fun setTitle(id: String, title: String) = change(id) { it.copy(title = title.trim(), titleOwner = Owner.user) }
    suspend fun setText(id: String, text: String) = change(id) { it.copy(text = text, textOwner = Owner.user, textIsRaw = false) }
    suspend fun edit(id: String, title: String, text: String) = change(id) {
        it.copy(title = title.trim(), text = text, titleOwner = Owner.user, textOwner = Owner.user, textIsRaw = false)
    }
    suspend fun setTopic(id: String, topicID: String?) = withContext(Dispatchers.IO) {
        val store = backend().store
        val resolved = topicID?.let { requireNotNull(store.resolveTopic(it)) { "topic-missing" }.id }
        change(id) { it.copy(topicId = resolved, topicOwner = Owner.user) }
    }
    suspend fun createTopic(title: String, icon: TopicIcon = TopicIcon.sparkles, note: String? = null): Topic = withContext(Dispatchers.IO) {
        require(title.isNotBlank())
        val topic = Topic(title = title.trim(), icon = icon, owner = Owner.user, note = Topic.normalizedNote(note))
        backend().store.updateTopics { it + topic }; publish(); topic
    }
    suspend fun trash(id: String) = withContext(Dispatchers.IO) { backend().store.delete(id); publish() }
    suspend fun restore(id: String) = withContext(Dispatchers.IO) { backend().store.restore(id); publish(); kick("restore") }
    suspend fun permanentlyDelete(id: String) = withContext(Dispatchers.IO) { backend().store.purge(id); publish() }
    suspend fun setTaskDone(thoughtID: String, taskID: String, done: Boolean) = change(thoughtID) { t ->
        t.copy(tasks = t.tasks.map { if (it.id == taskID) it.copy(done = done, doneAt = if (done) it.doneAt ?: Instant.now() else null) else it })
    }
    suspend fun toggleTask(thoughtID: String, taskID: String) = change(thoughtID) { t ->
        t.copy(tasks = t.tasks.map { if (it.id == taskID) it.copy(done = !it.done, doneAt = if (!it.done) Instant.now() else null) else it })
    }
    suspend fun retry(id: String) = withContext(Dispatchers.IO) {
        val store = backend().store
        val current = store.thought(id) ?: return@withContext
        if (current.deletedAt != null || current.state == ThoughtState.recording) return@withContext
        // Retain cached successful AI results on an interrupted commit; explicit reorganize is separate.
        store.update(id) { it.copy(state = if (store.hasSource(id)) ThoughtState.transcribed else ThoughtState.captured, status = Thought.Status()) }
        publish(store); kick("retry")
    }
    internal suspend fun maintenance(now: Instant = Instant.now()) = withContext(Dispatchers.IO) {
        val store = backend().store
        store.housekeeping(now)
        for (t in store.all()) {
            if (t.state == ThoughtState.recording || store.hasSource(t.id)) continue
            if (t.audio != null && !now.isBefore(t.createdAt.plusSeconds(AUDIO_RETENTION_SECONDS))) {
                // Persist the explanation first; no silent disappearance of the waiting thought.
                store.update(t.id) { it.copy(state = ThoughtState.needsAttention,
                    status = Thought.Status("Audio nach 30 Tagen entfernt · bitte erneut aufnehmen")) }
                store.audioURL(t.id)?.let { java.nio.file.Files.deleteIfExists(it) }
                store.update(t.id) { it.copy(audio = null) }
            }
        }
        publish(store)
    }
    companion object {
        const val AUDIO_RETENTION_SECONDS = 30L * 24 * 3600
        internal val trace = ThoughtTrace { event, fields ->
            // Preserve only measurements; no model output, text, IDs or arbitrary server strings.
            val numbers = fields.mapNotNull { (key, value) ->
                when (value) {
                    is ThoughtTrace.Value.I -> "$key=${value.value}"
                    is ThoughtTrace.Value.D -> "$key=${value.value}"
                    is ThoughtTrace.Value.B -> "$key=${value.value}"
                    is ThoughtTrace.Value.S -> null
                }
            }
            Diag.event((listOf(event) + numbers).joinToString(" "))
        }
        @android.annotation.SuppressLint("StaticFieldLeak") // Application context only.
        @Volatile private var instance: ThoughtsRepository? = null
        fun get(context: Context): ThoughtsRepository = instance ?: synchronized(this) {
            instance ?: ThoughtsRepository(context.applicationContext).also { instance = it }
        }
    }
}
