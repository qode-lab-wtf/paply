package com.paply.thoughts

import com.paply.core.AudioEncoder
import com.paply.thoughts.model.*
import com.paply.thoughts.store.*
import java.nio.file.*
import java.nio.file.attribute.PosixFilePermissions
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*

class StoreTests {
    private val root = StoreSupport.temporaryRoot()
    private val clock = TestClock()
    private val store = ThoughtStore(root, clock.function)

    @After
    fun clean() {
        StoreSupport.remove(root)
    }

    private fun perms(mode: String, vararg paths: Path) {
        paths.forEach { Files.setPosixFilePermissions(it, PosixFilePermissions.fromString(mode)) }
    }

    private fun error(code: ThoughtStoreError.Code, action: () -> Unit) {
        try {
            action()
            fail("Expected $code")
        } catch (e: ThoughtStoreError) {
            assertEquals(code, e.code)
        }
    }

    private fun topic(
        id: String,
        name: String = id,
        owner: Owner = Owner.ai,
        alias: String? = null,
    ) = Topic(id, name, TopicIcon.leaf, owner, clock.now, alias)

    private fun capture(seconds: Double = 1.0): String {
        val (t, w) = store.beginCapture(ThoughtTrigger.control, clock.now)
        w.append(StoreSupport.tone(seconds))
        store.finishCapture(t.id, w.close())
        return t.id
    }

    @Test
    fun protectedFilesAreLoadedLaterAndNeverOverwritten() = runBlocking {
        val t = StoreSupport.thought(title = "Tomaten gießen")
        store.save(t)
        store.saveTopics(listOf(topic("t_garden", "Garten", Owner.user)))
        val tf = store.thoughtURL(t.id)
        val before = Files.readAllBytes(store.topicsURL)
        perms("---------", tf, store.topicsURL)
        try {
            val locked = ThoughtStore(root)
            assertTrue(locked.all().isEmpty())
            assertTrue(locked.topics().isEmpty())
            error(ThoughtStoreError.Code.unavailable) { locked.saveTopics(listOf(topic("t_neu"))) }
            error(ThoughtStoreError.Code.unavailable) { locked.updateTopics { emptyList() } }
            assertFalse(locked.reloadIfNeeded())
            assertTrue(Files.exists(tf))
            assertFalse(
                Files.list(store.directory(t.id)).use {
                    it.anyMatch { f -> f.fileName.toString().startsWith("damaged-") }
                },
            )
            val changes = locked.changes
            perms("rw-r--r--", tf, store.topicsURL)
            assertTrue(locked.reloadIfNeeded())
            assertEquals("Tomaten gießen", locked.thought(t.id)?.title)
            assertEquals(listOf("t_garden"), locked.topics().map { it.id })
            assertArrayEquals(before, Files.readAllBytes(store.topicsURL))
            assertEquals(
                setOf(t.id, ThoughtStore.topicsChangeID),
                withTimeout(1000) { changes.take(2).toList().toSet() },
            )
            locked.saveTopics(locked.topics() + topic("t_neu"))
            assertEquals(2, locked.topics().size)
        } finally {
            perms("rw-r--r--", tf, store.topicsURL)
        }
    }

    @Test
    fun topicsSnapshotIsCompleteOnlyWhenRead() {
        store.saveTopics(listOf(topic("t_saved")))
        perms("---------", store.topicsURL)
        try {
            val locked = ThoughtStore(root)
            assertEquals(ThoughtStore.TopicsSnapshot(emptyList(), false), locked.topicsSnapshot())
            perms("rw-r--r--", store.topicsURL)
            assertTrue(locked.topicsSnapshot().complete)
            assertEquals("t_saved", locked.topicsSnapshot().topics.single().id)
        } finally {
            perms("rw-r--r--", store.topicsURL)
        }
    }

