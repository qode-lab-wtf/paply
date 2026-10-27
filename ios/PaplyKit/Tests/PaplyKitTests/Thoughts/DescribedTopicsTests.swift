import Foundation
import Testing
@testable import PaplyKit

/// Themen mit Beschreibung („Worum geht's?“, KONZEPT §6.3, §6.7, §6.10): Kodierung, Treffer-Erkennung,
/// Index, Prompt, Validator, Hygiene und die Rechte eines KI-Laufs.
@Suite("Themen mit Beschreibung")
struct DescribedTopicsTests {
    static let aramNote = "Meine Firma Aram UG – Kunden Müller Bau und Kowalski, Steuerberaterin Frau Albrecht"
    static let aram = Topic(id: "t_aram", title: "Aram UG", icon: .briefcase, owner: .user,
                            createdAt: Date(timeIntervalSince1970: 1_792_000_000), note: aramNote)
    static let club = Topic(id: "t_club", title: "Ruderclub", icon: .users, owner: .user,
                            createdAt: Date(timeIntervalSince1970: 1_792_000_000),
                            note: "Ruderverein RV Germania Beuel, Training mit den Junioren, Jahrgang 1987")

    // MARK: Kodierung

    @Test func olderTopicsDecodeWithoutNoteAndNoNoteIsWritten() throws {
        let old = #"{"id":"t_a","title":"Garten","icon":"leaf","owner":"ai","createdAt":1792000000000,"mergedInto":null}"#
        let topic = try ThoughtJSON.decoder().decode(Topic.self, from: Data(old.utf8))
        #expect(topic.note == nil && topic.describedNote == nil && !topic.isUserDefined)
        let written = String(decoding: try ThoughtJSON.encoder().encode(topic), as: UTF8.self)
        #expect(!written.contains("note"))
    }

    @Test func noteRoundTripsAndSurvivesAReload() async throws {
        let data = try ThoughtJSON.encoder().encode(Self.aram)
        #expect(String(decoding: data, as: UTF8.self).contains("\"note\""))
        #expect(try ThoughtJSON.decoder().decode(Topic.self, from: data) == Self.aram)
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        try await ThoughtStore(root: root).saveTopics([Self.aram, Topic(id: "t_plain", title: "Garten", icon: .leaf, owner: .ai)])
        let reloaded = try ThoughtStore(root: root)
        #expect(await reloaded.topics().first { $0.id == "t_aram" }?.note == Self.aramNote)
        #expect(await reloaded.topics().first { $0.id == "t_plain" }?.note == nil)
    }

    @Test func noteIsNormalised() {
        #expect(Topic.normalizedNote(nil) == nil)
        #expect(Topic.normalizedNote("  \n ") == nil)
        #expect(Topic.normalizedNote("  Aram UG \n") == "Aram UG")
        #expect(Topic.normalizedNote(String(repeating: "x", count: 300))?.count == Topic.maxNoteLength)
        #expect(Self.aram.isUserDefined)
        #expect(Topic(title: "X", icon: .list, owner: .ai, note: "Kunde Vogelsang").isUserDefined) // beschrieben = geschützt
    }

    // MARK: Treffer-Erkennung

    private func hits(_ text: String) -> [String] { TopicMentions.matches(Self.aram, in: text) }
    private func hits(_ topic: Topic, _ text: String) -> [String] { TopicMentions.matches(topic, in: text) }

    @Test func meaningfulTermsOnly() {
        let terms = TopicMentions.terms(Self.aram).map(\.original)
        #expect(terms == ["Aram", "Müller", "Bau", "Kowalski", "Steuerberaterin", "Albrecht"])
        // Stoppwörter, Rechtsformen, Anreden, sehr kurze Wörter und reine Zahlen fehlen
        let club = TopicMentions.terms(Self.club).map(\.original)
        #expect(club.contains("Germania") && club.contains("Beuel") && club.contains("Junioren"))
        #expect(!club.contains("RV") && !club.contains("1987") && !club.contains("mit") && !club.contains("den"))
        // ohne Beschreibung: keine Begriffe, auch der Name allein zählt nicht
        #expect(TopicMentions.terms(Topic(title: "Garten", icon: .leaf, owner: .user)).isEmpty)
        #expect(hits(Topic(title: "Garten", icon: .leaf, owner: .user), "Im Garten blüht es").isEmpty)
    }

