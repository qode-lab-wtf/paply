package com.paply.core

internal object TranscriptCleanup {
    const val voicedMsPerWord = 100.0

    data class Cleaned(val text: String, val segments: List<WhisperSegment>)

    fun removeEchoes(
        text: String,
        segments: List<WhisperSegment>,
        primer: String?,
        previousText: String?,
        vocabulary: String,
        duration: Double,
        voiced: (Double, Double) -> Double,
    ): Cleaned {
        val primerWords =
            TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(primer.orEmpty()))
        val tailWords =
            TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(previousText.orEmpty()))
        val vocab = PolishPrompt.vocabularyPrompt(vocabulary)
        fun isEcho(piece: String, start: Double, end: Double): Boolean {
            val words = TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(piece))
            if (words.isEmpty()) return false
            val fromPrimer = words.size >= 3 && containsSequence(primerWords, words)
            val fromTail = words.size >= 2 && containsSequence(tailWords, words)
            val fromVocabulary = vocab.isNotEmpty() && PolishPrompt.isVocabularyEcho(piece, vocab)
            if (!fromPrimer && !fromTail && !fromVocabulary) return false
            return voiced(maxOf(0.0, start - 0.2), end + 0.2) < voicedMsPerWord * words.size
        }
        if (segments.isEmpty())
            return Cleaned(if (isEcho(text, 0.0, duration)) "" else text, emptyList())
        val kept = segments.filter {
            !isEcho(it.text.orEmpty(), it.start ?: 0.0, it.end ?: duration)
        }
        if (kept.size == segments.size) return Cleaned(text, segments)
        return Cleaned(
            kept.map { it.text.orEmpty().trimmed() }.filter(String::isNotEmpty).joinToString(" "),
            kept,
        )
    }

    fun containsSequence(haystack: List<String>, needle: List<String>): Boolean {
        if (needle.isEmpty() || haystack.size < needle.size) return false
        return (0..haystack.size - needle.size).any {
            haystack.subList(it, it + needle.size) == needle
        }
    }

    private fun isContinuaEdge(s: Int) =
        TextAnalysis.isScriptioContinua(s) || TextAnalysis.isContinuaPunctuation(s)

    fun join(texts: List<String>): String {
        var out = ""
        for (text in texts) {
            var next = text.trimmed()
            if (next.isEmpty()) continue
            if (out.isEmpty()) {
                out = next
                continue
            }
            next = removeRepeatedLead(out, next)
            if (next.isEmpty()) continue
            val tight =
                isContinuaEdge(out.codePointBefore(out.length)) &&
                    isContinuaEdge(next.codePointAt(0))
            out += if (tight) next else " $next"
        }
        return out
    }

    fun removeRepeatedLead(previous: String, next: String): String {
        val previousWords = TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(previous))
        val nextTokens = TextAnalysis.runs(next, TextAnalysis::isWordScalar)
        val limit = minOf(10, previousWords.size, nextTokens.size)
        for (k in limit downTo 2) {
            val lead = nextTokens.take(k).map { TextAnalysis.normalizedLower(it.word) }
            if (previousWords.takeLast(k) != lead) continue
            if (k == 2 && lead.none { TextAnalysis.weightedLength(it) >= 4 }) continue
            val rest = next.substring(nextTokens[k - 1].end)
            var i = 0
            while (
                i < rest.length &&
                    !TextAnalysis.isLetter(rest.codePointAt(i)) &&
                    !TextAnalysis.isNumber(rest.codePointAt(i))
            ) i += Character.charCount(rest.codePointAt(i))
            return rest.substring(i)
        }
        return next
    }
}
