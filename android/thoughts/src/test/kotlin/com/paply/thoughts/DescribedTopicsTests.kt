package com.paply.thoughts

import com.paply.thoughts.ai.*
import com.paply.thoughts.model.*
import com.paply.thoughts.nlp.*
import com.paply.thoughts.processing.*
import com.paply.thoughts.store.*
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class DescribedTopicsTests {
    private val aramNote =
        "Meine Firma Aram UG – Kunden Müller Bau und Kowalski, Steuerberaterin Frau Albrecht"
    private val aram =
        Topic(
            id = "t_aram",
            title = "Aram UG",
            icon = TopicIcon.briefcase,
            owner = Owner.user,
            createdAt = Instant.ofEpochSecond(1792000000),
            note = aramNote,
        )
    private val club =
        Topic(
            id = "t_club",
            title = "Ruderclub",
            icon = TopicIcon.users,
            owner = Owner.user,
            createdAt = Instant.ofEpochSecond(1792000000),
            note = "Ruderverein RV Germania Beuel, Training mit den Junioren, Jahrgang 1987",
        )
    private val cooking = topic("Kochen", "Rezepte mit Reis")
    private val workshop = topic("Werkstatt", "Kunde Fischer, Aufträge und Rechnungen")
    private val grandma = topic("Oma Ilse", "Meine Oma in Köln, Arzttermine, Pflege")
    private val house =
        topic("Haus Lindenstraße", "Unser Haus mit Garten, Handwerker Schulte, Nebenkosten")
    private val brandt =
        topic(
                "Brandt Logistik",
                "Lagerverwaltung für Brandt Logistik in Troisdorf – Ansprechpartner Herr Wiechert",
            )
            .copy(id = "t_brandt")
    private val kessler =
        topic(
                "Kessler Digital",
                "Meine Beratungsfirma Kessler Digital UG – Kunden Brandt Logistik und Vogelsang, Buchhaltung bei Frau Okafor",
            )
            .copy(id = "t_kessler")

    private fun topic(title: String, note: String?) =
        Topic(title = title, note = note, icon = TopicIcon.list, owner = Owner.user)

    private fun hits(text: String) = TopicMentions.matches(aram, text)

    private fun hits(topic: Topic, text: String) = TopicMentions.matches(topic, text)

    private fun entry(t: Topic, count: Int = 0) =
        TopicIndexEntry(t.id, t.title, count, emptyList(), t.describedNote)

    private fun redirect(name: String, topics: List<Topic>) =
        TopicHygiene.matchExisting(name, topics.map { entry(it) })?.topicID

    /** The production local ranker now exercises the Part-A mention/pinning regressions. */
    private fun index(
        topics: List<Topic>,
        thoughts: List<Thought>,
        text: String,
    ): CandidateFinding.TopicIndex = runBlocking {
        com.paply.thoughts.local.CandidateFinder(thoughts, topics).topicIndex(text, listOf("de"))
    }

    @Test
    fun olderTopicsDecodeWithoutNoteAndNoNoteIsWritten() {
        val t =
            ThoughtJSON.decode<Topic>(
                """{"id":"t_a","title":"Garten","icon":"leaf","owner":"ai","createdAt":1792000000000,"mergedInto":null}"""
                    .toByteArray(),
            )
        assertNull(t.note)
        assertNull(t.describedNote)
        assertFalse(t.isUserDefined)
        assertFalse(String(ThoughtJSON.encode(t)).contains("note"))
    }

    @Test
    fun noteRoundTripsAndSurvivesAReload() {
        val bytes = ThoughtJSON.encode(aram)
        assertTrue(String(bytes).contains("\"note\""))
        assertEquals(aram, ThoughtJSON.decode<Topic>(bytes))
        val root = StoreSupport.temporaryRoot()
        try {
            ThoughtStore(root)
                .saveTopics(
                    listOf(aram, topic("Garten", null).copy(id = "t_plain", owner = Owner.ai)),
                )
            val reloaded = ThoughtStore(root)
            assertEquals(aramNote, reloaded.topics().first { it.id == "t_aram" }.note)
            assertNull(reloaded.topics().first { it.id == "t_plain" }.note)
        } finally {
            StoreSupport.remove(root)
        }
    }

    @Test
    fun noteIsNormalised() {
        assertNull(Topic.normalizedNote(null))
        assertNull(Topic.normalizedNote("  \n "))
        assertEquals("Aram UG", Topic.normalizedNote("  Aram UG \n"))
        assertEquals(Topic.maxNoteLength, Topic.normalizedNote("x".repeat(300))?.length)
        assertTrue(aram.isUserDefined)
        assertTrue(topic("X", "Kunde Vogelsang").copy(owner = Owner.ai).isUserDefined)
    }

    @Test
    fun meaningfulTermsOnly() {
        assertEquals(
            listOf("Aram", "Müller", "Bau", "Kowalski", "Steuerberaterin", "Albrecht"),
            TopicMentions.terms(aram).map { it.original },
        )
        val terms = TopicMentions.terms(club).map { it.original }
        assertTrue(terms.containsAll(listOf("Germania", "Beuel", "Junioren")))
        assertFalse(terms.any { it in listOf("RV", "1987", "mit", "den") })
        assertTrue(TopicMentions.terms(topic("Garten", null)).isEmpty())
        assertTrue(hits(topic("Garten", null), "Im Garten blüht es").isEmpty())
    }

    @Test
    fun namesAreFoundAtWordBoundariesIgnoringCaseAndAccents() {
        assertEquals(listOf("Müller", "Bau"), hits("Heute mit Müller Bau telefoniert"))
        assertEquals(listOf("Müller"), hits("das angebot von mueller"))
        assertEquals(listOf("Müller"), hits("Muller hat zurückgerufen"))
        assertEquals(listOf("Aram"), hits("ARAM braucht neue Visitenkarten"))
        assertEquals(listOf("Aram"), hits("die Aram-Rechnung ist raus"))
        assertEquals(
            listOf("Jörg", "Weiß"),
            hits(topic("Jörg", "Nachbar Jörg Weiß"), "joerg und weiss"),
        )
    }

    @Test
    fun simpleInflectionsInBothDirections() {
        assertEquals(listOf("Kowalski"), hits("Kowalskis Angebot liegt vor"))
        assertEquals(listOf("Albrecht"), hits("Albrechts Rechnung kam heute"))
        // iOS with dictionaries: [Beuel]. Android uses documented dictionary-unavailable fallback:
        // no -er hint.
        assertEquals(emptyList<String>(), hits(club, "die Beueler Fähre fällt aus"))
        assertEquals(
            listOf("Ruderverein", "Training"),
            hits(club, "beim Training der Rudervereine"),
        )
        assertEquals(
            listOf("Müllers"),
            hits(topic("Bäckerei", "Kunden Müllers und Omas Laden"), "Müller ruft an"),
        )
        assertEquals(
            listOf("Oma"),
            hits(topic("Oma Ilse", "Meine Oma in Wuppertal"), "Omas Geburtstag"),
        )
    }

    @Test
    fun noFalseHits() {
        listOf(
                "Die Firma hat neue Kunden, Frau Meier ruft an und die UG ist gegründet",
                "Bauarbeiten am Haus und ein Aramäisch-Kurs",
                "Brandschutz und Kowalczyk",
            )
            .forEach { assertTrue(hits(it).isEmpty()) }
        assertTrue(hits(club, "it is fine, the RV is parked, 1987 was good").isEmpty())
        assertTrue(hits(topic("Oma Ilse", "Oma in Wuppertal"), "Urlaub im Oman").isEmpty())
    }

    @Test
    fun aWordStartIsNoInflection() {
        assertTrue(hits(cooking, "Reisen nach Lissabon und eine Reise nach Porto").isEmpty())
        assertEquals(
            listOf("Kochen", "Rezepte", "Reis"),
            hits(cooking, "Reis kochen, dann die Rezepte sortieren"),
        )
        assertTrue(hits(workshop, "Fisch fürs Wochenende kaufen").isEmpty())
        assertEquals(listOf("Fischer", "Aufträge"), hits(workshop, "Fischers Auftrag ist da"))
        // iOS [Beuel] becomes [] only for its unavailable dictionary-dependent -er hint.
        assertTrue(hits(club, "die Bonner Fähre und die Beueler Fähre").isEmpty())
        assertTrue(hits(grandma, "Kölner Dom besichtigen").isEmpty())
        assertEquals(listOf("Brandt"), hits(brandt, "bei Brandts läuft die Inventur"))
        assertEquals(listOf("Brandt"), hits(kessler, "bei Brandts läuft die Inventur"))
    }

    @Test
    fun commonWordsOnlyGuardTheErHint() {
        assertFalse(CommonWords.available)
        // Original iOS expects false for the first seven names; missing dictionaries deliberately
        // return true for all.
        listOf(
                "Kowalski",
                "Brandt",
                "Germania",
                "Beuel",
                "Ilse",
                "Aram",
                "Okafor",
                "Köln",
                "Pflege",
                "Training",
                "Garten",
                "Reis",
                "Fisch",
                "Fischer",
                "Müller",
                "Bau",
                "Arzttermine",
                "Ruderverein",
            )
            .forEach { assertTrue(it, CommonWords.contains(it)) }
    }

    @Test
    fun namesFromADescriptionAreOnlyHintsTheTitleRedirects() {
        val topics =
            listOf(aram, club, topic("Garten", null).copy(id = "t_garden", owner = Owner.ai))
        listOf(
                "Kowalskis" to "Kowalskis Angebot liegt vor, die Rechnung geht über Aram",
                "Kowalski" to "Kowalski ruft wegen Aram an",
                "Kunde Kowalski" to "Kowalski und Albrecht brauchen die Belege",
                "Müller Bau" to "Müller Bau will das Angebot bis Freitag, Kowalski auch",
                "Germania" to "Germania-Regatta: die Junioren brauchen neue Trikots",
            )
            .forEach { (name, text) ->
                assertTrue(topics.any { hits(it, text).isNotEmpty() })
                assertNull(redirect(name, topics))
            }
        assertEquals(listOf("Brandt"), hits(brandt, "bei Brandts läuft die Inventur"))
        assertEquals("t_aram", redirect("aram ug", topics))
        assertEquals("t_aram", redirect("Aram-UG", topics))
        assertEquals("t_club", redirect("Ruderclubs", topics))
        assertEquals("t_garden", redirect("Garten", topics))
        listOf("Aram", "Müller", "Bau", "Kita Beuel", "Firma", "Ruder").forEach {
            assertNull(redirect(it, topics))
        }
    }

    @Test
    fun aCompanyNameRedirectsOnlyAsATitle() {
        val c = topic("Müller Bau", null).copy(id = "t_mb")
        assertNull(redirect("Müller Bau", listOf(aram)))
        assertEquals(listOf("Müller", "Bau"), hits("Müller Bau will das Angebot"))
        assertEquals("t_mb", redirect("Müller Bau", listOf(aram, c)))
        assertEquals("t_mb", redirect("Mueller-Bau", listOf(aram, c)))
        assertNull(redirect("Muller Bau", listOf(aram, c)))
    }

    @Test
    fun commonWordsWordStartsAndDescribedNamesAreNeverRedirected() {
        listOf(
                "Reisen" to cooking,
                "Fisch" to workshop,
                "Köln" to grandma,
                "Pflege" to grandma,
                "Training" to club,
                "Garten" to house,
                "Ilse" to grandma,
                "Reisen" to topic("Reis", null),
                "Fisch" to topic("Fischer", null),
            )
            .forEach { (n, t) -> assertNull(redirect(n, listOf(t))) }
        val koeln = topic("Oma Ilse", "Meine Oma in Koeln, Arzttermine")
        assertNull(redirect("Koeln", listOf(koeln)))
        assertNull(redirect("Köln", listOf(koeln)))
        assertEquals(listOf("Koeln"), hits(koeln, "Ausflug nach Koeln"))
        val office = topic("Kessler Digital", "Beratung, Home Office montags")
        assertNull(redirect("Home Office", listOf(office)))
        assertEquals(listOf("Home", "Office"), hits(office, "Home Office ab nächster Woche"))
    }

    @Test
    fun titleBeatsANameFromAnotherDescription() {
        val both = listOf(kessler, brandt)
        assertEquals("t_brandt", redirect("Brandt Logistik", both))
        assertEquals("t_brandt", redirect("brandt logistik", both))
        assertNull(redirect("Brandts", both))
        assertNull(redirect("Okafor", both))
    }

    @Test
    fun ambiguousMatchesNeverDecide() {
        val a = topic("Paply App", null).copy(id = "t_a")
        val b = topic("Paply-App", null).copy(id = "t_b", owner = Owner.ai)
        assertEquals(
            listOf("t_a", "t_b"),
            TopicHygiene.sameNamedTopics("paply app", listOf(a, b)).map { it.id },
        )
        assertNull(redirect("paply app", listOf(a, b)))
        assertNull(redirect("PAPLY-APP", listOf(a, b)))
        assertEquals("t_a", redirect("Paply App", listOf(a)))
        assertEquals(
            "t_a",
            TopicHygiene.matchExisting("Paply App", listOf(entry(a), entry(a, 3)))?.topicID,
        )
        val shop = topic("Werkstatt", "Kunde Kowalski, Reparaturen").copy(id = "t_shop2")
        val club = topic("Schachclub", "Trainer Kowalski").copy(id = "t_club2")
        assertEquals(
            setOf("t_shop2", "t_club2"),
            index(listOf(shop, club), emptyList(), "Kowalski hat angerufen")
                .entries
                .filter { it.mentioned }
                .map { it.topicID }
                .toSet(),
        )
        assertNull(redirect("Kowalski", listOf(shop, club)))
    }

    @Test
    fun mentionedTopicsArePinnedEvenBeyondTheCaps() {
        val now = Instant.ofEpochSecond(1793093400)
        val topics =
            (0 until 26).map {
                topic("Thema $it", null).copy(id = "t_$it", owner = Owner.ai, createdAt = now)
            } +
                aram +
                club.copy(
                    id = "t_old",
                    owner = Owner.ai,
                    createdAt = now.minusSeconds(200 * 86400),
                    note = "Ruderverein Germania",
                )
        val thoughts =
            topics.take(26).flatMap { t ->
                List(2) {
                    StoreSupport.thought(
                        createdAt = now,
                        title = "Gedanke",
                        text = "Inhalt",
                        topicId = t.id,
                    )
                }
            }
        val i =
            index(topics, thoughts, "Inhalt 0, Kowalski hat angerufen, danach Germania-Training")
        assertTrue(i.full)
        assertTrue(i.entries.size <= 32)
        assertEquals(setOf("t_aram", "t_old"), i.entries.take(2).map { it.topicID }.toSet())
        assertEquals(
            listOf("t_aram", "t_old"),
            i.entries.filter { it.mentioned }.map { it.topicID }.sorted(),
        )
        assertEquals(aramNote, i.entries.first { it.topicID == "t_aram" }.about)
        val plain = index(topics, thoughts, "Inhalt 3")
        assertFalse(plain.entries.any { it.mentioned })
        assertFalse(plain.entries.any { it.topicID == "t_old" })
        assertTrue(plain.entries.filter { it.about != null }.all { it.topicID == "t_aram" })
    }

    @Test
    fun describedFixtureMentionsMatchTheExpectation() {
        val fixture =
            Json.parseToJsonElement(
                    javaClass.getResourceAsStream("/store-a.json")!!.bufferedReader().readText(),
                )
                .jsonObject
        val objectJSON =
            Json.parseToJsonElement(
                    javaClass.getResourceAsStream("/described.json")!!.bufferedReader().readText(),
                )
                .jsonObject
        fun topics(j: JsonObject): List<Topic> {
            val raw = j["topics"]!!
            return (if (raw is JsonObject) raw["topics"]!! else raw).jsonArray.map {
                ThoughtJSON.json.decodeFromString<Topic>(it.toString())
            }
        }
        val extra = topics(objectJSON)
        assertEquals(4, extra.size)
        assertTrue(extra.all { it.describedNote != null && it.owner == Owner.user })
        val cases = objectJSON["cases"]!!.jsonArray
        assertEquals(8, cases.size)
        val ts = topics(fixture) + extra
        for (c in cases) {
            val item = c.jsonObject
            val text = item["transcript"]!!.jsonPrimitive.content
            val expected =
                item["expect"]!!
                    .jsonObject["mentioned"]!!
                    .jsonArray
                    .map { it.jsonPrimitive.content }
                    .toSet()
            val hay = TopicMentions.Haystack(text)
            assertEquals(
                item["id"].toString(),
                expected,
                ts.filter { TopicMentions.matches(TopicMentions.terms(it), hay).isNotEmpty() }
                    .map { it.title }
                    .toSet(),
            )
            val i = index(ts, emptyList(), text)
            assertEquals(expected, i.entries.filter { it.mentioned }.map { it.name }.toSet())
            assertEquals(
                extra.map { it.title }.toSet(),
                i.entries.filter { it.about != null }.map { it.name }.toSet(),
            )
        }
    }

    @Test
    fun promptCarriesAboutAndMentionedOnlyWhereSet() {
        val topics =
            listOf(
                TopicIndexEntry(
                    "t_aram",
                    "Aram UG",
                    0,
                    emptyList(),
                    "Meine Firma Aram UG\nKunden Müller Bau",
                    true,
                ),
            ) +
                AIFixture.topics +
                TopicIndexEntry("t_club", "Ruderclub", 2, listOf("Boot"), "Ruderverein Germania")
        val b = ThoughtPrompt.build(AIFixture.input(topics = topics))
        val lines =
            Json.parseToJsonElement(b.user).jsonObject["topics"]!!.jsonArray.map { it.jsonObject }
        assertEquals(
            "Meine Firma Aram UG; Kunden Müller Bau",
            lines[0]["about"]!!.jsonPrimitive.content,
        )
        assertEquals(JsonPrimitive(true), lines[0]["mentioned"])
        assertEquals("Paply", lines[1]["name"]!!.jsonPrimitive.content)
        assertNull(lines[1]["about"])
        assertNull(lines[1]["mentioned"])
        assertEquals("Ruderverein Germania", lines.last()["about"]!!.jsonPrimitive.content)
        assertNull(lines.last()["mentioned"])
        val plain = ThoughtPrompt.build(AIFixture.input())
        assertFalse(plain.user.contains("\"about\""))
        assertFalse(plain.user.contains("\"mentioned\""))
        assertTrue(ThoughtPrompt.system.contains("about is the user's own description of a topic"))
        assertTrue(
            ThoughtPrompt.system.contains(
                "a name mentioned only in passing does not decide the topic.",
            ),
        )
    }

    @Test
    fun mentionedTopicsSurviveTheTopicLimitAndEveryTrimStep() {
        val topics =
            (1..40).map {
                TopicIndexEntry(
                    "t_$it",
                    "Thema $it",
                    it,
                    listOf("Wort${it}a", "Wort${it}b", "Wort${it}c"),
                    if (it == 35) "Firma Aram UG, Kunden Müller Bau"
                    else if (it % 4 == 0) "Beschreibung $it mit Namen, Firmen und Personen"
                    else null,
                    it == 35,
                )
            }
        val normal = ThoughtPrompt.build(AIFixture.input(topics = topics))
        assertEquals(32, normal.aliases.topics.size)
        assertTrue(normal.aliases.topics.values.any { it.topicID == "t_35" })
        assertEquals(31, normal.aliases.topics.values.count { !it.mentioned })
        val candidates =
            (1..8).map {
                CandidateEntry(
                    "s_$it",
                    "Kandidat $it mit längerem Titel",
                    "t_$it",
                    "vor $it Tagen",
                    "Auszug ".repeat(30),
                    0.5,
                )
            }
        var trimmed: ThoughtPrompt.Built? = null
        for (n in 60..260 step 5) {
            val b =
                runCatching {
                    ThoughtPrompt.build(
                        AIFixture.input(
                            transcript = "Das ist ein langer Gedanke über das Projekt. ".repeat(n),
                            topics = topics,
                            candidates = candidates,
                        ),
                    )
                }
                    .getOrNull() ?: break
            if ("topics>16" in b.trimmed) {
                trimmed = b
                break
            }
        }
        val b = trimmed!!
        assertEquals(listOf("excerpts", "candidates>3", "hints", "about", "topics>16"), b.trimmed)
        assertEquals(16, b.aliases.topics.size)
        val alias = b.aliases.topics.entries.first { it.value.topicID == "t_35" }.key
        val lines =
            Json.parseToJsonElement(b.user).jsonObject["topics"]!!.jsonArray.map { it.jsonObject }
        val line = lines.first { it["id"]!!.jsonPrimitive.content == alias }
        assertEquals("Firma Aram UG, Kunden Müller Bau", line["about"]!!.jsonPrimitive.content)
        assertEquals(JsonPrimitive(true), line["mentioned"])
        assertEquals(1, lines.count { it["about"] != null })
    }

    @Test
    fun onlyTheTitleOfADescribedTopicIsRedirected() {
        val topics =
            AIFixture.topics + entry(aram).copy(mentioned = true) + entry(club, 2) + entry(grandma)
        val transcript =
            AIFixture.transcript + " Müller Bau will das Angebot bis Freitag, Kowalski auch."
        val answer =
            AIFixture.answer(
                topic = AIFixture.topic("new", name = "Müller Bau", symbol = "briefcase"),
            )
        val result =
            AIFixture.validate(answer, AIFixture.input(transcript = transcript, topics = topics))
        assertEquals(TopicDecision.New("Müller Bau", TopicIcon.briefcase), result.topic)
        assertFalse(result.rejections.any { it.startsWith("topic:") })
        val full =
            AIFixture.validate(
                answer,
                AIFixture.input(transcript = transcript, topics = topics, topicsFull = true),
            )
        assertEquals(TopicDecision.None, full.topic)
        assertTrue("topic:full" in full.rejections)
        listOf(false, true).forEach { f ->
            val r =
                AIFixture.validate(
                    AIFixture.answer(
                        topic = AIFixture.topic("new", name = "Aram-UG", symbol = "briefcase"),
                    ),
                    AIFixture.input(transcript = transcript, topics = topics, topicsFull = f),
                )
            assertEquals(TopicDecision.Existing("t_aram"), r.topic)
            assertTrue("topic:duplicate" in r.rejections)
        }
        listOf(
                "Kita Beuel" to TopicIcon.home,
                "Köln" to TopicIcon.mapPin,
                "Kowalski" to TopicIcon.users,
            )
            .forEach { (n, icon) ->
                val r =
                    AIFixture.validate(
                        AIFixture.answer(
                            topic = AIFixture.topic("new", name = n, symbol = icon.rawValue),
                        ),
                        AIFixture.input(
                            transcript = transcript + " Danach mit Oma nach Köln.",
                            topics = topics,
                        ),
                    )
                assertEquals(TopicDecision.New(n, icon), r.topic)
            }
    }

    @Test
    fun ambiguousTitlesBecomeNone() {
        val topics =
            AIFixture.topics +
                TopicIndexEntry("t_app1", "Paply App", 3, emptyList()) +
                TopicIndexEntry("t_app2", "Paply-App", 1, emptyList())
        val r =
            AIFixture.validate(
                AIFixture.answer(
                    topic = AIFixture.topic("new", name = "paply app", symbol = "code"),
                ),
                AIFixture.input(topics = topics),
            )
        assertEquals(TopicDecision.None, r.topic)
        assertTrue("topic:ambiguous" in r.rejections)
    }

    @Test
    fun userTopicsAreNeverPairedAndKeepTheirIDAndName() {
        val profiles =
            listOf(
                TopicHygiene.Profile("a", "Wohnung", 4, listOf("miete"), isUserDefined = true),
                TopicHygiene.Profile("b", "Wohnungen", 3, listOf("miete"), isUserDefined = true),
                TopicHygiene.Profile("c", "Wohnungssuche", 2, listOf("miete")),
            )
        val pairs = TopicHygiene.candidatePairs(profiles, emptySet()).map { it.a to it.b }.toSet()
        assertFalse("a" to "b" in pairs)
        assertTrue("a" to "c" in pairs && "b" to "c" in pairs)
        val json =
            """{"pairs":[{"a":"c","b":"a","merge":true,"name":"Wohnungssuche","reason":"gleich"},{"a":"a","b":"b","merge":true,"name":"Wohnen","reason":"x"}]}"""
        assertEquals(
            listOf(TopicSuggestion("a", "c", null, "gleich")),
            TopicHygiene.validateSuggestions(json, listOf("a" to "c", "a" to "b"), setOf("a", "b")),
        )
        assertEquals(
            listOf(TopicSuggestion("c", "a", "Wohnungssuche", "gleich")),
            TopicHygiene.validateSuggestions(json, listOf("a" to "c")),
        )
    }

    @Test
    fun hygieneOnlySuggestsAndNeverTouchesTopicsOrThoughts() = runBlocking {
        Harness().use { h ->
            val ai = topic("Aram", null).copy(id = "t_ai", owner = Owner.ai)
            h.store.saveTopics(listOf(aram, ai))
            repeat(2) {
                h.store.save(
                    StoreSupport.thought(
                        title = "Aram Rechnung",
                        text = "Rechnung für Aram",
                        topicId = ai.id,
                    ),
                )
            }
            val topics = h.store.topics()
            val thoughts = h.store.all()
            MockWebServer().use { s ->
                s.enqueue(
                    AIFixture.reply(
                        """{"pairs":[{"a":"t_ai","b":"t_aram","merge":true,"name":"Aram","reason":"gleiche Firma"}]}""",
                        total = 500,
                    ),
                )
                assertEquals(
                    TopicHygieneRunner.Outcome.Suggestions(
                        listOf(TopicSuggestion("t_aram", "t_ai", null, "gleiche Firma")),
                    ),
                    TopicHygieneRunner.run(
                        h.store,
                        h.ledger,
                        "test-placeholder",
                        TestTopicIndex,
                        force = true,
                        baseURL = s.url("/"),
                        now = h.clock.now,
                    ),
                )
                assertEquals(topics, h.store.topics())
                assertEquals(thoughts, h.store.all())
                assertEquals(1, h.store.pendingSuggestions().size)
            }
        }
    }

    @Test
    fun aRunOnlyOrdersItsOwnThoughtAndOnlyAppendsTopics() = runBlocking {
        Harness().use { h ->
            val garden = topic("Garten", null).copy(id = "t_garden", owner = Owner.ai)
            val alias =
                topic("Beete", null).copy(id = "t_beds", owner = Owner.ai, mergedInto = "t_garden")
            val user = topic("Lesen", null).copy(id = "t_mine")
            h.store.saveTopics(listOf(aram, alias, garden, user))
            val other =
                StoreSupport.thought(
                    createdAt = h.clock.now.minusSeconds(600),
                    title = "Tomaten",
                    text = "Tomaten im Garten",
                    topicId = "t_garden",
                )
            h.store.save(other)
            val topics = h.store.topics()
            val before = h.store.thought(other.id)
            h.structurer.push(
                processingSuccess(
                    topic = TopicDecision.New("Aram-UG", TopicIcon.briefcase),
                    related = listOf(RelatedDraft(other.id, LinkKind.continues, "Gleicher Garten")),
                ),
            )
            h.transcriber.push(
                TranscriptionResult.Success(
                    "Müller Bau will das Angebot bis Freitag, Kowalski auch",
                    listOf("de"),
                    2.0,
                    "whisper-large-v3",
                ),
            )
            val first = h.capture()
            h.run()
            assertEquals("t_aram", h.thought(first)?.topicId)
            assertEquals(Owner.ai, h.thought(first)?.topicOwner)
            assertEquals(listOf(other.id), h.thought(first)?.links?.map { it.target })
            assertEquals(topics, h.store.topics())
            assertEquals(before, h.store.thought(other.id))
            h.structurer.push(processingSuccess(topic = TopicDecision.Existing("t_mine")))
            val second = h.capture()
            h.run()
            assertEquals("t_mine", h.thought(second)?.topicId)
            assertEquals(topics, h.store.topics())
            h.structurer.push(
                processingSuccess(topic = TopicDecision.New("Lissabon", TopicIcon.plane)),
            )
            val third = h.capture()
            h.run()
            val after = h.store.topics()
            assertEquals(topics, after.dropLast(1))
            assertEquals("Lissabon", after.last().title)
            assertEquals(Owner.ai, after.last().owner)
            assertNull(after.last().note)
            assertEquals(after.last().id, h.thought(third)?.topicId)
            assertEquals(before, h.store.thought(other.id))
        }
    }

    @Test
    fun describedTopicStaysWhenItsLastThoughtIsPurged() {
        Harness().use { h ->
            h.store.saveTopics(listOf(aram, topic("Laufen", null).copy(id = "t_plain")))
            val a = StoreSupport.thought(topicId = "t_aram")
            val b = StoreSupport.thought(topicId = "t_plain")
            h.store.save(a)
            h.store.save(b)
            h.store.purge(listOf(a.id, b.id))
            assertEquals(listOf("t_aram"), h.store.topics().map { it.id })
        }
    }
}
