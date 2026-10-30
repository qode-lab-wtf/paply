package com.paply.core

public object EditCheck {
    val numberWords: Map<String, Int> = buildMap {
        fun add(value: Int, vararg words: String) {
            for (w in words) put(TextAnalysis.normalizedLower(w), value)
        }
        // Deutsch
        add(0, "null")
        add(1, "eins", "ein", "eine", "einen", "einem", "einer", "eines")
        add(2, "zwei")
        add(3, "drei")
        add(4, "vier")
        add(5, "fünf")
        add(6, "sechs")
        add(7, "sieben")
        add(8, "acht")
        add(9, "neun")
        add(10, "zehn")
        add(11, "elf")
        add(12, "zwölf")
        add(13, "dreizehn")
        add(14, "vierzehn")
        add(15, "fünfzehn")
        add(16, "sechzehn")
        add(17, "siebzehn")
        add(18, "achtzehn")
        add(19, "neunzehn")
        add(20, "zwanzig")
        add(30, "dreißig")
        add(40, "vierzig")
        add(50, "fünfzig")
        add(60, "sechzig")
        add(70, "siebzig")
        add(80, "achtzig")
        add(90, "neunzig")
        add(100, "hundert")
        add(1000, "tausend")
        for ((stem, value) in
            listOf(
                "erst" to 1,
                "zweit" to 2,
                "dritt" to 3,
                "viert" to 4,
                "fünft" to 5,
                "sechst" to 6,
                "siebt" to 7,
                "acht" to 8,
                "neunt" to 9,
                "zehnt" to 10,
            )) {
            for (ending in listOf("e", "en", "er", "es", "em", "ens")) {
                add(value, stem + ending)
            }
        }
        // Englisch
        add(0, "zero")
        add(1, "one", "first", "firstly")
        add(2, "two", "second", "secondly")
        add(3, "three", "third", "thirdly")
        add(4, "four", "fourth")
        add(5, "five", "fifth")
        add(6, "six", "sixth")
        add(7, "seven")
        add(8, "eight")
        add(9, "nine")
        add(10, "ten")
        add(11, "eleven")
        add(12, "twelve")
        add(13, "thirteen")
        add(14, "fourteen")
        add(15, "fifteen")
        add(16, "sixteen")
        add(17, "seventeen")
        add(18, "eighteen")
        add(19, "nineteen")
        add(20, "twenty")
        add(30, "thirty")
        add(40, "forty")
        add(50, "fifty")
        add(60, "sixty")
        add(70, "seventy")
        add(80, "eighty")
        add(90, "ninety")
        add(100, "hundred")
        add(1000, "thousand")
        // Französisch, Spanisch, Italienisch, Portugiesisch, Niederländisch (Grundzahlen bis 10)
        add(
            1,
            "un",
            "une",
            "premier",
            "première",
            "uno",
            "una",
            "primero",
            "primera",
            "primo",
            "um",
            "uma",
            "één",
        )
        add(2, "deux", "deuxième", "dos", "segundo", "due", "dois", "duas", "twee")
        add(3, "trois", "troisième", "tres", "tercero", "tre", "terzo", "três", "drie")
        add(4, "quatre", "cuatro", "quattro", "quatro")
        add(5, "cinq", "cinco", "cinque", "vijf")
        add(7, "sept", "siete", "sette", "sete", "zeven")
        add(8, "huit", "ocho", "otto", "oito")
        add(9, "neuf", "nueve", "nove")
        add(10, "dix", "diez", "dieci", "dez", "tien")
    }

    fun numberValue(word: String): Long? =
        if (word.isNotEmpty() && word.all { it in '0'..'9' }) word.toLongOrNull()
        else numberWords[word]?.toLong()

    fun isQuantity(word: String): Boolean {
        val v = numberValue(word) ?: return false
        return v != 1L || word.all { it in '0'..'9' }
    }

    sealed interface NumberToken {
        data class Digits(val value: String) : NumberToken

        data class Word(val value: Int) : NumberToken
    }

    fun numberTokens(text: String): List<NumberToken> {
        val scalars = TextAnalysis.normalizedLower(text).scalars()
        val tokens = mutableListOf<NumberToken>()
        var i = 0
        fun isDigit(s: Int) = s in 48..57
        while (i < scalars.size) {
            if (isDigit(scalars[i])) {
                val digits = StringBuilder()
                while (i < scalars.size) {
                    if (isDigit(scalars[i])) {
                        digits.appendCodePoint(scalars[i++])
                        continue
                    }
                    var j = i
                    while (
                        j < scalars.size &&
                            !isDigit(scalars[j]) &&
                            !TextAnalysis.isLetter(scalars[j])
                    ) j++
                    if (j < scalars.size && isDigit(scalars[j])) i = j else break
                }
                tokens += NumberToken.Digits(digits.toString())
            } else if (TextAnalysis.isLetter(scalars[i])) {
                val word = StringBuilder()
                while (
                    i < scalars.size &&
                        (TextAnalysis.isLetter(scalars[i]) || TextAnalysis.isMark(scalars[i]))
                ) word.appendCodePoint(scalars[i++])
                numberWords[word.toString()]?.let { tokens += NumberToken.Word(it) }
            } else i++
        }
        return tokens
    }

