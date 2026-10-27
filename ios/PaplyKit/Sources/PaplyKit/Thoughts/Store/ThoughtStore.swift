import Foundation

public enum ThoughtStoreError: Error, Sendable, Equatable {
    /// nur noch für den S1-Rückfall in ThoughtCapture (H3); der Speicher wirft ihn nicht mehr
    case notImplemented
    /// ID mit unzulässigen Zeichen (Pfadschutz)
    case invalidID
    case notFound
    /// `source.json` ist schon geschrieben (einmal, danach unveränderlich)
    case sourceExists
    /// Ablage nicht lesbar (z. B. vor dem ersten Entsperren); nichts wird überschrieben
    case unavailable
}

/// Validiertes KI-Ergebnis samt Abrechnung (Cache `ai-result.json`, §6.7).
public struct AIResultRecord: Sendable, Equatable {
    public var result: StructureResult
    public var model: String?
    public var usage: TokenUsage?
    public var at: Date

    public init(result: StructureResult, model: String? = nil, usage: TokenUsage? = nil, at: Date = Date()) {
        self.result = result
        self.model = model
        self.usage = usage
        self.at = at
    }
}

/// JSON-Dateien je Gedanke (KONZEPT §7).
///
/// Ablage unter `root` (§7.2): `topics.json` (+ `topics.prev.json`), `thoughts/<id>/thought.json`,
/// `source.json` (einmal), `ai-result.json` (Cache), `ai-parts.json` (Teile-Modus), `audio.wav` (nur bis zum Rohtext).
/// Alle Gedanken liegen als Index im RAM; geschrieben wird atomar (tmp + fsync + rename).
/// Beschädigte Dateien werden nie still ersetzt, sondern als `damaged-<ms>.json` daneben gesichert.
public actor ThoughtStore {
    /// Wird in `changes` gemeldet, wenn sich die Themen geändert haben.
    public static let topicsChangeID = "topics"
    /// „Zuletzt gelöscht“ bleibt so lange, dann endgültig entfernt
    public static let trashRetention: TimeInterval = 30 * 24 * 3600

    public nonisolated let root: URL
    private let clock: @Sendable () -> Date
    /// true erst, wenn alles Vorhandene lesbar war. Vor dem ersten Entsperren nach einem Neustart
    /// (Data Protection) bleibt es false; jeder Zugriff und `reloadIfNeeded()` lädt dann nach.
    private var loaded = false
    private var loadAttempts = 0
    private var cache: [String: Thought] = [:]
    private var sourceCache: [String: ThoughtSource] = [:]
    private var topicsDoc = TopicsDocument()
    /// `topics.json` gelesen (oder nicht vorhanden). Solange false, wird es nie geschrieben.
    private var topicsReadable = false
    /// laufende Aufnahmen dieses Prozesses: `recover()` fasst sie nicht an
    private var activeCaptures: Set<String> = []
    private var reconstructed: [String] = []
    private let changeBroadcast = Broadcast<String>()

    public init(root: URL) throws {
        try self.init(root: root, now: Date.init)
    }

    /// `now` für Tests (Aufbewahrungsfristen).
    public init(root: URL, now: @escaping @Sendable () -> Date) throws {
        guard root.isFileURL else { throw ThoughtStoreError.unavailable }
        self.root = root
        self.clock = now
    }

    /// geänderte Gedanken-ID (bzw. `topicsChangeID`). Jeder Zugriff liefert einen eigenen Strom.
    public nonisolated var changes: AsyncStream<String> { changeBroadcast.stream }

    // MARK: Pfade

    public nonisolated var thoughtsDirectory: URL { root.appendingPathComponent("thoughts", isDirectory: true) }
    public nonisolated func directory(_ id: String) -> URL { thoughtsDirectory.appendingPathComponent(id, isDirectory: true) }
    nonisolated func thoughtURL(_ id: String) -> URL { directory(id).appendingPathComponent("thought.json") }
    nonisolated func sourceURL(_ id: String) -> URL { directory(id).appendingPathComponent("source.json") }
    nonisolated func aiResultURL(_ id: String) -> URL { directory(id).appendingPathComponent("ai-result.json") }
    nonisolated func aiPartsURL(_ id: String) -> URL { directory(id).appendingPathComponent("ai-parts.json") }
    public nonisolated func wavURL(_ id: String) -> URL { directory(id).appendingPathComponent("audio.wav") }
    /// nur Altbestand (früher AAC nach dem Rohtext); wird beim Aufräumen gelöscht
    nonisolated func m4aURL(_ id: String) -> URL { directory(id).appendingPathComponent("audio.m4a") }
    nonisolated var topicsURL: URL { root.appendingPathComponent("topics.json") }
    nonisolated var topicsPrevURL: URL { root.appendingPathComponent("topics.prev.json") }
    nonisolated var suggestionsURL: URL { root.appendingPathComponent("topic-suggestions.json") }

    static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 80, !id.hasPrefix(".") else { return false }
        return id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-" }
    }

    // MARK: Laden

    /// Lädt beim ersten Zugriff (nicht im `init`, damit der App-Start nicht wartet). War etwas nicht lesbar
    /// (geschützt), bleibt `loaded` false und der nächste Zugriff lädt das Fehlende nach. Bereits Geladenes und
    /// in diesem Prozess Geschriebenes bleibt dabei erhalten; nachgeladene Gedanken und Themen werden gemeldet.
    private func ensureLoaded() throws {
        if loaded { return }
        try FileSafety.createDirectory(thoughtsDirectory)
        let isRetry = loadAttempts > 0
        loadAttempts += 1
        let known = Set(cache.keys)
        let topicsBefore = topicsReadable
        let thoughtsComplete = loadThoughts()
        if !topicsReadable { loadTopics() }
        loaded = thoughtsComplete && topicsReadable
        guard isRetry else { return }
        for id in cache.keys where !known.contains(id) { changeBroadcast.yield(id) }
        if topicsReadable && !topicsBefore { changeBroadcast.yield(Self.topicsChangeID) }
    }

    /// Nach `protectedDataDidBecomeAvailable` (erstes Entsperren nach Neustart) aufrufen: lädt nach, was
    /// vorher nicht lesbar war, und meldet es über `changes`. true = Ablage vollständig gelesen.
    @discardableResult
    public func reloadIfNeeded() -> Bool {
        try? ensureLoaded()
        return loaded
    }

    /// true = alles Vorhandene gelesen (geschützte Dateien zählen als nicht gelesen).
    private func loadThoughts() -> Bool {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: thoughtsDirectory.path)
        } catch {
            return false // Ordner nicht lesbar: später erneut
        }
        let ids = names.filter { Self.isValidID($0) && cache[$0] == nil }
        guard !ids.isEmpty else { return true }
        let base = thoughtsDirectory
        let decoded = Parallel.map(ids.count) { index -> Thought? in
            let url = base.appendingPathComponent(ids[index], isDirectory: true).appendingPathComponent("thought.json")
            guard let data = try? Data(contentsOf: url), let thought = try? ThoughtJSON.decoder().decode(Thought.self, from: data),
                  thought.id == ids[index] else { return nil }
            return thought
        }
        var complete = true
        for (index, id) in ids.enumerated() {
            if let thought = decoded[index] {
                cache[id] = thought
            } else if FileSafety.exists(thoughtURL(id)), (try? Data(contentsOf: thoughtURL(id))) == nil {
                complete = false // vorhanden, aber geschützt: nicht rekonstruieren, später erneut lesen
            } else if let rebuilt = reconstruct(id) {
                cache[id] = rebuilt
                reconstructed.append(id)
            }
        }
        return complete
    }

    /// `thought.json` fehlt oder ist beschädigt: aus Ton und `source.json` neu aufbauen (nie still verwerfen).
    private func reconstruct(_ id: String) -> Thought? {
        let dir = directory(id)
        let fm = FileManager.default
        let jsonURL = thoughtURL(id)
        if fm.fileExists(atPath: jsonURL.path) {
            if (try? Data(contentsOf: jsonURL)) == nil { return nil } // nicht lesbar (geschützt): nichts anfassen
            let damaged = dir.appendingPathComponent("damaged-\(ThoughtJSON.milliseconds(clock())).json")
            try? fm.moveItem(at: jsonURL, to: damaged)
        }
        let source = readSource(id)
        let wav = wavURL(id), m4a = m4aURL(id)
        let audioFile: String? = fm.fileExists(atPath: m4a.path) ? "audio.m4a" : fm.fileExists(atPath: wav.path) ? "audio.wav" : nil
        guard source != nil || audioFile != nil else {
            // nur Reste (Temp-Dateien) → Ordner weg; Beschädigtes bleibt liegen
            let rest = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(FileSafety.tempPrefix) }
            if rest.isEmpty { try? fm.removeItem(at: dir) }
            return nil
        }
        var durationMs = Int((source?.audioSeconds ?? 0) * 1000)
        if audioFile == "audio.wav", let repaired = try? WAVWriter.repair(wav) { durationMs = max(durationMs, repaired) }
        let created = (try? fm.attributesOfItem(atPath: dir.path)[.creationDate] as? Date) ?? source?.createdAt ?? clock()
        let thought = Thought(id: id, createdAt: created, durationMs: durationMs, trigger: .unknown,
                              state: source != nil ? .transcribed : .captured, languages: source?.languages ?? [],
                              audio: audioFile.map { Thought.AudioInfo(file: $0) }, updatedAt: clock())
        try? writeFile(thought)
        return thought
    }

    /// Setzt `topicsReadable`, sobald `topics.json` gelesen (oder nicht vorhanden) ist.
    private func loadTopics() {
        let fm = FileManager.default
        if fm.fileExists(atPath: topicsURL.path) {
            guard let data = try? Data(contentsOf: topicsURL) else {
                return // geschützt/nicht lesbar: nie überschreiben, später erneut
            }
            topicsReadable = true
            if let doc = try? ThoughtJSON.decoder().decode(TopicsDocument.self, from: data) {
                topicsDoc = doc
                return
            }
            // beschädigt: sichern, Vorgänger nehmen
            let damaged = root.appendingPathComponent("damaged-\(ThoughtJSON.milliseconds(clock())).json")
            try? fm.moveItem(at: topicsURL, to: damaged)
            if let prev = try? Data(contentsOf: topicsPrevURL),
               let doc = try? ThoughtJSON.decoder().decode(TopicsDocument.self, from: prev) {
                topicsDoc = doc
                try? FileSafety.writeAtomically(prev, to: topicsURL)
            }
            return
        }
        if fm.fileExists(atPath: topicsPrevURL.path), (try? Data(contentsOf: topicsPrevURL)) == nil {
            return // nur der Vorgänger liegt da und ist geschützt: später erneut
        }
        topicsReadable = true
        if let prev = try? Data(contentsOf: topicsPrevURL),
           let doc = try? ThoughtJSON.decoder().decode(TopicsDocument.self, from: prev) {
            topicsDoc = doc
        }
    }

    // MARK: Lesen

    /// alle Gedanken (auch gelöschte und laufende Aufnahmen), unsortiert
    public func all() -> [Thought] {
        try? ensureLoaded()
        return Array(cache.values)
    }

    public func thought(_ id: String) -> Thought? {
        try? ensureLoaded()
        return cache[id]
    }

    public func source(_ id: String) -> ThoughtSource? {
        if let cached = sourceCache[id] { return cached }
        guard Self.isValidID(id), let source = readSource(id) else { return nil }
        sourceCache[id] = source
        return source
    }

    private nonisolated func readSource(_ id: String) -> ThoughtSource? {
        guard let data = try? Data(contentsOf: sourceURL(id)) else { return nil }
        return try? ThoughtJSON.decoder().decode(ThoughtSource.self, from: data)
    }

    public func hasSource(_ id: String) -> Bool {
        sourceCache[id] != nil || FileSafety.exists(sourceURL(id))
    }

    /// Rohtexte aller Gedanken (für die Suche), parallel gelesen und danach im RAM.
    public func rawTexts() -> [String: String] {
        allSources().mapValues(\.text)
    }

    /// Alle `source.json` (parallel gelesen, danach im RAM).
    public func allSources() -> [String: ThoughtSource] {
        try? ensureLoaded()
        let missing = cache.keys.filter { sourceCache[$0] == nil }
        if !missing.isEmpty {
            let base = thoughtsDirectory
            let ids = Array(missing)
            let read = Parallel.map(ids.count) { i -> ThoughtSource? in
                let url = base.appendingPathComponent(ids[i], isDirectory: true).appendingPathComponent("source.json")
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? ThoughtJSON.decoder().decode(ThoughtSource.self, from: data)
            }
            for (i, id) in ids.enumerated() { if let source = read[i] { sourceCache[id] = source } }
        }
        return sourceCache
    }

    /// Datei laut `audio.file`; fehlt sie (Umwandlung unterbrochen), die andere Form.
    public func audioURL(_ id: String) -> URL? {
        try? ensureLoaded()
        guard Self.isValidID(id), let file = cache[id]?.audio?.file else { return nil }
        let primary = directory(id).appendingPathComponent(file)
        if FileSafety.exists(primary) { return primary }
        let other = file == "audio.wav" ? m4aURL(id) : wavURL(id)
        return FileSafety.exists(other) ? other : nil
    }

    // MARK: Schreiben

    /// atomar, rev + 1. Zustand `.empty` entfernt den Gedanken samt Ton (keine Leiche, §5.2).
    public func save(_ thought: Thought) throws {
        try ensureLoaded()
        guard Self.isValidID(thought.id) else { throw ThoughtStoreError.invalidID }
        if thought.state == .empty {
            purge(thought.id)
            return
        }
        var next = thought
        next.rev = max(thought.rev, cache[thought.id]?.rev ?? 0) + 1
        next.updatedAt = clock()
        try commit(next)
    }

    /// Ändert den aktuellen Stand atomar im Speicher-Akteur (keine verlorenen Änderungen zwischen
    /// Oberfläche und Warteschlange). nil = Gedanke existiert nicht (mehr).
    @discardableResult
    public func update(_ id: String, _ change: @Sendable (inout Thought) -> Void) throws -> Thought? {
        try ensureLoaded()
        guard let current = cache[id] else { return nil }
        var next = current
        change(&next)
        next.id = id
        if next == current { return current }
        if next.state == .empty {
            purge(id)
            return nil
        }
        next.rev = current.rev + 1
        next.updatedAt = clock()
        try commit(next)
        return next
    }

    private func commit(_ thought: Thought) throws {
        try writeFile(thought)
        cache[thought.id] = thought
        if thought.state != .recording { activeCaptures.remove(thought.id) }
        changeBroadcast.yield(thought.id)
    }

    private func writeFile(_ thought: Thought) throws {
        let dir = directory(thought.id)
        if !FileSafety.exists(dir) { try FileSafety.createDirectory(dir) }
        let data = try ThoughtJSON.encoder().encode(thought)
        try FileSafety.writeAtomically(data, to: thoughtURL(thought.id))
    }

    /// In „Zuletzt gelöscht“ legen.
    public func delete(_ id: String) throws {
        let now = clock()
        guard try update(id, { $0.deletedAt = now }) != nil else { throw ThoughtStoreError.notFound }
    }

    public func restore(_ id: String) throws {
        guard try update(id, { $0.deletedAt = nil }) != nil else { throw ThoughtStoreError.notFound }
    }

    /// Endgültig entfernen: Ton, Text, Cache (§7.6). Themen, die danach keinen Gedanken mehr tragen (weder
    /// aktiv noch im Papierkorb), fallen mit weg – egal ob von der KI oder vom Nutzer angelegt.
    public func purge(_ id: String) {
        purge([id])
    }

    /// Mehrere auf einmal („Alle löschen“, 30-Tage-Frist): Themen werden einmal am Ende aufgeräumt.
    public func purge(_ ids: [String]) {
        try? ensureLoaded()
        var topicIDs: Set<String> = []
        for id in ids {
            if let topicID = removeThought(id) { topicIDs.insert(topicID) }
        }
        pruneTopics(topicIDs)
    }

    /// Ordner und Index-Eintrag weg; gibt das (aufgelöste) Thema des Gedankens zurück.
    private func removeThought(_ id: String) -> String? {
        guard Self.isValidID(id) else { return nil }
        try? FileManager.default.removeItem(at: directory(id))
        let removed = cache.removeValue(forKey: id)
        sourceCache[id] = nil
        activeCaptures.remove(id)
        guard let removed else { return nil }
        changeBroadcast.yield(id)
        return Self.resolve(removed.topicId, in: topicsDoc.topics)?.id
    }

    /// Nur Themen gerade endgültig gelöschter Gedanken kommen in Frage: Trägt sie kein Gedanke mehr, gehen sie
    /// samt Aliassen, abgelehnten Paaren und Vorschlägen. Ein von Hand angelegtes, noch leeres Thema bleibt so
    /// stehen. Nur bei vollständig gelesener Ablage (sonst könnte ein ungelesener Gedanke das Thema tragen).
    private func pruneTopics(_ candidates: Set<String>) {
        guard !candidates.isEmpty, loaded, topicsReadable else { return }
        let topics = topicsDoc.topics
        var carried: Set<String> = []
        for thought in cache.values {
            if let topic = Self.resolve(thought.topicId, in: topics) { carried.insert(topic.id) }
        }
        let empty = candidates.subtracting(carried)
        guard !empty.isEmpty else { return }
        let removed = Set(topics.filter { topic in
            empty.contains(topic.id) || Self.resolve(topic.id, in: topics).map { empty.contains($0.id) } == true
        }.map(\.id))
        var doc = topicsDoc
        doc.topics.removeAll { removed.contains($0.id) }
        doc.declinedMerges.removeAll { pair in pair.contains { removed.contains($0) } }
        guard (try? writeTopics(doc)) != nil else { return }
        let suggestions = pendingSuggestions()
        let kept = suggestions.filter { !removed.contains($0.a) && !removed.contains($0.b) }
        if kept.count != suggestions.count { try? setPendingSuggestions(kept) }
    }

    public func saveSourceOnce(_ id: String, _ source: ThoughtSource) throws {
        try ensureLoaded()
        guard Self.isValidID(id) else { throw ThoughtStoreError.invalidID }
        // Endgültig gelöscht (z. B. während der Verschriftlichung): keinen Ordner neu anlegen, sonst kehrte
        // der Gedanke nach einem Neustart als Rekonstruktion zurück.
        guard cache[id] != nil else { throw ThoughtStoreError.notFound }
        guard !hasSource(id) else { throw ThoughtStoreError.sourceExists }
        let dir = directory(id)
        if !FileSafety.exists(dir) { try FileSafety.createDirectory(dir) }
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(source), to: sourceURL(id))
        sourceCache[id] = source
        releaseAudio(id) // Ton nur bis zum Rohtext
    }

    // MARK: Ton nur bis zum Rohtext

    /// Liegt der Rohtext dauerhaft (`source.json` von der Platte lesbar), kommt der Ton weg: erst die Dateien,
    /// dann `audio = nil`. Ein Absturz dazwischen verliert nie Ton UND Text – der Text liegt schon, und
    /// `housekeeping` räumt den Rest nach. Ohne Rohtext (offline, ohne Schlüssel, Fehler, im Papierkorb vor der
    /// Umschrift) bleibt die WAV für den Neuversuch; laufende Aufnahmen bleiben unberührt. true = Ton entfernt.
    @discardableResult
    public func releaseAudio(_ id: String) -> Bool {
        guard Self.isValidID(id), let thought = cache[id], thought.audio != nil, thought.state != .recording,
              !activeCaptures.contains(id), let source = readSource(id) else { return false }
        sourceCache[id] = source
        FileSafety.syncDirectory(directory(id)) // `source.json` samt Verzeichniseintrag auf der Platte
        for url in [wavURL(id), m4aURL(id)] where FileSafety.exists(url) {
            guard (try? FileManager.default.removeItem(at: url)) != nil else { return false }
        }
        return (try? update(id) { $0.audio = nil }) != nil
    }

    // MARK: Aufnahme (H3)

    /// Synchron: Eintrag `recording` + `audio.wav` mit Platzhalter-Kopf (§5.3 Punkt 1).
    public func beginCapture(trigger: ThoughtTrigger, at: Date) throws -> (thought: Thought, audio: WAVWriter) {
        try ensureLoaded()
        let id = ThoughtIDs.thought()
        try FileSafety.createDirectory(directory(id))
        let thought = Thought(id: id, createdAt: at, trigger: trigger, state: .recording,
                              audio: Thought.AudioInfo(file: "audio.wav"), updatedAt: at)
        try writeFile(thought)
        let writer: WAVWriter
        do {
            writer = try WAVWriter(url: wavURL(id))
        } catch {
            try? FileManager.default.removeItem(at: directory(id))
            throw error
        }
        cache[id] = thought
        activeCaptures.insert(id)
        changeBroadcast.yield(id)
        return (thought, writer)
    }

    /// Aufnahme beendet: Zustand `captured`, Dauer setzen. Ohne Ton (0 ms) wird der Eintrag entfernt.
    @discardableResult
    public func finishCapture(_ id: String, durationMs: Int) throws -> Thought? {
        try completeCapture(id, durationMs: durationMs, deletedAt: nil)
    }

    /// Aufnahme beendet und – beim Verwerfen – im selben Schritt in „Zuletzt gelöscht“ (`deletedAt`).
    /// Ein einziges atomares Update: Die Warteschlange sieht den Gedanken nie als `captured` ohne `deletedAt`
    /// und schickt ihn deshalb nicht an Groq. `deletedAt == nil` lässt den Löschstand unverändert.
    /// Ohne Ton (0 ms) wird der Eintrag entfernt. Fehlt der Gedanke (schon endgültig entfernt): `.notFound`.
    public func finishCapture(_ id: String, durationMs: Int, deletedAt: Date?) async throws {
        let finished = try completeCapture(id, durationMs: durationMs, deletedAt: deletedAt)
        if finished == nil && durationMs > 0 { throw ThoughtStoreError.notFound }
    }

    @discardableResult
    private func completeCapture(_ id: String, durationMs: Int, deletedAt: Date?) throws -> Thought? {
        activeCaptures.remove(id)
        guard durationMs > 0 else {
            purge(id)
            return nil
        }
        return try update(id) { thought in
            thought.state = .captured
            thought.durationMs = durationMs
            if let deletedAt { thought.deletedAt = deletedAt }
        }
    }

    /// Aufnahme verworfen (große Ansicht) oder Start gescheitert: Eintrag und Ton weg.
    public func discardCapture(_ id: String) {
        purge(id)
    }

    // MARK: KI-Cache

    public func saveAIResult(_ id: String, _ result: StructureResult) throws {
        try saveAIResult(id, AIResultRecord(result: result, at: clock()))
    }

    public func saveAIResult(_ id: String, _ record: AIResultRecord) throws {
        guard Self.isValidID(id), FileSafety.exists(directory(id)) else { throw ThoughtStoreError.notFound }
        let data = try ThoughtJSON.encoder().encode(AIResultFile(record))
        try FileSafety.writeAtomically(data, to: aiResultURL(id))
    }

    public func aiResult(_ id: String) -> StructureResult? {
        aiResultRecord(id)?.result
    }

    public func aiResultRecord(_ id: String) -> AIResultRecord? {
        guard Self.isValidID(id), let data = try? Data(contentsOf: aiResultURL(id)),
              let file = try? ThoughtJSON.decoder().decode(AIResultFile.self, from: data) else { return nil }
        return file.record
    }

    /// „Erneut ordnen“: alter Cache wird verworfen (Mac N11).
    public func discardAIResult(_ id: String) {
        guard Self.isValidID(id) else { return }
        try? FileManager.default.removeItem(at: aiResultURL(id))
        try? FileManager.default.removeItem(at: aiPartsURL(id))
    }

    /// Fortschritt im Teile-Modus (erledigte Teile überleben Warten und Neustart).
    public func saveParts(_ id: String, _ parts: StructureParts) throws {
        guard Self.isValidID(id), FileSafety.exists(directory(id)) else { throw ThoughtStoreError.notFound }
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(parts), to: aiPartsURL(id))
    }

    public func discardParts(_ id: String) {
        guard Self.isValidID(id) else { return }
        try? FileManager.default.removeItem(at: aiPartsURL(id))
    }

    public func parts(_ id: String) -> StructureParts? {
        guard Self.isValidID(id), let data = try? Data(contentsOf: aiPartsURL(id)) else { return nil }
        return try? ThoughtJSON.decoder().decode(StructureParts.self, from: data)
    }

    // MARK: Themen

    /// alle Themen, auch zusammengeführte (`mergedInto` = Alias)
    public func topics() -> [Topic] {
        try? ensureLoaded()
        return topicsDoc.topics
    }

    /// `topics.json` atomar; der bisherige Stand wandert nach `topics.prev.json`.
    public func saveTopics(_ topics: [Topic]) throws {
        try ensureLoaded()
        guard topicsReadable else { throw ThoughtStoreError.unavailable }
        var doc = topicsDoc
        doc.topics = topics
        try writeTopics(doc)
    }

    /// Themen atomar im Speicher-Akteur ändern (Oberfläche und Warteschlange legen gleichzeitig an).
    @discardableResult
    public func updateTopics(_ change: @Sendable (inout [Topic]) -> Void) throws -> [Topic] {
        try ensureLoaded()
        guard topicsReadable else { throw ThoughtStoreError.unavailable }
        var next = topicsDoc.topics
        change(&next)
        guard next != topicsDoc.topics else { return next }
        var doc = topicsDoc
        doc.topics = next
        try writeTopics(doc)
        return next
    }

    /// Offene Vorschläge der Themenpflege (`topic-suggestions.json`, höchstens 2).
    public func pendingSuggestions() -> [TopicSuggestion] {
        guard let data = try? Data(contentsOf: suggestionsURL) else { return [] }
        return (try? ThoughtJSON.decoder().decode([TopicSuggestion].self, from: data)) ?? []
    }

    public func setPendingSuggestions(_ suggestions: [TopicSuggestion]) throws {
        try ensureLoaded()
        guard topicsReadable else { throw ThoughtStoreError.unavailable } // Vorschläge beruhen auf den Themen
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(suggestions), to: suggestionsURL)
        changeBroadcast.yield(Self.topicsChangeID)
    }

    /// Abgelehntes Paar merken: kommt nie wieder (§6.10).
    public func declineMerge(_ a: String, _ b: String) throws {
        try ensureLoaded()
        let pair = [a, b].sorted()
        guard !topicsDoc.declinedMerges.contains(where: { $0.sorted() == pair }) else { return }
        try setDeclinedMerges(topicsDoc.declinedMerges + [pair])
    }

    public func topicsInfo() -> (declinedMerges: [[String]], lastHygieneAt: Date?) {
        try? ensureLoaded()
        return (topicsDoc.declinedMerges, topicsDoc.lastHygieneAt)
    }

    public func setDeclinedMerges(_ pairs: [[String]]) throws {
        try ensureLoaded()
        guard topicsReadable else { throw ThoughtStoreError.unavailable }
        var doc = topicsDoc
        doc.declinedMerges = pairs
        try writeTopics(doc)
    }

    public func setLastHygieneAt(_ date: Date?) throws {
        try ensureLoaded()
        guard topicsReadable else { throw ThoughtStoreError.unavailable }
        var doc = topicsDoc
        doc.lastHygieneAt = date
        try writeTopics(doc)
    }

    private func writeTopics(_ doc: TopicsDocument) throws {
        var next = doc
        next.rev = topicsDoc.rev + 1
        if let current = try? Data(contentsOf: topicsURL) {
            try? FileSafety.writeAtomically(current, to: topicsPrevURL)
        }
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(next), to: topicsURL)
        topicsDoc = next
        changeBroadcast.yield(Self.topicsChangeID)
    }

    /// Thema samt Alias-Kette (`mergedInto`) auflösen; nil, wenn es nicht (mehr) existiert.
    public func resolveTopic(_ id: String?) -> Topic? {
        try? ensureLoaded()
        return Self.resolve(id, in: topicsDoc.topics)
    }

    public static func resolve(_ id: String?, in topics: [Topic]) -> Topic? {
        guard var current = id else { return nil }
        var seen: Set<String> = []
        while let topic = topics.first(where: { $0.id == current }) {
            guard let next = topic.mergedInto, !seen.contains(next) else { return topic }
            seen.insert(current)
            current = next
        }
        return nil
    }

    // MARK: Wiederherstellung und Pflege

    /// Nach Absturz/Neustart: WAV-Kopf reparieren, `recording` → `captured` (laufende Aufnahmen dieses
    /// Prozesses bleiben unberührt). Platzhalter ohne Ton werden entfernt. Gibt die reparierten IDs zurück.
    public func recover() throws -> [String] {
        try ensureLoaded()
        var repaired = reconstructed
        reconstructed = []
        for thought in cache.values where thought.state == .recording && !activeCaptures.contains(thought.id) {
            let wav = wavURL(thought.id)
            let durationMs = FileSafety.exists(wav) ? ((try? WAVWriter.repair(wav)) ?? 0) : 0
            if durationMs > 0 {
                try update(thought.id) { t in
                    t.state = .captured
                    t.durationMs = durationMs
                }
                repaired.append(thought.id)
            } else {
                purge(thought.id)
            }
        }
        removeStaleTempFiles(olderThan: 600)
        return repaired
    }

    /// „Zuletzt gelöscht“ nach 30 Tagen endgültig (samt leer gewordener Themen). Danach Ton aller Gedanken mit
    /// Rohtext entfernen – auch Altbestand (früher 30 Tage behalten, als m4a) und im Papierkorb.
    public func housekeeping(now: Date) {
        guard (try? ensureLoaded()) != nil else { return }
        let expired = cache.values.filter { thought in
            thought.deletedAt.map { now.timeIntervalSince($0) >= Self.trashRetention } ?? false
        }
        if !expired.isEmpty { purge(expired.map(\.id)) }
        for thought in Array(cache.values) where thought.audio != nil {
            releaseAudio(thought.id)
        }
        removeStaleTempFiles(olderThan: 3600)
    }

    private func removeStaleTempFiles(olderThan seconds: TimeInterval) {
        let fm = FileManager.default
        let limit = Date().addingTimeInterval(-seconds)
        var dirs = [root]
        dirs += cache.keys.map(directory)
        for dir in dirs {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix(FileSafety.tempPrefix) {
                let url = dir.appendingPathComponent(name)
                let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
                if modified < limit { try? fm.removeItem(at: url) }
            }
        }
    }
}

