package com.paply.thoughts.map

import java.time.Instant
import kotlin.math.*

/** Deterministic layout. Growth never moves a valid remembered center. */
data class MapLayout(
    val bubbles: List<Bubble>,
    val dots: List<Dot>,
    val lines: List<Line>,
    val topicLines: List<TopicLine>,
    val bounds: MapRect,
    val anchors: Map<String, MapAnchor>,
    val collected: List<String>,
) {
    data class Bubble(
        val id: String,
        val center: MapPoint,
        val radius: Double,
        val outerRadius: Double,
        val label: MapRect,
        val count: Int,
        val hiddenCount: Int,
        val titleLines: Int,
    )

    data class Dot(
        val id: String,
        val topicID: String,
        val position: MapPoint,
        val angle: Double,
        val ring: Int,
        val rank: Int,
    )

    data class Line(
        val a: String,
        val b: String,
        val topicA: String,
        val topicB: String,
        val from: MapPoint,
        val control: MapPoint,
        val to: MapPoint,
        val crossTopic: Boolean,
        val touchesHidden: Boolean,
    ) {
        val id
            get() = "$a|$b"
    }

    data class TopicLine(
        val a: String,
        val b: String,
        val count: Int,
        val from: MapPoint,
        val control: MapPoint,
        val to: MapPoint,
    ) {
        val id
            get() = "$a|$b"
    }

    fun bubble(id: String) = bubbles.firstOrNull { it.id == id }

    private class Entry(
        val topic: MapLayoutInput.Topic,
        val thoughts: List<MapLayoutInput.Thought>,
        config: MapLayoutConfig,
    ) {
        val id
            get() = topic.id

        val pseudo
            get() = isPseudo(id)

        var center = MapPoint.zero
        val want =
            MapFootprint.sized(
                id,
                config.radius(topic.count),
                thoughts.size,
                max(0, topic.titleLines),
                config,
            )
        val floor = MapFootprint.sized(id, config.radius(1), thoughts.size, 0, config)
        val reserve = MapFootprint.reserve(id, 0, config)
        var shape = want

        fun at(f: MapFootprint) = f.copy(center = center)
    }

    companion object {
        const val moreID = "_more"
        val empty =
            MapLayout(
                emptyList(),
                emptyList(),
                emptyList(),
                emptyList(),
                MapRect.zero,
                emptyMap(),
                emptyList(),
            )

        internal fun isPseudo(id: String) = id.startsWith("_")

        fun collected(
            topics: List<MapLayoutInput.Topic>,
            config: MapLayoutConfig = MapLayoutConfig(),
        ): Set<String> {
            val eligible =
                topics.filter { it.id != moreID }.distinctBy { it.id }.filter { it.count > 0 }
            val real = eligible.filterNot { isPseudo(it.id) }
            val room = max(1, config.maxBubbles - eligible.count { isPseudo(it.id) })
            if (real.size <= room) return emptySet()
            return real
                .sortedWith(
                    compareByDescending<MapLayoutInput.Topic> { it.pinned || it.count >= 2 }
                        .thenByDescending { it.lastActivity }
                        .thenByDescending { it.count }
                        .thenBy { it.id },
                )
                .drop(max(0, room - 1))
                .map { it.id }
                .toSet()
        }

        fun compute(input: MapLayoutInput, config: MapLayoutConfig = MapLayoutConfig()): MapLayout {
            val topics = input.topics.filter { it.id != moreID }.distinctBy { it.id }
            val collected = collected(topics, config)
            val shown = mutableListOf<MapLayoutInput.Topic>()
            val resting = mutableListOf<String>()
            var more = MapLayoutInput.Topic(moreID, 0, Instant.MIN)
            for (topic in topics) when {
                topic.count <= 0 -> resting.add(topic.id)
                topic.id in collected -> {
                    more =
                        more.copy(
                            count = more.count + topic.count,
                            lastActivity = maxOf(more.lastActivity, topic.lastActivity),
                        )
                    resting.add(topic.id)
                }
                else -> shown.add(topic)
            }
            if (more.count > 0) shown.add(more)
            val shownIDs = shown.map { it.id }.toSet()
            val byTopic =
                input.thoughts
                    .map { if (it.topicID in collected) it.copy(topicID = moreID) else it }
                    .filter { it.topicID in shownIDs }
                    .distinctBy { it.id }
                    .groupBy { it.topicID }
                    .mapValues { (_, v) ->
                        v.sortedWith(
                            compareByDescending<MapLayoutInput.Thought> { it.createdAt }
                                .thenBy { it.id },
                        )
                    }
            val entries =
                shown.sortedBy { it.id }.map { Entry(it, byTopic[it.id].orEmpty(), config) }
            val byWeight =
                entries.indices.sortedWith(
                    compareByDescending<Int> { entries[it].topic.count }.thenBy { entries[it].id },
                )
            val placed = mutableListOf<Int>()
            val fresh = mutableListOf<Int>()
            for (i in byWeight) {
                val e = entries[i]
                val anchor = input.anchors[e.id]
                if (
                    anchor == null ||
                        !anchor.x.isFinite() ||
                        !anchor.y.isFinite() ||
                        abs(anchor.x) >= 1e6 ||
                        abs(anchor.y) >= 1e6
                ) {
                    fresh.add(i)
                    continue
                }
                e.center = anchor.point
                if (
                    placed.any {
                        MapGeometry.overlaps(
                            entries[it].at(entries[it].floor),
                            e.at(e.floor),
                            config.gap,
                        )
                    }
                )
                    fresh.add(i)
                else placed.add(i)
            }
            fresh.sortWith(
                compareBy<Int> { entries[it].pseudo }
                    .thenByDescending { entries[it].topic.lastActivity }
                    .thenByDescending { entries[it].topic.count }
                    .thenBy { entries[it].id },
            )
            val space = MapGeometry.Space(config)
            placed.forEach { space.obstacles.add(entries[it].at(entries[it].reserve)) }
            for (i in fresh) {
                val real = placed.filterNot { entries[it].pseudo }.map { entries[it].center.y }
                val pseudo = placed.filter { entries[it].pseudo }.map { entries[it].center.y }
                val band =
                    if (entries[i].pseudo)
                        (real + pseudo).maxOrNull()?.let { MapGeometry.Band.AtOrBelow(it) }
                            ?: MapGeometry.Band.Any
                    else
                        pseudo
                            .minOrNull()
                            ?.takeIf { it >= (real.maxOrNull() ?: Double.NEGATIVE_INFINITY) }
                            ?.let { MapGeometry.Band.AtOrAbove(it) } ?: MapGeometry.Band.Any
                entries[i].center = space.findSpot(entries[i].reserve, band)
                space.obstacles.add(entries[i].at(entries[i].reserve))
                placed.add(i)
            }
            fit(entries, config)
            val bubbles = mutableListOf<Bubble>()
            val dots = mutableListOf<Dot>()
            val anchors = mutableMapOf<String, MapAnchor>()
            val dotIndex = mutableMapOf<String, Int>()
            val shapes = mutableMapOf<String, MapFootprint>()
            for (e in entries) {
                val shape = e.at(e.shape)
                val visible = e.thoughts.take(shape.dots)
                for ((rank, slot) in
                    MapGeometry.dotSlots(visible.size, shape.radius, config).withIndex()) {
                    val thought = visible[rank]
                    dotIndex[thought.id] = dots.size
                    dots.add(
                        Dot(
                            thought.id,
                            e.id,
                            MapPoint(
                                shape.center.x + slot.offset.x,
                                shape.center.y + slot.offset.y,
                            ),
                            slot.angle,
                            slot.ring,
                            rank,
                        ),
                    )
                }
                bubbles.add(
                    Bubble(
                        e.id,
                        shape.center,
                        shape.radius,
                        shape.outer,
                        shape.labelRect,
                        e.topic.count,
                        max(0, e.topic.count - visible.size),
                        shape.titleLines,
                    ),
                )
                anchors[e.id] = MapAnchor(shape.center)
                shapes[e.id] = shape
            }
            val counts = topics.associate { it.id to it.count }
            val drawn = entries.map { shapes.getValue(it.id) }
            for (id in resting + moreID) {
                if (id in anchors) continue
                val a = input.anchors[id] ?: continue
                if (!a.x.isFinite() || !a.y.isFinite()) continue
                val f =
                    MapFootprint.sized(id, config.radius(1), max(1, counts[id] ?: 1), 0, config)
                        .copy(center = MapGeometry.snap(a.point))
                if (drawn.none { MapGeometry.overlaps(it, f, config.gap) }) anchors[id] = a
            }
            val created =
                byTopic
                    .flatMap { (topic, list) ->
                        list.map { it.id to MapLines.Created(topic, it.createdAt) }
                    }
                    .toMap()
            val lines = MapLines.lines(input.links, created, dots, dotIndex, shapes, config)
            val topicLines = MapLines.topicLines(input.links, created, shapes, config)
            val rectangles =
                drawn.flatMap { listOf(it.circleRect, it.labelRect) } +
                    topicLines.map { apexRect(it.from, it.control, it.to) } +
                    lines.map { apexRect(it.from, it.control, it.to) }
            val bounds = rectangles.reduceOrNull { a, b -> a.union(b) } ?: MapRect.zero
            return MapLayout(bubbles, dots, lines, topicLines, bounds, anchors, collected.sorted())
        }

        private fun apexRect(from: MapPoint, control: MapPoint, to: MapPoint) =
            MapRect(
                .25 * from.x + .5 * control.x + .25 * to.x - 1,
                .25 * from.y + .5 * control.y + .25 * to.y - 1,
                2.0,
                2.0,
            )

        private fun fit(entries: List<Entry>, config: MapLayoutConfig) {
            val order =
                entries.indices.sortedWith(
                    compareByDescending<Int> { entries[it].topic.count }.thenBy { entries[it].id },
                )
            val done = BooleanArray(entries.size)
            for (i in order) {
                val e = entries[i]
                val others =
                    entries.indices
                        .filter { it != i }
                        .map {
                            entries[it].at(if (done[it]) entries[it].shape else entries[it].floor)
                        }
                fun fits(f: MapFootprint) = others.none {
                    MapGeometry.overlaps(it, e.at(f), config.gap)
                }
                val want = e.want
                var best = want
                if (!fits(want)) {
                    var found = false
                    for (lines in want.titleLines - 1 downTo 0) {
                        val f =
                            MapFootprint.sized(want.id, want.radius, e.thoughts.size, lines, config)
                        if (fits(f)) {
                            best = f
                            found = true
                            break
                        }
                    }
                    if (!found) {
                        var lo = e.floor.radius
                        var hi = want.radius
                        repeat(14) {
                            val mid = (lo + hi) / 2
                            val f = MapFootprint.sized(want.id, mid, e.thoughts.size, 0, config)
                            if (fits(f)) lo = mid else hi = mid
                        }
                        val radius = floor(lo * 100) / 100
                        best =
                            if (radius <= e.floor.radius) e.floor
                            else MapFootprint.sized(want.id, radius, e.thoughts.size, 0, config)
                    }
                }
                e.shape = best
                done[i] = true
            }
        }
    }
}
