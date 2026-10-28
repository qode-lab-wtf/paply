// Besitzer: H2. Öffentliche Signatur aus KONZEPT.md §9.2 – bitte stabil lassen, H4 baut dagegen.
//
// Zwei Betriebsarten:
// - angebunden (`shared`): ThoughtStore + ThoughtProcessor (ThoughtsEnvironment). Änderungen der Oberfläche
//   wirken sofort im RAM und werden der Reihe nach atomar im Speicher-Akteur geschrieben (`store.update`).
//   Was die Warteschlange schreibt, kommt über `store.changes` herein.
// - nur RAM (`preview`, `ThoughtsModel()`, `init(thoughts:topics:…)`): gleiche Logik ohne Speicher.
import Foundation
import Observation
import PaplyKit

/// Speicher, Warteschlange und Ledger für das angebundene Modell.
struct ThoughtsBackend {
    let store: ThoughtStore
    let processor: ThoughtProcessor
    let ledger: TokenLedger
    let dailyTokens: @Sendable () -> Int
}

@MainActor
@Observable
final class ThoughtsModel {
    static let shared = ThoughtsModel(backend: ThoughtsEnvironment.backend)

    /// 60 Beispiel-Gedanken, aktive, vorläufige und leere eigene Themen, alle Zustände (für Vorschauen).
    static var preview: ThoughtsModel { ThoughtsPreviewData.make() }

    /// ohne gelöschte, neueste zuerst
    private(set) var thoughts: [Thought] = []
    /// zuletzt gelöscht zuerst
    private(set) var deleted: [Thought] = []
    /// aufgelöst, ohne zusammengeführte; nach letzter Aktivität
    private(set) var topics: [Topic] = []
    private(set) var suggestions: [TopicSuggestion] = []
    /// Verbrauch der letzten 24 h (Entwicklerbereich); nil = unbekannt
    private(set) var usage: ThoughtsUsage?
    /// „Themenpflege jetzt prüfen“ läuft
    private(set) var isCheckingTopics = false
    /// Ergebnis der letzten Prüfung, kurz („2 Vorschläge“, „Keine ähnlichen Themen“, „Groq-Schlüssel fehlt“)
    private(set) var topicCheckResult: String?
    /// Speicher gelesen (angebunden) bzw. sofort true (RAM)
    private(set) var isLoaded = false
    /// geladene `source.json` (Detail „Original“, Suche im Rohtext)
    private var sources: [String: ThoughtSource] = [:]

    @ObservationIgnored private let backend: ThoughtsBackend?
    @ObservationIgnored private var byID: [String: Thought] = [:]
    @ObservationIgnored private var allTopics: [Topic] = []
    @ObservationIgnored private var topicByID: [String: Topic] = [:]
    @ObservationIgnored private var counts: [String: Int] = [:]
    @ObservationIgnored private var incoming: [String: [(id: String, link: ThoughtLink)]] = [:]
    @ObservationIgnored private var searchIndex = ThoughtSearchIndex()
    @ObservationIgnored private var undoActions: [UndoToken: () -> Void] = [:]
    @ObservationIgnored private var pendingWrites: [String: Int] = [:]
    @ObservationIgnored private var writeChain: Task<Void, Never>?
    @ObservationIgnored private var changedWhileLoading: Set<String> = []
    @ObservationIgnored private var requestedSources: Set<String> = []
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []

    /// leer, nur RAM (`-PaplyEmpty`)
    init() {
        backend = nil
        isLoaded = true
    }

    /// nur RAM (Vorschau, `-PaplyMany`)
    init(thoughts: [Thought], topics: [Topic], sources: [String: ThoughtSource] = [:], suggestions: [TopicSuggestion] = []) {
        backend = nil
        self.sources = sources
        self.suggestions = suggestions
        replaceAll(thoughts, topics: topics)
        rebuildSearchIndex()
        isLoaded = true
    }

