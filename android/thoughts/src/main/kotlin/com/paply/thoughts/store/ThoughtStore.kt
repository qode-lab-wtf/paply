package com.paply.thoughts.store

import com.paply.thoughts.*
import com.paply.thoughts.ai.TopicHygiene
import com.paply.thoughts.model.*
import java.io.IOException
import java.nio.file.*
import java.time.Instant

/**
 * One serial transaction lock, immutable snapshots, atomically persisted JSON. Never holds a lock
 * over network work.
 */
class ThoughtStore(val root: Path, private val now: () -> Instant = Instant::now) {
    private var loaded = false
    private var loadAttempts = 0
    private val cache = linkedMapOf<String, Thought>()
    private val sourceCache = mutableMapOf<String, ThoughtSource>()
    private var topicsDoc = TopicsDocument(topics = emptyList())
    private var topicsReadable = false
    private val activeCaptures = mutableSetOf<String>()
    private val reconstructed = mutableListOf<String>()
    private val changeBroadcast = Broadcast<String>()
    private val removedBroadcast = Broadcast<Set<String>>()
    val changes
        get() = changeBroadcast.stream

    val removedTopics
        get() = removedBroadcast.stream

    val thoughtsDirectory
        get() = root.resolve("thoughts")

    fun directory(id: String): Path {
        requireID(id)
        return thoughtsDirectory.resolve(id)
    }

    fun thoughtURL(id: String) = directory(id).resolve("thought.json")

    fun sourceURL(id: String) = directory(id).resolve("source.json")

    fun aiResultURL(id: String) = directory(id).resolve("ai-result.json")

    fun aiPartsURL(id: String) = directory(id).resolve("ai-parts.json")

    fun wavURL(id: String) = directory(id).resolve("audio.wav")

    fun m4aURL(id: String) = directory(id).resolve("audio.m4a")

    val topicsURL
        get() = root.resolve("topics.json")

    val topicsPrevURL
        get() = root.resolve("topics.prev.json")

    val suggestionsURL
        get() = root.resolve("topic-suggestions.json")

    private fun requireID(id: String) {
        if (!isValidID(id)) throw ThoughtStoreError(ThoughtStoreError.Code.invalidID)
    }

    private fun safeDirectory(id: String) {
        requireID(id)
        if (Files.isSymbolicLink(thoughtsDirectory) || Files.isSymbolicLink(directory(id)))
            throw ThoughtStoreError(ThoughtStoreError.Code.unavailable)
    }

    private fun ensureLoaded() {
        if (loaded) return
        if (Files.isSymbolicLink(thoughtsDirectory))
            throw ThoughtStoreError(ThoughtStoreError.Code.unavailable)
        FileSafety.createDirectory(thoughtsDirectory)
        val retry = loadAttempts++ > 0
        val known = cache.keys.toSet()
        val before = topicsReadable
        val complete = loadThoughts()
        if (!topicsReadable) loadTopics()
        loaded = complete && topicsReadable
        if (retry) {
            (cache.keys - known).forEach(changeBroadcast::yield)
            if (topicsReadable && !before) changeBroadcast.yield(topicsChangeID)
        }
    }

    @Synchronized
    fun reloadIfNeeded(): Boolean {
        runCatching { ensureLoaded() }
        return loaded
    }

    private fun loadThoughts(): Boolean {
        val dirs =
            try {
                Files.list(thoughtsDirectory).use { it.toList() }
            } catch (_: IOException) {
                return false
            }
        var complete = true
        for (dir in dirs) {
            val id = dir.fileName.toString()
            if (
                !isValidID(id) ||
                    id in cache ||
                    Files.isSymbolicLink(dir) ||
                    !Files.isDirectory(dir)
            )
                continue
            val file = thoughtURL(id)
            val bytes =
                try {
                    if (FileSafety.exists(file)) Files.readAllBytes(file) else null
                } catch (_: IOException) {
                    complete = false
                    continue
                }
            val thought = bytes?.let { runCatching { ThoughtJSON.decode<Thought>(it) }.getOrNull() }
            if (thought != null && thought.id == id) {
                if (thought.schemaVersion != 1) {
                    complete = false
                    continue
                }
                cache[id] = thought
            } else {
                val rebuilt = reconstruct(id, bytes != null)
                if (rebuilt != null) {
                    cache[id] = rebuilt
                    reconstructed.add(id)
                }
            }
        }
        return complete
    }

