import Foundation

public actor ConversationProcessor {
    public struct Environment: Sendable {
        public var apiKey: @Sendable () async -> String
        public var mainLanguage: @Sendable () async -> String
        public var vocabulary: @Sendable () async -> [String]
        public init(apiKey: @escaping @Sendable () async -> String, mainLanguage: @escaping @Sendable () async -> String = { "de" }, vocabulary: @escaping @Sendable () async -> [String] = { [] }) {
            self.apiKey = apiKey; self.mainLanguage = mainLanguage; self.vocabulary = vocabulary
        }
    }
    public enum Event: Sendable { case changed(String), progress(String, ConversationProgress), failed(String, String) }
    private let store: ConversationStore
    private let thoughts: ThoughtStore
    private let profiles: VoiceProfileStore
    private let analyzer: any ConversationAnalyzing
    private let environment: Environment
    private let broadcast = Broadcast<Event>()
    public nonisolated var events: AsyncStream<Event> { broadcast.stream }
    private var running: Task<Void, Never>?
    private var rerun = false
    private var timer: Task<Void, Never>?
    public init(store: ConversationStore, thoughts: ThoughtStore, profiles: VoiceProfileStore, analyzer: any ConversationAnalyzing, environment: Environment) {
        self.store = store; self.thoughts = thoughts; self.profiles = profiles; self.analyzer = analyzer; self.environment = environment
    }
    /// Netz, Schlüssel und Vordergrund stoßen dieselbe serielle Warteschlange an.
    public func kick(reason: String = "foreground") {
        if running != nil { rerun = true; return }
        running = Task { await drain() }
    }
    public func waitUntilIdle() async { while let running { await running.value } }
    public func cancelRunning() { running?.cancel(); timer?.cancel() }
    public func retry(_ id: String) async throws {
        try await store.update(id) { $0.state = .captured; $0.status = .init() }
        kick(reason: "retry")
    }
    public func nextRetryDate() async -> Date? { (try? await store.all())?.filter { $0.deletedAt == nil && [.waitingNetwork, .waitingBudget, .waitingLimit].contains($0.state) }.compactMap(\.status.retryAt).min() }
    private func drain() async {
        repeat {
            rerun = false
            let items = (try? await store.all()) ?? []
            for item in items where item.deletedAt == nil && [.captured, .waitingKey, .waitingNetwork, .waitingBudget, .waitingLimit].contains(item.state) {
                if Task.isCancelled { break }
                if let retry = item.status.retryAt, retry > Date() { continue }
                await process(item)
            }
        } while rerun && !Task.isCancelled
        running = nil
        timer?.cancel()
        if let next = await nextRetryDate(), next > Date() {
            timer = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) } catch { return }
                await self?.kick(reason: "retry")
            }
        }
    }
    private func process(_ item: Conversation) async {
        do {
            guard let current = try await store.conversation(item.id), current.deletedAt == nil,
                  let audio = try await store.prepareForAnalysis(item.id) else { return }
            if await thoughts.thought(item.id) == nil {
                try await thoughts.save(Thought(id: item.id, kind: ConversationKind.thoughtKind, createdAt: item.createdAt, trigger: item.trigger, state: .done))
            }
            let topics = await thoughts.topics().filter { $0.mergedInto == nil }
            let input = ConversationAnalysisInput(id: item.id, audio: audio, workDirectory: store.workDirectory(item.id), recordedAt: item.createdAt,
                expectedSpeakers: item.expectedSpeakers, gaps: item.gaps, mainLanguage: await environment.mainLanguage(), vocabulary: await environment.vocabulary(),
                topics: topics.map { .init(topicID: $0.id, name: $0.title, count: 0, hint: [], about: $0.note) }, people: try await profiles.people(), previous: current)
            try await store.update(item.id) { $0.state = .analyzing }
            let broadcast = self.broadcast
            let store = self.store
            let outcome = await analyzer.analyze(input, apiKey: await environment.apiKey()) { progress in
                broadcast.yield(.progress(item.id, progress))
                Task { try? await store.update(item.id) { if $0.state == .analyzing { $0.progress = progress } } }
            }
            guard let latest = try await store.conversation(item.id), latest.deletedAt == nil else { return }
            switch outcome {
            case .done(let result):
                try await apply(result, id: item.id, state: .done, retryAt: nil, message: nil)
                try await store.compactAudio(item.id)
            case .partial(let result, let state, let retry, let message): try await apply(result, id: item.id, state: state, retryAt: retry, message: message)
            case .wait(let state, let retry, let message):
                try await store.update(item.id) { $0.state = state; $0.status.retryAt = retry; $0.status.message = message }
            case .empty: try await store.update(item.id) { $0.state = .empty; $0.progress = nil }
            case .failed(let code):
                try await store.update(item.id) { $0.status.attempts += 1; $0.state = $0.status.attempts >= 3 ? .needsAttention : .waitingNetwork; $0.status.retryAt = Date().addingTimeInterval(60); $0.status.message = code }
            }
            broadcast.yield(.changed(item.id))
        } catch {
            _ = try? await store.update(item.id) { $0.state = .needsAttention; $0.status.message = "store-failed" }
            broadcast.yield(.failed(item.id, "store-failed"))
        }
    }
    private func apply(_ result: ConversationAnalysis, id: String, state: ConversationState, retryAt: Date?, message: String?) async throws {
        if let transcript = result.transcript { try await store.saveTranscript(transcript, for: id) }
        try await store.saveVoiceprints(result.speakerPrints, for: id)
        let item = try await store.update(id) { item in
            guard item.deletedAt == nil else { return }
            if let model = result.model {
                item.ai = .init(model: model, promptVersion: 1, tokens: result.usage?.total ?? 0, at: Date())
            }
            item.stagesDone = result.stagesDone; item.state = state; item.progress = nil
            item.status.retryAt = retryAt; item.status.message = message
            if item.titleOwner != .user, let title = result.title { item.title = title; item.titleOwner = .ai }
            if let summary = result.summary { item.summary = summary }
            item.speakers = result.speakers.map { speaker in item.speakers.first { $0.id == speaker.id && $0.nameSource == .user } ?? speaker }
        }
        guard let item, item.deletedAt == nil, let summary = result.summary else { return }
        if await thoughts.thought(id) == nil {
            try await thoughts.save(Thought(id: id, kind: ConversationKind.thoughtKind, createdAt: item.createdAt, durationMs: item.durationMs, trigger: item.trigger, state: .done))
        }
        let topic: Topic?
        switch result.topic {
        case .existing(let id): topic = await thoughts.resolveTopic(id)
        case .new(let name, let icon):
            let all = await thoughts.topics()
            let same = TopicHygiene.sameNamed(name, among: all)
            topic = same.count == 1 ? same[0] : (same.isEmpty && TopicHygiene.isValidNewName(name) ? Topic(title: name, icon: icon, owner: .ai) : nil)
        default: topic = nil
        }
        let drafts = result.tasks.map { draft in
            let due = DueDate.resolved(draft.dueHint, reference: item.createdAt, now: Date())
            return ThoughtTask(text: draft.text, quote: draft.quote, dueHint: draft.dueHint, dueAt: due?.date, dueHasTime: due?.hasTime, owner: .ai)
        }
        try await thoughts.update(id, topic: topic) { thought, topicID in
            guard thought.deletedAt == nil, thought.kind == ConversationKind.thoughtKind else { return }
            if thought.titleOwner != .user { thought.title = item.title; thought.titleOwner = .ai }
            if thought.textOwner != .user { thought.text = ([summary.overview] + summary.points.map { "• " + $0 }).joined(separator: "\n"); thought.textOwner = .ai }
            if thought.topicOwner != .user { thought.topicId = topicID; thought.topicOwner = .ai }
            let kept = thought.tasks.filter { $0.owner == .user || $0.done }
            thought.tasks = kept + drafts.filter { draft in !kept.contains { RawText.sameTask($0, draft) } }
            thought.ai = item.ai
            thought.state = .done
        }
    }
    public func housekeeping(now: Date = Date()) async throws {
        for item in try await store.all() {
            if let deleted = item.deletedAt, now.timeIntervalSince(deleted) >= 30 * 86400 { try await purge(item.id) }
        }
        try await store.housekeeping(now: now)
    }
    public func delete(_ id: String) async throws {
        try await store.delete(id)
        if await thoughts.thought(id) != nil { try await thoughts.delete(id) }
    }
    public func restore(_ id: String) async throws {
        try await store.restore(id)
        if await thoughts.thought(id) != nil { try await thoughts.restore(id) }
    }
    public func purge(_ id: String) async throws { try await store.purge(id); await thoughts.purge(id) }
}
