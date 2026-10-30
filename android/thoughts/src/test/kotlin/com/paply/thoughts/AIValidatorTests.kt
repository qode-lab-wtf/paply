package com.paply.thoughts

import com.paply.thoughts.AIFixture as F
import com.paply.thoughts.ai.*
import com.paply.thoughts.processing.RawText
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class AIValidatorTitleTests {
    @Test
    fun goodTitleIsKept() {
        assertEquals("Wohnung Oranienstraße Unterlagen", F.validate(F.answer()).title)
    }

    @Test
    fun quotesAndFinalPeriodAreRemoved() {
        assertEquals(
            "Wohnung Oranienstraße",
            F.validate(F.answer(title = "„Wohnung Oranienstraße.“")).title,
        )
        assertEquals(
            "Makler Oranienstraße",
            F.validate(F.answer(title = "\"Makler Oranienstraße\"…")).title,
        )
    }

    @Test
    fun onlyTheFirstLineCounts() {
        assertEquals(
            "Makler Oranienstraße",
            F.validate(F.answer(title = "Makler Oranienstraße\nzweite Zeile")).title,
        )
    }

    @Test
    fun tooLongTitleFallsBack() {
        val r = F.validate(F.answer(title = "Wohnung ".repeat(10)))
        assertTrue("title" in r.rejections)
        assertEquals("Zur Wohnung in der Oranienstraße: Ich …", r.title)
    }

    @Test
    fun newDigitInTitleFallsBack() {
        assertTrue("title" in F.validate(F.answer(title = "Miete 1.500 Euro")).rejections)
        assertEquals("Miete 1.450 Euro", F.validate(F.answer(title = "Miete 1.450 Euro")).title)
    }

    @Test
    fun titleWithoutTranscriptWordFallsBack() {
        assertTrue("title" in F.validate(F.answer(title = "Neues Zuhause")).rejections)
    }

    @Test
    fun inflectedWordCountsAsTranscriptWord() {
        assertFalse("title" in F.validate(F.answer(title = "Unterlagen an Makler")).rejections)
    }

    @Test
    fun emptyTitleUsesTextStart() {
        val r = F.validate(F.answer(title = ""))
        assertEquals("Zur Wohnung in der Oranienstraße: Ich …", r.title)
        assertTrue("title" in r.rejections)
    }

    @Test
    fun fallbackFromRawSkipsFillersAndShortTextHasNoEllipsis() {
        assertEquals(
            "zur Wohnung in der Oranienstraße, ich …",
            ThoughtValidator.fallbackTitle("Ähm, zur Wohnung in der Oranienstraße, ich hab"),
        )
        assertEquals(
            "zur Wohnung in der Oranienstraße, ich",
            ThoughtValidator.fallbackTitle("Ähm, zur Wohnung in der Oranienstraße, ich"),
        )
        assertEquals("Milch kaufen", ThoughtValidator.fallbackTitle("Ähm, äh Milch kaufen."))
        assertEquals(
            "Eins zwei drei vier fünf sechs …",
            ThoughtValidator.fallbackTitle("Eins zwei drei vier fünf sechs sieben"),
        )
    }

    @Test
    fun cjkTitleNeedsASharedCharacterPair() {
        val t = "我明天要去看那套公寓，然后给中介打电话。"
        val i = F.input(t, emptyList(), emptyList())
        assertEquals(
            "那套公寓",
            F.validate(F.answer(title = "那套公寓", clean = t, topic = F.topic("none")), i).title,
        )
        assertTrue(
            "title" in
                F.validate(F.answer(title = "旅行计划", clean = t, topic = F.topic("none")), i)
                    .rejections,
        )
    }
}

class AIValidatorTextTests {
    @Test
    fun cleanTextWithParagraphsIsKept() {
        val r = F.validate(F.answer())
        assertEquals(F.goodClean, r.cleanText)
        assertFalse(r.rejections.any { it.startsWith("text") })
    }

    @Test
    fun summaryIsRejected() {
        val r = F.validate(F.answer(clean = "Makler angerufen, Unterlagen bis Freitag."))
        assertNull(r.cleanText)
        assertTrue("text:length" in r.rejections)
    }

