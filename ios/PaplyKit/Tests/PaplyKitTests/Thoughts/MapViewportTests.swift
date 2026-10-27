import CoreGraphics
import Foundation
import Testing
@testable import PaplyKit

@Suite("Gedanken-Landkarte: freie Ansicht")
struct MapViewportTests {
    /// iPhone im Hochformat: sichtbarer Teil zwischen Kopf und Leiste, Karte etwas größer als der Bildschirm
    private let viewport = MapViewport(visible: CGRect(x: 0, y: 120, width: 390, height: 560),
                                       bounds: CGRect(x: -300, y: -400, width: 600, height: 800), overviewZoom: 0.6)

    private func close(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool { abs(a - b) <= eps }

    @Test("Zoomgrenzen: 0,7- bis 3-fach der Übersicht, mindestens bis 2,6, höchstens 5")
    func zoomLimits() {
        #expect(close(viewport.minZoom, 0.42))
        #expect(close(viewport.maxZoom, 2.6)) // 3 × 0,6 = 1,8 → mindestens 2,6
        var small = viewport
        small.overviewZoom = 1.2
        #expect(close(small.maxZoom, 3.6))
        small.overviewZoom = 1.8
        #expect(close(small.maxZoom, 5))
        #expect(viewport.minZoom < viewport.overviewZoom && viewport.overviewZoom < viewport.maxZoom)
    }

    @Test("Zoom um einen Punkt: der Kartenpunkt unter dem Finger bleibt")
    func zoomKeepsPointUnderFinger() {
        let camera = MapCamera(zoom: 0.6, center: CGPoint(x: 10, y: -20))
        let finger = CGPoint(x: 80, y: 300)
        let before = viewport.world(finger, camera)
        let after = viewport.zoomed(camera, to: 1.7, around: finger)
        let p = viewport.screen(before, after)
        #expect(close(p.x, finger.x, 1e-9) && close(p.y, finger.y, 1e-9))
        #expect(after.zoom == 1.7)
    }

    @Test("Verschieben folgt dem Finger")
    func panFollowsFinger() {
        let camera = MapCamera(zoom: 2, center: .zero)
        let world = CGPoint(x: 5, y: 5)
        let moved = viewport.panned(camera, by: CGSize(width: 40, height: -10))
        let a = viewport.screen(world, camera), b = viewport.screen(world, moved)
        #expect(close(b.x - a.x, 40) && close(b.y - a.y, -10))
    }

    @Test("Grenzen: Die Karte bleibt mindestens zur Hälfte im Bild – kleine Karten ganz")
    func centerLimitsKeepMapVisible() {
        for zoom in [viewport.minZoom, viewport.overviewZoom, 1, viewport.maxZoom] {
            let r = viewport.centerRange(zoom: zoom)
            for x in [r.x.lowerBound, r.x.upperBound] {
                for y in [r.y.lowerBound, r.y.upperBound] {
                    let camera = MapCamera(zoom: zoom, center: CGPoint(x: x, y: y))
                    let map = CGRect(origin: viewport.screen(viewport.bounds.origin, camera),
                                     size: CGSize(width: viewport.bounds.width * zoom, height: viewport.bounds.height * zoom))
                    let shown = map.intersection(viewport.visible)
                    #expect(!shown.isNull)
                    let needW = min(map.width, viewport.visible.width / 2) - MapViewport.margin - 0.01
                    let needH = min(map.height, viewport.visible.height / 2) - MapViewport.margin - 0.01
                    #expect(shown.width >= needW, "Breite bei Zoom \(zoom)")
                    #expect(shown.height >= needH, "Höhe bei Zoom \(zoom)")
                }
            }
        }
        // weit hinausgeschoben → zurück in die Grenzen
        let far = viewport.clamped(MapCamera(zoom: 1, center: CGPoint(x: 5_000, y: -5_000)))
        let r = viewport.centerRange(zoom: 1)
        #expect(far.center.x == r.x.upperBound && far.center.y == r.y.lowerBound)
    }

    @Test("Gummiband: über die Grenze nur gedämpft, stetig, beim Loslassen zurück")
    func rubberBand() {
        // Verschieben
        let r = viewport.centerRange(zoom: 1)
        var last: CGFloat = r.x.upperBound
        for over in stride(from: CGFloat(10), through: 600, by: 10) {
            let raw = MapCamera(zoom: 1, center: CGPoint(x: r.x.upperBound + over, y: 0))
            let shown = viewport.rubberBanded(raw, around: viewport.anchor)
            #expect(shown.center.x > last) // wächst weiter …
            #expect(shown.center.x - r.x.upperBound < over) // … aber gedämpft
            #expect(shown.center.x - r.x.upperBound < viewport.visible.width) // nie mehr als ein Bildschirm
            last = shown.center.x
        }
        // innerhalb: unverändert
        let inside = MapCamera(zoom: 1, center: CGPoint(x: r.x.lowerBound + 1, y: 0))
        #expect(viewport.rubberBanded(inside, around: viewport.anchor) == inside)
        // Zoom über die Grenze: gedämpft, der Punkt unter den Fingern bleibt
        let finger = CGPoint(x: 120, y: 400)
        let raw = viewport.zoomed(MapCamera(zoom: 1, center: .zero), to: viewport.maxZoom * 2, around: finger)
        let banded = viewport.rubberBanded(raw, around: finger)
        #expect(banded.zoom > viewport.maxZoom && banded.zoom < viewport.maxZoom * 2)
        // Loslassen: zurück auf den größten Zoom
        let settled = viewport.settled(banded, around: finger)
        #expect(close(settled.zoom, viewport.maxZoom))
        #expect(viewport.clamped(settled) == settled)
        #expect(MapViewport.band(0, dimension: 100) == 0)
        #expect(MapViewport.band(1e9, dimension: 100) < 100)
    }

    @Test("Doppeltipp: zweifach hinein, bei starkem Zoom zurück zur Übersicht")
    func doubleTap() {
        let finger = CGPoint(x: 200, y: 300)
        var camera = MapCamera(zoom: viewport.overviewZoom, center: .zero)
        var steps = 0
        while let next = viewport.doubleTapped(camera, at: finger) {
            #expect(next.zoom > camera.zoom)
            #expect(next.zoom <= viewport.maxZoom)
            camera = next
            steps += 1
            if steps > 6 { break }
        }
        #expect(steps >= 2 && steps <= 3)
        #expect(camera.zoom >= viewport.maxZoom * 0.9)
    }

    @Test("Übersicht erkennen: winzige Abweichungen zählen nicht")
    func differs() {
        let home = MapCamera(zoom: 0.6, center: CGPoint(x: 3, y: 4))
        #expect(!viewport.differs(home, from: home))
        #expect(!viewport.differs(MapCamera(zoom: 0.605, center: CGPoint(x: 4, y: 4)), from: home))
        #expect(viewport.differs(MapCamera(zoom: 0.7, center: home.center), from: home))
        #expect(viewport.differs(MapCamera(zoom: 0.6, center: CGPoint(x: 30, y: 4)), from: home))
    }

    @Test("Schwung: landet in den Grenzen")
    func fling() {
        let camera = MapCamera(zoom: 1, center: .zero)
        let flung = viewport.flung(camera, velocity: CGSize(width: -20_000, height: 0))
        #expect(viewport.clamped(flung) == flung)
        #expect(flung.center.x > camera.center.x) // nach links gewischt → Karte zeigt weiter rechts
    }
}
