package com.paply.thoughts.display

import com.paply.core.Lexicon
import com.paply.core.TextAnalysis
import com.paply.thoughts.model.TextForm

object RawTitle {
    data class Parts(val title: String, val rest: String)

    private val leadingParticles =
        setOf(
            "also",
            "ja",
            "naja",
            "okay",
            "ok",
            "okey",
            "ach",
            "achso",
            "genau",
            "und",
            "well",
            "and",
        )
    private val leadingWithComma = setOf("so", "gut", "nun", "na", "right", "alright", "jo")

    fun split(raw: String, maxWords: Int = 6): Parts? {
        val words = TextForm.words(raw).filter { bare(it) !in Lexicon.fillers }.toMutableList()
        while (
            words.size > 1 &&
                (bare(words[0]) in leadingParticles ||
                    bare(words[0]) in leadingWithComma && words[0].endsWith(','))
        ) words.removeAt(0)
        while (
            words.isNotEmpty() &&
                !words[0].codePoints().anyMatch { Character.isLetter(it) || Character.isDigit(it) }
        ) words.removeAt(0)
        if (words.isEmpty()) return null
        var count = 0
        var endedSentence = false
        for (word in words) {
            count++
            if (word.lastOrNull() in setOf('.', '!', '?', '…')) {
                endedSentence = true
                break
            }
            if (count == maxOf(1, maxWords)) break
        }
        var title =
            capitalizedFirst(words.take(count).joinToString(" ").trimEnd { it in ".,;:–-…" })
        if (title.isEmpty()) return null
        val rest = words.drop(count).joinToString(" ")
        if (rest.isNotEmpty() && !endedSentence) title += " …"
        return Parts(title, if (endedSentence) capitalizedFirst(rest) else rest)
    }

    private fun bare(word: String) =
        TextAnalysis.normalizedLower(word.replace(Regex("^\\p{P}+|\\p{P}+$"), ""))

    private fun capitalizedFirst(text: String): String {
        val match =
            Regex("\\X").findAll(text).firstOrNull {
                it.value.codePoints().anyMatch { c ->
                    Character.isLetter(c) || Character.isDigit(c)
                }
            } ?: return text
        if (!Character.isLowerCase(match.value.codePointAt(0))) return text
        return text.replaceRange(match.range, match.value.uppercase())
    }
}
