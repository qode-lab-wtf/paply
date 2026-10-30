package com.paply.thoughts

import com.paply.thoughts.AIFixture as F
import com.paply.thoughts.ai.*
import org.junit.Assert.*
import org.junit.Test

class AITaskTextTests {
    @Test
    fun firstLetterIsCapitalizedSafely() {
        val cases =
            listOf(
                listOf("tomaten gießen", "Tomaten gießen"),
                listOf("übergabe vorbereiten", "Übergabe vorbereiten"),
                listOf("ärzte anrufen", "Ärzte anrufen"),
                listOf("3 Kartons bestellen", "3 Kartons bestellen"),
                listOf("20 kartons bestellen", "20 kartons bestellen"),
                listOf("iPhone reparieren lassen", "iPhone reparieren lassen"),
                listOf("eBay-Konto löschen", "eBay-Konto löschen"),
                listOf("schufa-Auskunft bestellen", "Schufa-Auskunft bestellen"),
                listOf("„paply“ testen", "„Paply“ testen"),
                listOf("call the bank", "Call the bank"),
                listOf("Anna anrufen", "Anna anrufen"),
            )
        for (c in cases) assertEquals(c[0], c.last(), TaskText.tidy(c[0], null))
    }

    @Test
    fun timeExpressionAtTheEdgeIsRemoved() {
        val cases =
            listOf(
                listOf("morgen einkaufen gehen", "morgen", "Einkaufen gehen"),
                listOf("Morgen, einkaufen gehen", "morgen", "Einkaufen gehen"),
                listOf("Morgen Mama anrufen", "morgen", "Mama anrufen"),
                listOf("Übermorgen Mama anrufen", "übermorgen", "Mama anrufen"),
                listOf("am Freitag Anna anrufen", "am Freitag", "Anna anrufen"),
                listOf("Anna anrufen, morgen früh", "morgen früh", "Anna anrufen"),
                listOf("Morgen um 10 Uhr Kunden empfangen", "morgen um 10 Uhr", "Kunden empfangen"),
                listOf("call the bank tomorrow", "tomorrow", "Call the bank"),
                listOf(
                    "renew the fluxo dot app domain before November third",
                    "before November third",
                    "Renew the fluxo dot app domain",
                ),
                listOf(
                    "bis spätestens Freitag Unterlagen schicken",
                    "bis spätestens Freitag",
                    "Unterlagen schicken",
                ),
            )
        for (c in cases) assertEquals(c[0], c.last(), TaskText.tidy(c[0], c[1]))
    }

    @Test
    fun timeExpressionStaysWhenInDoubt() {
        val cases =
            listOf(
                listOf(
                    "Reisepass bis Ende November verlängern",
                    "bis Ende November",
                    "Reisepass bis Ende November verlängern",
                ),
                listOf(
                    "Reisepass, bis Ende November, verlängern",
                    "bis Ende November",
                    "Reisepass, bis Ende November, verlängern",
                ),
                listOf(
                    "Unterlagen bis Freitag schicken",
                    "bis Freitag",
                    "Unterlagen bis Freitag schicken",
                ),
                listOf("Laufrad im Dezember kaufen", "im Dezember", "Laufrad im Dezember kaufen"),
                listOf("Anna morgen anrufen", "morgen", "Anna morgen anrufen"),
                listOf(
                    "Urlaub verlängern bis Freitag",
                    "bis Freitag",
                    "Urlaub verlängern bis Freitag",
                ),
                listOf(
                    "bis Freitag Urlaub verlängern",
                    "bis Freitag",
                    "Bis Freitag Urlaub verlängern",
                ),
                listOf(
                    "bis Freitag die Unterlagen schicken",
                    "bis Freitag",
                    "Bis Freitag die Unterlagen schicken",
                ),
                listOf("ab Montag Sport machen", "ab Montag", "Ab Montag Sport machen"),
                listOf("extend the lease until May", "until May", "Extend the lease until May"),
                listOf("Anna wegen Freitag anrufen", "Freitag", "Anna wegen Freitag anrufen"),
                listOf("Kuchen backen für morgen", "morgen", "Kuchen backen für morgen"),
                listOf("morgen nur Anna anrufen", "morgen", "Morgen nur Anna anrufen"),
                listOf("morgen erst Anna anrufen", "morgen", "Morgen erst Anna anrufen"),
                listOf(
                    "morgen oder übermorgen Anna anrufen",
                    "morgen",
                    "Morgen oder übermorgen Anna anrufen",
                ),
                listOf("morgen Abend Anna anrufen", "morgen", "Morgen Abend Anna anrufen"),
                listOf("Anna anrufen nächsten Freitag", "Freitag", "Anna anrufen nächsten Freitag"),
                listOf("Anna anrufen am 3. Mai", "Mai", "Anna anrufen am 3. Mai"),
                listOf(
                    "Frau Brandt fragen wegen Ausmessen am Samstag",
                    "am Samstag",
                    "Frau Brandt fragen wegen Ausmessen am Samstag",
                ),
                listOf(
                    "ask Anna about the meeting on Friday",
                    "on Friday",
                    "Ask Anna about the meeting on Friday",
                ),
                listOf(
                    "Reisepass bis Ende November verlängern",
                    "Ende November",
                    "Reisepass bis Ende November verlängern",
                ),
                listOf("am Freitag Anna anrufen", "Freitag", "Am Freitag Anna anrufen"),
                listOf(
                    "Unterlagen bis spätestens Freitag schicken",
                    "bis Freitag",
                    "Unterlagen bis spätestens Freitag schicken",
                ),
                listOf(
                    "Halteverbotszone beantragen bis Freitag",
                    "bis spätestens Freitag",
                    "Halteverbotszone beantragen bis Freitag",
                ),
                listOf("morgen", "morgen", "Morgen"),
            )
        for (c in cases) assertEquals(c[0], c.last(), TaskText.tidy(c[0], c[1]))
    }

