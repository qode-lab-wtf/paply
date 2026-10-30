package com.paply.thoughts

import com.paply.core.PolishSafetyNet
import com.paply.thoughts.ai.*
import org.junit.Assert.*
import org.junit.Test

class AINumbersTests {
    @Test
    fun germanCompounds() {
        for ((w, v) in
            listOf(
                "achtundzwanzigsten" to 28L,
                "dreißigste" to 30L,
                "zweitausendsechsundzwanzig" to 2026L,
                "vierzehnhundertfünfzig" to 1450L,
                "elfhundertzwanzig" to 1120L,
                "siebenhundertfünfzig" to 750L,
                "sechstausendfünfhundert" to 6500L,
                "viertausenddreihundertfünfzig" to 4350L,
                "zehnten" to 10L,
                "elften" to 11L,
                "dritte" to 3L,
                "siebte" to 7L,
                "sechste" to 6L,
                "zweimal" to 2L,
                "fünfundzwanzigsten" to 25L,
                "neunundneunzig" to 99L,
                "einhundert" to 100L,
                "eintausend" to 1000L,
                "zwanzig" to 20L,
            )) assertEquals(w, v, SpokenNumbers.germanValue(w))
    }

    @Test
    fun germanNonNumbers() {
        for (w in
            listOf(
                "minuten",
                "weihnachten",
                "mitte",
                "kiste",
                "leute",
                "hunderte",
                "manchmal",
                "einmal",
                "starten",
            )) assertNull(w, SpokenNumbers.germanValue(w))
    }

    private fun values(s: String) = SpokenNumbers.tokens(s).map { it.value }

    @Test
    fun englishSequences() {
        assertEquals(listOf(28L), values("twenty eight"))
        assertEquals(listOf(750L), values("seven hundred and fifty euros"))
        assertEquals(listOf(2026L), values("in two thousand twenty six"))
        assertEquals(listOf(1L, 2L, 3L), values("one two three"))
        assertEquals(listOf(11L, 3L), values("before November third"))
        assertEquals(listOf(21L), values("twenty-first"))
    }

    @Test
    fun digitGroups() {
        assertEquals(listOf(6500L, 6500L), values("6.500 € und 6 500 Leute"))
        assertEquals(listOf(15L, 30L), values("um 15:30"))
        assertEquals(listOf(28L, 12L, 2026L), values("am 28.12.2026"))
        assertEquals(listOf(1L, 5L), values("1,5 Liter"))
    }

    @Test
    fun optionalKinds() {
        assertEquals(
            List(4) { SpokenNumbers.Kind.optional },
            SpokenNumbers.tokens("ein Termin erstens im Dezember erster Gedanke").map { it.kind },
        )
    }

    @Test
    fun numberWordsBecomeDigits() {
        assertTrue(
            SpokenNumbers.preserved(
                "am achtundzwanzigsten Dezember um neun",
                "Am 28. Dezember um 9 Uhr.",
            ),
        )
        assertTrue(
            SpokenNumbers.preserved("das kostet siebenhundertfünfzig Euro", "Das kostet 750 €."),
        )
        assertTrue(SpokenNumbers.preserved("we need twenty eight seats", "We need 28 seats."))
    }

    @Test
    fun changedMissingOrNewNumbersFail() {
        for ((a, b) in
            listOf(
                "am achtundzwanzigsten Dezember" to "Am 27. Dezember.",
                "um neun mit zwanzig Leuten" to "Um 9 Uhr mit Leuten.",
                "mit Leuten" to "Mit 20 Leuten.",
                "im Dezember" to "Im Dezember 2026.",
            )) assertFalse(SpokenNumbers.preserved(a, b))
    }

    @Test
    fun optionalSourcesAreNotRequired() {
        for ((a, b) in
            listOf(
                "erstens Kartons zweitens Transporter" to "• Kartons\n• Transporter",
                "erstens Kartons" to "1. Kartons",
                "am achtundzwanzigsten Dezember" to "Am 28.12.",
            )) assertTrue(SpokenNumbers.preserved(a, b))
    }

