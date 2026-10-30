package com.paply.thoughts.ai

import com.paply.core.TextAnalysis
import com.paply.thoughts.model.TextForm
import java.util.Locale

object TaskText {
    val edgeFillers = setOf("noch", "mal", "eben")
    val definiteArticles = setOf("der", "die", "das", "den", "dem", "des")

    fun tidy(raw: String, dueHint: String?): String {
        val original = TextForm.words(raw).joinToString(" ")
        var words = original.split(' ').filter { it.isNotEmpty() }
        if (dueHint != null) words = removingTimeExpression(dueHint, words)
        words = removingEdgeFillers(words)
        var text = words.joinToString(" ").trim { it in ",;:–—- " }
        if (!text.codePoints().anyMatch { Character.isLetter(it) || TextAnalysis.isNumber(it) })
            text = original
        return capitalizedFirstLetter(text)
    }

    private fun folded(list: List<String>) = list.map(ThoughtValidator::normalizedForMatch).toSet()

    val extraNegations =
        folded(
            listOf(
                "ohne",
                "without",
                "no",
                "nein",
                "nee",
                "non",
                "nope",
                "dont",
                "doesnt",
                "didnt",
                "cant",
                "wont",
                "isnt",
                "arent",
                "wasnt",
                "shouldnt",
                "mustnt",
                "neednt",
                "havent",
                "hasnt",
            ),
        )
    val blockedNeighbors =
        folded(
            listOf(
                "und",
                "oder",
                "bzw",
                "aber",
                "sondern",
                "statt",
                "anstatt",
                "erst",
                "nur",
                "bis",
                "ab",
                "seit",
                "für",
                "wegen",
                "am",
                "an",
                "zum",
                "zur",
                "vor",
                "nach",
                "and",
                "or",
                "but",
                "instead",
                "until",
                "by",
                "for",
                "before",
                "after",
                "beziehungsweise",
                "sowie",
                "als",
                "außer",
                "sonst",
                "anstelle",
                "zwischen",
                "von",
                "vom",
                "spätestens",
                "frühestens",
                "schon",
                "bereits",
                "wenn",
                "falls",
                "sobald",
                "bevor",
                "nachdem",
                "ob",
                "dass",
                "than",
                "rather",
                "except",
                "nor",
                "only",
                "already",
                "if",
                "when",
                "once",
                "unless",
                "between",
                "from",
                "since",
                "till",
                "til",
                "latest",
                "earliest",
                "heute",
                "morgen",
                "übermorgen",
                "gestern",
                "früh",
                "morgens",
                "vormittag",
                "vormittags",
                "mittag",
                "mittags",
                "nachmittag",
                "nachmittags",
                "abend",
                "abends",
                "nacht",
                "nachts",
                "uhr",
                "um",
                "halb",
                "viertel",
                "woche",
                "wochenende",
                "monat",
                "jahr",
                "today",
                "tomorrow",
                "tonight",
                "morning",
                "afternoon",
                "evening",
                "night",
                "noon",
                "midnight",
                "week",
                "weekend",
                "month",
                "year",
                "pm",
                "montag",
                "dienstag",
                "mittwoch",
                "donnerstag",
                "freitag",
                "samstag",
                "sonnabend",
                "sonntag",
                "monday",
                "tuesday",
                "wednesday",
                "thursday",
                "friday",
                "saturday",
                "sunday",
            ),
        )
    val prepositions =
        folded(
            listOf(
                "wegen",
                "für",
                "über",
                "von",
                "vom",
                "vor",
                "nach",
                "bis",
                "ab",
                "an",
                "am",
                "ans",
                "auf",
                "zu",
                "zum",
                "zur",
                "seit",
                "ohne",
                "mit",
                "um",
                "in",
                "im",
                "ins",
                "bei",
                "beim",
                "gegen",
                "aus",
                "unter",
                "zwischen",
                "während",
                "innerhalb",
                "binnen",
                "bezüglich",
                "for",
                "about",
                "of",
                "to",
                "at",
                "on",
                "by",
                "until",
                "before",
                "after",
                "from",
                "since",
                "with",
                "into",
                "regarding",
                "during",
                "within",
                "between",
            ),
        )
    val governingDeterminers =
        folded(
            listOf(
                "der",
                "die",
                "das",
                "den",
                "dem",
                "des",
                "ein",
                "eine",
                "einen",
                "einem",
                "einer",
                "eines",
                "nächste",
                "nächsten",
                "nächster",
                "nächstes",
                "übernächste",
                "übernächsten",
                "kommende",
                "kommenden",
                "kommender",
                "kommendes",
                "diese",
                "diesen",
                "dieser",
                "dieses",
                "diesem",
                "jede",
                "jeden",
                "jeder",
                "jedes",
                "jedem",
                "letzte",
                "letzten",
                "letzter",
                "letztes",
                "vorige",
                "vorigen",
                "the",
                "a",
                "an",
                "next",
                "this",
                "every",
                "each",
                "last",
                "coming",
                "following",
            ),
        )
    val spanWords =
        folded(
            listOf(
                "bis",
                "ab",
                "seit",
                "von",
                "vom",
                "während",
                "über",
                "until",
                "till",
                "til",
                "from",
                "since",
                "through",
                "thru",
                "during",
                "throughout",
            ),
        )
    val deadlineWords = folded(listOf("spätestens"))