    @Test
    fun negationKeepsEverything() {
        val cases =
            listOf(
                listOf("nicht morgen anrufen", "morgen", "Nicht morgen anrufen"),
                listOf("morgen nicht anrufen", "morgen", "Morgen nicht anrufen"),
                listOf("bis morgen nicht anrufen", "bis morgen", "Bis morgen nicht anrufen"),
                listOf("bis morgen nicht anrufen", "morgen", "Bis morgen nicht anrufen"),
                listOf("Kein Termin morgen", "morgen", "Kein Termin morgen"),
                listOf(
                    "Anna anrufen, aber nicht morgen",
                    "morgen",
                    "Anna anrufen, aber nicht morgen",
                ),
                listOf(
                    "nicht heute, sondern morgen anrufen",
                    "morgen",
                    "Nicht heute, sondern morgen anrufen",
                ),
                listOf(
                    "nicht heute, sondern morgen anrufen",
                    "heute",
                    "Nicht heute, sondern morgen anrufen",
                ),
                listOf("Nicht morgen bezahlen", "morgen", "Nicht morgen bezahlen"),
                listOf("Nicht morgen Mama besuchen", "morgen", "Nicht morgen Mama besuchen"),
                listOf(
                    "Mama besuchen, nur nicht morgen",
                    "morgen",
                    "Mama besuchen, nur nicht morgen",
                ),
                listOf("morgen keine Pakete annehmen", "morgen", "Morgen keine Pakete annehmen"),
                listOf(
                    "morgen ohne Auto zum Arzt fahren",
                    "morgen",
                    "Morgen ohne Auto zum Arzt fahren",
                ),
                listOf("don't call the bank tomorrow", "tomorrow", "Don't call the bank tomorrow"),
                listOf("dont call the bank tomorrow", "tomorrow", "Dont call the bank tomorrow"),
                listOf("tomorrow never call the bank", "tomorrow", "Tomorrow never call the bank"),
                listOf(
                    "nicht vor Freitag bezahlen",
                    "nicht vor Freitag",
                    "Nicht vor Freitag bezahlen",
                ),
                listOf(
                    "Urlaub bis Freitag verlängern",
                    "bis Freitag",
                    "Urlaub bis Freitag verlängern",
                ),
            )
        for (c in cases) assertEquals(c[0], c.last(), TaskText.tidy(c[0], c[1]))
    }

    @Test
    fun noSingleWordAndNoTorso() {
        val cases =
            listOf(
                listOf("Freitag absagen", "Freitag", "Freitag absagen"),
                listOf("absagen Freitag", "Freitag", "Absagen Freitag"),
                listOf("Weihnachten planen", "Weihnachten", "Weihnachten planen"),
                listOf("morgen anrufen", "morgen", "Morgen anrufen"),
                listOf(
                    "morgen früh und abends gießen",
                    "morgen früh",
                    "Morgen früh und abends gießen",
                ),
                listOf("morgen früh und abends gießen", "morgen", "Morgen früh und abends gießen"),
                listOf(
                    "statt morgen übermorgen kommen",
                    "übermorgen",
                    "Statt morgen übermorgen kommen",
                ),
                listOf(
                    "statt morgen übermorgen kommen",
                    "morgen",
                    "Statt morgen übermorgen kommen",
                ),
                listOf(
                    "morgen statt heute Anna anrufen",
                    "morgen",
                    "Morgen statt heute Anna anrufen",
                ),
                listOf(
                    "morgen bzw. übermorgen Anna anrufen",
                    "morgen",
                    "Morgen bzw. übermorgen Anna anrufen",
                ),
                listOf("Anna anrufen und morgen", "morgen", "Anna anrufen und morgen"),
                listOf("call Anna and tomorrow", "tomorrow", "Call Anna and tomorrow"),
            )
        for (c in cases) assertEquals(c[0], c.last(), TaskText.tidy(c[0], c[1]))
    }