    @Test
    fun droppedNegationIsRejected() {
        assertTrue(
            "text:negation" in
                F.validate(
                        F.answer(
                            clean =
                                F.goodClean.replace("und nicht verhandelbar", "und verhandelbar"),
                        ),
                    )
                    .rejections,
        )
    }

    @Test
    fun changedNumberIsRejected() {
        assertTrue(
            "text:digits" in
                F.validate(F.answer(clean = F.goodClean.replace("1.450", "1.540"))).rejections,
        )
    }

    @Test
    fun inventedContentIsRejected() {
        val r =
            F.validate(
                F.answer(
                    clean =
                        F.goodClean +
                            " Außerdem sollte ich unbedingt einen Umzugswagen reservieren, die Nachbarn informieren und Kartons besorgen.",
                ),
            )
        assertNull(r.cleanText)
        assertTrue(r.rejections.any { it in listOf("text:length", "text:added") })
    }

    @Test
    fun metaAnswerIsRejected() {
        assertTrue(
            "text:meta" in
                F.validate(F.answer(clean = "Hier ist der bereinigte Text: " + F.goodClean))
                    .rejections,
        )
    }

    @Test
    fun bulletListFromSpokenEnumerationIsKept() {
        val t =
            "Für den Umzug brauche ich ähm Kartons, Klebeband, Luftpolsterfolie und einen Transporter."
        val c =
            "Für den Umzug brauche ich:\n• Kartons\n• Klebeband\n• Luftpolsterfolie\n• einen Transporter"
        assertEquals(
            c,
            F.validate(F.answer(title = "Umzug Material", clean = c), F.input(t)).cleanText,
        )
    }

    @Test
    fun emptyCleanTextButTitleKeepsTheRest() {
        val r = F.validate(F.answer(clean = ""))
        assertNull(r.cleanText)
        assertTrue("text:empty" in r.rejections)
        assertEquals(TopicDecision.Existing("t_umzug"), r.topic)
    }

    @Test
    fun bothEmptyIsUnusable() {
        val i = F.input()
        assertEquals(
            ThoughtValidator.Failure.Code.empty,
            (ThoughtValidator.validate(
                        F.answer(title = " ", clean = ""),
                        i,
                        ThoughtPrompt.build(i).aliases,
                    )
                    .exceptionOrNull() as ThoughtValidator.Failure)
                .code,
        )
    }

    @Test
    fun unreadableJSONIsUnusable() {
        val i = F.input()
        for (json in
            listOf("{\"title\": \"x\"", "{\"title\": \"x\", \"clean_text\": \"y\"}")) assertEquals(
            ThoughtValidator.Failure.Code.unreadable,
            (ThoughtValidator.validate(json, i, ThoughtPrompt.build(i).aliases).exceptionOrNull()
                    as ThoughtValidator.Failure)
                .code,
        )
    }

    @Test
    fun resolvedSelfCorrectionIsAccepted() {
        val t = "Wir treffen uns am Donnerstag um 15 Uhr, ich meine um 16 Uhr, im Café am Markt."
        val c = "Wir treffen uns am Donnerstag um 16 Uhr im Café am Markt."
        assertEquals(
            c,
            F.validate(
                    F.answer(title = "Treffen Café am Markt", clean = c, topic = F.topic("none")),
                    F.input(t),
                )
                .cleanText,
        )
    }
}

class AIValidatorTopicTests {
    @Test
    fun existingAliasMapsToRealID() {
        assertEquals(
            TopicDecision.Existing("t_paply"),
            F.validate(F.answer(topic = F.topic("existing", id = "t1"))).topic,
        )
    }

    @Test
    fun unknownAliasBecomesNone() {
        val r = F.validate(F.answer(topic = F.topic("existing", id = "t9")))
        assertEquals(TopicDecision.None, r.topic)
        assertTrue("topic:alias" in r.rejections)
        assertEquals(
            TopicDecision.None,
            F.validate(F.answer(topic = F.topic("existing", id = "t_umzug"))).topic,
        )
    }