    @Test
    fun removedTopicsAreReportedAfterSaving() = runBlocking {
        val removed = store.removedTopics
        store.saveTopics(listOf(topic("t_a"), topic("t_b"), topic("t_c")))
        store.updateTopics { ts ->
            ts.map { if (it.id == "t_a") it.copy(mergedInto = "t_b") else it }
        }
        store.updateTopics { ts -> ts.filter { it.id == "t_c" } }
        val t = StoreSupport.thought(topicId = "t_c")
        store.save(t)
        store.purge(t.id)
        assertEquals(
            listOf(setOf("t_a", "t_b"), setOf("t_c")),
            withTimeout(1000) { removed.take(2).toList() },
        )
        assertTrue(store.topics().isEmpty())
    }

    @Test
    fun nextAccessRetriesAfterUnreadableDirectory() {
        val t = StoreSupport.thought()
        store.save(t)
        perms("---------", store.thoughtsDirectory)
        try {
            val locked = ThoughtStore(root)
            assertTrue(locked.all().isEmpty())
            perms("rwxr-xr-x", store.thoughtsDirectory)
            assertEquals(listOf(t.id), locked.all().map { it.id })
        } finally {
            perms("rwxr-xr-x", store.thoughtsDirectory)
        }
    }

    @Test
    fun sourceForAPurgedThoughtIsRejected() {
        val t = StoreSupport.thought(state = ThoughtState.transcribing)
        store.save(t)
        store.purge(t.id)
        error(ThoughtStoreError.Code.notFound) { store.saveSourceOnce(t.id, StoreSupport.source()) }
        assertFalse(Files.exists(store.directory(t.id)))
        assertNull(ThoughtStore(root).thought(t.id))
    }

    @Test
    fun finishCaptureWithDeletion() {
        val (t, w) = store.beginCapture(ThoughtTrigger.control, clock.now)
        w.append(StoreSupport.tone(1.0))
        val d = w.close()
        store.finishCapture(t.id, d, clock.now)
        val saved = store.thought(t.id)!!
        assertEquals(ThoughtState.captured, saved.state)
        assertEquals(clock.now, saved.deletedAt)
        assertEquals(d, saved.durationMs)
        assertEquals(2, saved.rev)
        error(ThoughtStoreError.Code.notFound) {
            store.finishCapture("s_gibtsnicht", 1000, clock.now)
        }
        val (e, ew) = store.beginCapture(ThoughtTrigger.control, clock.now)
        ew.close()
        store.finishCapture(e.id, 0, clock.now)
        assertNull(store.thought(e.id))
    }

    @Test
    fun captureWritesWAVAndPlaceholderSynchronously() {
        val (t, w) = store.beginCapture(ThoughtTrigger.control, clock.now)
        assertEquals(ThoughtState.recording, t.state)
        assertTrue(t.id.matches(Regex("s_[0-9a-f]{32}")))
        assertTrue(Files.exists(store.thoughtURL(t.id)))
        assertEquals(44L, Files.size(w.url))
        repeat(10) { w.append(StoreSupport.tone(0.25)) }
        assertEquals(2500, w.close())
        assertEquals(2500, w.close())
        store.finishCapture(t.id, 2500)
        val reload = ThoughtStore(root)
        val saved = reload.thought(t.id)!!
        assertEquals(ThoughtState.captured, saved.state)
        assertEquals(2500, saved.durationMs)
        assertEquals(clock.now, saved.createdAt)
        assertEquals(2, saved.rev)
        assertEquals(80044L, Files.size(reload.audioURL(t.id)!!))
        assertEquals(2500, WAVWriter.headerDurationMs(w.url))
    }

    @Test
    fun wavHeaderIsPatchedEveryTwoSeconds() {
        val w = WAVWriter(root.resolve("a.wav"))
        w.append(StoreSupport.tone(2.5))
        w.waitForPendingWrites()
        assertEquals(2500, WAVWriter.headerDurationMs(w.url))
        w.close()
    }

