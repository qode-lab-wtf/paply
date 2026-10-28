package com.paply.core

import org.junit.Assert.*
import org.junit.Test

class FollowUpTextTests {
    private fun reject(raw: String, result: String, vocabulary: String = "") =
        PolishSafetyNet.rejection(raw, result, vocabulary)

    @Test
    fun goodPolishesPass() {
        for ((raw, result) in
            listOf(
                listOf(
                    "ich glaube äh das er morgen kommt und alles mitbringt",
                    "Ich glaube, dass er morgen kommt und alles mitbringt.",
                ),
                listOf(
                    "ich äh hab das schon erledigt und abgeschickt",
                    "Ich habe das schon erledigt und abgeschickt.",
                ),
                listOf(
                    "ich ich hab das Angebot gestern verschickt",
                    "Ich habe das Angebot gestern verschickt.",
                ),
                listOf(
                    "die äh daten bank ist seit gestern wieder voll",
                    "Die Datenbank ist seit gestern wieder voll.",
                ),
                listOf(
                    "ok dann machen wir das so wie besprochen",
                    "Okay, dann machen wir das so wie besprochen.",
                ),
            )) {

            expect(reject(raw, result) == null)
        }
    }

    @Test
    fun meaningChangesStillFail() {

        expect(
            reject(
                "Im Daily Morgan sollten wir klären, wer das übernimmt.",
                "Im Daily Morning sollten wir klären, wer das übernimmt.",
            ) == "replaced",
        )
        expect(
            reject(
                "Er braucht dafür äh ungefähr zwei Wochen, sagt er.",
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
                "ich äh treffe mich morgen mit Morgan im Büro am Bahnhof",
                "Ich treffe mich morgen mit Morning im Büro am Bahnhof.",
            ) == "replaced",
        )
    }

    @Test
    fun commaAfterSentenceInitialNo() {

        expect(
            reject(
                "Nein das passt so leider nicht für uns.",
                "Nein, das passt so leider nicht für uns.",
            ) == null,
        )
        expect(
            reject(
                "Gut. No that does not work for the team.",
                "Gut. No, that does not work for the team.",
            ) == null,
        )
        expect(
            TextAnalysis.negationCount("Nein das passt") ==
                TextAnalysis.negationCount("Nein, das passt"),
        )

        expect(
            reject("No quiero ir mañana a la reunión.", "Quiero ir mañana a la reunión.") ==
                "negation",
        )
        expect(
            reject(
                "Non posso venire domani alla riunione.",
                "Posso venire domani alla riunione.",
            ) == "negation",
        )
    }

    @Test
    fun formattingOfNumbersIsAllowed() {

        expect(
            reject(
                "Wir treffen uns morgen um 15.30 Uhr am Haupteingang vom Büro.",
                "Wir treffen uns morgen um 15:30 Uhr am Haupteingang vom Büro.",
            ) == null,
        )
        expect(
            reject(
                "Meine Handynummer lautet 0171 123 45 67, ruf gern jederzeit an.",
                "Meine Handynummer lautet 0171 1234567, ruf gern jederzeit an.",
            ) == null,
        )
        expect(EditCheck.digitsPreserved(raw = "um 15.30 Uhr", result = "um 15:31 Uhr") == false)
    }

    @Test
    fun newNumbersAreForbidden() {

        expect(
            EditCheck.digitsPreserved(raw = "Das kostet viel.", result = "Das kostet 100 Euro.") ==
                false,
        )
        expect(EditCheck.digitsPreserved(raw = "um drei Uhr", result = "um 3 Uhr"))
    }

    @Test
    fun spokenSelfCorrectionOfANumber() {

        expect(
            reject(
                "Wir treffen uns um 15 Uhr, ich meine um 16 Uhr.",
                "Wir treffen uns um 16 Uhr.",
            ) == null,
        )
        expect(reject("Ruf mich um 9 an, sorry, um 10 an.", "Ruf mich um 10 an.") == null)
        expect(
            reject("Treffen am Montag, nein Moment, am Dienstag.", "Treffen am Dienstag.") == null,
        )

        expect(
            reject("Wir treffen uns um 15 Uhr und dann um 16 Uhr.", "Wir treffen uns um 16 Uhr.") !=
                null,
        )

        expect(
            reject(
                "Wir treffen uns um 15 Uhr, ich meine um 16 Uhr.",
                "Wir treffen uns um 17 Uhr.",
            ) != null,
        )

        expect(EditCheck.resolvedSelfCorrection("I can't wait to see you at 5 tomorrow.") == null)
        expect(
            EditCheck.resolvedSelfCorrection("Wir treffen uns um 15 Uhr, ich meine um 16 Uhr.") ==
                "Wir treffen uns um 16 Uhr.",
        )
    }
}
