import SwiftUI

// Zeichnet die Lucide-Symbole (LucideIcons.swift) als SwiftUI-Formen: ohne Asset-Katalog, scharf in
// jeder Größe, runde Enden. Die SVG-Pfade werden einmal beim ersten Gebrauch in `Path` übersetzt und
// danach nur noch skaliert. Ohne PaplyKit – App und Widget-Erweiterung nutzen dieselbe Datei.
// Themen: `TopicGlyph(key: TopicIcon.rawValue)` (Schlüssel wie am Mac, z. B. "map-pin").

/// Baustein eines Lucide-Symbols im 24 × 24-Raster
enum LucideElement: Sendable {
    case path(String)
    case circle(CGFloat, CGFloat, CGFloat)
    case ellipse(CGFloat, CGFloat, CGFloat, CGFloat)
    case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    case line(CGFloat, CGFloat, CGFloat, CGFloat)
    case polyline([CGFloat])
    case polygon([CGFloat])
}

extension Lucide {
    /// Alle Symbole als Pfad im 24 × 24-Raster (einmal erzeugt, unveränderlich)
    static let paths: [Lucide: Path] = {
        var result: [Lucide: Path] = [:]
        for icon in Lucide.allCases { result[icon] = icon.makePath() }
        return result
    }()

    private func makePath() -> Path {
        var path = Path()
        for element in elements {
            switch element {
            case .path(let d):
                path.addPath(SVGPath.parse(d))
            case .circle(let cx, let cy, let r):
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            case .ellipse(let cx, let cy, let rx, let ry):
                path.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            case .rect(let x, let y, let w, let h, let rx, let ry):
                path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: rx, height: ry))
            case .line(let x1, let y1, let x2, let y2):
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x2, y: y2))
            case .polyline(let v), .polygon(let v):
                guard v.count >= 4 else { continue }
                path.move(to: CGPoint(x: v[0], y: v[1]))
                for i in stride(from: 2, to: v.count - 1, by: 2) { path.addLine(to: CGPoint(x: v[i], y: v[i + 1])) }
                if case .polygon = element { path.closeSubpath() }
            }
        }
        return path
    }
}

/// Ein Lucide-Symbol als Form (zentriert, seitenverhältnistreu)
struct LucideShape: Shape {
    let icon: Lucide

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let base = Lucide.paths[icon] ?? Path()
        return base.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: rect.midX - 12 * s, ty: rect.midY - 12 * s))
    }
}

/// Ein Lucide-Symbol in Textfarbe. Wächst mit Dynamic Type (bezogen auf `relativeTo`).
struct LucideImage: View {
    let icon: Lucide
    let size: CGFloat
    /// Strich im 24er-Raster (Lucide: 2)
    var stroke: CGFloat = 2
    @ScaledMetric private var scale: CGFloat

    init(_ icon: Lucide, size: CGFloat = 17, stroke: CGFloat = 2, relativeTo style: Font.TextStyle = .body, scales: Bool = true) {
        self.icon = icon
        self.size = size
        self.stroke = stroke
        _scale = scales ? ScaledMetric(wrappedValue: 1, relativeTo: style) : ScaledMetric(wrappedValue: 1, relativeTo: .body)
        self.scales = scales
    }

    private let scales: Bool

    var body: some View {
        let s = size * (scales ? min(scale, 2.4) : 1)
        LucideShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: max(1.1, stroke * s / 24), lineCap: .round, lineJoin: .round))
            .frame(width: s, height: s)
            .accessibilityHidden(true)
    }
}

/// Label mit Lucide-Symbol (statt `Label(_, systemImage:)`)
struct LucideLabel: View {
    let title: String
    let icon: Lucide
    var size: CGFloat = 14
    var relativeTo: Font.TextStyle = .caption
    var spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            LucideImage(icon, size: size, relativeTo: relativeTo)
            Text(title)
        }
    }
}

