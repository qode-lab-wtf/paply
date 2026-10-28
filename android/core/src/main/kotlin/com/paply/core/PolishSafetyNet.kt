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

    fun rejection(
        raw: String,
        result: String,
        vocabulary: String = "",
        strictEdits: Boolean = true,
    ): String? {
        if (result.isEmpty()) return "empty"
        if (isMetaAnswer(result, raw)) return "meta"
        val reason = check(raw, result, vocabulary, strictEdits, raw) ?: return null
        val resolved = EditCheck.resolvedSelfCorrection(raw)
        if (resolved != null && check(resolved, result, vocabulary, strictEdits, raw) == null)
            return null
        return reason
    }

    private fun check(
        raw: String,
        result: String,
        vocabulary: String,
        strictEdits: Boolean,
        lengthReference: String,
    ): String? {
        val resultLength = result.scalarCount.toDouble()
        val low = resultLength / maxOf(1, raw.trimmed().scalarCount)
        val high = resultLength / maxOf(1, lengthReference.trimmed().scalarCount)
        if (low < 0.7 || high > 1.3) return "length"
        val (rawWords, resultWords) =
            EditCheck.compoundAligned(
                TextAnalysis.letterRuns(TextAnalysis.normalizedLower(raw)),
                TextAnalysis.letterRuns(TextAnalysis.normalizedLower(result)),
            )
        val before = contentWords(rawWords.joinToString(" "))
        val after = contentWords(resultWords.joinToString(" "))
        val remaining = after.groupingBy { it }.eachCount().toMutableMap()
        var missing = 0
        for (word in before) {
            val count = remaining[word] ?: 0
            if (count > 0) remaining[word] = count - 1 else missing++
        }
        if (before.isNotEmpty() && missing.toDouble() / before.size > 0.3) return "content"
        if (negationCount(raw) != negationCount(result)) return "negation"
        if (!EditCheck.digitsPreserved(raw, result)) return "digits"
        if (strictEdits)
            EditCheck.substitutionRejection(raw, result, vocabulary)?.let {
                return it
            }
        val allowed = before.toSet() + contentWords(vocabulary)
        val added = after.count { it !in allowed }
        val limit = maxOf(2, ceil(before.size * 0.15).toInt())
        return if (added - missing > limit) "added" else null
    }
}
