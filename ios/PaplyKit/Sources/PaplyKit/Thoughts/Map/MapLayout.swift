import CoreGraphics
import Foundation

// „Landkarte“ der Gedanken: deterministische Anordnung als reine Funktion (Entwurf
// docs/prototypes/paply-ios/gedanken-richtungen.html, Richtung 2).
//
// Leitsatz: Die Kreise liegen jedes Mal am selben Platz – sonst verliert man die Orientierung.
//
// - Themen sind Kreise; der Radius wächst mit der Wurzel der Anzahl und ist gedeckelt.
// - Ein gemerkter Mittelpunkt (Anker) ändert sich nie: Wächst ein Kreis, bewegt sich nichts.
// - Damit das geht, hält ein neues Thema beim Anlegen so viel Platz frei, wie es je brauchen kann (Kreis am
//   Deckel samt Punkte-Bogen und Beschriftung, `MapFootprint.reserve`). Neue Themen kommen nur in freien
//   Platz; die Reserven überlappen nie.
// - Reicht der Platz trotzdem nicht (alte Anker, Titelzeilen bei sehr wenigen Gedanken), wird der sichtbare
//   Kreis begrenzt („so groß wie Platz ist“), nie ein Nachbar verschoben.
// - Neue Themen: dorthin, wo der Rahmen der Karte im Bildschirmformat am wenigsten wächst und die Themen
//   ausgewogen um die Mitte liegen, bei Gleichstand möglichst nahe der Mitte – so werden 2–5 Themen ein
//   Dreieck oder Versatz statt einer Spalte.
//   „Ohne Thema“ und der Sammelkreis (Pseudo-Themen, Kennung mit „_“) kommen an den unteren Rand, echte
//   Themen danach nicht mehr darunter.
// - Höchstens `maxBubbles` Kreise: Nutzer-Themen und Themen mit ≥ 2 Gedanken zuerst, dann nach Aktivität.
//   Der Rest steckt im Sammelkreis „Weitere Themen“ (`MapLayout.moreID`), seine Anker bleiben gemerkt.
// - Punkte liegen auf einem Bogen über dem Kreis (220°, Beschriftung frei darunter), innen die neuesten.
//   Höchstens `maxDots` je Thema (und nur so viele, wie auf den Bogen passen), der Rest steckt im Kreis.
// - Linien nur für echte Verknüpfungen, höchstens `maxLinksPerThought` je Gedanke, neueste zuerst. Für die
//   Übersicht wenige, gebündelt je Themenpaar (`topicLines`) – nur, wo die Linie frei verläuft.
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
        /// vom Nutzer angelegt: bekommt wie Themen mit ≥ 2 Gedanken zuerst einen eigenen Kreis
        public var pinned: Bool

        public init(id: String, count: Int, lastActivity: Date, titleLines: Int = 0, pinned: Bool = false) {
            self.id = id
            self.count = count
            self.lastActivity = lastActivity
            self.titleLines = titleLines
            self.pinned = pinned
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
    /// Abstand Kreisrand → Punkte-Bogen
    public var firstRing: CGFloat = 12
    public var ringStep: CGFloat = 12
    /// kleinster und größter Bogenabstand zweier Punkte (mit 11 passen bei der Radius-Formel immer alle
    /// 24 Punkte auf den Bogen)
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
    /// Übersicht: Themen-Linien nur für Paare mit mindestens so vielen Verknüpfungen …
    public var minTopicLinks: Int = 2
    /// … insgesamt höchstens so viele …
    public var maxTopicLines: Int = 6
    /// … und je Thema höchstens so viele (die stärksten)
    public var maxTopicLinesPerTopic: Int = 3
    /// höchstens so viele Kreise; darüber hinaus sammelt „Weitere Themen“
    public var maxBubbles: Int = 24
    /// gewünschtes Seitenverhältnis (Breite : Höhe) beim Anlegen neuer Themen – wie der sichtbare Teil des
    /// Bildschirms über den Leisten (≈ 0,68 auf iPhones im Hochformat)
    public var aspect: CGFloat = 0.68
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
        /// sichtbarer Radius (bei Platzmangel kleiner als die Anzahl verlangt)
        public var radius: CGFloat
        /// Punkte-Bogen samt Punkt (= `radius`, wenn es keine Punkte gibt)
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
        /// Kreis, an dem der Punkt sitzt (bei gesammelten Themen `MapLayout.moreID`)
        public var topicID: String
        public var position: CGPoint
        /// Richtung vom Kreismittelpunkt (Bogenmaß, y nach unten; −π/2 = oben)
        public var angle: CGFloat
        public var ring: Int
        /// 0 = neuester Gedanke des Kreises
        public var rank: Int
    }

    public struct Line: Sendable, Equatable, Identifiable {
        public var id: String { a + "|" + b }
        /// Gedanken-IDs (a < b)
        public var a: String
        public var b: String
        /// Kreise der beiden Gedanken
        public var topicA: String
        public var topicB: String
        /// quadratische Kurve von `from` über `control` nach `to`
        public var from: CGPoint
        public var control: CGPoint
        public var to: CGPoint
        /// verbindet zwei Kreise
        public var crossTopic: Bool
        /// ein Ende sitzt am Kreisrand, weil der Gedanke keinen eigenen Punkt hat
        public var touchesHidden: Bool
    }

    /// Übersicht: eine feine Linie je eng verbundenem Themenpaar (Kreisrand zu Kreisrand)
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
    /// je Kreis nach Rang, Kreise nach ID
    public var dots: [Dot]
    public var lines: [Line]
    /// Übersicht: Themenpaare, stärkste zuerst
    public var topicLines: [TopicLine]
    /// umschließt Kreise, Punkte-Bögen, Beschriftungsfelder und Linien; `.zero` ohne Themen
    public var bounds: CGRect
    /// alle Anker zum Merken: gezeichnete Themen, ruhende (Anzahl 0) und gesammelte mit altem Anker
    public var anchors: [String: MapAnchor]
    /// Themen im Sammelkreis `moreID` (nach ID sortiert, leer = kein Sammelkreis)
    public var collected: [String]

    public static let empty = MapLayout(bubbles: [], dots: [], lines: [], topicLines: [], bounds: .zero, anchors: [:],
                                        collected: [])

    public func bubble(_ id: String) -> Bubble? {
        bubbles.first { $0.id == id }
    }
}

