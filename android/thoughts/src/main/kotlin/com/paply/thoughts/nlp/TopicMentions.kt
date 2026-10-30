package com.paply.thoughts.nlp

import com.paply.core.Lexicon
import com.paply.core.TextAnalysis
import com.paply.thoughts.Topic
import java.text.Normalizer

/**
 * Pure word-boundary hints. V1 has no dictionary, so derived proper-name -er matches are
 * unavailable.
 */
object TopicMentions {
    data class Term(val original: String, val forms: Set<String>, val stems: Set<String>)

    class Haystack(text: String) {
        val forms = TextAnalysis.alphanumericRuns(text).flatMap { TopicMentions.forms(it) }.toSet()
        val keys =
            forms + TextAnalysis.alphanumericRuns(text).flatMap { bases(it).flatMap(::forms) }

        fun contains(term: Term) = term.forms.any { it in keys } || term.stems.any { it in forms }
    }

    fun terms(title: String, note: String?): List<Term> =
        Topic.normalizedNote(note)?.let { words("$title $it") } ?: emptyList()

    fun terms(topic: Topic) = terms(topic.title, topic.note)

    fun words(text: String): List<Term> =
        TextAnalysis.alphanumericRuns(text).mapNotNull(::term).distinctBy {
            it.forms.sorted().joinToString("|")
        }

    fun term(word: String): Term? {
        val folded = fold(word)
        if (
            folded.codePointCount(0, folded.length) < 3 ||
                !folded.codePoints().anyMatch(TextAnalysis::isLetter)
        )
            return null
        val forms = forms(word)
        if (forms.any { it in stopwords } || folded in Lexicon.fillers) return null
        return Term(word, forms, bases(word).flatMap(::forms).toSet())
    }

    fun matches(terms: List<Term>, haystack: Haystack) =
        terms.filter(haystack::contains).map { it.original }

    fun matches(topic: Topic, text: String) = matches(terms(topic), Haystack(text))

    fun fold(word: String): String =
        plain(
            TextAnalysis.normalizedLower(word)
                .replace("ä", "ae")
                .replace("ö", "oe")
                .replace("ü", "ue")
                .replace("ß", "ss"),
        )

    fun plain(word: String): String =
        Normalizer.normalize(
            Normalizer.normalize(word, Normalizer.Form.NFKD).replace(Regex("\\p{M}"), ""),
            Normalizer.Form.NFC,
        )

    fun forms(word: String) =
        setOf(fold(word), plain(TextAnalysis.normalizedLower(word).replace("ß", "ss")))

    @Suppress("UNUSED_PARAMETER")
    fun bases(word: String, derivedNames: Boolean = true): List<String> {
        val lower = TextAnalysis.normalizedLower(word)
        val length = word.codePointCount(0, word.length)
        val result = mutableListOf<String>()
        if (lower.endsWith("s") && length - 1 >= 3) result.add(word.dropLast(1))
        if (lower.endsWith("es") && length - 2 >= 4) result.add(word.dropLast(2))
        if (lower.endsWith("e") && length - 1 >= 5) result.add(word.dropLast(1))
        if (lower.endsWith("en") && length - 2 >= 5 && !lower.dropLast(2).endsWith("e"))
            result.add(word.dropLast(2))
        if (
            lower.endsWith("n") &&
                length - 1 >= 4 &&
                listOf("e", "el", "er").any { lower.dropLast(1).endsWith(it) }
        )
            result.add(word.dropLast(1))
        return result
    }

    private val stopwords: Set<String> =
        listOf(
                "der",
                "die",
                "das",
                "den",
                "dem",
                "des",
                "ein",
                "eine",
                "einer",
                "eines",
                "einem",
                "einen",
                "und",
                "oder",
                "aber",
                "auch",
                "noch",
                "nur",
                "sowie",
                "bzw",
                "usw",
                "etc",
                "inkl",
                "plus",
                "mit",
                "ohne",
                "für",
                "fuer",
                "von",
                "vom",
                "zum",
                "zur",
                "bei",
                "beim",
                "auf",
                "aus",
                "über",
                "unter",
                "nach",
                "vor",
                "seit",
                "bis",
                "gegen",
                "durch",
                "rund",
                "um",
                "ums",
                "als",
                "wie",
                "was",
                "wer",
                "wo",
                "ich",
                "mich",
                "mir",
                "mein",
                "meine",
                "meiner",
                "meines",
                "meinem",
                "meinen",
                "wir",
                "uns",
                "unser",
                "unsere",
                "unserer",
                "unseres",
                "unserem",
                "unseren",
                "sie",
                "ihr",
                "ihre",
                "ihren",
                "ihrem",
                "ihrer",
                "er",
                "ihn",
                "ihm",
                "sein",
                "seine",
                "seinen",
                "seinem",
                "seiner",
                "dein",
                "deine",
                "man",
                "alle",
                "alles",
                "bin",
                "ist",
                "sind",
                "war",
                "hat",
                "habe",
                "haben",
                "wird",
                "werden",
                "kann",
                "muss",
                "soll",
                "hier",
                "dort",
                "dazu",
                "davon",
                "dabei",
                "sonst",
                "sonstiges",
                "andere",
                "anderes",
                "weitere",
                "herr",
                "herrn",
                "frau",
                "dr",
                "prof",
                "mr",
                "mrs",
                "ms",
                "sir",
                "gmbh",
                "mbh",
                "ug",
                "ag",
                "kg",
                "ohg",
                "gbr",
                "ev",
                "co",
                "inc",
                "ltd",
                "llc",
                "plc",
                "corp",
                "firma",
                "firmen",
                "unternehmen",
                "kunde",
                "kunden",
                "kundin",
                "kundinnen",
                "auftraggeber",
                "projekt",
                "projekte",
                "thema",
                "themen",
                "sache",
                "sachen",
                "dinge",
                "zeug",
                "kram",
                "privat",
                "arbeit",
                "job",
                "team",
                "chef",
                "chefin",
                "kollege",
                "kollegen",
                "kollegin",
                "kolleginnen",
                "ansprechpartner",
                "ansprechpartnerin",
                "kontakt",
                "kontakte",
                "person",
                "personen",
                "leute",
                "mitglied",
                "mitglieder",
                "verein",
                "gruppe",
                "name",
                "namen",
                "betreff",
                "allgemein",
                "the",
                "and",
                "or",
                "of",
                "for",
                "with",
                "from",
                "to",
                "at",
                "in",
                "on",
                "by",
                "my",
                "our",
                "your",
                "his",
                "her",
                "its",
                "their",
                "is",
                "are",
                "was",
                "be",
                "all",
                "any",
                "about",
                "also",
                "via",
                "per",
                "company",
                "client",
                "clients",
                "customer",
                "customers",
                "project",
                "projects",
                "team",
                "work",
                "stuff",
                "things",
                "people",
                "contact",
                "contacts",
                "club",
                "group",
                "member",
                "members",
            )
            .flatMap(::forms)
            .toSet()
}

/**
 * iOS's safe fallback when either word dictionary is unavailable. Never treats an unknown noun as a
 * proper name.
 */
object CommonWords {
    const val available = false

    fun contains(word: String) = true
}
