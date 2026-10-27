import CoreGraphics
import Foundation
import PaplyKit

// Was die Karte zeichnet: Anordnung (`MapLayout`, PaplyKit) plus Anzeige-Angaben aus dem Modell.
// `MapEngine` baut die Eingabe aus `ThoughtsModel` und rechnet nur neu, wenn sie sich ändert.
// `MapMotion` merkt sich den vorigen Stand für weiche Übergänge und neu dazugekommene Punkte.

struct MapTopicInfo: Equatable {
    var title: String
    var icon: Lucide
    var count: Int
    var open: Int
}

struct MapDotInfo: Equatable {
    var title: String
    var date: Date
    var hasOpenTask: Bool
    /// jünger als 24 h – bekommt einen zarten Schein
    var isRecent: Bool
}

struct MapScene: Equatable {
    var layout: MapLayout
    /// Themen-ID → Anzeige
    var topics: [String: MapTopicInfo]
    /// Gedanken-ID → Anzeige (nur Gedanken mit Punkt)
    var dots: [String: MapDotInfo]
    /// alle Gedanken auf der Karte
    var total: Int
    /// sehr wenige Gedanken: Titel stehen unter den Kreisen
    var few: Bool
    /// steigt, sobald sich die Anordnung ändert
    var version: Int

    static let empty = MapScene(layout: .empty, topics: [:], dots: [:], total: 0, few: false, version: 0)

    /// Titel unter einem Kreis (wenige Gedanken), neueste zuerst
    func titles(of topicID: String) -> [(id: String, title: String)] {
        layout.dots.filter { $0.topicID == topicID }.sorted { $0.rank < $1.rank }
            .compactMap { dot in dots[dot.id].map { (dot.id, $0.title) } }
    }
}

@MainActor
final class MapEngine {
    /// bis hierher stehen Titel direkt unter den Kreisen
    static let fewLimit = 5

    private var lastInput: MapLayoutInput?
    private var lastLayout = MapLayout.empty
    private var version = 0

    func scene(model: ThoughtsModel, anchors: [String: MapAnchor], now: Date) -> MapScene {
        // Gedanken, die gerade geordnet werden, erscheinen erst fertig an ihrem Kreis
        let visible = model.thoughts.filter { !$0.isProcessing }
        var topicOf: [String: String] = [:]
        var counts: [String: Int] = [:]
        var open: [String: Int] = [:]
        var last: [String: Date] = [:]
        var items: [MapLayoutInput.Thought] = []
        items.reserveCapacity(visible.count)
        for thought in visible {
            let topic = model.topic(thought.topicId)?.id ?? ThoughtMapView.noTopicID
            topicOf[thought.id] = topic
            counts[topic, default: 0] += 1
            open[topic, default: 0] += thought.openTaskCount
            last[topic] = max(last[topic] ?? .distantPast, thought.createdAt)
            items.append(MapLayoutInput.Thought(id: thought.id, topicID: topic, createdAt: thought.createdAt))
        }
        let few = visible.count <= Self.fewLimit
        var topics: [MapLayoutInput.Topic] = model.topics.map { topic in
            let n = counts[topic.id] ?? 0
            return MapLayoutInput.Topic(id: topic.id, count: n, lastActivity: last[topic.id] ?? topic.createdAt,
                                        titleLines: few ? n : 0)
        }
        let none = counts[ThoughtMapView.noTopicID] ?? 0
        topics.append(MapLayoutInput.Topic(id: ThoughtMapView.noTopicID, count: none,
                                           lastActivity: last[ThoughtMapView.noTopicID] ?? .distantPast, titleLines: few ? none : 0))
        var links: [MapLayoutInput.Link] = []
        for thought in visible {
            for link in thought.links where topicOf[link.target] != nil {
                links.append(MapLayoutInput.Link(from: thought.id, to: link.target))
            }
        }
        let input = MapLayoutInput(topics: topics, thoughts: items, links: links, anchors: anchors)
        if input != lastInput {
            let layout = MapLayout.compute(input)
            if layout != lastLayout { version += 1 }
            lastLayout = layout
            lastInput = input
        }

        // Anzeige (billig: nur gezeichnete Themen und Punkte)
        var topicInfo: [String: MapTopicInfo] = [:]
        for bubble in lastLayout.bubbles {
            if bubble.id == ThoughtMapView.noTopicID {
                topicInfo[bubble.id] = MapTopicInfo(title: "Ohne Thema", icon: .circleDashed, count: bubble.count, open: open[bubble.id] ?? 0)
            } else if let topic = model.topic(bubble.id) {
                topicInfo[bubble.id] = MapTopicInfo(title: topic.title, icon: topic.icon.lucide, count: bubble.count, open: open[bubble.id] ?? 0)
            }
        }
        var dotInfo: [String: MapDotInfo] = [:]
        for dot in lastLayout.dots {
            guard let thought = model.thought(dot.id) else { continue }
            dotInfo[dot.id] = MapDotInfo(title: thought.displayTitle, date: thought.createdAt, hasOpenTask: thought.openTaskCount > 0,
                                         isRecent: now.timeIntervalSince(thought.createdAt) < 86_400)
        }
        return MapScene(layout: lastLayout, topics: topicInfo, dots: dotInfo, total: visible.count, few: few, version: version)
    }
}

