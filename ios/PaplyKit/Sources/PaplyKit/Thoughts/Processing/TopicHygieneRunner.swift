import Foundation

/// Seltene Themen-Vorschläge (KONZEPT §6.10 Punkt 5): höchstens 1× je 7 Tage, nur ab 8 aktiven Themen,
/// lokal Paare suchen, dann **ein** Aufruf an `gpt-oss-20b` (low). Gezeigt werden höchstens 2 Vorschläge;
/// nichts wird automatisch angewandt. Prompt, Paarsuche und Prüfung liegen in `TopicHygiene` (H1).
/// Rechte: schreibt nur `topic-suggestions.json` und `lastHygieneAt` – nie Themen oder Gedanken.
public enum TopicHygieneRunner {
    public static let model = "openai/gpt-oss-20b"

    public enum Outcome: Sendable, Equatable {
        /// Vorschläge gespeichert (auch leer: keine Paare)
        case suggestions([TopicSuggestion])
        /// noch nicht fällig (7 Tage, 8 aktive Themen)
        case notDue
        /// ohne Schlüssel, Netz oder Budget später erneut
        case skipped(String)
    }

    /// `force` = „Themenpflege jetzt prüfen“ (Entwicklerbereich): ohne 7-Tage- und 8-Themen-Grenze.
    public static func run(store: ThoughtStore, ledger: TokenLedger, apiKey: String?, force: Bool = false,
                           now: Date = Date()) async -> Outcome {
        await run(store: store, ledger: ledger, apiKey: apiKey, force: force, transport: .shared,
                  baseURL: GroqClient.defaultBaseURL, now: now)
    }

    package static func run(store: ThoughtStore, ledger: TokenLedger, apiKey: String?, force: Bool,
                            transport: GroqTransport, baseURL: URL, now: Date) async -> Outcome {
        let thoughts = await store.all()
        let topics = await store.topics()
        let info = await store.topicsInfo()
        let summaries = TopicIndex.summaries(topics: topics, thoughts: thoughts).filter(\.isActive)
        guard force || TopicHygiene.isSuggestionDue(activeTopics: summaries.count, lastRun: info.lastHygieneAt, now: now) else {
            return .notDue
        }
        let byID = Dictionary(uniqueKeysWithValues: thoughts.map { ($0.id, $0) })
        let profiles = summaries.map { summary -> TopicHygiene.Profile in
            let members = summary.memberIDs.compactMap { byID[$0] }.sorted { $0.createdAt > $1.createdAt }
            var counts: [String: Int] = [:]
            for keyword in members.flatMap(\.keywords) { counts[keyword, default: 0] += 1 }
            let keywords = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5).map(\.key)
            return TopicHygiene.Profile(topicID: summary.topic.id, name: summary.topic.title, count: summary.count,
                                        keywords: keywords, exampleTitles: members.compactMap(\.title).prefix(3).map { $0 },
                                        language: members.first?.languages.first, isUserDefined: summary.topic.isUserDefined)
        }
        let protected = Set(profiles.filter(\.isUserDefined).map(\.topicID))
        let declined = Set(info.declinedMerges.map { $0.sorted() })
        let pairs = TopicHygiene.candidatePairs(profiles, declined: declined).map { (a: $0.a, b: $0.b) }
        guard !pairs.isEmpty else {
            try? await store.setLastHygieneAt(now)
            try? await store.setPendingSuggestions([])
            return .suggestions([])
        }
        guard let key = apiKey?.trimmed, !key.isEmpty else { return .skipped("key") }
        guard let schema = try? JSONSerialization.data(withJSONObject: TopicHygiene.suggestionSchema, options: [.sortedKeys]) else {
            return .skipped("schema")
        }
        let request = StructuredChatRequest(model: model, system: TopicHygiene.suggestionSystem,
                                            user: TopicHygiene.suggestionMessage(pairs: pairs, profiles: profiles),
                                            schemaName: "topic_pairs", schema: schema, maxCompletionTokens: 1_200)
        let estimate = (request.system.utf8.count + request.user.utf8.count + schema.count) / 3 + request.maxCompletionTokens + 256
        let reservation: TokenLedger.Reservation
        do {
            reservation = try await ledger.reserve(model: model, amount: estimate, unit: .tokens)
        } catch {
            return .skipped("budget")
        }
        let client = GroqClient(apiKey: key, transport: transport, baseURL: baseURL)
        let response = await client.chatStructured(request)
        switch response {
        case .success(let reply):
            await ledger.settle(reservation, actual: reply.usage?.total ?? estimate)
            guard reply.finishReason == "stop", let content = reply.content else { return .skipped("invalid") }
            let suggestions = TopicHygiene.validateSuggestions(content, asked: pairs, protected: protected)
            try? await store.setPendingSuggestions(suggestions)
            try? await store.setLastHygieneAt(now)
            return .suggestions(suggestions)
        case .failure(let failure):
            await ledger.settle(reservation, actual: 0)
            return .skipped(failure.code)
        }
    }
}
