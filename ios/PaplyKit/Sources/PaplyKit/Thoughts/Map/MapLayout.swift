import CoreGraphics
import Foundation

// „Landkarte“ der Gedanken: deterministische Anordnung als reine Funktion (Entwurf
// docs/prototypes/paply-ios/gedanken-richtungen.html, Richtung 2).
//
// - Themen sind Kreise; der Radius wächst mit der Wurzel der Anzahl und ist gedeckelt.
// - Jedes Thema belegt eine feste Fläche: Kreis samt Punkte-Ringen und darunter ein reserviertes Feld für
//   die Beschriftung. Zwei Flächen halten immer mindestens `gap` Abstand – nichts überlappt.
// - Orientierung bleibt: Ein Thema mit gemerktem Anker bleibt dort. Wächst ein Kreis, bewegt sich nur, was
//   er berührt, und so wenig wie möglich (`MapGeometry.resolve`: Nachbarn weichen nach außen, oder – am Rand
//   oft kürzer – der gewachsene Kreis rückt selbst ein Stück; gewählt wird der kleinere Gesamtweg). Ein
//   neues Thema kommt an eine freie Stelle (Berührpunkte rund um die vorhandenen Themen): dorthin, wo der
//   Rahmen der Karte im Bildschirmformat am wenigsten wächst, bei Gleichstand möglichst nahe der Mitte.
//   Es wird nie alles neu sortiert.
// - Punkte liegen auf einem Bogen über dem Kreis (220°, Beschriftung frei darunter), innen die neuesten.
//   Die Ringe laufen als Schlange (Ring 0: neuester rechts, Ring 1: neuester links …): Kommt ein Gedanke
//   dazu, rückt jeder Punkt nur einen Platz weiter. Höchstens `maxDots` je Thema, der Rest steckt im Kreis.
// - Linien nur für echte Verknüpfungen, höchstens `maxLinksPerThought` je Gedanke, neueste zuerst. Für die
//   Übersicht zusätzlich gebündelt je Themenpaar (`topicLines`), damit es bei vielen Gedanken ruhig bleibt.
//
// Keine Zufälle, keine Uhrzeit, keine Abhängigkeit von der Reihenfolge der Eingabe oder von der
// Reihenfolge eines Dictionarys. Einheiten: Kartenpunkte (bei Maßstab 1 = Bildschirmpunkte).

/// Gemerkter Platz eines Themas (Mittelpunkt des Kreises in Kartenpunkten)
public struct MapAnchor: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    public var point: CGPoint { CGPoint(x: x, y: y) }
}

public struct MapLayoutInput: Sendable, Equatable {
    public struct Topic: Sendable, Equatable {
        public var id: String
        /// Gedanken im Thema (bestimmt die Größe). 0 = ruht: wird nicht gezeichnet, behält aber seinen Anker.
        public var count: Int
        public var lastActivity: Date
        /// Zeilen unter dem Namen (Titel bei sehr wenigen Gedanken); reserviert Platz
        public var titleLines: Int

        public init(id: String, count: Int, lastActivity: Date, titleLines: Int = 0) {
            self.id = id
            self.count = count
            self.lastActivity = lastActivity
            self.titleLines = titleLines
        }
    }

    public struct Thought: Sendable, Equatable {
        public var id: String
        /// Thema (Gedanken ohne Thema bekommen vom Aufrufer ein Pseudo-Thema)
        public var topicID: String
        public var createdAt: Date

        public init(id: String, topicID: String, createdAt: Date) {
            self.id = id
            self.topicID = topicID
            self.createdAt = createdAt
        }
    }

    /// Verknüpfung zweier Gedanken (Richtung egal)
    public struct Link: Sendable, Equatable {
        public var from: String
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public var topics: [Topic]
    public var thoughts: [Thought]
    public var links: [Link]
    /// Themen-ID → gemerkter Mittelpunkt
    public var anchors: [String: MapAnchor]

    public init(topics: [Topic], thoughts: [Thought], links: [Link] = [], anchors: [String: MapAnchor] = [:]) {
        self.topics = topics
        self.thoughts = thoughts
        self.links = links
        self.anchors = anchors
    }
}

/// Maße der Karte (Kartenpunkte). Die Vorgaben sind auf ein iPhone im Hochformat abgestimmt.
public struct MapLayoutConfig: Sendable, Equatable {
    public var minRadius: CGFloat = 20
    public var radiusPerRoot: CGFloat = 7
    public var maxRadius: CGFloat = 62
    /// Mindestabstand zwischen den Flächen zweier Themen
    public var gap: CGFloat = 16
    /// Punkte je Thema, der Rest steckt im Kreis
    public var maxDots: Int = 24
    /// Abstand Kreisrand → erster Ring
    public var firstRing: CGFloat = 12
    public var ringStep: CGFloat = 12
    /// kleinster und größter Bogenabstand zweier Punkte auf einem Ring (mit 11 passen bei der Radius-Formel
    /// immer alle 24 Punkte auf den inneren Bogen; weitere Ringe sind nur Rückfall für andere Maße)
    public var dotSpacing: CGFloat = 11
    public var maxDotSpacing: CGFloat = 22
    public var dotRadius: CGFloat = 4
    /// Bogen der Punkte über dem Kreis (unten bleibt Platz für die Beschriftung)
    public var arc: CGFloat = 220 * .pi / 180
    /// Beschriftung: Abstand unter dem Kreis, Höhe, Mindestbreite
    public var labelGap: CGFloat = 8
    public var labelHeight: CGFloat = 20
    public var labelWidth: CGFloat = 112
    /// Titel unter dem Namen (sehr wenige Gedanken)
    public var titleLineHeight: CGFloat = 17
    public var titleWidth: CGFloat = 196
    public var maxLinksPerThought: Int = 2
    public var maxLines: Int = 600
    /// Übersicht: höchstens so viele Themen-Linien je Thema (die stärksten)
    public var maxTopicLinesPerTopic: Int = 3
    /// gewünschtes Seitenverhältnis (Breite : Höhe) beim Anlegen neuer Themen – hochformatig wie der sichtbare
    /// Teil des Bildschirms (gemessen: 0,58 ergibt im Mittel den größten Maßstab für 4 … 25 Themen)
    public var aspect: CGFloat = 0.58
    /// Richtungen rund um jedes Thema, in denen ein neues Thema anlegen darf
    public var directions: Int = 36