    /// angebunden an Speicher und Warteschlange
    init(backend: ThoughtsBackend) {
        self.backend = backend
        listeners.append(Task { [weak self] in
            for await id in backend.store.changes {
                await self?.refresh(id)
            }
        })
        listeners.append(Task { [weak self] in
            for await event in backend.processor.events {
                if case .saved = event { self?.refreshUsage() }
            }
        })
        // Themenbilder werden nur auf dieses Ereignis endgültig gelöscht: Thema gespeichert entfernt
        listeners.append(Task { [weak self] in
            for await ids in backend.store.removedTopics {
                guard let self else { return }
                TopicImages.shared.topicsRemoved(ids, from: self)
            }
        })
        // Vor dem ersten Entsperren nach einem Neustart wäre alles leer: erst danach laden
        ProtectedData.whenReadable { [weak self] deferred in
            self?.listeners.append(Task { [weak self] in
                if deferred { await backend.store.reloadIfNeeded() }
                await self?.load()
            })
        }
    }

    // MARK: Lesen

    func thought(_ id: String) -> Thought? {
        track()
        return byID[id]
    }

    func topic(_ id: String?) -> Topic? {
        track()
        return resolvedTopic(id)
    }

    /// aktiv = ≥ 2 Gedanken oder vom Nutzer angelegt (§7.3)
    func isActive(_ topic: Topic) -> Bool {
        topic.owner == .user || count(of: topic.id) >= 2
    }

    /// Eigene Themen sofort als Chip und Such-Schnellweg; KI-Themen erst ab zwei Gedanken.
    func showsAsChip(_ topic: Topic) -> Bool {
        topic.owner == .user || (isActive(topic) && count(of: topic.id) > 0)
    }

