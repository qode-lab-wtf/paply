import CoreGraphics
import Foundation
import Testing
@testable import PaplyKit

@Suite("Gedanken-Landkarte: Anordnung")
struct MapLayoutTests {
    private let config = MapLayoutConfig()
    private static let base = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Hilfen

    /// Reproduzierbare Pseudozufallszahlen (keine echten Zufälle in Tests)
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        mutating func int(_ range: Range<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    }

    private static func id(_ i: Int, _ prefix: String = "t") -> String { "\(prefix)\(String(format: "%02d", i))" }

    /// `counts[i]` Gedanken in Thema `t<i>`, Gedanke j eines Themas j Stunden alt
    private func input(_ counts: [Int], anchors: [String: MapAnchor] = [:], links: [MapLayoutInput.Link] = [],
                       titleLines: Int = 0, prefix: String = "t") -> MapLayoutInput {
        var topics: [MapLayoutInput.Topic] = []
        var thoughts: [MapLayoutInput.Thought] = []
        for (i, n) in counts.enumerated() {
            let id = Self.id(i, prefix)
            topics.append(.init(id: id, count: n, lastActivity: Self.base.addingTimeInterval(-Double(i) * 600), titleLines: titleLines))
            for j in 0..<n {
                thoughts.append(.init(id: "\(id)-s\(String(format: "%04d", j))", topicID: id,
                                      createdAt: Self.base.addingTimeInterval(-Double(i) * 600 - Double(j) * 3_600)))
            }
        }
        return MapLayoutInput(topics: topics, thoughts: thoughts, links: links, anchors: anchors)
    }

    /// Thema mit `n` Gedanken anhängen (neueste Aktivität = `age` Sekunden vor `base`)
    private func add(_ id: String, _ n: Int, to input: inout MapLayoutInput, age: TimeInterval = 0, pinned: Bool = false) {
        input.topics.append(.init(id: id, count: n, lastActivity: Self.base.addingTimeInterval(-age), pinned: pinned))
        for j in 0..<n {
            input.thoughts.append(.init(id: "\(id)-s\(String(format: "%04d", j))", topicID: id,
                                        createdAt: Self.base.addingTimeInterval(-age - Double(j) * 60)))
        }
    }

    private func footprints(_ layout: MapLayout) -> [MapFootprint] {
        layout.bubbles.map { bubble in
            MapFootprint(id: bubble.id, center: bubble.center, radius: bubble.radius,
                         dots: layout.dots.filter { $0.topicID == bubble.id }.count, titleLines: bubble.titleLines, config: config)
        }
    }