    @Test func namesAreFoundAtWordBoundariesIgnoringCaseAndAccents() {
        #expect(hits("Heute mit Müller Bau telefoniert") == ["Müller", "Bau"])
        #expect(hits("das angebot von mueller") == ["Müller"])   // ä = ae
        #expect(hits("Muller hat zurückgerufen") == ["Müller"])  // ä = a
        #expect(hits("ARAM braucht neue Visitenkarten") == ["Aram"])
        #expect(hits("die Aram-Rechnung ist raus") == ["Aram"])  // Bindestrich trennt
        #expect(hits(Topic(title: "Jörg", icon: .users, owner: .user, note: "Nachbar Jörg Weiß"), "joerg und weiss") == ["Jörg", "Weiß"])
    }

    @Test func simpleInflectionsInBothDirections() {
        #expect(hits("Kowalskis Angebot liegt vor") == ["Kowalski"])            // Genitiv
        #expect(hits("Albrechts Rechnung kam heute") == ["Albrecht"])
        #expect(hits(Self.club, "die Beueler Fähre fällt aus") == ["Beuel"])    // -er
        #expect(hits(Self.club, "beim Training der Rudervereine") == ["Ruderverein", "Training"]) // -e
        let possessive = Topic(title: "Bäckerei", icon: .coffee, owner: .user, note: "Kunden Müllers und Omas Laden")
        #expect(hits(possessive, "Müller ruft an") == ["Müllers"])              // Begriff selbst gebeugt
        #expect(hits(Topic(title: "Oma Ilse", icon: .heart, owner: .user, note: "Meine Oma in Wuppertal"), "Omas Geburtstag") == ["Oma"])
    }

    @Test func noFalseHits() {
        #expect(hits("Die Firma hat neue Kunden, Frau Meier ruft an und die UG ist gegründet").isEmpty) // nur Stoppwörter
        #expect(hits("Bauarbeiten am Haus und ein Aramäisch-Kurs").isEmpty)        // kein Treffer mitten im Wort
        #expect(hits(Self.club, "it is fine, the RV is parked, 1987 was good").isEmpty)
        #expect(hits(Topic(title: "Oma Ilse", icon: .heart, owner: .user, note: "Oma in Wuppertal"), "Urlaub im Oman").isEmpty)
        #expect(hits("Brandschutz und Kowalczyk").isEmpty)
    }

    // Prüfer-Fälle: Ein Wortanfang ist keine Beugung.
    static let cooking = Topic(id: "t_cook", title: "Kochen", icon: .coffee, owner: .user, note: "Rezepte mit Reis")
    static let workshop = Topic(id: "t_shop", title: "Werkstatt", icon: .briefcase, owner: .user, note: "Kunde Fischer, Aufträge und Rechnungen")
    static let grandma = Topic(id: "t_oma", title: "Oma Ilse", icon: .heart, owner: .user, note: "Meine Oma in Köln, Arzttermine, Pflege")
    static let house = Topic(id: "t_house", title: "Haus Lindenstraße", icon: .home, owner: .user, note: "Unser Haus mit Garten, Handwerker Schulte, Nebenkosten")
    static let brandt = Topic(id: "t_brandt", title: "Brandt Logistik", icon: .list, owner: .user,
                              note: "Lagerverwaltung für Brandt Logistik in Troisdorf – Ansprechpartner Herr Wiechert")
    static let kessler = Topic(id: "t_kessler", title: "Kessler Digital", icon: .briefcase, owner: .user,
                               note: "Meine Beratungsfirma Kessler Digital UG – Kunden Brandt Logistik und Vogelsang, Buchhaltung bei Frau Okafor")