    /// Gleicher Name nach Trimmen, ohne Groß/Klein und Akzente; keine unscharfe Themenpflege.
    func existingTopic(named name: String) -> Topic? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return topics.first {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func count(of topicID: String) -> Int {
        track()
        return counts[topicID] ?? 0
    }

    func openTasks(topicID: String?) -> [(task: ThoughtTask, thought: Thought)] {
        thoughts
            .filter { topicID == nil || resolvedTopic($0.topicId)?.id == topicID }
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

    /// Erledigte der letzten `days` Tage (nil = alle), neueste zuerst
    func doneTasks(days: Int?) -> [(task: ThoughtTask, thought: Thought)] {
        let limit = days.map { Date().addingTimeInterval(-Double($0) * 86_400) } ?? .distantPast
        return thoughts
            .flatMap { thought in thought.tasks.filter { $0.done && ($0.doneAt ?? .distantPast) >= limit }.map { (task: $0, thought: thought) } }
            .sorted { ($0.task.doneAt ?? .distantPast) > ($1.task.doneAt ?? .distantPast) }
    }

    /// Reiter „Aufgaben“: alle Aufgaben, gegliedert nach Fälligkeit (`TaskAgenda`, ohne Obergrenze)
    func taskAgenda(now: Date = Date()) -> TaskAgenda {
        TaskAgenda(thoughts: thoughts, now: now)
    }

    /// Lokal, sofort: ohne Groß/Klein und Akzente, UND, Wortanfänge; Ausschnitt mit Fundstellen.
    func search(_ query: String) -> [SearchHit] {
        track()
        return searchIndex.search(query).filter { byID[$0.thoughtID]?.deletedAt == nil }
    }

    func source(_ id: String) -> ThoughtSource? {
        if let source = sources[id] { return source }
        if let store = backend?.store, !requestedSources.contains(id) {
            requestedSources.insert(id)
            Task { [weak self] in
                guard let source = await store.source(id) else { return }
                self?.sources[id] = source
            }
        }
        return nil
    }

    func linked(_ id: String) -> [(thought: Thought, link: ThoughtLink, incoming: Bool)] {
        track()
        var result: [(thought: Thought, link: ThoughtLink, incoming: Bool)] = []
        if let thought = byID[id] {
            for link in thought.links {
                if let other = byID[link.target], other.deletedAt == nil { result.append((other, link, false)) }
            }
        }
        for (other, link) in incoming[id] ?? [] {
            if let thought = byID[other], thought.deletedAt == nil { result.append((thought, link, true)) }
        }
        return result
    }

    // MARK: Ändern (setzt owner = user)

    func setTitle(_ id: String, _ value: String) {
        change(id) { $0.title = value; $0.titleOwner = .user }
    }

    func setText(_ id: String, _ value: String) {
        change(id) { $0.text = value; $0.textOwner = .user; $0.textIsRaw = false }
    }

    func setTopic(_ id: String, topicID: String?) {
        change(id) { $0.topicId = topicID; $0.topicOwner = .user }
    }

    func createTopic(title: String, icon: TopicIcon) -> Topic {
        let topic = Topic(title: title.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon, owner: .user)
        changeTopics { $0.append(topic) }
        return topic
    }

    func renameTopic(_ id: String, title: String) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        changeTopics { topics in
            if let i = topics.firstIndex(where: { $0.id == id }) { topics[i].title = value }
        }
    }

    func setTopicIcon(_ id: String, _ icon: TopicIcon) {
        changeTopics { topics in
            if let i = topics.firstIndex(where: { $0.id == id }) { topics[i].icon = icon }
        }
    }

    /// Thema mit Beschreibung („Worum geht's?“) anlegen; Paply ordnet Gedanken danach zu (KONZEPT §6.3).
    func createTopic(title: String, icon: TopicIcon, note: String?) -> Topic {
        let topic = Topic(title: title.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon, owner: .user,
                          note: Topic.normalizedNote(note))
        changeTopics { $0.append(topic) }
        return topic
    }

    /// Beschreibung setzen oder entfernen (nil/leer). Wer ein Thema beschreibt, behält es: owner = user wie „Behalten“.
    func setTopicNote(_ id: String, _ note: String?) {
        let value = Topic.normalizedNote(note)
        changeTopics { topics in
            guard let i = topics.firstIndex(where: { $0.id == id }) else { return }
            topics[i].note = value
            if value != nil { topics[i].owner = .user }
        }
    }

    /// Ziel behält seine ID, die Quellen werden Alias (`mergedInto`), Gedanken wandern zum Ziel (§6.10).
    func mergeTopics(_ ids: [String], into target: String, title: String?) -> UndoToken {
        let token = UndoToken()
        let merged = ids.filter { $0 != target }
        let oldTitle = topicByID[target]?.title
        let moved = byID.values.compactMap { thought -> (id: String, topic: String)? in
            guard let topic = thought.topicId, let resolved = resolvedTopic(topic)?.id, merged.contains(resolved) else { return nil }
            return (thought.id, topic)
        }
        let newTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        changeTopics { topics in
            for i in topics.indices where merged.contains(topics[i].id) { topics[i].mergedInto = target }
            if let newTitle, !newTitle.isEmpty, let i = topics.firstIndex(where: { $0.id == target }) { topics[i].title = newTitle }
        }
        for item in moved {
            let source = item.topic
            change(item.id) { if $0.topicId == source { $0.topicId = target } }
        }
        let involved = Set(ids + [target])
        setSuggestions(suggestions.filter { !involved.contains($0.a) && !involved.contains($0.b) })
        undoActions[token] = { [weak self] in
            guard let self else { return }
            self.changeTopics { topics in
                for i in topics.indices where merged.contains(topics[i].id) && topics[i].mergedInto == target { topics[i].mergedInto = nil }
                if let oldTitle, let i = topics.firstIndex(where: { $0.id == target }) { topics[i].title = oldTitle }
            }
            for item in moved {
                let original = item.topic
                self.change(item.id) { if $0.topicId == target { $0.topicId = original } }
            }
        }
        return token
    }

    /// „Thema löschen? Gedanken bleiben, nur ohne Thema.“ Aliasse auf das Thema fallen mit weg.
    func deleteTopic(_ id: String) {
        deleteTopics([id], withThoughts: false)
    }

    /// Aliasse mit entfernen; auf Wunsch gezählte Gedanken für 30 Tage nach „Zuletzt gelöscht“ verschieben.
    func deleteTopics(_ ids: Set<String>, withThoughts: Bool) {
        let targets = Set(ids.map { resolvedTopic($0)?.id ?? $0 })
        let removed = Set(allTopics.filter { targets.contains($0.id) || targets.contains(resolvedTopic($0.id)?.id ?? "") }.map(\.id))
        let now = Date()
        for thought in byID.values where removed.contains(thought.topicId ?? "") {
            change(thought.id) {
                guard let topic = $0.topicId, removed.contains(topic) else { return }
                if withThoughts, $0.deletedAt == nil, $0.state != .recording { $0.deletedAt = now }
                $0.topicId = nil
            }
        }
        // Bild: wird nicht mehr angezeigt; die Datei geht erst, wenn der Speicher das Thema gespeichert entfernt hat
        // (`ThoughtStore.removedTopics` → `TopicImages`) – scheitert das Speichern, ist es samt Bild wieder da
        changeTopics { $0.removeAll { removed.contains($0.id) } }
        setSuggestions(suggestions.filter { !removed.contains($0.a) && !removed.contains($0.b) })
    }

    /// Vorläufiges Thema übernehmen („Behalten“ macht es aktiv)
    func keepProvisional(_ id: String) {
        changeTopics { topics in
            if let i = topics.firstIndex(where: { $0.id == id }) { topics[i].owner = .user }
        }
    }

    func toggleTask(_ thoughtID: String, _ taskID: String) {
        let now = Date()
        change(thoughtID) { thought in
            guard let k = thought.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            thought.tasks[k].done.toggle()
            thought.tasks[k].doneAt = thought.tasks[k].done ? now : nil
        }
    }

    /// Sofort erledigt (Mitteilung „Erledigt“), ohne die Wartezeit der Oberfläche. Idempotent: schon erledigt bleibt,
    /// wie es ist. false = Aufgabe nicht (mehr) da. `at`: Zeitpunkt des Tipps (Widget-Warteschlange), sonst jetzt.
    @discardableResult
    func completeTask(_ thoughtID: String, _ taskID: String, at: Date = Date()) -> Bool {
        guard byID[thoughtID]?.tasks.contains(where: { $0.id == taskID }) == true else { return false }
        let now = at
        change(thoughtID) { thought in
            guard let k = thought.tasks.firstIndex(where: { $0.id == taskID }), !thought.tasks[k].done else { return }
            thought.tasks[k].done = true
            thought.tasks[k].doneAt = now
        }
        return true
    }

    /// Wartet, bis alle Änderungen gespeichert sind (Hintergrund-Aktionen, bevor iOS die App wieder anhält).
    func flushWrites() async {
        while let chain = writeChain {
            await chain.value
            if writeChain == chain { return }
        }
    }

    func addTask(_ thoughtID: String, text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let task = ThoughtTask(text: value, owner: .user)
        change(thoughtID) { $0.tasks.append(task) }
    }

    func editTask(_ thoughtID: String, _ taskID: String, text: String) {
        change(thoughtID) { thought in
            guard let k = thought.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            thought.tasks[k].text = text
            thought.tasks[k].owner = .user
        }
    }

    /// Löschen; widerrufbar (kommt an ihre alte Stelle zurück)
    @discardableResult
    func deleteTask(_ thoughtID: String, _ taskID: String) -> UndoToken? {
        guard let index = byID[thoughtID]?.tasks.firstIndex(where: { $0.id == taskID }),
              let removed = byID[thoughtID]?.tasks[index] else { return nil }
        change(thoughtID) { $0.tasks.removeAll { $0.id == taskID } }
        let token = UndoToken()
        undoActions[token] = { [weak self] in
            self?.change(thoughtID) { thought in
                guard !thought.tasks.contains(where: { $0.id == removed.id }) else { return }
                thought.tasks.insert(removed, at: min(index, thought.tasks.count))
            }
        }
        return token
    }

    /// Selbst verknüpfen. Gespeichert wird nur im neueren der beiden Gedanken (§6.9).
    func addLink(_ id: String, to target: String) {
        guard id != target, let a = byID[id], let b = byID[target] else { return }
        guard !a.links.contains(where: { $0.target == target }), !b.links.contains(where: { $0.target == id }) else { return }
        let (owner, other) = a.createdAt >= b.createdAt ? (id, target) : (target, id)
        let link = ThoughtLink(target: other, kind: .sameMatter, reason: "", origin: .user)
        change(owner) { $0.links.append(link) }
    }

    func removeLink(_ id: String, target: String) {
        change(id) { $0.links.removeAll { $0.target == target } }
        change(target) { $0.links.removeAll { $0.target == id } }
    }

    /// In „Zuletzt gelöscht“; widerrufbar
    func delete(_ id: String) -> UndoToken {
        let token = UndoToken()
        let now = Date()
        change(id) { $0.deletedAt = now }
        undoActions[token] = { [weak self] in self?.restore(id) }
        return token
    }

    /// Aus „Zuletzt gelöscht“ zurück. Nicht Geordnetes (z. B. in der Live Activity verworfen) wird danach geordnet.
    func restore(_ id: String) {
        change(id) { $0.deletedAt = nil }
        guard let processor = backend?.processor, byID[id]?.state != .done else { return }
        write(id) { _ in await processor.kick(reason: "restore") } // nach dem Schreiben
    }

    /// Endgültig: Text, Cache, Embedding und ggf. noch nicht verschriftlichter Ton (§7.6). Themen, die danach
    /// keinen Gedanken mehr tragen, entfernt der Speicher mit (kommt über `store.changes` herein).
    func purge(_ id: String) {
        apply(nil, id: id)
        write(id) { await $0.purge(id) }
    }

    func purgeAllDeleted() {
        for thought in deleted { purge(thought.id) }
    }

    /// „Erneut ordnen“ / „Erneut versuchen“: bewusst neue Anfrage
    func reorganize(_ id: String) {
        guard let current = byID[id] else { return }
        var optimistic = current
        optimistic.state = current.state == .done ? .structuring : .captured
        optimistic.status = Thought.Status()
        apply(optimistic, id: id) // die Warteschlange schreibt gleich den echten Stand
        guard let processor = backend?.processor else { return }
        Task { await processor.reorganize(id) }
    }

    func accept(_ s: TopicSuggestion) {
        _ = mergeTopics([s.a, s.b], into: s.a, title: s.name)
        setSuggestions(suggestions.filter { $0 != s })
    }

    func decline(_ s: TopicSuggestion) {
        setSuggestions(suggestions.filter { $0 != s })
        write(ThoughtStore.topicsChangeID) { try await $0.declineMerge(s.a, s.b) }
    }

    func undo(_ token: UndoToken) {
        undoActions.removeValue(forKey: token)?()
    }

    /// Hinweis abgelaufen (oder ersetzt): Widerrufen ist vorbei, die Aktion wird vergessen – sonst wüchse die Liste
    /// mit jeder Löschung
    func forgetUndo(_ token: UndoToken) {
        undoActions[token] = nil
    }

    // MARK: Entwicklerbereich

    /// Verbrauch der letzten 24 h aus dem Ledger neu lesen.
    func refreshUsage() {
        guard let backend else { return }
        Task { [weak self] in
            let summary = await backend.ledger.summary()
            self?.usage = ThoughtsUsage(tokens: summary.tokens, audioSeconds: summary.audioSeconds, requests: summary.requests,
                                        dailyTokens: backend.dailyTokens())
        }
    }

    /// „Themenpflege jetzt prüfen“: ohne 7-Tage-Grenze, ein Aufruf an gpt-oss-20b.
    func checkTopicsNow() {
        runTopicHygiene(force: true)
    }

    // MARK: Laden und Aktualisieren

    private func load() async {
        guard let backend else { return }
        let store = backend.store
        let all = await store.all()
        // Themen und „vollständig gelesen“ aus einem Aufruf: Vor dem ersten Entsperren ist die Liste leer
        let snapshot = await store.topicsSnapshot()
        let pending = await store.pendingSuggestions()
        replaceAll(all, topics: snapshot.topics)
        suggestions = pending
        isLoaded = true
        TopicImages.shared.reconcile(topics: snapshot.topics, complete: snapshot.complete, from: self)
        for id in changedWhileLoading { await refresh(id) }
        changedWhileLoading = []
        refreshUsage()
        // Rohtexte und Suchindex im Hintergrund (≈ 2 000 kleine Dateien)
        let loadedSources = await store.allSources()
        for (id, source) in loadedSources where sources[id] == nil { sources[id] = source }
        rebuildSearchIndex()
        runTopicHygiene(force: false)
    }

    /// Eine Änderung aus dem Speicher übernehmen (Warteschlange, andere Schreiber).
    private func refresh(_ id: String) async {
        guard let store = backend?.store else { return }
        if !isLoaded { changedWhileLoading.insert(id) }
        if id == ThoughtStore.topicsChangeID {
            guard (pendingWrites[id] ?? 0) == 0 else { return }
            let snapshot = await store.topicsSnapshot()
            let pending = await store.pendingSuggestions()
            // inzwischen eine neue Änderung der Oberfläche: Deren Schreiben meldet gleich den neueren Stand
            guard (pendingWrites[id] ?? 0) == 0 else { return }
            suggestions = pending
            setTopics(snapshot.topics, confirmed: true)
            // erst nach dem ersten Entsperren vollständig: dann einmal abgleichen (`TopicImages`)
            TopicImages.shared.reconcile(topics: snapshot.topics, complete: snapshot.complete, from: self)
            return
        }
        guard (pendingWrites[id] ?? 0) == 0 else { return }
        let thought = await store.thought(id)
        guard (pendingWrites[id] ?? 0) == 0 else { return }
        if let thought, sources[id] == nil, thought.state == .done || thought.state == .structuring {
            if let source = await store.source(id) { sources[id] = source }
        }
        apply(thought, id: id)
    }

    // MARK: Schreiben

    /// Sofort im RAM ändern, dann der Reihe nach atomar im Speicher (gleiche Änderung auf dem aktuellen Stand).
    private func change(_ id: String, _ edit: @escaping @Sendable (inout Thought) -> Void) {
        guard var thought = byID[id] else { return }
        let before = thought
        edit(&thought)
        guard thought != before else { return }
        thought.rev += 1
        thought.updatedAt = Date()
        apply(thought, id: id)
        write(id) { _ = try await $0.update(id, edit) }
    }

    private func changeTopics(_ edit: @escaping @Sendable (inout [Topic]) -> Void) {
        var next = allTopics
        edit(&next)
        setTopics(next, confirmed: false) // gespeichert ist es erst, wenn `refresh` den Stand des Speichers liest
        write(ThoughtStore.topicsChangeID) { _ = try await $0.updateTopics(edit) }
    }

    private func setSuggestions(_ next: [TopicSuggestion]) {
        guard next != suggestions else { return }
        suggestions = next
        write(ThoughtStore.topicsChangeID) { try await $0.setPendingSuggestions(next) }
    }

    private func write(_ key: String, _ operation: @escaping @Sendable (ThoughtStore) async throws -> Void) {
        guard let store = backend?.store else { return }
        pendingWrites[key, default: 0] += 1
        let previous = writeChain
        writeChain = Task { [weak self] in
            await previous?.value
            do {
                try await operation(store)
            } catch {
                Diag.log("thought.write.failed", ["error": .s(String(describing: type(of: error)))])
            }
            await self?.writeFinished(key)
        }
    }

    private func writeFinished(_ key: String) async {
        let remaining = (pendingWrites[key] ?? 1) - 1
        pendingWrites[key] = remaining > 0 ? remaining : nil
        if remaining <= 0 { await refresh(key) }
    }

    // MARK: Abgeleitete Daten

    /// Ansichten lesen über Methoden; so hängen sie trotzdem an `thoughts`.
    private func track() {
        _ = thoughts.count
        _ = topics.count
    }

    private static func isVisible(_ thought: Thought) -> Bool {
        thought.state != .recording && thought.state != .empty
    }

    private func replaceAll(_ all: [Thought], topics stored: [Topic]) {
        byID = [:]
        for thought in all where Self.isVisible(thought) { byID[thought.id] = thought }
        thoughts = byID.values.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt }
        deleted = byID.values.filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        allTopics = stored
        topicByID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        TopicPalette.register(stored, persistent: backend != nil) // Themenfarben (Oberfläche)
        reportTopicImages(stored, confirmed: true)
        recomputeDerived()
    }

