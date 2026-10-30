import Foundation
import PaplyKit
import Synchronization

// E0 (KONZEPT §8.2): Kandidatensuche und Themen-Passung lokal gegen den Bewertungssatz, ohne Groq.
//
//   paply-bench candidates [Fixture-Ordner]
//
// Misst je Variante (nur Schlagwörter, Satz-Embedding, kontextuelles Embedding, Mischung) den Recall der
// Pflicht-Verwandten unter den gesendeten Kandidaten (≤ 6 über dem Mindestwert + ≤ 2 der letzten 3 h) und
// unter den Top 6 nach Wert, die mittlere Zahl gesendeter Kandidaten und die Themen-Passung (Rang des
// erwarteten Themas im Themen-Index). Ausgabe Markdown für EVAL.md, Abschnitt E0.

struct E0Fixture {
    struct Case {
        var id: String
        var recordedAt: Date
        var transcript: String
        var languages: [String]
        var required: [[String]]
        var optional: [[String]]
        var expectedTopics: [String]
    }

    var thoughts: [Thought]
    var topics: [Topic]
    var cases: [Case]

    static func load(_ directory: URL) throws -> E0Fixture {
        let store = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("store-a.json"))) as! [String: Any]
        let decoder = ThoughtJSON.decoder()
        let thoughts = try (store["thoughts"] as! [[String: Any]]).map { raw -> Thought in
            var item = raw
            item["keywords"] = item["keywords"] ?? []
            item["status"] = item["status"] ?? ["attempts": 0]
            item["schemaVersion"] = item["schemaVersion"] ?? 1
            return try decoder.decode(Thought.self, from: JSONSerialization.data(withJSONObject: item))
        }
        let topicsDoc = store["topics"] as! [String: Any]
        let topics = try (topicsDoc["topics"] as! [[String: Any]]).map {
            try decoder.decode(Topic.self, from: JSONSerialization.data(withJSONObject: $0))
        }
        var cases: [Case] = []
        let lines = try String(contentsOf: directory.appendingPathComponent("eval.jsonl"), encoding: .utf8).split(separator: "\n")
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
            let meta = object["meta"] as! [String: Any]
            let expect = object["expect"] as! [String: Any]
            let related = expect["related"] as? [[String: Any]] ?? []
            func groups(_ status: String) -> [[String]] {
                related.filter { ($0["status"] as? String) == status }.map { $0["ids"] as? [String] ?? [] }
            }
            let topic = expect["topic"] as? [String: Any] ?? [:]
            var expectedTopics: [String] = []
            if (topic["choice"] as? String) == "existing", let id = topic["id"] as? String { expectedTopics.append(id) }
            for extra in topic["alsoAccept"] as? [Any] ?? [] {
                if let dict = extra as? [String: Any], let id = dict["id"] as? String { expectedTopics.append(id) }
            }
            cases.append(Case(id: object["id"] as! String,
                              recordedAt: Date(timeIntervalSince1970: (object["recordedAt"] as! Double) / 1000),
                              transcript: object["transcript"] as! String,
                              languages: meta["spokenLanguages"] as? [String] ?? [],
                              required: groups("required"), optional: groups("optional"),
                              expectedTopics: (topic["choice"] as? String) == "existing" ? expectedTopics : []))
        }
        return E0Fixture(thoughts: thoughts, topics: topics, cases: cases)
    }
}

struct E0Variant {
    var name: String
    var options: CandidateFinder.Options
}

struct E0Outcome {
    var name: String
    /// je Fall: bewertete Liste (absteigend)
    var ranked: [String: [CandidateFinder.Scored]]
    /// Rang des erwarteten Themas (1 = vorne), nil = nicht im Index
    var topicRanks: [String: Int?]
    var model: String
    var ms: Double
}

func runE0Variant(_ variant: E0Variant, fixture: E0Fixture) async -> E0Outcome {
    let clock = Mutex(Date())
    let finder = CandidateFinder(thoughts: fixture.thoughts, topics: fixture.topics, options: variant.options,
                                 now: { clock.withLock { $0 } })
    var ranked: [String: [CandidateFinder.Scored]] = [:]
    var topicRanks: [String: Int?] = [:]
    let start = Date()
    for item in fixture.cases {
        clock.withLock { $0 = item.recordedAt }
        ranked[item.id] = await finder.rank(forText: item.transcript, languages: item.languages, excluding: "")
        if !item.expectedTopics.isEmpty {
            let index = await finder.topicIndex(forText: item.transcript, languages: item.languages)
            let position = index.entries.firstIndex { item.expectedTopics.contains($0.topicID) }
            topicRanks[item.id] = position.map { $0 + 1 }
        }
    }
    let model = await finder.activeModel(language: "de")?.rawValue ?? "–"
    return E0Outcome(name: variant.name, ranked: ranked, topicRanks: topicRanks, model: variant.options.models.isEmpty ? "–" : model,
                     ms: Date().timeIntervalSince(start) * 1000 / Double(fixture.cases.count))
}

