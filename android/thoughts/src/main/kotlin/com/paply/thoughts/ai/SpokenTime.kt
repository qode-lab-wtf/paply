package com.paply.thoughts.ai

import java.time.*
import java.util.Locale

/** Exact German spoken clock rules from iOS. A Found with fixed=false is only a clock face. */
object SpokenTime {
    data class Clock(val hour: Int, val minute: Int)

    data class Found(val clock: Clock, val fixed: Boolean, val otherDigits: Boolean)

    data class Token(val text: String, val digits: Boolean, val gap: String)

    data class Number(val value: Int, val word: Boolean)

    data class Match(
        val hour: Int,
        val minute: Int,
        val used: IntRange,
        val words: Boolean,
        val twelveHour: Boolean = false,
    )

    enum class DayPart {
        early,
        forenoon,
        noon,
        evening,
        night,
    }

    val leadIns = setOf("um", "gegen", "at", "around")
    val dayParts =
        mapOf(
            "früh" to DayPart.early,
            "morgens" to DayPart.early,
            "vormittag" to DayPart.forenoon,
            "vormittags" to DayPart.forenoon,
            "mittag" to DayPart.noon,
            "mittags" to DayPart.noon,
            "nachmittag" to DayPart.evening,
            "nachmittags" to DayPart.evening,
            "abend" to DayPart.evening,
            "abends" to DayPart.evening,
            "nacht" to DayPart.night,
            "nachts" to DayPart.night,
        )
    val germanCardinals =
        buildMap<String, Int> {
            put("null", 0)
            put("eins", 1)
            val units =
                listOf("", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun")
            (2..9).forEach { put(units[it], it) }
            listOf(
                    "zehn",
                    "elf",
                    "zwölf",
                    "dreizehn",
                    "vierzehn",
                    "fünfzehn",
                    "sechzehn",
                    "siebzehn",
                    "achtzehn",
                    "neunzehn",
                )
                .forEachIndexed { i, w -> put(w, 10 + i) }
            listOf(
                    20 to "zwanzig",
                    30 to "dreißig",
                    30 to "dreissig",
                    40 to "vierzig",
                    50 to "fünfzig",
                )
                .forEach { (n, w) ->
                    put(w, n)
                    (1..9).forEach { put(units[it] + "und" + w, n + it) }
                }
        }

    fun tokenize(text: String): List<Token> {
        val tokens = mutableListOf<Token>()
        var current = ""
        var digits = false
        var gap = ""
        fun flush() {
            if (current.isNotEmpty()) {
                tokens.add(Token(current, digits, gap))
                current = ""
                gap = ""
            }
        }
        val s = text.lowercase(Locale.ROOT)
        s.forEachIndexed { i, c ->
            val apostrophe =
                (c == '\'' || c == '’') &&
                    current.isNotEmpty() &&
                    !digits &&
                    s.getOrNull(i + 1)?.isLetter() == true
            when {
                c in '0'..'9' -> {
                    if (current.isNotEmpty() && !digits) flush()
                    digits = true
                    current += c
                }
                c.isLetter() || apostrophe -> {
                    if (current.isNotEmpty() && digits) flush()
                    digits = false
                    current += if (apostrophe) '\'' else c
                }
                else -> {
                    flush()
                    gap += c
                }
            }
        }
        flush()
        return tokens
    }

    fun number(index: Int, tokens: List<Token>): Number? {
        val t = tokens.getOrNull(index) ?: return null
        if (t.digits) {
            if (t.text.length > 2) return null
            val next = tokens.getOrNull(index + 1)
            if (next?.gap == "" && next.text in listOf("st", "nd", "rd", "th")) return null
            return t.text.toIntOrNull()?.let { Number(it, false) }
        }
        return germanCardinals[t.text]?.let { Number(it, true) }
    }

    fun find(text: String): Found? {
        val tokens = tokenize(text)
        val matches = mutableListOf<Match>()
        var i = 0
        while (i < tokens.size) {
            val m = clock(i, tokens)
            if (m == null) i++
            else {
                matches.add(m)
                i = m.used.last + 1
            }
        }
        val m = matches.singleOrNull() ?: return null
        val parts = tokens.mapNotNull { dayParts[it.text] }.toSet()
        if (parts.size > 1) return null
        val part = parts.firstOrNull()
        val fixed = m.words || part != null
        return Found(
            if (fixed) fixedClock(m, part) else Clock(m.hour, m.minute),
            fixed,
            tokens.indices.any { tokens[it].digits && it !in m.used },
        )
    }

    fun matches(clock: Clock, date: Instant, calendar: ZoneId = ZoneId.systemDefault()): Boolean {
        val d = date.atZone(calendar)
        return d.hour == clock.hour % 24 && d.minute == clock.minute
    }

    fun clock(start: Int, tokens: List<Token>): Match? {
        fun w(i: Int) = tokens.getOrNull(i)?.text
        fun n(i: Int) = number(i, tokens)
        fun lead() = w(start - 1) in leadIns
        val first = w(start)
        when (first) {
            "mitternacht" -> return Match(24, 0, start..start, true)
            "halb",
            "dreiviertel" -> {
                val h = n(start + 1) ?: return null
                if (h.value !in 1..12) return null
                return Match(
                    h.value - 1,
                    if (first == "halb") 30 else 45,
                    start..start + 1,
                    true,
                    true,
                )
            }
            "viertel" -> {
                val dir = w(start + 1)
                val h = n(start + 2) ?: return null
                if (dir !in listOf("nach", "vor") || h.value !in 1..12) return null
                return Match(
                    if (dir == "nach") h.value else h.value - 1,
                    if (dir == "nach") 15 else 45,
                    start..start + 2,
                    true,
                    true,
                )
            }
            "ein" ->
                if (w(start + 1) == "uhr")
                    return withMinutes(Match(1, 0, start..start + 1, true), tokens)
        }
        if (first == "drei" && w(start + 1) == "viertel") {
            val h = n(start + 2)
            if (h != null && h.value in 1..12)
                return Match(h.value - 1, 45, start..start + 2, true, true)
        }
        val spoken = n(start) ?: return null
        val v = spoken.value
        val next = start + 1
        val nt = tokens.getOrNull(next)
        if (
            !spoken.word &&
                nt?.digits == true &&
                nt.text.length == 2 &&
                nt.text.toIntOrNull() in 0..59 &&
                v in 0..24
        ) {
            val after = w(next + 1)
            val dateLike =
                tokens.getOrNull(next + 1)?.let { it.digits && it.gap.startsWith('.') } == true
            if (nt.gap == ":" || (nt.gap == "." && (after == "uhr" || lead()) && !dateLike))
                return Match(
                    v,
                    nt.text.toInt(),
                    start..(if (after == "uhr") next + 1 else next),
                    false,
                )
        }
        if (w(next) == "uhr" && v in 0..24)
            return withMinutes(Match(v, 0, start..next, spoken.word), tokens)
        if (v in 1..29 && w(next) in listOf("nach", "vor") && lead()) {
            val h = n(next + 1)
            if (h != null && h.value in 1..12) {
                val after = w(next) == "nach"
                return Match(
                    if (after) h.value else h.value - 1,
                    if (after) v else 60 - v,
                    start..next + 1,
                    true,
                    true,
                )
            }
        }
        if (!spoken.word && v in 0..12)
            englishSuffix(next, tokens)?.let {
                return Match(v, 0, start until next + it, false)
            }
        if (lead() && v in 0..24)
            return withMinutes(Match(v, 0, start until next, spoken.word), tokens)
        return null
    }

    private fun withMinutes(m: Match, tokens: List<Token>): Match {
        val i = m.used.last + 1
        val n = number(i, tokens) ?: return m
        if (tokens[i].gap != " " || n.value !in 0..59) return m
        return m.copy(minute = n.value, used = m.used.first..i, words = m.words || n.word)
    }

    private fun englishSuffix(i: Int, t: List<Token>): Int? {
        val s = t.getOrNull(i) ?: return null
        if (s.text in listOf("pm", "o'clock", "oclock")) return 1
        if (s.text == "am" && (s.gap.isEmpty() || i + 1 == t.size)) return 1
        if (s.text in listOf("a", "p") && t.getOrNull(i + 1)?.text == "m" && t[i + 1].gap == ".")
            return 2
        return null
    }

    fun fixedClock(m: Match, part: DayPart?): Clock {
        if (m.hour == 24) return Clock(24, 0)
        var h = if (m.twelveHour && m.hour == 0) 12 else m.hour
        if (h in 1..12)
            when (part) {
                DayPart.early -> if (h == 12) h = 0
                DayPart.forenoon -> Unit
                DayPart.noon -> if (h <= 5) h += 12
                DayPart.evening -> if (h < 12) h += 12
                DayPart.night -> if (h == 12) h = 0 else if (h >= 9) h += 12
                null -> if (h <= 7) h += 12
            }
        return Clock(h, m.minute)
    }
}