extension Lucide {
    /// Themen-Symbol zum Schlüssel `TopicIcon.rawValue` – dieselben Formen wie am Mac
    /// (`electron-menubar/src/apps/notes/icons.tsx`, unbekannt → Glühbirne wie dort).
    static func topic(_ key: String?) -> Lucide {
        switch key {
        case "sparkles": .sparkles
        case "lightbulb": .lightbulb
        case "home": .house
        case "code": .codeXml
        case "map-pin": .mapPin
        case "sun": .sun
        case "moon": .moon
        case "heart": .heart
        case "coffee": .coffee
        case "briefcase": .briefcaseBusiness
        case "calendar": .calendarDays
        case "message-circle": .messageCircle
        case "book": .bookOpen
        case "music": .music
        case "camera": .camera
        case "leaf": .leaf
        case "flag": .flag
        case "circle-help": .circleQuestionMark
        case "pencil": .pencil
        case "plane": .plane
        case "wallet": .wallet
        case "users": .users
        case "list": .list
        case "zap": .zap
        default: .lightbulb
        }
    }
}

/// Themen-Symbol als Linien-Glyphe (Strich 1,6 wie die Mac-Notes). Wächst mit der Schrift.
struct TopicGlyph: View {
    let key: String?
    var size: CGFloat = 17
    var stroke: CGFloat = 1.6
    var relativeTo: Font.TextStyle = .body
    var scales = true

    init(key: String?, size: CGFloat = 17, stroke: CGFloat = 1.6, relativeTo: Font.TextStyle = .body, scales: Bool = true) {
        self.key = key
        self.size = size
        self.stroke = stroke
        self.relativeTo = relativeTo
        self.scales = scales
    }

    var body: some View {
        LucideImage(Lucide.topic(key), size: size, stroke: stroke, relativeTo: relativeTo, scales: scales)
    }
}

// MARK: - SVG-Pfad → Path