    /**
     * Quarantine preserves every byte. No read path deletes recordings, placeholders or temporary
     * files.
     */
    private fun quarantine(file: Path): Boolean =
        try {
            var stamp = ThoughtJSON.milliseconds(now())
            var target = file.resolveSibling("damaged-$stamp.json")
            while (FileSafety.exists(target)) {
                stamp++
                target = file.resolveSibling("damaged-$stamp.json")
            }
            Files.move(file, target)
            true
        } catch (_: IOException) {
            false
        }

    private fun reconstruct(id: String, damaged: Boolean): Thought? {
        if (damaged && !quarantine(thoughtURL(id))) return null
        val source = readSource(id)
        val audio =
            when {
                FileSafety.exists(m4aURL(id)) -> "audio.m4a"
                FileSafety.exists(wavURL(id)) -> "audio.wav"
                else -> null
            }
        if (source == null && audio == null) return null
        val duration =
            maxOf(
                ((source?.audioSeconds ?: 0.0) * 1000).toInt(),
                if (audio == "audio.wav")
                    WAVWriter.durationMs(
                        ((FileSafety.fileSize(wavURL(id)) ?: 44) - 44).coerceAtLeast(0).toInt(),
                    )
                else 0,
            )
        val created = runCatching {
            Files.readAttributes(
                    directory(id),
                    java.nio.file.attribute.BasicFileAttributes::class.java,
                )
                .creationTime()
                .toInstant()
        }
            .getOrElse { source?.createdAt ?: now() }
        val thought =
            Thought(
                id = id,
                createdAt = created,
                durationMs = duration,
                trigger = ThoughtTrigger.unknown,
                state = if (source != null) ThoughtState.transcribed else ThoughtState.captured,
                languages = source?.languages ?: emptyList(),
                audio = audio?.let { Thought.AudioInfo(it) },
                updatedAt = now(),
            )
        runCatching { writeFile(thought) }
        return thought
    }

    private fun loadTopics() {
        if (FileSafety.exists(topicsURL)) {
            val data =
                try {
                    Files.readAllBytes(topicsURL)
                } catch (_: IOException) {
                    return
                }
            val doc = runCatching { ThoughtJSON.decode<TopicsDocument>(data) }.getOrNull()
            if (doc != null) {
                if (doc.schemaVersion != 1) return
                topicsDoc = doc
                topicsReadable = true
                return
            }
            if (!quarantine(topicsURL)) return
        }
        val prev =
            try {
                if (FileSafety.exists(topicsPrevURL)) Files.readAllBytes(topicsPrevURL) else null
            } catch (_: IOException) {
                return
            }
        val doc = prev?.let { runCatching { ThoughtJSON.decode<TopicsDocument>(it) }.getOrNull() }
        if (doc != null) {
            if (doc.schemaVersion != 1) return
            topicsDoc = doc
            runCatching { FileSafety.writeAtomically(prev, topicsURL) }
        }
        topicsReadable = true
    }

    @Synchronized
    fun all(): List<Thought> {
        runCatching { ensureLoaded() }
        return cache.values.map { it.snapshot() }
    }

    @Synchronized
    fun thought(id: String): Thought? {
        runCatching { ensureLoaded() }
        return cache[id]?.snapshot()
    }

    private inline fun <reified T> readJSON(file: Path): T? {
        val data =
            try {
                Files.readAllBytes(file)
            } catch (_: IOException) {
                return null
            }
        return try {
            ThoughtJSON.decode<T>(data)
        } catch (_: kotlinx.serialization.SerializationException) {
            quarantine(file)
            null
        } catch (_: IllegalArgumentException) {
            quarantine(file)
            null
        }
    }

    private fun readSource(id: String): ThoughtSource? = runCatching {
        safeDirectory(id)
        readJSON<ThoughtSource>(sourceURL(id))
    }
        .getOrNull()

    @Synchronized
    fun source(id: String): ThoughtSource? {
        sourceCache[id]?.let {
            return it.snapshot()
        }
        return readSource(id)?.also { sourceCache[id] = it }?.snapshot()
    }

    @Synchronized
    fun hasSource(id: String) =
        isValidID(id) && (id in sourceCache || FileSafety.exists(sourceURL(id)))