    @Test func aWordStartIsNoInflection() {
        #expect(hits(Self.cooking, "Reisen nach Lissabon und eine Reise nach Porto").isEmpty) // Reis ≠ Reisen/Reise
        #expect(hits(Self.cooking, "Reis kochen, dann die Rezepte sortieren") == ["Kochen", "Rezepte", "Reis"])
        #expect(hits(Self.workshop, "Fisch fürs Wochenende kaufen").isEmpty)                 // Fischer ≠ Fisch
        #expect(hits(Self.workshop, "Fischers Auftrag ist da") == ["Fischer", "Aufträge"])  // Genitiv-s; Auftrag ← Aufträge (ä = a)
        #expect(hits(Self.club, "die Bonner Fähre und die Beueler Fähre") == ["Beuel"])      // -er nur bei Eigennamen
        #expect(hits(Self.grandma, "Kölner Dom besichtigen").isEmpty)                         // „Köln“ steht im Wortschatz: kein -er
        #expect(hits(Self.brandt, "bei Brandts läuft die Inventur") == ["Brandt"])
        #expect(hits(Self.kessler, "bei Brandts läuft die Inventur") == ["Brandt"])
    }

    @Test func properNamesAndCommonWords() {
        for name in ["Kowalski", "Brandt", "Germania", "Beuel", "Ilse", "Aram", "Okafor"] {
            #expect(TopicMentions.isProperName(name), "\(name)")
        }
        for name in ["Köln", "Pflege", "Training", "Garten", "Reis", "Fisch", "Fischer", "Müller", "Bau", "Arzttermine", "Ruderverein", "kowalski"] {
            #expect(!TopicMentions.isProperName(name), "\(name)")
        }
    }

    // MARK: Umleitung

    private static func entry(_ topic: Topic, count: Int = 0) -> TopicIndexEntry {
        TopicIndexEntry(topicID: topic.id, name: topic.title, count: count, hint: [], about: topic.describedNote)
    }

    private func redirect(_ name: String, _ transcript: String, among topics: [Topic]) -> String? {
        TopicMentions.describedMatch(name, transcript: transcript, among: topics.map { Self.entry($0) })?.topicID
    }

    @Test func describedMatchNeedsProperNamesAndOneMoreTermInTheTranscript() {
        let entries = [Self.entry(Self.aram), Self.entry(Self.club, count: 3),
                       TopicIndexEntry(topicID: "t_garden", name: "Garten", count: 5, hint: [])]
        func match(_ name: String, _ transcript: String) -> String? {
            TopicMentions.describedMatch(name, transcript: transcript, among: entries)?.topicID
        }
        // Positiv: Eigennamen aus der Beschreibung + ein weiterer Begriff des Themas im Transkript
        #expect(match("Kowalskis", "Kowalskis Angebot liegt vor, die Rechnung geht über Aram") == "t_aram")
        #expect(match("Kowalski", "Kowalski ruft wegen Aram an") == "t_aram")
        #expect(match("Kunde Kowalski", "Kowalski und Albrecht brauchen die Belege") == "t_aram") // Rollenwort zählt nicht
        #expect(match("Müller Bau", "Müller Bau will das Angebot bis Freitag, Kowalski auch") == "t_aram") // Name aus mehreren Wörtern
        #expect(match("Germania", "Germania-Regatta: die Junioren brauchen neue Trikots") == "t_club")
        // Der Titel selbst (oder eine klare Variante) braucht keinen weiteren Begriff
        #expect(match("aram ug", "") == "t_aram")
        #expect(match("Ruderclubs", "") == "t_club")
        // Ohne weiteren Begriff im Transkript: keine Umleitung
        #expect(match("Kowalskis", "Kowalskis Angebot liegt vor") == nil)
        #expect(match("Müller Bau", "Müller Bau will das Angebot bis Freitag") == nil)
        // Einzelne gewöhnliche Wörter eines Namens leiten nie um
        #expect(match("Müller", "Müller ruft wegen Kowalski an") == nil)
        #expect(match("Bau", "Bau der Garage, Kowalski fragen") == nil)
        #expect(match("Kita Beuel", "Kita Beuel: Junioren abholen") == nil) // gemeinsamer Ort allein zieht nicht
        #expect(match("Garten", "Garten umgraben") == nil)                  // ohne Beschreibung: Doppel-Schranke
        #expect(match("Firma", "Firma Aram") == nil)                        // nur Stoppwörter
    }