// MARK: - Dateiformate

/// `topics.json` (§7.3)
struct TopicsDocument: Codable, Sendable, Equatable {
    var schemaVersion = 1
    var rev = 0
    var topics: [Topic] = []
    var declinedMerges: [[String]] = []
    var lastHygieneAt: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        rev = try c.decodeIfPresent(Int.self, forKey: .rev) ?? 0
        topics = try c.decode([Topic].self, forKey: .topics)
        declinedMerges = try c.decodeIfPresent([[String]].self, forKey: .declinedMerges) ?? []
        lastHygieneAt = try c.decodeIfPresent(Date.self, forKey: .lastHygieneAt)
    }
}

/// Fortschritt im Teile-Modus (`ai-parts.json`).
public struct StructureParts: Codable, Sendable, Equatable {
    public struct Part: Codable, Sendable, Equatable {
        public var cleanText: String?
        public var tasks: [StoredTask]
        public var rejections: [String]
        public var tokens: Int

        public init(cleanText: String?, tasks: [StoredTask], rejections: [String], tokens: Int) {
            self.cleanText = cleanText
            self.tasks = tasks
            self.rejections = rejections
            self.tokens = tokens
        }
    }

    public struct StoredTask: Codable, Sendable, Equatable {
        public var text: String
        public var quote: String
        public var dueHint: String?