    @Test
    fun existingWithoutIDBecomesNone() {
        assertEquals(TopicDecision.None, F.validate(F.answer(topic = F.topic("existing"))).topic)
    }

    @Test
    fun validNewTopic() {
        assertEquals(
            TopicDecision.New("Schufa", TopicIcon.wallet),
            F.validate(F.answer(topic = F.topic("new", name = "Schufa", symbol = "wallet"))).topic,
        )
    }

    @Test
    fun unknownSymbolFallsBackToSparkles() {
        assertEquals(
            TopicDecision.New("Schufa", TopicIcon.sparkles),
            F.validate(F.answer(topic = F.topic("new", name = "Schufa", symbol = "rocket"))).topic,
        )
    }

    @Test
    fun genericNamesAreBlocked() {
        for (n in listOf("Ideen", "Notiz", "Todo", "To-dos", "Sonstiges", "Ideas", "Aufgabe")) {
            val r = F.validate(F.answer(topic = F.topic("new", name = n)))
            assertEquals(n, TopicDecision.None, r.topic)
            assertTrue("topic:name" in r.rejections)
        }
    }

    @Test
    fun variantsOfExistingTopicsBecomeExisting() {
        for ((n, id) in
            listOf(
                "Wohnungen" to "t_wohnung",
                "lissabon" to "t_lissabon",
                "Lissbaon" to "t_lissabon",
                "PAPLY" to "t_paply",
                "Umzugs" to "t_umzug",
                "Paply." to "t_paply",
            )) {
            val r = F.validate(F.answer(topic = F.topic("new", name = n)))
            assertEquals(n, TopicDecision.Existing(id), r.topic)
            assertTrue("topic:duplicate" in r.rejections)
        }
    }

    @Test
    fun nearNamesStayNew() {
        for (n in listOf("Wohnungssuche", "Lisabon", "Gärten", "Umzugsplanung")) {
            val r = F.validate(F.answer(topic = F.topic("new", name = n)))
            assertEquals(n, TopicDecision.New(n, TopicIcon.home), r.topic)
            assertFalse("topic:duplicate" in r.rejections)
        }
    }

    @Test
    fun invalidNewNamesBecomeNone() {
        for (n in
            listOf(
                "Ein sehr langer Themenname",
                "Viel zu viele Wörter hier",
                "2024",
                "x",
            )) assertEquals(
            n,
            TopicDecision.None,
            F.validate(F.answer(topic = F.topic("new", name = n))).topic,
        )
    }

    @Test
    fun fullIndexAllowsNoNewTopic() {
        val i = F.input(topicsFull = true)
        val r = F.validate(F.answer(topic = F.topic("new", name = "Schufa")), i)
        assertEquals(TopicDecision.None, r.topic)
        assertTrue("topic:full" in r.rejections)
        assertEquals(
            TopicDecision.Existing("t_wohnung"),
            F.validate(F.answer(topic = F.topic("new", name = "Wohnungen")), i).topic,
        )
    }

    @Test
    fun noneStaysNone() {
        val r = F.validate(F.answer(topic = F.topic("none")))
        assertEquals(TopicDecision.None, r.topic)
        assertFalse(r.rejections.any { it.startsWith("topic") })
    }
}

class AIValidatorTaskTests {
    @Test
    fun taskWithExactQuoteIsKeptAndQuoteIsTheRealSpan() {
        assertEquals(
            listOf(
                TaskDraft(
                    "Unterlagen schicken",
                    "Ich muss bis Freitag die Unterlagen schicken",
                    "bis Freitag",
                ),
            ),
            F.validate(
                    F.answer(
                        tasks =
                            listOf(
                                F.task(
                                    "Unterlagen schicken",
                                    "ich muss bis freitag die unterlagen schicken",
                                    "bis Freitag",
                                ),
                            ),
                    ),
                )
                .tasks,
        )
    }

