package com.paply.android.thoughts

import android.util.AtomicFile
import com.paply.thoughts.*
import com.paply.thoughts.processing.PartSplitter
import com.paply.thoughts.store.ThoughtStore
import com.paply.thoughts.store.WAVWriter
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.time.Instant

/** Deterministic IDs make every file migration restartable, including a crash before unlink. */
internal object LegacyThoughtMigration {
    fun run(root: File, store: ThoughtStore): Int {
        val legacy = root.listFiles().orEmpty().filter {
            it.isFile && it.nameWithoutExtension.matches(Regex("[a-fA-F0-9-]{36}")) && it.extension in setOf("json", "wav", "ready")
        }.groupBy { it.nameWithoutExtension }
        var migrated = 0
        for ((name, files) in legacy) {
            try {
                val id = "p0_" + name.replace("-", "")
                val json = files.firstOrNull { it.extension == "json" }
                val audio = files.firstOrNull { it.extension == "wav" }
                val text = json?.let { JSONObject(AtomicFile(it).readFully().toString(Charsets.UTF_8)) }
                val raw = text?.getString("text")?.takeIf { it.isNotBlank() }
                val created = Instant.ofEpochMilli(text?.optLong("createdAt")?.takeIf { it > 0 } ?: files.minOf { it.lastModified() })
                if (store.thought(id) == null) store.save(Thought(id = id, createdAt = created,
                    trigger = ThoughtTrigger.unknown, state = ThoughtState.captured,
                    audio = audio?.let { Thought.AudioInfo("audio.wav") }))
                if (raw != null) {
                    if (!store.hasSource(id)) store.saveSourceOnce(id, ThoughtSource(raw, PartSplitter.sentences(raw, id),
                        "phase0", created, emptyList(), text.optLong("durationMs") / 1000.0))
                    check(store.source(id)?.text == raw)
                    store.update(id) {
                        if (it.state in setOf(ThoughtState.empty, ThoughtState.captured, ThoughtState.recording))
                            it.copy(state = ThoughtState.transcribed, durationMs = text.optInt("durationMs"))
                        else it // A failed legacy unlink must not re-run already completed AI work.
                    }
                } else if (audio != null && !store.hasSource(id)) {
                    val target = store.wavURL(id).toFile()
                    if (!target.exists()) {
                        val atomic = AtomicFile(target)
                        val out = atomic.startWrite()
                        try { audio.inputStream().use { it.copyTo(out) }; atomic.finishWrite(out) }
                        catch (e: Exception) { atomic.failWrite(out); throw e }
                    }
                    // Phase 0 wrote an all-zero header until close; preserve its known PCM16 payload.
                    RandomAccessFile(target, "rw").use { f ->
                        if (f.length() >= 44) {
                            val head = ByteArray(44); f.readFully(head)
                            if (head.all { it == 0.toByte() }) {
                                f.seek(0); f.write(WAVWriter.header((f.length() - 44).toInt())); f.fd.sync()
                            }
                        }
                    }
                    val duration = WAVWriter.repair(target.toPath())
                    if (duration > 0) store.update(id) { it.copy(durationMs = duration, state = ThoughtState.captured) }
                    else store.purge(id)
                } else if (audio == null) store.purge(id)
                // Only after the new durable payload and metadata exist. Never delete during UI reads.
                files.forEach { check(it.delete() || !it.exists()) }
                migrated++
            } catch (_: Exception) {
                // A damaged legacy file never blocks other thoughts. Keep its original bytes;
                // a subsequent process launch can retry after storage/format repair.
                com.paply.android.Diag.event("thought.migration.retained")
            }
        }
        return migrated
    }
}