// MARK: - Sammelkreis

extension MapLayout {
    /// Kennung des Sammelkreises „Weitere Themen“ (Themen über `maxBubbles` hinaus)
    public static let moreID = "_more"

    /// Pseudo-Themen („Ohne Thema“, Sammelkreis) beginnen mit „_“: immer ein eigener Kreis, Platz am Rand
    static func isPseudo(_ id: String) -> Bool { id.hasPrefix("_") }

    /// Welche Themen keinen eigenen Kreis bekommen, sondern im Sammelkreis stecken (leer = alle passen).
    /// Pseudo-Themen zählen mit; wird gesammelt, belegt der Sammelkreis selbst einen Platz.
    public static func collected(_ topics: [MapLayoutInput.Topic], config: MapLayoutConfig = MapLayoutConfig()) -> Set<String> {
        var seen = Set<String>()
        var real: [MapLayoutInput.Topic] = []
        var pseudo = 0
        for topic in topics where topic.id != moreID && seen.insert(topic.id).inserted && topic.count > 0 {
            if isPseudo(topic.id) { pseudo += 1 } else { real.append(topic) }
        }
        let room = max(1, config.maxBubbles - pseudo)
        guard real.count > room else { return [] }
        real.sort(by: ranksBefore)
        return Set(real.dropFirst(max(0, room - 1)).map(\.id))
    }

    /// Vorrang für einen eigenen Kreis: Nutzer-Themen und Themen mit ≥ 2 Gedanken, dann nach Aktivität
    static func ranksBefore(_ a: MapLayoutInput.Topic, _ b: MapLayoutInput.Topic) -> Bool {
        let ka = a.pinned || a.count >= 2, kb = b.pinned || b.count >= 2
        if ka != kb { return ka }
        if a.lastActivity != b.lastActivity { return a.lastActivity > b.lastActivity }
        if a.count != b.count { return a.count > b.count }
        return a.id < b.id
    }
}

// MARK: - Berechnung

extension MapLayout {
    /// Ein gezeichneter Kreis während der Berechnung
    private struct Entry {
        var topic: MapLayoutInput.Topic
        /// neueste zuerst
        var thoughts: [MapLayoutInput.Thought]
        var center: CGPoint = .zero
        /// gezeichnete Fläche (nach dem Begrenzen)
        var shape: MapFootprint
        let want: MapFootprint
        let floor: MapFootprint
        let reserve: MapFootprint

        var id: String { topic.id }
        var pseudo: Bool { MapLayout.isPseudo(topic.id) }

        init(topic: MapLayoutInput.Topic, thoughts: [MapLayoutInput.Thought], config: MapLayoutConfig) {
            self.topic = topic
            self.thoughts = thoughts
            let lines = max(0, topic.titleLines)
            want = MapFootprint.sized(id: topic.id, radius: config.radius(for: topic.count), thoughts: thoughts.count,
                                      titleLines: lines, config: config)
            floor = MapFootprint.sized(id: topic.id, radius: config.radius(for: 1), thoughts: thoughts.count, titleLines: 0,
                                       config: config)
            // Titelzeilen (nur bei sehr wenigen Gedanken) zählen nicht zur Reserve: Sie weichen, wenn es eng wird
            reserve = MapFootprint.reserve(id: topic.id, titleLines: 0, config: config)
            shape = want
        }

        func at(_ f: MapFootprint) -> MapFootprint {
            var g = f
            g.center = center
            return g
        }
    }