    /// Prüfer-Fälle: Einwort-Themen sind der Normalfall – ein gewöhnliches Wort aus einer Beschreibung zieht nie,
    /// auch wenn das Transkript sonst etwas aus dem Thema nennt.
    @Test func commonWordsAndWordStartsAreNeverRedirected() {
        #expect(redirect("Reisen", "Reisen planen: erst Lissabon, dann Porto", among: [Self.cooking]) == nil)
        #expect(redirect("Reisen", "Reisen planen, vorher noch Rezepte und Reis kaufen", among: [Self.cooking]) == nil)
        #expect(redirect("Fisch", "Fisch fürs Wochenende kaufen, danach Rechnungen schreiben", among: [Self.workshop]) == nil)
        #expect(redirect("Köln", "Städtereise nach Köln: Dom, Museum Ludwig, Hotel buchen", among: [Self.grandma]) == nil)
        #expect(redirect("Köln", "Mit Oma nach Köln ins Museum", among: [Self.grandma]) == nil)
        #expect(redirect("Pflege", "Pflege für die Zimmerpflanzen, Oma fragen welche Erde", among: [Self.grandma]) == nil)
        #expect(redirect("Training", "Training im Fitnessstudio, danach in Beuel einkaufen", among: [Self.club]) == nil)
        #expect(redirect("Garten", "Im Garten Tomaten pflanzen, Handwerker Schulte kommt Freitag", among: [Self.house]) == nil)
        // Eigennamen derselben Themen ziehen weiterhin – mit einem weiteren Begriff
        #expect(redirect("Ilse", "Ilse hat angerufen, die Pflege klappt", among: [Self.grandma]) == "t_oma")
    }

    @Test func properNamesOfDescribedTopicsAreRedirected() {
        let both = [Self.kessler, Self.brandt]
        // „Brandts“ ← „Brandt Logistik“: Genitiv eines Eigennamens + weiterer Begriff
        #expect(redirect("Brandts", "Herr Wiechert sagt, bei Brandts läuft die Inventur", among: both) == "t_brandt")
        #expect(redirect("Brandts", "bei Brandts läuft die Inventur", among: both) == nil)
        // Titel schlägt Eigennamen aus einer anderen Beschreibung
        #expect(redirect("Brandt Logistik", "Vogelsang und Brandt Logistik", among: both) == "t_brandt")
        #expect(redirect("brandt logistik", "", among: both) == "t_brandt")
        #expect(redirect("Okafor", "Okafor braucht die Belege für Kessler Digital", among: both) == "t_kessler")
    }

    // MARK: Themen-Index

    @Test func mentionedTopicsArePinnedEvenBeyondTheCaps() async {
        let now = Date(timeIntervalSince1970: 1_793_093_400)
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
        topics.append(Self.aram) // Nutzer-Thema ohne Gedanken
        // KI-Thema mit Beschreibung, ohne Gedanken (sonst nie im Index)
        topics.append(Topic(id: "t_old", title: "Ruderclub", icon: .users, owner: .ai, createdAt: now.addingTimeInterval(-200 * 86_400),
                            note: "Ruderverein Germania"))
        var options = CandidateFinder.Options()
        options.models = []
        let finder = CandidateFinder(thoughts: thoughts, topics: topics, options: options, now: { now })

        let index = await finder.topicIndex(forText: "Inhalt 0, Kowalski hat angerufen, danach Germania-Training", languages: ["de"])
        #expect(index.full)
        #expect(index.entries.count <= 32)
        #expect(Set(index.entries.prefix(2).map(\.topicID)) == ["t_aram", "t_old"]) // Treffer vorn
        #expect(index.entries.filter(\.mentioned).map(\.topicID).sorted() == ["t_aram", "t_old"])
        let entry = index.entries.first { $0.topicID == "t_aram" }
        #expect(entry?.about == Self.aramNote && entry?.count == 0)

        let plain = await finder.topicIndex(forText: "Inhalt 3", languages: ["de"])
        #expect(!plain.entries.contains { $0.mentioned })
        #expect(!plain.entries.contains { $0.topicID == "t_old" }) // ohne Treffer: vorläufig ohne Aktivität fehlt es
        #expect(plain.entries.filter { $0.about != nil }.allSatisfy { $0.topicID == "t_aram" })
    }