/// Kleiner SVG-Pfad-Leser (M L H V C S Q T A Z, groß/klein). Bögen werden in Bézier-Kurven übersetzt.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var reader = Reader(Array(d.utf8))
        return reader.run()
    }

    private struct Reader {
        let c: [UInt8]
        var i = 0
        var path = Path()
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCubic: CGPoint?
        var lastQuad: CGPoint?

        init(_ chars: [UInt8]) { c = chars }

        mutating func run() -> Path {
            var cmd: UInt8 = 0
            while true {
                skip()
                guard i < c.count else { break }
                if isLetter(c[i]) {
                    cmd = c[i]
                    i += 1
                } else if cmd == 0 {
                    break
                }
                let before = i
                step(&cmd)
                if i == before && !isClose(cmd) { i += 1 } // Schutz gegen Endlosschleife bei Unsinn
                if isClose(cmd) { cmd = 0 }
            }
            return path
        }

        private func isClose(_ x: UInt8) -> Bool { x == UInt8(ascii: "Z") || x == UInt8(ascii: "z") }

        private mutating func step(_ cmd: inout UInt8) {
            let rel = cmd >= UInt8(ascii: "a")
            let base = rel ? cur : .zero
            switch cmd | 0x20 { // klein
            case UInt8(ascii: "m"):
                guard let p = point(base) else { return }
                path.move(to: p)
                cur = p
                start = p
                cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L") // weitere Paare sind Linien
                lastCubic = nil; lastQuad = nil
            case UInt8(ascii: "l"):
                guard let p = point(base) else { return }
                line(p)
            case UInt8(ascii: "h"):
                guard let x = number() else { return }
                line(CGPoint(x: (rel ? cur.x : 0) + x, y: cur.y))
            case UInt8(ascii: "v"):
                guard let y = number() else { return }
                line(CGPoint(x: cur.x, y: (rel ? cur.y : 0) + y))
            case UInt8(ascii: "c"):
                guard let c1 = point(base), let c2 = point(base), let p = point(base) else { return }
                path.addCurve(to: p, control1: c1, control2: c2)
                lastCubic = c2; lastQuad = nil; cur = p
            case UInt8(ascii: "s"):
                guard let c2 = point(base), let p = point(base) else { return }
                let c1 = lastCubic.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                path.addCurve(to: p, control1: c1, control2: c2)
                lastCubic = c2; lastQuad = nil; cur = p
            case UInt8(ascii: "q"):
                guard let q = point(base), let p = point(base) else { return }
                path.addQuadCurve(to: p, control: q)
                lastQuad = q; lastCubic = nil; cur = p
            case UInt8(ascii: "t"):
                guard let p = point(base) else { return }
                let q = lastQuad.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                path.addQuadCurve(to: p, control: q)
                lastQuad = q; lastCubic = nil; cur = p
            case UInt8(ascii: "a"):
                guard let rx = number(), let ry = number(), let rot = number(),
                      let large = flag(), let sweep = flag(), let p = point(base) else { return }
                arc(to: p, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                lastCubic = nil; lastQuad = nil; cur = p
            case UInt8(ascii: "z"):
                path.closeSubpath()
                cur = start
                lastCubic = nil; lastQuad = nil
            default:
                return
            }
        }

        private mutating func line(_ p: CGPoint) {
            path.addLine(to: p)
            cur = p
            lastCubic = nil; lastQuad = nil
        }

        /// Elliptischer Bogen nach SVG 1.1 (F.6.5), in ≤ 90°-Stücke als kubische Bézier-Kurven
        private mutating func arc(to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
            let p0 = cur
            guard p0 != p1 else { return }
            var rx = abs(rxIn), ry = abs(ryIn)
            guard rx > 0, ry > 0 else { path.addLine(to: p1); return }
            let phi = rotation * .pi / 180
            let cosP = cos(phi), sinP = sin(phi)
            let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
            let x1 = cosP * dx2 + sinP * dy2
            let y1 = -sinP * dx2 + cosP * dy2
            let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
            if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
            let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
            let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
            let coef = (large == sweep ? -1 : 1) * sqrt(max(0, num / max(den, 1e-12)))
            let cxp = coef * (rx * y1 / ry)
            let cyp = coef * (-ry * x1 / rx)
            let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
            let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2
            func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
                atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            }
            let theta1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
            var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
            if !sweep && delta > 0 { delta -= 2 * .pi } else if sweep && delta < 0 { delta += 2 * .pi }
            let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
            let step = delta / CGFloat(segments)
            let t = 4 / 3 * tan(step / 4)
            func point(_ a: CGFloat) -> CGPoint {
                CGPoint(x: cx + rx * cos(a) * cosP - ry * sin(a) * sinP, y: cy + rx * cos(a) * sinP + ry * sin(a) * cosP)
            }
            func tangent(_ a: CGFloat) -> CGPoint {
                CGPoint(x: -rx * sin(a) * cosP - ry * cos(a) * sinP, y: -rx * sin(a) * sinP + ry * cos(a) * cosP)
            }
            var a = theta1
            for k in 0..<segments {
                let b = a + step
                let pa = point(a), pb = k == segments - 1 ? p1 : point(b)
                let ta = tangent(a), tb = tangent(b)
                path.addCurve(to: pb,
                              control1: CGPoint(x: pa.x + t * ta.x, y: pa.y + t * ta.y),
                              control2: CGPoint(x: pb.x - t * tb.x, y: pb.y - t * tb.y))
                a = b
            }
        }

        // MARK: Zahlen

        private func isLetter(_ x: UInt8) -> Bool {
            (x >= 65 && x <= 90 || x >= 97 && x <= 122) && x != UInt8(ascii: "e") && x != UInt8(ascii: "E")
        }

        private mutating func skip() {
            while i < c.count, c[i] == 32 || c[i] == 44 || c[i] == 10 || c[i] == 9 || c[i] == 13 { i += 1 }
        }

        private mutating func point(_ base: CGPoint) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: base.x + x, y: base.y + y)
        }

        private mutating func flag() -> Bool? {
            skip()
            guard i < c.count, c[i] == 48 || c[i] == 49 else { return nil }
            defer { i += 1 }
            return c[i] == 49
        }

        private mutating func number() -> CGFloat? {
            skip()
            guard i < c.count else { return nil }
            let begin = i
            if c[i] == 43 || c[i] == 45 { i += 1 } // + -
            var dot = false, digits = false
            while i < c.count {
                let x = c[i]
                if x >= 48 && x <= 57 { digits = true; i += 1 }
                else if x == 46, !dot { dot = true; i += 1 }
                else if (x == 101 || x == 69), digits {
                    i += 1
                    if i < c.count, c[i] == 43 || c[i] == 45 { i += 1 }
                    while i < c.count, c[i] >= 48 && c[i] <= 57 { i += 1 }
                    break
                } else { break }
            }
            guard digits, let s = String(bytes: c[begin..<i], encoding: .ascii), let v = Double(s) else {
                i = begin
                return nil
            }
            return CGFloat(v)
        }
    }
}
