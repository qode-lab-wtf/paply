package com.paply.core

internal object Lexicon {
    val fillers =
        listOf(
                "äh",
                "ähm",
                "öhm",
                "ähem",
                "hm",
                "hmm",
                "mhm",
                "uh",
                "uhm",
                "uhmm",
                "um",
                "umm",
                "er",
                "erm",
                "eh",
                "ehm",
                "ehh",
                "eeh",
                "euh",
                "euhm",
                "eee",
                "eem",
                "yyy",
                "ııı",
                "hum",
                "mmm",
            )
            .map(TextAnalysis::normalizedLower)
            .toSet()

    /// Verneinungswörter. Ändert sich ihre Anzahl, kippt womöglich der Sinn.
    /// Französisch zählt bewusst nur den zweiten Teil (pas, jamais …): Gesprochenes
    /// „c'est pas“ ohne „ne“ darf korrekt zu „ce n'est pas“ werden.
    /// Türkisch verneint überwiegend per Suffix (-me/-ma); erfasst sind nur freie Wörter.
    val negations =
        listOf(
                // Deutsch
                "nicht",
                "nichts",
                "nie",
                "niemals",
                "niemand",
                "nirgends",
                "nirgendwo",
                "kein",
                "keine",
                "keinen",
                "keinem",
                "keiner",
                "keines",
                "weder",
                // Englisch
                "not",
                "never",
                "nothing",
                "nobody",
                "none",
                "neither",
                "nor",
                "nowhere",
                "cannot",
                // Französisch
                "pas",
                "jamais",
                "rien",
                "aucun",
                "aucune",
                "ni",
                // Spanisch
                "nunca",
                "nada",
                "nadie",
                "ningún",
                "ninguno",
                "ninguna",
                "jamás",
                "tampoco",
                // Italienisch
                "mai",
                "niente",
                "nulla",
                "nessuno",
                "nessuna",
                "nessun",
                "né",
                // Portugiesisch
                "não",
                "ninguém",
                "nenhum",
                "nenhuma",
                "nem",
                // Niederländisch
                "niet",
                "geen",
                "nooit",
                "niets",
                "niks",
                "nergens",
                // Türkisch
                "değil",
                "yok",
                "hayır",
                "asla",
                "hiç",
                "hiçbir",
                // Polnisch
                "nie",
                "nigdy",
                "nic",
                "nikt",
                "żaden",
                "żadna",
                "żadne",
                "nigdzie",
                "ani",
                // Russisch/Ukrainisch
                "не",
                "нет",
                "ни",
                "никогда",
                "ничего",
                "никто",
                "ні",
                // Arabisch
                "لا",
                "لم",
                "لن",
                "ليس",
                "ليست",
                "ولا",
                "ولم",
                "ولن",
                "غير",
                // Hebräisch
                "לא",
                "אין",
                "אינו",
                "אינה",
                "אף",
                "ולא",
                // Koreanisch (freistehend)
                "안",
                // Hindi
                "नहीं",
                "मत",
            )
            .map(TextAnalysis::normalizedLower)
            .toSet()

    /// „no“, „non“, „nee“, „nein“ verneinen nur satzintern („no problem“, „non posso“).
    /// Vor Satzzeichen oder einem Korrekturwort („no wait“, „non, enfin“, „nein Moment“)
    /// leiten sie eine Selbstkorrektur ein, deren Auflösung erlaubt ist.
    val answerNegators =
        listOf("no", "non", "nee", "nein", "nope").map(TextAnalysis::normalizedLower).toSet()

    /// Wörter/Wendungen, mit denen eine Selbstkorrektur weitergeht.
    val correctionPhrases =
        listOf(
                "wait",
                "warte",
                "moment",
                "momento",
                "attends",
                "attendez",
                "espera",
                "aspetta",
                "wacht",
                "czekaj",
                "sorry",
                "pardon",
                "perdón",
                "scusa",
                "entschuldigung",
                "actually",
                "eigentlich",
                "doch",
                "i mean",
                "ich meine",
                "ich mein",
                "je veux dire",
                "enfin",
                "quiero decir",
                "o sea",
                "voglio dire",
                "cioè",
                "ik bedoel",
                "quer dizer",
                "quero dizer",
                "yani",
                "znaczy",
                "to jest",
            )
            .map(TextAnalysis::normalizedLower)

    /// Englische Kurzformen („don't“, „isn’t“): Die Wortzerlegung trennt am Apostroph.
    val contractedNegation = Pattern("n['’]t\\b")

    /// Einzelzeichen-Verneinungen in Schriften ohne Wortgrenzen bzw. koreanische Stämme.
    val negationScalars = "不没沒无無别別未莫勿않없못".scalars().toSet()

    /// Mehrzeichige Verneinungsfragmente (Japanisch, Thai).
    val negationFragments = listOf("ない", "ません", "なかっ", "ไม่")

    /// Typische Einleitungen von Meta-Antworten („Hier ist der Text:“) – am Textanfang.
    val metaAnswer =
        Pattern(
            "^(?:"
            // Deutsch (wie Desktop)
            +
                "hier\\s+(?:ist|sind|der|das)|(?:der\\s+)?(?:poliert|korrigiert|überarbeitet)(?:er|e|es)\\s+text\\s*:"
                // Englisch
                +
                "|here\\s+(?:is|are)|here['’]s\\s+(?:the|your)|(?:the\\s+)?(?:polished|corrected|revised|edited|cleaned[- ]up)\\s+(?:text|version|dictation)\\s*:"
                // Französisch
                +
                "|voici\\s+(?:le|la|les|votre|ton|ta)\\b|(?:le\\s+)?texte\\s+(?:corrigé|poli|révisé|retravaillé)\\s*:"
                // Spanisch
                +
                "|aquí\\s+(?:está|tienes|tiene|va)\\b|(?:el\\s+)?texto\\s+(?:corregido|pulido|revisado)\\s*:"
                // Italienisch
                +
                "|ecco\\s+(?:il|la|lo|i|gli|le|l['’])|(?:il\\s+)?testo\\s+(?:corretto|rivisto|revisionato)\\s*:"
                // Portugiesisch
                + "|aqui\\s+está\\b|(?:o\\s+)?texto\\s+(?:corrigido|revisado|polido)\\s*:"
                // Niederländisch
                +
                "|hier\\s+is\\s+(?:de|het|je|uw)\\b|(?:de\\s+)?(?:gecorrigeerde|verbeterde|herziene)\\s+tekst\\s*:"
                // Türkisch
                + "|(?:İ|i̇|i|I)şte\\s+(?:düzeltilmiş|düzenlenmiş|metin)|düzeltilmiş\\s+metin\\s*:"
                // Polnisch
                + "|oto\\s+(?:poprawiony|poprawiona|tekst)|poprawiony\\s+tekst\\s*:" +
                ")",
            caseInsensitive = true,
        )

    /// Vollständig in Anführungszeichen gesetzte Antwort.
    val wrappedInQuotes =
        Pattern(
            "^(?:\"[\\s\\S]*\"|„[\\s\\S]*[“”]|“[\\s\\S]*”|«[\\s\\S]*»|»[\\s\\S]*«|'[\\s\\S]*'|‚[\\s\\S]*[‘’]|「[\\s\\S]*」|『[\\s\\S]*』)$",
        )
}