    @Test
    fun inventedQuoteDropsTheTask() {
        val r =
            F.validate(
                F.answer(
                    tasks =
                        listOf(F.task("Umzugswagen buchen", "ich muss einen Umzugswagen buchen")),
                ),
            )
        assertTrue(r.tasks.isEmpty())
        assertTrue("task:quote" in r.rejections)
    }

    @Test
    fun fuzzyQuoteIsReplacedByTheRealSpan() {
        val t =
            "Ich muss morgen früh unbedingt noch beim Bürgeramt in Kreuzberg wegen der Anmeldung der neuen Wohnung anrufen."
        val q =
            "Ich muss morgen früh unbedingt noch beim Bürgeramt in Kreuzberg wegen der Ummeldung der neuen Wohnung anrufen"
        val r =
            F.validate(
                F.answer(
                    title = "Bürgeramt Kreuzberg",
                    clean = t,
                    topic = F.topic("none"),
                    tasks = listOf(F.task("Bürgeramt wegen Anmeldung anrufen", q, "morgen früh")),
                ),
                F.input(t),
            )
        assertEquals(t.dropLast(1), r.tasks.first().quote)
    }

    @Test
    fun elidedQuoteBecomesTheRealSpan() {
        val t =
            "was ich aber wirklich noch machen muss sind die Screenshots für den App Store die müssen bis zur Einreichung am zehnten fertig sein und zwar nur fürs große iPhone"
        assertEquals(
            "die Screenshots für den App Store die müssen bis zur Einreichung am zehnten fertig sein",
            ThoughtValidator.locateQuote(
                "die Screenshots für den App Store ... bis zur Einreichung am zehnten fertig sein",
                t,
            ),
        )
        val far = (1..40).joinToString(" ") { "wort$it" }
        assertNull(
            ThoughtValidator.locateQuote(
                "die Screenshots … fertig sein",
                "die Screenshots $far fertig sein",
            ),
        )
        assertNull(ThoughtValidator.locateQuote("die Screenshots … Laptop kaufen", t))
    }

    @Test
    fun nonBreakingHyphensBecomePlain() {
        assertEquals(
            "{\"title\":\"RevenueCat-Dashboard\",\"x\":\"a-b\"}",
            ThoughtValidator.plainHyphens(
                "{\"title\":\"RevenueCat\u2011Dashboard\",\"x\":\"a\\u2011b\"}",
            ),
        )
    }

    @Test
    fun atMostFiveTasks() {
        val t = (1..7).joinToString(" ") { "Ich muss Punkt $it erledigen." }
        val tasks = (1..7).map { F.task("Punkt $it erledigen", "Ich muss Punkt $it erledigen") }
        val r =
            F.validate(
                F.answer(
                    title = "Punkte erledigen",
                    clean = t,
                    topic = F.topic("none"),
                    tasks = tasks,
                ),
                F.input(t),
            )
        assertEquals(5, r.tasks.size)
        assertTrue("tasks:limit" in r.rejections)
    }

    @Test
    fun newDigitInTaskTextDropsIt() {
        val r =
            F.validate(
                F.answer(
                    tasks =
                        listOf(
                            F.task(
                                "3 Unterlagen schicken",
                                "Ich muss bis Freitag die Unterlagen schicken",
                            ),
                        ),
                ),
            )
        assertTrue(r.tasks.isEmpty())
        assertTrue("task:digits" in r.rejections)
    }

    @Test
    fun missingNegationDropsIt() {
        val t = "Ich darf morgen auf keinen Fall den Schlüssel abgeben, bevor der Makler da ist."
        val r =
            F.validate(
                F.answer(
                    title = "Schlüssel Makler",
                    clean = t,
                    topic = F.topic("none"),
                    tasks =
                        listOf(
                            F.task(
                                "Schlüssel abgeben",
                                "Ich darf morgen auf keinen Fall den Schlüssel abgeben",
                            ),
                        ),
                ),
                F.input(t),
            )
        assertTrue(r.tasks.isEmpty())
        assertTrue("task:negation" in r.rejections)
    }

