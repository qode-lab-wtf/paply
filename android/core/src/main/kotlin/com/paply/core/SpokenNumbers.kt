package com.paply.core

/** Spoken-number rules for the iOS-compatible thought safety profile. */
internal object SpokenNumbers {
    enum class Kind {
        digits,
        word,
        optional,
    }

    data class Token(val value: Long, val kind: Kind, val word: Int)

    data class Word(val text: String, val digits: Long?)

    fun preserved(raw: String, result: String): Boolean {
        val rawWords = words(raw)
        val rawTokens = tokens(rawWords)
        val resultTokens = tokens(words(result))
        val found = resultTokens.map { it.value }.toSet()
        val corrected = correctedWords(rawWords, rawTokens)
        if (
            rawTokens.any {
                it.kind != Kind.optional && it.value !in found && it.word !in corrected
            }
        )
            return false
        val source = rawTokens.map { it.value }.toSet()
        return resultTokens.all { it.kind != Kind.digits || it.value in source }
    }

    fun digitsContained(text: String, source: String): Boolean {
        val available = values(source)
        return tokens(text).all { it.kind != Kind.digits || it.value in available }
    }

    fun isNumberWord(word: String): Boolean {
        val lower = TextAnalysis.normalizedLower(word)
        if (lower in english || lower == "hundred" || lower == "thousand" || lower in enumerators)
            return true
        if (lower in articles || lower in months) return false
        return germanValue(lower) != null
    }

    fun tokens(text: String) = tokens(words(text))

    fun values(text: String) = tokens(text).map { it.value }.toSet()

    fun words(text: String): List<Word> {
        val chars = TextAnalysis.normalizedLower(text).codePoints().toArray()
        var i = 0
        val out = mutableListOf<Word>()
        val separators = ". ’'\u202f\u00a0".map { it.code }.toSet()
        fun digit(s: Int) = s in 48..57
        while (i < chars.size) {
            if (digit(chars[i])) {
                val digits = StringBuilder()
                while (i < chars.size && digit(chars[i])) {
                    digits.appendCodePoint(chars[i])
                    i++
                }
                while (i + 3 < chars.size && chars[i] in separators) {
                    var end = i + 1
                    while (end < chars.size && digit(chars[end])) end++
                    if (end - i - 1 != 3) break
                    (i + 1 until end).forEach { digits.appendCodePoint(chars[it]) }
                    i = end
                }
                val s = digits.toString()
                out.add(Word(s, if (s.length <= 12) s.toLongOrNull() else null))
            } else if (TextAnalysis.isLetter(chars[i])) {
                val word = StringBuilder()
                while (
                    i < chars.size &&
                        (TextAnalysis.isLetter(chars[i]) || TextAnalysis.isMark(chars[i]))
                ) {
                    word.appendCodePoint(chars[i])
                    i++
                }
                out.add(Word(word.toString(), null))
            } else i++
        }
        return out
    }

    fun tokens(words: List<Word>): List<Token> {
        val tokens = mutableListOf<Token>()
        var i = 0
        while (i < words.size) {
            val digits = words[i].digits
            if (digits != null) {
                tokens.add(Token(digits, Kind.digits, i))
                i++
                continue
            }
            val seq = englishSequence(words, i)
            if (seq != null) {
                val (value, used) = seq
                val single = if (used == 1) words[i].text else ""
                tokens.add(
                    Token(
                        value,
                        if (single in listOf("one", "first", "second")) Kind.optional
                        else Kind.word,
                        i,
                    ),
                )
                i += used
                continue
            }
            germanToken(words[i].text, i)?.let(tokens::add)
            i++
        }
        return tokens
    }

    val negators = setOf("nee", "nein", "ne", "nö", "no", "nope", "non")
    val afterNegator =
        setOf("warte", "moment", "quatsch", "falsch", "sorry", "stopp", "wait", "scratch")
    val standalone =
        listOf(
            listOf("ich", "meine"),
            listOf("ich", "mein"),
            listOf("i", "mean"),
            listOf("scratch", "that"),
            listOf("korrektur"),
        )

