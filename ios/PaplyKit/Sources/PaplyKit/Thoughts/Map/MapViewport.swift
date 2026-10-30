import CoreGraphics
import Foundation

// Freie Ansicht der Karte (Verschieben, Zoomen, Doppeltipp): reine Rechnung ohne Zustand.
//
// Die Kamera ist nur Ansicht. Sie ändert nie einen Anker und wird nicht gespeichert – die Kreise bleiben, wo sie
// sind; man schaut nur anders darauf.
//
// - Zoom: etwa 0,7- bis 3-fach der Übersicht, mindestens aber bis `maxZoomFloor` (dort sind Titel an den Punkten
//   lesbar), höchstens `maxZoomCap`.
// - Verschieben: Die Karte darf nicht ganz aus dem Bild. Mindestens die halbe Breite bzw. Höhe des sichtbaren
//   Bereichs zeigt Karte; ist die Karte kleiner, bleibt sie ganz im Bild.
// - Über die Grenzen hinaus geht es während der Geste nur gedämpft (Gummiband wie `UIScrollView`), beim
//   Loslassen federt die Ansicht zurück (`settled`).

/// Weltpunkt `center` liegt in der Mitte des sichtbaren Bereichs, `zoom` Bildschirmpunkte je Kartenpunkt.
public struct MapCamera: Sendable, Equatable {
    public var zoom: CGFloat
    public var center: CGPoint

    public init(zoom: CGFloat, center: CGPoint) {
        self.zoom = zoom
        self.center = center
    }

    public static let identity = MapCamera(zoom: 1, center: .zero)
}

public struct MapViewport: Sendable, Equatable {
    /// sichtbarer Bereich in Bildschirmpunkten; seine Mitte ist der Ankerpunkt der Kamera
    public var visible: CGRect
    /// Rahmen der Karte in Kartenpunkten (`MapLayout.bounds`)
    public var bounds: CGRect
    /// Maßstab der Übersicht (alles sichtbar)
    public var overviewZoom: CGFloat

    public static let minFactor: CGFloat = 0.7
    public static let maxFactor: CGFloat = 3
    /// so nah geht es immer (Titel an den Punkten lesbar), auch wenn die Übersicht klein ist
    public static let maxZoomFloor: CGFloat = 2.6
    public static let maxZoomCap: CGFloat = 5
    /// Rand rund um die Karte, der noch ins Bild darf (Bildschirmpunkte)
    public static let margin: CGFloat = 24

    public init(visible: CGRect, bounds: CGRect, overviewZoom: CGFloat) {
        self.visible = visible
        self.bounds = bounds
        self.overviewZoom = overviewZoom
    }

    public var minZoom: CGFloat { max(0.02, overviewZoom * Self.minFactor) }

    public var maxZoom: CGFloat {
        max(minZoom, min(Self.maxZoomCap, max(overviewZoom * Self.maxFactor, Self.maxZoomFloor)))
    }

    public var anchor: CGPoint { CGPoint(x: visible.midX, y: visible.midY) }

    // MARK: Umrechnen

    public func screen(_ p: CGPoint, _ camera: MapCamera) -> CGPoint {
        CGPoint(x: anchor.x + (p.x - camera.center.x) * camera.zoom, y: anchor.y + (p.y - camera.center.y) * camera.zoom)
    }

    public func world(_ s: CGPoint, _ camera: MapCamera) -> CGPoint {
        CGPoint(x: camera.center.x + (s.x - anchor.x) / camera.zoom, y: camera.center.y + (s.y - anchor.y) / camera.zoom)
    }

    // MARK: Gesten

    /// Neuer Maßstab, der Kartenpunkt unter `point` (Bildschirm) bleibt, wo er ist
    public func zoomed(_ camera: MapCamera, to zoom: CGFloat, around point: CGPoint) -> MapCamera {
        let w = world(point, camera)
        let z = max(0.0001, zoom)
        return MapCamera(zoom: z, center: CGPoint(x: w.x - (point.x - anchor.x) / z, y: w.y - (point.y - anchor.y) / z))
    }

    /// Mit dem Finger verschoben (Bildschirmpunkte)
    public func panned(_ camera: MapCamera, by translation: CGSize) -> MapCamera {
        MapCamera(zoom: camera.zoom, center: CGPoint(x: camera.center.x - translation.width / camera.zoom,
                                                     y: camera.center.y - translation.height / camera.zoom))
    }

