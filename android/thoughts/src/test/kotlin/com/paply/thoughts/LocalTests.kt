package com.paply.thoughts

import com.paply.thoughts.local.*
import com.paply.thoughts.model.SearchHit
import com.paply.thoughts.store.ThoughtStore
import java.nio.file.Files
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class LocalTests {
    @Test
    fun keywordsAreFoldedLemmasWithoutStopwords() {
        val terms =
            Keywords.terms(
                "Ich muss morgen die Wohnungen besichtigen und den Mietvertrag mit Anna unterschreiben.",
                "de",
            )
        // Snowball stems replace Apple dictionary lemmas, retaining the same input and concepts.
        assertTrue(terms.contains("wohnung"))
        assertTrue(terms.contains("mietvertrag"))
        assertTrue(terms.contains("besicht"))
        assertTrue(terms.contains("anna"))
        assertTrue(listOf("muessen", "muss", "ich", "und").none { it in terms })
        assertEquals("groesse", Keywords.fold("Größe"))
        assertEquals("cafe", Keywords.fold("Café"))
        val english =
            Keywords.terms("We need to check the release plan for the App Store submission", "en")
        assertTrue(english.contains("releas") && english.contains("submiss"))
        assertFalse(english.contains("need"))
    }

    @Test
    fun topKeywordsUseInverseDocumentFrequency() {
        assertEquals(
            listOf("kowalski", "termin"),
            Keywords.top(mapOf("wohnung" to 3, "termin" to 1, "kowalski" to 1), 2) {
                if (it == "wohnung") 0.1 else 2.0
            },
        )
    }

    private fun searchIndex(): Pair<ThoughtSearchIndex, Map<String, Thought>> {
        val index = ThoughtSearchIndex()
        val a =
            StoreSupport.thought(
                    createdAt = Instant.ofEpochSecond(1000),
                    title = "Übergabe der Wohnung",
                    text =
                        "Herr Kowalski schlägt für die Übergabe der Wohnung in Ehrenfeld den 28. Dezember vor.",
                )
                .copy(tasks = listOf(ThoughtTask(text = "Maler anrufen", owner = Owner.ai)))
        val b =
            StoreSupport.thought(
                createdAt = Instant.ofEpochSecond(2000),
                title = "Café in der Straße",
                text = "Das neue Café an der Hauptstraße hat guten Kuchen.",
            )
        val c =
            StoreSupport.thought(
                createdAt = Instant.ofEpochSecond(3000),
                title = "Laufplan",
                text = "Dreimal pro Woche laufen.",
            )
        index.upsert(a, "Umzug", "ähm also herr kowalski schlägt vor")
        index.upsert(b)
        index.upsert(c, "Fitness", "ähm dreimal laufen und ne Notiz zur wohnung")
        return index to listOf(a, b, c).associateBy { it.id }
    }

    @Test
    fun searchIsCaseAndAccentInsensitiveWithPrefixes() {
        val (index, thoughts) = searchIndex()
        fun titles(query: String) = index.search(query).mapNotNull { thoughts[it.thoughtID]?.title }
        assertEquals(listOf("Übergabe der Wohnung"), titles("ubergabe"))
        assertEquals(listOf("Café in der Straße"), titles("CAFE"))
        assertEquals(listOf("Café in der Straße"), titles("strasse"))
        assertEquals(listOf("Übergabe der Wohnung"), titles("Kowal"))
        assertTrue(titles("owalski").isEmpty())
        assertEquals(listOf("Übergabe der Wohnung"), titles("wohn dez"))
        assertEquals(listOf("Übergabe der Wohnung", "Laufplan"), titles("wohnung"))
        assertEquals(listOf("Übergabe der Wohnung"), titles("umzug"))
        assertEquals(listOf("Übergabe der Wohnung"), titles("maler"))
        assertTrue(titles("wohnung kuchen").isEmpty())
        assertTrue(index.search("   ").isEmpty())
    }

    @Test
    fun searchSnippetHighlightsMatches() {
        val (index, _) = searchIndex()
        val hit = index.search("dezember").first()
        assertEquals(SearchHit.Field.text, hit.field)
        assertEquals("Dezember", hit.snippet.substring(hit.ranges.first()))
        val prefix = index.search("kowal").first()
        assertEquals("Kowal", prefix.snippet.substring(prefix.ranges.first()))
        val long = ThoughtSearchIndex()
        val text =
            "Vorher kommt viel anderer Text. ".repeat(10) +
                "Hier steht das Zielwort mitten drin. " +
                "Danach noch mehr. ".repeat(10)
        long.upsert(StoreSupport.thought(title = "Lang", text = text))
        val snippet = long.search("zielwort").first()
        assertTrue(snippet.snippet.startsWith("…") && snippet.snippet.endsWith("…"))
        assertTrue(snippet.snippet.length < 140)
        assertEquals("Zielwort", snippet.snippet.substring(snippet.ranges.first()))
    }

    @Test
    fun searchesTwoThousandThoughtsQuickly() {
        val index = ThoughtSearchIndex()
        repeat(2000) { i ->
            val thought =
                StoreSupport.thought(
                        createdAt = Instant.ofEpochSecond(i * 3600L),
                        title = "Gedanke $i über Wohnung und Fluxo",
                        text =
                            "Heute über die Übergabe, den Umzug nach Bonn und das Budget nachgedacht. "
                                .repeat(4) + "Nummer $i.",
                    )
                    .copy(tasks = listOf(ThoughtTask(text = "Maler $i anrufen", owner = Owner.ai)))
            index.upsert(thought, "Thema ${i % 20}", "ähm also " + thought.text!!.lowercase())
        }
        var worst = 0.0
        for (query in
            listOf("wohn", "ubergabe bonn", "maler 1999", "budget umzug fluxo", "zzz", "thema 7")) {
            var best = Double.MAX_VALUE
            repeat(6) {
                val start = System.nanoTime()
                index.search(query)
                best = minOf(best, (System.nanoTime() - start) / 1e6)
            }
            worst = maxOf(worst, best)
        }
        println("Search 2000 thoughts worst best-of-six: $worst ms")
        assertTrue("Search $worst ms", worst < 50)
        assertEquals(1, index.search("maler 1999").size)
        assertEquals(300, index.search("wohn").size)
    }

    @Test
    fun localIndexRoundTrips() {
        // Android omits the derived binary file. Rebuilding an independent RAM index must retain
        // entries/frequencies, and replacement/removal must not leave obsolete terms behind.
        val index = LocalIndex()
        index.upsert(LocalIndex.Entry("s_a", 42uL, "de", mapOf("wohnung" to 2, "umzug" to 1)))
        index.upsert(LocalIndex.Entry("s_b", 7uL, null, emptyMap()))
        val copy = LocalIndex().also { x -> index.entries.values.forEach(x::upsert) }
        assertEquals(index.entries, copy.entries)
        assertEquals(mapOf("wohnung" to 1, "umzug" to 1), copy.documentFrequency)
        copy.upsert(LocalIndex.Entry("s_a", 43uL, "de", mapOf("wald" to 1)))
        assertEquals(mapOf("wald" to 1), copy.documentFrequency)
        copy.remove("s_a")
        assertEquals(0, copy.totalLength)
        assertEquals(3, index.totalLength)
    }

    @Test
    fun candidateRecallOnEvaluationSet() = runBlocking {
        val fixture = E0Fixture.load()
        val clock = TestClock()
        val finder = CandidateFinder(fixture.thoughts, fixture.topics, now = clock.function)
        var hits = 0
        var total = 0
        for (item in fixture.cases) {
            clock.now = item.recordedAt
            val candidates = finder.candidates(item.transcript, item.languages, "")
            assertTrue(candidates.size <= 7)
            val ids = candidates.map { it.thoughtID }.toSet()
            for (group in item.required) {
                total++
                if (group.any { it in ids }) hits++
            }
        }
        assertEquals(11, total)
        assertTrue("$hits/$total", hits >= 10)
    }

    @Test
    fun recentThoughtsAreAlwaysCandidates() = runBlocking {
        val fixture = E0Fixture.load()
        val e01 = fixture.cases.first { it.id == "e01" }
        val finder = CandidateFinder(fixture.thoughts, fixture.topics, now = { e01.recordedAt })
        val entry =
            finder.candidates(e01.transcript, e01.languages, "").first {
                it.thoughtID == "s_a0ee7da79e48b773f3797c9307a17683"
            }
        assertTrue(entry.`when`.startsWith("heute "))
        assertTrue(entry.excerpt.length <= 160 && entry.excerpt.isNotEmpty())
        assertEquals("Übergabe der alten Wohnung am 28. Dezember", entry.title)
        val halfStep =
            CandidateFinder(
                fixture.thoughts,
                fixture.topics,
                options = CandidateFinder.Options(recencyBonus = 0.0005),
                now = { e01.recordedAt },
            )
        // No lexical score: the recent candidate's half-thousandth rounds up, as in Swift.
        val rounded = halfStep.candidates("", e01.languages, "").first()
        assertEquals(0.001, rounded.localScore, 0.0)
    }

    @Test
    fun candidatesExcludeSelfDeletedAndUnprocessed() = runBlocking {
        val now = Instant.ofEpochSecond(1_793_093_400)
        val thoughts =
            (0..<10)
                .map { i ->
                    StoreSupport.thought(
                        createdAt = now.minusSeconds((i + 1) * 86400L),
                        title = "Halbmarathon Training $i",
                        text = "Laufen am Rhein, Intervalle und lange Läufe für den Halbmarathon.",
                    )
                }
                .toMutableList()
        thoughts[0] = thoughts[0].copy(deletedAt = now)
        thoughts[1] = thoughts[1].copy(state = ThoughtState.captured, title = null, text = null)
        val finder = CandidateFinder(thoughts, emptyList(), now = { now })
        val result =
            finder.candidates(
                "Training für den Halbmarathon am Rhein",
                listOf("de"),
                thoughts[2].id,
            )
        assertTrue(result.none { it.thoughtID in thoughts.take(3).map { t -> t.id } })
        assertTrue(result.size <= 7 && result.isNotEmpty())
    }

    @Test
    fun candidatesRelativeToTheRecordingTime() = runBlocking {
        val recorded = Instant.ofEpochSecond(1_793_093_400)
        val processed = recorded.plusSeconds(2 * 86400)
        val older =
            StoreSupport.thought(
                createdAt = recorded.minusSeconds(3600),
                title = "Übergabe der Wohnung",
                text = "Herr Kowalski schlägt den 28. Dezember für die Übergabe vor.",
            )
        val unrelated =
            StoreSupport.thought(
                createdAt = recorded.minusSeconds(40 * 86400),
                title = "Gitarre",
                text = "Neue Saiten für die Gitarre kaufen.",
            )
        val later =
            StoreSupport.thought(
                createdAt = recorded.plusSeconds(3600),
                title = "Später",
                text = "Ein Gedanke nach der Aufnahme.",
            )
        val finder =
            CandidateFinder(listOf(older, unrelated, later), emptyList(), now = { processed })
        val text = "noch was zu vorhin der Termin geht doch nicht"
        val entries = finder.candidates(text, listOf("de"), "s_self", recorded)
        val old = entries.first { it.thoughtID == older.id }
        assertEquals(CandidateFinder.`when`(older.createdAt, recorded), old.`when`)
        assertTrue(old.`when`.startsWith("heute"))
        assertFalse(entries.any { it.thoughtID == later.id && it.localScore < 0.35 })
        assertFalse(
            finder
                .candidates(text, listOf("de"), "s_self")
                .firstOrNull { it.thoughtID == older.id }
                ?.`when`
                ?.startsWith("heute") == true,
        )
    }

    @Test
    fun whenIsPhrasedLocally() {
        val zone = ZoneId.of("Europe/Berlin")
        val now = Instant.ofEpochSecond(1_793_093_400)
        assertEquals("heute 08:10", CandidateFinder.`when`(now.minusSeconds(8400), now, zone))
        assertEquals("gestern", CandidateFinder.`when`(now.minusSeconds(86400), now, zone))
        assertEquals("vor 5 Tagen", CandidateFinder.`when`(now.minusSeconds(5 * 86400), now, zone))
        assertTrue(
            CandidateFinder.`when`(Instant.ofEpochSecond(1_789_200_000), now, zone)
                .startsWith("12. Sep"),
        )
    }

    @Test
    fun topicIndexFromEvaluationStore() = runBlocking {
        val fixture = E0Fixture.load()
        val e12 = fixture.cases.first { it.id == "e12" }
        val finder = CandidateFinder(fixture.thoughts, fixture.topics, now = { e12.recordedAt })
        val index = finder.topicIndex(e12.transcript, e12.languages)
        assertFalse(index.full)
        assertEquals(14, index.entries.size)
        assertEquals("Hochzeit Felix", index.entries.last().name)
        assertEquals(1, index.entries.last().count)
        val fluxo = index.entries.first { it.name == "Fluxo" }
        assertEquals(9, fluxo.count)
        assertEquals(3, fluxo.hint.size)
        assertFalse("fluxo" in fluxo.hint)
        assertEquals(1, index.entries.first { it.name == "Garten" }.count)
    }

    @Test
    fun topicIndexCapsActiveTopicsAndSkipsMerged() = runBlocking {
        val now = Instant.now()
        val topics = mutableListOf<Topic>()
        val thoughts = mutableListOf<Thought>()
        repeat(26) { i ->
            topics.add(Topic("t_$i", "Thema $i", TopicIcon.list, Owner.ai, now))
            repeat(2) { k ->
                thoughts.add(
                    StoreSupport.thought(
                        createdAt = now.minusSeconds((i * 10 + k) * 60L),
                        title = "Gedanke $i-$k",
                        text = "Inhalt $i",
                        topicId = "t_$i",
                    ),
                )
            }
        }
        topics.add(Topic("t_alias", "Alt", TopicIcon.list, Owner.ai, mergedInto = "t_0"))
        thoughts.add(StoreSupport.thought(title = "Altes Thema", text = "x", topicId = "t_alias"))
        topics.add(Topic("t_old", "Uralt", TopicIcon.list, Owner.ai, now.minusSeconds(90 * 86400)))
        thoughts.add(
            StoreSupport.thought(
                createdAt = now.minusSeconds(70 * 86400),
                title = "Lange her",
                text = "y",
                topicId = "t_old",
            ),
        )
        val index =
            CandidateFinder(thoughts, topics, now = { now }).topicIndex("Inhalt 0", listOf("de"))
        assertTrue(index.full)
        assertEquals(24, index.entries.size)
        assertFalse(index.entries.any { it.topicID in listOf("t_alias", "t_old") })
        val summaries = TopicIndex.summaries(topics, thoughts)
        assertEquals(3, summaries.first { it.topic.id == "t_0" }.count)
        assertFalse(summaries.any { it.topic.id == "t_alias" })
        assertFalse(summaries.first { it.topic.id == "t_old" }.isActive)
    }

    @Test
    fun persistedIndexIsReusedAndUpdated() = runBlocking {
        val root = StoreSupport.temporaryRoot()
        try {
            val store = ThoughtStore(root)
            val thought = StoreSupport.thought(title = "Halbmarathon", text = "Training am Rhein")
            store.save(thought)
            val finder = CandidateFinder(store)
            val initial = finder.rank("Rhein", listOf("de"), "").single().keyword
            assertTrue(initial > 0)
            store.save(store.thought(thought.id)!!.copy(text = "Training im Wald"))
            finder.didChange(store.thought(thought.id)!!)
            assertEquals(0.0, finder.rank("Rhein", listOf("de"), "").single().keyword, 0.0)
            assertTrue(finder.rank("Wald", listOf("de"), "").single().keyword > 0)
            assertEquals(
                setOf("wald", "wies", "wiese"),
                finder.keywords("Wald und Wiese im Wald", "de").toSet(),
            )
            // New finder rebuilds from source; Android deliberately does not persist this
            // derivative.
            assertEquals(
                finder.rank("Wald", listOf("de"), ""),
                CandidateFinder(store).rank("Wald", listOf("de"), ""),
            )
            assertFalse(Files.exists(root.resolve("embeddings.bin")))
        } finally {
            StoreSupport.remove(root)
        }
    }
}