    @Test
    fun reminderNegationMayBeDropped() {
        assertEquals(
            listOf("Schufa-Auskunft bestellen"),
            F.validate(
                    F.answer(
                        tasks =
                            listOf(
                                F.task(
                                    "Schufa-Auskunft bestellen",
                                    "nicht vergessen, die Schufa-Auskunft zu bestellen",
                                ),
                            ),
                    ),
                )
                .tasks
                .map { it.text },
        )
    }

    @Test
    fun ungroundedWordsDropTheTask() {
        val r =
            F.validate(
                F.answer(
                    tasks =
                        listOf(
                            F.task(
                                "Dringend Anwalt kontaktieren",
                                "Ich muss bis Freitag die Unterlagen schicken",
                            ),
                        ),
                ),
            )
        assertTrue(r.tasks.isEmpty())
        assertTrue("task:words" in r.rejections)
    }

    @Test
    fun oneExtraWordIsTolerated() {
        assertEquals(
            1,
            F.validate(
                    F.answer(
                        tasks =
                            listOf(
                                F.task(
                                    "Unterlagen an Makler schicken",
                                    "Ich muss bis Freitag die Unterlagen schicken",
                                ),
                            ),
                    ),
                )
                .tasks
                .size,
        )
    }

    @Test
    fun dueHintMustBeInTheQuote() {
        val r =
            F.validate(
                F.answer(
                    tasks =
                        listOf(
                            F.task(
                                "Unterlagen schicken",
                                "Ich muss bis Freitag die Unterlagen schicken",
                                "morgen",
                            ),
                        ),
                ),
            )
        assertNull(r.tasks.first().dueHint)
        assertTrue("task:due" in r.rejections)
    }

    @Test
    fun duplicateTasksCollapse() {
        assertEquals(
            1,
            F.validate(
                    F.answer(
                        tasks =
                            listOf(
                                F.task(
                                    "Unterlagen schicken",
                                    "Ich muss bis Freitag die Unterlagen schicken",
                                ),
                                F.task("unterlagen schicken!", "die Unterlagen schicken"),
                            ),
                    ),
                )
                .tasks
                .size,
        )
    }

    @Test
    fun sameTextOnDifferentDaysStaysTwoTasks() {
        val t = "Ich muss morgen Mama anrufen. Und übermorgen nochmal Mama anrufen."
        fun run(tasks: List<JsonObject>) =
            F.validate(
                F.answer(title = "Mama anrufen", clean = t, topic = F.topic("none"), tasks = tasks),
                F.input(t),
            )
        val with =
            run(
                listOf(
                    F.task("Morgen Mama anrufen", "morgen Mama anrufen", "morgen"),
                    F.task(
                        "Übermorgen Mama anrufen",
                        "übermorgen nochmal Mama anrufen",
                        "übermorgen",
                    ),
                ),
            )
        assertEquals(listOf("Mama anrufen", "Mama anrufen"), with.tasks.map { it.text })
        assertEquals(listOf("morgen", "übermorgen"), with.tasks.map { it.dueHint })
        assertFalse("task:duplicate" in with.rejections)
        assertEquals(
            listOf("morgen", "übermorgen"),
            run(
                    listOf(
                        F.task("Mama anrufen", "morgen Mama anrufen", "morgen"),
                        F.task("Mama anrufen", "übermorgen nochmal Mama anrufen", "übermorgen"),
                    ),
                )
                .tasks
                .map { it.dueHint },
        )
        val twice =
            run(
                listOf(
                    F.task("Morgen Mama anrufen", "morgen Mama anrufen", "morgen"),
                    F.task("Mama anrufen", "morgen Mama anrufen", "Morgen"),
                ),
            )
        assertEquals(1, twice.tasks.size)
        assertTrue("task:duplicate" in twice.rejections)
    }