    public init() {}

    /// Radius eines Kreises mit `count` Gedanken (Wurzel, gedeckelt)
    public func radius(for count: Int) -> CGFloat {
        min(maxRadius, minRadius + radiusPerRoot * CGFloat(max(1, count)).squareRoot())
    }
}

public struct MapLayout: Sendable, Equatable {
    public struct Bubble: Sendable, Equatable, Identifiable {
        public var id: String
        public var center: CGPoint
        public var radius: CGFloat
        /// äußerster Punkte-Ring samt Punkt (= `radius`, wenn es keine Punkte gibt)
        public var outerRadius: CGFloat
        /// reserviertes Feld für Name, Anzahl und ggf. Titel (Kartenpunkte, absolut)
        public var label: CGRect
        public var count: Int
        /// Gedanken ohne eigenen Punkt („stecken im Kreis“)
        public var hiddenCount: Int
        public var titleLines: Int
    }

    public struct Dot: Sendable, Equatable, Identifiable {
        /// Gedanken-ID
        public var id: String
        public var topicID: String
        public var position: CGPoint
        /// Richtung vom Kreismittelpunkt (Bogenmaß, y nach unten; −π/2 = oben)
        public var angle: CGFloat
        public var ring: Int
        /// 0 = neuester Gedanke des Themas
        public var rank: Int
    }

    public struct Line: Sendable, Equatable, Identifiable {
        public var id: String { a + "|" + b }
        /// Gedanken-IDs (a < b)
        public var a: String
        public var b: String
        public var topicA: String
        public var topicB: String
        /// quadratische Kurve von `from` über `control` nach `to`
        public var from: CGPoint
        public var control: CGPoint
        public var to: CGPoint
        /// verbindet zwei Themen (ganz fein, in der Übersicht sichtbar)
        public var crossTopic: Bool
        /// ein Ende sitzt am Kreisrand, weil der Gedanke keinen eigenen Punkt hat
        public var touchesHidden: Bool
    }

    /// Übersicht: eine feine Linie je verbundenem Themenpaar (Kreisrand zu Kreisrand)
    public struct TopicLine: Sendable, Equatable, Identifiable {
        public var id: String { a + "|" + b }
        /// Themen-IDs (a < b)
        public var a: String
        public var b: String
        /// Verknüpfungen zwischen Gedanken der beiden Themen
        public var count: Int
        public var from: CGPoint
        public var control: CGPoint
        public var to: CGPoint
    }

    /// nach ID sortiert
    public var bubbles: [Bubble]
    /// je Thema nach Rang, Themen nach ID
    public var dots: [Dot]
    public var lines: [Line]
    /// Übersicht: Themenpaare, stärkste zuerst
    public var topicLines: [TopicLine]
    /// umschließt Kreise, Ringe, Beschriftungsfelder und Linien; `.zero` ohne Themen
    public var bounds: CGRect
    /// alle Anker zum Merken: gezeichnete Themen und ruhende (Anzahl 0) mit altem Anker
    public var anchors: [String: MapAnchor]

    public static let empty = MapLayout(bubbles: [], dots: [], lines: [], topicLines: [], bounds: .zero, anchors: [:])

