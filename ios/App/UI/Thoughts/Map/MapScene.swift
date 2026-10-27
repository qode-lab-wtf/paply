import CoreGraphics
import Foundation
import Observation
import PaplyKit
import UIKit

// Was die Karte zeichnet: Anordnung (`MapLayout`, PaplyKit) plus Anzeige-Angaben aus dem Modell.
// `MapEngine` baut die Eingabe aus `ThoughtsModel` (billig, MainActor) und rechnet die Anordnung im
// Hintergrund; veraltete Ergebnisse werden verworfen, bis dahin bleibt die letzte Karte stehen.
// `MapMotion` merkt sich den vorigen Stand für weiche Übergänge, neu dazugekommene Punkte und die Flüge aus dem
// Eingang (`MapLandings`).
//
// Eingang: Gedanken, die gerade geordnet werden oder warten (`isInMapInbox`), stehen auf keinem Kreis – auch nicht
// unter „Ohne Thema“. Sie zählen an der Kugel (`MapInboxOrb`) und fliegen fertig zu ihrem Kreis.

extension Thought {
    /// Wird geordnet oder wartet: steht noch auf keinem Kreis, zählt an der Kugel (wie das Panel „Noch nicht
    /// geordnet“, `ThoughtsHome.pendingID`)
    var isInMapInbox: Bool { isProcessing || isWaiting }
}

/// Eingang der Karte: wer gerade geordnet wird oder wartet, und was die Kugel dazu sagt
struct MapInbox: Equatable {
    var ids: Set<String> = []
    var status: MapInboxStatus?
    /// alle Gedanken, die es gibt (ohne „Zuletzt gelöscht“): Wer fehlt, fliegt nicht und zählt nicht mehr
    var existing: Set<String> = []

    static let empty = MapInbox()

    @MainActor
    init(model: ThoughtsModel) {
        var ids = Set<String>()
        var existing = Set<String>(minimumCapacity: model.thoughts.count)
        var states: [ThoughtState] = []
        for thought in model.thoughts {
            existing.insert(thought.id)
            guard thought.isInMapInbox else { continue }
            ids.insert(thought.id)
            states.append(thought.state)
        }
        self.ids = ids
        self.existing = existing
        status = MapInboxStatus.of(states)
    }

    private init() {}
}

struct MapTopicInfo: Equatable {
    enum Kind: Equatable {
        case topic
        /// „Ohne Thema“: hohler, gestrichelter Ring
        case none
        /// Sammelkreis „Weitere Themen“
        case more
    }

    var title: String
    var icon: Lucide
    var count: Int
    var open: Int
    var kind: Kind = .topic
    /// Bild statt Symbol (`TopicImages`, quadratisch)
    var image: UIImage?
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

/// Eingabe der Anordnung, aus dem Modell gebaut
struct MapRequest: Equatable {
    var input: MapLayoutInput
    /// gezeichnete Gedanken (ohne die, die gerade geordnet werden)
    var total: Int
    /// Stand der gemerkten Plätze, mit denen `input` gebaut ist (`MapAnchors.revision`): Nur eine Anordnung mit
    /// dem aktuellen Stand darf ihre Plätze merken.
    var anchorRevision: Int
}

@MainActor
@Observable
final class MapEngine {
    /// bis hierher stehen Titel direkt unter den Kreisen
    static let fewLimit = 5

    /// zuletzt fertige Anordnung (nil = noch keine)
    private(set) var layout: MapLayout?
    /// steigt, sobald sich die Anordnung ändert
    private(set) var version = 0
    /// Gedanke → Kreis in `layout` (gesammelte Themen: `MapLayout.moreID`) – wohin ein fertiger Gedanke fliegt
    @ObservationIgnored private(set) var placed: [String: String] = [:]

    /// Eingabe, zu der `layout` gehört – mit den eigenen Ankern der Anordnung (rechnet man damit erneut,
    /// kommt genau `layout` heraus; das muss nicht noch einmal gerechnet werden)
    @ObservationIgnored private var settled: MapLayoutInput?
    @ObservationIgnored private var requested: MapRequest?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// Stand der zuletzt gezeigten Karte: Eine neu erzeugte Ansicht beginnt damit statt leer
    private static var last: (layout: MapLayout, version: Int, settled: MapLayoutInput, placed: [String: String])?

    init() {
        if let last = Self.last {
            layout = last.layout
            version = last.version
            settled = last.settled
            placed = last.placed
        }
    }