    @Test
    fun onlySafeFillersAtTheEdgesAreRemoved() {
        val cases =
            listOf(
                listOf("noch Milch kaufen", "Milch kaufen"),
                listOf("Noch Milch kaufen", "Milch kaufen"),
                listOf("noch die Belege prüfen", "Die Belege prüfen"),
                listOf("mal Anna anrufen", "Anna anrufen"),
                listOf("eben Brot holen", "Brot holen"),
                listOf("Anna anrufen mal", "Anna anrufen"),
                listOf("Rechnungen sammeln noch", "Rechnungen sammeln"),
                listOf("noch nicht bezahlen", "Noch nicht bezahlen"),
                listOf("noch keinen Termin machen", "Noch keinen Termin machen"),
                listOf("noch einen Termin machen", "Noch einen Termin machen"),
                listOf("noch mal anrufen", "Noch mal anrufen"),
                listOf("Anna anrufen noch mal", "Anna anrufen noch mal"),
                listOf("Kaffee trinken erst mal", "Kaffee trinken erst mal"),
                listOf("Fenster putzen nächstes Mal", "Fenster putzen nächstes Mal"),
                listOf("einmal Pizza bestellen", "Einmal Pizza bestellen"),
                listOf("nicht mal anrufen", "Nicht mal anrufen"),
                listOf("noch", "Noch"),
                listOf("noch Milch nicht kaufen", "Noch Milch nicht kaufen"),
                listOf("noch die Miete nicht überweisen", "Noch die Miete nicht überweisen"),
                listOf("Anna nicht anrufen noch", "Anna nicht anrufen noch"),
                listOf("mal Anna nicht stören", "Mal Anna nicht stören"),
            )
        for (c in cases) assertEquals(c[0], c.last(), TaskText.tidy(c[0], null))
    }

    @Test
    fun validatorAppliesTheFormAndStillChecksTheQuote() {
        val r =
            F.validate(
                F.answer(
                    tasks =
                        listOf(
                            F.task(
                                "noch die Unterlagen schicken",
                                "Ich muss bis Freitag die Unterlagen schicken",
                                "bis Freitag",
                            ),
                            F.task(
                                "schufa-Auskunft bestellen",
                                "nicht vergessen, die Schufa-Auskunft zu bestellen",
                            ),
                        ),
                ),
            )
        assertEquals(
            listOf("Die Unterlagen schicken", "Schufa-Auskunft bestellen"),
            r.tasks.map { it.text },
        )
        assertEquals("bis Freitag", r.tasks.first().dueHint)
        val span =
            F.validate(
                F.answer(
                    tasks =
                        listOf(
                            F.task(
                                "bis Freitag noch die Unterlagen schicken",
                                "Ich muss bis Freitag die Unterlagen schicken",
                                "bis Freitag",
                            ),
                        ),
                ),
            )
        assertEquals(listOf("Bis Freitag noch die Unterlagen schicken"), span.tasks.map { it.text })
        val doubled =
            F.validate(
                F.answer(
                    tasks =
                        listOf(
                            F.task(
                                "Unterlagen schicken",
                                "Ich muss bis Freitag die Unterlagen schicken",
                            ),
                            F.task("noch Unterlagen schicken", "die Unterlagen schicken"),
                        ),
                ),
            )
        assertEquals(1, doubled.tasks.size)
        assertTrue("task:duplicate" in doubled.rejections)
        val rejected =
            F.validate(
                F.answer(
                    tasks =
                        listOf(
                            F.task(
                                "morgen Unterlagen schicken",
                                "Ich muss bis Freitag die Unterlagen schicken",
                                "morgen",
                            ),
                        ),
                ),
            )
        assertTrue(
            rejected.tasks.isEmpty() || rejected.tasks.first().text == "Morgen Unterlagen schicken",
        )
    }

