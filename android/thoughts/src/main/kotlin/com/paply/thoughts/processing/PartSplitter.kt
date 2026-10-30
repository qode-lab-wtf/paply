package com.paply.thoughts.processing

import com.paply.core.TextAnalysis
import com.paply.thoughts.*
import com.paply.thoughts.model.TextForm
import com.paply.thoughts.nlp.BreakIteratorSentenceSegmenter
import kotlin.math.*

object PartSplitter {
    const val threshold = 1800
    const val maxPartTokens = 1400

    data class Part(val sentences: List<ThoughtSource.Sentence>, val text: String, val tokens: Int)

    data class Word(val text: String, val sentence: String, val boundary: Double)

    fun estimateTokens(text: String) = (text.toByteArray(Charsets.UTF_8).size + 2) / 3

    fun needsParts(transcript: String) = estimateTokens(transcript) > threshold

    val hesitations =
        setOf(
            "ähm",
            "äh",
            "öhm",
            "ähem",
            "ehm",
            "hm",
            "hmm",
            "mhm",
            "uh",
            "uhm",
            "umm",
            "erm",
            "euh",
            "euhm",
            "eeh",
            "ehh",
        )
    val hesitationsNotGerman = setOf("um", "er", "eh")
    val enumerations =
        setOf(
            "erstens",
            "zweitens",
            "drittens",
            "viertens",
            "letztens",
            "first",
            "firstly",
            "second",
            "secondly",
            "third",
            "thirdly",
            "finally",
            "naja",
            "jedenfalls",
            "außerdem",
            "übrigens",
            "anyway",
            "anyways",
        )
    val markers =
        setOf(
            "also",
            "so",
            "okay",
            "ok",
            "dann",
            "gut",
            "genau",
            "well",
            "alright",
            "right",
            "now",
            "alors",
            "donc",
            "bon",
            "enfin",
            "pues",
            "bueno",
            "entonces",
            "allora",
            "quindi",
            "comunque",
            "então",
            "bom",
            "dus",
            "nou",
        )
    val strongMarkers =
        listOf(
            listOf("und", "dann"),
            listOf("und", "noch"),
            listOf("na", "ja"),
            listOf("and", "then"),
            listOf("and", "also"),
            listOf("so", "yeah"),
            listOf("et", "puis"),
            listOf("y", "luego"),
            listOf("e", "poi"),
        )

    fun words(sentences: List<ThoughtSource.Sentence>, languages: List<String>): List<Word> {
        val german = languages.any { it.startsWith("de") }
        val result = mutableListOf<Word>()
        fun bare(s: String) =
            TextAnalysis.normalizedLower(s).replace(Regex("^\\p{P}+|\\p{P}+$"), "")
        for (sentence in sentences) {
            val tokens = TextForm.words(sentence.text)
            tokens.forEachIndexed { i, t ->
                val b = bare(t)
                val n = tokens.getOrNull(i + 1)?.let(::bare) ?: ""
                val previous = tokens.getOrNull(i - 1)?.lastOrNull()
                val boundary =
                    when {
                        i == 0 || previous in listOf('.', '!', '?', '…') -> 4.0
                        b in hesitations || (!german && b in hesitationsNotGerman) -> 3.0
                        listOf(b, n) in strongMarkers || b in enumerations -> 3.0
                        b in markers -> 2.0
                        previous in listOf(',', ';', ':', '–') -> 1.0
                        else -> 0.0
                    }
                result.add(Word(t, sentence.id, boundary))
            }
        }
        return result
    }

    fun split(source: ThoughtSource, force: Boolean = false): List<Part> {
        val sentences =
            source.sentences.ifEmpty { listOf(ThoughtSource.Sentence("s0", source.text)) }
        val total = estimateTokens(source.text)
        if (!force && total <= threshold) return listOf(Part(sentences, source.text, total))
        val words = words(sentences, source.languages)
        if (words.size <= 1) return listOf(Part(sentences, source.text, total))
        val prefix = IntArray(words.size + 1)
        words.forEachIndexed { i, w ->
            prefix[i + 1] = prefix[i] + w.text.toByteArray(Charsets.UTF_8).size + 1
        }
        fun tokens(a: Int, b: Int) = (maxOf(0, prefix[b] - prefix[a] - 1) + 2) / 3
        val count =
            maxOf(
                if (force) 2 else 1,
                ceil(tokens(0, words.size) / maxPartTokens.toDouble()).toInt(),
            )
        val cuts = mutableListOf<Int>()
        var start = 0
        while (
            start < words.size - 1 &&
                (tokens(start, words.size) > maxPartTokens || cuts.size + 1 < count)
        ) {
            val target = tokens(start, words.size).toDouble() / maxOf(1, count - cuts.size)
            var best: Int? = null
            var score = Double.NEGATIVE_INFINITY
            var end = start + 1
            while (end < words.size && tokens(start, end) <= maxPartTokens) {
                val size = tokens(start, end).toDouble()
                if (size >= target * 0.6) {
                    val candidate =
                        words[end].boundary * 10 + 1 - minOf(1.0, abs(size - target) / target)
                    if (candidate > score) {
                        best = end
                        score = candidate
                    }
                }
                end++
            }
            val cut = best ?: maxOf(start + 1, end - 1)
            cuts.add(cut)
            start = cut
        }
        var from = 0
        return (cuts + words.size).map { to ->
            val part = words.subList(from, to)
            from = to
            val ss = mutableListOf<ThoughtSource.Sentence>()
            for (w in part) {
                val last = ss.lastOrNull()
                if (last?.id == w.sentence)
                    ss[ss.lastIndex] = last.copy(text = last.text + " " + w.text)
                else ss.add(ThoughtSource.Sentence(w.sentence, w.text))
            }
            val text = part.joinToString(" ") { it.text }
            Part(ss, text, estimateTokens(text))
        }
    }

    fun sentences(text: String, thoughtID: String) =
        BreakIteratorSentenceSegmenter.sentences(text, null)
            .mapIndexed { i, s -> ThoughtSource.Sentence("${thoughtID}_s$i", TextForm.trim(s)) }
            .filter { it.text.isNotEmpty() }
}
