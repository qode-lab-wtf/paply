package com.paply.thoughts.map

import kotlin.math.*

internal object MapGeometry {
    data class Push(val dx: Double, val dy: Double, val depth: Double)

    const val tolerance = .01
    const val slack = .05

    // Swift's rounded() rounds half away from zero (kotlin.math.round uses ties-to-even).
    private fun rounded(x: Double) = if (x >= 0) floor(x + .5) else ceil(x - .5)

    fun snap(p: MapPoint) = MapPoint(rounded(p.x * 100) / 100, rounded(p.y * 100) / 100)

    fun penetration(a: MapFootprint, b: MapFootprint, gap: Double): Push? {
        val dx = b.center.x - a.center.x
        val dy = b.center.y - a.center.y
        val reach = a.bound + b.bound + gap
        if (dx * dx + dy * dy >= reach * reach) return null
        var best: Push? = null
        fun consider(p: Push?) {
            if (p != null && p.depth > (best?.depth ?: 0.0)) best = p
        }
        val ax = a.center.x
        val ay = a.center.y
        val bx = b.center.x
        val by = b.center.y
        consider(circleCircle(ax, ay, a.outer, bx, by, b.outer, gap))
        consider(
            circleRect(ax, ay, a.outer, bx + b.lx0, by + b.ly0, bx + b.lx1, by + b.ly1, gap, true),
        )
        consider(
            circleRect(bx, by, b.outer, ax + a.lx0, ay + a.ly0, ax + a.lx1, ay + a.ly1, gap, false),
        )
        consider(
            rectRect(
                ax + a.lx0,
                ay + a.ly0,
                ax + a.lx1,
                ay + a.ly1,
                bx + b.lx0,
                by + b.ly0,
                bx + b.lx1,
                by + b.ly1,
                gap,
            ),
        )
        return best
    }

    fun overlaps(a: MapFootprint, b: MapFootprint, gap: Double) =
        (penetration(a, b, gap)?.depth ?: 0.0) > tolerance

    private fun circleCircle(
        ax: Double,
        ay: Double,
        ra: Double,
        bx: Double,
        by: Double,
        rb: Double,
        gap: Double,
    ): Push? {
        val dx = bx - ax
        val dy = by - ay
        val d = sqrt(dx * dx + dy * dy)
        val depth = ra + rb + gap - d
        if (depth <= 0) return null
        return if (d < 1e-9) Push(0.0, 1.0, depth) else Push(dx / d, dy / d, depth)
    }

    private fun circleRect(
        cx: Double,
        cy: Double,
        r: Double,
        x0: Double,
        y0: Double,
        x1: Double,
        y1: Double,
        gap: Double,
        circleIsA: Boolean,
    ): Push? {
        val vx = cx - cx.coerceIn(x0, x1)
        val vy = cy - cy.coerceIn(y0, y1)
        val d2 = vx * vx + vy * vy
        val limit = r + gap
        if (d2 >= limit * limit) return null
        val d = sqrt(d2)
        val nx: Double
        val ny: Double
        val depth: Double
        if (d > 1e-9) {
            depth = limit - d
            nx = vx / d
            ny = vy / d
        } else {
            val left = cx - x0
            val right = x1 - cx
            val top = cy - y0
            val bottom = y1 - cy
            val m = minOf(left, right, top, bottom)
            when (m) {
                top -> {
                    nx = 0.0
                    ny = -1.0
                }
                bottom -> {
                    nx = 0.0
                    ny = 1.0
                }
                left -> {
                    nx = -1.0
                    ny = 0.0
                }
                else -> {
                    nx = 1.0
                    ny = 0.0
                }
            }
            depth = limit + m
        }
        return if (circleIsA) Push(-nx, -ny, depth) else Push(nx, ny, depth)
    }

    private fun rectRect(
        ax0: Double,
        ay0: Double,
        ax1: Double,
        ay1: Double,
        bx0: Double,
        by0: Double,
        bx1: Double,
        by1: Double,
        gap: Double,
    ): Push? {
        val ox = min(ax1, bx1) - max(ax0, bx0) + gap
        val oy = min(ay1, by1) - max(ay0, by0) + gap
        if (ox <= 0 || oy <= 0) return null
        return if (ox < oy) Push(if (bx0 + bx1 >= ax0 + ax1) 1.0 else -1.0, 0.0, ox)
        else Push(0.0, if (by0 + by1 >= ay0 + ay1) 1.0 else -1.0, oy)
    }

    sealed interface Band {
        data object Any : Band

        data class AtOrBelow(val y: Double) : Band

        data class AtOrAbove(val y: Double) : Band

        fun allows(y: Double) =
            when (this) {
                Any -> true
                is AtOrBelow -> y >= this.y - .5
                is AtOrAbove -> y <= this.y + .5
            }
    }

    class Space(val config: MapLayoutConfig) {
        val obstacles = mutableListOf<MapFootprint>()

