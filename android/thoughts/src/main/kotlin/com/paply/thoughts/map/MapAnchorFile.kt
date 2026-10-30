package com.paply.thoughts.map

import com.paply.thoughts.model.ThoughtJSON
import com.paply.thoughts.store.FileSafety
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.time.Instant
import kotlinx.serialization.Serializable

object MapAnchorFile {
    const val fileName = "map-anchors.json"

    sealed interface Loaded {
        data object Missing : Loaded

        data class Anchors(val anchors: Map<String, MapAnchor>) : Loaded

        data object Unreadable : Loaded

        data object Damaged : Loaded
    }

    @Serializable private data class Payload(val version: Int, val anchors: Map<String, MapAnchor>)

    fun load(from: Path): Loaded {
        if (Files.notExists(from, NOFOLLOW_LINKS)) return Loaded.Missing
        if (Files.isSymbolicLink(from)) return Loaded.Unreadable
        val data =
            try {
                Files.readAllBytes(from)
            } catch (_: Exception) {
                return Loaded.Unreadable
            }
        val payload =
            try {
                ThoughtJSON.decode<Payload>(data)
            } catch (_: Exception) {
                return Loaded.Damaged
            }
        return Loaded.Anchors(payload.anchors.filterValues { it.x.isFinite() && it.y.isFinite() })
    }

    fun save(anchors: Map<String, MapAnchor>, to: Path) {
        FileSafety.createDirectory(to.toAbsolutePath().parent)
        FileSafety.writeAtomically(
            ThoughtJSON.encode(
                Payload(1, anchors.filterValues { it.x.isFinite() && it.y.isFinite() }),
            ),
            to,
        )
    }
}

class MapAnchorState(inMemory: Boolean) {
    sealed interface Phase {
        data object Idle : Phase

        data object Waiting : Phase

        data object Loaded : Phase

        data class Blocked(val since: Instant) : Phase
    }

    enum class Next {
        Nothing,
        ReadAfterUnlock,
        ReadNow,
    }

    var phase: Phase = if (inMemory) Phase.Loaded else Phase.Idle
        private set

    var anchors: Map<String, MapAnchor> = emptyMap()
        private set

    var revision = 0
        private set

    var isReady = inMemory
        private set

    val mayWrite
        get() = phase == Phase.Loaded

    fun prepare(now: Instant): Next =
        when (val p = phase) {
            Phase.Idle -> {
                phase = Phase.Waiting
                Next.ReadAfterUnlock
            }
            is Phase.Blocked ->
                if (secondsBetween(p.since, now) >= retryInterval) Next.ReadNow else Next.Nothing
            else -> Next.Nothing
        }

    fun apply(loaded: MapAnchorFile.Loaded, now: Instant) {
        when (loaded) {
            is MapAnchorFile.Loaded.Anchors -> {
                anchors = loaded.anchors.toMap()
                phase = Phase.Loaded
            }
            MapAnchorFile.Loaded.Missing,
            MapAnchorFile.Loaded.Damaged -> {
                anchors = emptyMap()
                phase = Phase.Loaded
            }
            MapAnchorFile.Loaded.Unreadable -> phase = Phase.Blocked(now)
        }
        revision++
        isReady = true
    }

    fun remember(new: Map<String, MapAnchor>, revision: Int): Boolean {
        if (phase != Phase.Loaded || revision != this.revision || new == anchors) return false
        anchors = new.toMap()
        return true
    }

    override fun equals(other: Any?) =
        other is MapAnchorState &&
            phase == other.phase &&
            anchors == other.anchors &&
            revision == other.revision &&
            isReady == other.isReady

    override fun hashCode() = listOf(phase, anchors, revision, isReady).hashCode()

    companion object {
        const val retryInterval = 5.0
    }
}

internal fun secondsBetween(start: Instant, end: Instant) =
    (end.epochSecond - start.epochSecond).toDouble() + (end.nano - start.nano) / 1e9

internal fun Instant.addSeconds(seconds: Double): Instant =
    plusNanos(kotlin.math.round(seconds * 1e9).toLong())
