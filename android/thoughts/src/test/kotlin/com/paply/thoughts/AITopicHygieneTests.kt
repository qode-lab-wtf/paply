package com.paply.thoughts

import com.paply.thoughts.ai.*
import com.paply.thoughts.model.TopicSuggestion
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class AITopicHygieneTests {
    @Test
    fun normalisation() {
        assertEquals("lissabonreise", TopicHygiene.normalized("Lissabon-Reise"))
        assertEquals("cafemuller", TopicHygiene.normalized("Café Müller"))
    }

    @Test
    fun blockedNamesAndVariants() {
        listOf(
                "Ideen",
                "Idee",
                "notizen",
                "To-do",
                "TODOs",
                "Misc",
                "Allgemeines",
                "Gedanke",
                "Thoughts",
            )
            .forEach { assertTrue(it, TopicHygiene.isBlocked(it)) }
        assertFalse(TopicHygiene.isBlocked("Umzug"))
        assertFalse(TopicHygiene.isBlocked("Paply"))
    }

    @Test
    fun newNameRules() {
        listOf("Lissabon-Reise", "Oma Hilde").forEach {
            assertTrue(TopicHygiene.isValidNewName(it))
        }
        listOf("A", "2024", "eins zwei drei vier", "x".repeat(25)).forEach {
            assertFalse(TopicHygiene.isValidNewName(it))
        }
    }

    @Test
    fun duplicateBarrier() {
        assertEquals(
            "t_wohnung",
            TopicHygiene.matchExisting("Wohnungen", AIFixture.topics)?.topicID,
        )
        assertEquals("t_paply", TopicHygiene.matchExisting("PAPLY", AIFixture.topics)?.topicID)
        listOf("Umzugsplanung", "Lisbon", "Gärten", "Schufa", "Reise", "Pap", "Wohnungssuche")
            .forEach { assertNull(it, TopicHygiene.matchExisting(it, AIFixture.topics)) }
    }

    @Test
    fun sameNameIsCertain() {
        listOf(
                "Paply-App" to "Paply App",
                "PaplyApp" to "paply app",
                "Müller Bau" to "Mueller-Bau",
                "Café Müller" to "café mueller",
                "Wohnungen" to "Wohnung",
                "Rudervereine" to "Ruderverein",
                "Lissabon-Reisen" to "Lissabon Reise",
                "Brandts" to "Brandt",
                "Projekts" to "Projekt",
                "Ideen" to "Idee",
                "Lissbaon" to "Lissabon",
                "Lisssabon" to "Lissabon",
                "Kassenbuh" to "Kassenbuch",
            )
            .forEach { (a, b) ->
                assertNotNull("$a ↔ $b", TopicHygiene.sameNameRank(a, b))
                assertNotNull("$b ↔ $a", TopicHygiene.sameNameRank(b, a))
            }
    }

    @Test
    fun differentNamesStayApart() {
        listOf(
                "Reisen" to "Reis",
                "Fisch" to "Fischer",
                "Umzugsplanung" to "Umzug",
                "Paply" to "Pap",
                "Gärten" to "Garten",
                "Umzüge" to "Umzug",
                "Küchen" to "Kuchen",
                "Bär" to "Bar",
                "Buße" to "Busse",
                "Muller" to "Müller",
                "Café" to "Cafe",
                "Kurs" to "Kur",
                "Reise" to "Reis",
                "Lisbon" to "Lissabon",
                "Lisabon" to "Lissabon",
                "Lissabonn" to "Lissabon",
                "Llissabon" to "Lissabon",
                "Kuechenplanung" to "Kuchenplanung",
                "Küchenplanung" to "Kuchenplanung",
                "Projekt 12" to "Projekt 21",
                "Projekt 12" to "Projekt 1",
                "Schreiner" to "Schreiber",
                "Paply App" to "Paply",
                "Oma Ilse" to "Ilse",
            )
            .forEach { (a, b) ->
                assertNull("$a ↔ $b", TopicHygiene.sameNameRank(a, b))
                assertNull("$b ↔ $a", TopicHygiene.sameNameRank(b, a))
            }
    }

    @Test
    fun suggestionPairsAndSchedule() {
        val profiles =
            listOf(
                TopicHygiene.Profile("a", "Umzug", 9, listOf("wohnung", "kartons", "makler")),
                TopicHygiene.Profile("b", "Wohnungssuche", 4, listOf("wohnung", "makler", "miete")),
                TopicHygiene.Profile("c", "Garten", 3, listOf("tomaten")),
                TopicHygiene.Profile("d", "Gartenplanung", 2, listOf("beet")),
            )
        assertEquals(
            setOf(listOf("a", "b"), listOf("c", "d")),
            TopicHygiene.candidatePairs(profiles, emptySet()).map { listOf(it.a, it.b) }.toSet(),
        )
        listOf(
                "Umzug" to "Umzüge",
                "Garten" to "Gärten",
                "Lissabon" to "Lisbon",
                "Umzug" to "Umzugsplanung",
            )
            .forEach { (a, b) -> assertTrue(TopicHygiene.namesAreClose(a, b)) }
        assertEquals(
            listOf(listOf("c", "d")),
            TopicHygiene.candidatePairs(profiles, setOf(listOf("a", "b"))).map {
                listOf(it.a, it.b)
            },
        )
        val now = Instant.now()
        assertFalse(TopicHygiene.isSuggestionDue(7, null, now))
        assertTrue(TopicHygiene.isSuggestionDue(8, null, now))
        assertFalse(TopicHygiene.isSuggestionDue(12, now.minusSeconds(86400), now))
        assertTrue(TopicHygiene.isSuggestionDue(12, now.minusSeconds(8 * 86400), now))
    }

    @Test
    fun suggestionAnswerIsValidated() {
        val json =
            """{"pairs":[{"a":"b","b":"a","merge":true,"name":"Umzug","reason":"Beides die neue Wohnung"},{"a":"c","b":"x","merge":true,"name":null,"reason":"?"},{"a":"c","b":"d","merge":false,"name":null,"reason":"Verschieden"}]}"""
        assertEquals(
            listOf(TopicSuggestion("b", "a", "Umzug", "Beides die neue Wohnung")),
            TopicHygiene.validateSuggestions(json, listOf("a" to "b", "c" to "d")),
        )
        val message =
            TopicHygiene.suggestionMessage(
                listOf("a" to "b"),
                listOf(
                    TopicHygiene.Profile(
                        "a",
                        "Umzug",
                        9,
                        listOf("1", "2", "3", "4", "5", "6"),
                        exampleTitles = listOf("x", "y", "z", "w"),
                    ),
                    TopicHygiene.Profile("b", "Wohnung", 4, emptyList()),
                ),
            )
        assertTrue(message.contains("\"pairs\""))
        assertFalse(message.contains("\"6\""))
        assertFalse(message.contains("\"w\""))
    }
}