    @Test
    fun crashRecoveryRepairsHeaderAndOddByte() {
        val (t, w) = store.beginCapture(ThoughtTrigger.control, clock.now)
        w.close()
        Files.write(w.url, ByteArray(64001), StandardOpenOption.APPEND)
        val reload = ThoughtStore(root)
        assertEquals(listOf(t.id), reload.recover())
        assertEquals(2000, reload.thought(t.id)?.durationMs)
        assertEquals(ThoughtState.captured, reload.thought(t.id)?.state)
        assertEquals(64044L, Files.size(w.url))
        assertEquals(2000, WAVWriter.headerDurationMs(w.url))
    }

    @Test
    fun recoveryRemovesPlaceholderWithoutSoundButNotActiveCapture() {
        val (t, w) = store.beginCapture(ThoughtTrigger.control, clock.now)
        w.close()
        val reload = ThoughtStore(root)
        val (running, rw) = reload.beginCapture(ThoughtTrigger.app, clock.now)
        rw.append(StoreSupport.tone(0.5))
        reload.recover()
        assertNull(reload.thought(t.id))
        assertFalse(Files.exists(store.directory(t.id)))
        assertEquals(ThoughtState.recording, reload.thought(running.id)?.state)
        rw.close()
    }

    @Test
    fun damagedTopicsFallBackToPreviousGeneration() {
        store.saveTopics(listOf(topic("t_a", "Umzug")))
        store.saveTopics(store.topics() + topic("t_b", "Fluxo"))
        Files.writeString(store.topicsURL, "{\"topics\": [kaputt")
        val reload = ThoughtStore(root)
        assertEquals(listOf("Umzug"), reload.topics().map { it.title })
        assertEquals(
            1,
            Files.list(root)
                .use { it.filter { f -> f.fileName.toString().startsWith("damaged-") }.count() }
                .toInt(),
        )
        assertEquals(listOf("Umzug"), ThoughtStore(root).topics().map { it.title })
    }

    @Test
    fun damagedTopicsWithoutPreviousAreKeptAside() {
        Files.writeString(store.topicsURL, "nicht json")
        assertTrue(store.topics().isEmpty())
        val damaged =
            Files.list(root).use {
                it.filter { p -> p.fileName.toString().startsWith("damaged-") }.findFirst().get()
            }
        assertEquals("nicht json", Files.readString(damaged))
    }

    @Test
    fun damagedThoughtIsRebuiltFromSourceOrSound() {
        val a = capture()
        val b = capture()
        store.saveSourceOnce(a, StoreSupport.source("hallo welt"))
        listOf(a, b).forEach { Files.writeString(store.thoughtURL(it), "{\"id\":") }
        val reload = ThoughtStore(root)
        val raw = reload.thought(a)!!
        val sound = reload.thought(b)!!
        assertEquals(ThoughtState.transcribed, raw.state)
        assertNull(raw.audio)
        assertEquals(1000, raw.durationMs)
        assertEquals(ThoughtState.captured, sound.state)
        assertEquals("audio.wav", sound.audio?.file)
        assertEquals(1000, sound.durationMs)
        assertEquals(setOf(a, b), reload.recover().toSet())
        assertTrue(
            Files.list(store.directory(a)).use {
                it.anyMatch { p -> p.fileName.toString().startsWith("damaged-") }
            },
        )
    }

    @Test
    fun saveIsAtomicAndCountsRevisions() {
        val t = StoreSupport.thought()
        store.save(t)
        assertEquals(2, store.thought(t.id)?.rev)
        store.save(t.copy(title = "Neu"))
        assertEquals(3, store.thought(t.id)?.rev)
        val updated = store.update(t.id) { it.copy(title = "Noch neuer", titleOwner = Owner.user) }
        assertEquals(4, updated?.rev)
        assertEquals(clock.now, updated?.updatedAt)
        assertEquals(4, store.update(t.id) { it }?.rev)
        assertEquals(
            listOf("thought.json"),
            Files.list(store.directory(t.id)).use {
                it.map { p -> p.fileName.toString() }.toList()
            },
        )
        val json = Files.readString(store.thoughtURL(t.id))
        assertTrue(json.contains("\"createdAt\":${ThoughtJSON.milliseconds(t.createdAt)},"))
        assertTrue(json.contains("\"titleOwner\":\"user\""))
    }

