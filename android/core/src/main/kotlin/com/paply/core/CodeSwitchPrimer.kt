package com.paply.core

import java.util.Locale

internal object CodeSwitchPrimer {
    data class Phrases(val open: List<String>, val close: List<String>)

    val phrases =
        mapOf(
            "de" to
                Phrases(
                    listOf("Kurzes Update: Das Meeting ist verschoben", "Ich schreibe dir später"),
                    listOf("und der neue Termin ist nächsten Freitag", "bis morgen"),
                ),
            "en" to
                Phrases(
                    listOf("Quick update: the meeting has been moved", "I'll write to you later"),
                    listOf("and the new date is next Friday", "see you tomorrow"),
                ),
            "fr" to
                Phrases(
                    listOf("Petit point : la réunion est reportée", "Je t'écris plus tard"),
                    listOf("et la nouvelle date est vendredi prochain", "à demain"),
                ),
            "es" to
                Phrases(
                    listOf("Breve novedad: la reunión se aplaza", "Te escribo luego"),
                    listOf("y la nueva fecha es el viernes", "hasta mañana"),
                ),
            "it" to
                Phrases(
                    listOf("Breve aggiornamento: la riunione è spostata", "Ti scrivo dopo"),
                    listOf("e la nuova data è venerdì prossimo", "a domani"),
                ),
            "pt" to
                Phrases(
                    listOf("Novidade rápida: a reunião foi adiada", "Te escrevo depois"),
                    listOf("e a nova data é sexta-feira", "até amanhã"),
                ),
            "nl" to
                Phrases(
                    listOf("Korte update: de vergadering is verplaatst", "Ik schrijf je later"),
                    listOf("en de nieuwe datum is volgende vrijdag", "tot morgen"),
                ),
            "tr" to
                Phrases(
                    listOf("Kısa bilgi: toplantı ertelendi", "Sana sonra yazarım"),
                    listOf("ve yeni tarih cuma", "yarın görüşürüz"),
                ),
            "pl" to
                Phrases(
                    listOf("Krótko: spotkanie jest przełożone", "Napiszę później"),
                    listOf("a nowy termin to piątek", "do jutra"),
                ),
        )

    fun baseCode(identifier: String) =
        identifier
            .lowercase(Locale.ROOT)
            .characters()
            .dropWhile { it == "-" || it == "_" }
            .takeWhile { it != "-" && it != "_" }
            .joinToString("")

    fun pair(languages: List<String>): Pair<String, String>? {
        val codes = languages.map(::baseCode).filter { it in phrases }.distinct()
        return if (codes.size >= 2) codes[0] to codes[1] else null
    }

    fun text(languages: List<String>): String? {
        val (first, second) = pair(languages) ?: return null
        val a = phrases.getValue(first)
        val b = phrases.getValue(second)
        return "${a.open[0]}, ${b.close[0]}. ${a.open[1]}, ${b.close[1]}."
    }

    fun userLanguages(
        settings: PaplySettings,
        deviceLanguages: List<String> = emptyList(),
    ): List<String> {
        val list =
            listOfNotNull(settings.language?.takeIf { it.isNotEmpty() }) + settings.spokenLanguages
        return list.ifEmpty { deviceLanguages }
    }
}