struct E0Score {
    var hits = 0
    var total = 0
    var optionalHits = 0
    var optionalTotal = 0
    var sent = 0
    var cases = 0
    var misses: [String] = []
    var recall: Double { total == 0 ? 0 : Double(hits) / Double(total) }
    var meanSent: Double { cases == 0 ? 0 : Double(sent) / Double(cases) }
}

func scoreE0(_ outcome: E0Outcome, fixture: E0Fixture, options: CandidateFinder.Options, topSixOnly: Bool = false) -> E0Score {
    let createdAt = Dictionary(uniqueKeysWithValues: fixture.thoughts.map { ($0.id, $0.createdAt) })
    var score = E0Score()
    for item in fixture.cases {
        let ranked = outcome.ranked[item.id] ?? []
        let chosen = topSixOnly ? Array(ranked.prefix(6)) : CandidateFinder.select(ranked, options: options, createdAt: createdAt)
        let ids = Set(chosen.map(\.thoughtID))
        score.sent += chosen.count
        score.cases += 1
        for group in item.required {
            score.total += 1
            if group.contains(where: ids.contains) { score.hits += 1 } else { score.misses.append(item.id) }
        }
        for group in item.optional {
            score.optionalTotal += 1
            if group.contains(where: ids.contains) { score.optionalHits += 1 }
        }
    }
    return score
}