    @Test
    fun assembledPartsKeepTasksOnDifferentDays() {
        val first =
            StructureResult(
                "Mama",
                "Teil eins.",
                TopicDecision.None,
                listOf(TaskDraft("Mama anrufen", "morgen Mama anrufen", "morgen")),
                emptyList(),
            )
        val part =
            StructureResult(
                "",
                "Teil zwei.",
                TopicDecision.None,
                listOf(
                    TaskDraft("Mama anrufen", "übermorgen Mama anrufen", "übermorgen"),
                    TaskDraft("mama anrufen", "morgen Mama anrufen", "morgen"),
                ),
                emptyList(),
            )
        assertEquals(
            listOf("morgen", "übermorgen"),
            ThoughtValidator.assemble(first, "a", listOf(part to "b")).tasks.map { it.dueHint },
        )
        assertNotEquals(
            RawText.taskKey("Mama anrufen", "morgen"),
            RawText.taskKey("Mama anrufen", "übermorgen"),
        )
        assertEquals(
            RawText.taskKey("Mama anrufen!", "Morgen"),
            RawText.taskKey("mama anrufen", "morgen"),
        )
        val done = ThoughtTask(text = "Mama anrufen", dueHint = "morgen", owner = Owner.ai)
        assertTrue(
            RawText.sameTask(
                done,
                ThoughtTask(text = "mama anrufen", dueHint = "Morgen", owner = Owner.ai),
            ),
        )
        assertTrue(RawText.sameTask(done, ThoughtTask(text = "Mama anrufen", owner = Owner.ai)))
        assertTrue(RawText.sameTask(ThoughtTask(text = "Mama anrufen", owner = Owner.user), done))
        assertFalse(RawText.sameTask(done, done.copy(dueHint = "übermorgen")))
    }

    @Test
    fun tooLongTaskTextDropsIt() {
        assertTrue(
            F.validate(
                    F.answer(
                        tasks =
                            listOf(
                                F.task(
                                    "Unterlagen schicken " + "Unterlagen ".repeat(7),
                                    "Ich muss bis Freitag die Unterlagen schicken",
                                ),
                            ),
                    ),
                )
                .tasks
                .isEmpty(),
        )
    }

    @Test
    fun englishTaskWithInflection() {
        val t =
            "Quick note for the flat. I need to call Anna about Friday and remind me to order boxes next week."
        val r =
            F.validate(
                F.answer(
                    title = "Flat Anna Friday",
                    clean = t,
                    topic = F.topic("none"),
                    tasks =
                        listOf(
                            F.task("Call Anna about Friday", "I need to call Anna about Friday"),
                            F.task(
                                "Order boxes",
                                "remind me to order boxes next week",
                                "next week",
                            ),
                        ),
                ),
                F.input(t),
            )
        assertEquals(listOf("Call Anna about Friday", "Order boxes"), r.tasks.map { it.text })
        assertEquals("next week", r.tasks.last().dueHint)
    }
}

class AIValidatorRelatedTests {
    @Test
    fun highConfidenceLinkIsKept() {
        assertEquals(
            listOf(
                RelatedDraft(
                    "s_oranien",
                    LinkKind.continues,
                    "Gleiche Wohnung in der Oranienstraße",
                ),
            ),
            F.validate(
                    F.answer(
                        related =
                            listOf(
                                F.link("c1", "continues", "Gleiche Wohnung in der Oranienstraße"),
                            ),
                    ),
                )
                .related,
        )
    }

    @Test
    fun refOutsideTheCandidatesIsDropped() {
        val r = F.validate(F.answer(related = listOf(F.link("c9"), F.link("s_oranien"))))
        assertTrue(r.related.isEmpty())
        assertEquals(2, r.rejections.count { it == "related:ref" })
    }

    @Test
    fun mediumNeedsAHighLocalScore() {
        assertEquals(
            listOf("s_oranien"),
            F.validate(
                    F.answer(
                        related =
                            listOf(
                                F.link("c1", "same_matter", "Wohnung", "medium"),
                                F.link("c2", "same_matter", "Garten", "medium"),
                            ),
                    ),
                )
                .related
                .map { it.thoughtID },
        )
    }

    @Test
    fun lowConfidenceIsDropped() {
        assertTrue(
            F.validate(F.answer(related = listOf(F.link("c1", "continues", "Wohnung", "low"))))
                .related
                .isEmpty(),
        )
    }

    @Test
    fun longReasonIsDropped() {
        assertTrue(
            F.validate(F.answer(related = listOf(F.link("c1", "continues", "Wohnung ".repeat(9)))))
                .related
                .isEmpty(),
        )
    }