    public func bubble(_ id: String) -> Bubble? {
        bubbles.first { $0.id == id }
    }
}

// MARK: - Berechnung

extension MapLayout {
    /// Gleiche Eingabe → gleiche Ausgabe. Kosten: Themen O(n²·Richtungen) nur beim Anlegen, Gedanken O(m log m).
    public static func compute(_ input: MapLayoutInput, config: MapLayoutConfig = MapLayoutConfig()) -> MapLayout {
        // Themen: erstes Vorkommen je ID; gezeichnet werden nur Themen mit Gedanken
        var seen = Set<String>()
        var active: [MapLayoutInput.Topic] = []
        var dormant: [String] = []
        for topic in input.topics where seen.insert(topic.id).inserted {
            if topic.count > 0 { active.append(topic) } else { dormant.append(topic.id) }
        }
        let activeIDs = Set(active.map(\.id))

        // Gedanken je Thema, neueste zuerst (gleiche Zeit: nach ID)
        var byTopic: [String: [MapLayoutInput.Thought]] = [:]
        var thoughtSeen = Set<String>()
        for thought in input.thoughts where activeIDs.contains(thought.topicID) && thoughtSeen.insert(thought.id).inserted {
            byTopic[thought.topicID, default: []].append(thought)
        }
        for key in byTopic.keys {
            byTopic[key]?.sort { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id < $1.id }
        }

        // Flächen
        active.sort { $0.id < $1.id }
        var items: [MapFootprint] = active.map { topic in
            let shown = min(config.maxDots, byTopic[topic.id]?.count ?? 0)
            return MapFootprint(id: topic.id, center: .zero, radius: config.radius(for: topic.count),
                                dots: shown, titleLines: max(0, topic.titleLines), config: config)
        }

        // 1. Themen mit Anker an ihren Platz, Überlappungen durch Wachstum minimal auflösen
        var placed: [MapFootprint] = []
        var fresh: [Int] = []
        for i in items.indices {
            if let anchor = input.anchors[items[i].id], anchor.x.isFinite, anchor.y.isFinite {
                items[i].center = MapGeometry.snap(anchor.point)
                placed.append(items[i])
            } else {
                fresh.append(i)
            }
        }
        MapGeometry.resolve(&placed, config: config)

        // 2. Neue Themen: zuletzt aktive zuerst (sie liegen dann am nächsten an der Mitte), Pseudo-Themen zuletzt
        let lookup = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        fresh.sort { a, b in
            let x = lookup[items[a].id]!, y = lookup[items[b].id]!
            let px = x.id.hasPrefix("_"), py = y.id.hasPrefix("_")
            if px != py { return !px }
            if x.lastActivity != y.lastActivity { return x.lastActivity > y.lastActivity }
            if x.count != y.count { return x.count > y.count }
            return x.id < y.id
        }
        for i in fresh {
            var item = items[i]
            item.center = MapGeometry.findSpot(for: item, among: placed, config: config)
            placed.append(item)
        }

        // 3. Sicherheitsnetz: Was sich (theoretisch) nicht auflösen ließ, sucht sich einen freien Platz
        MapGeometry.separateRemaining(&placed, config: config)

        placed.sort { $0.id < $1.id }

        // Punkte
        var bubbles: [MapLayout.Bubble] = []
        var dots: [MapLayout.Dot] = []
        var anchors: [String: MapAnchor] = [:]
        var dotIndex: [String: Int] = [:]
        var placedByID: [String: MapFootprint] = [:]
        for item in placed {
            let topic = lookup[item.id]!
            let list = byTopic[item.id] ?? []
            let shown = Array(list.prefix(config.maxDots))
            for (rank, slot) in MapGeometry.dotSlots(count: shown.count, radius: item.radius, config: config).enumerated() {
                let thought = shown[rank]
                dotIndex[thought.id] = dots.count
                dots.append(MapLayout.Dot(id: thought.id, topicID: item.id,
                                          position: CGPoint(x: item.center.x + slot.offset.dx, y: item.center.y + slot.offset.dy),
                                          angle: slot.angle, ring: slot.ring, rank: rank))
            }
            bubbles.append(MapLayout.Bubble(id: item.id, center: item.center, radius: item.radius, outerRadius: item.outer,
                                            label: item.labelRect, count: topic.count,
                                            hiddenCount: max(0, topic.count - shown.count), titleLines: item.titleLines))
            anchors[item.id] = MapAnchor(item.center)
            placedByID[item.id] = item
        }
        for id in dormant {
            if let anchor = input.anchors[id] { anchors[id] = anchor }
        }

        // Linien
        var created: [String: (topic: String, date: Date)] = [:]
        for (topic, list) in byTopic {
            for thought in list { created[thought.id] = (topic, thought.createdAt) }
        }
        let lines = MapGeometry.lines(input.links, created: created, dots: dots, dotIndex: dotIndex,
                                      footprints: placedByID, config: config)

        // Rahmen
        var bounds = CGRect.null
        for item in placed {
            bounds = bounds.union(item.circleRect).union(item.labelRect)
        }
        let topicLines = MapGeometry.topicLines(input.links, created: created, footprints: placedByID, config: config)
        for line in topicLines {
            let apex = CGPoint(x: 0.25 * line.from.x + 0.5 * line.control.x + 0.25 * line.to.x,
                               y: 0.25 * line.from.y + 0.5 * line.control.y + 0.25 * line.to.y)
            bounds = bounds.union(CGRect(x: apex.x - 1, y: apex.y - 1, width: 2, height: 2))
        }
        for line in lines {
            // Scheitel der Kurve (t = ½)
            let apex = CGPoint(x: 0.25 * line.from.x + 0.5 * line.control.x + 0.25 * line.to.x,
                               y: 0.25 * line.from.y + 0.5 * line.control.y + 0.25 * line.to.y)
            bounds = bounds.union(CGRect(x: apex.x - 1, y: apex.y - 1, width: 2, height: 2))
        }
        return MapLayout(bubbles: bubbles, dots: dots, lines: lines, topicLines: topicLines,
                         bounds: bounds.isNull ? .zero : bounds, anchors: anchors)
    }
}

// MARK: - Fläche eines Themas

/// Kreis samt Punkte-Ringen (Kreis mit Radius `outer`) und Beschriftungsfeld darunter.
struct MapFootprint: Sendable, Equatable {
    var id: String
    var center: CGPoint
    var radius: CGFloat
    var outer: CGFloat
    var titleLines: Int
    /// Beschriftungsfeld relativ zum Mittelpunkt
    var label: CGRect
    /// Radius eines Kreises um den Mittelpunkt, der alles umschließt
    var bound: CGFloat
    /// Gewicht beim Ausweichen (größere Flächen bewegen sich weniger)
    var mass: CGFloat
    /// Beschriftungsfeld relativ, als Zahlen (schnell in der heißen Schleife)
    let lx0: CGFloat, ly0: CGFloat, lx1: CGFloat, ly1: CGFloat