    fun isNegated(text: String) =
        TextAnalysis.negationCount(text) > 0 || words(text).any { it in extraNegations }

    fun isPointInTime(hint: String): Boolean {
        val words = words(hint)
        return words.any { it in deadlineWords } || words.none { it in spanWords }
    }

    fun removingTimeExpression(hint: String, words: List<String>): List<String> {
        val target = ThoughtValidator.normalizedForMatch(hint)
        val text = words.joinToString(" ")
        if (
            target.isEmpty() ||
                words.size <= 1 ||
                isNegated(text) ||
                isNegated(hint) ||
                !isPointInTime(hint)
        )
            return words
        fun matches(part: List<String>) =
            ThoughtValidator.normalizedForMatch(part.joinToString(" ")) == target
        for (k in 1 until words.size) if (matches(words.take(k))) {
            val rest = words.drop(k)
            val real = rest.filter(::isRealWord)
            return if (real.size >= 2 && !isBlocked(real.first())) rest else words
        }
        for (k in 1 until words.size) if (matches(words.takeLast(k))) {
            val rest = words.dropLast(k)
            val real = rest.filter(::isRealWord)
            return if (
                real.size >= 2 &&
                    !isBlocked(real.last()) &&
                    key(real.last()) !in governingDeterminers &&
                    real.map(::key).none { it in prepositions }
            )
                rest
            else words
        }
        return words
    }

    private fun isBlocked(word: String) =
        key(word) in blockedNeighbors ||
            word.codePoints().anyMatch(TextAnalysis::isNumber) ||
            SpokenNumbers.isNumberWord(bare(word))

    private fun isRealWord(word: String) =
        word.codePoints().anyMatch { Character.isLetter(it) || TextAnalysis.isNumber(it) }

    private fun key(word: String) = ThoughtValidator.normalizedForMatch(word).replace(" ", "")

    private fun words(text: String) =
        ThoughtValidator.normalizedForMatch(text).split(' ').filter { it.isNotEmpty() }

    fun removingEdgeFillers(input: List<String>): List<String> {
        var words = input
        if (words.size >= 2 && bare(words[0]).lowercase(Locale.ROOT) in edgeFillers) {
            val next = bare(words[1])
            if (
                (next.firstOrNull()?.isUpperCase() == true ||
                    next.lowercase(Locale.ROOT) in definiteArticles) &&
                    !isNegated(firstClause(words.drop(1)))
            )
                words = words.drop(1)
        }
        if (
            words.size >= 2 &&
                bare(words.last()) in edgeFillers &&
                isInfinitive(words[words.size - 2]) &&
                !isNegated(lastClause(words.dropLast(1)))
        )
            words = words.dropLast(1)
        return words
    }

    private fun endsClause(word: String) =
        word.lastOrNull()?.let { it in ",;:" } == true || word in listOf("–", "—", "-")

    private fun firstClause(words: List<String>): String {
        val index = words.indexOfFirst(::endsClause)
        return (if (index < 0) words else words.take(index + 1)).joinToString(" ")
    }

    private fun lastClause(words: List<String>) =
        words.drop(words.indexOfLast(::endsClause) + 1).joinToString(" ")

    private fun isInfinitive(raw: String): Boolean {
        val word = bare(raw)
        return TextForm.count(word) >= 4 &&
            word == word.lowercase(Locale.ROOT) &&
            word !in edgeFillers &&
            TextAnalysis.negationCount(word) == 0 &&
            listOf("en", "rn", "ln").any(word::endsWith)
    }

    private fun bare(word: String) = word.replace(Regex("^[\\p{P}\\p{S}]+|[\\p{P}\\p{S}]+$"), "")

    fun capitalizedFirstLetter(text: String): String {
        val index = text.indices.firstOrNull { text[it].isLetterOrDigit() } ?: return text
        val first = text[index]
        if (!first.isLetter() || !first.isLowerCase()) return text
        val word = text.substring(index).takeWhile { !it.isWhitespace() && it != '-' }
        if (word.drop(1).any { it.isUpperCase() }) return text
        val upper = first.toString().uppercase(Locale.ROOT)
        return if (TextForm.count(upper) != 1) text else text.replaceRange(index, index + 1, upper)
    }
}