    @Test
    fun reasonWithNewDigitIsDropped() {
        assertTrue(
            F.validate(
                    F.answer(related = listOf(F.link("c1", "changes", "Miete jetzt 2.000 Euro"))),
                )
                .related
                .isEmpty(),
        )
        assertEquals(
            1,
            F.validate(F.answer(related = listOf(F.link("c1", "changes", "Miete 1.450 Euro"))))
                .related
                .size,
        )
    }

    @Test
    fun atMostThreeAndNoDuplicates() {
        val r =
            F.validate(
                F.answer(
                    related =
                        listOf(
                            F.link("c1"),
                            F.link("c1"),
                            F.link("c3", "same_matter", "Knopf"),
                            F.link("c2", "same_matter", "Garten"),
                        ),
                ),
            )
        assertEquals(listOf("s_oranien", "s_sperr"), r.related.map { it.thoughtID })
        assertTrue("related:limit" in r.rejections)
    }

    @Test
    fun noSelfReference() {
        val r = F.validate(F.answer(related = listOf(F.link("c1"))), selfID = "s_oranien")
        assertTrue(r.related.isEmpty())
        assertTrue("related:self" in r.rejections)
    }

    @Test
    fun unknownKindIsDropped() {
        assertTrue(F.validate(F.answer(related = listOf(F.link("c1", "merges")))).related.isEmpty())
    }
}

class AIValidatorPartTests {
    @Test
    fun partValidation() {
        val i = F.input(part = StructureInput.Part(2, 3))
        val json = buildJsonObject {
            put("clean_text", F.goodClean)
            put(
                "tasks",
                JsonArray(
                    listOf(
                        F.task(
                            "Unterlagen schicken",
                            "Ich muss bis Freitag die Unterlagen schicken",
                        ),
                    ),
                ),
            )
        }
            .toString()
        val p = ThoughtValidator.validatePart(json, i).getOrThrow()
        assertTrue(p.title.isEmpty() && p.topic == TopicDecision.None && p.related.isEmpty())
        assertEquals(F.goodClean, p.cleanText)
        assertEquals(1, p.tasks.size)
        assertEquals(
            ThoughtValidator.Failure.Code.unreadable,
            (ThoughtValidator.validatePart("{}", i).exceptionOrNull() as ThoughtValidator.Failure)
                .code,
        )
    }

    @Test
    fun assembleJoinsTextsAndDeduplicatesTasks() {
        val task = TaskDraft("Unterlagen schicken", "Unterlagen schicken")
        val first =
            StructureResult(
                "Wohnung",
                "Teil eins.",
                TopicDecision.Existing("t_umzug"),
                listOf(task),
                listOf(RelatedDraft("s_oranien", LinkKind.continues, "Wohnung")),
            )
        val second =
            StructureResult(
                "",
                null,
                TopicDecision.None,
                listOf(task, TaskDraft("Makler anrufen", "Makler anrufen")),
                emptyList(),
                listOf("text:length"),
            )
        val third = StructureResult("", "Teil drei.", TopicDecision.None, emptyList(), emptyList())
        val r =
            ThoughtValidator.assemble(
                first,
                "teil eins",
                listOf(second to "ähm teil zwei roh", third to "teil drei"),
            )
        assertEquals("Teil eins.\n\nähm teil zwei roh\n\nTeil drei.", r.cleanText)
        assertEquals(listOf("Unterlagen schicken", "Makler anrufen"), r.tasks.map { it.text })
        assertEquals(listOf("part2:text:length"), r.rejections)
        assertEquals(first.title, r.title)
        assertEquals(first.topic, r.topic)
        assertEquals(first.related, r.related)
    }

    @Test
    fun assembleWithAllTextsRejectedIsRaw() {
        val f = StructureResult("Wohnung", null, TopicDecision.None, emptyList(), emptyList())
        assertNull(ThoughtValidator.assemble(f, "a", listOf(f.copy(title = "") to "b")).cleanText)
    }
}
