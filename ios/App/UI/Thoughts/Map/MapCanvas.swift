import PaplyKit
import SwiftUI
import UIKit

// Zeichnet die Karte mit `Canvas` (Metal über `drawingGroup`): Punktraster, Linien, leuchtende Kreise mit
// Lucide-Symbol oder Themenbild, Punkte, Beschriftungen, Flüge aus dem Eingang. Kamera, verdeckte Höhe unten und
// Fokus sind animierbar (SwiftUI interpoliert sie Bild für Bild); Datenwechsel und Flüge laufen zeitgesteuert über
// `MapMotion`. Was gezeichnet wurde, landet in `MapHitBox` – Tipps treffen genau das Sichtbare.
//
// Ruhe in der Übersicht: Punkte erst ab Maßstab 1 (darunter ein feiner Bogen, wo sie im Fokus liegen), wenige
// zarte Themen-Linien in einer Mischfarbe. „Ohne Thema“ ist ein hohler, gestrichelter Ring ohne Schein, der
// Sammelkreis „Weitere Themen“ ein feiner Ring mit drei kleinen Kreisen. Schrift trägt einen Hof in der
// Grundfarbe, Linien laufen darunter. Titel an den Punkten: im Fokus die drei neuesten und offene Aufgaben, beim
// Hineinzoomen abgestuft mehr (neueste zuerst, `titleZoom`). Schrift wächst nie mit dem Zoom – sie bleibt lesbar.

/// Bildschirmbereich der Karte: ganze Fläche, oben verdeckt (Statusleiste, Kopf), unten verdeckt (Panel).
struct MapStage: Equatable {
    var size: CGSize
    var top: CGFloat
    var bottom: CGFloat

    var visible: CGRect {
        CGRect(x: 0, y: top, width: size.width, height: max(1, size.height - top - bottom))
    }

    var anchor: CGPoint { CGPoint(x: visible.midX, y: visible.midY) }
}

