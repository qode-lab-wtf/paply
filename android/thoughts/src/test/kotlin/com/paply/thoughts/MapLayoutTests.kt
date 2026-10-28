package com.paply.thoughts

import com.paply.thoughts.map.*
import java.nio.file.Files
import java.time.Instant
import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class MapLayoutTests {
    private val config = MapLayoutConfig()
    private val base = Instant.ofEpochSecond(1790000000)

    private class LCG(var state: ULong) {
        fun next(): ULong {
            state = state * 6364136223846793005uL + 1442695040888963407uL
            return state shr 33
        }

        fun int(range: IntRange) = range.first + (next() % range.count().toULong()).toInt()
    }

    private fun id(i: Int, prefix: String = "t") = prefix + i.toString().padStart(2, '0')

    private fun sid(topic: String, j: Int) = "$topic-s${j.toString().padStart(4,'0')}"

    private fun input(
        counts: List<Int>,
        anchors: Map<String, MapAnchor> = kotlin.collections.emptyMap(),
        links: List<MapLayoutInput.Link> = emptyList(),
        titleLines: Int = 0,
        prefix: String = "t",
    ): MapLayoutInput {
        val topics = counts.mapIndexed { i, n ->
            MapLayoutInput.Topic(id(i, prefix), n, base.minusSeconds(i * 600L), titleLines)
        }
        val thoughts = counts.flatMapIndexed { i, n ->
            (0 until n).map { j ->
                MapLayoutInput.Thought(
                    sid(id(i, prefix), j),
                    id(i, prefix),
                    base.minusSeconds(i * 600L + j * 3600L),
                )
            }
        }
        return MapLayoutInput(topics, thoughts, links, anchors)
    }

    private fun MapLayoutInput.add(id: String, n: Int, age: Long = 0, pinned: Boolean = false) =
        copy(
            topics = topics + MapLayoutInput.Topic(id, n, base.minusSeconds(age), pinned = pinned),
            thoughts =
                thoughts +
                    (0 until n).map {
                        MapLayoutInput.Thought(sid(id, it), id, base.minusSeconds(age + it * 60L))
                    },
        )

    private fun MapLayoutInput.removing(id: String) =
        copy(
            topics = topics.filterNot { it.id == id },
            thoughts = thoughts.filterNot { it.topicID == id },
        )

    private fun footprints(layout: MapLayout) =
        layout.bubbles.map { b ->
            MapFootprint.make(
                    b.id,
                    b.radius,
                    layout.dots.count { it.topicID == b.id },
                    b.titleLines,
                    config,
                )
                .copy(center = b.center)
        }

    private fun assertNoOverlap(layout: MapLayout) {
        val items = footprints(layout)
        for (i in items.indices) for (j in i + 1 until items.size) {
            val depth = MapGeometry.penetration(items[i], items[j], config.gap)?.depth ?: 0.0
            assertTrue("${items[i].id}/${items[j].id}: $depth", depth <= MapGeometry.tolerance)
        }
    }

    private fun assertNothingMoved(before: MapLayout, after: MapLayout) {
        for (bubble in before.bubbles) {
            val now = after.bubble(bubble.id) ?: continue
            assertEquals(bubble.id, bubble.center, now.center)
            assertEquals(before.anchors[bubble.id], after.anchors[bubble.id])
        }
    }

    private fun center(layout: MapLayout, id: String) = layout.bubble(id)!!.center

    private fun tightAnchors(columns: Int, rows: Int) =
        (0 until columns * rows).associate {
            id(it) to MapAnchor((it % columns) * 128.0, (it / columns) * 140.0)
        }

    private fun MapRect.contains(r: MapRect) =
        minX <= r.minX && minY <= r.minY && maxX >= r.maxX && maxY >= r.maxY

    private fun dist(a: MapPoint, b: MapPoint) = hypot(a.x - b.x, a.y - b.y)

    private fun nearestMiddle(layout: MapLayout) =
        layout.bubbles.minBy { dist(it.center, MapPoint(layout.bounds.midX, layout.bounds.midY)) }

    private fun crowd(): MapLayoutInput {
        val topics =
            (0 until 500).map {
                MapLayoutInput.Topic(
                    "p${it.toString().padStart(3,'0')}",
                    1,
                    base.minusSeconds(it * 3000L),
                )
            }
        val thoughts = topics.map { MapLayoutInput.Thought("${it.id}-s0", it.id, it.lastActivity) }
        return MapLayoutInput(
            topics + MapLayoutInput.Topic("_none", 1500, base),
            thoughts +
                (0 until 1500).map {
                    MapLayoutInput.Thought(
                        "n${it.toString().padStart(4,'0')}",
                        "_none",
                        base.minusSeconds(it * 1000L + 7),
                    )
                },
        )
    }

    @Test
    fun sameInputSameOutput() {
        val links =
            listOf(
                MapLayoutInput.Link("t00-s0000", "t01-s0000"),
                MapLayoutInput.Link("t02-s0001", "t00-s0002"),
            )
        val value = input(listOf(12, 3, 7, 1, 25, 4), links = links)
        val a = MapLayout.compute(value)
        assertEquals(a, MapLayout.compute(value))
        assertTrue(a.bubbles.isNotEmpty() && a.lines.isNotEmpty())
    }

    @Test
    fun orderOfInputDoesNotMatter() {
        val links =
            (0 until 20).map {
                MapLayoutInput.Link("t0${it%6}-s000${it%3}", "t0${(it+1)%6}-s000${it%2}")
            }
        val original = input(listOf(12, 3, 7, 1, 25, 4), links = links)
        val thoughts = original.thoughts.toMutableList()
        val rng = LCG(7u)
        for (i in thoughts.indices.reversed()) {
            val j = rng.int(0..i)
            val tmp = thoughts[i]
            thoughts[i] = thoughts[j]
            thoughts[j] = tmp
        }
        val shuffled =
            original.copy(
                topics = original.topics.reversed(),
                thoughts = thoughts,
                links = links.reversed().map { MapLayoutInput.Link(it.to, it.from) },
            )
        assertEquals(MapLayout.compute(original), MapLayout.compute(shuffled))
    }

    @Test
    fun layoutIsIdempotentWithItsOwnAnchors() {
        val counts = listOf(40, 3, 9, 1, 17, 2, 6, 6, 30)
        val first = MapLayout.compute(input(counts))
        assertEquals(first, MapLayout.compute(input(counts, first.anchors)))
        val path = Files.createTempFile("map-", ".json")
        try {
            MapAnchorFile.save(first.anchors, path)
            val loaded = MapAnchorFile.load(path) as MapAnchorFile.Loaded.Anchors
            assertEquals(first, MapLayout.compute(input(counts, loaded.anchors)))
        } finally {
            Files.deleteIfExists(path)
        }
    }

    @Test
    fun radiusGrowsWithSquareRootAndIsCapped() {
        assertTrue(config.radius(1) < config.radius(4))
        assertEquals(config.radius(4) - config.radius(1), config.radius(9) - config.radius(4), .001)
        assertEquals(config.maxRadius, config.radius(10000), 0.0)
        assertEquals(config.radius(1), config.radius(0), 0.0)
    }

    @Test
    fun everyVisibleSizeFitsIntoTheReserve() {
        for (lines in listOf(0, 2, 5)) {
            val reserve = MapFootprint.reserve("r", lines, config)
            assertTrue(reserve.label.contains(MapFootprint.reserve("r", 0, config).label))
            for (count in listOf(1, 2, 3, 5, 8, 13, 20, 36, 80, 400)) {
                val shown = MapFootprint.sized("s", config.radius(count), count, lines, config)
                assertTrue("n=$count arc", shown.outer <= reserve.outer + .001)
                assertTrue("n=$count lines=$lines label", reserve.label.contains(shown.label))
            }
        }
    }

    @Test
    fun circlesNeverOverlap() {
        val rng = LCG(42u)
        repeat(6) {
            val counts = List(rng.int(8 until 40)) { rng.int(1 until 120) }
            val layout = MapLayout.compute(input(counts))
            assertEquals(min(counts.size, config.maxBubbles), layout.bubbles.size)
            assertNoOverlap(layout)
        }
    }

    @Test
    fun clusteredAnchorsAreSeparated() {
        val anchors = (0 until 12).associate { id(it) to MapAnchor((it % 2).toDouble(), 0.0) }
        val layout = MapLayout.compute(input(List(12) { 20 }, anchors))
        assertNoOverlap(layout)
        assertEquals(12, layout.bubbles.size)
    }

    @Test
    fun labelFieldIsReservedBelowEachCircle() {
        val layout = MapLayout.compute(input(listOf(5, 5, 5, 5)))
        for (b in layout.bubbles) {
            assertTrue(b.label.minY >= b.center.y + b.radius)
            assertEquals(b.center.x, b.label.midX, .001)
            assertTrue(b.label.height >= config.labelHeight)
        }
        assertNoOverlap(layout)
    }

    @Test
    fun anchorsStayWhenATopicGains() {
        val before = MapLayout.compute(input(listOf(8, 8, 8, 8, 8)))
        val after = MapLayout.compute(input(listOf(9, 8, 8, 8, 8), before.anchors))
        assertNothingMoved(before, after)
        assertTrue(after.bubble("t00")!!.radius > before.bubble("t00")!!.radius)
        assertNoOverlap(after)
    }

    @Test
    fun anchorsStayWhenTopicsGrowAll() {
        val counts = MutableList(12) { 1 }
        var layout = MapLayout.compute(input(counts))
        val first = layout
        repeat(40) { round ->
            counts[round % counts.size] += 1 + round
            val next = MapLayout.compute(input(counts, layout.anchors))
            assertNothingMoved(layout, next)
            assertNoOverlap(next)
            next.bubbles.forEach { assertEquals(it.id, config.radius(it.count), it.radius, 0.0) }
            layout = next
        }
        assertNothingMoved(first, layout)
    }

    @Test
    fun tightOldAnchorsAreClampedNotPushed() {
        val anchors = tightAnchors(3, 2)
        val before = MapLayout.compute(input(List(6) { 8 }, anchors))
        anchors.forEach { (id, a) -> assertEquals(a, before.anchors[id]) }
        assertNoOverlap(before)
        val grown = MutableList(6) { 8 }
        grown[4] = 120
        val after = MapLayout.compute(input(grown, before.anchors))
        assertNothingMoved(before, after)
        assertNoOverlap(after)
        val big = after.bubble("t04")!!
        assertTrue(big.radius < config.radius(120))
        assertTrue(big.radius >= before.bubble("t04")!!.radius - .01)
        assertEquals(after, MapLayout.compute(input(grown, after.anchors)))
    }

    @Test
    fun storedAnchorsAreKeptBitExact() {
        val anchors =
            mapOf(
                "t00" to MapAnchor(.123456789, -3.000000001),
                "t01" to MapAnchor(400.987654321, 12.5),
            )
        val layout = MapLayout.compute(input(listOf(5, 9), anchors))
        assertEquals(anchors, layout.anchors)
        assertEquals(anchors.getValue("t00").point, center(layout, "t00"))
    }

    @Test
    fun invalidAnchorsAreIgnored() {
        val layout =
            MapLayout.compute(
                input(
                    listOf(3, 3, 3),
                    mapOf(
                        "t00" to MapAnchor(Double.NaN, 0.0),
                        "t01" to MapAnchor(10.0, 10.0),
                        "t02" to MapAnchor(1e12, 0.0),
                    ),
                ),
            )
        assertTrue(
            layout.bubbles.all {
                it.center.x.isFinite() && it.center.y.isFinite() && abs(it.center.x) < 10000
            },
        )
        assertEquals(MapPoint(10.0, 10.0), center(layout, "t01"))
        assertNoOverlap(layout)
    }

    @Test
    fun anchorsStayWhenTopicsAppear() {
        val counts = mutableListOf(6)
        var layout = MapLayout.compute(input(counts))
        for (step in 1 until 22) {
            counts.add(1 + step % 5)
            val next = MapLayout.compute(input(counts, layout.anchors))
            assertNothingMoved(layout, next)
            assertNoOverlap(next)
            assertEquals(counts.size, next.bubbles.size)
            layout = next
        }
    }

    @Test
    fun anchorsStayWhenTopicsDisappear() {
        val counts = listOf(10, 4, 7, 2, 15, 3, 9, 5)
        val before = MapLayout.compute(input(counts))
        val next =
            input(counts, before.anchors).removing("t05").let { v ->
                v.copy(
                    topics = v.topics.map { if (it.id == "t02") it.copy(count = 0) else it },
                    thoughts = v.thoughts.filterNot { it.topicID == "t02" },
                )
            }
        val after = MapLayout.compute(next)
        assertNothingMoved(before, after)
        assertNull(after.bubble("t02"))
        assertNull(after.bubble("t05"))
        assertEquals(before.anchors["t02"], after.anchors["t02"])
        assertNull(after.anchors["t05"])
        val back = MapLayout.compute(input(counts, after.anchors).removing("t05"))
        assertEquals(before.bubble("t02")?.center, back.bubble("t02")?.center)
        assertNothingMoved(before, back)
    }

    @Test
    fun returningTopicWhosePlaceIsTakenMovesAlone() {
        val counts = List(7) { 10 }
        val before = MapLayout.compute(input(counts))
        val inner = nearestMiddle(before)
        val resting =
            input(counts, before.anchors)
                .let { v ->
                    v.copy(
                        topics = v.topics.map { if (it.id == inner.id) it.copy(count = 0) else it },
                        thoughts = v.thoughts.filterNot { it.topicID == inner.id },
                    )
                }
                .add("neu", 10)
        val during = MapLayout.compute(resting)
        assertTrue(dist(during.bubble("neu")!!.center, inner.center) < inner.outerRadius)
        assertNull(during.anchors[inner.id])
        val after = MapLayout.compute(input(counts, during.anchors).add("neu", 10))
        assertNothingMoved(during, after)
        assertNoOverlap(after)
        assertNotEquals(inner.center, after.bubble(inner.id)!!.center)
    }

    @Test
    fun newTopicsFillTheGapOfADeletedOne() {
        val counts = List(7) { 10 }
        val before = MapLayout.compute(input(counts))
        val inner = nearestMiddle(before)
        val next = input(counts, before.anchors - inner.id).removing(inner.id).add("neu", 10)
        val after = MapLayout.compute(next)
        assertNoOverlap(after)
        assertNothingMoved(before, after)
        assertTrue(dist(center(after, "neu"), inner.center) < inner.outerRadius)
        assertTrue(
            after.bounds.width <= before.bounds.width + 1 &&
                after.bounds.height <= before.bounds.height + 1,
        )
    }

    @Test
    fun longSessionKeepsEveryAnchor() {
        val rng = LCG(2026u)
        val counts = mutableListOf(1)
        var layout = MapLayout.compute(input(counts))
        repeat(200) { step ->
            if (step % 9 == 0 && counts.size < 20) counts.add(1)
            else if (step % 23 == 0 && counts.size > 3) counts[rng.int(counts.indices)] = 0
            else {
                val i = rng.int(counts.indices)
                counts[i] += 1 + if (counts[i] > 10) rng.int(0 until 6) else 0
            }
            val next = MapLayout.compute(input(counts, layout.anchors))
            assertNothingMoved(layout, next)
            assertNoOverlap(next)
            layout = next
        }
    }

    @Test
    fun fewTopicsAreBalancedNotAColumn() {
        for (n in 3..5) {
            val layout = MapLayout.compute(input(List(n) { 3 }))
            val xs = layout.bubbles.map { round(it.center.x * 10) }.toSet()
            assertTrue("$n topics", xs.size >= 2)
            assertTrue(layout.bounds.width >= .45 * layout.bounds.height)
        }
        val four = MapLayout.compute(input(listOf(4, 4, 4, 4)))
        val columns = four.bubbles.groupBy { round(it.center.x / 40) }
        assertTrue(
            four.bubbles.toString(),
            columns.size == 2 && columns.values.all { it.size == 2 },
        )
    }

    @Test
    fun fiveThoughtsWithNoTopicAreBalanced() {
        val value =
            MapLayoutInput(emptyList(), emptyList())
                .add("paply", 2)
                .add("wohnung", 1, 600)
                .add("urlaub", 1, 1200)
                .add("_none", 1, 1800)
                .let { v -> v.copy(topics = v.topics.map { it.copy(titleLines = it.count) }) }
        val layout = MapLayout.compute(value)
        assertNoOverlap(layout)
        val midX = layout.bubbles.sumOf { it.center.x } / layout.bubbles.size
        assertEquals(2, layout.bubbles.count { it.center.x < midX - 1 })
        assertEquals(2, layout.bubbles.count { it.center.x > midX + 1 })
        assertTrue(layout.bubbles.all { it.titleLines == it.count })
    }

    @Test
    fun pseudoTopicsSitAtTheBottomEdge() {
        val start = input(listOf(12, 8, 6, 5, 3, 2)).add("_none", 9, 3000)
        val layout = MapLayout.compute(start)
        val none = center(layout, "_none")
        assertTrue(layout.bubbles.filterNot { it.id == "_none" }.all { it.center.y <= none.y + .5 })
        var later = start.copy(anchors = layout.anchors)
        repeat(6) { later = later.add("n$it", 2 + it, it.toLong()) }
        val grown = MapLayout.compute(later)
        assertNothingMoved(layout, grown)
        assertTrue(grown.bubbles.filterNot { it.id == "_none" }.all { it.center.y <= none.y + .5 })
        var first = MapLayoutInput(emptyList(), emptyList()).add("_none", 1)
        val one = MapLayout.compute(first)
        first = first.copy(anchors = one.anchors).add("a", 2).add("b", 1, 10)
        val three = MapLayout.compute(first)
        assertEquals(MapPoint.zero, center(three, "_none"))
        assertTrue(three.bubbles.all { it.center.y <= .5 })
    }

    @Test
    fun crowdIsCappedAndCollected() {
        val value = crowd()
        val layout = MapLayout.compute(value)
        assertEquals(config.maxBubbles, layout.bubbles.size)
        assertNotNull(layout.bubble("_none"))
        val more = layout.bubble(MapLayout.moreID)
        assertNotNull(more)
        assertEquals(500 - (config.maxBubbles - 2), layout.collected.size)
        assertEquals(layout.collected.size, more!!.count)
        assertEquals(config.maxDots, layout.dots.count { it.topicID == MapLayout.moreID })
        assertEquals(MapLayout.collected(value.topics), layout.collected.toSet())
        assertNotNull(layout.bubble("p000"))
        assertNotNull(layout.bubble("p021"))
        assertNull(layout.bubble("p022"))
        assertTrue(
            layout.dots
                .filter { it.topicID == MapLayout.moreID }
                .all { it.id.take(4) in layout.collected },
        )
        assertNoOverlap(layout)
        val again =
            MapLayout.compute(
                value.copy(anchors = layout.anchors + mapOf("p300" to MapAnchor(5000.0, 5000.0))),
            )
        assertEquals(MapAnchor(5000.0, 5000.0), again.anchors["p300"])
        assertNothingMoved(layout, again)
    }

    @Test
    fun realTopicsGetACircleBeforeSingles() {
        var value = MapLayoutInput(emptyList(), emptyList())
        repeat(40) { value = value.add(id(it, "s"), 1, it.toLong()) }
        value = value.add("alt-zwei", 2, 900000).add("alt-nutzer", 1, 990000, true)
        val layout = MapLayout.compute(value)
        assertNotNull(layout.bubble("alt-zwei"))
        assertNotNull(layout.bubble("alt-nutzer"))
        assertEquals(config.maxBubbles, layout.bubbles.size)
        assertNotNull(layout.bubble(MapLayout.moreID))
        var exact = MapLayoutInput(emptyList(), emptyList())
        repeat(config.maxBubbles) { exact = exact.add(id(it, "e"), 1, it.toLong()) }
        assertNull(MapLayout.compute(exact).bubble(MapLayout.moreID))
    }

    private fun measure(block: () -> Unit): Double {
        val t = System.nanoTime()
        block()
        return (System.nanoTime() - t) / 1e6
    }

    @Test
    fun crowdLayoutIsFast() {
        val value = crowd()
        assertEquals(2000, value.thoughts.size)
        var layout = MapLayout.empty
        var first = 10000.0
        repeat(7) { first = min(first, measure { layout = MapLayout.compute(value) }) }
        val steady = value.copy(anchors = layout.anchors)
        var again = 10000.0
        repeat(7) { again = min(again, measure { MapLayout.compute(steady) }) }
        assertTrue("first ${first}ms", first < 150)
        assertTrue("anchors ${again}ms", again < 50)
    }

    @Test
    fun emptyMap() {
        assertEquals(MapLayout.empty, MapLayout.compute(MapLayoutInput(emptyList(), emptyList())))
        val empty = MapLayout.compute(input(listOf(0, 0)))
        assertTrue(empty.bubbles.isEmpty())
        assertEquals(MapRect.zero, empty.bounds)
    }

    @Test
    fun singleThought() {
        val layout = MapLayout.compute(input(listOf(1), titleLines = 1))
        assertEquals(1, layout.bubbles.size)
        assertEquals(1, layout.dots.size)
        val b = layout.bubbles[0]
        val dot = layout.dots[0]
        assertEquals(MapPoint.zero, b.center)
        assertEquals(0, b.hiddenCount)
        assertEquals(-PI / 2, dot.angle, .0001)
        assertEquals(0.0, dot.position.y + b.radius + config.firstRing, .0001)
        assertEquals(config.labelHeight + config.titleLineHeight + 4, b.label.height, 0.0)
        assertTrue(layout.bounds.contains(b.label) && layout.bounds.contains(dot.position))
    }

    @Test
    fun fiveThoughtsWithTitles() {
        val layout = MapLayout.compute(input(listOf(2, 2, 1), titleLines = 2))
        assertEquals(3, layout.bubbles.size)
        assertEquals(5, layout.dots.size)
        assertTrue(layout.bubbles.all { it.label.width >= config.titleWidth && it.titleLines == 2 })
        assertNoOverlap(layout)
    }

    @Test
    fun threeHundredThoughtsInOneTopic() {
        val layout = MapLayout.compute(input(listOf(300)))
        val b = layout.bubbles[0]
        assertEquals(config.maxDots, layout.dots.size)
        assertEquals(300 - config.maxDots, b.hiddenCount)
        assertEquals(config.maxRadius, b.radius, 0.0)
        val rings = layout.dots.sortedBy { it.rank }.map { it.ring }
        assertEquals(rings.sorted(), rings)
        assertEquals("t00-s0000", layout.dots.first { it.rank == 0 }.id)
        layout.dots.forEach {
            val d = dist(it.position, b.center)
            assertTrue(d >= b.radius + config.firstRing - .001 && d <= b.outerRadius)
            assertTrue(it.position.y < b.label.minY)
        }
    }

    @Test
    fun allDotsFitOnTheInnerArc() {
        for (n in 1..400) assertEquals(
            "n=$n",
            1,
            MapGeometry.ringCount(min(n, config.maxDots), config.radius(n), config),
        )
    }

    @Test
    fun dotsKeepMinimumSpacing() {
        for (n in listOf(2, 7, 16, 24)) {
            val dots = MapLayout.compute(input(listOf(n))).dots
            for (i in dots.indices) for (j in i + 1 until dots.size) assertTrue(
                "n=$n $i/$j",
                dist(dots[i].position, dots[j].position) >= config.dotSpacing * .95,
            )
        }
    }

    @Test
    fun newThoughtShiftsDotsOnlyOnePlace() {
        val before = MapLayout.compute(input(listOf(30)))
        val next =
            input(listOf(31), before.anchors)
                .copy(
                    thoughts =
                        listOf(MapLayoutInput.Thought("neu", "t00", base.plusSeconds(60))) +
                            input(listOf(30)).thoughts,
                )
        val after = MapLayout.compute(next)
        assertEquals("neu", after.dots.first { it.rank == 0 }.id)
        for (dot in before.dots.filter { it.rank < config.maxDots - 1 }) {
            val moved = after.dots.first { it.id == dot.id }
            assertEquals(dot.rank + 1, moved.rank)
            assertTrue(dist(moved.position, dot.position) < 30)
        }
        assertFalse(
            after.dots.any { it.id == before.dots.first { it.rank == config.maxDots - 1 }.id },
        )
    }

    @Test
    fun linesOnlyForRealLinksAtMostTwoPerThought() {
        val links =
            (1 until 8).map { MapLayoutInput.Link("t00-s0000", "t01-s000$it") } +
                listOf(
                    MapLayoutInput.Link("t02-s0000", "t02-s0001"),
                    MapLayoutInput.Link("t02-s0001", "t02-s0000"),
                    MapLayoutInput.Link("t02-s0000", "gibt-es-nicht"),
                    MapLayoutInput.Link("t02-s0002", "t02-s0002"),
                )
        val layout = MapLayout.compute(input(listOf(3, 9, 4), links = links))
        val perThought = layout.lines.flatMap { listOf(it.a, it.b) }.groupingBy { it }.eachCount()
        for (line in layout.lines) {
            assertTrue(
                links.any {
                    it.from == line.a && it.to == line.b || it.from == line.b && it.to == line.a
                },
            )
            assertEquals(line.topicA != line.topicB, line.crossTopic)
        }
        assertTrue(perThought.values.all { it <= config.maxLinksPerThought })
        assertEquals(2, perThought["t00-s0000"])
        assertEquals(1, layout.lines.count { !it.crossTopic })
        assertFalse(layout.lines.any { it.a == "gibt-es-nicht" || it.b == "gibt-es-nicht" })
    }

    @Test
    fun linesToHiddenThoughtsStartAtTheCircle() {
        val links =
            listOf(
                MapLayoutInput.Link("t00-s0039", "t01-s0000"),
                MapLayoutInput.Link("t00-s0039", "t00-s0000"),
            )
        val layout = MapLayout.compute(input(listOf(40, 2), links = links))
        assertEquals(1, layout.lines.size)
        val line = layout.lines[0]
        assertTrue(line.touchesHidden && line.crossTopic)
        val b = layout.bubble("t00")!!
        val start = if (line.a == "t00-s0039") line.from else line.to
        assertEquals(b.radius, dist(start, b.center), .01)
    }

    @Test
    fun overviewShowsFewStrongTopicLines() {
        val links =
            (0 until 4).map { MapLayoutInput.Link("t00-s000$it", "t01-s000$it") }.toMutableList()
        links.addAll(
            listOf(
                MapLayoutInput.Link("t01-s0000", "t00-s0000"),
                MapLayoutInput.Link("t00-s0005", "t02-s0000"),
                MapLayoutInput.Link("t00-s0006", "t00-s0007"),
            ),
        )
        for (k in 3 until 7) {
            links.add(MapLayoutInput.Link("t00-s0008", "t0$k-s0000"))
            links.add(MapLayoutInput.Link("t00-s0009", "t0$k-s0001"))
        }
        val counts = listOf(12, 6, 3, 3, 3, 3, 3)
        val layout = MapLayout.compute(input(counts, links = links))
        val pairs = layout.topicLines
        assertEquals("t00|t01", pairs.first().id)
        assertEquals(4, pairs.first().count)
        assertTrue(pairs.all { it.a < it.b && it.count >= config.minTopicLinks })
        assertFalse(pairs.any { it.id == "t00|t02" })
        assertTrue(
            pairs
                .flatMap { listOf(it.a, it.b) }
                .groupingBy { it }
                .eachCount()
                .values
                .all { it <= config.maxTopicLinesPerTopic },
        )
        for (line in pairs) {
            val a = layout.bubble(line.a)!!
            val b = layout.bubble(line.b)!!
            assertEquals(a.radius, dist(line.from, a.center), .01)
            assertEquals(b.radius, dist(line.to, b.center), .01)
        }
        assertEquals(pairs, MapLayout.compute(input(counts, links = links.reversed())).topicLines)
    }

    @Test
    fun topicLinesAreCappedAndSkipPseudoTopics() {
        val links =
            (0 until 19).flatMap { i ->
                (0 until 3).map { MapLayoutInput.Link(sid(id(i), it), sid(id(i + 1), it)) }
            }
        val value =
            input(List(20) { 4 }, links = links).add("_none", 4).let { v ->
                v.copy(
                    links =
                        v.links +
                            (0 until 3).map { MapLayoutInput.Link("t00-s000$it", "_none-s000$it") },
                )
            }
        val layout = MapLayout.compute(value)
        assertTrue(layout.topicLines.size <= config.maxTopicLines && layout.topicLines.isNotEmpty())
        assertFalse(layout.topicLines.any { it.a.startsWith("_") || it.b.startsWith("_") })
    }

    @Test
    fun topicLinesNeverCrossAThirdCircle() {
        val anchors =
            mapOf(
                "a" to MapAnchor(0.0, 0.0),
                "c" to MapAnchor(180.0, 0.0),
                "b" to MapAnchor(360.0, 0.0),
            )
        val value =
            MapLayoutInput(emptyList(), emptyList(), anchors = anchors)
                .add("a", 3)
                .add("b", 3)
                .add("c", 3)
                .copy(
                    links =
                        (0 until 3).map { MapLayoutInput.Link("a-s000$it", "b-s000$it") } +
                            (0 until 2).map { MapLayoutInput.Link("a-s000$it", "c-s000$it") },
                )
        assertEquals(listOf("a|c"), MapLayout.compute(value).topicLines.map { it.id })
        val rng = LCG(5u)
        val many =
            input(List(14) { 5 }).let { v ->
                v.copy(
                    links =
                        List(200) {
                            val a = rng.int(0 until 14)
                            val b = rng.int(0 until 14)
                            MapLayoutInput.Link(
                                sid(id(a), rng.int(0 until 5)),
                                sid(id(b), rng.int(0 until 5)),
                            )
                        },
                )
            }
        val busy = MapLayout.compute(many)
        for (line in busy.topicLines) for (b in
            busy.bubbles.filter { it.id != line.a && it.id != line.b }) for (i in 0..20) {
            val t = i / 20.0
            val u = 1 - t
            val p =
                MapPoint(
                    u * u * line.from.x + 2 * u * t * line.control.x + t * t * line.to.x,
                    u * u * line.from.y + 2 * u * t * line.control.y + t * t * line.to.y,
                )
            assertTrue("${line.id}/${b.id}", dist(p, b.center) > b.radius)
        }
    }

    @Test
    fun twoThousandThoughtsAreFast() {
        val rng = LCG(99u)
        val value =
            input(listOf(420, 300, 260, 200, 160, 140, 120, 100, 80, 60, 50, 40, 30, 20, 20)).let {
                v ->
                v.copy(
                    links =
                        List(500) {
                            val a = v.thoughts[rng.int(v.thoughts.indices)].id
                            val b = v.thoughts[rng.int(v.thoughts.indices)].id
                            MapLayoutInput.Link(a, b)
                        },
                )
            }
        assertEquals(2000, value.thoughts.size)
        var first = 10000.0
        var layout = MapLayout.empty
        repeat(7) { first = min(first, measure { layout = MapLayout.compute(value) }) }
        val steady = value.copy(anchors = layout.anchors)
        var again = 10000.0
        repeat(7) { again = min(again, measure { MapLayout.compute(steady) }) }
        assertTrue("first ${first}ms", first < 150)
        assertTrue("anchors ${again}ms", again < 100)
        assertNoOverlap(layout)
    }
}
