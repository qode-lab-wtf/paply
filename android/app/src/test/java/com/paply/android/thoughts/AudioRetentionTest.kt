package com.paply.android.thoughts

import com.paply.thoughts.*
import com.paply.thoughts.store.ThoughtStore
import java.nio.file.Files
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AudioRetentionTest {
    @get:Rule val temporary = TemporaryFolder()
    private val now = Instant.parse("2026-10-29T00:00:00Z")
    private val expiry = now.minusSeconds(ThoughtsRepository.AUDIO_RETENTION_SECONDS)
    private fun audio(store: ThoughtStore, id: String, at: Instant, state: ThoughtState = ThoughtState.waitingKey): Thought {
        val thought = Thought(id = id, trigger = ThoughtTrigger.app, state = state, createdAt = at,
            text = "Text behalten", audio = Thought.AudioInfo("audio.wav"))
        store.save(thought)
        Files.write(store.wavURL(id), byteArrayOf(1, 2))
        return thought
    }
    @Test fun localExpiryNeedsNoBetaKeyOrNetworkAndRetainsText() {
        val store = ThoughtStore(temporary.root.toPath())
        audio(store, "old", expiry)
        Files.write(store.m4aURL("old"), byteArrayOf(3)) // A second/legacy format must not survive.
        val trim = store.directory("old").resolve(".tmp-trim-audio.wav")
        val legacyTrim = store.directory("old").resolve("audio.trim.tmp")
        val unrelated = store.directory("old").resolve("keep.txt")
        listOf(trim, legacyTrim, unrelated).forEach { Files.write(it, byteArrayOf(1)) }
        audio(store, "recent", expiry.plusMillis(1))
        audio(store, "recording", expiry.minusSeconds(60), ThoughtState.recording)
        expireThoughtAudio(store, now)
        assertFalse(Files.exists(store.wavURL("old"))); assertFalse(Files.exists(store.m4aURL("old")))
        assertFalse(Files.exists(trim)); assertFalse(Files.exists(legacyTrim)); assertTrue(Files.exists(unrelated))
        val old = store.thought("old")!!
        assertNull(old.audio); assertEquals("Text behalten", old.text)
        assertEquals(ThoughtState.needsAttention, old.state)
        assertTrue(old.status.message!!.contains("30 Tagen"))
        assertTrue(Files.exists(store.wavURL("recent"))); assertTrue(Files.exists(store.wavURL("recording")))
        assertNull(ThoughtStore(temporary.root.toPath()).thought("old")!!.audio)
        expireThoughtAudio(store, now.plusMillis(1))
        assertFalse(Files.exists(store.wavURL("recent")))
    }
    @Test fun failureRetainsReferenceForRetryAndDoesNotBlockOtherExpiredAudio() {
        val store = ThoughtStore(temporary.root.toPath())
        audio(store, "blocked", expiry); audio(store, "other", expiry)
        Files.delete(store.wavURL("blocked")); Files.createDirectory(store.wavURL("blocked"))
        Files.write(store.wavURL("blocked").resolve("blocker"), byteArrayOf(1))
        assertTrue(runCatching { expireThoughtAudio(store, now) }.isFailure)
        assertNotNull(store.thought("blocked")!!.audio)
        assertNull(store.thought("other")!!.audio)
        Files.delete(store.wavURL("blocked").resolve("blocker"))
        expireThoughtAudio(store, now)
        assertNull(store.thought("blocked")!!.audio)
    }
    @Test fun audioSymlinkNeverDeletesItsOutsideTarget() {
        val store = ThoughtStore(temporary.newFolder("store").toPath())
        audio(store, "link", expiry)
        val outside = temporary.newFile("outside.wav").apply { writeText("keep") }
        Files.delete(store.wavURL("link")); Files.createSymbolicLink(store.wavURL("link"), outside.toPath())
        expireThoughtAudio(store, now)
        assertEquals("keep", outside.readText()); assertFalse(Files.exists(store.wavURL("link")))
    }
}