    /// Gleiche Eingabe → gleiche Ausgabe. Kosten: höchstens `maxBubbles` Kreise, Platzsuche nur für neue
    /// Themen; Gedanken O(m log m).
    public static func compute(_ input: MapLayoutInput, config: MapLayoutConfig = MapLayoutConfig()) -> MapLayout {
        // Themen: erstes Vorkommen je ID; gezeichnet werden nur Themen mit Gedanken
        var seen = Set<String>()
        var topics: [MapLayoutInput.Topic] = []
        for topic in input.topics where topic.id != moreID && seen.insert(topic.id).inserted {
            topics.append(topic)
        }
        let collected = Self.collected(topics, config: config)
        var shown: [MapLayoutInput.Topic] = []
        var resting: [String] = []
        var more = MapLayoutInput.Topic(id: moreID, count: 0, lastActivity: .distantPast)
        for topic in topics {
            if topic.count <= 0 {
                resting.append(topic.id)
            } else if collected.contains(topic.id) {
                more.count += topic.count
                more.lastActivity = max(more.lastActivity, topic.lastActivity)
                resting.append(topic.id)
            } else {
                shown.append(topic)
            }
        }
        if more.count > 0 { shown.append(more) }
        let shownIDs = Set(shown.map(\.id))

        // Gedanken je Kreis, neueste zuerst (gleiche Zeit: nach ID)
        var byTopic: [String: [MapLayoutInput.Thought]] = [:]
        var thoughtSeen = Set<String>()
        for var thought in input.thoughts {
            if collected.contains(thought.topicID) { thought.topicID = moreID }
            guard shownIDs.contains(thought.topicID), thoughtSeen.insert(thought.id).inserted else { continue }
            byTopic[thought.topicID, default: []].append(thought)
        }
        for key in byTopic.keys {
            byTopic[key]?.sort { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id < $1.id }
        }

        shown.sort { $0.id < $1.id }
        var entries = shown.map { Entry(topic: $0, thoughts: byTopic[$0.id] ?? [], config: config) }

        // 1. Themen mit Anker bleiben, wo sie sind. Nur wenn sich gemerkte Plätze schon in kleinster Größe
        //    überdecken (kaputte oder sehr alte Datei), bekommt das kleinere einen neuen Platz.
        let byWeight = entries.indices.sorted { a, b in
            let x = entries[a].topic, y = entries[b].topic
            return x.count != y.count ? x.count > y.count : x.id < y.id
        }
        var placed: [Int] = []
        var fresh: [Int] = []
        for i in byWeight {
            guard let anchor = input.anchors[entries[i].id], anchor.x.isFinite, anchor.y.isFinite,
                  abs(anchor.x) < 1e6, abs(anchor.y) < 1e6 else {
                fresh.append(i)
                continue
            }
            // genau der gespeicherte Wert (neue Plätze liegen ohnehin auf 1/100 Kartenpunkt)
            entries[i].center = anchor.point
            let floor = entries[i].at(entries[i].floor)
            if placed.contains(where: { MapGeometry.overlaps(entries[$0].at(entries[$0].floor), floor, gap: config.gap) }) {
                fresh.append(i)
            } else {
                placed.append(i)
            }
        }

        // 2. Neue Themen: zuletzt aktive zuerst (sie liegen dann am nächsten an der Mitte), Pseudo-Themen zuletzt
        fresh.sort { a, b in
            let x = entries[a], y = entries[b]
            if x.pseudo != y.pseudo { return !x.pseudo }
            if x.topic.lastActivity != y.topic.lastActivity { return x.topic.lastActivity > y.topic.lastActivity }
            if x.topic.count != y.topic.count { return x.topic.count > y.topic.count }
            return x.id < y.id
        }
        var space = MapGeometry.Space(config: config)
        for i in placed { space.obstacles.append(entries[i].at(entries[i].reserve)) }
        for i in fresh {
            let real = placed.filter { !entries[$0].pseudo }.map { entries[$0].center.y }
            let pseudo = placed.filter { entries[$0].pseudo }.map { entries[$0].center.y }
            var band = MapGeometry.Band.any
            if entries[i].pseudo {
                // an den unteren Rand: nicht über dem tiefsten Kreis
                if let lowest = (real + pseudo).max() { band = .atOrBelow(lowest) }
            } else if let top = pseudo.min(), top >= (real.max() ?? -.infinity) {
                // „Ohne Thema“ liegt unten: echte Themen nicht mehr darunter
                band = .atOrAbove(top)
            }
            entries[i].center = space.findSpot(for: entries[i].reserve, band: band)
            space.obstacles.append(entries[i].at(entries[i].reserve))
            placed.append(i)
        }

        // 3. Größe: so groß, wie Platz ist (neue Themen haben immer genug, s. Reserve)
        fit(&entries, config: config)

        // Punkte
        var bubbles: [MapLayout.Bubble] = []
        var dots: [MapLayout.Dot] = []
        var anchors: [String: MapAnchor] = [:]
        var dotIndex: [String: Int] = [:]
        var shapes: [String: MapFootprint] = [:]
        for entry in entries {
            let shape = entry.at(entry.shape)
            let visible = Array(entry.thoughts.prefix(shape.dots))
            for (rank, slot) in MapGeometry.dotSlots(count: visible.count, radius: shape.radius, config: config).enumerated() {
                let thought = visible[rank]
                dotIndex[thought.id] = dots.count
                dots.append(MapLayout.Dot(id: thought.id, topicID: entry.id,
                                          position: CGPoint(x: shape.center.x + slot.offset.dx, y: shape.center.y + slot.offset.dy),
                                          angle: slot.angle, ring: slot.ring, rank: rank))
            }
            bubbles.append(MapLayout.Bubble(id: entry.id, center: shape.center, radius: shape.radius, outerRadius: shape.outer,
                                            label: shape.labelRect, count: entry.topic.count,
                                            hiddenCount: max(0, entry.topic.count - visible.count), titleLines: shape.titleLines))
            anchors[entry.id] = MapAnchor(shape.center)
            shapes[entry.id] = shape
        }
        // Ruhende und gesammelte Themen behalten ihren Platz, solange er frei ist. Nimmt ihn ein anderes Thema
        // ein (neu angelegt oder gewachsen), vergessen sie ihn – kommen sie zurück, bekommen sie einen neuen,
        // und kein sichtbarer Kreis muss weichen.
        let counts = Dictionary(topics.map { ($0.id, $0.count) }, uniquingKeysWith: { a, _ in a })
        // feste Reihenfolge (nach ID): Auch Gleitkomma-Rundungen sind dann bei jedem Lauf gleich
        let drawn = entries.map { shapes[$0.id]! }
        for id in resting + [moreID] where anchors[id] == nil {
            guard let anchor = input.anchors[id], anchor.x.isFinite, anchor.y.isFinite else { continue }
            var floor = MapFootprint.sized(id: id, radius: config.radius(for: 1), thoughts: max(1, counts[id] ?? 1),
                                           titleLines: 0, config: config)
            floor.center = MapGeometry.snap(anchor.point)
            guard !drawn.contains(where: { MapGeometry.overlaps($0, floor, gap: config.gap) }) else { continue }
            anchors[id] = anchor
        }

        // Linien
        var created: [String: (topic: String, date: Date)] = [:]
        for (topic, list) in byTopic {
            for thought in list { created[thought.id] = (topic, thought.createdAt) }
        }
        let lines = MapGeometry.lines(input.links, created: created, dots: dots, dotIndex: dotIndex,
                                      footprints: shapes, config: config)
        let topicLines = MapGeometry.topicLines(input.links, created: created, footprints: shapes, config: config)

        // Rahmen
        var bounds = CGRect.null
        for shape in drawn {
            bounds = bounds.union(shape.circleRect).union(shape.labelRect)
        }
        for line in topicLines {
            bounds = bounds.union(apexRect(line.from, line.control, line.to))
        }
        for line in lines {
            bounds = bounds.union(apexRect(line.from, line.control, line.to))
        }
        return MapLayout(bubbles: bubbles, dots: dots, lines: lines, topicLines: topicLines,
                         bounds: bounds.isNull ? .zero : bounds, anchors: anchors, collected: collected.sorted())
    }

