import Foundation

public actor ConversationProcessor: ConversationEditing {
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
    private var locked = false
    private var lockWaiters: [CheckedContinuation<Void, Never>] = []
    private func lock() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { lockWaiters.append($0) }
    }
    private func unlock() {
        if lockWaiters.isEmpty { locked = false }
        else { lockWaiters.removeFirst().resume() }
    }
    private var analysis: (id: String, task: Task<ConversationAnalysisOutcome, Never>)?
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
    public func cancelRunning() { analysis?.task.cancel(); running?.cancel(); timer?.cancel() }
    public func retry(_ id: String) async throws {
        try await store.update(id) { $0.state = .captured; $0.status = .init() }
        kick(reason: "retry")
    }
    public func nextRetryDate() async -> Date? { (try? await store.all())?.filter { $0.deletedAt == nil && [.waitingNetwork, .waitingBudget, .waitingLimit].contains($0.state) }.compactMap(\.status.retryAt).min() }
    private func drain() async {
        try? await reconcileDeletionStates()
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
            let key = await environment.apiKey()
            let analyzer = self.analyzer
            guard try await store.conversation(item.id)?.deletedAt == nil,
                  try await store.conversation(item.id) != nil else { return }
            let task = Task { await analyzer.analyze(input, apiKey: key) { progress in
                broadcast.yield(.progress(item.id, progress))
                Task { try? await store.update(item.id) { if $0.state == .analyzing { $0.progress = progress } } }
            } }
            analysis = (item.id, task)
            let outcome = await task.value
            analysis = nil
            do {
                await lock()
                defer { unlock() }
                guard let latest = try await store.conversation(item.id), latest.deletedAt == nil else { return }
                switch outcome {
                case .done(let result):
                    try await apply(result, id: item.id, state: .done, retryAt: nil, message: nil)
                case .partial(let result, let state, let retry, let message): try await apply(result, id: item.id, state: state, retryAt: retry, message: message)
                case .wait(let state, let retry, let message):
                    try await store.update(item.id) { $0.state = state; $0.status.retryAt = retry; $0.status.message = message }
                case .empty: try await store.update(item.id) { $0.state = .empty; $0.progress = nil }
                case .failed(let code):
                    try await store.update(item.id) { $0.status.attempts += 1; $0.state = $0.status.attempts >= 3 ? .needsAttention : .waitingNetwork; $0.status.retryAt = Date().addingTimeInterval(60); $0.status.message = code }
                }
            }
            if case .done = outcome { try await store.compactAudio(item.id) }
            broadcast.yield(.changed(item.id))
        } catch {
            _ = try? await store.update(item.id) { $0.state = .needsAttention; $0.status.message = "store-failed" }
            broadcast.yield(.failed(item.id, "store-failed"))
        }
    }
    private func apply(_ result: ConversationAnalysis, id: String, state: ConversationState, retryAt: Date?, message: String?) async throws {
        var result = result
        let edits = try readEdits(id)
        func target(_ source: String) -> String {
            var next = source
            var seen = Set<String>()
            while let merged = edits.merges[next], seen.insert(next).inserted { next = merged }
            return next
        }
        if var transcript = result.transcript {
            let previous = try await store.transcript(id)
            for i in transcript.utterances.indices {
                if let user = previous?.utterances.first(where: {
                    $0.speakerOwner == .user && ConversationUtteranceMatch.matches($0, transcript.utterances[i])
                }) {
                    transcript.utterances[i].speakerID = user.speakerID
                    transcript.utterances[i].speakerOwner = .user
                    continue
                }
                let source = transcript.utterances[i].speakerID
                if target(source) != source {
                    transcript.utterances[i].speakerID = target(source)
                    transcript.utterances[i].speakerOwner = .user
                }
            }
            result.transcript = transcript
        }
        let totals = result.speakers.reduce(into: [String: Double]()) { totals, speaker in
            totals[target(speaker.id), default: 0] += speaker.speechSeconds
        }
        result.speakers = result.speakers.filter { target($0.id) == $0.id }.map {
            var speaker = $0
            speaker.speechSeconds = totals[speaker.id] ?? speaker.speechSeconds
            if edits.rejected.contains(speaker.id) { speaker.suggestion = nil }
            return speaker
        }
        func replaceReferences(_ text: String) -> String {
            var text = text
            for source in edits.merges.keys {
                text = text.replacingOccurrences(of: "[\(source)]", with: "[\(target(source))]")
            }
            return text
        }
        result.title = result.title.map(replaceReferences)
        result.tasks = result.tasks.map {
            var task = $0
            task.text = replaceReferences(task.text)
            return task
        }
        if var summary = result.summary {
            summary.overview = replaceReferences(summary.overview)
            summary.points = summary.points.map(replaceReferences)
            for i in summary.commitments.indices {
                summary.commitments[i].speakerID = target(summary.commitments[i].speakerID)
                summary.commitments[i].text = replaceReferences(summary.commitments[i].text)
            }
            result.summary = summary
        }
        if !edits.merges.isEmpty {
            let stored = try await store.voiceprints(id)
            for speaker in result.speakers {
                if let print = stored[speaker.id] { result.speakerPrints[speaker.id] = print }
            }
            result.speakerPrints = result.speakerPrints.filter { target($0.key) == $0.key }
        }
        if let transcript = result.transcript { try await store.saveTranscript(transcript, for: id) }
        try await store.saveVoiceprints(result.speakerPrints, for: id)
        let applied = result
        let item = try await store.update(id) { item in
            guard item.deletedAt == nil else { return }
            if let model = applied.model {
                item.ai = .init(model: model, promptVersion: 1, tokens: applied.usage?.total ?? 0, at: Date())
            }
            item.stagesDone = applied.stagesDone; item.state = state; item.progress = nil
            item.status.retryAt = retryAt; item.status.message = message
            if item.titleOwner != .user, let title = applied.title { item.title = title; item.titleOwner = .ai }
            if let summary = applied.summary { item.summary = summary }
            item.speakers = applied.speakers.map { speaker in item.speakers.first { $0.id == speaker.id && $0.nameSource == .user } ?? speaker }
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
        try await thoughts.update(id, topic: topic) { thought, topicID in
            guard thought.deletedAt == nil, thought.kind == ConversationKind.thoughtKind else { return }
            if thought.titleOwner != .user { thought.title = item.title.map { ConversationText.render($0, speakers: item.speakers) }; thought.titleOwner = .ai }
            if thought.textOwner != .user { thought.text = ConversationText.render(([summary.overview] + summary.points.map { "• " + $0 }).joined(separator: "\n"), speakers: item.speakers); thought.textOwner = .ai }
            if thought.topicOwner != .user { thought.topicId = topicID; thought.topicOwner = .ai }
            thought.tasks = ConversationTasks.derive(item, preserving: thought.tasks)
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
        if analysis?.id == id { analysis?.task.cancel() }
        await lock()
        defer { unlock() }
        try await setDeleted(id, deleted: true)
    }
    public func restore(_ id: String) async throws {
        await lock()
        defer { unlock() }
        try await setDeleted(id, deleted: false)
    }
    public func purge(_ id: String) async throws {
        if analysis?.id == id { analysis?.task.cancel() }
        await lock()
        defer { unlock() }
        try await store.purge(id)
        await thoughts.purge(id)
    }

    private func setDeleted(_ id: String, deleted: Bool) async throws {
        guard try await store.conversation(id) != nil else { return }
        let journal = store.directory(id).appendingPathComponent("deletion.json")
        try FileSafety.writeAtomically(try JSONEncoder().encode(deleted), to: journal)
        if deleted {
            if analysis?.id == id { analysis?.task.cancel() }
            try await store.delete(id)
        } else { try await store.restore(id) }
        if let thought = await thoughts.thought(id) {
            if deleted && thought.deletedAt == nil { try await thoughts.delete(id) }
            if !deleted && thought.deletedAt != nil { try await thoughts.restore(id) }
        }
        try FileManager.default.removeItem(at: journal)
    }

    /// Beim Start aufrufen; ein unterbrochener Doppelschritt wird zuerst beendet.
    public func reconcileDeletionStates() async throws {
        await lock()
        defer { unlock() }
        for item in try await store.all() {
            if item.deletedAt == nil { try await renderThought(item.id) }
            let journal = store.directory(item.id).appendingPathComponent("deletion.json")
            if FileSafety.exists(journal) {
                let deleted = try JSONDecoder().decode(Bool.self, from: Data(contentsOf: journal))
                try await setDeleted(item.id, deleted: deleted)
            } else if let thought = await thoughts.thought(item.id),
                      (thought.deletedAt != nil) != (item.deletedAt != nil) {
                try await setDeleted(item.id, deleted: thought.updatedAt > item.updatedAt ? thought.deletedAt != nil : item.deletedAt != nil)
            }
        }
    }

    /// Nach Löschen/Wiederherstellen in der Gedanken-Ablage aufrufen.
    public func synchronizeLinkedThought(_ id: String) async throws {
        await lock()
        defer { unlock() }
        guard let thought = await thoughts.thought(id), thought.kind == ConversationKind.thoughtKind else { return }
        try await setDeleted(id, deleted: thought.deletedAt != nil)
    }

    private struct Edits: Codable {
        var rejected: Set<String> = []
        var merges: [String: String] = [:]
        var tasks: [String: String] = [:]
    }
    private func readEdits(_ id: String) throws -> Edits {
        guard ThoughtStore.isValidID(id) else { throw ThoughtStoreError.invalidID }
        let file = store.directory(id).appendingPathComponent("edits.json")
        return FileSafety.exists(file) ? try ThoughtJSON.decoder().decode(Edits.self, from: Data(contentsOf: file)) : Edits()
    }
    private func writeEdits(_ edits: Edits, _ id: String) throws {
        try FileSafety.writeAtomically(try ThoughtJSON.encoder().encode(edits), to: store.directory(id).appendingPathComponent("edits.json"))
    }
    private func renderThought(_ id: String) async throws {
        if let old = try await store.conversation(id), old.summary?.taskCatalogVersion == nil,
           let linked = await thoughts.thought(id), old.summary != nil {
            try await store.update(id) { item in
                for task in linked.tasks where !(item.summary?.commitments.contains { $0.id == task.id } ?? false) {
                    item.summary?.commitments.append(.init(id: task.id, speakerID: "shared", text: task.text, quote: task.quote, dueHint: task.dueHint))
                }
                item.summary?.taskCatalogVersion = 1
            }
        }
        guard let item = try await store.conversation(id) else { return }
        try await thoughts.update(id) { thought in
            if thought.titleOwner != .user {
                thought.title = item.title.map { ConversationText.render($0, speakers: item.speakers) }
            }
            if thought.textOwner != .user, let summary = item.summary {
                thought.text = ConversationText.render(([summary.overview] + summary.points.map { "• " + $0 }).joined(separator: "\n"), speakers: item.speakers)
            }
            thought.tasks = ConversationTasks.derive(item, preserving: thought.tasks)
        }
        broadcast.yield(.changed(id))
    }

    public func nameSpeaker(_ conversationID: String, speakerID: String, as identity: SpeakerIdentity, rememberVoice: Bool) async throws {
        await lock()
        defer { unlock() }
        guard let item = try await store.conversation(conversationID), item.speakers.contains(where: { $0.id == speakerID }) else { throw ThoughtStoreError.notFound }
        let person: VoicePerson
        switch identity {
        case .owner:
            person = try await profiles.people().first { $0.isOwner }!
        case .person(let id):
            guard let found = try await profiles.people().first(where: { $0.id == id }) else { throw ThoughtStoreError.notFound }
            person = found
        case .newPerson(let name):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ThoughtStoreError.unavailable }
            person = try await profiles.create(name: name)
        }
        if rememberVoice, let print = try await store.voiceprints(conversationID)[speakerID] {
            try await profiles.add(print, to: person.id)
        }
        try await store.update(conversationID) { item in
            guard let i = item.speakers.firstIndex(where: { $0.id == speakerID }) else { return }
            item.speakers[i].personID = person.id
            item.speakers[i].name = person.isOwner ? nil : person.name
            item.speakers[i].nameSource = .user
            item.speakers[i].suggestion = nil
            if person.isOwner { item.speakers[i].colorIndex = 0 }
        }
        try await renderThought(conversationID)
    }

    public func rejectSuggestion(_ conversationID: String, speakerID: String) async throws {
        await lock()
        defer { unlock() }
        var edits = try readEdits(conversationID)
        edits.rejected.insert(speakerID)
        try writeEdits(edits, conversationID)
        try await store.update(conversationID) { item in
            if let i = item.speakers.firstIndex(where: { $0.id == speakerID }) { item.speakers[i].suggestion = nil }
        }
        try await renderThought(conversationID)
    }

    public func reassignUtterance(_ conversationID: String, utteranceID: String, to speakerID: String) async throws {
        await lock()
        defer { unlock() }
        guard let item = try await store.conversation(conversationID), item.speakers.contains(where: { $0.id == speakerID }),
              var transcript = try await store.transcript(conversationID),
              let i = transcript.utterances.firstIndex(where: { $0.id == utteranceID }) else { throw ThoughtStoreError.notFound }
        transcript.utterances[i].speakerID = speakerID
        transcript.utterances[i].speakerOwner = .user
        transcript.utterances[i].uncertain = false
        try await store.saveTranscript(transcript, for: conversationID)
        try await renderThought(conversationID)
    }

    public func rename(_ conversationID: String, title: String) async throws {
        await lock()
        defer { unlock() }
        try await store.update(conversationID) { $0.title = title; $0.titleOwner = .user }
        try await renderThought(conversationID)
    }

    public func mergeSpeakers(_ conversationID: String, from: String, into: String) async throws {
        await lock()
        defer { unlock() }
        guard from != into, let item = try await store.conversation(conversationID),
              let source = item.speakers.first(where: { $0.id == from }),
              item.speakers.contains(where: { $0.id == into }) else { throw ThoughtStoreError.notFound }
        var edits = try readEdits(conversationID)
        edits.merges[from] = into
        for key in edits.tasks.keys { edits.tasks[key] = edits.tasks[key]?.replacingOccurrences(of: "[\(from)]", with: "[\(into)]") }
        try writeEdits(edits, conversationID)
        if var transcript = try await store.transcript(conversationID) {
            for i in transcript.utterances.indices where transcript.utterances[i].speakerID == from {
                transcript.utterances[i].speakerID = into
                transcript.utterances[i].speakerOwner = .user
            }
            try await store.saveTranscript(transcript, for: conversationID)
        }
        var prints = try await store.voiceprints(conversationID)
        if let a = prints[from] {
            if var b = prints[into], a.model == b.model, a.vector.count == b.vector.count {
                let vector = zip(a.vector, b.vector).map { Float(a.seconds) * $0 + Float(b.seconds) * $1 }
                let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
                if norm > 0 { b.vector = vector.map { $0 / norm } }
                b.seconds += a.seconds
                prints[into] = b
            } else if prints[into] == nil { prints[into] = a }
        }
        prints[from] = nil
        try await store.saveVoiceprints(prints, for: conversationID)
        try await store.update(conversationID) { item in
            item.speakers.removeAll { $0.id == from }
            if let i = item.speakers.firstIndex(where: { $0.id == into }) {
                item.speakers[i].speechSeconds += source.speechSeconds
                if source.isOwner {
                    item.speakers[i].personID = VoicePerson.ownerID
                    item.speakers[i].nameSource = .user
                    item.speakers[i].name = nil
                }
            }
            func replace(_ text: String) -> String { text.replacingOccurrences(of: "[\(from)]", with: "[\(into)]") }
            item.title = item.title.map(replace)
            if var summary = item.summary {
                summary.overview = replace(summary.overview)
                summary.points = summary.points.map(replace)
                for i in summary.commitments.indices {
                    summary.commitments[i].text = replace(summary.commitments[i].text)
                    if summary.commitments[i].speakerID == from { summary.commitments[i].speakerID = into }
                }
                item.summary = summary
            }
        }
        try await renderThought(conversationID)
    }
}