    @Test
    fun emptyStateRemovesThoughtCompletely() {
        val (t, w) = store.beginCapture(ThoughtTrigger.control, clock.now)
        w.close()
        store.save(t.copy(state = ThoughtState.empty, deletedAt = clock.now))
        assertNull(store.thought(t.id))
        assertFalse(Files.exists(store.directory(t.id)))
    }

    @Test
    fun sourceIsWrittenOnlyOnce() {
        val t = StoreSupport.thought(state = ThoughtState.captured)
        store.save(t)
        store.saveSourceOnce(t.id, StoreSupport.source("eins"))
        error(ThoughtStoreError.Code.sourceExists) {
            store.saveSourceOnce(t.id, StoreSupport.source("zwei"))
        }
        assertEquals("eins", ThoughtStore(root).source(t.id)?.text)
    }

    @Test
    fun aiResultRoundTripsAllDecisions() {
        val t = StoreSupport.thought(state = ThoughtState.structuring)
        store.save(t)
        for (decision in
            listOf(
                TopicDecision.Existing("t_1"),
                TopicDecision.New("Garten", TopicIcon.leaf),
                TopicDecision.None,
            )) {
            val r =
                StructureResult(
                    "T",
                    null,
                    decision,
                    listOf(TaskDraft("Anrufen", "ich muss anrufen", "morgen")),
                    listOf(RelatedDraft("s_x", LinkKind.changes, "Grund")),
                    listOf("length"),
                )
            store.saveAIResult(
                t.id,
                AIResultRecord(r, "openai/gpt-oss-120b", TokenUsage(1, 2, 3), clock.now),
            )
            assertEquals(r, store.aiResult(t.id))
            assertEquals(3, store.aiResultRecord(t.id)?.usage?.total)
        }
        store.saveAIResult(
            t.id,
            AIResultRecord(
                StructureResult("T", null, TopicDecision.Existing("t_1"), emptyList(), emptyList()),
                chosenTopic = TopicLabel("Boote", TopicIcon.flag),
            ),
        )
        assertEquals(TopicLabel("Boote", TopicIcon.flag), store.aiResultRecord(t.id)?.chosenTopic)
        store.discardAIResult(t.id)
        assertNull(store.aiResult(t.id))
    }

    @Test
    fun changesAreBroadcastToEveryListener() = runBlocking {
        val a = store.changes
        val b = store.changes
        val t = StoreSupport.thought()
        store.save(t)
        store.saveTopics(emptyList())
        assertEquals(listOf(t.id, "topics"), withTimeout(1000) { a.take(2).toList() })
        assertEquals(t.id, withTimeout(1000) { b.first() })
    }

    @Test
    fun mergedTopicsResolveThroughAliasChain() {
        val a = topic("t_a", alias = "t_b")
        val b = topic("t_b", alias = "t_c")
        val c = topic("t_c")
        assertEquals("t_c", ThoughtStore.resolve("t_a", listOf(a, b, c))?.id)
        assertNull(ThoughtStore.resolve("t_x", listOf(a, b, c)))
        assertEquals("t_l", ThoughtStore.resolve("t_l", listOf(topic("t_l", alias = "t_l")))?.id)
    }

    @Test
    fun trashIsPurgedAfterThirtyDays() {
        val kept = StoreSupport.thought()
        val trashed = StoreSupport.thought()
        store.save(kept)
        store.save(trashed)
        store.delete(trashed.id)
        assertEquals(30 * 86400L, ThoughtStore.trashRetention)
        store.housekeeping(clock.now.plusSeconds(29 * 86400L))
        assertNotNull(store.thought(trashed.id))
        store.housekeeping(clock.now.plusSeconds(31 * 86400L))
        assertNull(store.thought(trashed.id))
        assertFalse(Files.exists(store.directory(trashed.id)))
        assertNotNull(store.thought(kept.id))
    }