    /// Scheitel einer quadratischen Kurve (t = ½) als kleines Feld
    private static func apexRect(_ from: CGPoint, _ control: CGPoint, _ to: CGPoint) -> CGRect {
        let apex = CGPoint(x: 0.25 * from.x + 0.5 * control.x + 0.25 * to.x, y: 0.25 * from.y + 0.5 * control.y + 0.25 * to.y)
        return CGRect(x: apex.x - 1, y: apex.y - 1, width: 2, height: 2)
    }

    /// Sichtbare Größe: jeder Kreis so groß, wie seine Anzahl verlangt – wenn der Platz reicht. Sonst erst
    /// weniger Titelzeilen, dann ein kleinerer Radius (nie kleiner als ein Kreis mit einem Gedanken).
    /// Reihenfolge: mehr Gedanken zuerst; wer noch nicht dran war, zählt mit seiner kleinsten Größe.
    private static func fit(_ entries: inout [Entry], config: MapLayoutConfig) {
        let order = entries.indices.sorted { a, b in
            let x = entries[a].topic, y = entries[b].topic
            return x.count != y.count ? x.count > y.count : x.id < y.id
        }
        var done = [Bool](repeating: false, count: entries.count)
        for i in order {
            let others = entries.indices.filter { $0 != i }.map { j in entries[j].at(done[j] ? entries[j].shape : entries[j].floor) }
            let center = entries[i].center
            func fits(_ f: MapFootprint) -> Bool {
                var probe = f
                probe.center = center
                // nur, wer in Reichweite ist
                return !others.contains { MapGeometry.overlaps($0, probe, gap: config.gap) }
            }
            let want = entries[i].want
            var best = want
            if !fits(want) {
                var found = false
                if want.titleLines > 0 {
                    for lines in stride(from: want.titleLines - 1, through: 0, by: -1) {
                        let f = MapFootprint.sized(id: want.id, radius: want.radius, thoughts: entries[i].thoughts.count,
                                                   titleLines: lines, config: config)
                        if fits(f) {
                            best = f
                            found = true
                            break
                        }
                    }
                }
                if !found {
                    var lo = entries[i].floor.radius, hi = want.radius
                    for _ in 0..<14 {
                        let mid = (lo + hi) / 2
                        let f = MapFootprint.sized(id: want.id, radius: mid, thoughts: entries[i].thoughts.count, titleLines: 0,
                                                   config: config)
                        if fits(f) { lo = mid } else { hi = mid }
                    }
                    // auf 1/100 abrunden: gleiche Eingabe, gleiche Zahl
                    let radius = (lo * 100).rounded(.down) / 100
                    best = radius <= entries[i].floor.radius ? entries[i].floor
                        : MapFootprint.sized(id: want.id, radius: radius, thoughts: entries[i].thoughts.count, titleLines: 0,
                                             config: config)
                }
            }
            entries[i].shape = best
            done[i] = true
        }
    }
}

// MARK: - Fläche eines Themas

/// Kreis samt Punkte-Bogen (Kreis mit Radius `outer`) und Beschriftungsfeld darunter.
struct MapFootprint: Sendable, Equatable {
    var id: String
    var center: CGPoint
    var radius: CGFloat
    var outer: CGFloat
    /// Punkte auf dem Bogen
    var dots: Int
    var titleLines: Int
    /// Beschriftungsfeld relativ zum Mittelpunkt
    private(set) var label: CGRect
    /// Radius eines Kreises um den Mittelpunkt, der alles umschließt
    private(set) var bound: CGFloat
    /// Beschriftungsfeld relativ, als Zahlen (schnell in der heißen Schleife)
    private(set) var lx0: CGFloat, ly0: CGFloat, lx1: CGFloat, ly1: CGFloat

