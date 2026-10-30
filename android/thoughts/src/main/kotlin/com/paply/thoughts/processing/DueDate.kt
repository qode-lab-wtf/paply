package com.paply.thoughts.processing

import com.paply.thoughts.ai.SpokenTime
import java.time.*
import java.time.temporal.TemporalAdjusters
import java.util.Locale

/**
 * Conservative de/en replacement for NSDataDetector. Unsupported/ambiguous phrases retain dueHint
 * only.
 */
object DueDate {
    data class Resolved(val date: Instant, val hasTime: Boolean)

    private val leading =
        listOf("bis zum", "bis", "am", "ab", "spätestens", "by", "until", "on", "before")
    private val weekdays =
        listOf("montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonntag")
    private val englishDays =
        listOf("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
    private val months =
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
    private val englishMonths =
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

    fun germanAm(text: String) =
        text.replace(Regex("(?i)\\b(um\\s+\\d{1,2}(?:[:.]\\d{2})?)\\s+am\\b"), "$1 Uhr am")

    fun clock(
        spoken: SpokenTime.Found?,
        detected: Instant,
        calendar: ZoneId = ZoneId.systemDefault(),
    ): SpokenTime.Clock? {
        if (spoken == null) return null
        if (spoken.fixed) return spoken.clock
        val d = detected.atZone(calendar)
        return if (d.hour % 12 == spoken.clock.hour % 12 && d.minute == spoken.clock.minute)
            SpokenTime.Clock(d.hour, d.minute)
        else null
    }

    fun spokenClock(hint: String?): SpokenTime.Clock? {
        val now = Instant.now()
        val due = resolved(hint, now, now) ?: return null
        if (!due.hasTime) return null
        val date = due.date.atZone(ZoneId.systemDefault())
        return SpokenTime.Clock(date.hour, date.minute)
    }

    private fun clockFace(text: String, s: SpokenTime.Found): SpokenTime.Clock? {
        if (s.fixed) return s.clock
        if (Regex("(?i)\\bgegen\\s+\\d").containsMatchIn(text)) return null
        var h = s.clock.hour
        val lower = text.lowercase(Locale.ROOT)
        if (Regex("(?<!\\p{L})p\\.?m\\.?(?:\\b|$)").containsMatchIn(lower)) {
            if (h < 12) h += 12
        } else if (Regex("(?:\\ba\\.m\\.?|\\d\\s*am(?:$|\\s+tomorrow))").containsMatchIn(lower)) {
            if (h == 12) h = 0
        }
        // Unqualified numeric 1..7 follows the iOS detector's afternoon convention, except
        // zero-padded clocks.
        else if (h in 1..7 && !Regex("\\b0[1-7](?:[:.]|\\s*uhr)").containsMatchIn(lower)) h += 12
        return SpokenTime.Clock(h, s.clock.minute).takeIf {
            it.hour in 0..24 && it.minute in 0..59 && (it.hour != 24 || it.minute == 0)
        }
    }

    fun resolve(
        hint: String?,
        reference: Instant,
        now: Instant,
        calendar: ZoneId = ZoneId.systemDefault(),
    ) = resolved(hint, reference, now, calendar)?.date

    fun resolved(
        hint: String?,
        reference: Instant,
        now: Instant,
        calendar: ZoneId = ZoneId.systemDefault(),
    ): Resolved? {
        var text = hint?.trim()?.lowercase(Locale.ROOT)?.takeIf { it.isNotEmpty() } ?: return null
        leading.firstOrNull { text.startsWith("$it ") }?.let { text = text.drop(it.length + 1) }
        text = germanAm(text)
        val spoken = SpokenTime.find(text)
        val time = spoken?.let { clockFace(text, it) }
        val ref = reference.atZone(calendar).toLocalDate()
        var day: LocalDate? = null
        fun has(word: String) =
            Regex("(?<!\\p{L})${Regex.escape(word)}(?!\\p{L})").containsMatchIn(text)
        val relative =
            listOf(
                "übermorgen" to 2L,
                "day after tomorrow" to 2L,
                "morgen" to 1L,
                "tomorrow" to 1L,
                "heute" to 0L,
                "today" to 0L,
                "gestern" to -1L,
                "yesterday" to -1L,
            )
        relative.firstOrNull { has(it.first) }?.let { day = ref.plusDays(it.second) }
        val named = weekdays.indices.filter { has(weekdays[it]) || has(englishDays[it]) }
        if (named.size > 1) return null
        if (day == null && named.size == 1) {
            val target = DayOfWeek.of(named[0] + 1)
            day = ref.with(TemporalAdjusters.nextOrSame(target))
            if ((has("nächsten") || has("next")) && day == ref) day = ref.plusDays(7)
        }
        val numeric = Regex("(?<!\\d)(\\d{1,2})\\.(\\d{1,2})\\.(?:(\\d{4}))?(?!\\d)").find(text)
        if (numeric != null) {
            val (d, m, y) = numeric.destructured
            day =
                runCatching { LocalDate.of(y.toIntOrNull() ?: ref.year, m.toInt(), d.toInt()) }
                    .getOrNull() ?: return null
        }
        if (day == null) {
            val namedMonth =
                Regex("\\b(\\d{1,2})\\.?\\s+([\\p{L}]+)(?:\\s+(\\d{4}))?\\b").find(text)
            if (namedMonth != null) {
                val (d, m, y) = namedMonth.destructured
                val month = months.indexOf(m).takeIf { it >= 0 } ?: englishMonths.indexOf(m)
                if (month >= 0)
                    day =
                        runCatching {
                            LocalDate.of(y.toIntOrNull() ?: ref.year, month + 1, d.toInt())
                        }
                            .getOrNull()
            }
        }
        if (day == null) {
            val relativeAmount =
                Regex(
                        "\\bin\\s+(\\d+|ein(?:em|er|e)?|zwei|drei|one|two|three)\\s+(tag(?:en|e)?|woche[n]?|day[s]?|week[s]?)\\b",
                    )
                    .find(text)
            if (relativeAmount != null) {
                val n =
                    relativeAmount.groupValues[1].toLongOrNull()
                        ?: when (relativeAmount.groupValues[1]) {
                            "zwei",
                            "two" -> 2
                            "drei",
                            "three" -> 3
                            else -> 1
                        }
                val multiplier =
                    if (
                        relativeAmount.groupValues[2].startsWith("woch") ||
                            relativeAmount.groupValues[2].startsWith("week")
                    )
                        7L
                    else 1L
                day =
                    runCatching { ref.plusDays(Math.multiplyExact(n, multiplier)) }.getOrNull()
                        ?: return null
            }
        }
        if (day == null && (has("nächste woche") || has("next week"))) day = ref.plusWeeks(1)
        // NSDataDetector recognises a bare numeric clock only with Uhr/colon/am/pm, not "at 8" or
        // German word clocks.
        val bareSignal =
            Regex("\\b\\d{1,2}(?:[:.]\\d{2}|\\s*(?:uhr|a\\.?m|p\\.?m))").containsMatchIn(text)
        if (day == null && time != null && spoken.otherDigits == false && bareSignal) day = ref
        // These English forms have a detector date but no unambiguous SpokenTime clock.
        val englishMidnight = has("midnight")
        val englishHours =
            listOf(
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
            )
        val englishWordPM =
            Regex(
                    "\\b(?:quarter past|quarter to|half past) (${englishHours.joinToString("|")}) pm\\b",
                )
                .find(text)
                ?.groupValues
                ?.get(1)
                ?.let { (englishHours.indexOf(it) + 1) % 12 + 12 }
        // Preserve the detector's first match: a preceding day wins; otherwise the named hour
        // supplies a sorting date, but no precise clock (hasTime stays false).
        val standaloneEnglishHour = englishWordPM.takeIf { day == null }
        if (day == null && englishWordPM != null) day = ref
        val date = day ?: return null
        val hour =
            time?.hour
                ?: if (englishMidnight) 24
                else if (standaloneEnglishHour != null) standaloneEnglishHour
                else if (has("früh") || has("morning")) 9 else 12
        val local =
            if (hour == 24) date.plusDays(1).atStartOfDay()
            else date.atTime(hour, time?.minute ?: 0)
        // Refuse a daylight-saving gap instead of silently moving an explicitly spoken clock.
        if (calendar.rules.getValidOffsets(local).isEmpty()) return null
        val instant = local.atZone(calendar).toInstant()
        if (
            instant <= reference.minusSeconds(86400) ||
                instant >= reference.plusSeconds(2 * 365 * 86400)
        )
            return null
        return Resolved(instant, time != null)
    }
}
