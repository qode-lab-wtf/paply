package com.paply.thoughts

import com.paply.thoughts.map.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class MapInboxTests {
    private fun at(s: Double) = Instant.ofEpochSecond(1790000000).addSeconds(s)

    private fun same(a: Instant?, b: Instant) {
        assertNotNull(a)
        assertEquals(0.0, secondsBetween(a!!, b), 1e-4)
    }

    private fun MapLandings.observe(ids: Set<String>, s: Double) =
        observe(ids, ids + pending + awaiting.keys + flights.map { it.id }, at(s))

    @Test
    fun status() {
        assertNull(MapInboxStatus.of(emptyList()))
        assertNull(MapInboxStatus.of(listOf(ThoughtState.done, ThoughtState.empty)))
        assertEquals(
            MapInboxStatus.ordering,
            MapInboxStatus.of(listOf(ThoughtState.waitingNetwork, ThoughtState.structuring)),
        )
        assertEquals(
            MapInboxStatus.key,
            MapInboxStatus.of(listOf(ThoughtState.waitingNetwork, ThoughtState.waitingKey)),
        )
        assertEquals(
            MapInboxStatus.attention,
            MapInboxStatus.of(
                listOf(
                    ThoughtState.waitingLimit,
                    ThoughtState.needsAttention,
                    ThoughtState.waitingNetwork,
                ),
            ),
        )
        assertEquals(
            MapInboxStatus.limit,
            MapInboxStatus.of(listOf(ThoughtState.waitingBudget, ThoughtState.waitingLimit)),
        )
        assertEquals(MapInboxStatus.budget, MapInboxStatus.of(listOf(ThoughtState.waitingBudget)))
        assertTrue(
            MapInboxStatus.isPending(ThoughtState.transcribed) &&
                MapInboxStatus.isPending(ThoughtState.needsAttention),
        )
        assertFalse(
            MapInboxStatus.isPending(ThoughtState.done) ||
                MapInboxStatus.isPending(ThoughtState.empty),
        )
    }

    @Test
    fun firstObservationOnlyRemembers() {
        val l = MapLandings()
        l.observe(setOf("a"), 0.0)
        assertEquals(1, l.count(at(0.0)))
        assertTrue(l.place(true, at(0.0)) { "t" }.isEmpty())
    }

    @Test
    fun landsAfterLayout() {
        val l = MapLandings()
        l.observe(setOf("a"), 0.0)
        l.observe(emptySet(), 1.0)
        assertEquals(at(1.0), l.awaiting["a"])
        assertEquals(1, l.count(at(1.0)))
        assertTrue(l.place(true, at(1.1)) { null }.isEmpty())
        val flights = l.place(true, at(1.2)) { if (it == "a") "t1" else null }
        assertEquals(1, flights.size)
        assertEquals("t1", flights[0].topicID)
        same(flights[0].launch, at(1.2))
        assertEquals(0, l.count(at(1.2)))
        assertEquals(listOf("a"), l.unlanded(at(1.5)).map { it.id })
        assertTrue(l.unlanded(at(1.2 + MapLandings.duration + .001)).isEmpty())
        assertTrue(l.isRunning(at(1.2 + MapLandings.duration + .5)))
        assertFalse(l.isRunning(at(1.2 + MapLandings.duration + MapLandings.glow + .001)))
        assertEquals(.5, flights[0].progress(at(1.2 + MapLandings.duration / 2))!!, 1e-4)
        assertNull(flights[0].progress(at(1.1)))
    }

    @Test
    fun severalFlyOneAfterAnother() {
        val l = MapLandings()
        l.observe(setOf("a", "b", "c"), 0.0)
        l.observe(setOf("a"), 1.0)
        l.observe(emptySet(), 1.5)
        assertEquals(3, l.count(at(1.5)))
        val flights = l.place(true, at(2.0)) { "t" }
        assertEquals(listOf("b", "c", "a"), flights.map { it.id })
        val step = MapLandings.stagger
        flights.forEachIndexed { i, f -> same(f.launch, at(2 + i * step)) }
        assertEquals(2, l.count(at(2.001)))
        assertEquals(1, l.count(at(2.001 + step)))
        assertEquals(0, l.count(at(2.001 + 2 * step)))
        assertEquals(2, l.launched(at(2.001 + step)))
        l.observe(setOf("d"), 2.1)
        l.observe(emptySet(), 2.2)
        val late = l.place(true, at(2.2)) { "u" }
        assertEquals(1, late.size)
        same(late[0].launch, at(2 + 3 * step))
        same(l.nextEvent(at(2.2)), at(2 + step))
    }

    @Test
    fun manyAtOnce() {
        val l = MapLandings()
        l.observe((0 until 30).map { "g$it" }.toSet(), 0.0)
        l.observe(emptySet(), 1.0)
        val flights = l.place(true, at(1.0)) { "t" }
        assertEquals(MapLandings.maxFlights, flights.size)
        assertTrue(secondsBetween(at(1.0), flights.maxOf { it.launch }) <= MapLandings.spread)
        assertTrue(l.awaiting.isEmpty())
        assertEquals(MapLandings.maxFlights - 1, l.count(at(1.0)))
    }

    @Test
    fun withoutMotion() {
        val l = MapLandings()
        l.observe(setOf("a", "b"), 0.0)
        l.observe(emptySet(), 1.0)
        assertTrue(l.place(false, at(1.0)) { "t" }.isEmpty())
        assertEquals(0, l.count(at(1.0)))
        assertTrue(l.flights.isEmpty())
    }

    @Test
    fun patience() {
        val l = MapLandings()
        l.observe(setOf("a"), 0.0)
        l.observe(emptySet(), 1.0)
        assertEquals(1, l.count(at(2.0)))
        assertTrue(l.nextEvent(at(2.0))!! > at(1 + MapLandings.patience))
        l.observe(emptySet(), 1 + MapLandings.patience + .1)
        assertEquals(0, l.count(at(1 + MapLandings.patience + .1)))
        assertNull(l.nextEvent(at(20.0)))
    }

    @Test
    fun backToWork() {
        val l = MapLandings()
        l.observe(setOf("a", "b"), 0.0)
        l.observe(emptySet(), 1.0)
        l.place(true, at(1.0)) { if (it == "a") "t" else null }
        l.observe(setOf("a", "b"), 1.1)
        assertTrue(l.awaiting.isEmpty() && l.flights.isEmpty())
        assertEquals(2, l.count(at(1.1)))
    }

    @Test
    fun deletedWhilePending() {
        val l = MapLandings()
        l.observe(setOf("a", "b"), 0.0)
        l.observe(setOf("b"), setOf("b"), at(1.0))
        assertTrue(l.awaiting.isEmpty())
        assertEquals(1, l.count(at(1.0)))
        l.observe(emptySet(), emptySet(), at(2.0))
        assertEquals(0, l.count(at(2.0)))
        assertNull(l.nextEvent(at(2.0)))
    }

    @Test
    fun deletedWhileAwaiting() {
        val l = MapLandings()
        l.observe(setOf("a", "b"), 0.0)
        l.observe(emptySet(), 1.0)
        assertEquals(2, l.count(at(1.0)))
        l.observe(emptySet(), setOf("b"), at(1.5))
        assertEquals(setOf("b"), l.awaiting.keys)
        assertEquals(1, l.count(at(1.5)))
        assertEquals(listOf("b"), l.place(true, at(1.6)) { "t" }.map { it.id })
    }

    @Test
    fun deletedInFlight() {
        val l = MapLandings()
        l.observe(setOf("a", "b"), 0.0)
        l.observe(emptySet(), 1.0)
        assertEquals(listOf("a", "b"), l.place(true, at(1.0)) { "t" }.map { it.id })
        l.observe(emptySet(), emptySet(), at(1.2))
        assertTrue(l.flights.isEmpty() && l.unlanded(at(1.2)).isEmpty())
        assertEquals(0, l.count(at(1.2)))
        assertFalse(l.isRunning(at(1.2)))
        assertNull(l.nextEvent(at(1.2)))
    }

    @Test
    fun deletedInFlightKeepsOthers() {
        val l = MapLandings()
        l.observe(setOf("a", "b"), 0.0)
        l.observe(emptySet(), 1.0)
        val flights = l.place(true, at(1.0)) { "t" }
        l.observe(emptySet(), setOf("b"), at(1.1))
        assertEquals(listOf("b"), l.flights.map { it.id })
        same(l.flights.first().launch, flights[1].launch)
        assertEquals(1, l.count(at(1.1)))
    }
}