    @Test
    fun selfCorrectionWithoutComma() {
        val raw = "7 Kilometer in 38 Minuten nee warte 36 die Uhr sagt 36"
        assertTrue(SpokenNumbers.preserved(raw, "7 Kilometer in 36 Minuten, die Uhr sagt 36."))
        assertTrue(
            SpokenNumbers.preserved(raw, "7 Kilometer in 38, nein 36 Minuten; die Uhr sagt 36."),
        )
        assertFalse(
            SpokenNumbers.preserved(
                "in 38 Minuten und dann 36 Liegestütze",
                "In Minuten und dann 36 Liegestütze.",
            ),
        )
        assertTrue(
            SpokenNumbers.preserved(
                "das sind dreitausendachthundert nee falsch drei mal vierzehnhundertfünfzig das sind viertausenddreihundertfünfzig",
                "Das sind 3 × 1.450 €, also 4.350 €.",
            ),
        )
        val warm =
            "die alten elfhundertzwanzig warm äh nein das ist kalt warm sind's dreizehnhundertvierzig"
        assertFalse(SpokenNumbers.preserved(warm, "Warm sind es 1.340 €."))
        assertTrue(
            SpokenNumbers.preserved(warm, "Die alten 1.120 € sind kalt, warm sind es 1.340 €."),
        )
    }

    @Test
    fun validatorAcceptsDigitsFromNumberWords() {
        val t =
            "Herr Kowalski will am achtundzwanzigsten übergeben ich muss zwanzig Kartons bestellen"
        assertEquals("Übergabe am 28", ThoughtValidator.checkedTitle("Übergabe am 28.", t))
        assertNull(ThoughtValidator.checkedTitle("Übergabe am 29.", t))
        val rejects = mutableListOf<String>()
        val tasks =
            ThoughtValidator.checkedTasks(
                listOf(
                    ThoughtValidator.RawTask(
                        "20 Kartons bestellen",
                        "ich muss zwanzig Kartons bestellen",
                    ),
                    ThoughtValidator.RawTask(
                        "30 Kartons bestellen",
                        "ich muss zwanzig Kartons bestellen",
                    ),
                ),
                t,
                rejects,
            )
        assertEquals(listOf("20 Kartons bestellen"), tasks.map { it.text })
        assertEquals(listOf("task:digits"), rejects)
    }

    @Test
    fun spokenNegationIgnoresInterjections() {
        assertEquals(
            0,
            ThoughtSafetyNet.spokenNegationCount("bis Donnerstag nee Quatsch bis Mittwoch"),
        )
        assertEquals(0, ThoughtSafetyNet.spokenNegationCount("äh nein das ist kalt"))
        assertEquals(1, ThoughtSafetyNet.spokenNegationCount("das geht nicht"))
        assertEquals(1, ThoughtSafetyNet.spokenNegationCount("we have no staging environment"))
    }

    @Test
    fun thoughtProfileAcceptsCorrectedDeadline() {
        val raw =
            "ähm ich muss bis Donnerstag nee Quatsch bis Mittwoch den Keller freiräumen weil die von Rhein Zug am Donnerstag um neun zur Besichtigung kommen"
        val clean =
            "Ich muss bis Mittwoch den Keller freiräumen, weil die von Rheinzug am Donnerstag um 9 Uhr zur Besichtigung kommen."
        assertNull(ThoughtSafetyNet.rejection(raw, clean, "Rheinzug"))
        assertEquals(
            "digits",
            PolishSafetyNet.rejection(
                "wir treffen uns am achtundzwanzigsten Dezember im Büro",
                "Wir treffen uns am 28. Dezember im Büro.",
            ),
        )
        assertNull(
            ThoughtSafetyNet.rejection(
                "wir treffen uns am achtundzwanzigsten Dezember im Büro",
                "Wir treffen uns am 28. Dezember im Büro.",
            ),
        )
    }
}