    init(id: String, center: CGPoint, radius: CGFloat, dots: Int, titleLines: Int, config: MapLayoutConfig) {
        self.id = id
        self.center = center
        self.radius = radius
        self.titleLines = titleLines
        let rings = MapGeometry.ringCount(dots: dots, radius: radius, config: config)
        outer = rings == 0 ? radius : radius + config.firstRing + CGFloat(rings - 1) * config.ringStep + config.dotRadius
        let width = titleLines > 0 ? max(config.titleWidth, 2 * radius + 16) : max(config.labelWidth, 2 * radius + 16)
        let height = config.labelHeight + (titleLines > 0 ? CGFloat(titleLines) * config.titleLineHeight + 4 : 0)
        label = CGRect(x: -width / 2, y: radius + config.labelGap, width: width, height: height)
        lx0 = -width / 2
        lx1 = width / 2
        ly0 = radius + config.labelGap
        ly1 = radius + config.labelGap + height
        let corner = max(hypot(label.minX, label.maxY), hypot(label.maxX, label.maxY))
        bound = max(outer, corner)
        mass = outer * outer
    }

    var labelRect: CGRect { label.offsetBy(dx: center.x, dy: center.y) }
    var circleRect: CGRect { CGRect(x: center.x - outer, y: center.y - outer, width: 2 * outer, height: 2 * outer) }
}

// MARK: - Geometrie

enum MapGeometry {
    /// Wie weit `b` in `a` steckt (inkl. Mindestabstand) und in welche Richtung `b` weichen müsste.
    struct Push: Equatable {
        var dx: CGFloat
        var dy: CGFloat
        var depth: CGFloat
    }

    /// kleiner als das: gilt als frei (Rundung der Anker)
    static let tolerance: CGFloat = 0.01
    /// so viel zusätzlich beim Auseinanderschieben und Anlegen, damit Runden nichts wieder überlappen lässt
    static let slack: CGFloat = 0.05