    /// Erlaubte Mittelpunkte bei `zoom` (Kartenpunkte)
    public func centerRange(zoom: CGFloat) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let z = max(0.0001, zoom)
        let m = Self.margin / z
        let b = bounds.insetBy(dx: -m, dy: -m)
        func range(_ lo: CGFloat, _ hi: CGFloat, half: CGFloat) -> ClosedRange<CGFloat> {
            // mindestens `keep` der Karte bleibt im Bild: die halbe Sicht – oder die ganze Karte, wenn sie kleiner ist
            let keep = min(hi - lo, half)
            let a = lo + keep - half, e = hi - keep + half
            return a <= e ? a...e : (a + e) / 2...(a + e) / 2
        }
        return (range(b.minX, b.maxX, half: visible.width / 2 / z), range(b.minY, b.maxY, half: visible.height / 2 / z))
    }

    /// In die Grenzen (Zoom und Mittelpunkt)
    public func clamped(_ camera: MapCamera) -> MapCamera {
        let zoom = min(max(camera.zoom, minZoom), maxZoom)
        let r = centerRange(zoom: zoom)
        return MapCamera(zoom: zoom, center: CGPoint(x: Self.clamp(camera.center.x, r.x), y: Self.clamp(camera.center.y, r.y)))
    }

    /// Während der Geste: über die Grenzen hinaus nur gedämpft. `camera` ist die ungedämpfte Ansicht unter dem
    /// Finger, `point` der Mittelpunkt des Zooms.
    public func rubberBanded(_ camera: MapCamera, around point: CGPoint) -> MapCamera {
        var result = camera
        let lz = log(max(camera.zoom, 0.0001)), lo = log(minZoom), hi = log(maxZoom)
        // Zoom logarithmisch: eine Verdopplung über die Grenze wirkt wie ein Bildschirm beim Verschieben
        let dimension = CGFloat(log(2.0))
        var z = lz
        if lz > hi { z = hi + Self.band(lz - hi, dimension: dimension) }
        if lz < lo { z = lo - Self.band(lo - lz, dimension: dimension) }
        if z != lz { result = zoomed(result, to: exp(z), around: point) }
        let r = centerRange(zoom: result.zoom)
        result.center.x = Self.banded(result.center.x, r.x, dimension: visible.width / result.zoom)
        result.center.y = Self.banded(result.center.y, r.y, dimension: visible.height / result.zoom)
        return result
    }

    /// Nach dem Loslassen: zurück in die Grenzen – der Zoom um `point`, damit das Gegriffene bleibt
    public func settled(_ camera: MapCamera, around point: CGPoint) -> MapCamera {
        let zoom = min(max(camera.zoom, minZoom), maxZoom)
        return clamped(zoom == camera.zoom ? camera : zoomed(camera, to: zoom, around: point))
    }

    /// Schwung nach dem Loslassen: `velocity` in Bildschirmpunkten je Sekunde; ruhiger als eine Liste
    public func flung(_ camera: MapCamera, velocity: CGSize) -> MapCamera {
        let k: CGFloat = 0.3
        return clamped(panned(camera, by: CGSize(width: velocity.width * k, height: velocity.height * k)))
    }

    /// Doppeltipp: zweifach hinein um `point`. Bei starkem Zoom nil – zurück zur Übersicht.
    public func doubleTapped(_ camera: MapCamera, at point: CGPoint) -> MapCamera? {
        guard camera.zoom < maxZoom * 0.9 else { return nil }
        return clamped(zoomed(camera, to: min(camera.zoom * 2, maxZoom), around: point))
    }

    /// Weicht `camera` sichtbar von `home` ab? (Sonst zählt sie als Übersicht.)
    public func differs(_ camera: MapCamera, from home: MapCamera) -> Bool {
        abs(log(max(camera.zoom, 0.0001) / max(home.zoom, 0.0001))) > 0.02
            || hypot(camera.center.x - home.center.x, camera.center.y - home.center.y) * camera.zoom > 3
    }

    // MARK: Gummiband

    /// Gedämpfter Überstand (wie `UIScrollView`): wächst stetig, bleibt unter `dimension`
    public static func band(_ overshoot: CGFloat, dimension: CGFloat) -> CGFloat {
        guard overshoot > 0, dimension > 0 else { return 0 }
        return (1 - 1 / (overshoot * 0.55 / dimension + 1)) * dimension
    }

    static func banded(_ value: CGFloat, _ range: ClosedRange<CGFloat>, dimension: CGFloat) -> CGFloat {
        if value < range.lowerBound { return range.lowerBound - band(range.lowerBound - value, dimension: dimension) }
        if value > range.upperBound { return range.upperBound + band(value - range.upperBound, dimension: dimension) }
        return value
    }

    static func clamp(_ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