        private data class Shape(
            val outer: Double,
            val lx0: Double,
            val ly0: Double,
            val lx1: Double,
            val ly1: Double,
        ) {
            constructor(f: MapFootprint) : this(f.outer, f.lx0, f.ly0, f.lx1, f.ly1)
        }

        private data class ContactKey(val anchor: Shape, val item: Shape, val step: Int)

        private val contacts = mutableMapOf<ContactKey, Double>()

        private data class Ray(val anchor: Int, val ux: Double, val uy: Double, val t: Double)

        private data class Candidate(
            val score: Double,
            val cost: Double,
            val point: MapPoint,
            val ray: Ray? = null,
        )

        private val candidateOrder =
            compareBy<Candidate> { it.score }
                .thenBy { it.cost }
                .thenBy { it.point.x }
                .thenBy { it.point.y }

        fun findSpot(item: MapFootprint, band: Band = Band.Any): MapPoint {
            if (obstacles.isEmpty()) return MapPoint.zero
            search(item, band)?.let {
                return it
            }
            if (band != Band.Any)
                search(item, Band.Any)?.let {
                    return it
                }
            val box =
                obstacles.map { it.circleRect.union(it.labelRect) }.reduce { a, b -> a.union(b) }
            return snap(MapPoint(box.maxX + item.bound + config.gap + 2 * slack, box.midY))
        }

        private fun search(item: MapFootprint, band: Band): MapPoint? {
            var bx0 = Double.POSITIVE_INFINITY
            var by0 = bx0
            var bx1 = -bx0
            var by1 = -bx0
            var sx = 0.0
            var sy = 0.0
            var cx0 = bx0
            var cy0 = bx0
            var cx1 = bx1
            var cy1 = bx1
            for (p in obstacles) {
                val e = p.extent
                bx0 = min(bx0, p.center.x + e.minX)
                by0 = min(by0, p.center.y + e.minY)
                bx1 = max(bx1, p.center.x + e.maxX)
                by1 = max(by1, p.center.y + e.maxY)
                sx += p.center.x
                sy += p.center.y
                cx0 = min(cx0, p.center.x)
                cy0 = min(cy0, p.center.y)
                cx1 = max(cx1, p.center.x)
                cy1 = max(cy1, p.center.y)
            }
            val n = (obstacles.size + 1).toDouble()
            val weight = if (obstacles.size < 6) .5 else 0.0
            val target = snap(MapPoint((bx0 + bx1) / 2, (by0 + by1) / 2))
            val aspect = max(.2, config.aspect)
            val ie = item.extent
            fun score(c: MapPoint): Double {
                val x0 = min(bx0, c.x + ie.minX)
                val x1 = max(bx1, c.x + ie.maxX)
                val y0 = min(by0, c.y + ie.minY)
                val y1 = max(by1, c.y + ie.maxY)
                val size = max((x1 - x0) / aspect, y1 - y0)
                val mx = (min(cx0, c.x) + max(cx1, c.x)) / 2
                val my = (min(cy0, c.y) + max(cy1, c.y)) / 2
                val ux = ((sx + c.x) / n - mx) / aspect
                val uy = (sy + c.y) / n - my
                return rounded((size + weight * sqrt(ux * ux + uy * uy)) * 2) / 2
            }
            fun cost(c: MapPoint): Double {
                val dx = (c.x - target.x) / aspect
                val dy = c.y - target.y
                return dx * dx + dy * dy
            }
            val near = obstacles.map { it.outer + item.outer + config.gap - tolerance }
            val reach = obstacles.map { it.bound + item.bound + config.gap }
            fun circlesFree(c: MapPoint): Boolean =
                obstacles.indices.none { i ->
                    val dx = c.x - obstacles[i].center.x
                    val dy = c.y - obstacles[i].center.y
                    dx * dx + dy * dy < near[i] * near[i]
                }
            fun isFree(c: MapPoint): Boolean {
                if (!circlesFree(c)) return false
                val probe = item.copy(center = c)
                return obstacles.indices.none { i ->
                    val dx = c.x - obstacles[i].center.x
                    val dy = c.y - obstacles[i].center.y
                    dx * dx + dy * dy < reach[i] * reach[i] &&
                        overlaps(probe, obstacles[i], config.gap)
                }
            }
            val candidates = mutableListOf<Candidate>()
            val k = max(8, config.directions)
            if (band.allows(target.y))
                candidates.add(Candidate(score(target), cost(target), target))
            val itemShape = Shape(item)
            for ((index, anchor) in obstacles.withIndex()) {
                val tMin = anchor.outer + item.outer + config.gap
                val anchorShape = Shape(anchor)
                for (step in 0 until k) {
                    val angle = 2 * PI * step / k
                    val ux = cos(angle)
                    val uy = sin(angle)
                    val t =
                        contacts.getOrPut(ContactKey(anchorShape, itemShape, step)) {
                            contact(item, anchor, ux, uy, tMin, config.gap)
                        }
                    val c = snap(MapPoint(anchor.center.x + ux * t, anchor.center.y + uy * t))
                    if (band.allows(c.y) && circlesFree(c))
                        candidates.add(Candidate(score(c), cost(c), c, Ray(index, ux, uy, t)))
                }
            }
            for (i in obstacles.indices) {
                val a = obstacles[i]
                val ra = a.outer + item.outer + config.gap + slack
                for (j in i + 1 until obstacles.size) {
                    val b = obstacles[j]
                    val rb = b.outer + item.outer + config.gap + slack
                    val dx = b.center.x - a.center.x
                    val dy = b.center.y - a.center.y
                    val d = sqrt(dx * dx + dy * dy)
                    if (d <= 1e-6 || d >= ra + rb || d <= abs(ra - rb)) continue
                    val along = (ra * ra - rb * rb + d * d) / (2 * d)
                    val h = sqrt(max(0.0, ra * ra - along * along))
                    val mx = a.center.x + along * dx / d
                    val my = a.center.y + along * dy / d
                    for (sign in listOf(1.0, -1.0)) {
                        val c = snap(MapPoint(mx - sign * h * dy / d, my + sign * h * dx / d))
                        if (band.allows(c.y) && circlesFree(c))
                            candidates.add(Candidate(score(c), cost(c), c))
                    }
                }
            }
            candidates.sortWith(candidateOrder)
            fun march(ray: Ray): MapPoint? {
                val origin = obstacles[ray.anchor].center
                var t = ray.t
                repeat(4) {
                    val probe =
                        item.copy(center = MapPoint(origin.x + ray.ux * t, origin.y + ray.uy * t))
                    val blocker =
                        obstacles.firstOrNull { overlaps(probe, it, config.gap) }
                            ?: return snap(probe.center)
                    var lo = t
                    var hi = t + 2 * (blocker.bound + item.bound + config.gap) + 1
                    repeat(16) {
                        val mid = (lo + hi) / 2
                        val p =
                            item.copy(
                                center = MapPoint(origin.x + ray.ux * mid, origin.y + ray.uy * mid),
                            )
                        if (overlaps(p, blocker, config.gap)) lo = mid else hi = mid
                    }
                    t = hi + slack
                }
                return null
            }
            var index = 0
            var marches = 0
            while (index < candidates.size) {
                val candidate = candidates[index]
                if (isFree(candidate.point)) return candidate.point
                index++
                val ray = candidate.ray ?: continue
                if (marches >= 48) continue
                val moved = march(ray) ?: continue
                if (!band.allows(moved.y)) continue
                marches++
                val next = Candidate(score(moved), cost(moved), moved)
                var at = index
                while (
                    at < candidates.size && candidateOrder.compare(candidates[at], next) < 0
                ) at++
                candidates.add(at, next)
            }
            return null
        }
    }