    /// Themenliste an `TopicImages` (Aliasse, Zusammenführen – nur Verschieben, nie Löschen). `confirmed`: Stand des
    /// Speichers; erst dann übernimmt ein Ziel das Bild der Quelle.
    private func reportTopicImages(_ stored: [Topic], confirmed: Bool) {
        TopicImages.shared.update(topics: stored, persistent: backend != nil, saved: backend == nil || confirmed, from: self)
    }

    /// `confirmed`: Stand des Speichers (sonst Änderung der Oberfläche, noch nicht geschrieben)
    private func setTopics(_ stored: [Topic], confirmed: Bool) {
        let renamed = Set(stored.filter { topicByID[$0.id]?.title != $0.title || topicByID[$0.id]?.mergedInto != $0.mergedInto }.map(\.id))
        allTopics = stored
        topicByID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        TopicPalette.register(stored, persistent: backend != nil)
        reportTopicImages(stored, confirmed: confirmed)
        recomputeDerived()
        guard !renamed.isEmpty else { return }
        for thought in thoughts where renamed.contains(thought.topicId ?? "") || renamed.contains(resolvedTopic(thought.topicId)?.id ?? "") {
            indexForSearch(thought)
        }
    }

    /// Einen Gedanken einsortieren (nil = entfernt).
    private func apply(_ thought: Thought?, id: String) {
        let old = byID[id]
        let new = thought.flatMap { Self.isVisible($0) ? $0 : nil }
        byID[id] = new
        if let old, let new, old.deletedAt == nil, new.deletedAt == nil, old.createdAt == new.createdAt,
           let i = thoughts.firstIndex(where: { $0.id == id }) {
            thoughts[i] = new // häufigster Fall: an Ort und Stelle
        } else {
            if let old {
                if old.deletedAt == nil { thoughts.removeAll { $0.id == id } } else { deleted.removeAll { $0.id == id } }
            }
            if let new {
                if new.deletedAt == nil {
                    let index = thoughts.firstIndex { $0.createdAt < new.createdAt } ?? thoughts.endIndex
                    thoughts.insert(new, at: index)
                } else {
                    let index = deleted.firstIndex { ($0.deletedAt ?? .distantPast) < (new.deletedAt ?? .distantPast) } ?? deleted.endIndex
                    deleted.insert(new, at: index)
                }
            }
        }
        recomputeDerived()
        if let new, new.deletedAt == nil { indexForSearch(new) } else { searchIndex.remove(id) }
    }