    init(id: String, center: CGPoint, radius: CGFloat, dots: Int, titleLines: Int, config: MapLayoutConfig) {
        let rings = MapGeometry.ringCount(dots: dots, radius: radius, config: config)
        let outer = rings == 0 ? radius : radius + config.firstRing + CGFloat(rings - 1) * config.ringStep + config.dotRadius
        let width = titleLines > 0 ? max(config.titleWidth, 2 * radius + 16) : max(config.labelWidth, 2 * radius + 16)
        let height = config.labelHeight + (titleLines > 0 ? CGFloat(titleLines) * config.titleLineHeight + 4 : 0)
        let label = CGRect(x: -width / 2, y: radius + config.labelGap, width: width, height: height)
        self.init(id: id, center: center, radius: radius, outer: outer, dots: dots, titleLines: titleLines, label: label)
    }

    init(id: String, center: CGPoint, radius: CGFloat, outer: CGFloat, dots: Int, titleLines: Int, label: CGRect) {
        self.id = id
        self.center = center
        self.radius = radius
        self.outer = outer
        self.dots = dots
        self.titleLines = titleLines
        self.label = label
        lx0 = label.minX
        lx1 = label.maxX
        ly0 = label.minY
        ly1 = label.maxY
        let corner = max(hypot(label.minX, label.maxY), hypot(label.maxX, label.maxY),
                         hypot(label.minX, label.minY), hypot(label.maxX, label.minY))
        bound = max(outer, corner)
    }

    /// Kreis mit Radius `radius`; Punkte: so viele, wie auf den Bogen passen (höchstens `maxDots`)
    static func sized(id: String, radius: CGFloat, thoughts: Int, titleLines: Int, config: MapLayoutConfig) -> MapFootprint {
        let dots = min(thoughts, config.maxDots, MapGeometry.ringCapacity(0, radius: radius, config: config))
        return MapFootprint(id: id, center: .zero, radius: radius, dots: max(0, dots), titleLines: titleLines, config: config)
    }

    /// Platz, den ein Thema beim Anlegen frei hält: so viel, wie es je brauchen kann – Kreis am Deckel samt
    /// Punkte-Bogen, darunter ein Beschriftungsfeld, das jede Kreisgröße abdeckt (es rückt mit dem Radius).
    /// Jede sichtbare Größe (`sized`, Radius ≤ Deckel, gleiche oder weniger Titelzeilen) liegt darin. Die Karte
    /// reserviert ohne Titelzeilen (es gibt sie nur bei sehr wenigen Gedanken; wird es eng, entfallen sie).
    static func reserve(id: String, titleLines: Int, config: MapLayoutConfig) -> MapFootprint {
        let big = MapFootprint(id: id, center: .zero, radius: config.maxRadius, dots: config.maxDots, titleLines: titleLines,
                               config: config)
        let top = config.radius(for: 1) + config.labelGap
        let label = CGRect(x: big.label.minX, y: top, width: big.label.width, height: big.label.maxY - top)
        return MapFootprint(id: id, center: .zero, radius: config.maxRadius, outer: big.outer, dots: config.maxDots,
                            titleLines: titleLines, label: label)
    }

    var labelRect: CGRect { label.offsetBy(dx: center.x, dy: center.y) }
    var circleRect: CGRect { CGRect(x: center.x - outer, y: center.y - outer, width: 2 * outer, height: 2 * outer) }
    /// umschließendes Feld (Kreis samt Bogen und Beschriftung), relativ
    var extent: (x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat) {
        (min(-outer, lx0), min(-outer, ly0), max(outer, lx1), max(outer, ly1))
    }
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
    /// so viel zusätzlich beim Anlegen, damit Runden nichts überlappen lässt
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

    // MARK: Freier Platz

    /// Erlaubte Höhe des Mittelpunkts eines neuen Themas (y nach unten)
    enum Band: Equatable {
        case any
        /// am unteren Rand: nicht über `y`
        case atOrBelow(CGFloat)
        /// nicht unter `y`
        case atOrAbove(CGFloat)

        func allows(_ y: CGFloat) -> Bool {
            switch self {
            case .any: true
            case .atOrBelow(let limit): y >= limit - 0.5
            case .atOrAbove(let limit): y <= limit + 0.5
            }
        }
    }

    /// Platzsuche für neue Themen. Hindernisse sind die Reserven der vorhandenen Themen; die Berührabstände je
    /// Form und Richtung werden einmal berechnet (fast alle Reserven haben dieselbe Form).
    struct Space {
        let config: MapLayoutConfig
        var obstacles: [MapFootprint] = []
        private var contacts: [ContactKey: CGFloat] = [:]

        init(config: MapLayoutConfig) {
            self.config = config
        }

        private struct Shape: Hashable {
            var outer: CGFloat, lx0: CGFloat, ly0: CGFloat, lx1: CGFloat, ly1: CGFloat
            init(_ f: MapFootprint) {
                outer = f.outer
                lx0 = f.lx0
                ly0 = f.ly0
                lx1 = f.lx1
                ly1 = f.ly1
            }
        }

        private struct ContactKey: Hashable {
            var anchor: Shape
            var item: Shape
            var step: Int
        }