    /// Kreis eines Gedankens in der aktuellen Anordnung (nil = steht nicht auf der Karte)
    func bubble(ofThought id: String) -> String? { placed[id] }

    // MARK: Eingabe

    /// Eingabe aus dem Modell. Gedanken im Eingang (werden geordnet oder warten) erscheinen erst fertig an ihrem
    /// Kreis – nie unter „Ohne Thema“. `anchorRevision`: Stand von `anchors` (`MapAnchors.revision`).
    static func makeRequest(model: ThoughtsModel, anchors: [String: MapAnchor], anchorRevision: Int = 0) -> MapRequest {
        let visible = model.thoughts.filter { !$0.isInMapInbox }
        var topicOf: [String: String] = [:]
        var counts: [String: Int] = [:]
        var last: [String: Date] = [:]
        var items: [MapLayoutInput.Thought] = []
        items.reserveCapacity(visible.count)
        topicOf.reserveCapacity(visible.count)
        for thought in visible {
            let topic = model.topic(thought.topicId)?.id ?? ThoughtMapView.noTopicID
            topicOf[thought.id] = topic
            counts[topic, default: 0] += 1
            last[topic] = max(last[topic] ?? .distantPast, thought.createdAt)
            items.append(MapLayoutInput.Thought(id: thought.id, topicID: topic, createdAt: thought.createdAt))
        }
        let few = visible.count <= fewLimit
        var topics: [MapLayoutInput.Topic] = model.topics.map { topic in
            let n = counts[topic.id] ?? 0
            return MapLayoutInput.Topic(id: topic.id, count: n, lastActivity: last[topic.id] ?? topic.createdAt,
                                        titleLines: few ? n : 0, pinned: topic.owner == .user)
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
        return MapRequest(input: MapLayoutInput(topics: topics, thoughts: items, links: links, anchors: anchors),
                          total: visible.count, anchorRevision: anchorRevision)
    }

    // MARK: Rechnen

    /// Neue Eingabe: im Hintergrund rechnen. Eine laufende, ältere Rechnung wird verworfen; bis zum Ergebnis
    /// bleibt die letzte Karte stehen. `persist`: Anker danach merken (nur mit geladenem Modell). Neu gelesene
    /// Anker (`anchorRevision`) entwerten jede laufende Rechnung, auch wenn die Eingabe sonst gleich ist.
    func request(_ request: MapRequest, persist: Bool) {
        guard request != requested else { return }
        requested = request
        task?.cancel()
        generation &+= 1
        let input = request.input
        if input == settled { return } // nur die eigenen Anker kamen zurück: gleiche Karte
        let ticket = generation, revision = request.anchorRevision
        task = Task { [weak self] in
            let layout = await Task.detached(priority: .userInitiated) { MapLayout.compute(input) }.value
            guard let self, !Task.isCancelled, ticket == self.generation else { return }
            self.apply(layout, for: input, anchorRevision: revision, persist: persist)
        }
    }

    private func apply(_ layout: MapLayout, for input: MapLayoutInput, anchorRevision: Int, persist: Bool) {
        if layout != self.layout {
            version += 1
            self.layout = layout
        }
        var settled = input
        settled.anchors = layout.anchors
        self.settled = settled
        let collected = Set(layout.collected)
        var placed: [String: String] = [:]
        placed.reserveCapacity(input.thoughts.count)
        for thought in input.thoughts {
            placed[thought.id] = collected.contains(thought.topicID) ? MapLayout.moreID : thought.topicID
        }
        self.placed = placed
        Self.last = (layout, version, settled, placed)
        // erst mit geladenem Modell – sonst sähen alle Themen gelöscht aus; gerechnet mit einem älteren Stand der
        // Anker (vor dem Nachladen) merkt `MapAnchors` nichts
        if persist { MapAnchors.shared.remember(layout.anchors, revision: anchorRevision) }
    }

    // MARK: Anzeige

    /// Szene aus der letzten Anordnung und dem aktuellen Modell (billig: nur gezeichnete Kreise und Punkte)
    func scene(model: ThoughtsModel, total: Int, now: Date) -> MapScene? {
        guard let layout else { return nil }
        let collected = Set(layout.collected)
        var open: [String: Int] = [:]
        for thought in model.thoughts where !thought.isInMapInbox && thought.openTaskCount > 0 {
            let topic = model.topic(thought.topicId)?.id ?? ThoughtMapView.noTopicID
            let key = collected.contains(topic) ? ThoughtMapView.moreID : topic
            open[key, default: 0] += thought.openTaskCount
        }
        var topicInfo: [String: MapTopicInfo] = [:]
        for bubble in layout.bubbles {
            switch bubble.id {
            case ThoughtMapView.noTopicID:
                topicInfo[bubble.id] = MapTopicInfo(title: "Ohne Thema", icon: .circleDashed, count: bubble.count,
                                                    open: open[bubble.id] ?? 0, kind: .none)
            case ThoughtMapView.moreID:
                topicInfo[bubble.id] = MapTopicInfo(title: "Weitere Themen", icon: .list, count: bubble.count,
                                                    open: open[bubble.id] ?? 0, kind: .more)
            default:
                if let topic = model.topic(bubble.id) {
                    topicInfo[bubble.id] = MapTopicInfo(title: topic.title, icon: topic.icon.lucide, count: bubble.count,
                                                        open: open[bubble.id] ?? 0, image: TopicImages.shared.image(for: topic.id))
                }
            }
        }
        var dotInfo: [String: MapDotInfo] = [:]
        for dot in layout.dots {
            guard let thought = model.thought(dot.id) else { continue }
            dotInfo[dot.id] = MapDotInfo(title: thought.displayTitle, date: thought.createdAt, hasOpenTask: thought.openTaskCount > 0,
                                         isRecent: now.timeIntervalSince(thought.createdAt) < 86_400)
        }
        return MapScene(layout: layout, topics: topicInfo, dots: dotInfo, total: total, few: total <= Self.fewLimit,
                        version: version)
    }
}

// MARK: - Sammelkreis fürs Panel

extension ThoughtsModel {
    /// Themen, die auf der Karte keinen eigenen Kreis haben, sondern im Sammelkreis „Weitere Themen“
    /// (`ThoughtMapView.moreID`) stecken – dieselbe Regel wie die Karte (`MapLayout.collected`).
    func mapCollectedTopicIDs() -> Set<String> {
        MapLayout.collected(MapEngine.makeRequest(model: self, anchors: [:]).input.topics)
    }