    private func recomputeDerived() {
        var nextCounts: [String: Int] = [:]
        var lastActivity: [String: Date] = [:]
        var nextIncoming: [String: [(id: String, link: ThoughtLink)]] = [:]
        for thought in thoughts {
            if let topic = resolvedTopic(thought.topicId)?.id {
                nextCounts[topic, default: 0] += 1
                lastActivity[topic] = max(lastActivity[topic] ?? .distantPast, thought.createdAt)
            }
            for link in thought.links { nextIncoming[link.target, default: []].append((thought.id, link)) }
        }
        counts = nextCounts
        incoming = nextIncoming
        let visible = allTopics.filter { $0.mergedInto == nil }.sorted { a, b in
            let x = lastActivity[a.id] ?? a.createdAt, y = lastActivity[b.id] ?? b.createdAt
            return x != y ? x > y : a.title < b.title
        }
        if visible != topics { topics = visible }
    }

    private func resolvedTopic(_ id: String?) -> Topic? {
        guard var current = id else { return nil }
        var seen: Set<String> = []
        while let topic = topicByID[current] {
            guard let next = topic.mergedInto, seen.insert(current).inserted else { return topic }
            current = next
        }
        return nil
    }

    private func indexForSearch(_ thought: Thought) {
        searchIndex.upsert(thought, topicName: resolvedTopic(thought.topicId)?.title, raw: sources[thought.id]?.text)
    }

