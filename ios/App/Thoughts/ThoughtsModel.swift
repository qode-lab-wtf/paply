// GERÜST (G0.1, Koordinator). Besitzer: H2. Öffentliche Signatur aus KONZEPT.md §9.2 – bitte stabil
// lassen, H4 baut dagegen. Die Logik hier ist ein einfacher Speicher im RAM (für `preview` und
// solange der ThoughtStore noch nicht angebunden ist); H2 ersetzt sie durch Store + Prozessor.
import Foundation
import Observation
import PaplyKit

@MainActor
@Observable
final class ThoughtsModel {
    static let shared = ThoughtsModel()

    /// 60 Beispiel-Gedanken, 8 Themen, alle Zustände (für SwiftUI-Previews und den Oberflächenbau).
    static var preview: ThoughtsModel { ThoughtsPreviewData.make() }

    /// ohne gelöschte, neueste zuerst
    private(set) var thoughts: [Thought] = []
    private(set) var deleted: [Thought] = []
    /// aufgelöst, ohne zusammengeführte
    private(set) var topics: [Topic] = []
    private(set) var suggestions: [TopicSuggestion] = []

    @ObservationIgnored private var sources: [String: ThoughtSource] = [:]
    @ObservationIgnored private var undoStack: [UndoToken: Snapshot] = [:]

    private struct Snapshot {
        var thoughts: [Thought]
        var deleted: [Thought]
        var topics: [Topic]
    }

    init() {}