    @Test
    fun soundIsDeletedAsSoonAsTheSourceIsSaved() {
        val id = capture()
        assertFalse(store.releaseAudio(id))
        assertTrue(Files.exists(store.wavURL(id)))
        store.saveSourceOnce(id, StoreSupport.source("hallo"))
        assertFalse(Files.exists(store.wavURL(id)))
        assertNull(store.thought(id)?.audio)
        assertNull(store.audioURL(id))
        assertEquals(1000, store.thought(id)?.durationMs)
        assertEquals(
            listOf("source.json", "thought.json"),
            Files.list(store.directory(id)).use {
                it.map { p -> p.fileName.toString() }.sorted().toList()
            },
        )
        assertEquals("hallo", ThoughtStore(root).source(id)?.text)
    }

    @Test
    fun runningCaptureKeepsItsSoundUntilFinished() {
        val (t, w) = store.beginCapture(ThoughtTrigger.control, clock.now)
        w.append(StoreSupport.tone(0.5))
        store.saveSourceOnce(t.id, StoreSupport.source("live"))
        assertTrue(Files.exists(w.url))
        assertFalse(store.releaseAudio(t.id))
        store.finishCapture(t.id, w.close())
        store.housekeeping(clock.now)
        assertNull(store.thought(t.id)?.audio)
        assertFalse(Files.exists(w.url))
    }

    @Test
    fun housekeepingFreesExistingThoughtsFromSound() {
        fun legacy(
            state: ThoughtState,
            audio: String,
            files: List<String>,
            source: Boolean,
            deletedAt: Instant? = null,
        ): String {
            val t =
                StoreSupport.thought(state = state)
                    .copy(audio = Thought.AudioInfo(audio), deletedAt = deletedAt)
            val dir = Files.createDirectories(store.directory(t.id))
            val json =
                ThoughtJSON.json
                    .encodeToJsonElement(Thought.serializer(), t)
                    .jsonObject
                    .toMutableMap()
            json["audio"] = buildJsonObject {
                put("file", audio)
                put("deleteAfter", ThoughtJSON.milliseconds(clock.now) + 30 * 86400000L)
            }
            Files.writeString(dir.resolve("thought.json"), JsonObject(json).toString())
            files.forEach { Files.write(dir.resolve(it), ByteArray(1000)) }
            if (source)
                Files.write(
                    dir.resolve("source.json"),
                    ThoughtJSON.encode(StoreSupport.source("alt")),
                )
            return t.id
        }
        val a = legacy(ThoughtState.done, "audio.m4a", listOf("audio.m4a"), true)
        val b = legacy(ThoughtState.done, "audio.m4a", listOf("audio.wav", "audio.m4a"), true)
        val c = legacy(ThoughtState.transcribed, "audio.wav", listOf("audio.wav"), true, clock.now)
        val d = legacy(ThoughtState.done, "audio.wav", emptyList(), true)
        val wait = legacy(ThoughtState.waitingNetwork, "audio.wav", listOf("audio.wav"), false)
        store.housekeeping(clock.now)
        for (id in listOf(a, b, c, d)) {
            assertNull(store.thought(id)?.audio)
            assertFalse(Files.exists(store.wavURL(id)))
            assertFalse(Files.exists(store.m4aURL(id)))
            assertEquals("alt", store.source(id)?.text)
        }
        assertNotNull(store.thought(c)?.deletedAt)
        assertNotNull(store.thought(wait)?.audio)
        assertTrue(Files.exists(store.wavURL(wait)))
        val revs = store.all().map { it.rev }.sorted()
        store.housekeeping(clock.now)
        assertEquals(revs, store.all().map { it.rev }.sorted())
        assertNull(ThoughtStore(root).thought(a)?.audio)
    }

