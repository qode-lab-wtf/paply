package com.paply.thoughts.nlp

import com.paply.core.*
import java.text.BreakIterator
import java.util.Locale
import org.tartarus.snowball.ext.englishStemmer
import org.tartarus.snowball.ext.germanStemmer

/** Explicit stems, not a claim of Apple lemma/POS/NER parity. Originals always remain available. */
interface LexicalAnalyzer {
    data class Token(
        val original: String,
        val normalized: String,
        val stem: String?,
        val partOfSpeech: PartOfSpeech?,
        val isName: Boolean,
    )

    enum class PartOfSpeech {
        noun,
        verb,
        otherWord,
    }

    fun analyze(text: String, language: String?): List<Token>
}

class SnowballLemmatizer(private val language: String? = null) : Lemmatizer, LexicalAnalyzer {
    override fun lemmas(text: String): List<String> =
        analyze(text, language)
            .flatMap {
                // With no reliable language, offer both de/en stems; source forms are retained by
                // the validator.
                if (language == null)
                    listOfNotNull(stem(it.normalized, "de"), stem(it.normalized, "en"))
                else listOfNotNull(it.stem)
            }
            .distinct()

    override fun analyze(text: String, language: String?): List<LexicalAnalyzer.Token> =
        TextAnalysis.runs(text) { TextAnalysis.isLetter(it) || TextAnalysis.isMark(it) }
            .map { run ->
                val lower = TextAnalysis.normalizedLower(run.word)
                val prefix = text.substring(0, run.start).trimEnd()
                val sentenceStart = prefix.isEmpty() || prefix.last() in ".!?\n\r"
                val caps = run.word.codePointAt(0).let(Character::isUpperCase)
                val interiorUpper = run.word.codePoints().skip(1).anyMatch(Character::isUpperCase)
                val possibleName = interiorUpper || (caps && !sentenceStart)
                val pos =
                    when {
                        caps && !sentenceStart -> LexicalAnalyzer.PartOfSpeech.noun
                        lower.endsWith("en") ||
                            lower.endsWith("ern") ||
                            lower.endsWith("eln") ||
                            (language == "en" && (lower.endsWith("ing") || lower.endsWith("ed"))) ->
                            LexicalAnalyzer.PartOfSpeech.verb
                        else -> LexicalAnalyzer.PartOfSpeech.otherWord
                    }
                LexicalAnalyzer.Token(run.word, lower, stem(lower, language), pos, possibleName)
            }

    fun stem(word: String, language: String?): String? {
        val stemmer =
            when (language?.substringBefore('-')) {
                "de" -> germanStemmer()
                "en" -> englishStemmer()
                else -> return null
            }
        stemmer.setCurrent(word)
        stemmer.stem()
        return stemmer.current.takeIf { it.isNotEmpty() }
    }
}

fun interface SentenceSegmenter {
    fun sentences(text: String, language: String?): List<String>
}

object BreakIteratorSentenceSegmenter : SentenceSegmenter {
    override fun sentences(text: String, language: String?): List<String> {
        if (text.isEmpty()) return emptyList()
        val iterator = BreakIterator.getSentenceInstance(Locale.forLanguageTag(language ?: "und"))
        iterator.setText(text)
        val result = mutableListOf<String>()
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) {
            text.substring(start, end).trim().takeIf { it.isNotEmpty() }?.let(result::add)
            start = end
            end = iterator.next()
        }
        return result.ifEmpty { listOf(text) }
    }
}

interface Embedder {
    data class Vector(
        val values: List<Float>,
        val modelRevision: String,
        val tokenizerRevision: String,
        val quantizationRevision: String,
        val space: String,
        val language: String?,
    ) {
        val dimension
            get() = values.size

        fun compatible(other: Vector) =
            modelRevision == other.modelRevision &&
                tokenizerRevision == other.tokenizerRevision &&
                quantizationRevision == other.quantizationRevision &&
                space == other.space &&
                dimension == other.dimension
    }

    val available: Boolean

    fun embed(text: String, language: String?): Vector?
}

object UnavailableEmbedder : Embedder {
    override val available = false

    override fun embed(text: String, language: String?): Embedder.Vector? = null
}
