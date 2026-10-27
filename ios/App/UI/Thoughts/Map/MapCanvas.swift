import PaplyKit
import SwiftUI

// Zeichnet die Karte mit `Canvas` (Metal über `drawingGroup`): Punktraster, Linien, leuchtende Kreise mit
// Lucide-Symbol, Punkte, Beschriftungen. Kamera, verdeckte Höhe unten und Fokus sind animierbar (SwiftUI
// interpoliert sie Bild für Bild); Datenwechsel laufen zeitgesteuert über `MapMotion`.
// Was gezeichnet wurde, landet in `MapHitBox` – Tipps treffen genau das Sichtbare.

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

/// Weltpunkt `center` liegt am Ankerpunkt der Bühne, `zoom` Bildschirmpunkte je Kartenpunkt.
struct MapCamera: Equatable {
    var zoom: CGFloat
    var center: CGPoint

    static let identity = MapCamera(zoom: 1, center: .zero)
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
        let style = style
        ZStack {
            Canvas { context, _ in
                MapPainter(frame: frame, size: size, visible: visible, style: style, grid: grid, reduceMotion: reduceMotion)
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
        let oldBubbles = Dictionary((previous?.layout.bubbles ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var worldBubble: [String: MapLayout.Bubble] = [:]
        for bubble in scene.layout.bubbles {
            var b = bubble
            var alpha: CGFloat = 1, scale: CGFloat = 1
            if let old = oldBubbles[bubble.id], move < 1 {
                b.center = lerp(old.center, bubble.center, move)
                b.radius = lerp(old.radius, bubble.radius, move)
                b.outerRadius = lerp(old.outerRadius, bubble.outerRadius, move)
            } else if previous != nil, oldBubbles[bubble.id] == nil {
                if let a = appear["topic:" + bubble.id] {
                    scale = reduceMotion ? 1 : 0.55 + 0.45 * Self.backOut(a)
                    alpha = min(1, a * 2.5)
                } else {
                    alpha = p
                }
            }
            worldBubble[bubble.id] = b
            let dim = focus != nil && bubble.id != focus ? focusLevel : 0
            frame.bubbles.append(MapFrame.Bubble(
                id: b.id, center: screen(b.center), radius: b.radius * zoom,
                labelTop: screen(CGPoint(x: b.center.x, y: b.center.y + b.radius + 8)).y,
                alpha: alpha, scale: scale, dim: dim, focused: bubble.id == focus,
                info: scene.topics[bubble.id], style: styleOf(bubble.id)))
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
        for dot in scene.layout.dots {
            var position = dot.position
            var alpha: CGFloat = 1
            var appearing: CGFloat?
            if let old = oldDots[dot.id], move < 1 {
                position = lerp(old.position, dot.position, move)
            } else if previous != nil, oldDots[dot.id] == nil {
                if let a = appear[dot.id] { appearing = a } else { alpha = p }
            }
            let isFocus = dot.topicID == focus
            let dim = focus != nil && !isFocus ? focusLevel : 0
            let radius = isFocus ? lerp(overviewDot, focusDot, focusLevel) : overviewDot
            frame.dots.append(MapFrame.Dot(
                id: dot.id, topicID: dot.topicID, center: screen(position), radius: radius, angle: dot.angle, rank: dot.rank,
                alpha: alpha * (1 - 0.82 * dim), appear: appearing, info: scene.dots[dot.id], color: styleOf(dot.topicID).dot,
                focused: isFocus, spacing: spacing[dot.topicID] ?? .infinity))
        }
        if let previous, p < 1 {
            let current = Set(scene.layout.dots.map(\.id))
            for old in previous.layout.dots where !current.contains(old.id) {
                frame.dots.append(MapFrame.Dot(
                    id: old.id, topicID: old.topicID, center: screen(old.position), radius: overviewDot, angle: old.angle,
                    rank: old.rank, alpha: 1 - p, appear: nil, info: previous.dots[old.id], color: styleOf(old.topicID).dot,
                    focused: false, spacing: .infinity))
            }
        }

        // Linien: Übersicht gebündelt zwischen Themen, im Fokus die Gedanken-Linien des Themas
        func addLine(_ id: String, _ from: CGPoint, _ control: CGPoint, _ to: CGPoint, topics: (String, String),
                     width: CGFloat, alpha: CGFloat) {
            guard alpha > 0.01 else { return }
            frame.lines.append(MapFrame.Line(
                id: id, from: screen(from), control: screen(control), to: screen(to),
                colors: (styleOf(topics.0).line, styleOf(topics.1).line), width: width, alpha: alpha))
        }
        let overview = 1 - focusLevel
        if overview > 0.01 {
            let oldPairs = Dictionary((previous?.layout.topicLines ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            func strength(_ count: Int) -> CGFloat { min(1, log2(CGFloat(count) + 1) / 3) }
            func pairAlpha(_ count: Int) -> CGFloat { (style.dark ? 0.32 : 0.28) + 0.22 * strength(count) }
            for line in scene.layout.topicLines {
                let width = 0.8 + 0.7 * strength(line.count)
                if let old = oldPairs[line.id], move < 1 {
                    addLine(line.id, lerp(old.from, line.from, move), lerp(old.control, line.control, move), lerp(old.to, line.to, move),
                            topics: (line.a, line.b), width: width, alpha: pairAlpha(line.count) * overview)
                } else {
                    let fade: CGFloat = previous != nil && oldPairs[line.id] == nil ? p : 1
                    addLine(line.id, line.from, line.control, line.to, topics: (line.a, line.b), width: width,
                            alpha: pairAlpha(line.count) * overview * fade)
                }
            }
            if let previous, p < 1 {
                let current = Set(scene.layout.topicLines.map(\.id))
                for old in previous.layout.topicLines where !current.contains(old.id) {
                    addLine(old.id, old.from, old.control, old.to, topics: (old.a, old.b), width: 0.8,
                            alpha: pairAlpha(old.count) * overview * (1 - p))
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

    /// leichtes Überschwingen (Einblenden)
    static func backOut(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.4, c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }

    // MARK: Schrift als Symbole (einmal gesetzt, beim Zeichnen nur platziert)

    @ViewBuilder
    private func symbols(_ frame: MapFrame) -> some View {
        ForEach(frame.bubbles, id: \.id) { bubble in
            if let info = bubble.info {
                MapLabel(title: info.title, count: info.count, style: style)
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
                        .tag("T:" + item.id)
                }
            }
        }
        if frame.focusLevel > 0.01 {
            ForEach(frame.dots.filter(\.focused), id: \.id) { dot in
                if let info = dot.info {
                    Text(MapText.short(info.title, 24))
                        .font(.caption)
                        .foregroundStyle(style.ink.opacity(0.86))
                        .lineLimit(1)
                        .fixedSize()
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .tag("F:" + dot.id)
                }
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

    func draw(_ context: inout GraphicsContext, hitBox: MapHitBox) {
        var hits = MapHitBox.Snapshot()
        drawGrid(&context)
        drawLines(&context)
        for bubble in frame.bubbles.sorted(by: { ($0.focused ? 1 : 0, $0.radius) < ($1.focused ? 1 : 0, $1.radius) }) {
            drawBubble(&context, bubble)
        }
        drawDots(&context)
        let labels = drawLabels(&context)
        hits.titles = labels.titles + drawFocusTitles(&context)
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

        // Schein
        if r > 4 {
            let glowR = r * (style.dark ? 2.15 : 1.8)
            let strength = s.glowStrength * (bubble.focused ? 1.25 : 1)
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
            var rect = CGRect(x: bubble.center.x - w / 2, y: bubble.labelTop, width: w, height: h)
            rect.origin.x = min(max(rect.minX, 8), size.width - 8 - w)
            guard rect.minY < size.height, rect.maxY > 0 else { continue }
            guard !placed.contains(where: { $0.insetBy(dx: -4, dy: -1).intersects(rect) }), !circleHits(rect, except: bubble.id) else { continue }
            var ctx = context
            ctx.opacity = frame.labelAlpha * bubble.alpha * (1 - 0.7 * bubble.dim)
            ctx.draw(symbol, in: rect)
            placed.append(rect)
            rects[bubble.id] = rect

            // wenige Gedanken: Titel darunter
            guard frame.few else { continue }
            var y = rect.maxY + 3
            for dot in frame.dots.filter({ $0.topicID == bubble.id }).sorted(by: { $0.rank < $1.rank }) {
                guard let title = context.resolveSymbol(id: "T:" + dot.id) else { continue }
                let tw = title.size.width, th = title.size.height
                var tr = CGRect(x: bubble.center.x - tw / 2, y: y, width: tw, height: th)
                tr.origin.x = min(max(tr.minX, 8), size.width - 8 - tw)
                guard !placed.contains(where: { $0.intersects(tr) }), !circleHits(tr, except: bubble.id) else { break }
                ctx.draw(title, in: tr)
                placed.append(tr)
                titles.append(MapHitBox.Title(id: dot.id, rect: tr))
                y = tr.maxY + 1
            }
        }
        return (rects, titles)
    }

    /// Im Fokus: kurze Titel neben den Punkten, wo Platz ist (neueste zuerst)
    private func drawFocusTitles(_ context: inout GraphicsContext) -> [MapHitBox.Title] {
        guard frame.focusLevel > 0.05, let focus = frame.focusID,
              let bubble = frame.bubbles.first(where: { $0.id == focus }) else { return [] }
        let dots = frame.dots.filter(\.focused).sorted { $0.rank < $1.rank }
        let area = visible.insetBy(dx: 8, dy: 6)
        var placed: [CGRect] = []
        var titles: [MapHitBox.Title] = []
        for dot in dots {
            guard let symbol = context.resolveSymbol(id: "F:" + dot.id) else { continue }
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
            let hitsDot = dots.contains { other in
                let qx = min(max(other.center.x, rect.minX), rect.maxX), qy = min(max(other.center.y, rect.minY), rect.maxY)
                return hypot(other.center.x - qx, other.center.y - qy) < other.radius + 3
            }
            guard !hitsDot else { continue }
            let qx = min(max(bubble.center.x, rect.minX), rect.maxX), qy = min(max(bubble.center.y, rect.minY), rect.maxY)
            guard hypot(bubble.center.x - qx, bubble.center.y - qy) > bubble.radius + 4 else { continue }
            var ctx = context
            ctx.opacity = min(1, max(0, (frame.focusLevel - 0.35) / 0.65)) * dot.alpha
            ctx.draw(symbol, in: rect)
            placed.append(rect)
            titles.append(MapHitBox.Title(id: dot.id, rect: rect))
        }
        return frame.focusLevel > 0.6 ? titles : []
    }

    private func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - min(1, max(0, t)), 3) }
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }
}