    @Synchronized
    fun allSources(): Map<String, ThoughtSource> {
        runCatching { ensureLoaded() }
        cache.keys.forEach { source(it) }
        return sourceCache.mapValues { it.value.snapshot() }
    }

    @Synchronized fun rawTexts() = allSources().mapValues { it.value.text }

    @Synchronized
    fun audioURL(id: String): Path? {
        runCatching { ensureLoaded() }
        if (!isValidID(id)) return null
        val file = cache[id]?.audio?.file ?: return null
        if (file !in setOf("audio.wav", "audio.m4a") || runCatching { safeDirectory(id) }.isFailure)
            return null
        val primary = directory(id).resolve(file)
        if (FileSafety.exists(primary)) return primary
        val other = if (file == "audio.wav") m4aURL(id) else wavURL(id)
        return other.takeIf(FileSafety::exists)
    }

    @Synchronized
    fun save(thought: Thought) {
        ensureLoaded()
        safeDirectory(thought.id)
        if (thought.id !in cache && FileSafety.exists(thoughtURL(thought.id)))
            throw ThoughtStoreError(ThoughtStoreError.Code.unavailable)
        if (thought.state == ThoughtState.empty) {
            purge(thought.id)
            return
        }
        commit(
            thought.copy(
                rev = maxOf(thought.rev, cache[thought.id]?.rev ?: 0) + 1,
                updatedAt = now(),
            ),
        )
    }

    @Synchronized
    fun update(id: String, change: (Thought) -> Thought): Thought? {
        ensureLoaded()
        val current = cache[id] ?: return null
        return commitChange(id, current, change(current.snapshot()))?.snapshot()
    }

    @Synchronized
    fun update(id: String, topic: Topic?, change: (Thought, String?) -> Thought): Thought? {
        ensureLoaded()
        val current = cache[id] ?: return null
        var topicID: String? = null
        var missing: Topic? = null
        if (topic != null) {
            val existing = resolve(topic.id, topicsDoc.topics)
            if (existing != null) topicID = existing.id
            else if (topicsReadable && topicsDoc.topics.none { it.id == topic.id }) {
                val same = TopicHygiene.sameNamedTopics(topic.title, topicsDoc.topics)
                if (same.size == 1) topicID = same[0].id
                else if (same.isEmpty()) {
                    missing = topic.copy(mergedInto = null)
                    topicID = topic.id
                }
            }
        }
        var next = change(current.snapshot(), topicID)
        if (missing != null && next.topicId == missing.id) {
            if (
                runCatching { writeTopics(topicsDoc.copy(topics = topicsDoc.topics + missing)) }
                    .isFailure
            )
                next = change(current.snapshot(), null)
        }
        return commitChange(id, current, next)?.snapshot()
    }

    private fun commitChange(id: String, current: Thought, proposed: Thought): Thought? {
        var next = proposed.copy(id = id)
        if (next == current) return current
        if (next.state == ThoughtState.empty) {
            purge(id)
            return null
        }
        next = next.copy(rev = current.rev + 1, updatedAt = now())
        commit(next)
        return next
    }

    private fun Thought.snapshot() =
        copy(
            tasks = tasks.toList(),
            links = links.toList(),
            languages = languages.toList(),
            keywords = keywords.toList(),
            ai = ai?.copy(rejections = ai.rejections.toList()),
        )

    private fun ThoughtSource.snapshot() =
        copy(sentences = sentences.toList(), languages = languages.toList())

    private fun commit(thought: Thought) {
        val stored = thought.snapshot()
        writeFile(stored)
        cache[thought.id] = stored
        if (thought.state != ThoughtState.recording) activeCaptures.remove(thought.id)
        changeBroadcast.yield(thought.id)
    }

    private fun writeFile(thought: Thought) {
        safeDirectory(thought.id)
        FileSafety.createDirectory(directory(thought.id))
        FileSafety.writeAtomically(ThoughtJSON.encode(thought), thoughtURL(thought.id))
    }

    @Synchronized
    fun delete(id: String) {
        if (update(id) { it.copy(deletedAt = now()) } == null)
            throw ThoughtStoreError(ThoughtStoreError.Code.notFound)
    }

