import Foundation
import Testing
@testable import PaplyKit

@Suite("Gedanken lokal: Schlagwörter, Suche, Kandidaten, Themen-Index")
struct LocalTests {
    // MARK: Schlagwörter

    @Test func keywordsAreFoldedLemmasWithoutStopwords() {
        let terms = Keywords.terms("Ich muss morgen die Wohnungen besichtigen und den Mietvertrag mit Anna unterschreiben.", language: "de")
        #expect(terms.contains("wohnung"))
        #expect(terms.contains("mietvertrag"))
        #expect(terms.contains("besichtigen"))
        #expect(terms.contains("anna"))
        #expect(!terms.contains("muessen") && !terms.contains("ich") && !terms.contains("und"))
        #expect(Keywords.fold("Größe") == "groesse")
        #expect(Keywords.fold("Café") == "cafe")
        let english = Keywords.terms("We need to check the release plan for the App Store submission", language: "en")
        #expect(english.contains("release") && english.contains("submission"))
        #expect(!english.contains("need"))
    }

    @Test func topKeywordsUseInverseDocumentFrequency() {
        let counts = ["wohnung": 3, "termin": 1, "kowalski": 1]
        let top = Keywords.top(counts, limit: 2) { $0 == "wohnung" ? 0.1 : 2.0 }
        #expect(top == ["kowalski", "termin"])
    }

    // MARK: Suche

    private func searchIndex() -> (ThoughtSearchIndex, [String: Thought]) {
        var index = ThoughtSearchIndex()
        var a = StoreSupport.thought(createdAt: Date(timeIntervalSince1970: 1_000), title: "Übergabe der Wohnung",
                                     text: "Herr Kowalski schlägt für die Übergabe der Wohnung in Ehrenfeld den 28. Dezember vor.")
        a.tasks = [ThoughtTask(text: "Maler anrufen", owner: .ai)]
        let b = StoreSupport.thought(createdAt: Date(timeIntervalSince1970: 2_000), title: "Café in der Straße",
                                     text: "Das neue Café an der Hauptstraße hat guten Kuchen.")
        let c = StoreSupport.thought(createdAt: Date(timeIntervalSince1970: 3_000), title: "Laufplan", text: "Dreimal pro Woche laufen.")
        index.upsert(a, topicName: "Umzug", raw: "ähm also herr kowalski schlägt vor")
        index.upsert(b, topicName: nil, raw: nil)
        index.upsert(c, topicName: "Fitness", raw: "ähm dreimal laufen und ne Notiz zur wohnung")
        return (index, [a.id: a, b.id: b, c.id: c])
    }

    @Test func searchIsCaseAndAccentInsensitiveWithPrefixes() {
        let (index, thoughts) = searchIndex()
        func titles(_ query: String) -> [String] { index.search(query).compactMap { thoughts[$0.thoughtID]?.title } }
        #expect(titles("ubergabe") == ["Übergabe der Wohnung"])
        #expect(titles("CAFE") == ["Café in der Straße"])
        #expect(titles("strasse") == ["Café in der Straße"])
        #expect(titles("Kowal") == ["Übergabe der Wohnung"]) // Wortanfang
        #expect(titles("owalski").isEmpty) // kein Treffer mitten im Wort
        #expect(titles("wohn dez") == ["Übergabe der Wohnung"]) // UND
        #expect(titles("wohnung") == ["Übergabe der Wohnung", "Laufplan"]) // Titel vor Rohtext
        #expect(titles("umzug") == ["Übergabe der Wohnung"]) // Themenname
        #expect(titles("maler") == ["Übergabe der Wohnung"]) // Aufgabe
        #expect(titles("wohnung kuchen").isEmpty)
        #expect(index.search("   ").isEmpty)
    }

    @Test func searchSnippetHighlightsMatches() throws {
        let (index, _) = searchIndex()
        let hit = try #require(index.search("dezember").first)
        #expect(hit.field == .text)
        let snippet = hit.snippet as NSString
        let range = try #require(hit.ranges.first)
        #expect(snippet.substring(with: NSRange(location: range.lowerBound, length: range.count)) == "Dezember")
        let prefix = try #require(index.search("kowal").first)
        let marked = (prefix.snippet as NSString).substring(with: NSRange(location: prefix.ranges[0].lowerBound, length: prefix.ranges[0].count))
        #expect(marked == "Kowal")
        // langer Text: Ausschnitt um den Treffer mit „…“
        var long = ThoughtSearchIndex()
        let text = String(repeating: "Vorher kommt viel anderer Text. ", count: 10) + "Hier steht das Zielwort mitten drin. " + String(repeating: "Danach noch mehr. ", count: 10)
        long.upsert(StoreSupport.thought(title: "Lang", text: text), topicName: nil, raw: nil)
        let snippetHit = try #require(long.search("zielwort").first)
        #expect(snippetHit.snippet.hasPrefix("…") && snippetHit.snippet.hasSuffix("…"))
        #expect(snippetHit.snippet.count < 140)
        let hitRange = try #require(snippetHit.ranges.first)
        #expect((snippetHit.snippet as NSString).substring(with: NSRange(location: hitRange.lowerBound, length: hitRange.count)) == "Zielwort")
    }

