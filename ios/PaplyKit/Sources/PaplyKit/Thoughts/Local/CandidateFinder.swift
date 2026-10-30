import Foundation

/// Lokale Vorauswahl: Themen-Index + höchstens 7 Kandidaten (KONZEPT §6.3).
///
/// Wert = 0,6 · Kosinus + 0,4 · BM25 (0…1) + 0,05, wenn jünger als 7 Tage; Mindestwert und Normierung
/// kalibriert E0 (`paply-bench candidates`, EVAL.md). Höchstens 6 Kandidaten über dem Mindestwert,
/// dazu immer die ≤ 2 letzten Gedanken der letzten 3 h; zusammen ≤ 7.
public actor CandidateFinder: CandidateFinding {
    public struct Options: Sendable, Equatable {
        public var cosineWeight = 0.6
        public var keywordWeight = 0.4
        public var recencyBonus = 0.05
        public var recencyWindow: TimeInterval = 7 * 24 * 3600
        public var minimumScore = 0.35
        public var maxScored = 6
        public var maxTotal = 7
        public var recentWindow: TimeInterval = 3 * 3600
        public var recentMax = 2
        public var excerptLength = 160
        /// Vektoren um den Mittelwert der Ablage zentrieren (E0: bei relativer Wertung ohne Nutzen)
        public var centerVectors = false
        /// Kosinus unterhalb dieses Werts zählt 0, darüber linear bis 1
        public var cosineFloor = 0.0
        public var keywordNormalization: KeywordNormalization = .selfScore
        public var scoring: Scoring = .relative
        /// relativ: so viele Standardabweichungen über dem Durchschnitt der Ablage ergeben Wert 1
        public var zScale = 4.0
        /// relativ erst ab so vielen Gedanken (darunter absolut)
        public var relativeMinimumCount = 8
        /// Reihenfolge der Modelle; leer = nur Schlagwörter. E0: das Satz-Embedding verschlechtert die Suche,
        /// fehlt das kontextuelle Modell, zählen deshalb nur die Schlagwörter.
        public var models: [EmbeddingModel] = [.contextual]
        /// so viele Index-Einträge höchstens je Aufruf neu berechnen (Rest später)
        public var maxRefreshPerCall = 400

        public init() {}
    }

    /// Wie Kosinus und Schlagwort-Wert zu 0…1 werden.
    public enum Scoring: String, Sendable, Equatable {
        /// fest: 0,6 · Kosinus + 0,4 · Schlagwort (je 0…1)
        case absolute
        /// je Anfrage standardisiert: wie weit ein Gedanke über dem Durchschnitt der Ablage liegt (z-Wert / `zScale`).
        /// Unabhängig vom Modell (gemittelte Token-Vektoren liegen alle bei ≈ 0,8) und von der Länge der Anfrage.
        case relative
    }

    public enum KeywordNormalization: String, Sendable, Equatable {
        /// BM25 geteilt durch BM25 der Anfrage gegen sich selbst
        case selfScore
        /// BM25 geteilt durch den besten Wert dieser Anfrage
        case maximum
    }

    /// Bewertung eines Gedankens (für E0 und Protokolle; ohne Text).
    public struct Scored: Sendable, Equatable {
        public var thoughtID: String
        public var score: Double
        public var cosine: Double?
        public var keyword: Double
        public var isRecent: Bool
    }

    private enum Source {
        case store(ThoughtStore)
        case snapshot([Thought], [Topic])
    }

    public nonisolated let options: Options
    private let source: Source
    private let indexURL: URL?
    private let embedder: EmbeddingIndex
    private let now: @Sendable () -> Date
    private var index = LocalIndex()
    private var indexLoaded = false
    private var dirty = false

    /// Am Speicher: liest Gedanken und Themen dort, Index in `<root>/embeddings.bin`.
    public init(store: ThoughtStore, options: Options = Options(), now: @escaping @Sendable () -> Date = Date.init) {
        self.source = .store(store)
        self.options = options
        self.indexURL = store.root.appendingPathComponent("embeddings.bin")
        self.embedder = EmbeddingIndex(preference: options.models)
        self.now = now
    }

    /// Feste Ablage im RAM (Prüfstand, Tests), ohne Datei.
    public init(thoughts: [Thought], topics: [Topic], options: Options = Options(), now: @escaping @Sendable () -> Date = Date.init) {
        self.source = .snapshot(thoughts, topics)
        self.options = options
        self.indexURL = nil
        self.embedder = EmbeddingIndex(preference: options.models)
        self.now = now
    }

    // MARK: CandidateFinding

    public func topicIndex(forText text: String, languages: [String]) async -> (entries: [TopicIndexEntry], full: Bool) {
        let (thoughts, topics) = await snapshot()
        sync(thoughts)
        let query = analyze(text, language: languages.first)
        let summaries = TopicIndex.summaries(topics: topics, thoughts: thoughts)
        let mean = query.vector.flatMap { options.centerVectors ? index.meanVector(model: $0.model, space: $0.space) : nil }
        let clock = now()
        let haystack = TopicMentions.Haystack(text)

        var active: [(entry: TopicIndexEntry, fit: Double, count: Int)] = []
        var provisional: [(entry: TopicIndexEntry, fit: Double, last: Date)] = []
        var mentioned: [(entry: TopicIndexEntry, fit: Double, hits: Int, isActive: Bool, last: Date)] = []
        var activeTotal = 0
        for summary in summaries {
            let fit = TopicIndex.fit(summary: summary, index: index, queryTerms: query.terms, queryVector: query.vector,
                                     mean: mean, cosineFloor: options.cosineFloor)
            let hits = TopicMentions.matches(TopicMentions.terms(summary.topic), in: haystack)
            let entry = TopicIndexEntry(topicID: summary.topic.id, name: summary.topic.title, count: summary.count, hint: fit.hint,
                                        about: summary.topic.describedNote, mentioned: !hits.isEmpty)
            if summary.isActive { activeTotal += 1 }
            if !hits.isEmpty {
                // Namens-Treffer: immer im Index, auch vorläufig oder außerhalb des 60-Tage-Fensters
                mentioned.append((entry, fit.score, hits.count, summary.isActive, summary.lastActivity ?? summary.topic.createdAt))
            } else if summary.isActive {
                active.append((entry, fit.score, summary.count))
            } else if let last = summary.lastActivity, clock.timeIntervalSince(last) <= TopicIndex.provisionalWindow {
                provisional.append((entry, fit.score, last))
            }
        }
        let full = activeTotal >= TopicIndex.maxActive
        let ranked = mentioned.sorted { $0.hits != $1.hits ? $0.hits > $1.hits : $0.fit > $1.fit }
        let pinned = ranked.prefix(TopicIndex.maxMentioned)
        for extra in ranked.dropFirst(TopicIndex.maxMentioned) { // nur bei sehr vielen Treffern
            if extra.isActive { active.append((extra.entry, extra.fit, extra.entry.count)) } else { provisional.append((extra.entry, extra.fit, extra.last)) }
        }
        let pinnedActive = pinned.filter(\.isActive).count
        let sortedActive = active.sorted { $0.fit != $1.fit ? $0.fit > $1.fit : $0.count > $1.count }
            .prefix(max(0, TopicIndex.maxActive - pinnedActive))
        let sortedProvisional = provisional.sorted { $0.fit != $1.fit ? $0.fit > $1.fit : $0.last > $1.last }
            .prefix(max(0, TopicIndex.maxProvisional - (pinned.count - pinnedActive)))
        return (pinned.map(\.entry) + sortedActive.map(\.entry) + sortedProvisional.map(\.entry), full)
    }

    public func candidates(forText text: String, languages: [String], excluding: String) async -> [CandidateEntry] {
        await candidates(forText: text, languages: languages, excluding: excluding, relativeTo: now())
    }

    /// Zeitbezug (`when`, 3-h-Fenster, Aktualität) relativ zur Aufnahmezeit des Gedankens, auch wenn er erst
    /// später verarbeitet wird. Spätere Gedanken zählen nicht als „kürzlich“ (Alter < 0).
    public func candidates(forText text: String, languages: [String], excluding: String,
                           relativeTo reference: Date) async -> [CandidateEntry] {
        let (thoughts, _) = await snapshot()
        sync(thoughts)
        let scored = score(text, language: languages.first, thoughts: thoughts, excluding: excluding, clock: reference)
        let byID = Dictionary(uniqueKeysWithValues: thoughts.map { ($0.id, $0) })
        return select(scored).compactMap { item in
            byID[item.thoughtID].map { entry(for: $0, score: item.score, clock: reference) }
        }
    }

    public func didChange(_ thought: Thought) async {
        loadIndexIfNeeded()
        if let entry = makeEntryIfNeeded(thought) {
            index.upsert(entry)
            dirty = true
        } else if !isIndexable(thought), index[thought.id] != nil {
            index.remove(thought.id)
            dirty = true
        }
        flush()
    }

    // MARK: Zusätze

    /// Alle bewerteten Gedanken, absteigend (E0, Diagnose).
    public func rank(forText text: String, languages: [String], excluding: String) async -> [Scored] {
        let (thoughts, _) = await snapshot()
        sync(thoughts)
        return score(text, language: languages.first, thoughts: thoughts, excluding: excluding, clock: now())
    }

    /// Die Auswahl, die `candidates` zurückgibt, als IDs mit Bewertung.
    public func selection(forText text: String, languages: [String], excluding: String) async -> [Scored] {
        select(await rank(forText: text, languages: languages, excluding: excluding))
    }

    /// Schlagwörter für `thought.keywords` (TF-IDF gegen die Ablage).
    public func keywords(forText text: String, language: String?, limit: Int = 5) -> [String] {
        loadIndexIfNeeded()
        return Keywords.top(Keywords.counts(Keywords.terms(text, language: language)), limit: limit, idf: index.idf)
    }

    /// Index auf die Platte (abgeleitet; Fehler sind unkritisch).
    public func flush() {
        guard dirty, let indexURL else { return }
        dirty = false
        try? FileSafety.writeAtomically(index.encoded(), to: indexURL)
    }

    /// Welches Embedding-Modell gerade genutzt wird (Diagnose/E0).
    public func activeModel(language: String?) -> EmbeddingModel? {
        embedder.availableModel(language: language)
    }

    // MARK: Bewertung

    private func score(_ text: String, language: String?, thoughts: [Thought], excluding: String, clock: Date) -> [Scored] {
        let query = analyze(text, language: language)
        let mean = query.vector.flatMap { options.centerVectors ? index.meanVector(model: $0.model, space: $0.space) : nil }
        var raw: [(thought: Thought, cosine: Double?, bm25: Double)] = []
        for thought in thoughts where thought.id != excluding && isIndexable(thought) {
            guard let entry = index[thought.id] else { continue }
            var cosine: Double?
            if let q = query.vector, let d = entry.vector, q.isComparable(to: d) {
                cosine = Self.adjustedCosine(q.values, d.values, mean: mean, floor: options.cosineFloor)
            }
            raw.append((thought, cosine, index.bm25(query: query.terms, document: entry)))
        }
        let normalizer: Double
        switch options.keywordNormalization {
        case .selfScore: normalizer = index.selfScore(query: query.terms)
        case .maximum: normalizer = raw.map(\.bm25).max() ?? 0
        }
        let relative = options.scoring == .relative && raw.count >= options.relativeMinimumCount
        let cosineStats = Self.meanAndDeviation(raw.compactMap(\.cosine))
        let keywordStats = Self.meanAndDeviation(raw.map(\.bm25))
        return raw.map { item in
            let keyword = normalizer > 0 ? min(1, item.bm25 / normalizer) : 0
            var value: Double
            if relative {
                let zKeyword = (item.bm25 - keywordStats.mean) / keywordStats.deviation
                if let cosine = item.cosine {
                    let zCosine = (cosine - cosineStats.mean) / cosineStats.deviation
                    value = (options.cosineWeight * zCosine + options.keywordWeight * zKeyword) / options.zScale
                } else {
                    value = zKeyword / options.zScale
                }
                value = min(1, max(0, value))
            } else if let cosine = item.cosine {
                value = options.cosineWeight * cosine + options.keywordWeight * keyword
            } else {
                value = keyword // ohne vergleichbares Embedding zählen nur die Schlagwörter
            }
            let age = clock.timeIntervalSince(item.thought.createdAt)
            if age >= 0, age < options.recencyWindow { value += options.recencyBonus }
            let recent = age >= 0 && age <= options.recentWindow
            return Scored(thoughtID: item.thought.id, score: value, cosine: item.cosine, keyword: keyword, isRecent: recent)
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.thoughtID < $1.thoughtID }
    }

    private func select(_ scored: [Scored]) -> [Scored] {
        Self.select(scored, options: options, createdAt: cachedCreatedAt)
    }

    /// ≤ 6 über dem Mindestwert + immer die ≤ 2 neuesten der letzten 3 h, zusammen ≤ 7.
    public static func select(_ scored: [Scored], options: Options, createdAt: [String: Date]) -> [Scored] {
        guard !scored.isEmpty else { return [] }
        let recent = scored.filter(\.isRecent)
            .sorted { (createdAt[$0.thoughtID] ?? .distantPast) > (createdAt[$1.thoughtID] ?? .distantPast) }
            .prefix(options.recentMax)
        let recentIDs = Set(recent.map(\.thoughtID))
        let room = max(0, min(options.maxScored, options.maxTotal - recent.count))
        let above = scored.filter { $0.score >= options.minimumScore && !recentIDs.contains($0.thoughtID) }.prefix(room)
        return (Array(above) + Array(recent)).sorted { $0.score > $1.score }
    }

    static func meanAndDeviation(_ values: [Double]) -> (mean: Double, deviation: Double) {
        guard !values.isEmpty else { return (0, 1) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, max(variance.squareRoot(), 1e-6))
    }

    /// Kosinus, optional um den Mittelwert zentriert und ab `floor` linear auf 0…1 gestreckt.
    static func adjustedCosine(_ a: [Float], _ b: [Float], mean: [Float]?, floor: Double) -> Double {
        var cos: Double
        if let mean, mean.count == a.count, mean.count == b.count {
            cos = EmbeddingVector.cosine(zip(a, mean).map { $0 - $1 }, zip(b, mean).map { $0 - $1 })
        } else {
            cos = EmbeddingVector.cosine(a, b)
        }
        if floor > 0 { cos = (cos - floor) / (1 - floor) }
        return min(1, max(0, cos))
    }

    // MARK: Index

    private var cachedCreatedAt: [String: Date] = [:]

    private func snapshot() async -> ([Thought], [Topic]) {
        let result: ([Thought], [Topic])
        switch source {
        case .snapshot(let thoughts, let topics): result = (thoughts, topics)
        case .store(let store): result = (await store.all(), await store.topics())
        }
        cachedCreatedAt = Dictionary(result.0.map { ($0.id, $0.createdAt) }, uniquingKeysWith: { a, _ in a })
        return result
    }

    private func isIndexable(_ thought: Thought) -> Bool {
        thought.kind != ConversationKind.thoughtKind && thought.deletedAt == nil && thought.state != .recording && !Self.document(thought).isEmpty
    }

    static func document(_ thought: Thought) -> String {
        [thought.title, thought.text].compactMap { $0?.trimmed }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func language(of thought: Thought) -> String? {
        thought.languages.first ?? detectLanguage(document(thought))
    }

    private func contentHash(_ thought: Thought, language: String?) -> UInt64 {
        let model = embedder.availableModel(language: language)?.rawValue ?? "-"
        return StableHash.of(Self.document(thought) + "\u{1}" + (language ?? "") + "\u{1}" + model + "\u{1}"
                             + options.models.map(\.rawValue).joined(separator: ","))
    }

    private func makeEntryIfNeeded(_ thought: Thought) -> LocalIndex.Entry? {
        guard isIndexable(thought) else { return nil }
        let language = Self.language(of: thought)
        let hash = contentHash(thought, language: language)
        if index[thought.id]?.contentHash == hash { return nil }
        let text = Self.document(thought)
        return LocalIndex.Entry(id: thought.id, contentHash: hash, language: language,
                                terms: Keywords.counts(Keywords.terms(text, language: language)),
                                vector: embedder.vector(for: text, language: language))
    }

    private func sync(_ thoughts: [Thought]) {
        loadIndexIfNeeded()
        var present: Set<String> = []
        var refreshed = 0
        for thought in thoughts where isIndexable(thought) {
            present.insert(thought.id)
            if refreshed >= options.maxRefreshPerCall, index[thought.id] != nil { continue }
            if let entry = makeEntryIfNeeded(thought) {
                index.upsert(entry)
                refreshed += 1
                dirty = true
            }
        }
        for id in index.entries.keys where !present.contains(id) {
            index.remove(id)
            dirty = true
        }
        if refreshed > 0 { flush() }
    }

    private func loadIndexIfNeeded() {
        guard !indexLoaded else { return }
        indexLoaded = true
        if let indexURL, let data = try? Data(contentsOf: indexURL), let loaded = LocalIndex.decode(data) {
            index = loaded
        }
    }

    private func analyze(_ text: String, language: String?) -> (terms: [String: Int], vector: EmbeddingVector?) {
        let language = language ?? detectLanguage(text)
        return (Keywords.counts(Keywords.terms(text, language: language)), embedder.vector(for: text, language: language))
    }

    // MARK: Ausgabe

    private func entry(for thought: Thought, score: Double, clock: Date) -> CandidateEntry {
        let text = (thought.text ?? "").replacingOccurrences(of: "\n", with: " ").trimmed
        let excerpt = text.count > options.excerptLength ? String(text.prefix(options.excerptLength)) : text
        return CandidateEntry(thoughtID: thought.id, title: thought.title ?? "", topicID: thought.topicId,
                              when: Self.when(thought.createdAt, now: clock), excerpt: excerpt,
                              localScore: (score * 1000).rounded() / 1000)
    }

    /// „heute 08:10“, „gestern“, „vor 5 Tagen“, „12. Sep.“ (lokal formuliert, §6.3 Punkt 5)
    public static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "HH:mm"
            return "heute " + formatter.string(from: date)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "gestern" }
        if days > 1, days < 7 { return "vor \(days) Tagen" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "d. MMM" : "d. MMM yyyy"
        return formatter.string(from: date)
    }
}