    @Synchronized
    fun restore(id: String) {
        if (update(id) { it.copy(deletedAt = null) } == null)
            throw ThoughtStoreError(ThoughtStoreError.Code.notFound)
    }

    @Synchronized fun purge(id: String) = purge(listOf(id))

    @Synchronized
    fun purge(ids: List<String>) {
        runCatching { ensureLoaded() }
        val topicIDs = ids.mapNotNull { removeThought(it) }.toSet()
        pruneTopics(topicIDs)
    }

    private fun removeThought(id: String): String? {
        if (!isValidID(id)) return null
        // Unlike ignoring an unlink error, retaining the index keeps a failed deletion
        // reviewable/retryable.
        try {
            safeDirectory(id)
            if (FileSafety.exists(directory(id)))
                Files.walk(directory(id)).use { paths ->
                    paths.sorted(Comparator.reverseOrder()).forEach { Files.delete(it) }
                }
        } catch (_: IOException) {
            return null
        }
        val removed = cache.remove(id)
        sourceCache.remove(id)
        activeCaptures.remove(id)
        if (removed == null) return null
        changeBroadcast.yield(id)
        return resolve(removed.topicId, topicsDoc.topics)?.id
    }

    private fun pruneTopics(candidates: Set<String>) {
        if (candidates.isEmpty() || !loaded || !topicsReadable) return
        val topics = topicsDoc.topics
        val carried = cache.values.mapNotNull { resolve(it.topicId, topics)?.id }.toSet()
        val described = topics.filter { it.describedNote != null }.map { it.id }.toSet()
        val empty = candidates - carried - described
        if (empty.isEmpty()) return
        val removed =
            topics
                .filter { it.id in empty || resolve(it.id, topics)?.id in empty }
                .map { it.id }
                .toSet()
        if (
            runCatching {
                writeTopics(
                    topicsDoc.copy(
                        topics = topics.filterNot { it.id in removed },
                        declinedMerges =
                            topicsDoc.declinedMerges.filterNot { pair ->
                                pair.any { it in removed }
                            },
                    ),
                )
            }
                .isFailure
        )
            return
        val suggestions = pendingSuggestions()
        val kept = suggestions.filter { it.a !in removed && it.b !in removed }
        if (kept.size != suggestions.size) runCatching { setPendingSuggestions(kept) }
    }

    @Synchronized
    fun saveSourceOnce(id: String, source: ThoughtSource) {
        ensureLoaded()
        safeDirectory(id)
        if (id !in cache) throw ThoughtStoreError(ThoughtStoreError.Code.notFound)
        if (hasSource(id)) throw ThoughtStoreError(ThoughtStoreError.Code.sourceExists)
        FileSafety.createDirectory(directory(id))
        FileSafety.writeAtomically(ThoughtJSON.encode(source), sourceURL(id))
        sourceCache[id] = source.snapshot()
        releaseAudio(id)
    }

    @Synchronized
    fun releaseAudio(id: String): Boolean {
        if (!isValidID(id)) return false
        val thought = cache[id] ?: return false
        if (
            thought.audio == null || thought.state == ThoughtState.recording || id in activeCaptures
        )
            return false
        val source = readSource(id) ?: return false
        sourceCache[id] = source
        return runCatching {
                FileSafety.syncDirectory(directory(id))
                listOf(wavURL(id), m4aURL(id)).forEach { Files.deleteIfExists(it) }
                update(id) { it.copy(audio = null) } != null
            }
            .getOrDefault(false)
    }

    data class Capture(val thought: Thought, val audio: WAVWriter)

    @Synchronized
    fun beginCapture(trigger: ThoughtTrigger, at: Instant): Capture {
        ensureLoaded()
        val id = ThoughtIDs.thought()
        FileSafety.createDirectory(directory(id))
        val thought =
            Thought(
                id = id,
                createdAt = at,
                trigger = trigger,
                state = ThoughtState.recording,
                audio = Thought.AudioInfo("audio.wav"),
                updatedAt = at,
            )
        writeFile(thought)
        val writer =
            try {
                WAVWriter(wavURL(id))
            } catch (e: Exception) {
                removeThought(id)
                throw e
            }
        cache[id] = thought
        activeCaptures.add(id)
        changeBroadcast.yield(id)
        return Capture(thought, writer)
    }