    @Test func searchesTwoThousandThoughtsQuickly() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        var index = ThoughtSearchIndex()
        let topics = (0..<20).map { "Thema \($0)" }
        for i in 0..<2_000 {
            var thought = StoreSupport.thought(createdAt: Date(timeIntervalSince1970: Double(i) * 3_600),
                                               title: "Gedanke \(i) über Wohnung und Fluxo",
                                               text: String(repeating: "Heute über die Übergabe, den Umzug nach Bonn und das Budget nachgedacht. ", count: 4) + "Nummer \(i).")
            thought.tasks = [ThoughtTask(text: "Maler \(i) anrufen", owner: .ai)]
            index.upsert(thought, topicName: topics[i % 20], raw: "ähm also " + (thought.text ?? "").lowercased())
        }
        let clock = ContinuousClock()
        var worst = Duration.zero
        for query in ["wohn", "ubergabe bonn", "maler 1999", "budget umzug fluxo", "zzz", "thema 7"] {
            var best = Duration.seconds(10)
            for _ in 0..<6 { // bestes von sechs verteilten Läufen (andere Tests laufen parallel)
                try await Task.sleep(for: .milliseconds(50))
                let started = clock.now
                _ = index.search(query)
                best = min(best, clock.now - started)
            }
            print("Leistung: Suche „\(query)“ \(best)")
            worst = max(worst, best)
        }
        let ms = Double(worst.components.attoseconds) / 1e15 + Double(worst.components.seconds) * 1000
        print("Leistung: Suche in 2 000 Gedanken, langsamste Anfrage \(Int(ms)) ms")
        #expect(ms < 50)
        #expect(index.search("maler 1999").count == 1)
        #expect(index.search("wohn").count == 300) // Obergrenze der Treffer
    }

    // MARK: Index-Datei

    @Test func localIndexRoundTrips() throws {
        var index = LocalIndex()
        index.upsert(LocalIndex.Entry(id: "s_a", contentHash: 42, language: "de", terms: ["wohnung": 2, "umzug": 1],
                                      vector: EmbeddingVector(model: .contextual, space: "latn", values: [0.5, -0.25, 1])))
        index.upsert(LocalIndex.Entry(id: "s_b", contentHash: 7, language: nil, terms: [:], vector: nil))
        let decoded = try #require(LocalIndex.decode(index.encoded()))
        #expect(decoded["s_a"] == index["s_a"])
        #expect(decoded["s_b"] == index["s_b"])
        #expect(decoded.documentFrequency == ["wohnung": 1, "umzug": 1])
        #expect(LocalIndex.decode(Data("kaputt".utf8)) == nil)
        #expect(LocalIndex.decode(index.encoded().prefix(30)) == nil)
    }

    // MARK: Kandidaten (E0 als Regressionstest)

    @Test func candidateRecallOnEvaluationSet() async throws {
        let fixture = try StoreSupport.storeA()
        let clock = TestClock()
        let finder = CandidateFinder(thoughts: fixture.thoughts, topics: fixture.topics, now: clock.function)
        var hits = 0, total = 0, sent = 0
        for item in fixture.cases {
            clock.set(item.recordedAt)
            let candidates = await finder.candidates(forText: item.transcript, languages: item.languages, excluding: "")
            #expect(candidates.count <= 7)
            sent += candidates.count
            let ids = Set(candidates.map(\.thoughtID))
            for group in item.required {
                total += 1
                if group.contains(where: ids.contains) { hits += 1 }
            }
        }
        print("E0: Recall \(hits)/\(total), Ø \(Double(sent) / Double(fixture.cases.count)) Kandidaten")
        #expect(total == 11)
        #expect(Double(hits) / Double(total) >= 0.9)
    }

    @Test func recentThoughtsAreAlwaysCandidates() async throws {
        let fixture = try StoreSupport.storeA()
        let e01 = try #require(fixture.cases.first { $0.id == "e01" })
        let finder = CandidateFinder(thoughts: fixture.thoughts, topics: fixture.topics, now: { e01.recordedAt })
        let candidates = await finder.candidates(forText: e01.transcript, languages: e01.languages, excluding: "")
        #expect(candidates.contains { $0.thoughtID == "s_a0ee7da79e48b773f3797c9307a17683" })
        let entry = try #require(candidates.first { $0.thoughtID == "s_a0ee7da79e48b773f3797c9307a17683" })
        #expect(entry.when.hasPrefix("heute "))
        #expect(entry.excerpt.count <= 160 && !entry.excerpt.isEmpty)
        #expect(entry.title == "Übergabe der alten Wohnung am 28. Dezember")
    }

    @Test func candidatesExcludeSelfDeletedAndUnprocessed() async {
        let now = Date(timeIntervalSince1970: 1_793_093_400)
        var thoughts: [Thought] = []
        for i in 0..<10 {
            thoughts.append(StoreSupport.thought(createdAt: now.addingTimeInterval(-Double(i + 1) * 86_400),
                                                 title: "Halbmarathon Training \(i)", text: "Laufen am Rhein, Intervalle und lange Läufe für den Halbmarathon."))
        }
        thoughts[0].deletedAt = now
        thoughts[1].state = .captured
        thoughts[1].text = nil
        thoughts[1].title = nil
        let finder = CandidateFinder(thoughts: thoughts, topics: [], now: { now })
        let result = await finder.candidates(forText: "Training für den Halbmarathon am Rhein", languages: ["de"], excluding: thoughts[2].id)
        let ids = Set(result.map(\.thoughtID))
        #expect(!ids.contains(thoughts[0].id) && !ids.contains(thoughts[1].id) && !ids.contains(thoughts[2].id))
        #expect(result.count <= 7 && !result.isEmpty)
    }

    /// Spät verarbeitet (offline): Zeitbezug = Aufnahmezeit, nicht Verarbeitungszeit.
    @Test func candidatesRelativeToTheRecordingTime() async {
        let recorded = Date(timeIntervalSince1970: 1_793_093_400)          // Aufnahme
        let processed = recorded.addingTimeInterval(2 * 86_400)            // zwei Tage später geordnet
        let older = StoreSupport.thought(createdAt: recorded.addingTimeInterval(-3_600), title: "Übergabe der Wohnung",
                                         text: "Herr Kowalski schlägt den 28. Dezember für die Übergabe vor.")
        let unrelated = StoreSupport.thought(createdAt: recorded.addingTimeInterval(-40 * 86_400), title: "Gitarre",
                                             text: "Neue Saiten für die Gitarre kaufen.")
        let later = StoreSupport.thought(createdAt: recorded.addingTimeInterval(3_600), title: "Später",
                                         text: "Ein Gedanke nach der Aufnahme.")
        let finder = CandidateFinder(thoughts: [older, unrelated, later], topics: [], now: { processed })
        let text = "noch was zu vorhin der Termin geht doch nicht"
        let atRecording = await finder.candidates(forText: text, languages: ["de"], excluding: "s_self", relativeTo: recorded)
        let olderEntry = atRecording.first { $0.thoughtID == older.id }
        #expect(olderEntry?.when == CandidateFinder.when(older.createdAt, now: recorded))  // „heute …“
        #expect(olderEntry?.when.hasPrefix("heute") == true)
        #expect(!atRecording.contains { $0.thoughtID == later.id && $0.localScore < 0.35 }) // später zählt nicht als „kürzlich“
        let atProcessing = await finder.candidates(forText: text, languages: ["de"], excluding: "s_self")
        #expect(atProcessing.first { $0.thoughtID == older.id }?.when.hasPrefix("heute") != true)
    }

    @Test func whenIsPhrasedLocally() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = Date(timeIntervalSince1970: 1_793_093_400) // 27.10.2026 10:30
        #expect(CandidateFinder.when(now.addingTimeInterval(-8_400), now: now, calendar: calendar) == "heute 08:10")
        #expect(CandidateFinder.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "gestern")
        #expect(CandidateFinder.when(now.addingTimeInterval(-5 * 86_400), now: now, calendar: calendar) == "vor 5 Tagen")
        let september = CandidateFinder.when(Date(timeIntervalSince1970: 1_789_200_000), now: now, calendar: calendar)
        #expect(september.hasPrefix("12. Sep"))
    }

    // MARK: Themen-Index

    @Test func topicIndexFromEvaluationStore() async throws {
        let fixture = try StoreSupport.storeA()
        let e12 = try #require(fixture.cases.first { $0.id == "e12" })
        let finder = CandidateFinder(thoughts: fixture.thoughts, topics: fixture.topics, now: { e12.recordedAt })
        let index = await finder.topicIndex(forText: e12.transcript, languages: e12.languages)
        #expect(!index.full)
        #expect(index.entries.count == 14) // 13 aktive + 1 vorläufiges
        let provisional = try #require(index.entries.last)
        #expect(provisional.name == "Hochzeit Felix" && provisional.count == 1)
        let fluxo = try #require(index.entries.first { $0.name == "Fluxo" })
        #expect(fluxo.count == 9 && fluxo.hint.count == 3)
        #expect(!fluxo.hint.contains("fluxo")) // der Name selbst ist kein Hinweis
        let garden = try #require(index.entries.first { $0.name == "Garten" })
        #expect(garden.count == 1) // vom Nutzer angelegt: aktiv trotz n = 1
    }

    @Test func topicIndexCapsActiveTopicsAndSkipsMerged() async {
        let now = Date()
        var topics: [Topic] = []
        var thoughts: [Thought] = []
        for i in 0..<26 {
            let topic = Topic(id: "t_\(i)", title: "Thema \(i)", icon: .list, owner: .ai, createdAt: now)
            topics.append(topic)
            for k in 0..<2 {
                thoughts.append(StoreSupport.thought(createdAt: now.addingTimeInterval(-Double(i * 10 + k) * 60),
                                                     title: "Gedanke \(i)-\(k)", text: "Inhalt \(i)", topicId: topic.id))
            }
        }
        topics.append(Topic(id: "t_alias", title: "Alt", icon: .list, owner: .ai, mergedInto: "t_0"))
        thoughts.append(StoreSupport.thought(title: "Altes Thema", text: "x", topicId: "t_alias"))
        thoughts.append(StoreSupport.thought(createdAt: now.addingTimeInterval(-70 * 86_400), title: "Lange her", text: "y", topicId: nil))
        topics.append(Topic(id: "t_old", title: "Uralt", icon: .list, owner: .ai, createdAt: now.addingTimeInterval(-90 * 86_400)))
        thoughts[thoughts.count - 1].topicId = "t_old"
        let finder = CandidateFinder(thoughts: thoughts, topics: topics, options: { var o = CandidateFinder.Options(); o.models = []; return o }(),
                                     now: { now })
        let index = await finder.topicIndex(forText: "Inhalt 0", languages: ["de"])
        #expect(index.full)
        #expect(index.entries.count == 24) // höchstens 24 aktive, vorläufige älter als 60 Tage fehlen
        #expect(!index.entries.contains { $0.topicID == "t_alias" || $0.topicID == "t_old" })
        let summaries = TopicIndex.summaries(topics: topics, thoughts: thoughts)
        #expect(summaries.first { $0.topic.id == "t_0" }?.count == 3) // Alias zählt zum Ziel
        #expect(!summaries.contains { $0.topic.id == "t_alias" })
        #expect(summaries.first { $0.topic.id == "t_old" }?.isActive == false)
    }

    @Test func persistedIndexIsReusedAndUpdated() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        var options = CandidateFinder.Options()
        options.models = []
        let thought = StoreSupport.thought(title: "Halbmarathon", text: "Training am Rhein")
        try await store.save(thought)
        let finder = CandidateFinder(store: store, options: options)
        _ = await finder.candidates(forText: "Rhein laufen", languages: ["de"], excluding: "")
        let file = root.appendingPathComponent("embeddings.bin")
        let index = try #require(LocalIndex.decode(Data(contentsOf: file)))
        #expect(index[thought.id]?.terms["rhein"] == 1)
        var changed = try #require(await store.thought(thought.id))
        changed.text = "Training im Wald"
        try await store.save(changed)
        await finder.didChange(try #require(await store.thought(thought.id)))
        let updated = try #require(LocalIndex.decode(Data(contentsOf: file)))
        #expect(updated[thought.id]?.terms["wald"] == 1 && updated[thought.id]?.terms["rhein"] == nil)
        let keywords = await finder.keywords(forText: "Wald und Wiese im Wald", language: "de")
        #expect(Set(keywords) == ["wald", "wiese"])
    }
}