        public init(_ draft: TaskDraft) {
            text = draft.text
            quote = draft.quote
            dueHint = draft.dueHint
        }

        public var draft: TaskDraft { TaskDraft(text: text, quote: quote, dueHint: dueHint) }
    }

    /// Stabiler Hash des Transkripts: ändert er sich, gilt der Fortschritt nicht mehr.
    public var transcriptHash: String
    public var count: Int
    /// Ergebnis von Teil 1 (Titel, Thema, Verbindungen)
    public var first: AIResultFile?
    /// Teile 2…n in Reihenfolge
    public var rest: [Part]
    public var lastCallAt: Date?

    public init(transcriptHash: String, count: Int, first: AIResultFile? = nil, rest: [Part] = [], lastCallAt: Date? = nil) {
        self.transcriptHash = transcriptHash
        self.count = count
        self.first = first
        self.rest = rest
        self.lastCallAt = lastCallAt
    }
}

/// `ai-result.json`: validiertes Ergebnis (Contract-Typen sind nicht Codable, daher eigenes Format).
public struct AIResultFile: Codable, Sendable, Equatable {
    struct TopicDTO: Codable, Sendable, Equatable {
        var kind: String
        var id: String?
        var name: String?
        var icon: TopicIcon?
    }

    struct RelatedDTO: Codable, Sendable, Equatable {
        var thoughtID: String
        var kind: LinkKind
        var reason: String
    }