    init(thoughts: [Thought], topics: [Topic], sources: [String: ThoughtSource] = [:], suggestions: [TopicSuggestion] = []) {
        self.thoughts = thoughts.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt }
        self.deleted = thoughts.filter { $0.deletedAt != nil }
        self.topics = topics.filter { $0.mergedInto == nil }
        self.sources = sources
        self.suggestions = suggestions
    }

    // MARK: Lesen

    func topic(_ id: String?) -> Topic? {
        guard let id else { return nil }
        return topics.first { $0.id == id }
    }

    /// aktiv = ≥ 2 Gedanken oder vom Nutzer angelegt (§7.3)
    func isActive(_ topic: Topic) -> Bool {
        topic.owner == .user || count(of: topic.id) >= 2
    }

    func count(of topicID: String) -> Int {
        thoughts.reduce(0) { $0 + ($1.topicId == topicID ? 1 : 0) }
    }

    func openTasks(topicID: String?) -> [(task: ThoughtTask, thought: Thought)] {
        thoughts
            .filter { topicID == nil || $0.topicId == topicID }
            .flatMap { thought in thought.tasks.filter { !$0.done }.map { (task: $0, thought: thought) } }
            .sorted { a, b in
                switch (a.task.dueAt, b.task.dueAt) {
                case let (x?, y?): x < y
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): a.thought.createdAt > b.thought.createdAt
                }
            }
    }

    func doneTasks(days: Int) -> [(task: ThoughtTask, thought: Thought)] {
        let limit = Date().addingTimeInterval(-Double(days) * 86_400)
        return thoughts
            .flatMap { thought in thought.tasks.filter { $0.done && ($0.doneAt ?? .distantPast) >= limit }.map { (task: $0, thought: thought) } }
            .sorted { ($0.task.doneAt ?? .distantPast) > ($1.task.doneAt ?? .distantPast) }
    }

    /// Einfache Suche (Wortanfänge, UND, ohne Groß/Klein und Akzente). H2 ersetzt durch den Index.
    func search(_ query: String) -> [SearchHit] {
        let words = query.split(separator: " ").map { Self.fold(String($0)) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        return thoughts.compactMap { thought in
            let title = thought.title ?? ""
            let text = thought.text ?? ""
            let topicName = topic(thought.topicId)?.title ?? ""
            let haystack = Self.fold([title, text, topicName, thought.tasks.map(\.text).joined(separator: " ")].joined(separator: " "))
            guard words.allSatisfy({ haystack.contains($0) }) else { return nil }
            let inTitle = words.contains { Self.fold(title).contains($0) }
            return SearchHit(thoughtID: thought.id, field: inTitle ? .title : .text, snippet: String((inTitle ? title : text).prefix(120)), score: inTitle ? 2 : 1)
        }
        .sorted { $0.score > $1.score }
    }

    func source(_ id: String) -> ThoughtSource? { sources[id] }

    func audioURL(_ id: String) -> URL? { nil }

    func linked(_ id: String) -> [(thought: Thought, link: ThoughtLink, incoming: Bool)] {
        var result: [(thought: Thought, link: ThoughtLink, incoming: Bool)] = []
        if let thought = thoughts.first(where: { $0.id == id }) {
            for link in thought.links {
                if let other = thoughts.first(where: { $0.id == link.target }) { result.append((other, link, false)) }
            }
        }
        for other in thoughts where other.id != id {
            for link in other.links where link.target == id { result.append((other, link, true)) }
        }
        return result
    }

    // MARK: Ändern (setzt owner = user)

    func setTitle(_ id: String, _ value: String) { update(id) { $0.title = value; $0.titleOwner = .user } }
    func setText(_ id: String, _ value: String) { update(id) { $0.text = value; $0.textOwner = .user; $0.textIsRaw = false } }
    func setTopic(_ id: String, topicID: String?) { update(id) { $0.topicId = topicID; $0.topicOwner = .user } }

    func createTopic(title: String, icon: TopicIcon) -> Topic {
        let topic = Topic(title: title, icon: icon, owner: .user)
        topics.append(topic)
        return topic
    }

    func renameTopic(_ id: String, title: String) {
        guard let i = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[i].title = title
        topics[i].owner = .user
    }

    func setTopicIcon(_ id: String, _ icon: TopicIcon) {
        guard let i = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[i].icon = icon
        topics[i].owner = .user
    }

    func mergeTopics(_ ids: [String], into target: String, title: String?) -> UndoToken {
        let token = remember()
        for i in thoughts.indices where ids.contains(thoughts[i].topicId ?? "") && thoughts[i].topicId != target {
            thoughts[i].topicId = target
            bump(&thoughts[i])
        }
        topics.removeAll { ids.contains($0.id) && $0.id != target }
        if let title, let i = topics.firstIndex(where: { $0.id == target }) { topics[i].title = title }
        suggestions.removeAll { ids.contains($0.a) || ids.contains($0.b) }
        return token
    }

    func deleteTopic(_ id: String) {
        for i in thoughts.indices where thoughts[i].topicId == id {
            thoughts[i].topicId = nil
            bump(&thoughts[i])
        }
        topics.removeAll { $0.id == id }
    }

    func keepProvisional(_ id: String) {
        guard let i = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[i].owner = .user
    }

    func toggleTask(_ thoughtID: String, _ taskID: String) {
        update(thoughtID) { thought in
            guard let k = thought.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            thought.tasks[k].done.toggle()
            thought.tasks[k].doneAt = thought.tasks[k].done ? Date() : nil
        }
    }

    func addTask(_ thoughtID: String, text: String) {
        update(thoughtID) { $0.tasks.append(ThoughtTask(text: text, owner: .user)) }
    }

    func editTask(_ thoughtID: String, _ taskID: String, text: String) {
        update(thoughtID) { thought in
            guard let k = thought.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            thought.tasks[k].text = text
            thought.tasks[k].owner = .user
        }
    }

    func deleteTask(_ thoughtID: String, _ taskID: String) {
        update(thoughtID) { $0.tasks.removeAll { $0.id == taskID } }
    }

    func addLink(_ id: String, to target: String) {
        update(id) { $0.links.append(ThoughtLink(target: target, kind: .sameMatter, reason: "", origin: .user)) }
    }

    func removeLink(_ id: String, target: String) {
        update(id) { $0.links.removeAll { $0.target == target } }
        update(target) { $0.links.removeAll { $0.target == id } }
    }

    func delete(_ id: String) -> UndoToken {
        let token = remember()
        if let i = thoughts.firstIndex(where: { $0.id == id }) {
            var thought = thoughts.remove(at: i)
            thought.deletedAt = Date()
            deleted.insert(thought, at: 0)
        }
        return token
    }

    func restore(_ id: String) {
        guard let i = deleted.firstIndex(where: { $0.id == id }) else { return }
        var thought = deleted.remove(at: i)
        thought.deletedAt = nil
        thoughts.append(thought)
        thoughts.sort { $0.createdAt > $1.createdAt }
    }

    func purge(_ id: String) { deleted.removeAll { $0.id == id } }
    func purgeAllDeleted() { deleted.removeAll() }

    func reorganize(_ id: String) { update(id) { $0.state = .structuring } }

    func accept(_ s: TopicSuggestion) { _ = mergeTopics([s.a, s.b], into: s.a, title: s.name) }
    func decline(_ s: TopicSuggestion) { suggestions.removeAll { $0 == s } }

    func undo(_ token: UndoToken) {
        guard let snapshot = undoStack.removeValue(forKey: token) else { return }
        thoughts = snapshot.thoughts
        deleted = snapshot.deleted
        topics = snapshot.topics
    }

    // MARK: Hilfen

    private func update(_ id: String, _ change: (inout Thought) -> Void) {
        guard let i = thoughts.firstIndex(where: { $0.id == id }) else { return }
        change(&thoughts[i])
        bump(&thoughts[i])
    }

    private func bump(_ thought: inout Thought) {
        thought.rev += 1
        thought.updatedAt = Date()
    }

    private func remember() -> UndoToken {
        let token = UndoToken()
        undoStack[token] = Snapshot(thoughts: thoughts, deleted: deleted, topics: topics)
        return token
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

/// Beispieldaten ohne echte Personendaten.
@MainActor
private enum ThoughtsPreviewData {
    static func make() -> ThoughtsModel {
        let topics: [Topic] = [
            Topic(title: "Paply", icon: .code, owner: .ai),
            Topic(title: "Wohnung", icon: .home, owner: .ai),
            Topic(title: "Urlaub Portugal", icon: .plane, owner: .ai),
            Topic(title: "Garten", icon: .leaf, owner: .user),
            Topic(title: "Finanzen", icon: .wallet, owner: .ai),
            Topic(title: "Lesen", icon: .book, owner: .ai),
            Topic(title: "Team", icon: .users, owner: .ai),
            Topic(title: "Ideen", icon: .lightbulb, owner: .ai),
        ]
        let provisional = Topic(title: "Fotografie", icon: .camera, owner: .ai)
        let samples: [(String, String)] = [
            ("Gedanken-Knopf statt Taschenlampe", "Statt der Taschenlampe soll unten links der Paply-Knopf sitzen. Ein Druck nimmt auf, nochmal drücken beendet."),
            ("Mietvertrag prüfen", "Bevor ich unterschreibe, die Klausel zur Staffelmiete nochmal genau lesen und den Vermieter fragen."),
            ("Porto statt Lissabon", "Wir fliegen doch nach Porto, weil die Flüge dort günstiger sind. Hotel in der Altstadt suchen."),
            ("Tomaten ausgeizen", "Am Wochenende die Tomaten ausgeizen und die Beete gießen, sonst wird es zu trocken."),
            ("Sparplan anpassen", "Den monatlichen Sparplan ab nächstem Monat um fünfzig Euro erhöhen."),
            ("Buchidee aus dem Podcast", "Das Buch über Gewohnheiten aus dem Podcast vormerken und in der Bibliothek schauen."),
            ("Retro am Freitag", "In der Retro ansprechen, dass die Reviews zu lange liegen bleiben."),
            ("App für Einkaufslisten", "Idee: Einkaufsliste, die sich nach dem Laden sortiert, in dem ich gerade bin."),
        ]
        let states: [ThoughtState] = [.captured, .transcribing, .structuring, .waitingNetwork, .waitingKey,
                                      .waitingLimit, .waitingBudget, .needsAttention]
        var thoughts: [Thought] = []
        var sources: [String: ThoughtSource] = [:]
        let now = Date()
        for i in 0..<60 {
            let sample = samples[i % samples.count]
            let topic = topics[i % topics.count]
            let created = now.addingTimeInterval(-Double(i) * 36_000 - Double(i % 5) * 1_800)
            var thought = Thought(
                createdAt: created,
                durationMs: 8_000 + (i * 7_919) % 90_000,
                trigger: [.control, .shortcut, .app][i % 3],
                state: .done,
                title: i == 0 ? sample.0 : "\(sample.0) \(i / samples.count + 1)",
                titleOwner: .ai,
                text: sample.1,
                textOwner: .ai,
                topicId: topic.id,
                topicOwner: .ai,
                languages: ["de"],
                ai: Thought.AIInfo(model: "openai/gpt-oss-120b", promptVersion: 1, tokens: 3_000 + i * 11, at: created),
                audio: Thought.AudioInfo(file: "audio.m4a", deleteAfter: created.addingTimeInterval(30 * 86_400)),
                updatedAt: created
            )
            if i % 4 == 0 {
                thought.tasks = [ThoughtTask(text: "Nächsten Schritt erledigen", quote: "das muss ich noch machen",
                                             dueHint: i % 8 == 0 ? "morgen" : nil, dueAt: i % 8 == 0 ? created.addingTimeInterval(86_400) : nil,
                                             done: i % 12 == 0, doneAt: i % 12 == 0 ? created.addingTimeInterval(3_600) : nil, owner: .ai, createdAt: created)]
            }
            if i > 0, i % 6 == 0 {
                thought.links = [ThoughtLink(target: thoughts[i - 1].id, kind: [.continues, .sameMatter, .changes][i % 3],
                                             reason: "Gleiches Anliegen", origin: .ai, createdAt: created)]
            }
            if i < states.count {
                // die neuesten zeigen die Zwischen- und Wartezustände
                thought.state = states[i]
                thought.title = nil
                thought.text = nil
                thought.titleOwner = .system
                thought.textOwner = .system
                thought.topicId = nil
                thought.tasks = []
                thought.ai = nil
                thought.status = Thought.Status(message: statusMessage(states[i]), attempts: states[i] == .needsAttention ? 5 : 1)
            } else if i == states.count {
                thought.textIsRaw = true // „nicht geordnet“
                thought.topicId = nil
            } else if i == states.count + 1 {
                thought.topicId = provisional.id // vorläufiges Thema (1 Gedanke)
            }
            if i == 59 { thought.deletedAt = now.addingTimeInterval(-86_400) }
            thoughts.append(thought)
            sources[thought.id] = ThoughtSource(
                text: "Ähm, also \(sample.1.lowercased())",
                sentences: [ThoughtSource.Sentence(id: "\(thought.id)_s0", text: sample.1)],
                model: "whisper-large-v3", createdAt: created, languages: ["de"], audioSeconds: Double(thought.durationMs) / 1000
            )
        }
        let suggestions = [TopicSuggestion(a: topics[1].id, b: topics[4].id, name: nil, reason: "Beide drehen sich um Miete und Kosten")]
        return ThoughtsModel(thoughts: thoughts, topics: topics + [provisional], sources: sources, suggestions: suggestions)
    }

    private static func statusMessage(_ state: ThoughtState) -> String? {
        switch state {
        case .waitingNetwork: "Gesichert · wartet auf Netz"
        case .waitingKey: "Gesichert · Groq-Schlüssel fehlt"
        case .waitingLimit: "Gesichert · Groq-Limit, ab ca. 14:30"
        case .waitingBudget: "Gesichert · Kontingent für heute erreicht"
        case .needsAttention: "Ton gesichert · nicht verschriftlicht"
        default: nil
        }
    }
}