    /// Gedanken des Sammelkreises in der Reihenfolge des Modells (für das Panel zu `ThoughtMapView.moreID`)
    func mapCollectedThoughts() -> [Thought] {
        let ids = mapCollectedTopicIDs()
        guard !ids.isEmpty else { return [] }
        return thoughts.filter { thought in !thought.isInMapInbox && (topic(thought.topicId).map { ids.contains($0.id) } ?? false) }
    }
}

/// Übergänge zwischen zwei Ständen der Karte (zeitgesteuert, damit das erste Bild nie springt), das Einblenden neuer
/// Punkte und Kreise und die Flüge aus dem Eingang (`MapLandings`). Wird im `body` fortgeschrieben – reine
/// Buchführung, löst nichts aus. Wann wieder etwas zu tun ist, sagt `nextWake` (die Karte plant bei jeder neuen
/// Frist neu).
@MainActor
final class MapMotion {
    /// Feder für Datenwechsel (kritisch gedämpft, ≈ 0,6 s)
    static let settle: TimeInterval = 0.65
    nonisolated static let appearDuration: TimeInterval = 1.1
    /// mehr neue Punkte auf einmal: kein Einblenden (nichts Teures)
    static let appearLimit = 6
    /// Ein neuer Kreis beginnt so lange vor der Landung seines ersten Punkts aus dem Nichts zu wachsen
    static let growLead: TimeInterval = 0.3
    /// so lange glüht ein gelandeter Punkt am Ziel nach (liegt im Nachleuchten von `MapLandings`)
    nonisolated static let afterglow: TimeInterval = 0.24

    struct Flight {
        var id: String
        var topicID: String
        /// 0 … 1
        var progress: CGFloat
    }

    private(set) var current: MapScene?
    private(set) var previous: MapScene?
    private(set) var start = Date.distantPast
    private(set) var appear: [String: Date] = [:]
    private(set) var landings = MapLandings()
    private var knownDots: Set<String> = []
    private var knownTopics: Set<String> = []

