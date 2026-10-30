package com.paply.thoughts

import com.paply.thoughts.ai.SpokenTime
import com.paply.thoughts.processing.DueDate
import java.time.*
import java.time.temporal.ChronoUnit
import org.junit.Assert.*
import org.junit.Test

/** Source: the owned SpokenTime/DueDate subsection of iOS TaskAgendaTests; no Display port. */
class SpokenTimeTests {
    private val zone = ZoneId.systemDefault()
    private val now = LocalDate.of(2026, 10, 28).atTime(10, 0).atZone(zone).toInstant()

    private fun resolved(s: String) = DueDate.resolved(s, now, now, zone)

    @Test
    fun wordFormsAndDayPartsAreFixed() {
        run {
            val s = "um acht"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "um acht Uhr"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "gegen acht"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "um zwölf"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(12, 0), f.clock)
        }
        run {
            val s = "um ein Uhr"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(13, 0), f.clock)
        }
        run {
            val s = "um null Uhr"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(0, 0), f.clock)
        }
        run {
            val s = "Mitternacht"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(24, 0), f.clock)
        }
        run {
            val s = "um Mitternacht"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(24, 0), f.clock)
        }
        run {
            val s = "acht Uhr dreißig"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 30), f.clock)
        }
        run {
            val s = "um 8 Uhr dreißig"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 30), f.clock)
        }
        run {
            val s = "halb drei"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(14, 30), f.clock)
        }
        run {
            val s = "halb eins"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(12, 30), f.clock)
        }
        run {
            val s = "halb neun"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 30), f.clock)
        }
        run {
            val s = "um halb 3"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(14, 30), f.clock)
        }
        run {
            val s = "Viertel nach acht"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 15), f.clock)
        }
        run {
            val s = "Viertel vor neun"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 45), f.clock)
        }
        run {
            val s = "Viertel nach 8"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 15), f.clock)
        }
        run {
            val s = "dreiviertel neun"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 45), f.clock)
        }
        run {
            val s = "drei viertel neun"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 45), f.clock)
        }
        run {
            val s = "um zehn nach acht"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 10), f.clock)
        }
        run {
            val s = "um fünf vor zwölf"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(11, 55), f.clock)
        }
        run {
            val s = "um 10 nach 8"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 10), f.clock)
        }
        run {
            val s = "um zwölf Uhr mittags"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(12, 0), f.clock)
        }
        run {
            val s = "um 12 Uhr mittags"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(12, 0), f.clock)
        }
        run {
            val s = "um 2 Uhr mittags"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(14, 0), f.clock)
        }
        run {
            val s = "um 7 Uhr früh"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(7, 0), f.clock)
        }
        run {
            val s = "um 6 Uhr morgens"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(6, 0), f.clock)
        }
        run {
            val s = "halb acht abends"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(19, 30), f.clock)
        }
        run {
            val s = "morgen früh um halb acht"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(7, 30), f.clock)
        }
        run {
            val s = "abends um 8"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(20, 0), f.clock)
        }
        run {
            val s = "heute Abend um neun"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(21, 0), f.clock)
        }
        run {
            val s = "um 2 Uhr nachts"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(2, 0), f.clock)
        }
        run {
            val s = "um 11 Uhr nachts"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(23, 0), f.clock)
        }
        run {
            val s = "um 9 Uhr vormittags"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(9, 0), f.clock)
        }
        run {
            val s = "morgen Nachmittag um 3"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(15, 0), f.clock)
        }
        run {
            val s = "abends um 19:30"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(19, 30), f.clock)
        }
        run {
            val s = "morgen um halb eins morgens"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(0, 30), f.clock)
        }
        run {
            val s = "Viertel vor eins morgens"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(0, 45), f.clock)
        }
        run {
            val s = "um zwölf Uhr nachts"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(0, 0), f.clock)
        }
        run {
            val s = "halb eins nachts"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(0, 30), f.clock)
        }
        run {
            val s = "um 12 Uhr morgens"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, true, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(0, 0), f.clock)
        }
    }

    @Test
    fun digitsOnlyReadTheClockFace() {
        run {
            val s = "morgen um 07:00"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(7, 0), f.clock)
        }
        run {
            val s = "tomorrow at 06:00"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(6, 0), f.clock)
        }
        run {
            val s = "at 6 am tomorrow"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(6, 0), f.clock)
        }
        run {
            val s = "morgen um 12 Uhr"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(12, 0), f.clock)
        }
        run {
            val s = "um 0 Uhr"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(0, 0), f.clock)
        }
        run {
            val s = "um 24 Uhr"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(24, 0), f.clock)
        }
        run {
            val s = "um 8 Uhr 30"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 30), f.clock)
        }
        run {
            val s = "8:30"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 30), f.clock)
        }
        run {
            val s = "8.30 Uhr"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 30), f.clock)
        }
        run {
            val s = "um 8.30"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 30), f.clock)
        }
        run {
            val s = "15:45"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(15, 45), f.clock)
        }
        run {
            val s = "Freitag 10 Uhr"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(10, 0), f.clock)
        }
        run {
            val s = "um 3"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(3, 0), f.clock)
        }
        run {
            val s = "um 7"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(7, 0), f.clock)
        }
        run {
            val s = "gegen 8"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "um 8 am Freitag"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "at 8"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "8 pm"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "8pm"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "12 am"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(12, 0), f.clock)
        }
        run {
            val s = "8 a.m."
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "8 o'clock"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(8, 0), f.clock)
        }
        run {
            val s = "tomorrow at 7:30 pm"
            val f = SpokenTime.find(s)
            assertNotNull(s, f)
            assertEquals(s, false, f!!.fixed)
            assertEquals(s, SpokenTime.Clock(7, 30), f.clock)
        }
    }

    @Test
    fun noClockWithoutAnUnambiguousOne() {
        listOf(
                "morgen",
                "morgen früh",
                "abends",
                "morgen Mittag",
                "am 10.11.",
                "am 10.11.2026",
                "am achten",
                "in zwei Wochen",
                "on the 5th",
                "bis Ende November",
                "nächste Woche",
                "um den 10. herum",
                "Viertel acht",
                "zweimal",
                "next week",
                "at eight",
                "tomorrow at eight",
                "tomorrow at half past eight pm",
                "quarter past eight pm",
                "quarter to nine",
                "ten past eight",
                "at noon",
                "tomorrow at midnight",
                "um acht oder um neun",
                "morgen um 8 oder um 9",
                "morgen früh oder abends um acht",
            )
            .forEach { assertNull(it, SpokenTime.find(it)) }
    }

    @Test
    fun datesBesideTheClockStayAbsolute() {
        assertEquals(
            SpokenTime.Found(SpokenTime.Clock(9, 0), false, true),
            SpokenTime.find("am 10.11. um 9"),
        )
        assertEquals(false, SpokenTime.find("morgen um 15 Uhr")?.otherDigits)
        assertEquals(false, SpokenTime.find("morgen um halb 3")?.otherDigits)
    }

    @Test
    fun resolverSetsTheTime() {
        run {
            val s = "morgen um 07:00"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 7, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "tomorrow at 06:00"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 6, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "at 6 am tomorrow"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 6, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "tomorrow at 8"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 8, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "tomorrow 8 pm"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 20, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "8 pm"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                0L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 20, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "tomorrow at 7:30 pm"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 19, at.hour)
            assertEquals(s, 30, at.minute)
        }
        run {
            val s = "morgen um 3"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 15, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 12 Uhr"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 12, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 0 Uhr"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 0, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 24 Uhr"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                2L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 0, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 8:30"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 8, at.hour)
            assertEquals(s, 30, at.minute)
        }
        run {
            val s = "übermorgen um 10 Uhr"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                2L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 10, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 8 Uhr 30"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 8, at.hour)
            assertEquals(s, 30, at.minute)
        }
        run {
            val s = "morgen um acht"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 8, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um acht Uhr"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 8, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um halb drei"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 14, at.hour)
            assertEquals(s, 30, at.minute)
        }
        run {
            val s = "morgen um halb 3"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 14, at.hour)
            assertEquals(s, 30, at.minute)
        }
        run {
            val s = "morgen um Viertel nach acht"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 8, at.hour)
            assertEquals(s, 15, at.minute)
        }
        run {
            val s = "morgen um Mitternacht"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                2L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 0, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um zwölf Uhr mittags"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 12, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen halb acht abends"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 19, at.hour)
            assertEquals(s, 30, at.minute)
        }
        run {
            val s = "morgen gegen acht"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 8, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um halb eins morgens"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 0, at.hour)
            assertEquals(s, 30, at.minute)
        }
        run {
            val s = "morgen um Viertel vor eins morgens"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 0, at.hour)
            assertEquals(s, 45, at.minute)
        }
        run {
            val s = "morgen um 7 Uhr früh"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 7, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 6 Uhr morgens"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 6, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen abend um 8"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 20, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 2 Uhr nachts"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 2, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 11 Uhr nachts"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 23, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen um 10 Uhr"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, true, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 10, at.hour)
            assertEquals(s, 0, at.minute)
        }
    }

    @Test
    fun resolverWithoutTime() {
        run {
            val s = "morgen"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 12, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen früh"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 9, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen Mittag"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 12, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "tomorrow"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 12, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "tomorrow at half past eight pm"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 12, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "quarter past eight pm"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                0L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 20, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "tomorrow at eight"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 12, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "tomorrow at midnight"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                2L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 0, at.hour)
            assertEquals(s, 0, at.minute)
        }
        run {
            val s = "morgen gegen 8"
            val due = resolved(s)
            assertNotNull(s, due)
            assertEquals(s, false, due!!.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(
                s,
                1L,
                ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), at.toLocalDate()),
            )
            assertEquals(s, 12, at.hour)
            assertEquals(s, 0, at.minute)
        }
    }

    @Test
    fun noDateWithoutDay() {
        listOf("at 8", "um acht", "halb drei", "um Mitternacht").forEach {
            assertNull(it, resolved(it))
        }
    }

    @Test
    fun germanAmIsNotMorning() {
        listOf("um 8 am Freitag", "bis um 8 am Freitag", "um 8.30 am Freitag").forEach {
            val due = resolved(it)!!
            assertTrue(due.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(DayOfWeek.FRIDAY, at.dayOfWeek)
            assertEquals(8, at.hour)
        }
        assertEquals("at 6 am tomorrow", DueDate.germanAm("at 6 am tomorrow"))
    }

    @Test
    fun bareTimesTheDetectorReads() {
        listOf("um 7 Uhr früh" to 7, "um 6 Uhr morgens" to 6, "8 pm" to 20).forEach { (s, h) ->
            val due = resolved(s)!!
            assertTrue(due.hasTime)
            val at = due.date.atZone(zone)
            assertEquals(now.atZone(zone).toLocalDate(), at.toLocalDate())
            assertEquals(h, at.hour)
            assertEquals(0, at.minute)
        }
    }

    @Test
    fun hasTimeAndOlderTasksAgree() {
        listOf(
                "morgen um 07:00",
                "tomorrow at 06:00",
                "at 6 am tomorrow",
                "tomorrow at half past eight pm",
                "quarter past eight pm",
                "morgen um halb eins morgens",
                "morgen um Viertel vor eins morgens",
                "morgen um acht",
                "morgen halb drei",
                "morgen um Mitternacht",
                "morgen um zwölf Uhr mittags",
                "morgen um 7 Uhr früh",
                "morgen um 6 Uhr morgens",
                "morgen halb acht abends",
                "tomorrow at 8",
                "8 pm",
                "morgen gegen 8",
                "morgen abend um 8",
                "morgen",
                "morgen früh",
                "tomorrow at eight",
                "10. November um 9",
                "bis Freitag 10 Uhr",
            )
            .forEach { s ->
                val due = resolved(s)!!
                val clock = DueDate.spokenClock(s)
                assertEquals(s, due.hasTime, clock != null)
                if (clock != null) assertTrue(s, SpokenTime.matches(clock, due.date, zone))
            }
    }

    @Test
    fun savedRunsKeepTheirTimes() {
        val hints =
            listOf(
                "Donnerstag",
                "am Samstag",
                "am zehnten",
                "before November third",
                "before Thursday",
                "bis Ende November",
                "bis Mittwoch",
                "bis Sonntag",
                "bis spätestens Freitag",
                "bis zum fünfundzwanzigsten",
                "diese Woche",
                "für den Sonntag danach",
                "im Dezember",
                "morgen",
                "morgen am besten vormittags",
                "morgen früh",
                "morgen um 10 Uhr",
                "morgen um acht",
            )
        assertEquals(
            listOf("morgen um 10 Uhr", "morgen um acht"),
            hints.filter { resolved(it)?.hasTime == true },
        )
    }

    @Test
    fun relativeDayWithTimeFollowsTheRecording() {
        val recorded = now.minusSeconds(2 * 86400)
        listOf("morgen um 15 Uhr" to 15, "morgen um halb drei" to 14).forEach { (s, h) ->
            val due = DueDate.resolved(s, recorded, now, zone)!!
            val at = due.date.atZone(zone)
            assertEquals(recorded.atZone(zone).toLocalDate().plusDays(1), at.toLocalDate())
            assertEquals(h, at.hour)
            assertTrue(due.hasTime)
        }
    }
}