    @Test
    fun negatedTaskKeepsItsNegation() {
        val t =
            "Ich muss beim Fitnessstudio noch Bescheid sagen, dass ich den Vertrag nicht verlängere."
        val r =
            F.validate(
                F.answer(
                    title = "Vertrag nicht verlängern",
                    clean = t,
                    topic = F.topic("none"),
                    tasks =
                        listOf(
                            F.task("noch Bescheid sagen: Vertrag nicht verlängern", t.dropLast(1)),
                            F.task("Vertrag kündigen", t.dropLast(1)),
                        ),
                ),
                F.input(t),
            )
        assertEquals(listOf("Bescheid sagen: Vertrag nicht verlängern"), r.tasks.map { it.text })
        assertTrue("task:negation" in r.rejections)
    }
}

class AITaskWordingV4Tests {
    @Test
    fun coreOfTheSpeakersWordsIsGrounded() {
        val t = "Ich muss bei meiner Firma Brenner noch die neuesten Briefe einmal bearbeiten."
        val tasks =
            listOf("Neueste Briefe bei Brenner bearbeiten", "Beim Brenner Briefe bearbeiten")
        assertEquals(
            tasks,
            F.validate(
                    F.answer(
                        title = "Briefe bei Brenner bearbeiten",
                        clean = t,
                        topic = F.topic("none"),
                        tasks = tasks.map { F.task(it, t.dropLast(1)) },
                    ),
                    F.input(t),
                )
                .tasks
                .map { it.text },
        )
    }

    @Test
    fun errandWithSplitTimeExpression() {
        val first =
            "Ich muss morgen, am besten vormittags, wenn die Kinder in der Schule sind, einkaufen gehen und die drei Gutscheine vom Biomarkt am besten benutzen"
        val t =
            first +
                ". Und dafür mir die Einkaufsliste von meinem Agenten nochmal exportieren lassen."
        val r =
            F.validate(
                F.answer(
                    title = "Einkaufen mit Gutscheinen",
                    clean = t,
                    topic = F.topic("none"),
                    tasks =
                        listOf(
                            F.task(
                                "Beim Biomarkt einkaufen, Gutscheine nutzen",
                                first,
                                "morgen vormittags",
                            ),
                            F.task(
                                "Einkaufsliste vom Agenten exportieren lassen",
                                "dafür mir die Einkaufsliste von meinem Agenten nochmal exportieren lassen",
                            ),
                        ),
                ),
                F.input(t),
            )
        assertEquals(
            listOf(
                "Beim Biomarkt einkaufen, Gutscheine nutzen",
                "Einkaufsliste vom Agenten exportieren lassen",
            ),
            r.tasks.map { it.text },
        )
        assertEquals(listOf("morgen vormittags", null), r.tasks.map { it.dueHint })
        assertFalse("task:due" in r.rejections)
    }

    @Test
    fun appointmentWithTimeFromTwoClauses() {
        val q =
            "Morgen möchte ein Kunde bei Brenner 10 Bildschirme kaufen, um 10 Uhr will er kommen"
        val r =
            F.validate(
                F.answer(
                    title = "Kunde kauft 10 Bildschirme",
                    clean = "$q.",
                    topic = F.topic("none"),
                    tasks =
                        listOf(
                            F.task("Kunden wegen 10 Bildschirmen empfangen", q, "morgen um 10 Uhr"),
                        ),
                ),
                F.input("$q."),
            )
        assertEquals(
            listOf(TaskDraft("Kunden wegen 10 Bildschirmen empfangen", q, "morgen um 10 Uhr")),
            r.tasks,
        )
    }

    @Test
    fun dueHintFromPiecesStaysInTheQuote() {
        val q =
            "Ich muss morgen, am besten vormittags, wenn die Kinder in der Schule sind, einkaufen gehen"
        for (h in listOf("morgen vormittags", "morgen, am besten vormittags", "Morgen")) assertTrue(
            ThoughtValidator.dueHintInQuote(h, q),
        )
        for (h in listOf("morgen nachmittags", "übermorgen", "vormittags morgen")) assertFalse(
            ThoughtValidator.dueHintInQuote(h, q),
        )
        assertFalse(
            ThoughtValidator.dueHintInQuote(
                "morgen",
                "Ich muss übermorgen die Unterlagen schicken",
            ),
        )
        assertTrue(
            ThoughtValidator.dueHintInQuote(
                "morgen vormittags",
                "morgen " + (1..18).joinToString(" ") { "wort$it" } + " vormittags",
            ),
        )
        assertFalse(
            ThoughtValidator.dueHintInQuote(
                "morgen vormittags",
                "morgen " + (1..19).joinToString(" ") { "wort$it" } + " vormittags",
            ),
        )
        assertFalse(ThoughtValidator.dueHintInQuote("a c e g", "a b c d e f g"))
        assertTrue(ThoughtValidator.dueHintInQuote("a c e", "a b c d e f g"))
    }
}
