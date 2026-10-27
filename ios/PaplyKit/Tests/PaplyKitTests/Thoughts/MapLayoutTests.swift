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

    /// `counts[i]` Gedanken in Thema `t<i>`, Gedanke j eines Themas j Stunden alt
    private func input(_ counts: [Int], anchors: [String: MapAnchor] = [:], links: [MapLayoutInput.Link] = [],
                       titleLines: Int = 0, prefix: String = "t") -> MapLayoutInput {
        var topics: [MapLayoutInput.Topic] = []
        var thoughts: [MapLayoutInput.Thought] = []
        for (i, n) in counts.enumerated() {
            let id = "\(prefix)\(String(format: "%02d", i))"
            topics.append(.init(id: id, count: n, lastActivity: Self.base.addingTimeInterval(-Double(i) * 600), titleLines: titleLines))
            for j in 0..<n {
                thoughts.append(.init(id: "\(id)-s\(String(format: "%04d", j))", topicID: id,
                                      createdAt: Self.base.addingTimeInterval(-Double(i) * 600 - Double(j) * 3_600)))
            }
        }
        return MapLayoutInput(topics: topics, thoughts: thoughts, links: links, anchors: anchors)
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

    private func center(_ layout: MapLayout, _ id: String) -> CGPoint { layout.bubble(id)!.center }

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

    // MARK: Überlappung

    @Test func circlesNeverOverlap() {
        var rng = LCG(state: 42)
        for _ in 0..<6 {
            let counts = (0..<rng.int(8..<40)).map { _ in rng.int(1..<120) }
            let layout = MapLayout.compute(input(counts))
            #expect(layout.bubbles.count == counts.count)
            assertNoOverlap(layout)
        }
    }

    @Test func clusteredAnchorsAreSeparated() {
        // alle Anker auf (fast) demselben Punkt: alles muss trotzdem frei liegen
        var anchors: [String: MapAnchor] = [:]
        for i in 0..<12 { anchors["t\(String(format: "%02d", i))"] = MapAnchor(x: Double(i % 2), y: 0) }
        let layout = MapLayout.compute(input(Array(repeating: 20, count: 12), anchors: anchors))
        assertNoOverlap(layout)
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

    // MARK: Stabilität

    @Test func newTopicKeepsEveryoneElseInPlace() {
        let before = MapLayout.compute(input([10, 4, 7, 2, 15]))
        let after = MapLayout.compute(input([10, 4, 7, 2, 15, 3], anchors: before.anchors))
        for bubble in before.bubbles {
            #expect(center(after, bubble.id) == bubble.center, "\(bubble.id) ist gewandert")
        }
        assertNoOverlap(after)
        // neu = an einer freien Stelle nahe der Mitte: berührt mindestens ein vorhandenes Thema
        let new = footprints(after).first { $0.id == "t05" }!
        let nearest = footprints(after).filter { $0.id != "t05" }.map { other -> CGFloat in
            let push = MapGeometry.penetration(new, other, gap: config.gap + 40)
            return push?.depth ?? 0
        }.max() ?? 0
        #expect(nearest > 0, "neues Thema liegt nicht an den anderen")
        #expect(before.bounds.insetBy(dx: -new.bound - config.gap - 1, dy: -new.bound - config.gap - 1).contains(new.center))
    }

    @Test func newTopicsFillTheGapOfADeletedOne() {
        let before = MapLayout.compute(input([10, 10, 10, 10, 10, 10, 10]))
        var anchors = before.anchors
        // das Thema nahe der Mitte fällt weg …
        let mid = CGPoint(x: before.bounds.midX, y: before.bounds.midY)
        let inner = before.bubbles.min { hypot($0.center.x - mid.x, $0.center.y - mid.y) < hypot($1.center.x - mid.x, $1.center.y - mid.y) }!
        anchors[inner.id] = nil
        var next = input([10, 10, 10, 10, 10, 10, 10], anchors: anchors)
        next.topics.removeAll { $0.id == inner.id }
        next.thoughts.removeAll { $0.topicID == inner.id }
        // … ein neues gleich großes nimmt seinen Platz (ungefähr) ein, statt außen anzubauen
        next.topics.append(.init(id: "neu", count: 10, lastActivity: Self.base))
        for j in 0..<10 { next.thoughts.append(.init(id: "neu-\(j)", topicID: "neu", createdAt: Self.base.addingTimeInterval(Double(-j)))) }
        let after = MapLayout.compute(next)
        assertNoOverlap(after)
        let placed = center(after, "neu")
        #expect(hypot(placed.x - inner.center.x, placed.y - inner.center.y) < inner.outerRadius)
        #expect(after.bounds.width <= before.bounds.width + 1 && after.bounds.height <= before.bounds.height + 1)
    }

    /// Wie stark ist die Fläche von `id` gewachsen (Ringe bzw. Beschriftungsfeld)?
    private func growth(_ id: String, _ before: MapLayout, _ after: MapLayout) -> CGFloat {
        let old = before.bubble(id)!, new = after.bubble(id)!
        return max(new.outerRadius - old.outerRadius, new.label.maxY - new.center.y - (old.label.maxY - old.center.y),
                   (new.label.width - old.label.width) / 2) + 1
    }

    private func moved(_ id: String, _ before: MapLayout, _ after: MapLayout) -> CGFloat {
        let a = center(before, id), b = center(after, id)
        return hypot(a.x - b.x, a.y - b.y)
    }

    @Test func growingCircleAtTheEdgeOnlyNudgesItsNeighbours() {
        let counts = Array(repeating: 6, count: 20)
        let before = MapLayout.compute(input(counts))
        var grown = counts
        grown[19] = 120 // zuletzt angelegt → am Rand; Kreis und Ringe wachsen deutlich
        let after = MapLayout.compute(input(grown, anchors: before.anchors))
        assertNoOverlap(after)
        let g = growth("t19", before, after)
        var unmoved = 0
        for bubble in before.bubbles where bubble.id != "t19" {
            let d = moved(bubble.id, before, after)
            #expect(d <= g * 1.5, "\(bubble.id) ist \(d) gewandert (Wachstum \(g))")
            if d == 0 { unmoved += 1 }
        }
        // am Rand ist es oft kürzer, wenn der gewachsene Kreis selbst ein Stück rückt
        #expect(moved("t19", before, after) <= 2 * g)
        #expect(unmoved >= 15, "es wurde zu viel verschoben (\(unmoved) von 20 unbewegt)")
    }

    @Test func growingCircleInTheMiddleMovesLittleInTotal() {
        let counts = Array(repeating: 6, count: 10)
        let before = MapLayout.compute(input(counts))
        var grown = counts
        grown[0] = 120 // zuerst angelegt → in der Mitte
        let after = MapLayout.compute(input(grown, anchors: before.anchors))
        assertNoOverlap(after)
        let g = growth("t00", before, after)
        var squared: CGFloat = 0
        for bubble in before.bubbles {
            let d = moved(bubble.id, before, after)
            #expect(d <= g * 1.6, "\(bubble.id) ist \(d) gewandert (Wachstum \(g))")
            squared += d * d
        }
        // dicht gepackt müssen die direkten Nachbarn weichen – mehr als ein voller Ring (6) um das ganze
        // Wachstum ist es aber nie; nichts wird neu sortiert
        #expect(squared <= 6 * g * g, "Gesamtweg² \(squared), Wachstum \(g)")
    }

    @Test func growthOneThoughtAtATimeIsCalm() {
        // realistisch: ein Gedanke nach dem anderen im mittleren Thema
        var counts = Array(repeating: 8, count: 12)
        var layout = MapLayout.compute(input(counts))
        var maxStep: CGFloat = 0
        for _ in 0..<60 {
            counts[0] += 1
            let next = MapLayout.compute(input(counts, anchors: layout.anchors))
            for bubble in layout.bubbles { maxStep = max(maxStep, moved(bubble.id, layout, next)) }
            assertNoOverlap(next)
            layout = next
        }
        // kein Thema springt je mehr als einen Ring-Abstand (+ Spielraum)
        #expect(maxStep <= config.ringStep + config.dotRadius + 2, "größter Schritt \(maxStep)")
    }

    @Test func longSessionStaysStableAndFree() {
        // Gedanken kommen nach und nach dazu, gelegentlich ein neues Thema – jede Runde mit den Ankern der vorigen
        var rng = LCG(state: 2026)
        var counts = [1]
        var layout = MapLayout.compute(input(counts))
        var totalMoves: CGFloat = 0
        for step in 0..<160 {
            if step % 9 == 0, counts.count < 18 { counts.append(1) } else { counts[rng.int(0..<counts.count)] += 1 }
            let next = MapLayout.compute(input(counts, anchors: layout.anchors))
            for bubble in layout.bubbles {
                let c = center(next, bubble.id)
                totalMoves += hypot(c.x - bubble.center.x, c.y - bubble.center.y)
            }
            assertNoOverlap(next)
            layout = next
        }
        // Wachstum verschiebt wenig: im Mittel weniger als ein Punkt je Thema und Runde
        #expect(totalMoves / CGFloat(160 * 10) < 1, "Gesamtverschiebung \(totalMoves)")
    }

    // MARK: Anker

    @Test func dormantTopicsKeepTheirAnchorDeletedOnesDrop() {
        let first = MapLayout.compute(input([5, 5, 5]))
        var next = input([5, 0, 5], anchors: first.anchors)
        next.thoughts.removeAll { $0.topicID == "t01" }
        next.topics.removeAll { $0.id == "t02" } // gelöscht
        next.thoughts.removeAll { $0.topicID == "t02" }
        let layout = MapLayout.compute(next)
        #expect(layout.bubbles.map(\.id) == ["t00"])
        #expect(layout.anchors["t01"] == first.anchors["t01"]) // ruht, Platz bleibt gemerkt
        #expect(layout.anchors["t02"] == nil) // gelöscht → fällt weg
        #expect(layout.anchors["t00"] == first.anchors["t00"])
    }

    @Test func invalidAnchorsAreIgnored() {
        let layout = MapLayout.compute(input([3, 3], anchors: ["t00": MapAnchor(x: .nan, y: 0), "t01": MapAnchor(x: 10, y: 10)]))
        #expect(layout.bubbles.allSatisfy { $0.center.x.isFinite && $0.center.y.isFinite })
        #expect(center(layout, "t01") == CGPoint(x: 10, y: 10))
        assertNoOverlap(layout)
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

    @Test func overviewBundlesLinksPerTopicPair() {
        var links: [MapLayoutInput.Link] = []
        for j in 0..<4 { links.append(.init(from: "t00-s000\(j)", to: "t01-s000\(j)")) } // 4 × t00–t01
        links.append(.init(from: "t01-s0000", to: "t00-s0000")) // doppelt, andersherum
        links.append(.init(from: "t00-s0005", to: "t02-s0000")) // 1 × t00–t02
        links.append(.init(from: "t00-s0006", to: "t00-s0007")) // im Thema: keine Themen-Linie
        for k in 3..<7 { links.append(.init(from: "t00-s0008", to: "t0\(k)-s0000")) } // t00 mit vier weiteren
        let layout = MapLayout.compute(input([12, 6, 3, 3, 3, 3, 3], links: links))
        let pairs = layout.topicLines
        #expect(pairs.first?.id == "t00|t01" && pairs.first?.count == 4) // stärkste zuerst
        #expect(pairs.allSatisfy { $0.a < $0.b })
        // je Thema höchstens drei
        var perTopic: [String: Int] = [:]
        for line in pairs { perTopic[line.a, default: 0] += 1; perTopic[line.b, default: 0] += 1 }
        #expect(perTopic.values.allSatisfy { $0 <= config.maxTopicLinesPerTopic })
        #expect(perTopic["t00"] == config.maxTopicLinesPerTopic)
        // Kreisrand zu Kreisrand
        for line in pairs {
            let a = layout.bubble(line.a)!, b = layout.bubble(line.b)!
            #expect(abs(hypot(line.from.x - a.center.x, line.from.y - a.center.y) - a.radius) < 0.01)
            #expect(abs(hypot(line.to.x - b.center.x, line.to.y - b.center.y) - b.radius) < 0.01)
        }
        #expect(MapLayout.compute(input([12, 6, 3, 3, 3, 3, 3], links: links.reversed())).topicLines == pairs)
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
        // (allein ~18 ms bzw. ~2,4 ms)
        #expect(first < .milliseconds(250), "erste Anordnung \(first)")
        #expect(again < .milliseconds(100), "mit Ankern \(again)")
        assertNoOverlap(layout)
    }
}
