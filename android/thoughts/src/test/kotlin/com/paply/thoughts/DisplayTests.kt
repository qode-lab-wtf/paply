package com.paply.thoughts

import com.paply.thoughts.display.*
import java.nio.file.Files
import java.nio.file.attribute.PosixFilePermissions
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class TopicColorRegisterTests {
    private val order = listOf(0, 6, 3, 7, 2, 4, 8, 5, 1, 9)

    private fun topics(n: Int, start: Int = 0) =
        (start..<start + n).map {
            Topic(
                "t%02d".format(it),
                "Thema $it",
                TopicIcon.sparkles,
                Owner.ai,
                Instant.ofEpochSecond(1000 + it * 60L),
            )
        }

    @Test
    fun firstSightingInCreationOrder() {
        val r = TopicColorRegister()
        assertTrue(r.update(topics(4).reversed(), order))
        assertEquals(listOf(0, 6, 3, 7), topics(4).map { r.slot(it.id) })
        assertEquals(7, r.last)
        assertFalse(r.update(topics(4), order))
    }

    @Test
    fun deletingAnOlderTopicKeepsTheOthers() {
        val r = TopicColorRegister()
        r.update(topics(5), order)
        val before = r.slots
        val rest = topics(5).filter { it.id != "t01" }
        assertTrue(r.update(rest, order))
        rest.forEach { assertEquals(before[it.id], r.slot(it.id)) }
        assertNull(r.slot("t01"))
        r.update(rest + topics(1, 9), order)
        assertEquals(before["t01"], r.slot("t09"))
    }

    @Test
    fun aliasesTakeNoSlotAndShowTheirTarget() {
        val r = TopicColorRegister()
        val all = topics(3)
        r.update(all, order)
        val target = r.slot("t00")
        r.update(all.map { if (it.id == "t02") it.copy(mergedInto = "t00") else it }, order)
        assertNull(r.slots["t02"])
        assertEquals(target, r.slot("t02"))
        r.update(all, order)
        assertEquals(3, r.slot("t02"))
    }

    @Test
    fun noDuplicatesUpToTenAndNoImmediateRepeatAfterwards() {
        val r = TopicColorRegister()
        val all = topics(10) + topics(6, 20).map { it.copy(mergedInto = "t00") }
        r.update(all, order)
        assertEquals(10, topics(10).map { r.slot(it.id) }.toSet().size)
        val last = r.last
        r.update(all + topics(1, 40), order)
        assertNotEquals(last, r.slot("t40"))
        assertEquals(0, r.slot("t40"))
        val last2 = r.last
        r.update(all + topics(2, 40), order)
        assertNotEquals(last2, r.slot("t41"))
    }

    @Test
    fun emptyListFreesNothing() {
        val r = TopicColorRegister()
        r.update(topics(3), order)
        val before = TopicColorRegister(r.slots, r.last)
        assertFalse(r.update(emptyList(), order))
        assertEquals(before, r)
    }

    @Test
    fun storedSlotsAreNeverRedistributed() {
        val r = TopicColorRegister(mapOf("t00" to 6, "t01" to 9), 9)
        r.update(topics(3), order)
        assertEquals(listOf(6, 9, 0), topics(3).map { r.slot(it.id) })
        val odd = TopicColorRegister(mapOf("t00" to 42))
        odd.update(topics(1), order)
        assertEquals(0, odd.slot("t00"))
    }

    @Test
    fun fileRoundTripAndStates() {
        val root = StoreSupport.temporaryRoot()
        val file = root.resolve("nested/${TopicColorFile.fileName}")
        try {
            assertEquals(TopicColorFile.Loaded.Missing, TopicColorFile.load(file))
            val r = TopicColorRegister()
            r.update(topics(3), order)
            TopicColorFile.save(r, file)
            assertEquals(TopicColorFile.Loaded.Register(r), TopicColorFile.load(file))
            val before = Files.readAllBytes(file)
            TopicColorFile.save(r, file)
            assertArrayEquals(before, Files.readAllBytes(file))
            Files.list(file.parent).use { assertEquals(1, it.count()) }
            Files.writeString(file, "{kaputt")
            assertEquals(TopicColorFile.Loaded.Damaged, TopicColorFile.load(file))
            TopicColorFile.save(r, file)
            Files.setPosixFilePermissions(file, emptySet())
            assertEquals(TopicColorFile.Loaded.Unreadable, TopicColorFile.load(file))
        } finally {
            if (Files.exists(file))
                Files.setPosixFilePermissions(file, PosixFilePermissions.fromString("rw-------"))
            StoreSupport.remove(root)
        }
    }
}

class RawTitleTests {
    @Test
    fun dropsLeadingFillersAndCapitalizes() {
        assertEquals(
            RawTitle.Parts(
                "Am wochenende die tomaten ausgeizen und …",
                "die beete gießen, sonst wird es zu trocken.",
            ),
            RawTitle.split(
                "Ähm, also am wochenende die tomaten ausgeizen und die beete gießen, sonst wird es zu trocken.",
            ),
        )
    }

    @Test
    fun stopsAtSentenceEnd() {
        assertEquals(
            RawTitle.Parts("Mietvertrag prüfen", "Bevor ich unterschreibe, die Klausel lesen."),
            RawTitle.split("Mietvertrag prüfen. Bevor ich unterschreibe, die Klausel lesen."),
        )
        assertEquals("Wirklich?", RawTitle.split("wirklich?")?.title)
    }

    @Test
    fun shortTextIsTitleOnly() {
        assertEquals(RawTitle.Parts("Milch kaufen", ""), RawTitle.split("  Milch kaufen  "))
        assertEquals(RawTitle.Parts("Also", ""), RawTitle.split("also"))
    }

    @Test
    fun fillersOnlyGiveNothing() {
        assertNull(RawTitle.split("ähm … äh, hm"))
        assertNull(RawTitle.split("   "))
    }

    @Test
    fun particlesNeedCommaWhenTheyCarryMeaning() {
        assertEquals(
            "So viele Ideen für den Garten",
            RawTitle.split("So viele Ideen für den Garten")?.title,
        )
        assertEquals(
            "Jetzt noch Porto buchen",
            RawTitle.split("So, jetzt noch Porto buchen")?.title,
        )
        assertEquals("Sparplan erhöhen", RawTitle.split("Okay ähm ja, Sparplan erhöhen")?.title)
    }

    @Test
    fun innerHesitationsDisappear() {
        assertEquals(
            "Die Retro am Freitag ansprechen",
            RawTitle.split("Die Retro äh am Freitag ansprechen")?.title,
        )
    }
}