    private func rebuildSearchIndex() {
        var index = ThoughtSearchIndex()
        for thought in thoughts {
            index.upsert(thought, topicName: resolvedTopic(thought.topicId)?.title, raw: sources[thought.id]?.text)
        }
        searchIndex = index
    }

    // MARK: Themenpflege

    private func runTopicHygiene(force: Bool) {
        guard let backend, !isCheckingTopics else { return }
        isCheckingTopics = force
        let apiKey = AppSettings.shared.apiKey
        Task { [weak self] in
            if !force, ThoughtsEnvironment.isDictationBusy() {
                self?.isCheckingTopics = false
                return
            }
            let outcome = await TopicHygieneRunner.run(store: backend.store, ledger: backend.ledger, apiKey: apiKey, force: force)
            guard let self else { return }
            self.suggestions = await backend.store.pendingSuggestions()
            self.isCheckingTopics = false
            switch outcome {
            case .suggestions(let list):
                self.topicCheckResult = list.isEmpty ? "Keine ähnlichen Themen" : (list.count == 1 ? "1 Vorschlag" : "\(list.count) Vorschläge")
                self.refreshUsage()
            case .notDue:
                self.topicCheckResult = nil
            case .skipped(let code):
                self.topicCheckResult = code == "key" ? "Groq-Schlüssel fehlt" : code == "budget" ? "Kontingent erreicht" : "Später erneut"
            }
            Diag.log("thoughts.hygiene", ["force": .b(force), "outcome": .s(String(describing: outcome).prefix(40).description)])
        }
    }
}

