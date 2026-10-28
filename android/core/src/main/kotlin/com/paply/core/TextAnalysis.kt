package com.paply.core

import java.text.Normalizer
import java.util.Locale

internal object TextAnalysis {
    fun normalizedLower(text: String): String {
        val lower = Normalizer.normalize(text, Normalizer.Form.NFC).lowercase(Locale.ROOT)
        if ('\u0307' !in lower && '\u0131' !in lower) return lower
        val out = StringBuilder()
        var previous = -1
        for (s in lower.scalars()) {
            if (s == 0x307 && previous == 'i'.code) continue
            val folded = if (s == 0x131) 'i'.code else s
            out.appendCodePoint(folded)
            previous = folded
        }
        return Normalizer.normalize(out, Normalizer.Form.NFC)
    }

    fun isLetter(s: Int) = Character.isLetter(s)

    fun isMark(s: Int) = Character.getType(s) in listOf(6, 7, 8)

    fun isNumber(s: Int) = Character.getType(s) in listOf(9, 10, 11)

    fun isWordScalar(s: Int) = isLetter(s) || isMark(s) || isNumber(s)

    fun isScriptioContinua(s: Int) =
        s in 0x3005..0x3007 ||
            s in 0x3040..0x30ff ||
            s in 0x31f0..0x31ff ||
            s in 0x3400..0x4dbf ||
            s in 0x4e00..0x9fff ||
            s in 0xf900..0xfaff ||
            s in 0xff66..0xff9d ||
            s in 0x20000..0x2fa1f ||
            s in 0xe00..0xe7f ||
            s in 0xe80..0xeff ||
            s in 0x1000..0x109f ||
            s in 0x1780..0x17ff

    fun isContinuaPunctuation(s: Int) =
        s in 0x3000..0x303f || s in 0xff01..0xff0f || s in 0xff1a..0xff20

    fun containsScriptioContinua(text: String) = text.scalars().any(::isScriptioContinua)

    fun weightedLength(word: String) = word.scalars().sumOf { if (it in 0xac00..0xd7a3) 2 else 1 }

    data class Run(val word: String, val start: Int, val end: Int)

    fun runs(text: String, belongs: (Int) -> Boolean): List<Run> {
        val out = mutableListOf<Run>()
        var start = -1
        var index = 0
        while (index < text.length) {
            val s = text.codePointAt(index)
            if (belongs(s)) {
                if (start < 0) start = index
            } else if (start >= 0) {
                out += Run(text.substring(start, index), start, index)
                start = -1
            }
            index += Character.charCount(s)
        }
        if (start >= 0) out += Run(text.substring(start), start, text.length)
        return out
    }

    fun letterRuns(text: String) = runs(text) { isLetter(it) || isMark(it) }.map { it.word }

    fun alphanumericRuns(text: String) = runs(text, ::isWordScalar).map { it.word }

    fun contentUnits(text: String): List<String> {
        val out = mutableListOf<String>()
        for (run in letterRuns(normalizedLower(text))) {
            val latin = StringBuilder()
            val continua = mutableListOf<Int>()
            fun flushLatin() {
                val w = latin.toString()
                if (weightedLength(w) >= 4 && w !in Lexicon.fillers) out += w
                latin.clear()
            }
            fun flushContinua() {
                if (continua.size == 1) out += continua[0].scalarString()
                else
                    for (i in 0 until continua.size - 1) out +=
                        continua[i].scalarString() + continua[i + 1].scalarString()
                continua.clear()
            }
            for (s in run.scalars()) if (isScriptioContinua(s)) {
                flushLatin()
                continua += s
            } else {
                flushContinua()
                latin.appendCodePoint(s)
            }
            flushLatin()
            flushContinua()
        }
        return out
    }

    fun negationCount(text: String): Int {
        val lower = normalizedLower(text)
        var count = 0
        for ((word, start, end) in runs(lower) { isLetter(it) || isMark(it) }) {
            if (word in Lexicon.negations) count++
            else if (
                word in Lexicon.answerNegators &&
                    (isSentenceStart(lower, start) || isSentenceInternal(lower, end))
            )
                count++
        }
        count += Lexicon.contractedNegation.count(lower)
        count += lower.scalars().count { it in Lexicon.negationScalars }
        for (fragment in Lexicon.negationFragments) count += lower.split(fragment).size - 1
        return count
    }

    private fun isSentenceStart(text: String, index: Int): Boolean {
        val last =
            text.substring(0, index).characters().lastOrNull {
                it.length != 1 || it[0] !in " \t\n¡¿\"„“«(‚'"
            } ?: return true
        return last.length == 1 && last[0] in ".!?…:"
    }

    private fun isSentenceInternal(text: String, index: Int): Boolean {
        val rest =
            text
                .substring(index)
                .characters()
                .dropWhile { it == " " || it == "\t" }
                .joinToString("")
        if (rest.isEmpty() || !isLetter(rest.codePointAt(0))) return false
        for (phrase in Lexicon.correctionPhrases) if (rest.startsWith(phrase)) {
            val after = rest.substring(phrase.length)
            if (after.isEmpty() || !isWordScalar(after.codePointAt(0))) return false
        }
        return true
    }
}