        /// Neues Thema: dorthin, wo der Rahmen der Karte – gemessen im Seitenverhältnis des Bildschirms – am
        /// wenigsten wächst (so füllen sich Lücken zuerst und die Karte bleibt bildschirmförmig) und die Themen
        /// ausgewogen um die Mitte liegen; bei Gleichstand entscheidet die Nähe zur Mitte (elliptischer Abstand).
        /// `band` grenzt die Höhe ein; passt dort nichts, gilt sie nicht.
        mutating func findSpot(for item: MapFootprint, band: Band = .any) -> CGPoint {
            guard !obstacles.isEmpty else { return .zero }
            if let spot = search(item, band: band) { return spot }
            if band != .any, let spot = search(item, band: .any) { return spot }
            // Rückfall (kommt praktisch nicht vor): rechts neben alles
            var box = CGRect.null
            for p in obstacles { box = box.union(p.circleRect).union(p.labelRect) }
            return snap(CGPoint(x: box.maxX + item.bound + config.gap + 2 * slack, y: box.midY))
        }

        private mutating func search(_ item: MapFootprint, band: Band) -> CGPoint? {
            var bx0 = CGFloat.infinity, by0 = CGFloat.infinity, bx1 = -CGFloat.infinity, by1 = -CGFloat.infinity
            // Mittelpunkte: Summe und Rahmen (für die Unwucht)
            var sx: CGFloat = 0, sy: CGFloat = 0
            var cx0 = CGFloat.infinity, cy0 = CGFloat.infinity, cx1 = -CGFloat.infinity, cy1 = -CGFloat.infinity
            for p in obstacles {
                let e = p.extent
                bx0 = min(bx0, p.center.x + e.x0)
                by0 = min(by0, p.center.y + e.y0)
                bx1 = max(bx1, p.center.x + e.x1)
                by1 = max(by1, p.center.y + e.y1)
                sx += p.center.x
                sy += p.center.y
                cx0 = min(cx0, p.center.x)
                cy0 = min(cy0, p.center.y)
                cx1 = max(cx1, p.center.x)
                cy1 = max(cy1, p.center.y)
            }
            let n = CGFloat(obstacles.count + 1)
            // Ausgewogenheit zählt nur bei wenigen Themen; in größeren Karten füllen neue zuerst Lücken nahe der Mitte
            let weight = obstacles.count < Space.fewTopics ? Space.balance : 0
            let target = snap(CGPoint(x: (bx0 + bx1) / 2, y: (by0 + by1) / 2))
            let aspect = max(0.2, config.aspect)
            let ie = item.extent
            // Wert eines Platzes: Größe des Rahmens im Bildschirmformat plus Unwucht (Abstand des Schwerpunkts der
            // Mittelpunkte von der Mitte ihres Rahmens) – so wird aus wenigen Themen ein Dreieck oder Versatz statt
            // einer Spalte mit einem Ausreißer. Auf halbe Punkte gerundet, damit Rundungsrauschen nicht entscheidet;
            // bei Gleichstand gewinnt die Nähe zur Mitte.
            func score(_ c: CGPoint) -> CGFloat {
                let x0 = min(bx0, c.x + ie.x0), x1 = max(bx1, c.x + ie.x1), y0 = min(by0, c.y + ie.y0), y1 = max(by1, c.y + ie.y1)
                let size = max((x1 - x0) / aspect, y1 - y0)
                let mx = (min(cx0, c.x) + max(cx1, c.x)) / 2, my = (min(cy0, c.y) + max(cy1, c.y)) / 2
                let ux = ((sx + c.x) / n - mx) / aspect, uy = (sy + c.y) / n - my
                return ((size + weight * (ux * ux + uy * uy).squareRoot()) * 2).rounded() / 2
            }
            func cost(_ c: CGPoint) -> CGFloat {
                let dx = (c.x - target.x) / aspect, dy = c.y - target.y
                return dx * dx + dy * dy
            }
            // Freiprüfung: erst Kreis an Kreis (billig, verwirft fast alles Belegte), dann die ganze Fläche nur für
            // Nachbarn in Reichweite
            let count = obstacles.count
            let ox = obstacles.map(\.center.x), oy = obstacles.map(\.center.y)
            let near = obstacles.map { $0.outer + item.outer + config.gap - tolerance }
            let reach = obstacles.map { $0.bound + item.bound + config.gap }
            /// Kreis an Kreis frei? (verwirft Punkte mitten in anderen Themen, bevor sie bewertet werden)
            func circlesFree(_ c: CGPoint) -> Bool {
                for i in 0..<count {
                    let dx = c.x - ox[i], dy = c.y - oy[i]
                    if dx * dx + dy * dy < near[i] * near[i] { return false }
                }
                return true
            }
            func isFree(_ c: CGPoint) -> Bool {
                guard circlesFree(c) else { return false }
                var probe = item
                probe.center = c
                for i in 0..<count {
                    let dx = c.x - ox[i], dy = c.y - oy[i]
                    if dx * dx + dy * dy < reach[i] * reach[i], overlaps(probe, obstacles[i], gap: config.gap) { return false }
                }
                return true
            }

            // Kandidaten: die Mitte und die Berührpunkte rund um jede Fläche; erst bewerten, dann der Reihe nach
            // prüfen, ob dort frei ist (das Teure nur für die besten). Ist ein Berührpunkt belegt, rückt er auf
            // seinem Strahl bis zur ersten freien Stelle vor und reiht sich mit neuem Wert wieder ein.
            struct Candidate {
                var score: CGFloat
                var cost: CGFloat
                var point: CGPoint
                /// Strahl (Fläche, Richtung, Abstand), auf dem der Punkt liegt; nil = Mitte oder Zweifach-Berührung
                var ray: (anchor: Int, ux: CGFloat, uy: CGFloat, t: CGFloat)?

                func before(_ other: Candidate) -> Bool {
                    if score != other.score { return score < other.score }
                    if cost != other.cost { return cost < other.cost }
                    return (point.x, point.y) < (other.point.x, other.point.y)
                }
            }
            var candidates: [Candidate] = []
            let k = max(8, config.directions)
            candidates.reserveCapacity(obstacles.count * k + 1)
            if band.allows(target.y) { candidates.append(Candidate(score: score(target), cost: cost(target), point: target)) }
            let itemShape = Shape(item)
            for (index, anchor) in obstacles.enumerated() {
                let tMin = anchor.outer + item.outer + config.gap
                let anchorShape = Shape(anchor)
                for step in 0..<k {
                    let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(k)
                    let ux = cos(angle), uy = sin(angle)
                    let key = ContactKey(anchor: anchorShape, item: itemShape, step: step)
                    let t: CGFloat
                    if let known = contacts[key] {
                        t = known
                    } else {
                        t = MapGeometry.contact(item, around: anchor, ux: ux, uy: uy, from: tMin, gap: config.gap)
                        contacts[key] = t
                    }
                    let c = snap(CGPoint(x: anchor.center.x + ux * t, y: anchor.center.y + uy * t))
                    guard band.allows(c.y), circlesFree(c) else { continue }
                    candidates.append(Candidate(score: score(c), cost: cost(c), point: c, ray: (index, ux, uy, t)))
                }
            }
            // Punkte, die zwei Nachbarn zugleich berühren (Kreis an Kreis): ergeben genaue Dreiecke und Versätze
            for i in obstacles.indices {
                let a = obstacles[i]
                let ra = a.outer + item.outer + config.gap + slack
                for j in obstacles.indices where j > i {
                    let b = obstacles[j]
                    let rb = b.outer + item.outer + config.gap + slack
                    let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y
                    let d = (dx * dx + dy * dy).squareRoot()
                    guard d > 1e-6, d < ra + rb, d > abs(ra - rb) else { continue }
                    let along = (ra * ra - rb * rb + d * d) / (2 * d)
                    let h = max(0, ra * ra - along * along).squareRoot()
                    let mx = a.center.x + along * dx / d, my = a.center.y + along * dy / d
                    for sign in [CGFloat(1), -1] {
                        let c = snap(CGPoint(x: mx - sign * h * dy / d, y: my + sign * h * dx / d))
                        guard band.allows(c.y), circlesFree(c) else { continue }
                        candidates.append(Candidate(score: score(c), cost: cost(c), point: c))
                    }
                }
            }
            candidates.sort { $0.before($1) }

            /// erste freie Stelle auf dem Strahl ab `t` (nil = nach einigen Hindernissen aufgegeben)
            func march(_ ray: (anchor: Int, ux: CGFloat, uy: CGFloat, t: CGFloat)) -> CGPoint? {
                let origin = obstacles[ray.anchor].center
                var t = ray.t
                var probe = item
                for _ in 0..<4 {
                    probe.center = CGPoint(x: origin.x + ray.ux * t, y: origin.y + ray.uy * t)
                    guard let blocker = obstacles.first(where: { overlaps(probe, $0, gap: config.gap) }) else {
                        return snap(probe.center)
                    }
                    var lo = t, hi = t + 2 * (blocker.bound + item.bound + config.gap) + 1
                    for _ in 0..<16 {
                        let mid = (lo + hi) / 2
                        probe.center = CGPoint(x: origin.x + ray.ux * mid, y: origin.y + ray.uy * mid)
                        if overlaps(probe, blocker, gap: config.gap) { lo = mid } else { hi = mid }
                    }
                    t = hi + slack
                }
                return nil
            }

            var index = 0
            var marches = 0
            while index < candidates.count {
                let candidate = candidates[index]
                if isFree(candidate.point) { return candidate.point }
                index += 1
                guard let ray = candidate.ray, marches < Space.maxMarches, let moved = march(ray), band.allows(moved.y) else { continue }
                marches += 1
                let next = Candidate(score: score(moved), cost: cost(moved), point: moved)
                // einsortieren (hinter den gerade geprüften)
                var at = index
                while at < candidates.count, candidates[at].before(next) { at += 1 }
                candidates.insert(next, at: at)
            }
            return nil
        }

