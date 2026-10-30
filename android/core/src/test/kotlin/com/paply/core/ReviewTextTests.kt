package com.paply.core

import org.junit.Assert.*
import org.junit.Test

class ReviewTextTests {
    private fun reject(raw: String, result: String, vocabulary: String = "") =
        PolishSafetyNet.rejection(raw, result, vocabulary)

    @Test
    fun digitsMustSurvive() {

        val raw = "Wir treffen uns am Donnerstag um 15 Uhr im großen Besprechungsraum."
        expect(
            reject(raw, "Wir treffen uns am Donnerstag um 16 Uhr im großen Besprechungsraum.") ==
                "digits",
        )

        expect(
            reject(raw, "Wir treffen uns am Donnerstag um 15:00 Uhr im großen Besprechungsraum.") ==
                "digits",
        )
        expect(
            reject(
                "Das kostet 1.000 Euro pro Monat für das ganze Team.",
                "Das kostet 1000 Euro pro Monat für das ganze Team.",
            ) == null,
        )
        expect(
            reject(
                "3. Müssen wir noch klären, wie wir mit den Anfragen umgehen.",
                "Drittens müssen wir noch klären, wie wir mit den Anfragen umgehen.",
            ) == null,
        )
        expect(
            EditCheck.digitsPreserved(raw = "Zimmer 12 und 14", result = "Zimmer 12 und 41") ==
                false,
        )
        expect(EditCheck.digitsPreserved(raw = "um drei Uhr", result = "um 3 Uhr"))
    }

    @Test
    fun selfCorrectionWithNoIsAllowed() {

        expect(
            reject(
                "Please send the quarterly report to the whole marketing team on Monday, no wait, on Tuesday.",
                "Please send the quarterly report to the whole marketing team on Tuesday.",
            ) == null,
        )
        expect(
            reject(
                "Envoie le rapport trimestriel à toute l'équipe marketing lundi, non, enfin mardi.",
                "Envoie le rapport trimestriel à toute l'équipe marketing mardi.",
            ) == null,
        )
        expect(
            reject(
                "Schick den neuen Quartalsbericht bitte noch heute an das ganze Marketingteam und die Geschäftsführung am Montag, nein Moment, am Dienstag.",
                "Schick den neuen Quartalsbericht bitte noch heute an das ganze Marketingteam und die Geschäftsführung am Dienstag.",
            ) == null,
        )

        expect(
            reject(
                "That is really no problem for the whole team at all.",
                "That is really a problem for the whole team at all.",
            ) == "negation",
        )

        expect(TextAnalysis.negationCount("No, I mean Tuesday.") == 1)
        expect(TextAnalysis.negationCount("Meet on Monday, no, I mean Tuesday.") == 0)
        expect(TextAnalysis.negationCount("Non posso venire domani.") == 1)
    }

    @Test
    fun compoundsAndHyphens() {

        expect(
            reject(
                "Die daten bank für das Projekt ist leider schon voll.",
                "Die Datenbank für das Projekt ist leider schon voll.",
            ) == null,
        )
        expect(
            reject(
                "Das neue Designsystem ist seit Montag im Projekt verfügbar.",
                "Das neue Design-System ist seit Montag im Projekt verfügbar.",
            ) == null,
        )
    }

    @Test
    fun turkishDottedAndDotlessI() {

        expect(TextAnalysis.normalizedLower("İSTANBUL") == TextAnalysis.normalizedLower("istanbul"))
        expect(TextAnalysis.normalizedLower("ıstanbul") == "istanbul")
        expect(
            reject(
                "istanbul'da yarın buluşalım mı, hayır değil mi",
                "İstanbul'da yarın buluşalım mı, hayır değil mi?",
            ) == null,
        )
    }