    fun correctedWords(words: List<Word>, tokens: List<Token>): Set<Int> {
        val texts = words.map { it.text }
        val result = mutableSetOf<Int>()
        var i = 0
        while (i < texts.size) {
            var end: Int? = null
            if (texts[i] in negators) {
                if (i + 1 < texts.size && texts[i + 1] in afterNegator) end = i + 2
                else if (tokens.any { it.word == i + 1 && it.kind != Kind.optional }) end = i + 1
            } else
                standalone
                    .firstOrNull {
                        i + it.size <= texts.size && texts.subList(i, i + it.size) == it
                    }
                    ?.let { end = i + it.size }
            val e = end
            if (e == null) {
                i++
                continue
            }
            val next = tokens.firstOrNull {
                it.word >= e && it.word <= e + 3 && it.kind != Kind.optional
            }
            val previous = tokens.lastOrNull {
                it.word < i && it.word >= i - 6 && it.kind != Kind.optional
            }
            if (next != null && previous != null) result.add(previous.word)
            i = e
        }
        return result
    }

    val english: Map<String, Long> = buildMap {
        listOf(
                "zero",
                "one",
                "two",
                "three",
                "four",
                "five",
                "six",
                "seven",
                "eight",
                "nine",
                "ten",
                "eleven",
                "twelve",
                "thirteen",
                "fourteen",
                "fifteen",
                "sixteen",
                "seventeen",
                "eighteen",
                "nineteen",
            )
            .forEachIndexed { i, w -> put(w, i.toLong()) }
        listOf(
                "",
                "first",
                "second",
                "third",
                "fourth",
                "fifth",
                "sixth",
                "seventh",
                "eighth",
                "ninth",
                "tenth",
                "eleventh",
                "twelfth",
                "thirteenth",
                "fourteenth",
                "fifteenth",
                "sixteenth",
                "seventeenth",
                "eighteenth",
                "nineteenth",
            )
            .forEachIndexed { i, w -> if (w.isNotEmpty()) put(w, i.toLong()) }
        listOf("twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety")
            .forEachIndexed { i, w ->
                put(w, (i + 2) * 10L)
                put(w.dropLast(1) + "ieth", (i + 2) * 10L)
            }
    }

    private enum class Place {
        none,
        unit,
        tens,
        hundred,
        thousand,
    }

    private fun englishSequence(words: List<Word>, start: Int): Pair<Long, Int>? {
        var total = 0L
        var current = 0L
        var last = Place.none
        var k = start
        scan@ while (k < words.size && words[k].digits == null) {
            val w = words[k].text
            val v = english[w]
            if (v != null) {
                when {
                    last == Place.none -> current = v
                    last == Place.tens && v in 1..9 -> current += v
                    last == Place.hundred || last == Place.thousand -> current += v
                    else -> break@scan
                }
                last = if (v >= 20 && v % 10 == 0L) Place.tens else Place.unit
            } else if (w == "hundred" && last in listOf(Place.none, Place.unit, Place.tens)) {
                current = maxOf(1, current) * 100
                last = Place.hundred
            } else if (w == "thousand" && last != Place.thousand) {
                total += maxOf(1, current) * 1000
                current = 0
                last = Place.thousand
            } else if (
                w == "and" &&
                    last in listOf(Place.hundred, Place.thousand) &&
                    k + 1 < words.size &&
                    words[k + 1].text in english
            ) {
                k++
                continue
            } else break
            k++
        }
        return if (last == Place.none) null else total + current to k - start
    }

