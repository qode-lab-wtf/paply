package com.paply.thoughts.map

import kotlin.math.*

data class MapCamera(val zoom: Double, val center: MapPoint) {
    companion object {
        val identity = MapCamera(1.0, MapPoint.zero)
    }
}

/** Camera operations never alter the remembered topic anchors. */
data class MapViewport(val visible: MapRect, val bounds: MapRect, val overviewZoom: Double) {
    val minZoom
        get() = max(0.02, overviewZoom * minFactor)

    val maxZoom
        get() = max(minZoom, min(maxZoomCap, max(overviewZoom * maxFactor, maxZoomFloor)))

    val anchor
        get() = MapPoint(visible.midX, visible.midY)

    fun screen(p: MapPoint, camera: MapCamera) =
        MapPoint(
            anchor.x + (p.x - camera.center.x) * camera.zoom,
            anchor.y + (p.y - camera.center.y) * camera.zoom,
        )

    fun world(s: MapPoint, camera: MapCamera) =
        MapPoint(
            camera.center.x + (s.x - anchor.x) / camera.zoom,
            camera.center.y + (s.y - anchor.y) / camera.zoom,
        )

    fun zoomed(camera: MapCamera, zoom: Double, around: MapPoint): MapCamera {
        val w = world(around, camera)
        val z = max(0.0001, zoom)
        return MapCamera(
            z,
            MapPoint(w.x - (around.x - anchor.x) / z, w.y - (around.y - anchor.y) / z),
        )
    }

    fun panned(camera: MapCamera, translation: MapSize) =
        camera.copy(
            center =
                MapPoint(
                    camera.center.x - translation.width / camera.zoom,
                    camera.center.y - translation.height / camera.zoom,
                ),
        )

    data class CenterRange(
        val x: ClosedFloatingPointRange<Double>,
        val y: ClosedFloatingPointRange<Double>,
    )

    fun centerRange(zoom: Double): CenterRange {
        val z = max(0.0001, zoom)
        val b = bounds.inset(-margin / z, -margin / z)
        fun range(lo: Double, hi: Double, half: Double): ClosedFloatingPointRange<Double> {
            val keep = min(hi - lo, half)
            val a = lo + keep - half
            val e = hi - keep + half
            return if (a <= e) a..e else (a + e) / 2..(a + e) / 2
        }
        return CenterRange(
            range(b.minX, b.maxX, visible.width / 2 / z),
            range(b.minY, b.maxY, visible.height / 2 / z),
        )
    }

    fun clamped(camera: MapCamera): MapCamera {
        val z = camera.zoom.coerceIn(minZoom, maxZoom)
        val r = centerRange(z)
        return MapCamera(z, MapPoint(camera.center.x.coerceIn(r.x), camera.center.y.coerceIn(r.y)))
    }

    fun rubberBanded(camera: MapCamera, around: MapPoint): MapCamera {
        val lz = ln(max(camera.zoom, 0.0001))
        val lo = ln(minZoom)
        val hi = ln(maxZoom)
        val z =
            when {
                lz > hi -> hi + band(lz - hi, ln(2.0))
                lz < lo -> lo - band(lo - lz, ln(2.0))
                else -> lz
            }
        val result = if (z != lz) zoomed(camera, exp(z), around) else camera
        val r = centerRange(result.zoom)
        return result.copy(
            center =
                MapPoint(
                    banded(result.center.x, r.x, visible.width / result.zoom),
                    banded(result.center.y, r.y, visible.height / result.zoom),
                ),
        )
    }

    fun settled(camera: MapCamera, around: MapPoint): MapCamera {
        val z = camera.zoom.coerceIn(minZoom, maxZoom)
        return clamped(if (z == camera.zoom) camera else zoomed(camera, z, around))
    }

    fun flung(camera: MapCamera, velocity: MapSize) =
        clamped(panned(camera, MapSize(velocity.width * .3, velocity.height * .3)))

    fun doubleTapped(camera: MapCamera, at: MapPoint): MapCamera? =
        if (camera.zoom >= maxZoom * .9) null
        else clamped(zoomed(camera, min(camera.zoom * 2, maxZoom), at))

    fun differs(camera: MapCamera, home: MapCamera) =
        abs(ln(max(camera.zoom, .0001) / max(home.zoom, .0001))) > .02 ||
            hypot(camera.center.x - home.center.x, camera.center.y - home.center.y) * camera.zoom >
                3

    companion object {
        const val minFactor = .7
        const val maxFactor = 3.0
        const val maxZoomFloor = 2.6
        const val maxZoomCap = 5.0
        const val margin = 24.0

        fun band(overshoot: Double, dimension: Double) =
            if (overshoot <= 0 || dimension <= 0) 0.0
            else (1 - 1 / (overshoot * .55 / dimension + 1)) * dimension

        internal fun banded(
            value: Double,
            range: ClosedFloatingPointRange<Double>,
            dimension: Double,
        ) =
            when {
                value < range.start -> range.start - band(range.start - value, dimension)
                value > range.endInclusive ->
                    range.endInclusive + band(value - range.endInclusive, dimension)
                else -> value
            }
    }
}
