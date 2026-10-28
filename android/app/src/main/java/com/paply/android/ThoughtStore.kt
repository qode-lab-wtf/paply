package com.paply.android

import android.content.Context
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File

/** One durable record per thought. Raw text is fsynced before its WAV is removed. */
class ThoughtStore(context: Context) {
    private val directory = File(context.filesDir, "thoughts").apply { mkdirs() }
    fun newAudio(): File = File(directory, "${java.util.UUID.randomUUID()}.wav")
    private fun ready(audio: File) = File(directory, "${audio.nameWithoutExtension}.ready")
    fun pending(): List<File> = directory.listFiles()?.filter { it.extension == "wav" && ready(it).exists() && !File(directory, "${it.nameWithoutExtension}.json").exists() }.orEmpty()
    fun interrupted(): List<File> = directory.listFiles()?.filter { it.extension == "wav" && !ready(it).exists() }.orEmpty()
    fun durationMs(audio: File) = ready(audio).readText().toLong()
    fun discard(audio: File) { audio.delete(); ready(audio).delete() }
    fun markReady(audio: CaptureResult) {
        require(audio.usable)
        val atomic = AtomicFile(ready(audio.file))
        val stream = atomic.startWrite()
        try { stream.write(audio.durationMs.toString().toByteArray()); atomic.finishWrite(stream) }
        catch (e: Exception) { atomic.failWrite(stream); throw e }
    }
    fun save(audio: File, text: String, durationMs: Long) {
        val atomic = AtomicFile(File(directory, "${audio.nameWithoutExtension}.json"))
        val stream = atomic.startWrite()
        try {
            val record = JSONObject().put("text", text).put("createdAt", System.currentTimeMillis()).put("durationMs", durationMs)
            stream.write(record.toString().toByteArray(Charsets.UTF_8))
            atomic.finishWrite(stream)
        } catch (e: Exception) { atomic.failWrite(stream); throw e }
        check(audio.delete() || !audio.exists())
        ready(audio).delete()
        Diag.event("thought.saved chars=${text.length} ms=$durationMs audioDeleted=${!audio.exists()}")
    }
    fun entries(): List<JSONObject> = directory.listFiles()?.filter { it.extension == "json" }?.mapNotNull { file ->
        runCatching {
            val record = JSONObject(AtomicFile(file).readFully().toString(Charsets.UTF_8))
            // Recover a crash between committing raw text and deleting audio.
            discard(File(directory, "${file.nameWithoutExtension}.wav"))
            record
        }.getOrNull()
    }?.sortedByDescending { it.getLong("createdAt") }.orEmpty()
}