    /// Mittelpunkte liegen immer auf 1/100 Kartenpunkt: Was geprüft wird, ist genau das, was gespeichert
    /// wird – mit den eigenen Ankern ergibt sich exakt dieselbe Karte.
    static func snap(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x * 100).rounded() / 100, y: (p.y * 100).rounded() / 100)
    }

    static func penetration(_ a: MapFootprint, _ b: MapFootprint, gap: CGFloat) -> Push? {
        let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y
        let reach = a.bound + b.bound + gap
        if dx * dx + dy * dy >= reach * reach { return nil }
        var best: Push?
        func consider(_ push: Push?) {
            guard let push, push.depth > (best?.depth ?? 0) else { return }
            best = push
        }
        let ax = a.center.x, ay = a.center.y, bx = b.center.x, by = b.center.y
        consider(circleCircle(ax, ay, a.outer, bx, by, b.outer, gap: gap))
        consider(circleRect(ax, ay, a.outer, bx + b.lx0, by + b.ly0, bx + b.lx1, by + b.ly1, gap: gap, circleIsA: true))
        consider(circleRect(bx, by, b.outer, ax + a.lx0, ay + a.ly0, ax + a.lx1, ay + a.ly1, gap: gap, circleIsA: false))
        consider(rectRect(ax + a.lx0, ay + a.ly0, ax + a.lx1, ay + a.ly1, bx + b.lx0, by + b.ly0, bx + b.lx1, by + b.ly1, gap: gap))
        return best
    }

    static func overlaps(_ a: MapFootprint, _ b: MapFootprint, gap: CGFloat) -> Bool {
        (penetration(a, b, gap: gap)?.depth ?? 0) > tolerance
    }

    private static func circleCircle(_ ax: CGFloat, _ ay: CGFloat, _ ra: CGFloat, _ bx: CGFloat, _ by: CGFloat, _ rb: CGFloat,
                                     gap: CGFloat) -> Push? {
        let dx = bx - ax, dy = by - ay
        let d = (dx * dx + dy * dy).squareRoot()
        let depth = ra + rb + gap - d
        guard depth > 0 else { return nil }
        if d < 1e-9 { return Push(dx: 0, dy: 1, depth: depth) }
        return Push(dx: dx / d, dy: dy / d, depth: depth)
    }

    /// Richtung immer von a nach b; `circleIsA`: der Kreis gehört zu a, das Feld (x0 … x1, y0 … y1) zu b
    private static func circleRect(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat,
                                   _ y1: CGFloat, gap: CGFloat, circleIsA: Bool) -> Push? {
        let qx = min(max(cx, x0), x1), qy = min(max(cy, y0), y1)
        let vx = cx - qx, vy = cy - qy
        let d2 = vx * vx + vy * vy
        let limit = r + gap
        if d2 >= limit * limit { return nil }
        var nx: CGFloat, ny: CGFloat, depth: CGFloat // n: vom Feld zum Kreis
        let d = d2.squareRoot()
        if d > 1e-9 {
            depth = limit - d
            nx = vx / d
            ny = vy / d
        } else {
            // Mittelpunkt im Feld: zur nächsten Kante hinaus
            let left = cx - x0, right = x1 - cx, top = cy - y0, bottom = y1 - cy
            let m = min(left, right, top, bottom)
            if m == top { nx = 0; ny = -1 } else if m == bottom { nx = 0; ny = 1 } else if m == left { nx = -1; ny = 0 } else { nx = 1; ny = 0 }
            depth = limit + m
        }
        return circleIsA ? Push(dx: -nx, dy: -ny, depth: depth) : Push(dx: nx, dy: ny, depth: depth)
    }

    private static func rectRect(_ ax0: CGFloat, _ ay0: CGFloat, _ ax1: CGFloat, _ ay1: CGFloat,
                                 _ bx0: CGFloat, _ by0: CGFloat, _ bx1: CGFloat, _ by1: CGFloat, gap: CGFloat) -> Push? {
        let ox = min(ax1, bx1) - max(ax0, bx0) + gap
        let oy = min(ay1, by1) - max(ay0, by0) + gap
        guard ox > 0, oy > 0 else { return nil }
        if ox < oy { return Push(dx: (bx0 + bx1) >= (ax0 + ax1) ? 1 : -1, dy: 0, depth: ox) }
        return Push(dx: 0, dy: (by0 + by1) >= (ay0 + ay1) ? 1 : -1, depth: oy)
    }

    // MARK: Ausweichen

    static func hasOverlap(_ items: [MapFootprint], gap: CGFloat) -> Bool {
        for i in items.indices {
            for j in items.indices where j > i && overlaps(items[i], items[j], gap: gap) { return true }
        }
        return false
    }

    /// Überlappungen (z. B. weil ein Kreis gewachsen ist) mit möglichst wenig Bewegung auflösen. Zwei Wege,
    /// genommen wird der mit der kleineren Summe der quadrierten Wege – lieber wenige kleine Schritte als ein
    /// großer Sprung:
    /// (a) Schubwelle: Die größte beteiligte Fläche bleibt stehen, nur berührte Nachbarn weichen nach außen,
    ///     und nur, wen sie dabei berühren, weicht weiter. Wer einmal geschoben hat, bewegt sich nicht mehr.
    /// (b) Umzug: Die größte beteiligte Fläche rückt selbst an die nächste freie Stelle (typisch am Rand).
    /// Wer nichts berührt, bewegt sich in beiden Wegen nicht.
    static func resolve(_ items: inout [MapFootprint], config: MapLayoutConfig) {
        guard items.count > 1, hasOverlap(items, gap: config.gap) else { return }
        let original = items.map(\.center)
        func cost(_ list: [MapFootprint]) -> CGFloat {
            var sum: CGFloat = 0
            for i in list.indices {
                let dx = list[i].center.x - original[i].x, dy = list[i].center.y - original[i].y
                sum += dx * dx + dy * dy
            }
            return sum
        }
        var wave = items
        pushWave(&wave, config: config)
        var hop = items
        relocate(&hop, config: config)
        items = cost(hop) < cost(wave) ? hop : wave
    }

    private static func byMass(_ items: [MapFootprint], _ indices: [Int]) -> [Int] {
        indices.sorted { a, b in items[a].mass != items[b].mass ? items[a].mass > items[b].mass : items[a].id < items[b].id }
    }

    private static func pushWave(_ items: inout [MapFootprint], config: MapLayoutConfig) {
        let n = items.count
        var involved = [Bool](repeating: false, count: n)
        for i in 0..<n {
            for j in (i + 1)..<n where overlaps(items[i], items[j], gap: config.gap) {
                involved[i] = true
                involved[j] = true
            }
        }
        var queue = byMass(items, (0..<n).filter { involved[$0] })
        var settled = [Bool](repeating: false, count: n)
        var head = 0
        while head < queue.count {
            let p = queue[head]
            head += 1
            guard !settled[p] else { continue }
            settled[p] = true
            for q in 0..<n where !settled[q] {
                guard let push = penetration(items[p], items[q], gap: config.gap), push.depth > tolerance else { continue }
                let before = items[q].center
                let d = push.depth + slack
                items[q].center = snap(CGPoint(x: before.x + push.dx * d, y: before.y + push.dy * d))
                // gegen eine schon feste Fläche gedrückt: nächste freie Stelle zwischen den festen
                let fixed = (0..<n).filter { settled[$0] }.map { items[$0] }
                if fixed.contains(where: { overlaps($0, items[q], gap: config.gap) }) {
                    items[q].center = freeSpot(for: items[q], among: fixed, config: config, near: before)
                }
                queue.append(q)
            }
        }
    }

    private static func relocate(_ items: inout [MapFootprint], config: MapLayoutConfig) {
        for i in byMass(items, Array(items.indices)) {
            let others = items.indices.filter { $0 != i }.map { items[$0] }
            guard others.contains(where: { overlaps($0, items[i], gap: config.gap) }) else { continue }
            items[i].center = freeSpot(for: items[i], among: others, config: config, near: items[i].center)
        }
    }

    /// Sicherheitsnetz: Bleibt etwas überlappend, sucht sich die kleinere Fläche einen freien Platz in der
    /// Nähe. Danach überlappt garantiert nichts.
    static func separateRemaining(_ items: inout [MapFootprint], config: MapLayoutConfig) {
        guard items.count > 1 else { return }
        for _ in 0..<items.count {
            var victim: Int?
            outer: for i in 0..<(items.count - 1) {
                for j in (i + 1)..<items.count where overlaps(items[i], items[j], gap: config.gap) {
                    let a = items[i], b = items[j]
                    victim = (a.mass, a.id) < (b.mass, b.id) ? i : j
                    break outer
                }
            }
            guard let index = victim else { return }
            let others = items.indices.filter { $0 != index }.map { items[$0] }
            items[index].center = freeSpot(for: items[index], among: others, config: config, near: items[index].center)
        }
    }

    // MARK: Freier Platz

    /// Neues Thema: Es kommt dorthin, wo der Rahmen der Karte – gemessen im Seitenverhältnis des Bildschirms –
    /// am wenigsten wächst (so füllen sich Lücken zuerst und die Karte bleibt bildschirmförmig); bei Gleichstand
    /// entscheidet die Nähe zur Mitte (elliptischer Abstand, hochformatig).
    static func findSpot(for item: MapFootprint, among placed: [MapFootprint], config: MapLayoutConfig) -> CGPoint {
        guard !placed.isEmpty else { return .zero }
        return freeSpot(for: item, among: placed, config: config, near: nil)
    }

    /// Freier Platz mit den kleinsten Kosten. Kandidaten: der Wunschpunkt selbst und die Berührpunkte rund um
    /// jede Fläche in `directions` Richtungen. `near` = nil: neues Thema (Rahmen, dann Mitte), sonst: nahe `near`.
    static func freeSpot(for item: MapFootprint, among placed: [MapFootprint], config: MapLayoutConfig, near: CGPoint?) -> CGPoint {
        var box = CGRect.null
        for p in placed { box = box.union(p.circleRect).union(p.labelRect) }
        guard !box.isNull else { return near.map(snap) ?? .zero }
        let target = snap(near ?? CGPoint(x: box.midX, y: box.midY))
        let aspect = near == nil ? max(0.2, config.aspect) : 1
        func cost(_ c: CGPoint) -> CGFloat {
            let dx = (c.x - target.x) / aspect, dy = c.y - target.y
            return dx * dx + dy * dy
        }
        // Größe des Rahmens im Bildschirmformat (halbe Punkte, damit Rundungsrauschen nicht entscheidet)
        func size(_ r: CGRect) -> CGFloat { (max(r.width / aspect, r.height) * 2).rounded() / 2 }
        let ix0 = min(-item.outer, item.lx0), ix1 = max(item.outer, item.lx1)
        let iy0 = min(-item.outer, item.ly0), iy1 = max(item.outer, item.ly1)
        let bx0 = box.minX, bx1 = box.maxX, by0 = box.minY, by1 = box.maxY
        let base = near == nil ? size(box) : 0
        func rawExtent(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let w = max(bx1, x + ix1) - min(bx0, x + ix0), h = max(by1, y + iy1) - min(by0, y + iy0)
            return max(w / aspect, h)
        }
        func extent(_ c: CGPoint) -> CGFloat {
            guard near == nil else { return 0 }
            return (rawExtent(c.x, c.y) * 2).rounded() / 2
        }
        func isFree(_ c: CGPoint) -> Bool {
            var probe = item
            probe.center = c
            for other in placed where overlaps(probe, other, gap: config.gap) { return false }
            return true
        }

        var best: CGPoint?
        var bestExtent = CGFloat.infinity
        var bestCost = CGFloat.infinity
        func better(_ e: CGFloat, _ v: CGFloat) -> Bool { e != bestExtent ? e < bestExtent : v < bestCost }
        if isFree(target) {
            best = target
            bestExtent = extent(target)
            bestCost = cost(target)
        }
        let k = max(8, config.directions)
        // nahe Flächen zuerst: Ein guter Platz fällt früh, danach lässt sich mehr überspringen
        let order = placed.indices.sorted { a, b in
            let ca = cost(placed[a].center), cb = cost(placed[b].center)
            return ca != cb ? ca < cb : a < b
        }
        for index in order {
            let anchor = placed[index]
            // Überspringen lässt sich nur, wenn der beste Platz den Rahmen nicht vergrößert (kleiner geht nicht):
            // dann zählt allein die Nähe, und Kandidaten um diese Fläche liegen nie näher als ihr Rand.
            let pruning = bestExtent <= base
            let reach = anchor.bound + item.bound + config.gap + 1
            let ex = (anchor.center.x - target.x) / aspect, ey = anchor.center.y - target.y
            let lower = max(0, (ex * ex + ey * ey).squareRoot() - reach / aspect)
            if pruning, lower * lower >= bestCost { continue }
            // Kreise allein brauchen schon so viel Abstand – der Berührpunkt liegt nie näher
            let tMin = anchor.outer + item.outer + config.gap
            for step in 0..<k {
                let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(k)
                let ux = cos(angle), uy = sin(angle)
                if near == nil, bestExtent < .infinity {
                    // Rahmen entlang des Strahls ist konvex: Wächst er ab tMin schon, ist das die Untergrenze
                    let x0 = anchor.center.x + ux * tMin, y0 = anchor.center.y + uy * tMin
                    let e0 = rawExtent(x0, y0)
                    if rawExtent(x0 + ux, y0 + uy) >= e0, (e0 * 2).rounded() / 2 > bestExtent { continue }
                }
                if bestExtent <= base {
                    // günstigster denkbarer Punkt auf dem Strahl ab tMin (Kosten sind entlang des Strahls quadratisch)
                    let px = (anchor.center.x - target.x) / aspect, py = anchor.center.y - target.y
                    let vx = ux / aspect, vy = uy
                    let vertex = -(px * vx + py * vy) / (vx * vx + vy * vy)
                    let tBest = max(tMin, vertex)
                    let bx = px + vx * tBest, by = py + vy * tBest
                    if bx * bx + by * by >= bestCost { continue }
                }
                let t = contact(item, around: anchor, ux: ux, uy: uy, from: tMin, gap: config.gap)
                let c = snap(CGPoint(x: anchor.center.x + ux * t, y: anchor.center.y + uy * t))
                let e = extent(c), value = cost(c)
                guard better(e, value), isFree(c) else { continue }
                best = c
                bestExtent = e
                bestCost = value
            }
        }
        if let best { return best }
        // Rückfall (kommt praktisch nicht vor): rechts neben alles
        return snap(CGPoint(x: box.maxX + item.bound + config.gap + 2 * slack, y: target.y))
    }

    /// Kleinster Abstand entlang (ux, uy), ab dem `item` die Fläche `anchor` nicht mehr berührt.
    private static func contact(_ item: MapFootprint, around anchor: MapFootprint, ux: CGFloat, uy: CGFloat,
                                from tMin: CGFloat, gap: CGFloat) -> CGFloat {
        var probe = item
        // häufigster Fall: Am Mindestabstand der Kreise stört auch kein Beschriftungsfeld
        probe.center = CGPoint(x: anchor.center.x + ux * tMin, y: anchor.center.y + uy * tMin)
        if !overlaps(anchor, probe, gap: gap) { return tMin + slack }
        var lo = max(0, tMin - 0.05) // hier überlappen die Kreise sicher
        var hi = max(lo + 0.1, anchor.bound + item.bound + gap + 1)
        for _ in 0..<14 {
            let mid = (lo + hi) / 2
            probe.center = CGPoint(x: anchor.center.x + ux * mid, y: anchor.center.y + uy * mid)
            if overlaps(anchor, probe, gap: gap) { lo = mid } else { hi = mid }
        }
        return hi + slack
    }

    // MARK: Punkte

    struct DotSlot: Equatable {
        var offset: CGVector
        var angle: CGFloat
        var ring: Int
    }

    /// Plätze auf jedem Ring, solange der Mindestabstand passt
    static func ringCapacity(_ ring: Int, radius: CGFloat, config: MapLayoutConfig) -> Int {
        let r = radius + config.firstRing + CGFloat(ring) * config.ringStep
        return max(1, Int((r * config.arc / config.dotSpacing).rounded(.down)) + 1)
    }

    static func ringCount(dots: Int, radius: CGFloat, config: MapLayoutConfig) -> Int {
        var remaining = dots, ring = 0
        while remaining > 0 {
            remaining -= ringCapacity(ring, radius: radius, config: config)
            ring += 1
        }
        return ring
    }

    /// Platz für Rang 0 (neuester) … count−1. Der innerste Ring liegt mittig über dem Kreis (neuester rechts).
    /// Äußere Ringe gibt es nur, wenn der innere voll ist (er reicht dann über den ganzen Bogen); sie beginnen
    /// an der Kante, an der der innere endet – eine Schlange: Kommt ein Gedanke dazu, rückt jeder Punkt nur
    /// einen Platz weiter, nichts springt über den Kreis.
    static func dotSlots(count: Int, radius: CGFloat, config: MapLayoutConfig) -> [DotSlot] {
        var slots: [DotSlot] = []
        slots.reserveCapacity(count)
        var remaining = count, ring = 0
        let top = -CGFloat.pi / 2
        while remaining > 0 {
            let r = radius + config.firstRing + CGFloat(ring) * config.ringStep
            let capacity = ringCapacity(ring, radius: radius, config: config)
            let n = min(capacity, remaining)
            for j in 0..<n {
                let angle: CGFloat
                if ring == 0 {
                    let step = n > 1 ? min(config.maxDotSpacing / r, config.arc / CGFloat(n - 1)) : 0
                    angle = top + step * (CGFloat(n - 1) / 2 - CGFloat(j))
                } else {
                    let step = capacity > 1 ? config.arc / CGFloat(capacity - 1) : 0
                    // ungerade Ringe: von links nach rechts, gerade: von rechts nach links
                    angle = ring % 2 == 1 ? top - config.arc / 2 + step * CGFloat(j) : top + config.arc / 2 - step * CGFloat(j)
                }
                slots.append(DotSlot(offset: CGVector(dx: r * cos(angle), dy: r * sin(angle)), angle: angle, ring: ring))
            }
            remaining -= n
            ring += 1
        }
        return slots
    }

    // MARK: Linien

    static func lines(_ links: [MapLayoutInput.Link], created: [String: (topic: String, date: Date)],
                      dots: [MapLayout.Dot], dotIndex: [String: Int], footprints: [String: MapFootprint],
                      config: MapLayoutConfig) -> [MapLayout.Line] {
        // Paare einmalig, neueste Verknüpfungen zuerst
        struct Pair { var a: String; var b: String; var newest: Date }
        var unique: [String: Pair] = [:]
        for link in links where link.from != link.to {
            guard let x = created[link.from], let y = created[link.to] else { continue }
            let (a, b) = link.from < link.to ? (link.from, link.to) : (link.to, link.from)
            unique[a + "|" + b] = Pair(a: a, b: b, newest: max(x.date, y.date))
        }
        let pairs = unique.values.sorted { p, q in
            if p.newest != q.newest { return p.newest > q.newest }
            if p.a != q.a { return p.a < q.a }
            return p.b < q.b
        }

        var used: [String: Int] = [:]
        var edgePairs = Set<String>()
        var result: [MapLayout.Line] = []
        for pair in pairs {
            guard result.count < config.maxLines else { break }
            guard (used[pair.a] ?? 0) < config.maxLinksPerThought, (used[pair.b] ?? 0) < config.maxLinksPerThought,
                  let ta = created[pair.a]?.topic, let tb = created[pair.b]?.topic,
                  let fa = footprints[ta], let fb = footprints[tb] else { continue }
            let pa = dotIndex[pair.a].map { dots[$0].position }
            let pb = dotIndex[pair.b].map { dots[$0].position }
            var line: MapLayout.Line
            if ta == tb {
                // im Thema: nur zwischen zwei Punkten, Bogen außen um die Ringe
                guard let pa, let pb else { continue }
                let mx = (pa.x + pb.x) / 2 - fa.center.x, my = (pa.y + pb.y) / 2 - fa.center.y
                let len = (mx * mx + my * my).squareRoot()
                let ux = len > 1 ? mx / len : 0, uy = len > 1 ? my / len : -1
                let reach = fa.outer + 14
                line = MapLayout.Line(a: pair.a, b: pair.b, topicA: ta, topicB: tb, from: pa,
                                      control: CGPoint(x: fa.center.x + ux * reach, y: fa.center.y + uy * reach),
                                      to: pb, crossTopic: false, touchesHidden: false)
            } else {
                // zwischen Themen: fehlt ein Punkt, beginnt die Linie am Kreisrand
                let target = pb ?? fb.center
                let source = pa ?? fa.center
                let from = pa ?? edge(fa, toward: target)
                let to = pb ?? edge(fb, toward: source)
                if pa == nil || pb == nil {
                    // je Themenpaar höchstens eine Linie vom Kreisrand
                    let key = pa == nil && pb == nil ? min(ta, tb) + "|" + max(ta, tb)
                        : (pa == nil ? ta + "|" + pair.b : tb + "|" + pair.a)
                    guard edgePairs.insert(key).inserted else { continue }
                }
                // Biegung immer zur selben Seite (unabhängig von der Eingabereihenfolge)
                let flip = (ta, pair.a) > (tb, pair.b)
                let (s, e) = flip ? (to, from) : (from, to)
                let dx = e.x - s.x, dy = e.y - s.y
                let bend: CGFloat = 0.16
                let control = CGPoint(x: (s.x + e.x) / 2 - dy * bend, y: (s.y + e.y) / 2 + dx * bend)
                line = MapLayout.Line(a: pair.a, b: pair.b, topicA: ta, topicB: tb, from: from, control: control, to: to,
                                      crossTopic: true, touchesHidden: pa == nil || pb == nil)
            }
            used[pair.a, default: 0] += 1
            used[pair.b, default: 0] += 1
            result.append(line)
        }
        return result
    }

    /// Übersicht: Verknüpfungen zwischen Themen gebündelt – je Paar eine Linie, je Thema höchstens die
    /// `maxTopicLinesPerTopic` stärksten (mehr Verknüpfungen, dann neuere, dann ID). Kreisrand zu Kreisrand.
    static func topicLines(_ links: [MapLayoutInput.Link], created: [String: (topic: String, date: Date)],
                           footprints: [String: MapFootprint], config: MapLayoutConfig) -> [MapLayout.TopicLine] {
        struct Pair { var a: String; var b: String; var count: Int; var newest: Date }
        var pairs: [String: Pair] = [:]
        var seen = Set<String>()
        for link in links where link.from != link.to {
            guard let x = created[link.from], let y = created[link.to], x.topic != y.topic else { continue }
            let thoughts = link.from < link.to ? link.from + "|" + link.to : link.to + "|" + link.from
            guard seen.insert(thoughts).inserted else { continue }
            let (a, b) = x.topic < y.topic ? (x.topic, y.topic) : (y.topic, x.topic)
            let newest = max(x.date, y.date)
            if var pair = pairs[a + "|" + b] {
                pair.count += 1
                pair.newest = max(pair.newest, newest)
                pairs[a + "|" + b] = pair
            } else {
                pairs[a + "|" + b] = Pair(a: a, b: b, count: 1, newest: newest)
            }
        }
        let ranked = pairs.values.sorted { p, q in
            if p.count != q.count { return p.count > q.count }
            if p.newest != q.newest { return p.newest > q.newest }
            return (p.a, p.b) < (q.a, q.b)
        }
        var perTopic: [String: Int] = [:]
        var result: [MapLayout.TopicLine] = []
        for pair in ranked {
            guard (perTopic[pair.a] ?? 0) < config.maxTopicLinesPerTopic, (perTopic[pair.b] ?? 0) < config.maxTopicLinesPerTopic,
                  let fa = footprints[pair.a], let fb = footprints[pair.b] else { continue }
            perTopic[pair.a, default: 0] += 1
            perTopic[pair.b, default: 0] += 1
            let from = edge(fa, toward: fb.center), to = edge(fb, toward: fa.center)
            let dx = to.x - from.x, dy = to.y - from.y
            let bend: CGFloat = 0.12
            result.append(MapLayout.TopicLine(a: pair.a, b: pair.b, count: pair.count, from: from,
                                              control: CGPoint(x: (from.x + to.x) / 2 - dy * bend, y: (from.y + to.y) / 2 + dx * bend),
                                              to: to))
        }
        return result
    }

    private static func edge(_ f: MapFootprint, toward p: CGPoint) -> CGPoint {
        let dx = p.x - f.center.x, dy = p.y - f.center.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > 1e-9 else { return CGPoint(x: f.center.x, y: f.center.y - f.radius) }
        return CGPoint(x: f.center.x + dx / d * f.radius, y: f.center.y + dy / d * f.radius)
    }
}
