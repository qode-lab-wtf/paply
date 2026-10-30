package com.paply.thoughts

import com.paply.thoughts.map.*
import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class MapViewportTests {
    private val viewport =
        MapViewport(MapRect(0.0, 120.0, 390.0, 560.0), MapRect(-300.0, -400.0, 600.0, 800.0), .6)

    private fun close(a: Double, b: Double, eps: Double = 1e-6) = assertEquals(a, b, eps)

    @Test
    fun zoomLimits() {
        close(.42, viewport.minZoom)
        close(2.6, viewport.maxZoom)
        close(3.6, viewport.copy(overviewZoom = 1.2).maxZoom)
        close(5.0, viewport.copy(overviewZoom = 1.8).maxZoom)
        assertTrue(
            viewport.minZoom < viewport.overviewZoom && viewport.overviewZoom < viewport.maxZoom,
        )
    }

    @Test
    fun zoomKeepsPointUnderFinger() {
        val camera = MapCamera(.6, MapPoint(10.0, -20.0))
        val finger = MapPoint(80.0, 300.0)
        val before = viewport.world(finger, camera)
        val after = viewport.zoomed(camera, 1.7, finger)
        val p = viewport.screen(before, after)
        close(p.x, finger.x, 1e-9)
        close(p.y, finger.y, 1e-9)
        close(1.7, after.zoom)
    }

    @Test
    fun panFollowsFinger() {
        val camera = MapCamera(2.0, MapPoint.zero)
        val world = MapPoint(5.0, 5.0)
        val moved = viewport.panned(camera, MapSize(40.0, -10.0))
        val a = viewport.screen(world, camera)
        val b = viewport.screen(world, moved)
        close(40.0, b.x - a.x)
        close(-10.0, b.y - a.y)
    }

    @Test
    fun centerLimitsKeepMapVisible() {
        for (zoom in listOf(viewport.minZoom, viewport.overviewZoom, 1.0, viewport.maxZoom)) {
            val r = viewport.centerRange(zoom)
            for (x in listOf(r.x.start, r.x.endInclusive)) for (y in
                listOf(r.y.start, r.y.endInclusive)) {
                val camera = MapCamera(zoom, MapPoint(x, y))
                val origin = viewport.screen(MapPoint(viewport.bounds.x, viewport.bounds.y), camera)
                val map =
                    MapRect(
                        origin.x,
                        origin.y,
                        viewport.bounds.width * zoom,
                        viewport.bounds.height * zoom,
                    )
                val shownW =
                    min(map.maxX, viewport.visible.maxX) - max(map.minX, viewport.visible.minX)
                val shownH =
                    min(map.maxY, viewport.visible.maxY) - max(map.minY, viewport.visible.minY)
                assertTrue(shownW >= 0 && shownH >= 0)
                assertTrue(
                    shownW >= min(map.width, viewport.visible.width / 2) - MapViewport.margin - .01,
                )
                assertTrue(
                    shownH >=
                        min(map.height, viewport.visible.height / 2) - MapViewport.margin - .01,
                )
            }
        }
        val far = viewport.clamped(MapCamera(1.0, MapPoint(5000.0, -5000.0)))
        val r = viewport.centerRange(1.0)
        close(r.x.endInclusive, far.center.x)
        close(r.y.start, far.center.y)
    }

    @Test
    fun rubberBand() {
        val r = viewport.centerRange(1.0)
        var last = r.x.endInclusive
        for (over in 10..600 step 10) {
            val raw = MapCamera(1.0, MapPoint(r.x.endInclusive + over, 0.0))
            val shown = viewport.rubberBanded(raw, viewport.anchor)
            assertTrue(shown.center.x > last)
            assertTrue(shown.center.x - r.x.endInclusive < over)
            assertTrue(shown.center.x - r.x.endInclusive < viewport.visible.width)
            last = shown.center.x
        }
        val inside = MapCamera(1.0, MapPoint(r.x.start + 1, 0.0))
        assertEquals(inside, viewport.rubberBanded(inside, viewport.anchor))
        val finger = MapPoint(120.0, 400.0)
        val raw = viewport.zoomed(MapCamera.identity, viewport.maxZoom * 2, finger)
        val banded = viewport.rubberBanded(raw, finger)
        assertTrue(banded.zoom > viewport.maxZoom && banded.zoom < viewport.maxZoom * 2)
        val settled = viewport.settled(banded, finger)
        close(viewport.maxZoom, settled.zoom)
        assertEquals(settled, viewport.clamped(settled))
        close(0.0, MapViewport.band(0.0, 100.0))
        assertTrue(MapViewport.band(1e9, 100.0) < 100)
    }

    @Test
    fun doubleTap() {
        val finger = MapPoint(200.0, 300.0)
        var camera = MapCamera(viewport.overviewZoom, MapPoint.zero)
        var steps = 0
        while (true) {
            val next = viewport.doubleTapped(camera, finger) ?: break
            assertTrue(next.zoom > camera.zoom && next.zoom <= viewport.maxZoom)
            camera = next
            steps++
            if (steps > 6) break
        }
        assertTrue(steps in 2..3)
        assertTrue(camera.zoom >= viewport.maxZoom * .9)
    }

    @Test
    fun differs() {
        val home = MapCamera(.6, MapPoint(3.0, 4.0))
        assertFalse(viewport.differs(home, home))
        assertFalse(viewport.differs(MapCamera(.605, MapPoint(4.0, 4.0)), home))
        assertTrue(viewport.differs(MapCamera(.7, home.center), home))
        assertTrue(viewport.differs(MapCamera(.6, MapPoint(30.0, 4.0)), home))
    }

    @Test
    fun fling() {
        val camera = MapCamera.identity
        val flung = viewport.flung(camera, MapSize(-20000.0, 0.0))
        assertEquals(flung, viewport.clamped(flung))
        assertTrue(flung.center.x > camera.center.x)
    }
}
