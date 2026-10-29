package com.paply.android.thoughts

import com.paply.thoughts.store.ThoughtStore
import java.io.File

/** App-owned capture copies; never remove canonical audio or atomic metadata files. */
internal object TrimResidue {
    private fun clean(directory: File) {
        directory.listFiles().orEmpty().filter {
            it.name.startsWith(".tmp-trim-") || it.name == "audio.trim.tmp"
        }.forEach { runCatching { java.nio.file.Files.deleteIfExists(it.toPath()) } }
    }
    fun recover(store: ThoughtStore) {
        store.thoughtsDirectory.toFile().listFiles().orEmpty().filter { it.isDirectory && !java.nio.file.Files.isSymbolicLink(it.toPath()) }.forEach(::clean)
    }
    /** Called under the store lock on releaseAudio's change and the initial publication. */
    fun releaseAudio(store: ThoughtStore) {
        store.all().filter { it.audio == null && store.hasSource(it.id) }.forEach {
            clean(store.wavURL(it.id).parent.toFile())
        }
    }
}