    @Test
    fun purgingTheLastThoughtRemovesItsTopic() {
        store.saveTopics(
            listOf(
                topic("t_garden"),
                topic("t_beds", alias = "t_garden"),
                topic("t_flat", owner = Owner.user),
                topic("t_manual", owner = Owner.user),
                topic("t_books"),
            ),
        )
        store.setDeclinedMerges(listOf(listOf("t_books", "t_garden"), listOf("t_books", "t_flat")))
        store.setPendingSuggestions(
            listOf(
                TopicSuggestion("t_garden", "t_books", null, "a"),
                TopicSuggestion("t_flat", "t_books", null, "b"),
            ),
        )
        val ts =
            listOf("t_beds", "t_flat", "t_flat", "t_books").map {
                StoreSupport.thought(topicId = it)
            }
        ts.forEach(store::save)
        store.delete(ts[2].id)
        store.purge(ts[0].id)
        assertEquals(setOf("t_flat", "t_manual", "t_books"), store.topics().map { it.id }.toSet())
        assertEquals(listOf(listOf("t_books", "t_flat")), store.topicsInfo().declinedMerges)
        assertEquals(listOf("t_flat"), store.pendingSuggestions().map { it.a })
        store.purge(ts[1].id)
        assertNotNull(store.resolveTopic("t_flat"))
        store.purge(ts[2].id)
        assertEquals(
            setOf("t_manual", "t_books"),
            ThoughtStore(root).topics().map { it.id }.toSet(),
        )
        assertTrue(store.topicsInfo().declinedMerges.isEmpty())
        assertTrue(store.pendingSuggestions().isEmpty())
    }

    @Test
    fun assigningATopicThatJustVanishedCreatesItAgain() {
        val boats = topic("t_boats", "Boote")
        store.saveTopics(listOf(boats))
        val last = StoreSupport.thought(topicId = boats.id)
        val fresh = StoreSupport.thought()
        val mine = StoreSupport.thought()
        val gone = StoreSupport.thought()
        listOf(last, fresh, mine, gone).forEach(store::save)
        store.purge(last.id)
        assertTrue(store.topics().isEmpty())
        store.update(mine.id) { it.copy(topicOwner = Owner.user) }
        assertNull(
            store
                .update(mine.id, boats) { t, id ->
                    if (t.topicOwner != Owner.user) t.copy(topicId = id) else t
                }
                ?.topicId,
        )
        assertTrue(store.topics().isEmpty())
        store.purge(gone.id)
        assertNull(store.update(gone.id, boats) { t, id -> t.copy(topicId = id) })
        assertTrue(store.topics().isEmpty())
        assertEquals(
            boats.id,
            store
                .update(fresh.id, boats) { t, id -> t.copy(topicId = id, topicOwner = Owner.ai) }
                ?.topicId,
        )
        assertEquals(listOf(boats), store.topics())
        store.updateTopics { it + topic("t_alias", "Kähne", alias = boats.id) }
        assertEquals(
            boats.id,
            store.update(fresh.id, topic("t_alias")) { t, id -> t.copy(topicId = id) }?.topicId,
        )
        assertEquals(2, ThoughtStore(root).topics().size)
    }