// MARK: - Vorschau

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
        // Die drei neuesten sind fertig (Abschnitt „Heute“), danach je ein Zwischen- und Wartezustand.
        let states: [ThoughtState] = [.captured, .transcribing, .structuring, .waitingNetwork, .waitingKey,
                                      .waitingLimit, .waitingBudget, .needsAttention]
        let firstState = 3
        var thoughts: [Thought] = []
        var sources: [String: ThoughtSource] = [:]
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        for i in 0..<60 {
            let sample = samples[i % samples.count]
            let topic = topics[i % topics.count]
            // die ersten sechs dicht beieinander (heute, sofern der Tag schon begonnen hat), dann alle ~10 h
            let created = i < 6
                ? max(startOfDay.addingTimeInterval(60 * Double(6 - i)), now.addingTimeInterval(-Double(i) * 1_500))
                : now.addingTimeInterval(-Double(i) * 36_000 - Double(i % 5) * 1_800)
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
            if i == 1 {
                thought.links = [ThoughtLink(target: thoughts[0].id, kind: .continues, reason: "Gleicher Knopf", origin: .ai, createdAt: created)]
            }
            let stateIndex = i - firstState
            if stateIndex >= 0, stateIndex < states.count {
                // Zwischen- und Wartezustände
                thought.state = states[stateIndex]
                thought.title = nil
                thought.text = nil
                thought.titleOwner = .system
                thought.textOwner = .system
                thought.topicId = nil
                thought.tasks = []
                thought.links = []
                thought.ai = nil
                thought.audio = Thought.AudioInfo(file: "audio.wav") // Ton nur, bis der Rohtext liegt
                thought.status = Thought.Status(message: statusMessage(states[stateIndex]),
                                                attempts: states[stateIndex] == .needsAttention ? 5 : 1)
            } else if i == firstState + states.count {
                thought.textIsRaw = true // „nicht geordnet“
                thought.topicId = nil
            } else if i == firstState + states.count + 1 {
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
        let empty = Topic(title: "RA Solartechnik", icon: .lightbulb, owner: .user,
                          note: "Solaranlagen und Projekte für RA Solartechnik")
        return ThoughtsModel(thoughts: thoughts, topics: topics + [provisional, empty], sources: sources, suggestions: suggestions)
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