    /// Neuen Stand übernehmen. `inbox`: Gedanken im Eingang (`ids`) und alle, die es gibt (`existing`). `flights`:
    /// Flüge erlaubt (Kugel sichtbar, Bewegung an). `bubbleOf`: Kreis eines Gedankens in `scene` (nil = noch nicht
    /// auf der Karte).
    func update(_ scene: MapScene, inbox: MapInbox, flights: Bool, bubbleOf: (String) -> String?, now: Date) {
        landings.observe(pending: inbox.ids, existing: inbox.existing, now: now)
        var born: Set<String> = []
        if let current, current.version != scene.version {
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
            born = newTopics
            knownDots = dots
            knownTopics = topics
        } else if current == nil {
            knownDots = Set(scene.layout.dots.map(\.id))
            knownTopics = Set(scene.layout.bubbles.map(\.id))
        }
        current = scene

        // Fertige Gedanken, die jetzt auf der Karte stehen: Flug von der Kugel. Ihr Punkt erscheint erst mit der
        // Landung; ein neuer Kreis wächst, während sein erster Punkt anfliegt.
        guard !landings.awaiting.isEmpty else { return }
        let added = landings.place(animate: flights, now: now) { id in
            guard let bubble = bubbleOf(id), scene.layout.bubble(bubble) != nil else { return nil }
            return bubble
        }
        guard !added.isEmpty else { return }
        for flight in added {
            appear[flight.id] = flight.land
            guard born.contains(flight.topicID) else { continue }
            let key = "topic:" + flight.topicID
            let grow = flight.land.addingTimeInterval(-Self.growLead)
            if let begin = appear[key], begin > now, begin <= grow { continue } // schon für einen früheren Punkt
            appear[key] = grow
        }
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
        if appear.values.contains(where: { now.timeIntervalSince($0) < Self.appearDuration }) { return true }
        return landings.isRunning(at: now)
    }

    /// Fortschritt des Einblendens (nil = kein Einblenden; 0, solange es noch nicht begonnen hat)
    func appearance(_ key: String, at now: Date) -> CGFloat? {
        guard let begin = appear[key] else { return nil }
        let t = now.timeIntervalSince(begin) / Self.appearDuration
        return t < 1 ? CGFloat(max(0, t)) : nil
    }

    /// Nächster Zeitpunkt, an dem sich etwas ändert (Ende eines Übergangs, Abflug, Landung, Ende des Nachleuchtens);
    /// nil = Ruhe
    func nextWake(after now: Date) -> Date? {
        var best: Date?
        func consider(_ t: Date) {
            guard t > now else { return }
            if best.map({ t < $0 }) ?? true { best = t }
        }
        if previous != nil { consider(start.addingTimeInterval(Self.settle)) }
        for begin in appear.values { consider(begin.addingTimeInterval(Self.appearDuration)) }
        if let t = landings.nextEvent(after: now) { consider(t) }
        return best
    }

    // MARK: Eingang und Flüge

    /// Zahl an der Kugel
    func inboxCount(at now: Date) -> Int { landings.count(at: now) }

    /// schon abgeflogene Punkte (die Kugel stößt bei jedem kurz nach)
    func launched(at now: Date) -> Int { landings.launched(at: now) }

    /// Punkte in der Luft – und kurz nach der Landung (Fortschritt über 1: Nachglühen am Ziel)
    func flights(at now: Date) -> [Flight] {
        landings.flights.compactMap { flight in
            let t = now.timeIntervalSince(flight.launch)
            guard t >= 0, t < flight.duration + Self.afterglow else { return nil }
            return Flight(id: flight.id, topicID: flight.topicID, progress: CGFloat(t / flight.duration))
        }
    }

    /// Noch nicht gelandet (geplant oder in der Luft): Punkt verborgen, der Kreis zählt ihn noch nicht
    func unlanded(at now: Date) -> (ids: Set<String>, perTopic: [String: Int]) {
        var ids = Set<String>()
        var perTopic: [String: Int] = [:]
        for flight in landings.unlanded(at: now) {
            ids.insert(flight.id)
            perTopic[flight.topicID, default: 0] += 1
        }
        return (ids, perTopic)
    }

    /// Nachleuchten der Kreise nach einer Landung (0 … 1, frischeste zählt)
    func glows(at now: Date) -> [String: CGFloat] {
        var result: [String: CGFloat] = [:]
        for flight in landings.flights {
            let t = now.timeIntervalSince(flight.land)
            guard t >= 0, t < MapLandings.glow else { continue }
            result[flight.topicID] = min(result[flight.topicID] ?? 1, CGFloat(t / MapLandings.glow))
        }
        return result
    }
}