    @Synchronized
    fun finishCapture(id: String, durationMs: Int): Thought? = completeCapture(id, durationMs, null)

    @Synchronized
    fun finishCapture(id: String, durationMs: Int, deletedAt: Instant?) {
        if (completeCapture(id, durationMs, deletedAt) == null && durationMs > 0)
            throw ThoughtStoreError(ThoughtStoreError.Code.notFound)
    }

    private fun completeCapture(id: String, durationMs: Int, deletedAt: Instant?): Thought? {
        activeCaptures.remove(id)
        if (durationMs <= 0) {
            purge(id)
            return null
        }
        return update(id) {
            it.copy(
                state = ThoughtState.captured,
                durationMs = durationMs,
                deletedAt = deletedAt ?: it.deletedAt,
            )
        }
    }

    @Synchronized fun discardCapture(id: String) = purge(id)

    @Synchronized
    fun saveAIResult(id: String, result: StructureResult) =
        saveAIResult(id, AIResultRecord(result, at = now()))

    @Synchronized
    fun saveAIResult(id: String, record: AIResultRecord) {
        requireExistingDirectory(id)
        FileSafety.writeAtomically(ThoughtJSON.encode(AIResultFile(record)), aiResultURL(id))
    }

    private fun requireExistingDirectory(id: String) {
        safeDirectory(id)
        if (!Files.isDirectory(directory(id)))
            throw ThoughtStoreError(ThoughtStoreError.Code.notFound)
    }

    @Synchronized fun aiResult(id: String) = aiResultRecord(id)?.result

    @Synchronized
    fun aiResultRecord(id: String): AIResultRecord? = runCatching {
        safeDirectory(id)
        readJSON<AIResultFile>(aiResultURL(id))?.takeIf { it.schemaVersion == 1 }?.record
    }
        .getOrNull()

    @Synchronized
    fun discardAIResult(id: String) {
        if (!isValidID(id)) return
        runCatching { Files.deleteIfExists(aiResultURL(id)) }
        discardParts(id)
    }

    @Synchronized
    fun saveParts(id: String, parts: StructureParts) {
        requireExistingDirectory(id)
        FileSafety.writeAtomically(ThoughtJSON.encode(parts), aiPartsURL(id))
    }

    @Synchronized
    fun discardParts(id: String) {
        if (isValidID(id)) {
            runCatching { Files.deleteIfExists(aiPartsURL(id)) }
        }
    }

    @Synchronized
    fun parts(id: String): StructureParts? = runCatching {
        safeDirectory(id)
        readJSON<StructureParts>(aiPartsURL(id))
    }
        .getOrNull()

    @Synchronized
    fun topics(): List<Topic> {
        runCatching { ensureLoaded() }
        return topicsDoc.topics.toList()
    }

    data class TopicsSnapshot(val topics: List<Topic>, val complete: Boolean)

    @Synchronized
    fun topicsSnapshot(): TopicsSnapshot {
        runCatching { ensureLoaded() }
        return TopicsSnapshot(topicsDoc.topics.toList(), loaded)
    }

    private fun requireTopics() {
        ensureLoaded()
        if (!topicsReadable) throw ThoughtStoreError(ThoughtStoreError.Code.unavailable)
    }

    @Synchronized
    fun saveTopics(topics: List<Topic>) {
        requireTopics()
        writeTopics(topicsDoc.copy(topics = topics.toList()))
    }

    @Synchronized
    fun updateTopics(change: (List<Topic>) -> List<Topic>): List<Topic> {
        requireTopics()
        val next = change(topicsDoc.topics).toList()
        if (next != topicsDoc.topics) writeTopics(topicsDoc.copy(topics = next))
        return next
    }

    @Synchronized
    fun pendingSuggestions(): List<TopicSuggestion> = runCatching {
        readJSON<List<TopicSuggestion>>(suggestionsURL) ?: emptyList()
    }
        .getOrDefault(emptyList())

    @Synchronized
    fun setPendingSuggestions(suggestions: List<TopicSuggestion>) {
        requireTopics()
        FileSafety.writeAtomically(ThoughtJSON.encode(suggestions), suggestionsURL)
        changeBroadcast.yield(topicsChangeID)
    }