        /// höchstens so viele Strahlen je Suche bis zur ersten freien Stelle verfolgen
        static let maxMarches = 48

        /// Gewicht der Unwucht gegenüber der Rahmengröße (nur solange weniger als `fewTopics` Themen liegen)
        static let balance: CGFloat = 0.5
        static let fewTopics = 6
    }

    /// Kleinster Abstand entlang (ux, uy), ab dem `item` die Fläche `anchor` nicht mehr berührt. Hängt nur von
    /// den Formen und der Richtung ab, nicht vom Ort.
    static func contact(_ item: MapFootprint, around anchor: MapFootprint, ux: CGFloat, uy: CGFloat,
                        from tMin: CGFloat, gap: CGFloat) -> CGFloat {
        var a = anchor
        a.center = .zero
        var probe = item
        // häufigster Fall: Am Mindestabstand der Kreise stört auch kein Beschriftungsfeld
        probe.center = CGPoint(x: ux * tMin, y: uy * tMin)
        if !overlaps(a, probe, gap: gap) { return tMin + slack }
        var lo = max(0, tMin - 0.05) // hier überlappen die Kreise sicher
        var hi = max(lo + 0.1, a.bound + item.bound + gap + 1)
        for _ in 0..<16 {
            let mid = (lo + hi) / 2
            probe.center = CGPoint(x: ux * mid, y: uy * mid)
            if overlaps(a, probe, gap: gap) { lo = mid } else { hi = mid }
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

    /// Übersicht: Verknüpfungen zwischen echten Themen gebündelt – je Paar eine Linie, nur Paare mit mindestens
    /// `minTopicLinks` Verknüpfungen, insgesamt höchstens `maxTopicLines` und je Thema `maxTopicLinesPerTopic`
    /// (mehr Verknüpfungen, dann neuere, dann ID). Kreisrand zu Kreisrand; eine Linie, die einen dritten Kreis
    /// oder dessen Namen kreuzen würde, entfällt.
    static func topicLines(_ links: [MapLayoutInput.Link], created: [String: (topic: String, date: Date)],
                           footprints: [String: MapFootprint], config: MapLayoutConfig) -> [MapLayout.TopicLine] {
        struct Pair { var a: String; var b: String; var count: Int; var newest: Date }
        var pairs: [String: Pair] = [:]
        var seen = Set<String>()
        for link in links where link.from != link.to {
            guard let x = created[link.from], let y = created[link.to], x.topic != y.topic,
                  !MapLayout.isPseudo(x.topic), !MapLayout.isPseudo(y.topic) else { continue }
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
        let ranked = pairs.values.filter { $0.count >= config.minTopicLinks }.sorted { p, q in
            if p.count != q.count { return p.count > q.count }
            if p.newest != q.newest { return p.newest > q.newest }
            return (p.a, p.b) < (q.a, q.b)
        }
        let all = footprints.values.sorted { $0.id < $1.id }
        var perTopic: [String: Int] = [:]
        var result: [MapLayout.TopicLine] = []
        for pair in ranked {
            guard result.count < config.maxTopicLines else { break }
            guard (perTopic[pair.a] ?? 0) < config.maxTopicLinesPerTopic, (perTopic[pair.b] ?? 0) < config.maxTopicLinesPerTopic,
                  let fa = footprints[pair.a], let fb = footprints[pair.b] else { continue }
            let from = edge(fa, toward: fb.center), to = edge(fb, toward: fa.center)
            let dx = to.x - from.x, dy = to.y - from.y
            let bend: CGFloat = 0.12
            let control = CGPoint(x: (from.x + to.x) / 2 - dy * bend, y: (from.y + to.y) / 2 + dx * bend)
            guard !crossesThird(from: from, control: control, to: to, except: [pair.a, pair.b], all: all, config: config) else { continue }
            perTopic[pair.a, default: 0] += 1
            perTopic[pair.b, default: 0] += 1
            result.append(MapLayout.TopicLine(a: pair.a, b: pair.b, count: pair.count, from: from, control: control, to: to))
        }
        return result
    }

    /// Läuft die Kurve durch einen anderen Kreis (mit etwas Luft) oder über dessen Namen?
    static func crossesThird(from: CGPoint, control: CGPoint, to: CGPoint, except: Set<String>, all: [MapFootprint],
                             config: MapLayoutConfig) -> Bool {
        // Kurve als Streckenzug (12 Teile reichen bei der flachen Biegung)
        var points: [CGPoint] = []
        for i in 0...12 {
            let t = CGFloat(i) / 12, u = 1 - t
            points.append(CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                                  y: u * u * from.y + 2 * u * t * control.y + t * t * to.y))
        }
        let margin: CGFloat = 6
        for other in all where !except.contains(other.id) {
            let r = other.radius + margin
            let name = CGRect(x: other.center.x + other.lx0, y: other.center.y + other.ly0,
                              width: other.lx1 - other.lx0, height: config.labelHeight).insetBy(dx: 4, dy: 2)
            for i in 0..<(points.count - 1) {
                let p = points[i], q = points[i + 1]
                if distance(other.center, p, q) < r { return true }
                if segment(p, q, hits: name) { return true }
            }
        }
        return false
    }

    /// Abstand eines Punkts zu einer Strecke
    private static func distance(_ c: CGPoint, _ p: CGPoint, _ q: CGPoint) -> CGFloat {
        let vx = q.x - p.x, vy = q.y - p.y
        let len2 = vx * vx + vy * vy
        let t = len2 > 0 ? max(0, min(1, ((c.x - p.x) * vx + (c.y - p.y) * vy) / len2)) : 0
        return hypot(c.x - (p.x + vx * t), c.y - (p.y + vy * t))
    }

    /// Schneidet die Strecke das Feld? (Liang–Barsky)
    private static func segment(_ p: CGPoint, _ q: CGPoint, hits r: CGRect) -> Bool {
        var t0: CGFloat = 0, t1: CGFloat = 1
        let dx = q.x - p.x, dy = q.y - p.y
        for (pk, qk) in [(-dx, p.x - r.minX), (dx, r.maxX - p.x), (-dy, p.y - r.minY), (dy, r.maxY - p.y)] {
            if pk == 0 {
                if qk < 0 { return false }
            } else {
                let t = qk / pk
                if pk < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                if t0 > t1 { return false }
            }
        }
        return true
    }

    private static func edge(_ f: MapFootprint, toward p: CGPoint) -> CGPoint {
        let dx = p.x - f.center.x, dy = p.y - f.center.y
        let d = (dx * dx + dy * dy).squareRoot()
        guard d > 1e-9 else { return CGPoint(x: f.center.x, y: f.center.y - f.radius) }
        return CGPoint(x: f.center.x + dx / d * f.radius, y: f.center.y + dy / d * f.radius)
    }
}