func e0Main(_ arguments: [String]) async {
    let directory = arguments.first.map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/Thoughts")
    let fixture: E0Fixture
    do { fixture = try E0Fixture.load(directory) } catch { fail("Fixtures nicht lesbar: \(error)") }
    print("E0: \(fixture.thoughts.count) Gedanken, \(fixture.topics.count) Themen, \(fixture.cases.count) Fälle, "
          + "\(fixture.cases.reduce(0) { $0 + $1.required.count }) Pflicht-Verwandte\n")

    func options(_ models: [EmbeddingModel], center: Bool = true, floor: Double = 0,
                 normalization: CandidateFinder.KeywordNormalization = .selfScore,
                 scoring: CandidateFinder.Scoring = .absolute) -> CandidateFinder.Options {
        var o = CandidateFinder.Options()
        o.scoring = scoring
        o.models = models
        o.centerVectors = center
        o.cosineFloor = floor
        o.keywordNormalization = normalization
        return o
    }
    let only = ProcessInfo.processInfo.environment["E0_ONLY"]
    let variants = [
        E0Variant(name: "absolut: Schlagwörter (BM25)", options: options([])),
        E0Variant(name: "absolut: Satz-Embedding + BM25 (Plan §6.3)", options: options([.sentence], center: false)),
        E0Variant(name: "absolut: kontextuell + BM25", options: options([.contextual], center: false)),
        E0Variant(name: "absolut: kontextuell zentriert + BM25", options: options([.contextual])),
        E0Variant(name: "relativ: Schlagwörter (Rückfall ohne Modell)", options: options([], scoring: .relative)),
        E0Variant(name: "relativ: Satz-Embedding + BM25", options: options([.sentence], center: false, scoring: .relative)),
        E0Variant(name: "relativ: kontextuell zentriert + BM25", options: options([.contextual], scoring: .relative)),
        E0Variant(name: "relativ: kontextuell + BM25 (Standard)", options: CandidateFinder.Options()),
    ].filter { only == nil || $0.name.contains(only!) }
    var outcomes: [(E0Variant, E0Outcome)] = []
    for variant in variants {
        outcomes.append((variant, await runE0Variant(variant, fixture: fixture)))
    }

    print("| Variante | Modell | Recall gesendet | Recall Top 6 | optional gesendet | Ø gesendet | Thema Top 1 / Top 3 | ms/Fall | verfehlt |")
    print("|---|---|---|---|---|---|---|---|---|")
    for (variant, outcome) in outcomes {
        let sent = scoreE0(outcome, fixture: fixture, options: variant.options)
        let top = scoreE0(outcome, fixture: fixture, options: variant.options, topSixOnly: true)
        let ranks = outcome.topicRanks.values
        let top1 = ranks.filter { $0 == 1 }.count, top3 = ranks.filter { ($0 ?? 99) <= 3 }.count
        print(String(format: "| %@ | %@ | %d/%d (%.0f %%) | %d/%d (%.0f %%) | %d/%d | %.1f | %d / %d von %d | %.0f | %@ |",
                     variant.name, outcome.model, sent.hits, sent.total, sent.recall * 100, top.hits, top.total, top.recall * 100,
                     sent.optionalHits, sent.optionalTotal, sent.meanSent, top1, top3, ranks.count, outcome.ms,
                     sent.misses.isEmpty ? "–" : sent.misses.joined(separator: " ")))
    }

    print("\nMindestwert (Recall gesendet / Ø gesendet):\n")
    let minimums = [0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5]
    print("| Variante | " + minimums.map { String(format: "%.2f", $0) }.joined(separator: " | ") + " |")
    print("|---|" + minimums.map { _ in "---|" }.joined())
    for (variant, outcome) in outcomes {
        let cells = minimums.map { minimum -> String in
            var o = variant.options
            o.minimumScore = minimum
            let s = scoreE0(outcome, fixture: fixture, options: o)
            return String(format: "%.0f %% / %.1f", s.recall * 100, s.meanSent)
        }
        print("| \(variant.name) | " + cells.joined(separator: " | ") + " |")
    }

    // Abstand Ziel ↔ Rauschen: bester Wert ohne jeden erwarteten Bezug (Fälle ohne Pflicht/optional) gegen Ziel-Werte
    print("\nTrennung (Rauschen = bester Wert in Fällen ohne erwarteten Bezug; Ziel = Wert des Pflicht-Ziels):\n")
    print("| Variante | Rauschen Median | Rauschen p90 | Rauschen max | Ziel min | Ziel Median | Ziele über Rauschen-p90 |")
    print("|---|---|---|---|---|---|---|")
    for (variant, outcome) in outcomes {
        var noise: [Double] = []
        var targets: [Double] = []
        for item in fixture.cases {
            let ranked = outcome.ranked[item.id] ?? []
            if item.required.isEmpty && item.optional.isEmpty {
                noise.append(ranked.first?.score ?? 0)
            }
            for group in item.required {
                targets.append(ranked.filter { group.contains($0.thoughtID) }.map(\.score).max() ?? 0)
            }
        }
        noise.sort()
        targets.sort()
        func pct(_ list: [Double], _ p: Double) -> Double { list.isEmpty ? 0 : list[min(list.count - 1, Int(Double(list.count - 1) * p))] }
        let p90 = pct(noise, 0.9)
        print(String(format: "| %@ | %.3f | %.3f | %.3f | %.3f | %.3f | %d/%d |", variant.name, pct(noise, 0.5), p90, noise.last ?? 0,
                     targets.first ?? 0, pct(targets, 0.5), targets.filter { $0 > p90 }.count, targets.count))
    }

    // Einzelheiten der Standard-Variante: Rang und Wert jedes Pflicht-Ziels
    if let (variant, outcome) = outcomes.last {
        print("\nStandard-Variante, Pflicht-Ziele (Rang · Wert · Kosinus · Schlagwort):\n")
        print("| Fall | Ziel | Rang | Wert | Kosinus | Schlagwort | zuletzt (3 h) |")
        print("|---|---|---|---|---|---|---|")
        for item in fixture.cases where !item.required.isEmpty {
            let ranked = outcome.ranked[item.id] ?? []
            for group in item.required {
                let best = group.compactMap { id in ranked.firstIndex { $0.thoughtID == id } }.min()
                guard let best else {
                    print("| \(item.id) | \(group[0].prefix(10)) | – | – | – | – | – |")
                    continue
                }
                let s = ranked[best]
                print(String(format: "| %@ | %@ | %d | %.3f | %@ | %.3f | %@ |", item.id, String(s.thoughtID.prefix(10)), best + 1, s.score,
                             s.cosine.map { String(format: "%.3f", $0) } ?? "–", s.keyword, s.isRecent ? "ja" : "nein"))
            }
        }
        _ = variant
    }
}
