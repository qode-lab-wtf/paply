package com.paply.thoughts.ai

import com.paply.core.*
import com.paply.thoughts.model.TextForm

/** The iOS .thought profile. Kept here so :core's dictation implementation stays untouched. */
object ThoughtSafetyNet {
    fun spokenNegationCount(text: String): Int {
        var stripped = text
        for (run in
            TextAnalysis.runs(text) { TextAnalysis.isLetter(it) || TextAnalysis.isMark(it) }
                .asReversed()) if (
            TextAnalysis.normalizedLower(run.word) in listOf("nee", "nein", "nö")
        )
            stripped = stripped.removeRange(run.start, run.end)
        return TextAnalysis.negationCount(stripped)
    }

    fun rejection(raw: String, result: String, vocabulary: String = ""): String? {
        if (result.isEmpty()) return "empty"
        if (PolishSafetyNet.isMetaAnswer(result, raw)) return "meta"
        val reason = check(raw, result, vocabulary, raw) ?: return null
        val resolved = EditCheck.resolvedSelfCorrection(raw)
        return if (resolved != null && check(resolved, result, vocabulary, raw) == null) null
        else reason
    }

    private fun check(
        raw: String,
        result: String,
        vocabulary: String,
        lengthReference: String,
    ): String? {
        val measured = result.replace("• ", "").replace("\n", "")
        fun n(s: String) = s.codePointCount(0, s.length)
        val length = n(measured).toDouble()
        val low = length / maxOf(1, n(TextForm.trim(raw)))
        val high = length / maxOf(1, n(TextForm.trim(lengthReference)))
        if (low < 0.55 || high > 1.15) return "length"
        val (rawWords, resultWords) =
            EditCheck.compoundAligned(
                TextAnalysis.letterRuns(TextAnalysis.normalizedLower(raw)),
                TextAnalysis.letterRuns(TextAnalysis.normalizedLower(result)),
            )
        val before =
            TextAnalysis.contentUnits(rawWords.joinToString(" "))
                .filterNot(SpokenNumbers::isNumberWord)
        val after =
            TextAnalysis.contentUnits(resultWords.joinToString(" "))
                .filterNot(SpokenNumbers::isNumberWord)
        val remaining = after.groupingBy { it }.eachCount().toMutableMap()
        var missing = 0
        for (word in before) {
            val count = remaining[word] ?: 0
            if (count > 0) remaining[word] = count - 1 else missing++
        }
        if (before.isNotEmpty() && missing.toDouble() / before.size > 0.25) return "content"
        if (spokenNegationCount(raw) != spokenNegationCount(result)) return "negation"
        if (!SpokenNumbers.preserved(raw, result)) return "digits"
        val allowed = before.toSet() + TextAnalysis.contentUnits(vocabulary)
        val added = after.count { it !in allowed }
        return if (added - missing > maxOf(2, kotlin.math.ceil(before.size * 0.10).toInt())) "added"
        else null
    }
}