    /// Bewertungssatz `described.json`: Die deterministischen Treffer gegen store-a stimmen mit `expect.mentioned`.
    /// Ein Finder für den ganzen Themen-Satz, nur Schlagwörter (Treffer hängen nicht an Embeddings).
    @Test func describedFixtureMentionsMatchTheExpectation() async throws {
        let fixture = try StoreSupport.storeA()
        let data = try Data(contentsOf: StoreSupport.fixtures.appendingPathComponent("described.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoder = ThoughtJSON.decoder()
        let extra = try (object["topics"] as? [[String: Any]] ?? []).map {
            try decoder.decode(Topic.self, from: JSONSerialization.data(withJSONObject: $0))
        }
        #expect(extra.count == 4 && extra.allSatisfy { $0.describedNote != nil && $0.owner == .user })
        let cases = try #require(object["cases"] as? [[String: Any]])
        #expect(cases.count == 8)
        let topics = fixture.topics + extra
        let clock = Box(Date())
        var options = CandidateFinder.Options()
        options.models = []
        let finder = CandidateFinder(thoughts: fixture.thoughts, topics: topics, options: options, now: { clock.value })
        for item in cases {
            let transcript = item["transcript"] as? String ?? ""
            let expected = Set(((item["expect"] as? [String: Any])?["mentioned"] as? [String]) ?? [])
            let haystack = TopicMentions.Haystack(transcript)
            let direct = topics.filter { !TopicMentions.matches(TopicMentions.terms($0), in: haystack).isEmpty }.map(\.title)
            #expect(Set(direct) == expected, "\(item["id"] ?? "?")")
            clock.value = Date(timeIntervalSince1970: (item["recordedAt"] as? Double ?? 0) / 1000)
            let index = await finder.topicIndex(forText: transcript, languages: ["de"])
            #expect(Set(index.entries.filter(\.mentioned).map(\.name)) == expected, "\(item["id"] ?? "?")")
            #expect(Set(index.entries.filter { $0.about != nil }.map(\.name)) == Set(extra.map(\.title)))
        }
    }

    // MARK: Prompt

    @Test func promptCarriesAboutAndMentionedOnlyWhereSet() throws {
        var topics = AIFixture.topics
        topics.insert(TopicIndexEntry(topicID: "t_aram", name: "Aram UG", count: 0, hint: [],
                                      about: "Meine Firma Aram UG\nKunden Müller Bau", mentioned: true), at: 0)
        topics.append(TopicIndexEntry(topicID: "t_club", name: "Ruderclub", count: 2, hint: ["Boot"], about: "Ruderverein Germania"))
        let built = try ThoughtPrompt.build(AIFixture.input(topics: topics))
        let json = try #require(try JSONSerialization.jsonObject(with: Data(built.user.utf8)) as? [String: Any])
        let lines = try #require(json["topics"] as? [[String: Any]])
        #expect(lines[0]["about"] as? String == "Meine Firma Aram UG; Kunden Müller Bau")
        #expect(lines[0]["mentioned"] as? Bool == true)
        #expect(lines[1]["name"] as? String == "Paply" && lines[1]["about"] == nil && lines[1]["mentioned"] == nil)
        #expect(lines.last?["about"] as? String == "Ruderverein Germania" && lines.last?["mentioned"] == nil)
        // Ohne Beschreibungen bleibt die Nachricht wie in v2: keine neuen Schlüssel
        let plain = try ThoughtPrompt.build(AIFixture.input())
        #expect(!plain.user.contains("\"about\"") && !plain.user.contains("\"mentioned\""))
        // Der Systemprompt hat genau eine neue Zeile dazu
        #expect(ThoughtPrompt.system.contains("about is the user's own description of a topic"))
        #expect(ThoughtPrompt.system.contains("a name mentioned only in passing does not decide the topic."))
    }

    @Test func mentionedTopicsSurviveTheTopicLimitAndEveryTrimStep() throws {
        var topics = (1...40).map {
            TopicIndexEntry(topicID: "t_\($0)", name: "Thema \($0)", count: $0, hint: ["Wort\($0)a", "Wort\($0)b", "Wort\($0)c"],
                            about: $0 % 4 == 0 ? "Beschreibung \($0) mit Namen, Firmen und Personen" : nil)
        }
        topics[34].mentioned = true
        topics[34].about = "Firma Aram UG, Kunden Müller Bau"
        let normal = try ThoughtPrompt.build(AIFixture.input(topics: topics))
        #expect(normal.aliases.topics.count == 32)
        #expect(normal.aliases.topics.values.contains { $0.topicID == "t_35" }) // Platz 35 → trotzdem dabei
        #expect(normal.aliases.topics.values.filter { !$0.mentioned }.count == 31)

        let candidates = (1...8).map { CandidateEntry(thoughtID: "s_\($0)", title: "Kandidat \($0) mit längerem Titel", topicID: "t_\($0)",
                                                      when: "vor \($0) Tagen", excerpt: String(repeating: "Auszug ", count: 30),
                                                      localScore: 0.5) }
        var trimmed: ThoughtPrompt.Built?
        for repeats in stride(from: 60, through: 260, by: 5) {
            let transcript = String(repeating: "Das ist ein langer Gedanke über das Projekt. ", count: repeats)
            guard let built = try? ThoughtPrompt.build(AIFixture.input(transcript: transcript, topics: topics, candidates: candidates)) else { break }
            if built.trimmed.contains("topics>16") { trimmed = built; break }
        }
        let built = try #require(trimmed)
        #expect(built.trimmed == ["excerpts", "candidates>3", "hints", "about", "topics>16"])
        #expect(built.aliases.topics.count == 16)
        let kept = try #require(built.aliases.topics.first { $0.value.topicID == "t_35" })
        let json = try #require(try JSONSerialization.jsonObject(with: Data(built.user.utf8)) as? [String: Any])
        let lines = try #require(json["topics"] as? [[String: Any]])
        let line = try #require(lines.first { $0["id"] as? String == kept.key })
        #expect(line["about"] as? String == "Firma Aram UG, Kunden Müller Bau" && line["mentioned"] as? Bool == true)
        #expect(lines.filter { $0["about"] != nil }.count == 1) // Beschreibungen ohne Treffer sind gekürzt
    }

    // MARK: Validator

    @Test func newTopicForADescribedNameIsRedirected() {
        var topics = AIFixture.topics
        topics.append(TopicIndexEntry(topicID: "t_aram", name: "Aram UG", count: 0, hint: [], about: Self.aramNote))
        topics.append(TopicIndexEntry(topicID: "t_club", name: "Ruderclub", count: 2, hint: [], about: Self.club.note))
        topics.append(Self.entry(Self.grandma))
        let transcript = AIFixture.transcript + " Müller Bau will das Angebot bis Freitag, Kowalski auch."
        let answer = AIFixture.answer(topic: AIFixture.topic("new", name: "Müller Bau", symbol: "briefcase"))
        let result = AIFixture.validate(answer, AIFixture.input(transcript: transcript, topics: topics))
        #expect(result.topic == .existing("t_aram"))
        #expect(result.rejections.contains("topic:described"))
        // auch wenn keine neuen Themen mehr erlaubt sind
        let full = AIFixture.validate(answer, AIFixture.input(transcript: transcript, topics: topics, topicsFull: true))
        #expect(full.topic == .existing("t_aram"))
        // ohne weiteren Begriff des Themas im Transkript: bleibt ein neues Thema
        let alone = AIFixture.validate(answer, AIFixture.input(transcript: AIFixture.transcript + " Müller Bau will das Angebot.", topics: topics))
        #expect(alone.topic == .new(name: "Müller Bau", icon: .briefcase))
        #expect(!alone.rejections.contains("topic:described"))
        // gemeinsamer Ort allein: bleibt ein neues Thema
        let kita = AIFixture.validate(AIFixture.answer(topic: AIFixture.topic("new", name: "Kita Beuel", symbol: "home")),
                                      AIFixture.input(transcript: transcript, topics: topics))
        #expect(kita.topic == .new(name: "Kita Beuel", icon: .home))
        #expect(!kita.rejections.contains("topic:described"))
        // gewöhnliches Wort aus einer Beschreibung: bleibt ein neues Thema
        let city = AIFixture.validate(AIFixture.answer(topic: AIFixture.topic("new", name: "Köln", symbol: "map-pin")),
                                      AIFixture.input(transcript: AIFixture.transcript + " Danach mit Oma nach Köln.", topics: topics))
        #expect(city.topic == .new(name: "Köln", icon: .mapPin))
    }

    // MARK: Hygiene

    @Test func userTopicsAreNeverPairedAndKeepTheirIDAndName() {
        let profiles = [
            TopicHygiene.Profile(topicID: "a", name: "Wohnung", count: 4, keywords: ["miete"], isUserDefined: true),
            TopicHygiene.Profile(topicID: "b", name: "Wohnungen", count: 3, keywords: ["miete"], isUserDefined: true),
            TopicHygiene.Profile(topicID: "c", name: "Wohnungssuche", count: 2, keywords: ["miete"]),
        ]
        let pairs = Set(TopicHygiene.candidatePairs(profiles, declined: []).map { [$0.a, $0.b] })
        #expect(!pairs.contains(["a", "b"]))
        #expect(pairs.contains(["a", "c"]) && pairs.contains(["b", "c"]))
        let json = #"{"pairs":[{"a":"c","b":"a","merge":true,"name":"Wohnungssuche","reason":"gleich"},{"a":"a","b":"b","merge":true,"name":"Wohnen","reason":"x"}]}"#
        let suggestions = TopicHygiene.validateSuggestions(json, asked: [("a", "c"), ("a", "b")], protected: ["a", "b"])
        #expect(suggestions == [TopicSuggestion(a: "a", b: "c", name: nil, reason: "gleich")]) // Nutzer-Thema ist Ziel, Name bleibt
        // ohne geschützte Themen unverändert
        #expect(TopicHygiene.validateSuggestions(json, asked: [("a", "c")]) == [TopicSuggestion(a: "c", b: "a", name: "Wohnungssuche", reason: "gleich")])
    }

    /// Die Themenpflege schreibt nur Vorschläge: Themen und Gedanken bleiben unberührt, bis der Nutzer bestätigt.
    @Test func hygieneOnlySuggestsAndNeverTouchesTopicsOrThoughts() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let ai = Topic(id: "t_ai", title: "Aram", icon: .list, owner: .ai, createdAt: Date(timeIntervalSince1970: 1_792_000_000))
        try await store.saveTopics([Self.aram, ai])
        for _ in 0..<2 { try await store.save(StoreSupport.thought(title: "Aram Rechnung", text: "Rechnung für Aram", topicId: ai.id)) }
        let topicsBefore = await store.topics()
        let thoughtsBefore = await store.all().sorted { $0.id < $1.id }
        let content = #"{"pairs":[{"a":"t_ai","b":"t_aram","merge":true,"name":"Aram","reason":"gleiche Firma"}]}"#
        let server = MockServer { _, _ in
            .json(200, ["choices": [["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": content]]],
                        "usage": ["prompt_tokens": 400, "completion_tokens": 100, "total_tokens": 500]])
        }
        let ledger = TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: { TokenLedger.Limits() })
        let outcome = await TopicHygieneRunner.run(store: store, ledger: ledger, apiKey: "test-placeholder", force: true,
                                                   transport: server.transport, baseURL: server.baseURL, now: Date())
        #expect(outcome == .suggestions([TopicSuggestion(a: "t_aram", b: "t_ai", name: nil, reason: "gleiche Firma")]))
        #expect(await store.topics() == topicsBefore)
        #expect(await store.all().sorted { $0.id < $1.id } == thoughtsBefore)
        #expect(await store.pendingSuggestions().count == 1)
    }

    // MARK: Rechte eines KI-Laufs

    /// Ein Lauf ordnet nur seinen Gedanken: andere Gedanken und vorhandene Themen (Name, Symbol, Beschreibung,
    /// Besitzer, Reihenfolge) bleiben unverändert; ein neues Thema wird nur angehängt.
    @Test func aRunOnlyOrdersItsOwnThoughtAndOnlyAppendsTopics() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let garden = Topic(id: "t_garden", title: "Garten", icon: .leaf, owner: .ai, createdAt: Date(timeIntervalSince1970: 1_792_000_000))
        let alias = Topic(id: "t_beds", title: "Beete", icon: .leaf, owner: .ai, createdAt: Date(timeIntervalSince1970: 1_792_000_000),
                          mergedInto: "t_garden")
        let user = Topic(id: "t_mine", title: "Lesen", icon: .book, owner: .user, createdAt: Date(timeIntervalSince1970: 1_792_000_000))
        try await h.store.saveTopics([Self.aram, alias, garden, user])
        let other = StoreSupport.thought(createdAt: h.clock.now.addingTimeInterval(-600), title: "Tomaten", text: "Tomaten im Garten",
                                         topicId: "t_garden")
        try await h.store.save(other)
        let topicsBefore = await h.store.topics()
        let otherBefore = try #require(await h.store.thought(other.id))

        // 1. neues Thema für einen Namen aus der Beschreibung → beschriebenes Thema, Themen unverändert
        await h.structurer.push(ProcessingTests.success(topic: .new(name: "Müller Bau", icon: .briefcase),
                                                        related: [RelatedDraft(thoughtID: other.id, kind: .continues, reason: "Gleicher Garten")]))
        await h.transcriber.push(.success(text: "Müller Bau will das Angebot bis Freitag, Kowalski auch", languages: ["de"],
                                          audioSeconds: 2, model: "whisper-large-v3"))
        let first = try await h.capture()
        await h.run()
        let ordered = try #require(await h.thought(first))
        #expect(ordered.topicId == "t_aram" && ordered.topicOwner == .ai)
        #expect(ordered.links.map(\.target) == [other.id])                 // Verbindung nur im neuen Gedanken
        #expect(await h.store.topics() == topicsBefore)
        #expect(await h.store.thought(other.id) == otherBefore)

        // 2. vorhandenes Nutzer-Thema wählen: Thema bleibt, wie es ist
        await h.structurer.push(ProcessingTests.success(topic: .existing("t_mine")))
        let second = try await h.capture()
        await h.run()
        #expect(await h.thought(second)?.topicId == "t_mine")
        #expect(await h.store.topics() == topicsBefore)

        // 3. wirklich neues Thema: wird hinten angehängt, alles davor bleibt gleich
        await h.structurer.push(ProcessingTests.success(topic: .new(name: "Lissabon", icon: .plane)))
        let third = try await h.capture()
        await h.run()
        let after = await h.store.topics()
        #expect(Array(after.dropLast()) == topicsBefore)
        #expect(after.last?.title == "Lissabon" && after.last?.owner == .ai && after.last?.note == nil)
        #expect(await h.thought(third)?.topicId == after.last?.id)
        #expect(await h.store.thought(other.id) == otherBefore)
    }

    // MARK: Speicher

    @Test func describedTopicStaysWhenItsLastThoughtIsPurged() async throws {
        let root = StoreSupport.temporaryRoot()
        defer { StoreSupport.remove(root) }
        let store = try ThoughtStore(root: root)
        let plain = Topic(id: "t_plain", title: "Laufen", icon: .zap, owner: .user)
        try await store.saveTopics([Self.aram, plain])
        let a = StoreSupport.thought(topicId: "t_aram"), b = StoreSupport.thought(topicId: "t_plain")
        for thought in [a, b] { try await store.save(thought) }
        await store.purge([a.id, b.id])
        #expect(await store.topics().map(\.id) == ["t_aram"]) // beschrieben: bleibt; unbeschrieben: geht mit
    }
}