    @Synchronized
    fun declineMerge(a: String, b: String) {
        ensureLoaded()
        val pair = listOf(a, b).sorted()
        if (topicsDoc.declinedMerges.none { it.sorted() == pair })
            setDeclinedMerges(topicsDoc.declinedMerges + listOf(pair))
    }

    data class TopicsInfo(val declinedMerges: List<List<String>>, val lastHygieneAt: Instant?)

    @Synchronized
    fun topicsInfo(): TopicsInfo {
        runCatching { ensureLoaded() }
        return TopicsInfo(topicsDoc.declinedMerges.map { it.toList() }, topicsDoc.lastHygieneAt)
    }

    @Synchronized
    fun setDeclinedMerges(pairs: List<List<String>>) {
        requireTopics()
        writeTopics(topicsDoc.copy(declinedMerges = pairs))
    }

    @Synchronized
    fun setLastHygieneAt(date: Instant?) {
        requireTopics()
        writeTopics(topicsDoc.copy(lastHygieneAt = date))
    }

    private fun writeTopics(doc: TopicsDocument) {
        val next = doc.copy(rev = topicsDoc.rev + 1)
        if (FileSafety.exists(topicsURL)) {
            val current = Files.readAllBytes(topicsURL) // unreadable is never silently overwritten
            FileSafety.writeAtomically(current, topicsPrevURL)
        }
        FileSafety.writeAtomically(ThoughtJSON.encode(next), topicsURL)
        val removed = topicsDoc.topics.map { it.id }.toSet() - next.topics.map { it.id }.toSet()
        topicsDoc = next
        changeBroadcast.yield(topicsChangeID)
        if (removed.isNotEmpty()) removedBroadcast.yield(removed)
    }

    @Synchronized
    fun resolveTopic(id: String?): Topic? {
        runCatching { ensureLoaded() }
        return resolve(id, topicsDoc.topics)
    }

    @Synchronized
    fun recover(): List<String> {
        ensureLoaded()
        val repaired = reconstructed.toMutableList()
        reconstructed.clear()
        for (thought in cache.values.toList()) {
            if (thought.id in activeCaptures) continue
            if (thought.state == ThoughtState.recording) {
                val duration =
                    if (FileSafety.exists(wavURL(thought.id)))
                        runCatching { WAVWriter.repair(wavURL(thought.id)) }.getOrDefault(0)
                    else 0
                if (duration > 0) {
                    update(thought.id) {
                        it.copy(state = ThoughtState.captured, durationMs = duration)
                    }
                    repaired.add(thought.id)
                } else purge(thought.id)
            } else if (thought.id in repaired && thought.audio?.file == "audio.wav")
                runCatching { WAVWriter.repair(wavURL(thought.id)) }
        }
        removeStaleTempFiles(600)
        return repaired.distinct()
    }

    @Synchronized
    fun housekeeping(now: Instant) {
        if (runCatching { ensureLoaded() }.isFailure) return
        purge(
            cache.values
                .filter {
                    it.deletedAt?.let { date -> !now.isBefore(date.plusSeconds(trashRetention)) }
                        ?: false
                }
                .map { it.id },
        )
        cache.values.toList().filter { it.audio != null }.forEach { releaseAudio(it.id) }
        removeStaleTempFiles(3600)
    }

    private fun removeStaleTempFiles(olderThan: Long) {
        val limit = now().minusSeconds(olderThan)
        for (dir in listOf(root) + cache.keys.map(::directory)) runCatching {
            Files.list(dir).use { files ->
                files
                    .filter { it.fileName.toString().startsWith(FileSafety.tempPrefix) }
                    .forEach {
                        if (Files.getLastModifiedTime(it).toInstant().isBefore(limit))
                            Files.deleteIfExists(it)
                    }
            }
        }
    }

    companion object {
        const val topicsChangeID = "topics"
        const val trashRetention = 30L * 24 * 3600

        fun isValidID(id: String) = id.length in 1..80 && Regex("[a-zA-Z0-9_-]+").matches(id)

        fun resolve(id: String?, topics: List<Topic>): Topic? {
            var current = id ?: return null
            val seen = mutableSetOf<String>()
            while (true) {
                val topic = topics.firstOrNull { it.id == current } ?: return null
                val next = topic.mergedInto ?: return topic
                if (next in seen) return topic
                seen.add(current)
                current = next
            }
        }
    }
}
