package com.paply.core

import kotlinx.coroutines.delay

/** Android supplies its local language recognizer. No network and no guesses on short input. */
fun interface LanguageDetector {
    fun detect(text: String): String?
}

object NoLanguageDetector : LanguageDetector {
    override fun detect(text: String): String? = null
}

fun detectLanguage(text: String, detector: LanguageDetector = NoLanguageDetector): String? =
    if (TextAnalysis.letterRuns(text).size < 2) null
    else detector.detect(text)?.substringBefore('-')

/**
 * Reserved NLP boundary: Android supplies language-aware lemmas when thoughts need them. The
 * dictation text rules do not use NaturalLanguage lemmatization in the Swift source.
 */
fun interface Lemmatizer {
    fun lemmas(text: String): List<String>
}

object IdentityLemmatizer : Lemmatizer {
    override fun lemmas(text: String) = TextAnalysis.letterRuns(TextAnalysis.normalizedLower(text))
}

/**
 * Wall time for cache/history; monotonic time for elapsed durations. Android may use
 * elapsedRealtimeNanos.
 */
interface PaplyClock {
    fun nowMillis(): Long

    fun monotonicNanos(): Long

    suspend fun sleep(seconds: Double)
}

object SystemPaplyClock : PaplyClock {
    override fun nowMillis() = System.currentTimeMillis()

    override fun monotonicNanos() = System.nanoTime()

    override suspend fun sleep(seconds: Double) {
        delay(kotlin.math.ceil(seconds.coerceAtLeast(0.0) * 1000).toLong())
    }
}

/**
 * Android supplies ConnectivityManager state. Unknown/default remains optimistic; HTTP is
 * authoritative.
 */
fun interface NetworkReachability {
    fun isReachable(): Boolean
}

object AssumeReachable : NetworkReachability {
    override fun isReachable() = true
}

// Foundation includes ZERO WIDTH SPACE in whitespacesAndNewlines; Unicode White_Space does not.
internal fun String.trimmed() = trim { it.code.isUnicodeWhitespace() || it == '\u200b' }

internal fun Int.isFoundationSpace() =
    this == 9 ||
        this == 0x200b ||
        (isUnicodeWhitespace() &&
            this !in 10..13 &&
            this != 0x85 &&
            this != 0x2028 &&
            this != 0x2029)

internal fun String.scalars(): IntArray = codePoints().toArray()

internal fun Int.scalarString(): String = String(Character.toChars(this))

internal val String.scalarCount
    get() = codePointCount(0, length)

internal fun String.scalarPrefix(n: Int) =
    substring(0, offsetByCodePoints(0, n.coerceAtMost(scalarCount)))

// Java 17's \X implements extended grapheme clusters (Swift Character), unlike String.length.
private val graphemePattern = Regex("\\X")

internal fun String.characters(): List<String> =
    graphemePattern.findAll(this).map { it.value }.toList()

internal fun Int.isUnicodeWhitespace() =
    this in 0x09..0x0d ||
        this == 0x20 ||
        this == 0x85 ||
        this == 0xa0 ||
        this == 0x1680 ||
        this in 0x2000..0x200a ||
        this in 0x2028..0x2029 ||
        this == 0x202f ||
        this == 0x205f ||
        this == 0x3000

/** Swift split(whereSeparator: Character.isWhitespace): discard the entire whitespace cluster. */
internal fun String.words(): List<String> {
    val result = mutableListOf<String>()
    val word = StringBuilder()
    for (character in characters()) {
        if (character.codePointAt(0).isUnicodeWhitespace()) {
            if (word.isNotEmpty()) {
                result += word.toString()
                word.clear()
            }
        } else word.append(character)
    }
    if (word.isNotEmpty()) result += word.toString()
    return result
}
