package com.paply.android.thoughts

import android.util.AtomicFile
import com.paply.thoughts.store.ThoughtStore
import java.io.File

/** A committed discard must never become a recovered/transcribed recording after process death. */
internal object CaptureDiscardJournal {
    private fun marker(root: File, id: String): AtomicFile {
        require(id.matches(Regex("[A-Za-z0-9_-]+")))
        return AtomicFile(File(root, "discard-$id"))
    }
    fun mark(root: File, id: String) {
        root.mkdirs()
        val file = marker(root, id)
        val output = file.startWrite()
        try { output.write(1); file.finishWrite(output); check(file.readFully().contentEquals(byteArrayOf(1))) }
        catch (e: Exception) { file.failWrite(output); throw e }
    }
    fun discard(root: File, store: ThoughtStore, id: String) {
        // A full disk may prevent creating the marker while unlinking still works.
        runCatching { mark(root, id) }
        store.discardCapture(id)
        check(store.thought(id) == null && !store.wavURL(id).parent.toFile().exists()) { "discard-pending" }
        marker(root, id).delete()
    }
    fun recover(root: File, store: ThoughtStore) {
        root.listFiles().orEmpty().filter { it.name.matches(Regex("discard-[A-Za-z0-9_-]+")) }.forEach {
            discard(root, store, it.name.removePrefix("discard-"))
        }
    }
}