    @Test
    fun parallelRunsNeverCreateTheSameTopicTwice() = runBlocking {
        val thoughts = List(8) { StoreSupport.thought(state = ThoughtState.structuring) }
        thoughts.forEach(store::save)
        val proposals =
            thoughts.indices.map {
                Topic(
                    title = listOf("Boote", "boote", "Boote", "BOOTE")[it % 4],
                    icon = TopicIcon.flag,
                    owner = Owner.ai,
                )
            }
        thoughts
            .zip(proposals)
            .map { (t, p) ->
                async(Dispatchers.Default) {
                    store.update(t.id, p) { old, id ->
                        old.copy(topicId = id, topicOwner = Owner.ai)
                    }
                }
            }
            .awaitAll()
        val boats = store.topics().single()
        thoughts.forEach { assertEquals(boats.id, store.thought(it.id)?.topicId) }
        assertEquals(
            listOf(boats.id, boats.title),
            ThoughtStore(root).topics().single().let { listOf(it.id, it.title) },
        )
        val own = topic("t_own", "Segeln", Owner.user)
        store.updateTopics { it + own }
        assertEquals(
            own.id,
            store
                .update(thoughts[0].id, topic("t_late", "Segeln")) { t, id -> t.copy(topicId = id) }
                ?.topicId,
        )
        val apps =
            listOf(
                topic("t_app1", "Paply App", Owner.user),
                topic("t_app2", "Paply-App", Owner.user),
            )
        store.updateTopics { it + apps }
        assertNull(
            store
                .update(thoughts[1].id, topic("t_amb", "paply app")) { t, id ->
                    t.copy(topicId = id)
                }
                ?.topicId,
        )
        assertEquals(listOf(boats, own) + apps, store.topics())
    }

    @Test
    fun purgeAllAndThirtyDayPurgeTakeTheirTopicsAlong() {
        store.saveTopics(
            listOf(
                topic("t_a"),
                topic("t_b", owner = Owner.user),
                topic("t_c"),
                topic("t_manual", owner = Owner.user),
            ),
        )
        val ts = listOf("t_a", "t_a", "t_b", "t_c").map { StoreSupport.thought(topicId = it) }
        ts.forEach {
            store.save(it)
            store.delete(it.id)
        }
        store.purge(ts.take(2).map { it.id })
        assertEquals(setOf("t_b", "t_c", "t_manual"), store.topics().map { it.id }.toSet())
        store.housekeeping(clock.now.plusSeconds(31 * 86400L))
        assertTrue(store.all().isEmpty())
        assertEquals("t_manual", store.topics().single().id)
    }

    @Test
    fun adoptsSpikeCaptureFilesInPlace() {
        val finished =
            StoreSupport.thought(state = ThoughtState.captured)
                .copy(audio = Thought.AudioInfo("audio.wav"), durationMs = 1000)
        val crashed =
            StoreSupport.thought(state = ThoughtState.recording)
                .copy(audio = Thought.AudioInfo("audio.wav"))
        for ((t, sec) in listOf(finished to 1.0, crashed to 0.5)) {
            val dir = Files.createDirectories(store.directory(t.id))
            var json = ThoughtJSON.encode(t).toString(Charsets.UTF_8)
            json =
                json.replace(
                    "\"createdAt\":${ThoughtJSON.milliseconds(t.createdAt)}",
                    "\"createdAt\":1793000000123.4",
                )
            Files.writeString(dir.resolve("thought.json"), json)
            val wav = AudioEncoder.wav(AudioEncoder.int16(StoreSupport.tone(sec)))
            if (t.state == ThoughtState.recording) (40..43).forEach { wav[it] = 0 }
            Files.write(dir.resolve("audio.wav"), wav)
        }
        assertEquals(listOf(crashed.id), store.recover())
        assertEquals(1000, store.thought(finished.id)?.durationMs)
        assertEquals(500, store.thought(crashed.id)?.durationMs)
        assertEquals(ThoughtState.captured, store.thought(crashed.id)?.state)
        assertEquals(
            Instant.ofEpochSecond(1793000000, 123400000),
            store.thought(finished.id)?.createdAt,
        )
        assertNotNull(store.audioURL(finished.id))
    }

    @Test
    fun loadsTwoThousandThoughtsQuickly() {
        StoreSupport.writeCorpus(2000, root)
        var best = Double.POSITIVE_INFINITY
        repeat(6) {
            val reload = ThoughtStore(root)
            val started = System.nanoTime()
            val all = reload.all()
            best = minOf(best, (System.nanoTime() - started) / 1e6)
            assertEquals(2000, all.size)
        }
        println("Leistung: 2 000 Gedanken laden ${best.toInt()} ms")
        assertTrue("2000 thoughts: $best ms", best < 300)
    }
}