    fun contact(
        item: MapFootprint,
        anchor: MapFootprint,
        ux: Double,
        uy: Double,
        tMin: Double,
        gap: Double,
    ): Double {
        val a = anchor.copy(center = MapPoint.zero)
        fun probe(t: Double) = item.copy(center = MapPoint(ux * t, uy * t))
        if (!overlaps(a, probe(tMin), gap)) return tMin + slack
        var lo = max(0.0, tMin - .05)
        var hi = max(lo + .1, a.bound + item.bound + gap + 1)
        repeat(16) {
            val mid = (lo + hi) / 2
            if (overlaps(a, probe(mid), gap)) lo = mid else hi = mid
        }
        return hi + slack
    }

    data class DotSlot(val offset: MapPoint, val angle: Double, val ring: Int)

    fun ringCapacity(ring: Int, radius: Double, config: MapLayoutConfig) =
        max(
            1,
            floor(
                    (radius + config.firstRing + ring * config.ringStep) * config.arc /
                        config.dotSpacing,
                )
                .toInt() + 1,
        )

    fun ringCount(dots: Int, radius: Double, config: MapLayoutConfig): Int {
        var remaining = dots
        var ring = 0
        while (remaining > 0) {
            remaining -= ringCapacity(ring, radius, config)
            ring++
        }
        return ring
    }

    fun dotSlots(count: Int, radius: Double, config: MapLayoutConfig): List<DotSlot> {
        val slots = mutableListOf<DotSlot>()
        var remaining = count
        var ring = 0
        val top = -PI / 2
        while (remaining > 0) {
            val r = radius + config.firstRing + ring * config.ringStep
            val capacity = ringCapacity(ring, radius, config)
            val n = min(capacity, remaining)
            for (j in 0 until n) {
                val angle =
                    if (ring == 0) {
                        val step =
                            if (n > 1) min(config.maxDotSpacing / r, config.arc / (n - 1)) else 0.0
                        top + step * ((n - 1) / 2.0 - j)
                    } else {
                        val step = if (capacity > 1) config.arc / (capacity - 1) else 0.0
                        if (ring % 2 == 1) top - config.arc / 2 + step * j
                        else top + config.arc / 2 - step * j
                    }
                slots.add(DotSlot(MapPoint(r * cos(angle), r * sin(angle)), angle, ring))
            }
            remaining -= n
            ring++
        }
        return slots
    }
}
