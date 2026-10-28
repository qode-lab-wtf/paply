package com.paply.thoughts.map

import java.time.Instant
import kotlin.math.*

internal object MapLines {
    data class Created(val topic: String, val date: Instant)

    private data class PairInfo(
        val a: String,
        val b: String,
        val newest: Instant,
        val count: Int = 1,
    )

    fun lines(
        links: List<MapLayoutInput.Link>,
        created: Map<String, Created>,
        dots: List<MapLayout.Dot>,
        dotIndex: Map<String, Int>,
        footprints: Map<String, MapFootprint>,
        config: MapLayoutConfig,
    ): List<MapLayout.Line> {
        val unique = mutableMapOf<String, PairInfo>()
        for (link in links) {
            if (link.from == link.to) continue
            val x = created[link.from] ?: continue
            val y = created[link.to] ?: continue
            val a = minOf(link.from, link.to)
            val b = maxOf(link.from, link.to)
            unique["$a|$b"] = PairInfo(a, b, maxOf(x.date, y.date))
        }
        val pairs =
            unique.values.sortedWith(
                compareByDescending<PairInfo> { it.newest }.thenBy { it.a }.thenBy { it.b },
            )
        val used = mutableMapOf<String, Int>()
        val edgePairs = mutableSetOf<String>()
        val result = mutableListOf<MapLayout.Line>()
        for (pair in pairs) {
            if (result.size >= config.maxLines) break
            if (
                (used[pair.a] ?: 0) >= config.maxLinksPerThought ||
                    (used[pair.b] ?: 0) >= config.maxLinksPerThought
            )
                continue
            val ta = created[pair.a]?.topic ?: continue
            val tb = created[pair.b]?.topic ?: continue
            val fa = footprints[ta] ?: continue
            val fb = footprints[tb] ?: continue
            val pa = dotIndex[pair.a]?.let { dots[it].position }
            val pb = dotIndex[pair.b]?.let { dots[it].position }
            val line: MapLayout.Line
            if (ta == tb) {
                if (pa == null || pb == null) continue
                val mx = (pa.x + pb.x) / 2 - fa.center.x
                val my = (pa.y + pb.y) / 2 - fa.center.y
                val len = sqrt(mx * mx + my * my)
                val ux = if (len > 1) mx / len else 0.0
                val uy = if (len > 1) my / len else -1.0
                val reach = fa.outer + 14
                line =
                    MapLayout.Line(
                        pair.a,
                        pair.b,
                        ta,
                        tb,
                        pa,
                        MapPoint(fa.center.x + ux * reach, fa.center.y + uy * reach),
                        pb,
                        false,
                        false,
                    )
            } else {
                val from = pa ?: edge(fa, pb ?: fb.center)
                val to = pb ?: edge(fb, pa ?: fa.center)
                if (pa == null || pb == null) {
                    val key =
                        if (pa == null && pb == null) "${minOf(ta,tb)}|${maxOf(ta,tb)}"
                        else if (pa == null) "$ta|${pair.b}" else "$tb|${pair.a}"
                    if (!edgePairs.add(key)) continue
                }
                val flip = ta > tb || (ta == tb && pair.a > pair.b)
                val s = if (flip) to else from
                val e = if (flip) from else to
                val control =
                    MapPoint(
                        (s.x + e.x) / 2 - (e.y - s.y) * .16,
                        (s.y + e.y) / 2 + (e.x - s.x) * .16,
                    )
                line =
                    MapLayout.Line(
                        pair.a,
                        pair.b,
                        ta,
                        tb,
                        from,
                        control,
                        to,
                        true,
                        pa == null || pb == null,
                    )
            }
            used[pair.a] = (used[pair.a] ?: 0) + 1
            used[pair.b] = (used[pair.b] ?: 0) + 1
            result.add(line)
        }
        return result
    }