    fun digitsPreserved(raw: String, result: String): Boolean {
        val rawTokens = numberTokens(raw)
        val available = numberTokens(result)
        val used = mutableSetOf<Int>()
        var position = 0
        for (token in rawTokens.filterIsInstance<NumberToken.Digits>()) {
            val match =
                (position until available.size).firstOrNull {
                    when (val a = available[it]) {
                        is NumberToken.Digits -> a.value == token.value
                        is NumberToken.Word -> token.value.toLongOrNull() == a.value.toLong()
                    }
                } ?: return false
            used += match
            position = match + 1
        }
        val rawWords =
            rawTokens.filterIsInstance<NumberToken.Word>().map { it.value }.toMutableList()
        for ((index, token) in available.withIndex()) if (
            index !in used && token is NumberToken.Digits
        ) {
            val value = token.value.toLongOrNull() ?: return false
            val index = rawWords.indexOfFirst { it.toLong() == value }
            if (index < 0) return false
            rawWords.removeAt(index)
        }
        return true
    }

    val correctionMarkers =
        listOf(
                "ich meine",
                "ich mein",
                "moment",
                "warte",
                "sorry",
                "sorri",
                "pardon",
                "entschuldigung",
                "i mean",
                "wait",
                "je veux dire",
                "attends",
                "quiero decir",
                "perdón",
                "espera",
                "o sea",
                "voglio dire",
                "scusa",
                "aspetta",
                "ik bedoel",
                "wacht",
                "quer dizer",
                "quero dizer",
                "znaczy",
                "czekaj",
                "przepraszam",
                "yani",
                "pardon",
            )
            .map { TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(it)) }

    fun resolvedSelfCorrection(raw: String): String? {
        val tokens = TextAnalysis.runs(raw, TextAnalysis::isWordScalar)
        val words = tokens.map { TextAnalysis.normalizedLower(it.word) }
        fun between(a: Int, b: Int) = raw.substring(tokens[a].end, tokens[b].start)
        fun has(gap: String, marks: String) =
            gap.characters().any { it.length == 1 && it[0] in marks }
        val cuts = mutableListOf<Pair<Int, Int>>()
        var i = 0
        while (i < words.size) {
            val marker = correctionMarkers.firstOrNull {
                i + it.size <= words.size && words.subList(i, i + it.size) == it
            }
            if (marker == null) {
                i++
                continue
            }
            var start = i
            if (start > 0 && words[start - 1] in Lexicon.answerNegators) start--
            val end = i + marker.size
            val preceded = start > 0 && has(between(start - 1, start), ",–—-…;")
            if (!preceded || end >= words.size) {
                i = end
                continue
            }
            var replacement = 1
            while (
                end + replacement < words.size &&
                    replacement < 6 &&
                    !has(between(end + replacement - 1, end + replacement), ",.;!?:–—…")
            ) replacement++
            var spanStart = start
            while (
                spanStart > 0 &&
                    start - spanStart < replacement &&
                    !has(between(spanStart - 1, spanStart), ".!?…")
            ) spanStart--
            if (spanStart >= start) {
                i = end
                continue
            }
            cuts += tokens[spanStart].start to tokens[end].start
            i = end + replacement
        }
        if (cuts.isEmpty()) return null
        var resolved = raw
        for ((start, end) in cuts.asReversed()) resolved = resolved.removeRange(start, end)
        return resolved
    }

    fun editDistance(a: String, b: String): Int {
        val x = a.scalars()
        val y = b.scalars()
        val d = Array(x.size + 1) { IntArray(y.size + 1) }
        for (i in 0..x.size) d[i][0] = i
        for (j in 0..y.size) d[0][j] = j
        for (i in 1..x.size) for (j in 1..y.size) {
            val cost = if (x[i - 1] == y[j - 1]) 0 else 1
            d[i][j] = minOf(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
            if (i > 1 && j > 1 && x[i - 1] == y[j - 2] && x[i - 2] == y[j - 1])
                d[i][j] = minOf(d[i][j], d[i - 2][j - 2] + 1)
        }
        return d[x.size][y.size]
    }

    fun isSmallCorrection(a: String, b: String) =
        editDistance(a, b) <= maxOf(1, minOf(a.scalarCount, b.scalarCount) / 4)

    val spellingVariants = listOf(setOf("ok", "okay", "okey", "oke", "okej", "okee"))

    fun areVariants(a: String, b: String) = spellingVariants.any { a in it && b in it }

    fun cleanedWords(words: List<String>): List<String> {
        val out = mutableListOf<String>()
        for (w in words) if (w !in Lexicon.fillers && out.lastOrNull() != w) out += w
        return out
    }

    fun substitutionRejection(raw: String, result: String, vocabulary: String): String? {
        if (
            TextAnalysis.containsScriptioContinua(raw) ||
                TextAnalysis.containsScriptioContinua(result)
        )
            return null
        val (r, h) =
            compoundAligned(
                cleanedWords(
                    TextAnalysis.alphanumericRuns(
                        expandContractions(TextAnalysis.normalizedLower(raw)),
                    ),
                ),
                TextAnalysis.alphanumericRuns(
                    expandContractions(TextAnalysis.normalizedLower(result)),
                ),
            )
        if (r.isEmpty() || h.isEmpty() || r.size.toLong() * h.size > 4_000_000) return null
        val custom = TextAnalysis.alphanumericRuns(TextAnalysis.normalizedLower(vocabulary)).toSet()
        val pairs = lcsPairs(r, h)
        val matchedRaw = pairs.map { it.first }.toSet()
        val movable = mutableMapOf<String, Int>()
        for ((i, word) in r.withIndex()) if (i !in matchedRaw)
            movable[word] = (movable[word] ?: 0) + 1
        fun numberEquivalent(a: String, b: String) =
            numberValue(a)?.let { it == numberValue(b) } == true
        fun compatible(a: String, b: String) =
            a == b || numberEquivalent(a, b) || areVariants(a, b) || isSmallCorrection(a, b)
        fun isContent(w: String) =
            TextAnalysis.weightedLength(w) >= 4 && w !in Lexicon.fillers && numberValue(w) == null
        var previous = -1 to -1
        for ((i, j) in pairs + (r.size to h.size)) {
            val rawStart = previous.first + 1
            val gapRaw = r.subList(rawStart, i)
            val gapResult = h.subList(previous.second + 1, j)
            previous = i to j
            if (gapResult.isEmpty() || gapRaw.joinToString("") == gapResult.joinToString(""))
                continue
            var pointer = 0
            for (b in gapResult) {
                val k = (pointer until gapRaw.size).firstOrNull { compatible(gapRaw[it], b) }
                if (k != null) {
                    val a = gapRaw[k]
                    val before = rawStart + k - 1
                    if (
                        a != b &&
                            !numberEquivalent(a, b) &&
                            !areVariants(a, b) &&
                            before >= 0 &&
                            isQuantity(r[before])
                    )
                        return "replaced"
                    pointer = k + 1
                    continue
                }
                val count = movable[b] ?: 0
                if (count > 0) {
                    movable[b] = count - 1
                    continue
                }
                if (b in custom) {
                    pointer = minOf(pointer + 1, gapRaw.size)
                    continue
                }
                if (!isContent(b)) continue
                return if (pointer < gapRaw.size) "replaced" else "inserted"
            }
        }
        return null
    }

    fun compoundAligned(raw: List<String>, result: List<String>): Pair<List<String>, List<String>> {
        fun merge(words: List<String>, other: Set<String>): List<String> {
            val out = mutableListOf<String>()
            var i = 0
            while (i < words.size) if (
                i + 1 < words.size &&
                    !(words[i] in other && words[i + 1] in other) &&
                    words[i] + words[i + 1] in other
            ) {
                out += words[i] + words[i + 1]
                i += 2
            } else out += words[i++]
            return out
        }
        val r = merge(raw, result.toSet())
        return r to merge(result, r.toSet())
    }

    private val contractions =
        listOf(
            Pattern("\\bcan['’]t\\b") to "can not",
            Pattern("\\bcannot\\b") to "can not",
            Pattern("\\bwon['’]t\\b") to "will not",
            Pattern("n['’]t\\b") to " not",
            Pattern("['’]re\\b") to " are",
            Pattern("['’]ve\\b") to " have",
            Pattern("['’]ll\\b") to " will",
            Pattern("\\bi['’]m\\b") to "i am",
        )

    fun expandContractions(text: String): String {
        if (!text.contains("'") && !text.contains("’") && !text.contains("cannot")) return text
        return contractions.fold(text) { out, (pattern, replacement) ->
            pattern.replacing(out, replacement)
        }
    }

    fun lcsPairs(a: List<String>, b: List<String>): List<Pair<Int, Int>> {
        val n = a.size
        val m = b.size
        val table = IntArray((n + 1) * (m + 1))
        fun at(i: Int, j: Int) = i * (m + 1) + j
        for (i in n - 1 downTo 0) for (j in m - 1 downTo 0) table[at(i, j)] =
            if (a[i] == b[j]) table[at(i + 1, j + 1)] + 1
            else maxOf(table[at(i + 1, j)], table[at(i, j + 1)])
        val pairs = mutableListOf<Pair<Int, Int>>()
        var i = 0
        var j = 0
        while (i < n && j < m) if (a[i] == b[j]) {
            pairs += i to j
            i++
            j++
        } else if (table[at(i + 1, j)] >= table[at(i, j + 1)]) i++ else j++
        return pairs
    }
}