    struct UsageDTO: Codable, Sendable, Equatable {
        var prompt: Int
        var completion: Int
        var total: Int
    }

    var schemaVersion = 1
    var title: String
    var cleanText: String?
    var topic: TopicDTO
    var tasks: [StructureParts.StoredTask]
    var related: [RelatedDTO]
    var rejections: [String]
    var model: String?
    var usage: UsageDTO?
    var at: Date

    public init(_ record: AIResultRecord) {
        let result = record.result
        title = result.title
        cleanText = result.cleanText
        switch result.topic {
        case .existing(let id): topic = TopicDTO(kind: "existing", id: id)
        case .new(let name, let icon): topic = TopicDTO(kind: "new", name: name, icon: icon)
        case .none: topic = TopicDTO(kind: "none")
        }
        tasks = result.tasks.map(StructureParts.StoredTask.init)
        related = result.related.map { RelatedDTO(thoughtID: $0.thoughtID, kind: $0.kind, reason: $0.reason) }
        rejections = result.rejections
        model = record.model
        usage = record.usage.map { UsageDTO(prompt: $0.prompt, completion: $0.completion, total: $0.total) }
        at = record.at
    }

    public var record: AIResultRecord {
        let decision: TopicDecision
        switch topic.kind {
        case "existing": decision = topic.id.map(TopicDecision.existing) ?? .none
        case "new": decision = topic.name.map { TopicDecision.new(name: $0, icon: topic.icon ?? .sparkles) } ?? .none
        default: decision = .none
        }
        let result = StructureResult(title: title, cleanText: cleanText, topic: decision, tasks: tasks.map(\.draft),
                                     related: related.map { RelatedDraft(thoughtID: $0.thoughtID, kind: $0.kind, reason: $0.reason) },
                                     rejections: rejections)
        return AIResultRecord(result: result, model: model,
                              usage: usage.map { TokenUsage(prompt: $0.prompt, completion: $0.completion, total: $0.total) }, at: at)
    }
}