    private func assertNoOverlap(_ layout: MapLayout, sourceLocation: SourceLocation = #_sourceLocation) {
        let items = footprints(layout)
        for i in items.indices {
            for j in items.indices where j > i {
                let depth = MapGeometry.penetration(items[i], items[j], gap: config.gap)?.depth ?? 0
                #expect(depth <= MapGeometry.tolerance, "\(items[i].id) und \(items[j].id) überlappen um \(depth)",
                        sourceLocation: sourceLocation)
            }
        }
    }

    /// Jeder Kreis, der vorher und nachher zu sehen ist, liegt bitgenau gleich; die Anker auch.
    private func assertNothingMoved(_ before: MapLayout, _ after: MapLayout, sourceLocation: SourceLocation = #_sourceLocation) {
        for bubble in before.bubbles {
            guard let now = after.bubble(bubble.id) else { continue }
            #expect(now.center == bubble.center, "\(bubble.id) ist gewandert: \(bubble.center) → \(now.center)",
                    sourceLocation: sourceLocation)
            #expect(after.anchors[bubble.id] == before.anchors[bubble.id], "Anker von \(bubble.id) geändert",
                    sourceLocation: sourceLocation)
        }
    }

    private func center(_ layout: MapLayout, _ id: String) -> CGPoint { layout.bubble(id)!.center }

    /// Dicht gepackte Anker wie aus der alten Anordnung: Raster, in dem Kreise mit 8 Gedanken knapp passen
    private func tightAnchors(columns: Int, rows: Int) -> [String: MapAnchor] {
        var anchors: [String: MapAnchor] = [:]
        for i in 0..<(columns * rows) {
            anchors[Self.id(i)] = MapAnchor(x: Double(i % columns) * 128, y: Double(i / columns) * 140)
        }
        return anchors
    }

    // MARK: Determinismus

    @Test func sameInputSameOutput() {
        let links = [MapLayoutInput.Link(from: "t00-s0000", to: "t01-s0000"), .init(from: "t02-s0001", to: "t00-s0002")]
        let a = MapLayout.compute(input([12, 3, 7, 1, 25, 4], links: links))
        let b = MapLayout.compute(input([12, 3, 7, 1, 25, 4], links: links))
        #expect(a == b)
        #expect(!a.bubbles.isEmpty && !a.lines.isEmpty)
    }

    @Test func orderOfInputDoesNotMatter() {
        let links = (0..<20).map { MapLayoutInput.Link(from: "t0\($0 % 6)-s000\($0 % 3)", to: "t0\(($0 + 1) % 6)-s000\($0 % 2)") }
        let original = input([12, 3, 7, 1, 25, 4], links: links)
        var shuffled = original
        shuffled.topics.reverse()
        var rng = LCG(state: 7)
        for i in shuffled.thoughts.indices.reversed() {
            shuffled.thoughts.swapAt(i, rng.int(0..<(i + 1)))
        }
        shuffled.links = links.reversed().map { MapLayoutInput.Link(from: $0.to, to: $0.from) }
        #expect(MapLayout.compute(original) == MapLayout.compute(shuffled))
    }

    @Test func layoutIsIdempotentWithItsOwnAnchors() {
        let first = MapLayout.compute(input([40, 3, 9, 1, 17, 2, 6, 6, 30]))
        let second = MapLayout.compute(input([40, 3, 9, 1, 17, 2, 6, 6, 30], anchors: first.anchors))
        #expect(first == second)
        // auch über die Datei (Runden, JSON)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("map-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try? MapAnchorFile.save(first.anchors, to: url)
        guard case .anchors(let loaded) = MapAnchorFile.load(from: url) else {
            Issue.record("Anker nicht gelesen")
            return
        }
        #expect(MapLayout.compute(input([40, 3, 9, 1, 17, 2, 6, 6, 30], anchors: loaded)) == first)
    }

    // MARK: Größe

    @Test func radiusGrowsWithSquareRootAndIsCapped() {
        #expect(config.radius(for: 1) < config.radius(for: 4))
        let grow1 = config.radius(for: 4) - config.radius(for: 1)
        let grow2 = config.radius(for: 9) - config.radius(for: 4)
        #expect(abs(grow1 - grow2) < 0.001) // √: gleiche Schritte bei 1 → 4 → 9
        #expect(config.radius(for: 10_000) == config.maxRadius)
        #expect(config.radius(for: 0) == config.radius(for: 1))
    }

    @Test func everyVisibleSizeFitsIntoTheReserve() {
        // Grundlage der festen Anker: Was ein Thema je zeigt, liegt in dem Platz, den es beim Anlegen frei hält
        for lines in [0, 2, 5] {
            let reserve = MapFootprint.reserve(id: "r", titleLines: lines, config: config)
            #expect(reserve.label.contains(MapFootprint.reserve(id: "r", titleLines: 0, config: config).label))
            for count in [1, 2, 3, 5, 8, 13, 20, 36, 80, 400] {
                let shown = MapFootprint.sized(id: "s", radius: config.radius(for: count), thoughts: count, titleLines: lines, config: config)
                #expect(shown.outer <= reserve.outer + 0.001, "n=\(count): Bogen ragt hinaus")
                #expect(reserve.label.contains(shown.label), "n=\(count), \(lines) Zeilen: Beschriftung ragt hinaus")
            }
        }
    }

    // MARK: Überlappung

    @Test func circlesNeverOverlap() {
        var rng = LCG(state: 42)
        for _ in 0..<6 {
            let counts = (0..<rng.int(8..<40)).map { _ in rng.int(1..<120) }
            let layout = MapLayout.compute(input(counts))
            #expect(layout.bubbles.count == min(counts.count, config.maxBubbles))
            assertNoOverlap(layout)
        }
    }

    @Test func clusteredAnchorsAreSeparated() {
        // alle Anker auf (fast) demselben Punkt (kaputte Datei): alles muss trotzdem frei liegen
        var anchors: [String: MapAnchor] = [:]
        for i in 0..<12 { anchors[Self.id(i)] = MapAnchor(x: Double(i % 2), y: 0) }
        let layout = MapLayout.compute(input(Array(repeating: 20, count: 12), anchors: anchors))
        assertNoOverlap(layout)
        #expect(layout.bubbles.count == 12)
    }

    @Test func labelFieldIsReservedBelowEachCircle() {
        let layout = MapLayout.compute(input([5, 5, 5, 5]))
        for bubble in layout.bubbles {
            #expect(bubble.label.minY >= bubble.center.y + bubble.radius)
            #expect(abs(bubble.label.midX - bubble.center.x) < 0.001)
            #expect(bubble.label.height >= config.labelHeight)
        }
        assertNoOverlap(layout)
    }

    // MARK: Feste Anker

    @Test func anchorsStayWhenATopicGains() {
        // Befund: 5 Themen à 8 Gedanken, ein neunter im ersten – vorher wanderten drei andere Mittelpunkte
        let before = MapLayout.compute(input([8, 8, 8, 8, 8]))
        let after = MapLayout.compute(input([9, 8, 8, 8, 8], anchors: before.anchors))
        assertNothingMoved(before, after)
        #expect(after.bubble("t00")!.radius > before.bubble("t00")!.radius) // Platz war reserviert
        assertNoOverlap(after)
    }

    @Test func anchorsStayWhenTopicsGrowAll() {
        // jedes Thema wächst bis weit über den Deckel – nichts bewegt sich, alles wird so groß wie verlangt
        var counts = Array(repeating: 1, count: 12)
        var layout = MapLayout.compute(input(counts))
        let first = layout
        for round in 0..<40 {
            counts[round % counts.count] += 1 + round
            let next = MapLayout.compute(input(counts, anchors: layout.anchors))
            assertNothingMoved(layout, next)
            assertNoOverlap(next)
            for bubble in next.bubbles {
                #expect(bubble.radius == config.radius(for: bubble.count), "\(bubble.id) wurde ohne Not begrenzt")
            }
            layout = next
        }
        assertNothingMoved(first, layout)
    }

    @Test func tightOldAnchorsAreClampedNotPushed() {
        // Anker aus der alten, dichten Anordnung: Wachstum begrenzt den Kreis, die Nachbarn bleiben
        let anchors = tightAnchors(columns: 3, rows: 2)
        let before = MapLayout.compute(input(Array(repeating: 8, count: 6), anchors: anchors))
        for (id, anchor) in anchors { #expect(before.anchors[id] == anchor) }
        assertNoOverlap(before)
        var grown = Array(repeating: 8, count: 6)
        grown[4] = 120 // mitten in der unteren Reihe
        let after = MapLayout.compute(input(grown, anchors: before.anchors))
        assertNothingMoved(before, after)
        assertNoOverlap(after)
        let big = after.bubble("t04")!
        #expect(big.radius < config.radius(for: 120), "müsste begrenzt sein")
        #expect(big.radius >= before.bubble("t04")!.radius - 0.01, "darf nicht schrumpfen, solange Platz ist")
        // und bleibt stabil
        #expect(MapLayout.compute(input(grown, anchors: after.anchors)) == after)
    }

    @Test func storedAnchorsAreKeptBitExact() {
        // auch krumme Werte (nicht auf 1/100) kommen unverändert zurück
        let anchors = ["t00": MapAnchor(x: 0.123456789, y: -3.000000001), "t01": MapAnchor(x: 400.987654321, y: 12.5)]
        let layout = MapLayout.compute(input([5, 9], anchors: anchors))
        #expect(layout.anchors == anchors)
        #expect(center(layout, "t00") == anchors["t00"]!.point)
    }

    @Test func invalidAnchorsAreIgnored() {
        let layout = MapLayout.compute(input([3, 3, 3], anchors: ["t00": MapAnchor(x: .nan, y: 0), "t01": MapAnchor(x: 10, y: 10),
                                                                  "t02": MapAnchor(x: 1e12, y: 0)]))
        #expect(layout.bubbles.allSatisfy { $0.center.x.isFinite && $0.center.y.isFinite && abs($0.center.x) < 10_000 })
        #expect(center(layout, "t01") == CGPoint(x: 10, y: 10))
        assertNoOverlap(layout)
    }

    @Test func anchorsStayWhenTopicsAppear() {
        var counts = [6]
        var layout = MapLayout.compute(input(counts))
        for step in 1..<22 {
            counts.append(1 + step % 5)
            let next = MapLayout.compute(input(counts, anchors: layout.anchors))
            assertNothingMoved(layout, next)
            assertNoOverlap(next)
            #expect(next.bubbles.count == counts.count)
            layout = next
        }
    }

    @Test func anchorsStayWhenTopicsDisappear() {
        let counts = [10, 4, 7, 2, 15, 3, 9, 5]
        let before = MapLayout.compute(input(counts))
        // t02 ruht (alle Gedanken weg), t05 ist gelöscht
        var next = input(counts, anchors: before.anchors)
        next.topics = next.topics.compactMap { topic in
            if topic.id == "t05" { return nil }
            var t = topic
            if t.id == "t02" { t.count = 0 }
            return t
        }
        next.thoughts.removeAll { $0.topicID == "t02" || $0.topicID == "t05" }
        let after = MapLayout.compute(next)
        assertNothingMoved(before, after)
        #expect(after.bubble("t02") == nil && after.bubble("t05") == nil)
        #expect(after.anchors["t02"] == before.anchors["t02"]) // ruht: Platz bleibt gemerkt
        #expect(after.anchors["t05"] == nil) // gelöscht: fällt weg
        // kommt das ruhende Thema zurück und sein Platz ist frei, liegt es wieder genau dort
        let back = MapLayout.compute(input(counts, anchors: after.anchors).removing("t05"))
        #expect(back.bubble("t02")?.center == before.bubble("t02")?.center)
        assertNothingMoved(before, back)
    }

    @Test func returningTopicWhosePlaceIsTakenMovesAlone() {
        let before = MapLayout.compute(input([10, 10, 10, 10, 10, 10, 10]))
        let mid = CGPoint(x: before.bounds.midX, y: before.bounds.midY)
        let inner = before.bubbles.min { hypot($0.center.x - mid.x, $0.center.y - mid.y) < hypot($1.center.x - mid.x, $1.center.y - mid.y) }!
        // das mittlere ruht …
        var resting = input([10, 10, 10, 10, 10, 10, 10], anchors: before.anchors)
        resting.topics = resting.topics.map { var t = $0; if t.id == inner.id { t.count = 0 }; return t }
        resting.thoughts.removeAll { $0.topicID == inner.id }
        // … ein neues nimmt seinen Platz ein …
        add("neu", 10, to: &resting)
        let during = MapLayout.compute(resting)
        let taken = during.bubble("neu")!.center
        #expect(hypot(taken.x - inner.center.x, taken.y - inner.center.y) < inner.outerRadius)
        #expect(during.anchors[inner.id] == nil, "belegter Platz wird vergessen")
        // … dann kehrt es zurück: nur es selbst bekommt einen neuen Platz
        var again = input([10, 10, 10, 10, 10, 10, 10], anchors: during.anchors)
        add("neu", 10, to: &again)
        let after = MapLayout.compute(again)
        assertNothingMoved(during, after)
        assertNoOverlap(after)
        #expect(after.bubble(inner.id)!.center != inner.center)
    }

    @Test func newTopicsFillTheGapOfADeletedOne() {
        let before = MapLayout.compute(input([10, 10, 10, 10, 10, 10, 10]))
        var anchors = before.anchors
        // das Thema nahe der Mitte fällt weg …
        let mid = CGPoint(x: before.bounds.midX, y: before.bounds.midY)
        let inner = before.bubbles.min { hypot($0.center.x - mid.x, $0.center.y - mid.y) < hypot($1.center.x - mid.x, $1.center.y - mid.y) }!
        anchors[inner.id] = nil
        var next = input([10, 10, 10, 10, 10, 10, 10], anchors: anchors).removing(inner.id)
        // … ein neues gleich großes nimmt seinen Platz (ungefähr) ein, statt außen anzubauen
        add("neu", 10, to: &next)
        let after = MapLayout.compute(next)
        assertNoOverlap(after)
        assertNothingMoved(before, after)
        let placed = center(after, "neu")
        #expect(hypot(placed.x - inner.center.x, placed.y - inner.center.y) < inner.outerRadius)
        #expect(after.bounds.width <= before.bounds.width + 1 && after.bounds.height <= before.bounds.height + 1)
    }

    @Test func longSessionKeepsEveryAnchor() {
        // Gedanken kommen nach und nach dazu, gelegentlich ein neues Thema, selten ruht eins – jede Runde mit
        // den Ankern der vorigen. Wer sichtbar bleibt, bewegt sich nie.
        var rng = LCG(state: 2026)
        var counts = [1]
        var layout = MapLayout.compute(input(counts))
        for step in 0..<200 {
            if step % 9 == 0, counts.count < 20 {
                counts.append(1)
            } else if step % 23 == 0, counts.count > 3 {
                counts[rng.int(0..<counts.count)] = 0
            } else {
                let i = rng.int(0..<counts.count)
                counts[i] += 1 + (counts[i] > 10 ? rng.int(0..<6) : 0)
            }
            let next = MapLayout.compute(input(counts, anchors: layout.anchors))
            assertNothingMoved(layout, next)
            assertNoOverlap(next)
            layout = next
        }
    }

    // MARK: Erstplatzierung

    @Test func fewTopicsAreBalancedNotAColumn() {
        for n in 3...5 {
            let layout = MapLayout.compute(input(Array(repeating: 3, count: n)))
            let xs = Set(layout.bubbles.map { ($0.center.x * 10).rounded() })
            #expect(xs.count >= 2, "\(n) Themen liegen in einer Spalte")
            let box = layout.bounds
            #expect(box.width >= 0.45 * box.height, "\(n) Themen: \(box.width) × \(box.height) ist zu schmal")
        }
        // vier gleich große: zwei Spalten (2 × 2 oder versetzt), nicht übereinander
        let four = MapLayout.compute(input([4, 4, 4, 4]))
        let columns = Dictionary(grouping: four.bubbles, by: { ($0.center.x / 40).rounded() })
        #expect(columns.count == 2 && columns.values.allSatisfy { $0.count == 2 }, "\(four.bubbles.map(\.center))")
    }

    @Test func fiveThoughtsWithNoTopicAreBalanced() {
        // wie auf dem Bildschirm: drei Themen mit Titeln und „Ohne Thema“ – zwei links, zwei rechts
        var value = MapLayoutInput(topics: [], thoughts: [])
        add("paply", 2, to: &value)
        add("wohnung", 1, to: &value, age: 600)
        add("urlaub", 1, to: &value, age: 1_200)
        add("_none", 1, to: &value, age: 1_800)
        value.topics = value.topics.map { var t = $0; t.titleLines = t.count; return t }
        let layout = MapLayout.compute(value)
        assertNoOverlap(layout)
        let midX = layout.bubbles.map(\.center.x).reduce(0, +) / CGFloat(layout.bubbles.count)
        let left = layout.bubbles.filter { $0.center.x < midX - 1 }.count, right = layout.bubbles.filter { $0.center.x > midX + 1 }.count
        #expect(left == 2 && right == 2, "\(layout.bubbles.map { ($0.id, $0.center) })")
        #expect(layout.bubbles.allSatisfy { $0.titleLines == $0.count }, "Titel haben Platz")
    }

    @Test func pseudoTopicsSitAtTheBottomEdge() {
        // „Ohne Thema“ kommt an den unteren Rand – nicht in die Mitte
        var start = input([12, 8, 6, 5, 3, 2])
        add("_none", 9, to: &start, age: 3_000)
        let layout = MapLayout.compute(start)
        let none = center(layout, "_none")
        for bubble in layout.bubbles where bubble.id != "_none" {
            #expect(bubble.center.y <= none.y + 0.5, "\(bubble.id) liegt unter „Ohne Thema“")
        }
        // spätere Themen auch nicht darunter
        var later = start
        later.anchors = layout.anchors
        for i in 0..<6 { add("n\(i)", 2 + i, to: &later, age: Double(i)) }
        let grown = MapLayout.compute(later)
        assertNothingMoved(layout, grown)
        for bubble in grown.bubbles where bubble.id != "_none" {
            #expect(bubble.center.y <= none.y + 0.5, "\(bubble.id) liegt unter „Ohne Thema“")
        }
        // erster Gedanke ohne Thema: echte Themen wachsen darüber
        var first = MapLayoutInput(topics: [], thoughts: [])
        add("_none", 1, to: &first)
        let one = MapLayout.compute(first)
        first.anchors = one.anchors
        add("a", 2, to: &first)
        add("b", 1, to: &first, age: 10)
        let three = MapLayout.compute(first)
        #expect(center(three, "_none") == .zero)
        #expect(three.bubbles.allSatisfy { $0.center.y <= 0.5 })
    }

    // MARK: Sammelkreis

    /// 2 000 Gedanken: 500 einzelne vorläufige KI-Themen, 1 500 ohne Thema
    private func crowd() -> MapLayoutInput {
        var value = MapLayoutInput(topics: [], thoughts: [])
        for i in 0..<500 {
            let id = "p\(String(format: "%03d", i))"
            let date = Self.base.addingTimeInterval(-Double(i) * 3_000)
            value.topics.append(.init(id: id, count: 1, lastActivity: date))
            value.thoughts.append(.init(id: "\(id)-s0", topicID: id, createdAt: date))
        }
        value.topics.append(.init(id: "_none", count: 1_500, lastActivity: Self.base))
        for j in 0..<1_500 {
            value.thoughts.append(.init(id: "n\(String(format: "%04d", j))", topicID: "_none",
                                        createdAt: Self.base.addingTimeInterval(-Double(j) * 1_000 - 7)))
        }
        return value
    }

    @Test func crowdIsCappedAndCollected() {
        let value = crowd()
        let layout = MapLayout.compute(value)
        #expect(layout.bubbles.count == config.maxBubbles)
        #expect(layout.bubble("_none") != nil)
        let more = layout.bubble(MapLayout.moreID)
        #expect(more != nil)
        // 22 Kreise für die neuesten einzelnen Themen, der Rest im Sammelkreis
        #expect(layout.collected.count == 500 - (config.maxBubbles - 2))
        #expect(more?.count == layout.collected.count)
        #expect(layout.dots.filter { $0.topicID == MapLayout.moreID }.count == config.maxDots)
        #expect(Set(layout.collected) == MapLayout.collected(value.topics))
        // die neuesten haben einen eigenen Kreis
        #expect(layout.bubble("p000") != nil && layout.bubble("p021") != nil && layout.bubble("p022") == nil)
        // Punkte im Sammelkreis gehören zu gesammelten Themen
        for dot in layout.dots where dot.topicID == MapLayout.moreID {
            #expect(layout.collected.contains(String(dot.id.prefix(4))))
        }
        assertNoOverlap(layout)
        // Gesammelte behalten ihren Anker, falls sie einen hatten
        var withAnchor = value
        withAnchor.anchors = layout.anchors
        withAnchor.anchors["p300"] = MapAnchor(x: 5_000, y: 5_000)
        let again = MapLayout.compute(withAnchor)
        #expect(again.anchors["p300"] == MapAnchor(x: 5_000, y: 5_000))
        assertNothingMoved(layout, again)
    }

    @Test func realTopicsGetACircleBeforeSingles() {
        var value = MapLayoutInput(topics: [], thoughts: [])
        for i in 0..<40 { add("s\(String(format: "%02d", i))", 1, to: &value, age: Double(i)) } // ganz neu, einzeln
        add("alt-zwei", 2, to: &value, age: 900_000) // alt, aber zwei Gedanken
        add("alt-nutzer", 1, to: &value, age: 990_000, pinned: true) // alt, vom Nutzer
        let layout = MapLayout.compute(value)
        #expect(layout.bubble("alt-zwei") != nil)
        #expect(layout.bubble("alt-nutzer") != nil)
        #expect(layout.bubbles.count == config.maxBubbles)
        #expect(layout.bubble(MapLayout.moreID) != nil)
        // genau so viele passen nicht: kein Sammelkreis
        var exact = MapLayoutInput(topics: [], thoughts: [])
        for i in 0..<config.maxBubbles { add("e\(String(format: "%02d", i))", 1, to: &exact, age: Double(i)) }
        #expect(MapLayout.compute(exact).bubble(MapLayout.moreID) == nil)
    }

    @Test func crowdLayoutIsFast() {
        let value = crowd()
        #expect(value.thoughts.count == 2_000)
        let clock = ContinuousClock()
        var first = Duration.seconds(10)
        var layout = MapLayout.empty
        // Minimum aus mehreren Läufen: Lastspitzen der parallel laufenden Tests zählen nicht
        for _ in 0..<7 {
            first = min(first, clock.measure { layout = MapLayout.compute(value) })
        }
        var steady = value
        steady.anchors = layout.anchors
        var again = Duration.seconds(10)
        for _ in 0..<7 {
            again = min(again, clock.measure { _ = MapLayout.compute(steady) })
        }
        // Vorher ≈ 6 s (-O). Jetzt allein gemessen: erste Anordnung (24 Kreise neu anlegen) ≈ 25 ms Debug bzw.
        // ≈ 6 ms -O, mit Ankern ≈ 4 ms bzw. ≈ 1 ms. Unter Volllast der parallelen Tests großzügige Grenzen, die nur
        // echte Ausreißer fangen.
        #expect(first < .milliseconds(150), "erste Anordnung \(first)")
        #expect(again < .milliseconds(50), "mit Ankern \(again)")
    }

    // MARK: Grenzfälle 0, 1, 5, 300

    @Test func emptyMap() {
        let layout = MapLayout.compute(MapLayoutInput(topics: [], thoughts: []))
        #expect(layout == .empty)
        let onlyEmptyTopics = MapLayout.compute(input([0, 0]))
        #expect(onlyEmptyTopics.bubbles.isEmpty && onlyEmptyTopics.bounds == .zero)
    }

    @Test func singleThought() {
        let layout = MapLayout.compute(input([1], titleLines: 1))
        #expect(layout.bubbles.count == 1 && layout.dots.count == 1)
        let bubble = layout.bubbles[0], dot = layout.dots[0]
        #expect(bubble.center == .zero)
        #expect(bubble.hiddenCount == 0)
        #expect(abs(dot.angle + .pi / 2) < 0.0001) // genau oben
        #expect(abs(dot.position.y + bubble.radius + config.firstRing) < 0.0001)
        #expect(bubble.label.height == config.labelHeight + config.titleLineHeight + 4)
        #expect(layout.bounds.contains(bubble.label) && layout.bounds.contains(dot.position))
    }

    @Test func fiveThoughtsWithTitles() {
        let layout = MapLayout.compute(input([2, 2, 1], titleLines: 2))
        #expect(layout.bubbles.count == 3 && layout.dots.count == 5)
        #expect(layout.bubbles.allSatisfy { $0.label.width >= config.titleWidth })
        #expect(layout.bubbles.allSatisfy { $0.titleLines == 2 })
        assertNoOverlap(layout)
    }

    @Test func threeHundredThoughtsInOneTopic() {
        let layout = MapLayout.compute(input([300]))
        let bubble = layout.bubbles[0]
        #expect(layout.dots.count == config.maxDots)
        #expect(bubble.hiddenCount == 300 - config.maxDots)
        #expect(bubble.radius == config.maxRadius)
        // neueste innen: Rang 0 … auf Ring 0, Ringe steigen mit dem Alter
        let rings = layout.dots.sorted { $0.rank < $1.rank }.map(\.ring)
        #expect(rings == rings.sorted())
        #expect(layout.dots.first { $0.rank == 0 }?.id == "t00-s0000")
        // alle Punkte über der Beschriftung, keiner im Kreis
        for dot in layout.dots {
            let d = hypot(dot.position.x - bubble.center.x, dot.position.y - bubble.center.y)
            #expect(d >= bubble.radius + config.firstRing - 0.001 && d <= bubble.outerRadius)
            #expect(dot.position.y < bubble.label.minY)
        }
    }

    @Test func allDotsFitOnTheInnerArc() {
        // keine einzelnen Punkte auf einem zweiten Ring: für jede Anzahl reicht der innere Bogen
        for n in 1...400 {
            let radius = config.radius(for: n)
            #expect(MapGeometry.ringCount(dots: min(n, config.maxDots), radius: radius, config: config) == 1, "n=\(n)")
        }
    }

    @Test func dotsKeepMinimumSpacing() {
        for n in [2, 7, 16, 24] {
            let layout = MapLayout.compute(input([n]))
            let dots = layout.dots
            for i in dots.indices {
                for j in dots.indices where j > i {
                    let d = hypot(dots[i].position.x - dots[j].position.x, dots[i].position.y - dots[j].position.y)
                    #expect(d >= config.dotSpacing * 0.95, "n=\(n): Punkte \(i)/\(j) nur \(d) auseinander")
                }
            }
        }
    }

    @Test func newThoughtShiftsDotsOnlyOnePlace() {
        let before = MapLayout.compute(input([30]))
        var next = input([31])
        // Gedanke 0 ist der neue; die alten heißen gleich, aber eine Stunde älter verschoben → neu aufbauen
        next.thoughts = [MapLayoutInput.Thought(id: "neu", topicID: "t00", createdAt: Self.base.addingTimeInterval(60))]
            + input([30]).thoughts
        next.anchors = before.anchors
        let after = MapLayout.compute(next)
        #expect(after.dots.first { $0.rank == 0 }?.id == "neu")
        for dot in before.dots where dot.rank < config.maxDots - 1 {
            guard let moved = after.dots.first(where: { $0.id == dot.id }) else {
                Issue.record("\(dot.id) fehlt")
                continue
            }
            #expect(moved.rank == dot.rank + 1)
            let d = hypot(moved.position.x - dot.position.x, moved.position.y - dot.position.y)
            #expect(d < 30, "\(dot.id) springt \(d)")
        }
        // der älteste sichtbare verschwindet im Kreis
        let oldest = before.dots.first { $0.rank == config.maxDots - 1 }!
        #expect(!after.dots.contains { $0.id == oldest.id })
    }

    // MARK: Linien

    @Test func linesOnlyForRealLinksAtMostTwoPerThought() {
        var links: [MapLayoutInput.Link] = []
        for j in 1..<8 { links.append(.init(from: "t00-s0000", to: "t01-s000\(j)")) } // 7 Links am selben Gedanken
        links.append(.init(from: "t02-s0000", to: "t02-s0001")) // im Thema
        links.append(.init(from: "t02-s0001", to: "t02-s0000")) // doppelt, andersherum
        links.append(.init(from: "t02-s0000", to: "gibt-es-nicht"))
        links.append(.init(from: "t02-s0002", to: "t02-s0002")) // auf sich selbst
        let layout = MapLayout.compute(input([3, 9, 4], links: links))
        var perThought: [String: Int] = [:]
        for line in layout.lines {
            perThought[line.a, default: 0] += 1
            perThought[line.b, default: 0] += 1
            #expect(links.contains { ($0.from == line.a && $0.to == line.b) || ($0.from == line.b && $0.to == line.a) })
            #expect(line.crossTopic == (line.topicA != line.topicB))
        }
        #expect(perThought.values.allSatisfy { $0 <= config.maxLinksPerThought })
        #expect(perThought["t00-s0000"] == 2)
        #expect(layout.lines.filter { !$0.crossTopic }.count == 1)
        #expect(!layout.lines.contains { $0.a == "gibt-es-nicht" || $0.b == "gibt-es-nicht" })
    }

    @Test func linesToHiddenThoughtsStartAtTheCircle() {
        // t00 hat 40 Gedanken; der älteste hat keinen Punkt
        let links = [MapLayoutInput.Link(from: "t00-s0039", to: "t01-s0000"), .init(from: "t00-s0039", to: "t00-s0000")]
        let layout = MapLayout.compute(input([40, 2], links: links))
        #expect(layout.lines.count == 1) // im Thema ohne Punkt: keine Linie
        let line = layout.lines[0]
        #expect(line.touchesHidden && line.crossTopic)
        let bubble = layout.bubble("t00")!
        let start = line.a == "t00-s0039" ? line.from : line.to
        #expect(abs(hypot(start.x - bubble.center.x, start.y - bubble.center.y) - bubble.radius) < 0.01)
    }

    @Test func overviewShowsFewStrongTopicLines() {
        var links: [MapLayoutInput.Link] = []
        for j in 0..<4 { links.append(.init(from: "t00-s000\(j)", to: "t01-s000\(j)")) } // 4 × t00–t01
        links.append(.init(from: "t01-s0000", to: "t00-s0000")) // doppelt, andersherum
        links.append(.init(from: "t00-s0005", to: "t02-s0000")) // nur 1 × t00–t02: keine Linie
        links.append(.init(from: "t00-s0006", to: "t00-s0007")) // im Thema: keine Themen-Linie
        for k in 3..<7 { // t00 mit vier weiteren, je zweimal
            links.append(.init(from: "t00-s0008", to: "t0\(k)-s0000"))
            links.append(.init(from: "t00-s0009", to: "t0\(k)-s0001"))
        }
        let layout = MapLayout.compute(input([12, 6, 3, 3, 3, 3, 3], links: links))
        let pairs = layout.topicLines
        #expect(pairs.first?.id == "t00|t01" && pairs.first?.count == 4) // stärkste zuerst
        #expect(pairs.allSatisfy { $0.a < $0.b && $0.count >= config.minTopicLinks })
        #expect(!pairs.contains { $0.id == "t00|t02" })
        // je Thema höchstens drei
        var perTopic: [String: Int] = [:]
        for line in pairs { perTopic[line.a, default: 0] += 1; perTopic[line.b, default: 0] += 1 }
        #expect(perTopic.values.allSatisfy { $0 <= config.maxTopicLinesPerTopic })
        // Kreisrand zu Kreisrand
        for line in pairs {
            let a = layout.bubble(line.a)!, b = layout.bubble(line.b)!
            #expect(abs(hypot(line.from.x - a.center.x, line.from.y - a.center.y) - a.radius) < 0.01)
            #expect(abs(hypot(line.to.x - b.center.x, line.to.y - b.center.y) - b.radius) < 0.01)
        }
        #expect(MapLayout.compute(input([12, 6, 3, 3, 3, 3, 3], links: links.reversed())).topicLines == pairs)
    }

    @Test func topicLinesAreCappedAndSkipPseudoTopics() {
        // 20 Themen, jedes Paar (i, i+1) dreimal verknüpft – höchstens sechs Linien
        var links: [MapLayoutInput.Link] = []
        for i in 0..<19 {
            for j in 0..<3 { links.append(.init(from: "\(Self.id(i))-s000\(j)", to: "\(Self.id(i + 1))-s000\(j)")) }
        }
        var value = input(Array(repeating: 4, count: 20), links: links)
        add("_none", 4, to: &value)
        for j in 0..<3 { value.links.append(.init(from: "t00-s000\(j)", to: "_none-s000\(j)")) }
        let layout = MapLayout.compute(value)
        #expect(layout.topicLines.count <= config.maxTopicLines)
        #expect(!layout.topicLines.isEmpty)
        #expect(!layout.topicLines.contains { $0.a.hasPrefix("_") || $0.b.hasPrefix("_") })
    }

    @Test func topicLinesNeverCrossAThirdCircle() {
        // drei Themen in einer Reihe: A – C – B. A–B ist eng verknüpft, die Linie liefe durch C → entfällt
        let anchors = ["a": MapAnchor(x: 0, y: 0), "c": MapAnchor(x: 180, y: 0), "b": MapAnchor(x: 360, y: 0)]
        var value = MapLayoutInput(topics: [], thoughts: [], anchors: anchors)
        add("a", 3, to: &value)
        add("b", 3, to: &value)
        add("c", 3, to: &value)
        for j in 0..<3 { value.links.append(.init(from: "a-s000\(j)", to: "b-s000\(j)")) }
        for j in 0..<2 { value.links.append(.init(from: "a-s000\(j)", to: "c-s000\(j)")) }
        let layout = MapLayout.compute(value)
        #expect(layout.topicLines.map(\.id) == ["a|c"])
        // allgemein: keine Linie läuft durch einen anderen Kreis
        var rng = LCG(state: 5)
        var many = input(Array(repeating: 5, count: 14))
        for _ in 0..<200 {
            let a = rng.int(0..<14), b = rng.int(0..<14)
            many.links.append(.init(from: "\(Self.id(a))-s000\(rng.int(0..<5))", to: "\(Self.id(b))-s000\(rng.int(0..<5))"))
        }
        let busy = MapLayout.compute(many)
        for line in busy.topicLines {
            for bubble in busy.bubbles where bubble.id != line.a && bubble.id != line.b {
                for i in 0...20 {
                    let t = CGFloat(i) / 20, u = 1 - t
                    let p = CGPoint(x: u * u * line.from.x + 2 * u * t * line.control.x + t * t * line.to.x,
                                    y: u * u * line.from.y + 2 * u * t * line.control.y + t * t * line.to.y)
                    #expect(hypot(p.x - bubble.center.x, p.y - bubble.center.y) > bubble.radius, "\(line.id) kreuzt \(bubble.id)")
                }
            }
        }
    }

    // MARK: Leistung

    @Test func twoThousandThoughtsAreFast() {
        var rng = LCG(state: 99)
        let counts = [420, 300, 260, 200, 160, 140, 120, 100, 80, 60, 50, 40, 30, 20, 20]
        var base = input(counts)
        base.links = (0..<500).map { _ in
            let a = base.thoughts[rng.int(0..<base.thoughts.count)].id, b = base.thoughts[rng.int(0..<base.thoughts.count)].id
            return MapLayoutInput.Link(from: a, to: b)
        }
        #expect(base.thoughts.count == 2_000)
        let clock = ContinuousClock()
        var first = Duration.seconds(10)
        var layout = MapLayout.empty
        // Minimum aus mehreren Läufen: Lastspitzen der parallel laufenden Tests zählen nicht
        for _ in 0..<7 {
            first = min(first, clock.measure { layout = MapLayout.compute(base) })
        }
        var steady = base
        steady.anchors = layout.anchors
        var again = Duration.seconds(10)
        for _ in 0..<7 {
            again = min(again, clock.measure { _ = MapLayout.compute(steady) })
        }
        // Debug-Build unter Volllast der parallelen Tests: großzügige Grenze, die nur echte Ausreißer fängt
        #expect(first < .milliseconds(150), "erste Anordnung \(first)")
        #expect(again < .milliseconds(100), "mit Ankern \(again)")
        assertNoOverlap(layout)
    }
}

private extension MapLayoutInput {
    /// ohne dieses Thema und seine Gedanken
    func removing(_ id: String) -> MapLayoutInput {
        var copy = self
        copy.topics.removeAll { $0.id == id }
        copy.thoughts.removeAll { $0.topicID == id }
        return copy
    }
}