    fun topicLines(
        links: List<MapLayoutInput.Link>,
        created: Map<String, Created>,
        footprints: Map<String, MapFootprint>,
        config: MapLayoutConfig,
    ): List<MapLayout.TopicLine> {
        val pairs = mutableMapOf<String, PairInfo>()
        val seen = mutableSetOf<String>()
        for (link in links) {
            if (link.from == link.to) continue
            val x = created[link.from] ?: continue
            val y = created[link.to] ?: continue
            if (x.topic == y.topic || MapLayout.isPseudo(x.topic) || MapLayout.isPseudo(y.topic))
                continue
            if (!seen.add("${minOf(link.from,link.to)}|${maxOf(link.from,link.to)}")) continue
            val a = minOf(x.topic, y.topic)
            val b = maxOf(x.topic, y.topic)
            val newest = maxOf(x.date, y.date)
            val key = "$a|$b"
            val old = pairs[key]
            pairs[key] =
                PairInfo(
                    a,
                    b,
                    if (old == null) newest else maxOf(old.newest, newest),
                    (old?.count ?: 0) + 1,
                )
        }
        val ranked =
            pairs.values
                .filter { it.count >= config.minTopicLinks }
                .sortedWith(
                    compareByDescending<PairInfo> { it.count }
                        .thenByDescending { it.newest }
                        .thenBy { it.a }
                        .thenBy { it.b },
                )
        val all = footprints.values.sortedBy { it.id }
        val perTopic = mutableMapOf<String, Int>()
        val result = mutableListOf<MapLayout.TopicLine>()
        for (pair in ranked) {
            if (result.size >= config.maxTopicLines) break
            if (
                (perTopic[pair.a] ?: 0) >= config.maxTopicLinesPerTopic ||
                    (perTopic[pair.b] ?: 0) >= config.maxTopicLinesPerTopic
            )
                continue
            val fa = footprints[pair.a] ?: continue
            val fb = footprints[pair.b] ?: continue
            val from = edge(fa, fb.center)
            val to = edge(fb, fa.center)
            val control =
                MapPoint(
                    (from.x + to.x) / 2 - (to.y - from.y) * .12,
                    (from.y + to.y) / 2 + (to.x - from.x) * .12,
                )
            if (crossesThird(from, control, to, setOf(pair.a, pair.b), all, config)) continue
            perTopic[pair.a] = (perTopic[pair.a] ?: 0) + 1
            perTopic[pair.b] = (perTopic[pair.b] ?: 0) + 1
            result.add(MapLayout.TopicLine(pair.a, pair.b, pair.count, from, control, to))
        }
        return result
    }

    fun crossesThird(
        from: MapPoint,
        control: MapPoint,
        to: MapPoint,
        except: Set<String>,
        all: List<MapFootprint>,
        config: MapLayoutConfig,
    ): Boolean {
        val points =
            (0..12).map {
                val t = it / 12.0
                val u = 1 - t
                MapPoint(
                    u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                    u * u * from.y + 2 * u * t * control.y + t * t * to.y,
                )
            }
        for (other in all) {
            if (other.id in except) continue
            val r = other.radius + 6
            val name =
                MapRect(
                        other.center.x + other.lx0,
                        other.center.y + other.ly0,
                        other.lx1 - other.lx0,
                        config.labelHeight,
                    )
                    .inset(4.0, 2.0)
            for (i in 0 until points.lastIndex) if (
                distance(other.center, points[i], points[i + 1]) < r ||
                    segment(points[i], points[i + 1], name)
            )
                return true
        }
        return false
    }

    private fun distance(c: MapPoint, p: MapPoint, q: MapPoint): Double {
        val vx = q.x - p.x
        val vy = q.y - p.y
        val len2 = vx * vx + vy * vy
        val t =
            if (len2 > 0) (((c.x - p.x) * vx + (c.y - p.y) * vy) / len2).coerceIn(0.0, 1.0) else 0.0
        return hypot(c.x - (p.x + vx * t), c.y - (p.y + vy * t))
    }

    private fun segment(p: MapPoint, q: MapPoint, r: MapRect): Boolean {
        var t0 = 0.0
        var t1 = 1.0
        val dx = q.x - p.x
        val dy = q.y - p.y
        for ((pk, qk) in
            listOf(
                -dx to p.x - r.minX,
                dx to r.maxX - p.x,
                -dy to p.y - r.minY,
                dy to r.maxY - p.y,
            )) {
            if (pk == 0.0) {
                if (qk < 0) return false
            } else {
                val t = qk / pk
                if (pk < 0) t0 = max(t0, t) else t1 = min(t1, t)
                if (t0 > t1) return false
            }
        }
        return true
    }

    private fun edge(f: MapFootprint, p: MapPoint): MapPoint {
        val dx = p.x - f.center.x
        val dy = p.y - f.center.y
        val d = sqrt(dx * dx + dy * dy)
        return if (d <= 1e-9) MapPoint(f.center.x, f.center.y - f.radius)
        else MapPoint(f.center.x + dx / d * f.radius, f.center.y + dy / d * f.radius)
    }
}
