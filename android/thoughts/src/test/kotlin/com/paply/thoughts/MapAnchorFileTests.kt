package com.paply.thoughts

import com.paply.thoughts.map.*
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class MapAnchorFileTests {
    private fun withFile(block: (Path) -> Unit) {
        val dir = Files.createTempDirectory("paply-map")
        val path = dir.resolve("nested").resolve(MapAnchorFile.fileName)
        try {
            block(path)
        } finally {
            if (Files.exists(path))
                Files.setPosixFilePermissions(path, PosixFilePermissions.fromString("rw-r--r--"))
            dir.toFile().deleteRecursively()
        }
    }

    private fun permissions(path: Path, value: String) {
        Files.setPosixFilePermissions(path, PosixFilePermissions.fromString(value))
    }

    @Test
    fun roundTripIsExactAndSorted() = withFile { url ->
        val anchors =
            mapOf(
                "t_b" to MapAnchor(-12.34, 56.78),
                "t_a" to MapAnchor(.1, -.2),
                "_none" to MapAnchor(300.0, 1e-3),
            )
        MapAnchorFile.save(anchors, url)
        assertEquals(MapAnchorFile.Loaded.Anchors(anchors), MapAnchorFile.load(url))
        val text = Files.readString(url)
        assertTrue(text.indexOf("\"_none\"") < text.indexOf("\"t_a\""))
        val before = Files.readAllBytes(url)
        MapAnchorFile.save(anchors, url)
        assertArrayEquals(before, Files.readAllBytes(url))
        Files.list(url.parent).use {
            assertEquals(
                listOf(MapAnchorFile.fileName),
                it.map { p -> p.fileName.toString() }.toList(),
            )
        }
    }

    @Test
    fun missingDamagedAndUnreadableAreDistinguished() = withFile { url ->
        assertEquals(MapAnchorFile.Loaded.Missing, MapAnchorFile.load(url))
        Files.createDirectories(url.parent)
        Files.writeString(url, "{nicht json")
        assertEquals(MapAnchorFile.Loaded.Damaged, MapAnchorFile.load(url))
        MapAnchorFile.save(mapOf("t" to MapAnchor(1.0, 2.0)), url)
        permissions(url, "---------")
        assertEquals(MapAnchorFile.Loaded.Unreadable, MapAnchorFile.load(url))
    }

    @Test
    fun nonFiniteValuesAreNeverWritten() = withFile { url ->
        MapAnchorFile.save(
            mapOf(
                "ok" to MapAnchor(1.0, 1.0),
                "kaputt" to MapAnchor(Double.POSITIVE_INFINITY, 0.0),
            ),
            url,
        )
        assertEquals(
            MapAnchorFile.Loaded.Anchors(mapOf("ok" to MapAnchor(1.0, 1.0))),
            MapAnchorFile.load(url),
        )
    }

    @Test
    fun reloadInvalidatesOlderLayoutsAndTheFileStays() = withFile { url ->
        val stored = mapOf("t_a" to MapAnchor(400.0, 300.0))
        MapAnchorFile.save(stored, url)
        val before = Files.readAllBytes(url)
        val start = Instant.ofEpochSecond(1793000000)
        val state = MapAnchorState(false)
        fun rememberAndSave(anchors: Map<String, MapAnchor>, revision: Int): Boolean {
            if (!state.remember(anchors, revision)) return false
            assertTrue(state.mayWrite)
            MapAnchorFile.save(state.anchors, url)
            return true
        }
        assertFalse(state.isReady)
        assertEquals(MapAnchorState.Next.ReadAfterUnlock, state.prepare(start))
        assertEquals(MapAnchorState.Next.Nothing, state.prepare(start))
        val zero = mapOf("t_a" to MapAnchor(0.0, 0.0))
        assertFalse(rememberAndSave(zero, state.revision))
        permissions(url, "---------")
        state.apply(MapAnchorFile.load(url), start)
        assertEquals(MapAnchorState.Phase.Blocked(start), state.phase)
        assertTrue(state.isReady && state.anchors.isEmpty() && !state.mayWrite)
        val stale = state.revision
        assertFalse(rememberAndSave(zero, stale))
        assertEquals(MapAnchorState.Next.Nothing, state.prepare(start.plusSeconds(4)))
        assertEquals(MapAnchorState.Next.ReadNow, state.prepare(start.plusSeconds(5)))
        permissions(url, "rw-r--r--")
        state.apply(MapAnchorFile.load(url), start.plusSeconds(5))
        assertTrue(state.revision != stale && state.mayWrite)
        assertEquals(stored, state.anchors)
        assertFalse(rememberAndSave(zero, stale))
        assertEquals(stored, state.anchors)
        assertArrayEquals(before, Files.readAllBytes(url))
        val grown = stored + mapOf("t_b" to MapAnchor(-80.0, 20.0))
        assertTrue(rememberAndSave(grown, state.revision))
        assertEquals(MapAnchorFile.Loaded.Anchors(grown), MapAnchorFile.load(url))
        assertFalse(rememberAndSave(grown, state.revision))
        assertEquals(MapAnchorState.Next.Nothing, state.prepare(start.plusSeconds(100)))
    }

    @Test
    fun missingOrDamagedFileMayBeWrittenAndInMemoryIsReadyAtOnce() {
        val start = Instant.ofEpochSecond(1793000000)
        for (loaded in listOf(MapAnchorFile.Loaded.Missing, MapAnchorFile.Loaded.Damaged)) {
            val state = MapAnchorState(false)
            state.prepare(start)
            state.apply(loaded, start)
            assertTrue(state.isReady && state.mayWrite && state.anchors.isEmpty())
            assertTrue(state.remember(mapOf("t" to MapAnchor(1.0, 2.0)), state.revision))
        }
        val memory = MapAnchorState(true)
        val next = memory.prepare(start)
        val taken = memory.remember(mapOf("t" to MapAnchor(1.0, 2.0)), memory.revision)
        assertTrue(
            memory.isReady && memory.mayWrite && next == MapAnchorState.Next.Nothing && taken,
        )
    }
}
