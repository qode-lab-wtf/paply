package com.paply.core

import kotlin.math.ceil

object PolishSafetyNet {
    private val closedThinking = Pattern("<(think|analysis)\\b[^>]*>[\\s\\S]*?</\\1\\s*>", true)
    private val leadingThinking = Pattern("^[\\s\\S]*?</(?:think|analysis)\\s*>", true)
    private val openThinking = Pattern("<(?:think|analysis)\\b[\\s\\S]*$", true)
    private val finalChannel =
        Pattern("(?:<\\|channel\\|>final(?:<\\|message\\|>|\\|>)|<\\|final\\|>)([\\s\\S]*)")
    private val controlToken = Pattern("<\\|[^>]+\\|>")
    private val analysisLeftover = Pattern("<\\|(?:channel\\|>analysis|start\\|>)", true)

    fun finalPolishText(content: String?): String {
        if (content == null) return ""
        var text = closedThinking.replacing(content)
        text = leadingThinking.replacingFirst(text)
        text = openThinking.replacing(text).trimmed()
        finalChannel.firstGroup(text)?.let { text = controlToken.replacing(it).trimmed() }
        return if (analysisLeftover.matches(text)) "" else text
    }

    fun contentWords(text: String) = TextAnalysis.contentUnits(text)

    fun negationCount(text: String) = TextAnalysis.negationCount(text)

    fun isMetaAnswer(result: String, raw: String) =
        (Lexicon.metaAnswer.matches(result) && !Lexicon.metaAnswer.matches(raw.trimmed())) ||
            (Lexicon.wrappedInQuotes.matches(result) &&
                !Lexicon.wrappedInQuotes.matches(raw.trimmed()))

    enum class Profile { dictation, thought }

    private data class Limits(
        val lengthLow: Double,
        val lengthHigh: Double,
        val missingContent: Double,
        val addedShare: Double,
        val spoken: Boolean = false,
    )

    private val dictationLimits = Limits(0.7, 1.3, 0.3, 0.15)
    private val thoughtLimits = Limits(0.55, 1.15, 0.25, 0.10, spoken = true)

    fun rejection(
        raw: String,
        result: String,
        vocabulary: String = "",
        profile: Profile,
    ): String? = when (profile) {
        Profile.dictation -> rejection(raw, result, vocabulary, true, dictationLimits)
        Profile.thought -> rejection(raw, result, vocabulary, false, thoughtLimits)
    }

    fun spokenNegationCount(text: String): Int {
        var stripped = text
        for (run in TextAnalysis.runs(text) { TextAnalysis.isLetter(it) || TextAnalysis.isMark(it) }
            .asReversed()) {
            if (TextAnalysis.normalizedLower(run.word) in listOf("nee", "nein", "nö"))
                stripped = stripped.removeRange(run.start, run.end)
        }
        return negationCount(stripped)
    }

    fun rejection(
        raw: String,
        result: String,
        vocabulary: String = "",
        strictEdits: Boolean = true,
    ): String? = rejection(raw, result, vocabulary, strictEdits, dictationLimits)

    private fun rejection(
        raw: String,
        result: String,
        vocabulary: String,
        strictEdits: Boolean,
        limits: Limits,
    ): String? {
        if (result.isEmpty()) return "empty"
        if (isMetaAnswer(result, raw)) return "meta"
        val reason = check(raw, result, vocabulary, strictEdits, raw, limits) ?: return null
        val resolved = EditCheck.resolvedSelfCorrection(raw)
        if (resolved != null && check(resolved, result, vocabulary, strictEdits, raw, limits) == null)
            return null
        return reason
    }

    private fun check(
        raw: String,
        result: String,
        vocabulary: String,
        strictEdits: Boolean,
        lengthReference: String,
        limits: Limits,
    ): String? {
        val measured = if (limits.spoken) result.replace("• ", "").replace("\n", "") else result
        val resultLength = measured.scalarCount.toDouble()
        val low = resultLength / maxOf(1, raw.trimmed().scalarCount)
        val high = resultLength / maxOf(1, lengthReference.trimmed().scalarCount)
        if (low < limits.lengthLow || high > limits.lengthHigh) return "length"
        val (rawWords, resultWords) =
            EditCheck.compoundAligned(
                TextAnalysis.letterRuns(TextAnalysis.normalizedLower(raw)),
                TextAnalysis.letterRuns(TextAnalysis.normalizedLower(result)),
            )
        val before = contentWords(rawWords.joinToString(" ")).let { words ->
            if (limits.spoken) words.filterNot(SpokenNumbers::isNumberWord) else words
        }
        val after = contentWords(resultWords.joinToString(" ")).let { words ->
            if (limits.spoken) words.filterNot(SpokenNumbers::isNumberWord) else words
        }
        val remaining = after.groupingBy { it }.eachCount().toMutableMap()
        var missing = 0
        for (word in before) {
            val count = remaining[word] ?: 0
            if (count > 0) remaining[word] = count - 1 else missing++
        }
        if (before.isNotEmpty() && missing.toDouble() / before.size > limits.missingContent) return "content"
        if (limits.spoken) {
            if (spokenNegationCount(raw) != spokenNegationCount(result)) return "negation"
            if (!SpokenNumbers.preserved(raw, result)) return "digits"
        } else {
            if (negationCount(raw) != negationCount(result)) return "negation"
            if (!EditCheck.digitsPreserved(raw, result)) return "digits"
        }
        if (strictEdits)
            EditCheck.substitutionRejection(raw, result, vocabulary)?.let {
                return it
            }
        val allowed = before.toSet() + contentWords(vocabulary)
        val added = after.count { it !in allowed }
        val limit = maxOf(2, ceil(before.size * limits.addedShare).toInt())
        return if (added - missing > limit) "added" else null
    }
}