/// Übergänge zwischen zwei Ständen der Karte (zeitgesteuert, damit der erste Bild nie springt) und das
/// Einblenden neuer Punkte. Wird im `body` fortgeschrieben – reine Buchführung, löst nichts aus.
@MainActor
final class MapMotion {
    /// Feder für Datenwechsel (kritisch gedämpft, ≈ 0,6 s)
    static let settle: TimeInterval = 0.65
    static let appearDuration: TimeInterval = 1.1
    /// mehr neue Punkte auf einmal: kein Einblenden (nichts Teures)
    static let appearLimit = 6

    private(set) var current: MapScene?
    private(set) var previous: MapScene?
    private(set) var start = Date.distantPast
    private(set) var appear: [String: Date] = [:]
    private var knownDots: Set<String> = []
    private var knownTopics: Set<String> = []

    /// Neuen Stand übernehmen. Gibt true zurück, wenn ab jetzt etwas läuft.
    @discardableResult
    func update(_ scene: MapScene, now: Date) -> Bool {
        defer { current = scene }
        guard let current, current.version != scene.version else {
            if self.current == nil {
                knownDots = Set(scene.layout.dots.map(\.id))
                knownTopics = Set(scene.layout.bubbles.map(\.id))
            }
            return false
        }
        previous = current
        start = now
        let dots = Set(scene.layout.dots.map(\.id)), topics = Set(scene.layout.bubbles.map(\.id))
        let newDots = dots.subtracting(knownDots), newTopics = topics.subtracting(knownTopics)
        appear = appear.filter { now.timeIntervalSince($0.value) < Self.appearDuration }
        // erster Stand nach dem Laden: nur weich einblenden, nichts ploppt
        let firstContent = current.layout.bubbles.isEmpty
        if !firstContent, newDots.count <= Self.appearLimit {
            for id in newDots { appear[id] = now }
        }
        if !firstContent, newTopics.count <= 3 {
            for id in newTopics { appear["topic:" + id] = now }
        }
        knownDots = dots
        knownTopics = topics
        return true
    }

    /// 0 … 1, kritisch gedämpfte Feder
    func progress(at now: Date) -> CGFloat {
        guard previous != nil else { return 1 }
        let t = now.timeIntervalSince(start)
        guard t < Self.settle else { return 1 }
        let w = 11.0
        return CGFloat(1 - (1 + w * t) * exp(-w * t))
    }

    func isRunning(at now: Date) -> Bool {
        if previous != nil, now.timeIntervalSince(start) < Self.settle { return true }
        return appear.values.contains { now.timeIntervalSince($0) < Self.appearDuration }
    }

    /// Fortschritt des Einblendens (nil = kein Einblenden)
    func appearance(_ key: String, at now: Date) -> CGFloat? {
        guard let begin = appear[key] else { return nil }
        let t = now.timeIntervalSince(begin) / Self.appearDuration
        return t < 1 ? CGFloat(max(0, t)) : nil
    }

    /// längste noch laufende Zeit (für das Abschalten der Zeitleiste)
    func remaining(at now: Date) -> TimeInterval {
        var rest: TimeInterval = 0
        if previous != nil { rest = max(rest, Self.settle - now.timeIntervalSince(start)) }
        for begin in appear.values { rest = max(rest, Self.appearDuration - now.timeIntervalSince(begin)) }
        return max(0, rest)
    }
}