    @Test
    fun meaningChangingReplacementsAreCaught() {

        expect(
            reject(
                "Im Daily Morgan sollten wir klären, wer das übernimmt.",
                "Im Daily Morning sollten wir klären, wer das übernimmt.",
            ) == "replaced",
        )
        expect(
            reject(
                "Er braucht dafür ungefähr zwei Wochen, sagt er.",
                "Er braucht dafür ungefähr zwei Woche, sagt er.",
            ) == "replaced",
        )
        expect(
            reject(
                "Wir sammeln die Anfragen der Kunden auf einer eigenen Seite.",
                "Wir sammeln die Anfragen der Kundinnen und Kunden auf einer eigenen Seite.",
            ) == "inserted",
        )
        expect(
            reject(
                "Ich schlage vor, dass wir dafür eine eigene Seite anlegen.",
                "Ich schlage vor, dass wir dazu eine eigene Seite anlegen.",
            ) == "replaced",
        )
    }

    @Test
    fun goodCorrectionsPass() {

        expect(
            reject(
                "Das Buckend ist fertig, die Schnittstelle ist dokumentiert und alle Endpunkte haben Tests.",
                "Das Backend ist fertig, die Schnittstelle ist dokumentiert und alle Endpunkte haben Tests.",
            ) == null,
        )
        expect(
            reject(
                "Für das Unboarding brauchen wir außerdem noch die finalen Screenshots und einen Text.",
                "Für das Onboarding brauchen wir außerdem noch die finalen Screenshots und einen Text.",
            ) == null,
        )
        expect(
            reject(
                "Ich habe den pull request gemerget, aber der Build läuft nicht.",
                "Ich habe den Pull Request gemerged, aber der Build läuft nicht.",
            ) == null,
        )

        val raw =
            "Bitte installiere heute Abend Cooper Netties auf dem neuen Server im Rechenzentrum und prüfe danach alle Dienste."
        val fixed =
            "Bitte installiere heute Abend Kubernetes auf dem neuen Server im Rechenzentrum und prüfe danach alle Dienste."
        expect(reject(raw, fixed) != null)
        expect(reject(raw, fixed, vocabulary = "Kubernetes") == null)

        expect(
            reject(
                "morgen gehen wir gemeinsam essen und danach ins Kino",
                "Gemeinsam gehen wir morgen essen und danach ins Kino.",
            ) == null,
        )
    }

    @Test
    fun arabicAndHebrewNegation() {

        expect(
            reject(
                "أنا لا أريد الذهاب غدا إلى الاجتماع الكبير",
                "أنا أريد الذهاب غدا إلى الاجتماع الكبير",
            ) == "negation",
        )
        expect(
            reject("אני לא יכול לבוא מחר לפגישה הגדולה", "אני יכול לבוא מחר לפגישה הגדולה") ==
                "negation",
        )
    }

    @Test
    fun hesitationsOnly() {

        expect(
            Lexicon.fillers.contains("ähm") &&
                Lexicon.fillers.contains("euh") &&
                Lexicon.fillers.contains("yyy"),
        )
        for (word in
            listOf(
                "like",
                "also",
                "este",
                "vale",
                "tipo",
                "pronto",
                "genre",
                "gewoon",
                "şey",
                "znaczy",
            )) {
            expect(!Lexicon.fillers.contains(TextAnalysis.normalizedLower(word)))
        }
    }

    @Test
    fun cjkJoinsWithoutSpace() {

        expect(TranscriptCleanup.join(listOf("我明天去开会。", "然后回家。")) == "我明天去开会。然后回家。")
        expect(TranscriptCleanup.join(listOf("明日は会議", "です。")) == "明日は会議です。")
        expect(
            TranscriptCleanup.join(listOf("Hello there.", "See you.")) == "Hello there. See you.",
        )
        expect(TranscriptCleanup.join(listOf("会议。", "Then we go.")) == "会议。 Then we go.")
    }

    @Test
    fun repeatedLeadAtChunkBoundaryIsRemoved() {

        expect(
            TranscriptCleanup.join(
                listOf(
                    "Wir treffen uns morgen früh im Büro.",
                    "morgen früh im Büro und dann gehen wir essen.",
                ),
            ) == "Wir treffen uns morgen früh im Büro. und dann gehen wir essen.",
        )

        expect(
            TranscriptCleanup.join(listOf("Das ist so.", "ist so gut.")) ==
                "Das ist so. ist so gut.",
        )
    }
}
