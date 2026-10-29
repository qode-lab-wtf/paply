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
import com.paply.thoughts.display.TaskKey
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
import kotlinx.coroutines.sync.withLock

/** App boundary for the next UI stage. All actions finish only after the core's atomic commit. */
class ThoughtsRepository private constructor(private val app: Context) {
    internal val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    internal val workMutex = Mutex()
    private val publishMutex = Mutex()
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
    private val ready = RetryableReady {
        val root = File(app.filesDir, "thoughts")
        val store = ThoughtStore(root.toPath())
        val migrated = LegacyThoughtMigration.run(root, store)
        CaptureDiscardJournal.recover(root, store)
        TrimResidue.recover(store)
        val recovered = store.recover()
        expireThoughtAudio(store, Instant.now())
        if (enabled()) store.housekeeping(Instant.now())
        Diag.event("thoughts.recovered migrated=$migrated count=${recovered.size}")
        val ledger = TokenLedger(root.toPath().resolve("ledger.json"))
        mutableUsage.value = ledger.summary()
        val result = Backend(store, ledger, CandidateFinder(store, detector = AndroidLanguageDetector(app)))
        publish(store)
        // No caller can mutate this store until ready returns. Install only after every fallible initialization step.
        scope.launch(start = CoroutineStart.UNDISPATCHED) { store.changes.collect { publish(store) } }
        mutableError.value = null
        mutableLoaded.value = true
        result
    }
    init {
        // Local retention is independent of Beta, connectivity, keys and AI maintenance.
        androidx.work.WorkManager.getInstance(app).enqueueUniquePeriodicWork("paply-audio-retention",
            androidx.work.ExistingPeriodicWorkPolicy.KEEP,
            androidx.work.PeriodicWorkRequestBuilder<AudioRetentionWorker>(1, java.util.concurrent.TimeUnit.HOURS).build())
        com.paply.android.reminders.TaskReminders.start(app, this)
        com.paply.android.widgets.TaskWidgets.start(app, this)
        keyPrefs.registerOnSharedPreferenceChangeListener(keyListener)
        scope.launch {
            SettingsRepository.get(app).state.map { it.betaThoughts }.distinctUntilChanged().collect { enabled ->
                if (enabled) { ThoughtWork.installMaintenance(app); kick("beta-on") } else ThoughtWork.pause(app)
                com.paply.android.ThoughtWidget.updateAll(app)
                android.service.quicksettings.TileService.requestListeningState(app,
                    android.content.ComponentName(app, com.paply.android.ThoughtTile::class.java))
            }
        }
        manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { kick("network") }
        })
        scope.launch {
            try { backend(); if (enabled()) ThoughtWork.installMaintenance(app); kick("launch") }
            catch (_: Exception) { mutableError.value = "Gedanken konnten nicht geladen werden. Die Dateien bleiben erhalten." }
        }
    }
    internal suspend fun backend(): Backend = ready.get()
    internal fun enabled() = SettingsRepository.get(app).state.value.betaThoughts
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
        ProcessorEnvironment(apiKey = { KeyVault(app).read() }, isOnline = { enabled() && online() },
            isDictationBusy = { !enabled() || dictationBusy() }, settings = { settings() }, uiLanguage = Locale.getDefault().language),
        TopicIndex, b.finder, transcriber = com.paply.thoughts.processing.FileTranscriber(diagnostic = Diag::event),
        options = ThoughtProcessor.Options(autoRetry = false), trace = trace,
        languageDetector = AndroidLanguageDetector(app),
    )
    fun kick(reason: String = "foreground") {
        scope.launch {
            try {
                expireRetainedAudio()
                val b = backend()
                if (!enabled()) return@launch
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
      publishMutex.withLock { synchronized(store) {
        TrimResidue.releaseAudio(store)
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
      } }
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
    /** Consistent reminder input, including trash; topics are resolved across merges under the store lock. */
    data class ReminderSnapshot(val thoughts: List<Thought>, val topicsByThought: Map<String, Topic>)
    suspend fun reminderSnapshot(): ReminderSnapshot = withContext(Dispatchers.IO) {
        val store = backend().store
        synchronized(store) {
            val all = store.all()
            ReminderSnapshot(all, all.mapNotNull { thought -> store.resolveTopic(thought.topicId)?.let { thought.id to it } }.toMap())
        }
    }
    private val mutableReminderDestination = MutableStateFlow<TaskKey?>(null)
    val reminderDestination = mutableReminderDestination.asStateFlow()
    fun openTaskFromReminder(key: TaskKey) { mutableReminderDestination.value = key }
    fun consumeReminderDestination(key: TaskKey) { mutableReminderDestination.compareAndSet(key, null) }
    /** Notification completion is a set, never a toggle; stale actions cannot restore a deleted thought. */
    suspend fun completeTaskFromReminder(thoughtID: String, taskID: String) = change(thoughtID) { t ->
        if (t.deletedAt != null) t else t.copy(tasks = t.tasks.map {
            if (it.id == taskID && !it.done) it.copy(done = true, doneAt = Instant.now()) else it
        })
    }
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
    suspend fun finishRecording() { com.paply.android.ThoughtService.command(app, com.paply.android.ThoughtService.FINISH) }
    // UI actions: additive to the service boundary; all edits use the existing core store.
    suspend fun renameTopic(id: String, title: String) = withContext(Dispatchers.IO) {
        require(title.isNotBlank())
        backend().store.updateTopics { list -> list.map { if (it.id == id) it.copy(title = title.trim()) else it } }
        publish()
    }
    suspend fun setTopicIcon(id: String, icon: TopicIcon) = withContext(Dispatchers.IO) {
        backend().store.updateTopics { list -> list.map { if (it.id == id) it.copy(icon = icon) else it } }
        publish()
    }
    suspend fun setTopicNote(id: String, note: String?) = withContext(Dispatchers.IO) {
        val normalized = Topic.normalizedNote(note)
        backend().store.updateTopics { list -> list.map {
            if (it.id == id) it.copy(note = normalized, owner = if (normalized != null) Owner.user else it.owner) else it
        } }
        publish()
    }
    suspend fun keepProvisional(id: String) = withContext(Dispatchers.IO) {
        backend().store.updateTopics { list -> list.map { if (it.id == id) it.copy(owner = Owner.user) else it } }
        publish()
    }
    suspend fun updateTopic(id: String, title: String, icon: TopicIcon, note: String?) = withContext(Dispatchers.IO) {
        require(title.isNotBlank())
        val normalized = Topic.normalizedNote(note)
        backend().store.updateTopics { list -> list.map {
            if (it.id == id) it.copy(title = title.trim(), icon = icon, note = normalized,
                owner = if (normalized != null) Owner.user else it.owner) else it
        } }
        publish()
    }
    /** Returns a conditional undo action; later user assignments are never blindly replaced. */
    suspend fun mergeTopics(ids: List<String>, into: String, title: String? = null): suspend () -> Unit = withContext(Dispatchers.IO) {
        val store = backend().store
        val target = requireNotNull(store.resolveTopic(into)) { "topic-missing" }
        val sources = ids.mapNotNull { store.resolveTopic(it)?.id }.filter { it != target.id }.toSet()
        val originalTopics = store.topics().filter { it.id in sources || it.id == target.id }
        val originalImages = topicImages()
        val originalSlots = topicColorSlots()
        val moved = mutableListOf<Pair<Thought, Int>>()
        synchronized(store) {
            val members = store.all().filter { store.resolveTopic(it.topicId)?.id in sources }
            store.updateTopics { list -> list.map {
                when {
                    it.id in sources -> it.copy(mergedInto = target.id)
                    it.id == target.id && !title.isNullOrBlank() -> it.copy(title = title.trim())
                    else -> it
                }
            } }
            for (thought in members) {
                val result = store.update(thought.id) { it.copy(topicId = target.id) }
                if (result != null) moved += thought to result.rev
            }
            val involved = sources + target.id
            store.setPendingSuggestions(store.pendingSuggestions().filter { it.a !in involved && it.b !in involved })
        }
        reconcileTopicImages()
        val adoptedImage = if (originalImages[target.id] == null) topicImages()[target.id] else null
        publish(store)
        val undo: suspend () -> Unit = {
            withContext(Dispatchers.IO) {
                synchronized(store) {
                    store.updateTopics { list -> list.map { current ->
                        val old = originalTopics.firstOrNull { it.id == current.id }
                        when {
                            old == null -> current
                            current.id in sources && current.mergedInto == target.id -> current.copy(mergedInto = old.mergedInto)
                            current.id == target.id && current.title == (title?.trim()?.takeIf { it.isNotEmpty() } ?: target.title) -> current.copy(title = old.title)
                            else -> current
                        }
                    } }
                    for ((old, _) in moved) store.update(old.id) {
                        if (it.topicId == target.id && it.topicOwner == old.topicOwner) it.copy(topicId = old.topicId) else it
                    }
                }
                // An adopted source picture returns with the source on undo. A newly chosen target picture stays.
                if (adoptedImage != null && sources.any { source ->
                        store.resolveTopic(source)?.id == source && originalImages[source]?.contentEquals(adoptedImage) == true
                    }) {
                    val name = com.paply.thoughts.display.TopicImageFile.fileName(target.id)!!
                    val file = store.root.resolve(com.paply.thoughts.display.TopicImageFile.directoryName).resolve(name)
                    if (java.nio.file.Files.exists(file) && java.nio.file.Files.readAllBytes(file).contentEquals(adoptedImage))
                        java.nio.file.Files.delete(file)
                }
                reconcileTopicImages()
                restoreTopicColorSlots(originalSlots.filterKeys { it in sources })
                publish(store)
            }
        }
        undo
    }
    suspend fun deleteTopic(id: String) = withContext(Dispatchers.IO) {
        val store = backend().store
        synchronized(store) {
            val removed = store.topics().filter { it.id == id || store.resolveTopic(it.id)?.id == id }.map { it.id }.toSet()
            for (thought in store.all().filter { it.topicId in removed }) store.update(thought.id) {
                if (it.topicId in removed) it.copy(topicId = null, topicOwner = Owner.user) else it
            }
            store.updateTopics { it.filterNot { topic -> topic.id in removed } }
            store.setPendingSuggestions(store.pendingSuggestions().filter { it.a !in removed && it.b !in removed })
        }
        reconcileTopicImages(); publish(store)
    }
    suspend fun acceptSuggestion(suggestion: TopicSuggestion): suspend () -> Unit =
        mergeTopics(listOf(suggestion.a, suggestion.b), suggestion.a, suggestion.name)
    suspend fun declineSuggestion(suggestion: TopicSuggestion) = withContext(Dispatchers.IO) {
        val store = backend().store
        store.declineMerge(suggestion.a, suggestion.b)
        store.setPendingSuggestions(store.pendingSuggestions().filter { it.id != suggestion.id })
        publish(store)
    }
    suspend fun addTask(id: String, text: String) = change(id) { thought ->
        require(text.isNotBlank())
        thought.copy(tasks = thought.tasks + ThoughtTask(text = text.trim(), owner = Owner.user))
    }
    suspend fun editTask(id: String, taskID: String, text: String) = change(id) { thought ->
        require(text.isNotBlank())
        thought.copy(tasks = thought.tasks.map { if (it.id == taskID) it.copy(text = text.trim(), owner = Owner.user) else it })
    }
    suspend fun deleteTask(id: String, taskID: String): suspend () -> Unit {
        var removed: ThoughtTask? = null
        var position = 0
        change(id) { thought ->
            position = thought.tasks.indexOfFirst { it.id == taskID }.coerceAtLeast(0)
            removed = thought.tasks.firstOrNull { it.id == taskID }
            thought.copy(tasks = thought.tasks.filterNot { it.id == taskID })
        }
        return {
            removed?.let { task -> change(id) { thought ->
                if (thought.tasks.any { it.id == task.id } || thought.deletedAt != null) thought
                else thought.copy(tasks = thought.tasks.toMutableList().apply { add(position.coerceAtMost(size), task) })
            } }
        }
    }
    suspend fun addLink(id: String, target: String) = withContext(Dispatchers.IO) {
        val store = backend().store
        synchronized(store) {
            val a = store.thought(id); val b = store.thought(target)
            if (a != null && b != null && a.id != b.id && a.deletedAt == null && b.deletedAt == null &&
                a.links.none { it.target == b.id } && b.links.none { it.target == a.id }) {
                val (owner, other) = if (a.createdAt >= b.createdAt) a to b else b to a
                store.update(owner.id) { it.copy(links = it.links + ThoughtLink(other.id, LinkKind.sameMatter, "", Owner.user)) }
            }
        }
        publish(store)
    }
    suspend fun removeLink(id: String, target: String) = withContext(Dispatchers.IO) {
        val store = backend().store
        synchronized(store) {
            store.update(id) { it.copy(links = it.links.filterNot { link -> link.target == target }) }
            store.update(target) { it.copy(links = it.links.filterNot { link -> link.target == id }) }
        }
        publish(store)
    }
    suspend fun reorganize(id: String) = withContext(Dispatchers.IO) {
        // Worker owns processing; only reset the cached result before the existing retry path.
        workMutex.lock()
        try { backend().store.discardAIResult(id); retry(id) } finally { workMutex.unlock() }
    }
    suspend fun purgeAllDeleted() = withContext(Dispatchers.IO) {
        val store = backend().store
        store.purge(store.all().filter { it.deletedAt != null }.map { it.id })
        reconcileTopicImages(); publish(store)
    }
    suspend fun makeSearchIndex(): com.paply.thoughts.local.ThoughtSearchIndex = withContext(Dispatchers.IO) {
        val store = backend().store
        val index = com.paply.thoughts.local.ThoughtSearchIndex()
        val sources = store.allSources()
        for (thought in store.all().filter { it.deletedAt == null && it.state != ThoughtState.empty }) {
            index.upsert(thought, store.resolveTopic(thought.topicId)?.title, sources[thought.id]?.text)
        }
        index
    }
    suspend fun search(query: String): List<com.paply.thoughts.model.SearchHit> = withContext(Dispatchers.Default) {
        makeSearchIndex().search(query)
    }
    /** Map selection also follows merged aliases, which the public topic summary intentionally omits. */
    suspend fun mapTopics(): List<Topic> = withContext(Dispatchers.IO) { backend().store.topics() }

    suspend fun topicColorSlots(): Map<String, Int> = withContext(Dispatchers.IO) {
        val store = backend().store
        synchronized(store) {
            val file = store.root.resolve(com.paply.thoughts.display.TopicColorFile.fileName)
            val loaded = com.paply.thoughts.display.TopicColorFile.load(file)
            if (loaded is com.paply.thoughts.display.TopicColorFile.Loaded.Unreadable) return@synchronized emptyMap()
            val register = (loaded as? com.paply.thoughts.display.TopicColorFile.Loaded.Register)?.register
                ?: com.paply.thoughts.display.TopicColorRegister()
            if (register.update(store.topics(), listOf(0, 6, 3, 7, 2, 4, 8, 5, 1, 9)))
                com.paply.thoughts.display.TopicColorFile.save(register, file)
            store.topics().mapNotNull { topic -> register.slot(topic.id)?.let { topic.id to it } }.toMap()
        }
    }
    private suspend fun restoreTopicColorSlots(oldSlots: Map<String, Int>) = withContext(Dispatchers.IO) {
        val store = backend().store
        synchronized(store) {
            val file = store.root.resolve(com.paply.thoughts.display.TopicColorFile.fileName)
            val loaded = com.paply.thoughts.display.TopicColorFile.load(file)
            if (loaded is com.paply.thoughts.display.TopicColorFile.Loaded.Unreadable) return@synchronized
            val current = (loaded as? com.paply.thoughts.display.TopicColorFile.Loaded.Register)?.register
                ?: com.paply.thoughts.display.TopicColorRegister()
            val available = oldSlots.filter { (id, slot) -> store.resolveTopic(id)?.id == id && slot !in current.slots.values }
            val register = com.paply.thoughts.display.TopicColorRegister(current.slots + available, current.last)
            register.update(store.topics(), listOf(0, 6, 3, 7, 2, 4, 8, 5, 1, 9))
            com.paply.thoughts.display.TopicColorFile.save(register, file)
        }
    }
    suspend fun topicImages(): Map<String, ByteArray> = withContext(Dispatchers.IO) {
        reconcileTopicImages()
        val store = backend().store
        store.topics().mapNotNull { topic ->
            val name = com.paply.thoughts.display.TopicImageFile.fileName(topic.id) ?: return@mapNotNull null
            val file = store.root.resolve(com.paply.thoughts.display.TopicImageFile.directoryName).resolve(name)
            if (java.nio.file.Files.exists(file)) topic.id to java.nio.file.Files.readAllBytes(file) else null
        }.toMap()
    }
    /** Input must already be a fresh JPEG produced by the platform codec. */
    suspend fun setTopicImage(id: String, jpeg: ByteArray?) = withContext(Dispatchers.IO) {
        val store = backend().store
        requireNotNull(store.resolveTopic(id))
        val name = requireNotNull(com.paply.thoughts.display.TopicImageFile.fileName(id))
        val directory = store.root.resolve(com.paply.thoughts.display.TopicImageFile.directoryName)
        com.paply.thoughts.store.FileSafety.createDirectory(directory)
        if (jpeg == null) java.nio.file.Files.deleteIfExists(directory.resolve(name))
        else {
            val clean = requireNotNull(com.paply.thoughts.display.TopicImageFile.squareJPEG(jpeg, AndroidTopicImageCodec()))
            com.paply.thoughts.store.FileSafety.writeAtomically(clean, directory.resolve(name))
        }
    }
    private suspend fun reconcileTopicImages() = withContext(Dispatchers.IO) {
        val store = backend().store
        synchronized(store) {
            val directory = store.root.resolve(com.paply.thoughts.display.TopicImageFile.directoryName)
            val names = directory.toFile().list()?.toList().orEmpty()
            val scan = com.paply.thoughts.display.TopicImageFile.scan(names)
            val plan = com.paply.thoughts.display.TopicImageFile.plan(scan.images, scan.parked, topics = store.topics(), saved = true)
            fun move(from: String, to: String) {
                val source = directory.resolve(from)
                if (java.nio.file.Files.exists(source)) java.nio.file.Files.move(source, directory.resolve(to), java.nio.file.StandardCopyOption.REPLACE_EXISTING)
            }
            val files = com.paply.thoughts.display.TopicImageFile
            for ((target, source) in plan.adopt) {
                // Keep a parked copy for the merge undo. Both are derived, local-only JPEGs.
                java.nio.file.Files.copy(directory.resolve(files.fileName(source)!!), directory.resolve(files.parkedFileName(source)!!), java.nio.file.StandardCopyOption.REPLACE_EXISTING)
                move(files.fileName(source)!!, files.fileName(target)!!)
            }
            for (id in plan.park) move(files.fileName(id)!!, files.parkedFileName(id)!!)
            for (id in plan.restore) move(files.parkedFileName(id)!!, files.fileName(id)!!)
            val living = store.topics().map { it.id }.toSet()
            for (id in scan.images + scan.parked) if (id !in living) {
                java.nio.file.Files.deleteIfExists(directory.resolve(files.fileName(id)!!))
                java.nio.file.Files.deleteIfExists(directory.resolve(files.parkedFileName(id)!!))
            }
        }
    }
    /** Also invoked while Beta is off. Never starts transcription or topic hygiene. */
    internal suspend fun expireRetainedAudio(now: Instant = Instant.now()) = withContext(Dispatchers.IO) {
        workMutex.withLock {
            val dictations = runCatching {
                com.paply.android.history.HistoryStore.get(app).expireAudio(now.toEpochMilli(), DictationRuntime.activeIDs())
            }
            currentCoroutineContext().ensureActive()
            val store = backend().store
            val thoughts = runCatching { expireThoughtAudio(store, now) }
            publish(store)
            dictations.getOrThrow()
            thoughts.getOrThrow()
        }
    }
    internal suspend fun maintenance(now: Instant = Instant.now()) = withContext(Dispatchers.IO) {
        val store = backend().store
        expireThoughtAudio(store, now)
        if (enabled()) store.housekeeping(now)
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

/** Caller holds the processing mutex; the store lock also excludes capture mutations. */
internal fun expireThoughtAudio(store: ThoughtStore, now: Instant) = synchronized(store) {
    var failed = false
    for (thought in store.all()) {
        if (thought.audio == null || thought.state == ThoughtState.recording ||
            now.isBefore(thought.createdAt.plusSeconds(ThoughtsRepository.AUDIO_RETENTION_SECONDS))) continue
        try {
            val hasSource = store.hasSource(thought.id)
            if (!hasSource) store.update(thought.id) { it.copy(state = ThoughtState.needsAttention,
                status = Thought.Status("Audio nach 30 Tagen entfernt · bitte erneut aufnehmen")) }
            // Validate the directory before touching either supported audio format. Unlinking a
            // file symlink removes the link only; never resolve it to an outside target.
            val directory = store.directory(thought.id)
            check(!java.nio.file.Files.isSymbolicLink(store.thoughtsDirectory) && !java.nio.file.Files.isSymbolicLink(directory))
            val trimCopies = directory.toFile().listFiles().orEmpty().filter {
                it.name.startsWith(".tmp-trim-") || it.name == "audio.trim.tmp"
            }.map { it.toPath() }
            (listOf(store.wavURL(thought.id), store.m4aURL(thought.id)) + trimCopies)
                .forEach { java.nio.file.Files.deleteIfExists(it) }
            store.update(thought.id) { it.copy(audio = null) }
        } catch (_: Exception) { failed = true }
    }
    check(!failed) { "Audio retention incomplete" } // Retry later, without skipping other entries.
}

class AudioRetentionWorker(context: Context, params: androidx.work.WorkerParameters) : androidx.work.CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        ThoughtsRepository.get(applicationContext).expireRetainedAudio()
        Result.success()
    } catch (e: CancellationException) { throw e }
    catch (_: Exception) { Result.retry() }
}