/// Themenbilder, einmal für die Zeichenfläche aufgelöst und wiederverwendet. Behalten wird nur, was zuletzt
/// gezeichnet wurde.
final class MapImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ObjectIdentifier: (image: UIImage, resolved: GraphicsContext.ResolvedImage)] = [:]
    private var used: Set<ObjectIdentifier> = []

    func resolved(_ image: UIImage, in context: GraphicsContext) -> GraphicsContext.ResolvedImage {
        let key = ObjectIdentifier(image)
        lock.lock()
        defer { lock.unlock() }
        used.insert(key)
        if let entry = entries[key] { return entry.resolved }
        let resolved = context.resolve(Image(uiImage: image))
        // das Bild bleibt gehalten, solange es im Speicher steht – so kann keine andere Adresse den Schlüssel erben
        entries[key] = (image, resolved)
        return resolved
    }

    /// nach jedem Bild: nicht Gezeichnetes vergessen
    func sweep() {
        lock.lock()
        if entries.count != used.count { entries = entries.filter { used.contains($0.key) } }
        used.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

/// Zuletzt Gezeichnetes in Bildschirmpunkten (für Tipps). Wird beim Zeichnen geschrieben.
final class MapHitBox: @unchecked Sendable {
    struct Topic {
        var id: String
        var center: CGPoint
        var radius: CGFloat
        var label: CGRect?
    }

    struct Dot {
        var id: String
        var topicID: String
        var center: CGPoint
        /// Abstand zum Nachbarpunkt auf dem Bogen (∞ = einzeln)
        var spacing: CGFloat
    }

    struct Title {
        var id: String
        var rect: CGRect
    }

    struct Snapshot {
        var topics: [Topic] = []
        var dots: [Dot] = []
        var titles: [Title] = []
    }

    private let lock = NSLock()
    private var value = Snapshot()

    func store(_ snapshot: Snapshot) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - Bild

/// Ein Bild der Karte (Bildschirmpunkte), aus Szene, Übergang und Kamera berechnet.
struct MapFrame {
    struct Bubble {
        var id: String
        var center: CGPoint
        var radius: CGFloat
        /// Oberkante des Beschriftungsfelds
        var labelTop: CGFloat
        var alpha: CGFloat
        var scale: CGFloat
        /// 0 = normal, 1 = tritt zurück (anderes Thema im Fokus)
        var dim: CGFloat
        var focused: Bool
        var info: MapTopicInfo?
        var style: MapStyle.Bubble
        /// Titel unter dem Kreis (wenige Gedanken), höchstens so viele, wie Platz reserviert ist
        var titleLines: Int = 0
        /// Übersicht unter Maßstab 1: statt der Punkte ein feiner Bogen, wo sie im Fokus liegen
        var arc: Arc?
        /// Nachleuchten nach einer Landung (0 … 1)
        var glow: CGFloat?
    }

    /// Punkt auf dem Weg von der Kugel zu seinem Kreis
    struct Flight {
        var id: String
        var from: CGPoint
        var to: CGPoint
        /// 0 … 1 in der Luft, danach kurz nachleuchtend (bis `flightAfterglow`)
        var progress: CGFloat
        var color: Color
        /// Größe des Punkts am Ziel
        var endRadius: CGFloat
    }

    struct Arc {
        var radius: CGFloat
        var from: CGFloat
        var to: CGFloat
        var alpha: CGFloat
    }

    struct Dot {
        var id: String
        var topicID: String
        var center: CGPoint
        var radius: CGFloat
        var angle: CGFloat
        var rank: Int
        var alpha: CGFloat
        var appear: CGFloat?
        var info: MapDotInfo?
        var color: Color
        var focused: Bool
        var spacing: CGFloat
        /// Titel daneben (0 = keiner, sonst Deckkraft): im Fokus die neuesten, beim Zoomen abgestuft mehr
        var title: CGFloat = 0
    }

    struct Line {
        var id: String
        var from: CGPoint
        var control: CGPoint
        var to: CGPoint
        var colors: (Color, Color)
        var width: CGFloat
        var alpha: CGFloat
    }

    var bubbles: [Bubble] = []
    var dots: [Dot] = []
    var lines: [Line] = []
    var flights: [Flight] = []
    var few = false
    var labelAlpha: CGFloat = 1
    var focusLevel: CGFloat = 0
    var focusID: String?
}

struct MapCanvas: View, @preconcurrency Animatable {
    var scene: MapScene
    var previous: MapScene?
    /// Fortschritt des Datenwechsels 0 … 1
    var progress: CGFloat
    /// Einblenden neuer Punkte/Kreise: Schlüssel → 0 … 1
    var appear: [String: CGFloat]
    var camera: MapCamera
    var stage: MapStage
    var focusLevel: CGFloat
    /// zuletzt fokussiertes Thema (bleibt beim Herauszoomen gesetzt, damit es weich zurücktritt)
    var focusID: String?
    var style: MapStyle
    var reduceMotion: Bool
    var hitBox: MapHitBox
    var images: MapImageCache
    /// Punkte in der Luft (von `orb` aus) und was noch nicht gelandet ist
    var flights: [MapMotion.Flight] = []
    var unlanded: (ids: Set<String>, perTopic: [String: Int]) = ([], [:])
    /// Nachleuchten der Kreise nach einer Landung
    var glows: [String: CGFloat] = [:]
    /// Mittelpunkt der Kugel (Bildschirm), Start der Flüge
    var orb: CGPoint?
    var onTopic: (String) -> Void
    var onThought: (String) -> Void

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(AnimatablePair(log(max(camera.zoom, 0.0001)), camera.center.x),
                           AnimatablePair(camera.center.y, AnimatablePair(stage.bottom, focusLevel)))
        }
        set {
            camera.zoom = exp(newValue.first.first)
            camera.center.x = newValue.first.second
            camera.center.y = newValue.second.first
            stage.bottom = newValue.second.second.first
            focusLevel = newValue.second.second.second
        }
    }

    var body: some View {
        let frame = makeFrame()
        let size = stage.size
        let visible = stage.visible
        let grid = gridShading()
        let hitBox = hitBox
        let images = images
        let style = style
        ZStack {
            Canvas { context, _ in
                MapPainter(frame: frame, size: size, visible: visible, style: style, grid: grid, reduceMotion: reduceMotion,
                           images: images)
                    .draw(&context, hitBox: hitBox)
            } symbols: {
                symbols(frame)
            }
            .drawingGroup()
            .accessibilityHidden(true)
            accessibility(frame)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Kamera

    private func screen(_ p: CGPoint) -> CGPoint {
        let a = stage.anchor
        return CGPoint(x: a.x + (p.x - camera.center.x) * camera.zoom, y: a.y + (p.y - camera.center.y) * camera.zoom)
    }

    private func gridShading() -> MapPainter.Grid {
        // Raster in Weltpunkten (24 · 2^k), so gewählt, dass der Abstand am Bildschirm in [18, 36) liegt;
        // die feinere Stufe blendet weich ein, die gröbere entsprechend aus
        var spacing = MapStyle.gridTile * camera.zoom
        var guardSteps = 0
        while spacing < 18, guardSteps < 20 { spacing *= 2; guardSteps += 1 }
        while spacing >= 36, guardSteps < 40 { spacing /= 2; guardSteps += 1 }
        let fine = min(1, max(0, (spacing - 18) / 18))
        let eased = fine * fine * (3 - 2 * fine)
        return MapPainter.Grid(image: style.gridImage(), origin: screen(.zero), spacing: spacing, fineAlpha: eased)
    }

    // MARK: Bild berechnen

    private func makeFrame() -> MapFrame {
        var frame = MapFrame()
        frame.few = scene.few
        frame.focusLevel = focusLevel
        let focus = focusID.flatMap { scene.layout.bubble($0) != nil ? $0 : nil }
        frame.focusID = focus
        frame.labelAlpha = 1 - focusLevel
        let p = previous == nil ? 1 : progress
        let move = reduceMotion ? 1 : p // bei reduzierter Bewegung springen Plätze, nur Deckkraft blendet
        let zoom = camera.zoom

        // Kreise
        var styles: [String: MapStyle.Bubble] = [:]
        func styleOf(_ id: String) -> MapStyle.Bubble {
            if let s = styles[id] { return s }
            let s = style.bubble(id)
            styles[id] = s
            return s
        }
        // Punkte gehören in den Fokus: in der Übersicht erst ab Maßstab 1, darunter nur ein feiner Bogen.
        // Bei sehr wenigen Gedanken stehen ihre Titel unter den Kreisen – dann bleiben die Punkte.
        let dotsShown = scene.few ? 1 : Self.dotFade(zoom)
        var arcs: [String: (from: CGFloat, to: CGFloat)] = [:]
        if dotsShown < 0.99 {
            for dot in scene.layout.dots {
                let span = arcs[dot.topicID] ?? (dot.angle, dot.angle)
                arcs[dot.topicID] = (min(span.from, dot.angle), max(span.to, dot.angle))
            }
        }
        let config = MapLayoutConfig()
        let oldBubbles = Dictionary((previous?.layout.bubbles ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var worldBubble: [String: MapLayout.Bubble] = [:]
        for bubble in scene.layout.bubbles {
            var b = bubble
            var alpha: CGFloat = 1, scale: CGFloat = 1
            if let old = oldBubbles[bubble.id], move < 1 {
                b.center = lerp(old.center, bubble.center, move)
                b.radius = lerp(old.radius, bubble.radius, move)
                b.outerRadius = lerp(old.outerRadius, bubble.outerRadius, move)
            } else if previous != nil || appear["topic:" + bubble.id] != nil, oldBubbles[bubble.id] == nil {
                if let a = appear["topic:" + bubble.id] {
                    // neuer Kreis: wächst an seinem Anker aus dem Nichts (weiche Feder), nichts sonst bewegt sich
                    scale = reduceMotion ? 1 : Self.grow(a)
                    alpha = reduceMotion ? min(1, a * 3) : min(1, a * 5)
                } else {
                    alpha = p
                }
            }
            worldBubble[bubble.id] = b
            let dim = focus != nil && bubble.id != focus ? focusLevel : 0
            var arc: MapFrame.Arc?
            if let span = arcs[bubble.id], span.to - span.from > 0.2 {
                let hidden = bubble.id == focus ? max(0, 1 - dotsShown - focusLevel) : 1 - dotsShown
                arc = MapFrame.Arc(radius: (b.radius + config.firstRing) * zoom, from: span.from, to: span.to,
                                   alpha: hidden * (style.dark ? 0.22 : 0.2))
            }
            var info = scene.topics[bubble.id]
            if let waiting = unlanded.perTopic[bubble.id], waiting > 0, let shown = info?.count {
                // die Zahl am Kreis steigt erst mit der Landung
                info?.count = max(1, shown - waiting)
            }
            frame.bubbles.append(MapFrame.Bubble(
                id: b.id, center: screen(b.center), radius: b.radius * zoom,
                labelTop: screen(CGPoint(x: b.center.x, y: b.center.y + b.radius + 8)).y,
                alpha: alpha, scale: scale, dim: dim, focused: bubble.id == focus,
                info: info, style: styleOf(bubble.id), titleLines: bubble.titleLines, arc: arc,
                glow: reduceMotion ? nil : glows[bubble.id]))
        }
        if let previous, p < 1 {
            let current = Set(scene.layout.bubbles.map(\.id))
            for old in previous.layout.bubbles where !current.contains(old.id) {
                worldBubble[old.id] = worldBubble[old.id] ?? old
                frame.bubbles.append(MapFrame.Bubble(
                    id: old.id, center: screen(old.center), radius: old.radius * zoom,
                    labelTop: screen(CGPoint(x: old.center.x, y: old.center.y + old.radius + 8)).y,
                    alpha: 1 - p, scale: 1, dim: 0, focused: false, info: previous.topics[old.id], style: styleOf(old.id)))
            }
        }

        // Punkte
        let overviewDot = min(3.4, max(1.5, 0.27 * 11 * zoom))
        let focusDot = min(6.2, max(3.4, 0.24 * 11 * zoom))
        var spacing: [String: CGFloat] = [:]
        for bubble in scene.layout.bubbles {
            let own = scene.layout.dots.filter { $0.topicID == bubble.id }.sorted { $0.rank < $1.rank }
            if own.count >= 2 {
                spacing[bubble.id] = hypot(own[0].position.x - own[1].position.x, own[0].position.y - own[1].position.y) * zoom
            } else {
                spacing[bubble.id] = .infinity
            }
        }
        let oldDots = Dictionary((previous?.layout.dots ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Ziele der Flüge (Punkte, die noch nicht gelandet sind, werden nicht gezeichnet)
        var targets: [String: (point: CGPoint, radius: CGFloat)] = [:]
        let flying = Set(flights.map(\.id))
        let onScreen = CGRect(origin: .zero, size: stage.size).insetBy(dx: -40, dy: -40)
        let focusTitle = min(1, max(0, (focusLevel - 0.35) / 0.65))
        for dot in scene.layout.dots {
            var position = dot.position
            var alpha: CGFloat = 1
            var appearing: CGFloat?
            if let old = oldDots[dot.id], move < 1 {
                position = lerp(old.position, dot.position, move)
            } else if previous != nil || appear[dot.id] != nil, oldDots[dot.id] == nil {
                if let a = appear[dot.id] { appearing = a } else { alpha = p }
            }
            let isFocus = dot.topicID == focus
            let dim = focus != nil && !isFocus ? focusLevel : 0
            let radius = isFocus ? lerp(overviewDot, focusDot, focusLevel) : overviewDot
            let shown = isFocus ? max(dotsShown, focusLevel) : dotsShown
            if flying.contains(dot.id) || unlanded.ids.contains(dot.id) {
                targets[dot.id] = (position, shown > 0.5 ? radius : 2.4)
                if unlanded.ids.contains(dot.id) { continue }
            }
            guard shown > 0.01 else { continue }
            let center = screen(position)
            let info = scene.dots[dot.id]
            // Titel: im Fokus die drei neuesten und offene Aufgaben; beim Hineinzoomen abgestuft mehr
            var title: CGFloat = 0
            if onScreen.contains(center), info != nil {
                if !scene.few { title = Self.titleAlpha(rank: dot.rank, zoom: zoom) * shown * (1 - dim) }
                if isFocus, dot.rank < 3 || info?.hasOpenTask == true { title = max(title, focusTitle) }
            }
            frame.dots.append(MapFrame.Dot(
                id: dot.id, topicID: dot.topicID, center: center, radius: radius, angle: dot.angle, rank: dot.rank,
                alpha: alpha * shown * (1 - 0.82 * dim), appear: appearing, info: info, color: styleOf(dot.topicID).dot,
                focused: isFocus, spacing: spacing[dot.topicID] ?? .infinity, title: title))
        }
        if let previous, p < 1, dotsShown > 0.01 || focusLevel > 0.01 {
            let current = Set(scene.layout.dots.map(\.id))
            for old in previous.layout.dots where !current.contains(old.id) {
                let shown = old.topicID == focus ? max(dotsShown, focusLevel) : dotsShown
                frame.dots.append(MapFrame.Dot(
                    id: old.id, topicID: old.topicID, center: screen(old.position), radius: overviewDot, angle: old.angle,
                    rank: old.rank, alpha: (1 - p) * shown, appear: nil, info: previous.dots[old.id], color: styleOf(old.topicID).dot,
                    focused: false, spacing: .infinity))
            }
        }

        // Flüge von der Kugel: zum Punkt des Gedankens – steckt er im Kreis (kein eigener Punkt), oben an den Kreis
        if let orb, !reduceMotion {
            for flight in flights {
                let target: (point: CGPoint, radius: CGFloat)
                if let t = targets[flight.id] {
                    target = t
                } else if let b = worldBubble[flight.topicID] {
                    target = (CGPoint(x: b.center.x, y: b.center.y - b.radius), 2.4)
                } else {
                    continue
                }
                frame.flights.append(MapFrame.Flight(
                    id: flight.id, from: orb, to: screen(target.point), progress: flight.progress,
                    color: flight.topicID == ThoughtMapView.noTopicID || flight.topicID == ThoughtMapView.moreID
                        ? style.flightNeutral : styleOf(flight.topicID).dot,
                    endRadius: target.radius))
            }
        }

        // Linien: Übersicht gebündelt zwischen Themen, im Fokus die Gedanken-Linien des Themas
        func addLine(_ id: String, _ from: CGPoint, _ control: CGPoint, _ to: CGPoint, topics: (String, String),
                     width: CGFloat, alpha: CGFloat, blend: Bool = false) {
            guard alpha > 0.01 else { return }
            let a = styleOf(topics.0).line, b = styleOf(topics.1).line
            let colors = blend ? (a.mix(with: b, by: 0.5), a.mix(with: b, by: 0.5)) : (a, b)
            frame.lines.append(MapFrame.Line(
                id: id, from: screen(from), control: screen(control), to: screen(to),
                colors: colors, width: width, alpha: alpha))
        }
        let overview = 1 - focusLevel
        if overview > 0.01 {
            let oldPairs = Dictionary((previous?.layout.topicLines ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            func strength(_ count: Int) -> CGFloat { min(1, log2(CGFloat(count)) / 3) }
            // zart: höchstens 0,2 Deckkraft, eine Mischfarbe statt Verlauf
            func pairAlpha(_ count: Int) -> CGFloat { (style.dark ? 0.13 : 0.12) + 0.07 * strength(count) }
            for line in scene.layout.topicLines {
                let width = 1 + 0.5 * strength(line.count)
                if let old = oldPairs[line.id], move < 1 {
                    addLine(line.id, lerp(old.from, line.from, move), lerp(old.control, line.control, move), lerp(old.to, line.to, move),
                            topics: (line.a, line.b), width: width, alpha: pairAlpha(line.count) * overview, blend: true)
                } else {
                    let fade: CGFloat = previous != nil && oldPairs[line.id] == nil ? p : 1
                    addLine(line.id, line.from, line.control, line.to, topics: (line.a, line.b), width: width,
                            alpha: pairAlpha(line.count) * overview * fade, blend: true)
                }
            }
            if let previous, p < 1 {
                let current = Set(scene.layout.topicLines.map(\.id))
                for old in previous.layout.topicLines where !current.contains(old.id) {
                    addLine(old.id, old.from, old.control, old.to, topics: (old.a, old.b), width: 1,
                            alpha: pairAlpha(old.count) * overview * (1 - p), blend: true)
                }
            }
        }
        if let focus, focusLevel > 0.01 {
            let oldLines = Dictionary((previous?.layout.lines ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // nur Linien, deren Ende im Thema ein sichtbarer Punkt ist (keine Strahlen vom Kreisrand)
            let shown = Set(scene.layout.dots.lazy.filter { $0.topicID == focus }.map(\.id))
            for line in scene.layout.lines where (line.topicA == focus && shown.contains(line.a)) || (line.topicB == focus && shown.contains(line.b)) {
                let alpha = (line.crossTopic ? 0.55 : 0.72) * focusLevel
                let width: CGFloat = line.crossTopic ? 0.9 : 1.3
                if let old = oldLines[line.id], move < 1 {
                    addLine(line.id, lerp(old.from, line.from, move), lerp(old.control, line.control, move), lerp(old.to, line.to, move),
                            topics: (line.topicA, line.topicB), width: width, alpha: alpha)
                } else {
                    addLine(line.id, line.from, line.control, line.to, topics: (line.topicA, line.topicB), width: width,
                            alpha: alpha * (previous != nil && oldLines[line.id] == nil ? p : 1))
                }
            }
        }
        return frame
    }

    /// Punkte in der Übersicht: erst ab Maßstab 1 (kurz davor weich eingeblendet, damit beim Zoomen nichts ploppt)
    static func dotFade(_ zoom: CGFloat) -> CGFloat {
        let t = min(1, max(0, (zoom - 0.95) / 0.05))
        return t * t * (3 - 2 * t)
    }

    /// Wachsen aus dem Nichts: weiche Feder mit kaum merklichem Überschwingen (≈ 4 %), `t` über `appearDuration`
    static func grow(_ t: CGFloat) -> CGFloat {
        guard t > 0 else { return 0 }
        let time = t * CGFloat(MapMotion.appearDuration), zeta: CGFloat = 0.72, omega: CGFloat = 10
        let wd = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * time) * (cos(wd * time) + zeta * omega / wd * sin(wd * time))
    }

    /// Ab welchem Maßstab ein Punkt in der Übersicht seinen Titel zeigt – neueste zuerst, abgestuft
    static func titleZoom(rank: Int) -> CGFloat {
        switch rank {
        case 0: 1.5
        case 1...2: 1.95
        case 3...5: 2.45
        case 6...11: 3.1
        default: 3.8
        }
    }

    /// Deckkraft des Titels beim Zoomen (blendet über einen kleinen Bereich ein, damit nichts ploppt)
    static func titleAlpha(rank: Int, zoom: CGFloat) -> CGFloat {
        min(1, max(0, (zoom - titleZoom(rank: rank)) / 0.18))
    }

    /// Weg eines Flugs über die Zeit: hebt weich ab, legt den Großteil früh zurück und setzt sanft auf
    /// (kritisch gedämpfte Feder, auf 0 … 1 normiert)
    nonisolated static func flightEase(_ p: CGFloat) -> CGFloat {
        let w: CGFloat = 6.5, t = min(1, max(0, p))
        return (1 - (1 + w * t) * exp(-w * t)) / (1 - (1 + w) * exp(-w))
    }

    // MARK: Schrift als Symbole (einmal gesetzt, beim Zeichnen nur platziert)

    @ViewBuilder
    private func symbols(_ frame: MapFrame) -> some View {
        ForEach(frame.bubbles, id: \.id) { bubble in
            if let info = bubble.info {
                MapLabel(title: info.title, count: info.count, style: style)
                    .modifier(MapHalo(color: style.ground))
                    .tag("L:" + bubble.id)
            }
        }
        if frame.few {
            ForEach(scene.layout.bubbles) { bubble in
                ForEach(scene.titles(of: bubble.id), id: \.id) { item in
                    Text(MapText.short(item.title, 30))
                        .font(.footnote)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .modifier(MapHalo(color: style.ground))
                        .tag("T:" + item.id)
                }
            }
        }
        // Titel an den Punkten (im Fokus die neuesten, beim Zoomen mehr) – mit Hof in der Grundfarbe, damit Linien
        // darunter die Schrift nicht kreuzen. Nur für Punkte im Bild.
        ForEach(frame.dots.filter { $0.title > 0.01 }, id: \.id) { dot in
            if let info = dot.info {
                Text(MapText.short(info.title, 24))
                    .font(.caption)
                    .foregroundStyle(style.ink.opacity(0.86))
                    .lineLimit(1)
                    .fixedSize()
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .modifier(MapHalo(color: style.ground))
                    .tag("F:" + dot.id)
            }
        }
    }

    // MARK: VoiceOver

    @ViewBuilder
    private func accessibility(_ frame: MapFrame) -> some View {
        let ranked = frame.bubbles.filter { $0.info != nil && $0.alpha > 0.5 }
            .sorted { ($0.info?.count ?? 0, $1.id) > ($1.info?.count ?? 0, $0.id) }
        ZStack {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, bubble in
                let side = max(44, 2 * bubble.radius)
                Color.clear
                    .frame(width: side, height: side)
                    .position(bubble.center)
                    .accessibilityElement()
                    .accessibilityLabel(MapText.spoken(bubble.info!))
                    .accessibilityHint(bubble.focused ? "" : "Zeigt die Gedanken dieses Themas.")
                    .accessibilityAddTraits(bubble.focused ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { onTopic(bubble.id) }
                    .accessibilitySortPriority(Double(1_000 - index))
            }
            if frame.focusLevel > 0.5 {
                ForEach(frame.dots.filter { $0.focused && $0.info != nil }, id: \.id) { dot in
                    Color.clear
                        .frame(width: 44, height: 44)
                        .position(dot.center)
                        .accessibilityElement()
                        .accessibilityLabel(MapText.spoken(dot.info!))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onThought(dot.id) }
                        .accessibilitySortPriority(Double(500 - dot.rank))
                }
            }
        }
        .frame(width: stage.size.width, height: stage.size.height)
        .allowsHitTesting(false)
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t)) }

/// Weicher Hof in der Grundfarbe um Schrift: Linien und Raster laufen darunter, die Schrift bleibt ruhig lesbar
private struct MapHalo: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .shadow(color: color, radius: 1)
            .shadow(color: color, radius: 2.5)
            .shadow(color: color.opacity(0.8), radius: 4)
    }
}

/// Name und Anzahl unter einem Kreis
private struct MapLabel: View {
    let title: String
    let count: Int
    let style: MapStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(MapText.short(title, 22))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(style.ink)
            Text("\(count)")
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(style.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

enum MapText {
    /// kurz halten, möglichst an einer Wortgrenze
    static func short(_ text: String, _ limit: Int) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        let cut = String(clean.prefix(limit - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= limit * 3 / 5 {
            return cut[..<space].trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    static func spoken(_ info: MapTopicInfo) -> String {
        var text = "\(info.title), \(info.count) \(info.count == 1 ? "Gedanke" : "Gedanken")"
        if info.open > 0 { text += ", \(info.open) offen" }
        return text
    }

    static func spoken(_ info: MapDotInfo) -> String {
        var text = "\(info.title), \(ThoughtDate.compact(info.date))"
        if info.hasOpenTask { text += ", offene Aufgabe" }
        return text
    }
}

// MARK: - Zeichnen

private struct MapPainter {
    struct Grid {
        var image: Image
        var origin: CGPoint
        var spacing: CGFloat
        var fineAlpha: CGFloat
    }

    let frame: MapFrame
    let size: CGSize
    let visible: CGRect
    let style: MapStyle
    let grid: Grid
    let reduceMotion: Bool
    let images: MapImageCache

    func draw(_ context: inout GraphicsContext, hitBox: MapHitBox) {
        var hits = MapHitBox.Snapshot()
        drawGrid(&context)
        drawLines(&context)
        for bubble in frame.bubbles.sorted(by: { ($0.focused ? 1 : 0, $0.radius) < ($1.focused ? 1 : 0, $1.radius) }) {
            drawBubble(&context, bubble)
        }
        images.sweep()
        drawDots(&context)
        let labels = drawLabels(&context)
        hits.titles = labels.titles + drawDotTitles(&context, avoid: Array(labels.rects.values) + labels.titles.map(\.rect))
        drawFlights(&context)
        hits.topics = frame.bubbles.filter { $0.alpha > 0.5 && $0.info != nil }.map {
            MapHitBox.Topic(id: $0.id, center: $0.center, radius: $0.radius * $0.scale, label: labels.rects[$0.id])
        }
        hits.dots = frame.dots.filter { $0.alpha > 0.3 }.map {
            MapHitBox.Dot(id: $0.id, topicID: $0.topicID, center: $0.center, spacing: $0.spacing)
        }
        hitBox.store(hits)
    }

    // MARK: Raster

    private func drawGrid(_ context: inout GraphicsContext) {
        let image = grid.image
        let all = Path(CGRect(origin: .zero, size: size))
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        var coarse = context
        coarse.opacity = 1 - grid.fineAlpha * 0.999
        let big = grid.spacing * 2
        coarse.fill(all, with: .tiledImage(image, origin: CGPoint(x: grid.origin.x - big / 2, y: grid.origin.y - big / 2),
                                           sourceRect: unit, scale: big / MapStyle.gridTile))
        guard grid.fineAlpha > 0.01 else { return }
        var fine = context
        fine.opacity = grid.fineAlpha
        fine.fill(all, with: .tiledImage(image, origin: CGPoint(x: grid.origin.x - grid.spacing / 2, y: grid.origin.y - grid.spacing / 2),
                                         sourceRect: unit, scale: grid.spacing / MapStyle.gridTile))
    }

    // MARK: Linien

    private func drawLines(_ context: inout GraphicsContext) {
        for line in frame.lines {
            var path = Path()
            path.move(to: line.from)
            path.addQuadCurve(to: line.to, control: line.control)
            let shading: GraphicsContext.Shading = line.colors.0 == line.colors.1
                ? .color(line.colors.0.opacity(line.alpha))
                : .linearGradient(Gradient(colors: [line.colors.0.opacity(line.alpha), line.colors.1.opacity(line.alpha)]),
                                  startPoint: line.from, endPoint: line.to)
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: line.width, lineCap: .round))
        }
    }

    // MARK: Kreise

    private func drawBubble(_ context: inout GraphicsContext, _ bubble: MapFrame.Bubble) {
        let r = bubble.radius * bubble.scale
        let c = bubble.center
        guard r > 0.5, bubble.alpha > 0.01 else { return }
        // außerhalb des Bildschirms samt Schein: nichts zu tun
        guard CGRect(origin: .zero, size: size).insetBy(dx: -2.2 * r, dy: -2.2 * r).contains(c) else { return }
        var ctx = context
        ctx.opacity = bubble.alpha * (1 - 0.7 * bubble.dim)
        let s = bubble.style
        let kind = bubble.info?.kind ?? .topic

        // feiner Bogen, wo im Fokus die Punkte liegen (Übersicht unter Maßstab 1)
        if let arc = bubble.arc, arc.alpha > 0.01 {
            var path = Path()
            path.addArc(center: c, radius: arc.radius * bubble.scale, startAngle: .radians(Double(arc.from) - 0.06),
                        endAngle: .radians(Double(arc.to) + 0.06), clockwise: false)
            ctx.stroke(path, with: .color(s.dot.opacity(arc.alpha)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }

        // Landung: ein Ring öffnet sich sanft um den Kreis
        if let glow = bubble.glow {
            let e = easeOut(glow)
            let rr = r + 3 + 18 * e
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                       with: .color((kind == .topic ? s.glow : style.neutralRing).opacity(0.6 * (1 - glow))),
                       lineWidth: 1.6 - 0.8 * glow)
        }

        switch kind {
        case .none:
            // „Ohne Thema“: hohler, gestrichelter Ring – kein Schein, keine Kugel
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            let dash = max(2.5, min(5, r * 0.16))
            ctx.stroke(ring, with: .color(style.neutralRing),
                       style: StrokeStyle(lineWidth: bubble.focused ? 1.6 : 1.3, lineCap: .round, dash: [dash, dash * 0.9]))
            return
        case .more:
            // Sammelkreis: feiner Ring, darin drei kleine Kreise (viele kleine Themen)
            let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(ring, with: .color(style.neutralFill))
            ctx.stroke(ring, with: .color(style.neutralRing), lineWidth: bubble.focused ? 1.4 : 1.1)
            if r >= 9 {
                for (dx, dy, k) in [(-0.2, 0.14, 0.2), (0.22, 0.1, 0.15), (0.02, -0.24, 0.12)] as [(CGFloat, CGFloat, CGFloat)] {
                    let p = CGPoint(x: c.x + dx * r, y: c.y + dy * r), q = k * r
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - q, y: p.y - q, width: 2 * q, height: 2 * q)), with: .color(style.neutralGlyph))
                }
            }
            return
        case .topic:
            break
        }

        // Schein (leuchtet nach einer Landung kurz auf)
        if r > 4 {
            let glowR = r * (style.dark ? 2.15 : 1.8)
            let fade: Double = bubble.glow.map { Double(1 - $0) } ?? 0
            let flash: Double = 1 + 0.9 * fade * fade
            let strength: Double = min(0.9, s.glowStrength * (bubble.focused ? 1.25 : 1) * flash)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - glowR, y: c.y - glowR, width: 2 * glowR, height: 2 * glowR)),
                     with: .radialGradient(Gradient(stops: [
                        .init(color: s.glow.opacity(strength), location: 0.36),
                        .init(color: s.glow.opacity(strength * 0.32), location: 0.62),
                        .init(color: s.glow.opacity(0), location: 1),
                     ]), center: c, startRadius: 0, endRadius: glowR))
            if !style.dark {
                // weicher Schatten darunter
                let shadow = CGPoint(x: c.x, y: c.y + r * 0.42)
                let sr = r * 1.25
                ctx.fill(Path(ellipseIn: CGRect(x: shadow.x - sr, y: shadow.y - sr, width: 2 * sr, height: 2 * sr)),
                         with: .radialGradient(Gradient(colors: [s.rim.opacity(0.55), s.rim.opacity(0)]),
                                               center: shadow, startRadius: 0, endRadius: sr))
            }
        }

        // Themenbild: rund zugeschnitten, feiner Rand in der Themenfarbe statt Farbfüllung und Symbol
        if let image = bubble.info?.image {
            drawImage(&ctx, image, center: c, radius: r, style: s)
            return
        }

        // Kugel
        let body = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.fill(body, with: .radialGradient(Gradient(stops: s.body), center: CGPoint(x: c.x - 0.36 * r, y: c.y - 0.48 * r),
                                             startRadius: 0, endRadius: 1.62 * r))
        ctx.stroke(body, with: .color(s.rim), lineWidth: 0.75)

        // Symbol
        if r >= 9, let info = bubble.info, let glyph = Lucide.paths[info.icon] {
            let box = r * 1.2
            let k = box / 24
            let path = glyph.applying(CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: c.x - 12 * k, ty: c.y - 12 * k))
            let stroke = (r > 40 ? 1.6 : 1.85) * k
            ctx.stroke(path, with: .color(s.glyph), style: StrokeStyle(lineWidth: max(1, stroke), lineCap: .round, lineJoin: .round))
        }
    }

    /// Bild im Kreis: füllt ihn (Seitenverhältnis bleibt), ein zarter Lichtpunkt oben links und etwas Tiefe zum Rand
    /// geben ihm die Wölbung der anderen Kreise; der Rand leuchtet fein in der Themenfarbe.
    private func drawImage(_ ctx: inout GraphicsContext, _ image: UIImage, center c: CGPoint, radius r: CGFloat,
                           style s: MapStyle.Bubble) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        let circle = Path(ellipseIn: rect)
        var clip = ctx
        clip.clip(to: circle)
        // Grund in der Themenfarbe (durchscheinende Logos, Ränder beim Einpassen)
        clip.fill(circle, with: .color(s.glow.opacity(0.35)))
        let resolved = images.resolved(image, in: ctx)
        let size = resolved.size
        let k = max(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
        let w = size.width * k, h = size.height * k
        clip.draw(resolved, in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
        clip.fill(circle, with: .radialGradient(Gradient(stops: [
            .init(color: .white.opacity(style.dark ? 0.22 : 0.28), location: 0),
            .init(color: .white.opacity(0), location: 0.6),
        ]), center: CGPoint(x: c.x - 0.42 * r, y: c.y - 0.52 * r), startRadius: 0, endRadius: 1.2 * r))
        clip.fill(circle, with: .radialGradient(Gradient(stops: [
            .init(color: .black.opacity(0), location: 0.64),
            .init(color: .black.opacity(style.dark ? 0.3 : 0.14), location: 1),
        ]), center: c, startRadius: 0, endRadius: r))
        // Rand: innen kräftig, außen ein Hauch Leuchten
        let rim = max(1.2, min(2.6, r * 0.055))
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: rim / 2, dy: rim / 2)), with: .color(s.ring.opacity(style.dark ? 0.95 : 0.9)),
                   lineWidth: rim)
        let halo = rect.insetBy(dx: -1.4, dy: -1.4)
        ctx.stroke(Path(ellipseIn: halo), with: .color(s.glow.opacity(style.dark ? 0.4 : 0.3)), lineWidth: 1.2)
    }

    // MARK: Punkte

    private func drawDots(_ context: inout GraphicsContext) {
        let ground = style.ground
        for dot in frame.dots {
            guard dot.alpha > 0.01 else { continue }
            let c = dot.center
            guard c.x > -20, c.y > -20, c.x < size.width + 20, c.y < size.height + 20 else { continue }
            var r = dot.radius
            var alpha = dot.alpha
            var ripple: (radius: CGFloat, alpha: CGFloat)?
            if let a = dot.appear {
                if reduceMotion {
                    alpha *= min(1, a * 3)
                } else {
                    // aufploppen mit leichtem Überschwingen, dazu ein sich öffnender Ring
                    let pop = a < 0.38 ? 1.22 * easeOut(a / 0.38) : 1.22 - 0.22 * easeInOut((a - 0.38) / 0.62)
                    r *= pop
                    let t = min(1, max(0, (a - 0.08) / 0.92))
                    ripple = (dot.radius + 3 + 15 * easeOut(t), 0.55 * (1 - t))
                }
            }
            if let ripple {
                let rr = ripple.radius
                context.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: 2 * rr, height: 2 * rr)),
                               with: .color(dot.color.opacity(ripple.alpha * alpha)), lineWidth: 1.4)
            }
            // Ring in Grundfarbe trennt den Punkt von Linien
            let halo = r + 1.5
            context.fill(Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: 2 * halo, height: 2 * halo)),
                         with: .color(ground.opacity(0.9 * alpha)))
            if dot.info?.isRecent == true {
                // jünger als 24 h: weicher Schein in der Themenfarbe
                let h = r + 6
                context.fill(Path(ellipseIn: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h)),
                             with: .radialGradient(Gradient(stops: [
                                .init(color: dot.color.opacity(0.75 * alpha), location: r / h),
                                .init(color: dot.color.opacity(0), location: 1),
                             ]), center: c, startRadius: 0, endRadius: h))
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(dot.color.opacity(alpha)))
            if dot.info?.hasOpenTask == true {
                let o = r + 2.6
                context.stroke(Path(ellipseIn: CGRect(x: c.x - o, y: c.y - o, width: 2 * o, height: 2 * o)),
                               with: .color(style.open.opacity(alpha)), lineWidth: 1.3)
            }
        }
    }

    // MARK: Beschriftungen

    private func circleHits(_ rect: CGRect, except id: String) -> Bool {
        for bubble in frame.bubbles where bubble.id != id && bubble.alpha > 0.3 {
            let r = bubble.radius * bubble.scale
            let qx = min(max(bubble.center.x, rect.minX), rect.maxX), qy = min(max(bubble.center.y, rect.minY), rect.maxY)
            if hypot(bubble.center.x - qx, bubble.center.y - qy) < r + 2 { return true }
        }
        return false
    }

    private func drawLabels(_ context: inout GraphicsContext) -> (rects: [String: CGRect], titles: [MapHitBox.Title]) {
        var rects: [String: CGRect] = [:]
        var titles: [MapHitBox.Title] = []
        guard frame.labelAlpha > 0.01 else { return (rects, titles) }
        var placed: [CGRect] = []
        // wichtige zuerst: mehr Gedanken, dann Name
        let order = frame.bubbles.filter { $0.info != nil && $0.alpha > 0.05 }
            .sorted { ($0.info!.count, $1.id) > ($1.info!.count, $0.id) }
        for bubble in order {
            guard let symbol = context.resolveSymbol(id: "L:" + bubble.id) else { continue }
            let w = symbol.size.width, h = symbol.size.height
            let r = bubble.radius * bubble.scale
            // mittig unter dem Kreis; ist dort schon eine andere Beschriftung, ein Stück zur Seite (bleibt unter
            // dem Kreis) oder eine Zeile tiefer
            let offsets: [CGPoint] = [.zero, CGPoint(x: min(w * 0.3, r + 12), y: 0), CGPoint(x: -min(w * 0.3, r + 12), y: 0),
                                      CGPoint(x: 0, y: h * 0.85)]
            var found: CGRect?
            for offset in offsets {
                var rect = CGRect(x: bubble.center.x - w / 2 + offset.x, y: bubble.labelTop + offset.y, width: w, height: h)
                // am Rand ins Bild rücken – aber nur so weit, wie der Kreis reicht (beim Zoomen bleibt der Name eines
                // Kreises außerhalb des Bildes bei seinem Kreis)
                let inside = min(max(rect.minX, 8), size.width - 8 - w)
                if abs(inside - rect.minX) <= r + 6 { rect.origin.x = inside }
                guard rect.minY < size.height, rect.maxY > 0 else { break }
                if !placed.contains(where: { $0.insetBy(dx: -4, dy: -1).intersects(rect) }), !circleHits(rect, except: bubble.id) {
                    found = rect
                    break
                }
            }
            guard let rect = found else { continue }
            var ctx = context
            // ein wachsender Kreis bekommt seinen Namen erst, wenn er fast da ist
            let grown = min(1, max(0, (bubble.scale - 0.55) / 0.4))
            ctx.opacity = frame.labelAlpha * bubble.alpha * grown * (1 - 0.7 * bubble.dim)
            ctx.draw(symbol, in: rect)
            placed.append(rect)
            rects[bubble.id] = rect

            // wenige Gedanken: Titel darunter
            guard frame.few else { continue }
            var y = rect.maxY + 1
            for dot in frame.dots.filter({ $0.topicID == bubble.id }).sorted(by: { $0.rank < $1.rank }).prefix(bubble.titleLines) {
                guard let title = context.resolveSymbol(id: "T:" + dot.id) else { continue }
                let tw = title.size.width, th = title.size.height
                var tr = CGRect(x: bubble.center.x - tw / 2, y: y, width: tw, height: th)
                let inside = min(max(tr.minX, 8), size.width - 8 - tw)
                if abs(inside - tr.minX) <= r + 6 { tr.origin.x = inside }
                guard !placed.contains(where: { $0.intersects(tr) }), !circleHits(tr, except: bubble.id) else { break }
                ctx.draw(title, in: tr)
                placed.append(tr)
                titles.append(MapHitBox.Title(id: dot.id, rect: tr))
                y = tr.maxY - 1
            }
        }
        return (rects, titles)
    }

    /// Kurze Titel neben den Punkten, wo Platz ist: im Fokus die neuesten und offene Aufgaben, beim Zoomen abgestuft
    /// mehr. Thema im Fokus zuerst, dann neueste zuerst. Weicht Beschriftungen, Kreisen und Punkten aus.
    private func drawDotTitles(_ context: inout GraphicsContext, avoid: [CGRect]) -> [MapHitBox.Title] {
        let candidates = frame.dots.filter { $0.title > 0.01 }
            .sorted { ($0.focused ? 0 : 1, $0.rank, $0.id) < ($1.focused ? 0 : 1, $1.rank, $1.id) }
        guard !candidates.isEmpty else { return [] }
        var bubbles: [String: MapFrame.Bubble] = [:]
        for bubble in frame.bubbles where bubble.info != nil { bubbles[bubble.id] = bubble }
        let topics = Set(candidates.map(\.topicID))
        var neighbours: [String: [MapFrame.Dot]] = [:]
        for dot in frame.dots where topics.contains(dot.topicID) { neighbours[dot.topicID, default: []].append(dot) }
        let area = visible.insetBy(dx: 8, dy: 6)
        var placed = avoid
        var titles: [MapHitBox.Title] = []
        for dot in candidates {
            guard let bubble = bubbles[dot.topicID], let symbol = context.resolveSymbol(id: "F:" + dot.id) else { continue }
            let w = symbol.size.width, h = symbol.size.height
            let c = dot.center, gap = dot.radius + 7
            let cosine = cos(dot.angle)
            let rect: CGRect
            if cosine < -0.35 {
                rect = CGRect(x: c.x - gap - w, y: c.y - h / 2, width: w, height: h)
            } else if cosine > 0.35 {
                rect = CGRect(x: c.x + gap, y: c.y - h / 2, width: w, height: h)
            } else {
                rect = CGRect(x: c.x - w / 2, y: c.y - dot.radius - 5 - h, width: w, height: h)
            }
            guard area.contains(rect) else { continue }
            guard !placed.contains(where: { $0.insetBy(dx: -3, dy: -2).intersects(rect) }) else { continue }
            let hitsDot = (neighbours[dot.topicID] ?? []).contains { other in
                let qx = min(max(other.center.x, rect.minX), rect.maxX), qy = min(max(other.center.y, rect.minY), rect.maxY)
                return hypot(other.center.x - qx, other.center.y - qy) < other.radius + 3
            }
            guard !hitsDot else { continue }
            let qx = min(max(bubble.center.x, rect.minX), rect.maxX), qy = min(max(bubble.center.y, rect.minY), rect.maxY)
            guard hypot(bubble.center.x - qx, bubble.center.y - qy) > bubble.radius + 4, !circleHits(rect, except: bubble.id) else { continue }
            var ctx = context
            ctx.opacity = dot.title * dot.alpha
            ctx.draw(symbol, in: rect)
            placed.append(rect)
            if dot.title * dot.alpha > 0.6 { titles.append(MapHitBox.Title(id: dot.id, rect: rect)) }
        }
        return titles
    }

    // MARK: Flüge

    /// Punkt von der Kugel zu seinem Kreis: ein weicher Bogen, hebt klein ab, fliegt mit zartem Schweif und färbt sich
    /// unterwegs von Paply-Grün in die Themenfarbe. Nach der Landung glüht er kurz nach, während der Punkt am Ziel
    /// aufploppt.
    private func drawFlights(_ context: inout GraphicsContext) {
        for flight in frame.flights {
            let s = flight.from, e = flight.to
            let dist = hypot(e.x - s.x, e.y - s.y)
            let p = flight.progress
            if p >= 1 {
                // Nachglühen am Ziel
                let k = min(1, (p - 1) * CGFloat(MapLandings.duration / MapMotion.afterglow))
                let rr = max(flight.endRadius, 2) * (1.6 + 3 * easeOut(k))
                context.fill(Path(ellipseIn: CGRect(x: e.x - rr, y: e.y - rr, width: 2 * rr, height: 2 * rr)),
                             with: .radialGradient(Gradient(colors: [flight.color.opacity(0.55 * (1 - k)), flight.color.opacity(0)]),
                                                   center: e, startRadius: 0, endRadius: rr))
                continue
            }
            // Bogen: steigt von der Kugel auf und setzt von oben auf den Kreis
            let lift = min(140, 0.24 * dist)
            let control = CGPoint(x: s.x + (e.x - s.x) * 0.2, y: min(s.y, e.y) - lift)
            func point(_ t: CGFloat) -> CGPoint {
                let u = 1 - t
                return CGPoint(x: u * u * s.x + 2 * u * t * control.x + t * t * e.x,
                               y: u * u * s.y + 2 * u * t * control.y + t * t * e.y)
            }
            let u = MapCanvas.flightEase(p)
            let rise = easeOut(min(1, p / 0.2))
            let land = easeInOut(max(0, (p - 0.72) / 0.28))
            let r = (1.8 + 3.8 * rise) * (1 - land) + max(flight.endRadius, 2.4) * 1.2 * land
            let color = style.inbox.mix(with: flight.color, by: Double(min(1, u * 1.25)))
            // Schweif
            for k in stride(from: 6, through: 1, by: -1) {
                let q = max(0, u - CGFloat(k) * 0.032 * (1 - land))
                let tp = point(q)
                let tr = r * (1 - 0.12 * CGFloat(k))
                context.fill(Path(ellipseIn: CGRect(x: tp.x - tr, y: tp.y - tr, width: 2 * tr, height: 2 * tr)),
                             with: .color(color.opacity(0.36 * (1 - CGFloat(k) / 7) * rise)))
            }
            let c = point(u)
            let h = r * 3.8
            context.fill(Path(ellipseIn: CGRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h)),
                         with: .radialGradient(Gradient(stops: [
                            .init(color: color.opacity(0.6), location: r / h),
                            .init(color: color.opacity(0.18), location: (r / h + 1) / 2),
                            .init(color: color.opacity(0), location: 1),
                         ]), center: c, startRadius: 0, endRadius: h))
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            let core = r * 0.45
            context.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: 2 * core, height: 2 * core)),
                         with: .color(.white.opacity(0.5 * (1 - land))))
        }
    }

    private func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - min(1, max(0, t)), 3) }
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }
}
