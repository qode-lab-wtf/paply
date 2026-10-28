package com.paply.thoughts.map

import java.time.Instant
import kotlin.math.*
import kotlinx.serialization.Serializable

/** Platform-independent geometry, in map points (screen points at zoom 1). */
data class MapPoint(val x: Double, val y: Double) {
    companion object {
        val zero = MapPoint(0.0, 0.0)
    }
}

data class MapSize(val width: Double, val height: Double)

data class MapRect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX
        get() = x

    val minY
        get() = y

    val maxX
        get() = x + width

    val maxY
        get() = y + height

    val midX
        get() = x + width / 2

    val midY
        get() = y + height / 2

    fun offset(dx: Double, dy: Double) = copy(x = x + dx, y = y + dy)

    fun inset(dx: Double, dy: Double) = MapRect(x + dx, y + dy, width - 2 * dx, height - 2 * dy)

    fun union(other: MapRect): MapRect {
        val a = min(x, other.x)
        val b = min(y, other.y)
        return MapRect(a, b, max(maxX, other.maxX) - a, max(maxY, other.maxY) - b)
    }

    fun contains(p: MapPoint) = p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY

    companion object {
        val zero = MapRect(0.0, 0.0, 0.0, 0.0)
    }
}

@Serializable
data class MapAnchor(val x: Double, val y: Double) {
    constructor(point: MapPoint) : this(point.x, point.y)

    val point
        get() = MapPoint(x, y)
}

data class MapLayoutInput(
    val topics: List<Topic>,
    val thoughts: List<Thought>,
    val links: List<Link> = emptyList(),
    val anchors: Map<String, MapAnchor> = emptyMap(),
) {
    data class Topic(
        val id: String,
        val count: Int,
        val lastActivity: Instant,
        val titleLines: Int = 0,
        val pinned: Boolean = false,
    )

    data class Thought(val id: String, val topicID: String, val createdAt: Instant)

    data class Link(val from: String, val to: String)
}

data class MapLayoutConfig(
    val minRadius: Double = 20.0,
    val radiusPerRoot: Double = 7.0,
    val maxRadius: Double = 62.0,
    val gap: Double = 16.0,
    val maxDots: Int = 24,
    val firstRing: Double = 12.0,
    val ringStep: Double = 12.0,
    val dotSpacing: Double = 11.0,
    val maxDotSpacing: Double = 22.0,
    val dotRadius: Double = 4.0,
    val arc: Double = 220 * PI / 180,
    val labelGap: Double = 8.0,
    val labelHeight: Double = 20.0,
    val labelWidth: Double = 112.0,
    val titleLineHeight: Double = 17.0,
    val titleWidth: Double = 196.0,
    val maxLinksPerThought: Int = 2,
    val maxLines: Int = 600,
    val minTopicLinks: Int = 2,
    val maxTopicLines: Int = 6,
    val maxTopicLinesPerTopic: Int = 3,
    val maxBubbles: Int = 24,
    val aspect: Double = 0.68,
    val directions: Int = 36,
) {
    fun radius(count: Int) =
        min(maxRadius, minRadius + radiusPerRoot * sqrt(max(1, count).toDouble()))
}

internal data class MapFootprint(
    val id: String,
    val center: MapPoint,
    val radius: Double,
    val outer: Double,
    val dots: Int,
    val titleLines: Int,
    val label: MapRect,
) {
    val lx0 = label.minX
    val lx1 = label.maxX
    val ly0 = label.minY
    val ly1 = label.maxY
    val bound = maxOf(outer, hypot(lx0, ly0), hypot(lx0, ly1), hypot(lx1, ly0), hypot(lx1, ly1))
    val labelRect
        get() = label.offset(center.x, center.y)

    val circleRect
        get() = MapRect(center.x - outer, center.y - outer, 2 * outer, 2 * outer)

    val extent
        get() =
            MapRect(
                min(-outer, lx0),
                min(-outer, ly0),
                max(outer, lx1) - min(-outer, lx0),
                max(outer, ly1) - min(-outer, ly0),
            )

    companion object {
        fun make(
            id: String,
            radius: Double,
            dots: Int,
            titleLines: Int,
            config: MapLayoutConfig,
        ): MapFootprint {
            val rings = MapGeometry.ringCount(dots, radius, config)
            val outer =
                if (rings == 0) radius
                else radius + config.firstRing + (rings - 1) * config.ringStep + config.dotRadius
            val width =
                max(if (titleLines > 0) config.titleWidth else config.labelWidth, 2 * radius + 16)
            val height =
                config.labelHeight +
                    if (titleLines > 0) titleLines * config.titleLineHeight + 4 else 0.0
            return MapFootprint(
                id,
                MapPoint.zero,
                radius,
                outer,
                dots,
                titleLines,
                MapRect(-width / 2, radius + config.labelGap, width, height),
            )
        }

        fun sized(
            id: String,
            radius: Double,
            thoughts: Int,
            titleLines: Int,
            config: MapLayoutConfig,
        ) =
            make(
                id,
                radius,
                max(
                    0,
                    minOf(thoughts, config.maxDots, MapGeometry.ringCapacity(0, radius, config)),
                ),
                titleLines,
                config,
            )

        fun reserve(id: String, titleLines: Int, config: MapLayoutConfig): MapFootprint {
            val big = make(id, config.maxRadius, config.maxDots, titleLines, config)
            val top = config.radius(1) + config.labelGap
            return big.copy(
                label = MapRect(big.label.x, top, big.label.width, big.label.maxY - top),
            )
        }
    }
}