    val units =
        mapOf(
            "eins" to 1L,
            "zwei" to 2L,
            "drei" to 3L,
            "vier" to 4L,
            "fünf" to 5L,
            "sechs" to 6L,
            "sieben" to 7L,
            "acht" to 8L,
            "neun" to 9L,
        )
    val teens =
        mapOf(
            "zehn" to 10L,
            "elf" to 11L,
            "zwölf" to 12L,
            "dreizehn" to 13L,
            "vierzehn" to 14L,
            "fünfzehn" to 15L,
            "sechzehn" to 16L,
            "siebzehn" to 17L,
            "achtzehn" to 18L,
            "neunzehn" to 19L,
        )
    val tens =
        mapOf(
            "zwanzig" to 20L,
            "dreißig" to 30L,
            "vierzig" to 40L,
            "fünfzig" to 50L,
            "sechzig" to 60L,
            "siebzig" to 70L,
            "achtzig" to 80L,
            "neunzig" to 90L,
        )
    val articles = setOf("ein", "eine", "einen", "einem", "einer", "eines", "a", "an")
    val enumerators =
        mapOf(
            "erstens" to 1L,
            "zweitens" to 2L,
            "drittens" to 3L,
            "viertens" to 4L,
            "fünftens" to 5L,
            "sechstens" to 6L,
            "siebtens" to 7L,
            "achtens" to 8L,
            "neuntens" to 9L,
            "zehntens" to 10L,
            "firstly" to 1L,
            "secondly" to 2L,
            "thirdly" to 3L,
        )
    val months: Map<String, Long> = buildMap {
        listOf(
                "januar",
                "februar",
                "märz",
                "april",
                "mai",
                "juni",
                "juli",
                "august",
                "september",
                "oktober",
                "november",
                "dezember",
            )
            .forEachIndexed { i, w -> put(w, i + 1L) }
        listOf(
                "january",
                "february",
                "march",
                "april",
                "may",
                "june",
                "july",
                "august",
                "september",
                "october",
                "november",
                "december",
            )
            .forEachIndexed { i, w -> put(w, i + 1L) }
        put("jänner", 1)
    }
    val ordinalStems = mapOf("erst" to 1L, "dritt" to 3L, "siebt" to 7L, "acht" to 8L)

    private fun germanToken(word: String, index: Int): Token? {
        if (word in articles) return Token(1, Kind.optional, index)
        (enumerators[word] ?: months[word])?.let {
            return Token(it, Kind.optional, index)
        }
        val value = germanValue(word) ?: return null
        return Token(
            value,
            if (value == 1L && word.startsWith("erst")) Kind.optional else Kind.word,
            index,
        )
    }

    fun germanValue(word: String): Long? {
        if (word.length < 3) return null
        cardinal(word)?.let {
            return it
        }
        if (word.endsWith("mal") && word.length > 5)
            cardinal(word.dropLast(3))?.let {
                return it
            }
        for (e in listOf("e", "en", "er", "es", "em")) for ((s, v) in ordinalStems) if (
            word == s + e
        )
            return v
        for (e in
            listOf("sten", "ster", "stes", "stem", "ste", "ten", "ter", "tes", "tem", "te")) if (
            word.endsWith(e)
        )
            cardinal(word.dropLast(e.length))
                ?.takeIf { it > 1 }
                ?.let {
                    return it
                }
        return null
    }

    private fun cardinal(word: String): Long? {
        if (word.isEmpty()) return null
        val index = word.indexOf("tausend")
        if (index >= 0) {
            val head = word.take(index)
            val tail = word.drop(index + 7)
            val high = if (head.isEmpty() || head == "ein") 1 else below1000(head) ?: return null
            val low = if (tail.isEmpty()) 0 else below1000(tail.removePrefix("und")) ?: return null
            return if (high > 0) high * 1000 + low else null
        }
        return below1000(word)
    }

    private fun below1000(word: String): Long? {
        val index = word.indexOf("hundert")
        if (index >= 0) {
            val head = word.take(index)
            val tail = word.drop(index + 7)
            val high = if (head.isEmpty() || head == "ein") 1 else below100(head) ?: return null
            val low = if (tail.isEmpty()) 0 else below100(tail.removePrefix("und")) ?: return null
            return if (high in 1..99) high * 100 + low else null
        }
        return below100(word)
    }

    private fun below100(word: String): Long? {
        (units[word] ?: teens[word] ?: tens[word])?.let {
            return it
        }
        val index = word.indexOf("und")
        if (index >= 0) {
            val unitWord = word.take(index)
            val unit = if (unitWord == "ein") 1 else units[unitWord] ?: return null
            val ten = tens[word.drop(index + 3)] ?: return null
            return ten + unit
        }
        return null
    }
}
