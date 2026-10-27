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

    /// Wortschatz nur noch für die Herkunftsendung -er der Hinweise („Beueler“ ← „Beuel“, nicht „Fischer“ ← „Fisch“).
    @Test func commonWordsOnlyGuardTheErHint() {
        for name in ["Kowalski", "Brandt", "Germania", "Beuel", "Ilse", "Aram", "Okafor"] {
            #expect(!CommonWords.contains(name), "\(name)")
        }
        for name in ["Köln", "Pflege", "Training", "Garten", "Reis", "Fisch", "Fischer", "Müller", "Bau", "Arzttermine", "Ruderverein"] {
            #expect(CommonWords.contains(name), "\(name)")
        }
    }

    // MARK: Umleitung nur über den Titel

    private static func entry(_ topic: Topic, count: Int = 0) -> TopicIndexEntry {
        TopicIndexEntry(topicID: topic.id, name: topic.title, count: count, hint: [], about: topic.describedNote)
    }

    /// Verbindliche Umleitung eines neuen Themennamens (Doppel-Schranke, wie Validator und Prozessor)
    private func redirect(_ name: String, among topics: [Topic]) -> String? {
        TopicHygiene.matchExisting(name, among: topics.map { Self.entry($0) })?.topicID
    }

    /// Namen aus einer Beschreibung sind nur Hinweise (`mentioned`), nie eine Umleitung; der Titel (oder eine sichere
    /// Variante davon) leitet um – beschrieben oder nicht.
    @Test func namesFromADescriptionAreOnlyHintsTheTitleRedirects() {
        let topics = [Self.aram, Self.club, Topic(id: "t_garden", title: "Garten", icon: .leaf, owner: .ai)]
        // Hinweis ja, Umleitung nein – auch mit weiteren Begriffen des Themas im Transkript
        for (name, transcript) in [("Kowalskis", "Kowalskis Angebot liegt vor, die Rechnung geht über Aram"),
                                   ("Kowalski", "Kowalski ruft wegen Aram an"),
                                   ("Kunde Kowalski", "Kowalski und Albrecht brauchen die Belege"),
                                   ("Müller Bau", "Müller Bau will das Angebot bis Freitag, Kowalski auch"),
                                   ("Germania", "Germania-Regatta: die Junioren brauchen neue Trikots")] {
            let mentioned = topics.filter { !TopicMentions.matches($0, in: transcript).isEmpty }.map(\.id)
            #expect(!mentioned.isEmpty, "\(name)")
            #expect(redirect(name, among: topics) == nil, "\(name)")
        }
        #expect(hits(Self.brandt, "bei Brandts läuft die Inventur") == ["Brandt"]) // Genitiv bleibt ein Treffer
        // Der Titel selbst oder eine sichere Variante (Groß/Klein, Leer-/Bindestrich, Plural/Genitiv)
        #expect(redirect("aram ug", among: topics) == "t_aram")
        #expect(redirect("Aram-UG", among: topics) == "t_aram")
        #expect(redirect("Ruderclubs", among: topics) == "t_club")
        #expect(redirect("Garten", among: topics) == "t_garden") // ohne Beschreibung genauso
        // Einzelne Wörter, Orte, Stoppwörter
        for name in ["Aram", "Müller", "Bau", "Kita Beuel", "Firma", "Ruder"] {
            #expect(redirect(name, among: topics) == nil, "\(name)")
        }
    }

    /// „Müller Bau“ als neuer Name: Umleitung, wenn ein Thema so heißt; steht es nur in einer Beschreibung, ein Hinweis.
    @Test func aCompanyNameRedirectsOnlyAsATitle() {
        let company = Topic(id: "t_mb", title: "Müller Bau", icon: .briefcase, owner: .user)
        #expect(redirect("Müller Bau", among: [Self.aram]) == nil)
        #expect(hits("Müller Bau will das Angebot") == ["Müller", "Bau"])
        #expect(redirect("Müller Bau", among: [Self.aram, company]) == "t_mb")
        #expect(redirect("Mueller-Bau", among: [Self.aram, company]) == "t_mb") // ü = ue, Bindestrich
        #expect(redirect("Muller Bau", among: [Self.aram, company]) == nil)      // ü ≠ u
    }

    /// Prüfer-Fälle: Einwort-Themen sind der Normalfall – ein gewöhnliches Wort, ein Wortanfang oder ein Name aus einer
    /// Beschreibung zieht nie, auch wenn das Transkript sonst etwas aus dem Thema nennt.
    @Test func commonWordsWordStartsAndDescribedNamesAreNeverRedirected() {
        #expect(redirect("Reisen", among: [Self.cooking]) == nil)
        #expect(redirect("Fisch", among: [Self.workshop]) == nil)
        #expect(redirect("Köln", among: [Self.grandma]) == nil)
        #expect(redirect("Pflege", among: [Self.grandma]) == nil)
        #expect(redirect("Training", among: [Self.club]) == nil)
        #expect(redirect("Garten", among: [Self.house]) == nil)
        #expect(redirect("Ilse", among: [Self.grandma]) == nil)
        // Prüfer: Titel „Reis“ bzw. „Fischer“ – „Reisen“ und „Fisch“ sind andere Themen
        #expect(redirect("Reisen", among: [Topic(id: "t_reis", title: "Reis", icon: .coffee, owner: .ai)]) == nil)
        #expect(redirect("Fisch", among: [Topic(id: "t_fischer", title: "Fischer", icon: .users, owner: .user)]) == nil)
        // Prüfer: „Koeln“ steht nur in der Beschreibung („Köln“) – ein Hinweis, nie Oma Ilse
        let koeln = Topic(id: "t_oma2", title: "Oma Ilse", icon: .heart, owner: .user, note: "Meine Oma in Koeln, Arzttermine")
        #expect(redirect("Koeln", among: [koeln]) == nil && redirect("Köln", among: [koeln]) == nil)
        #expect(hits(koeln, "Ausflug nach Koeln") == ["Koeln"])
        // Prüfer: Großschreibung mehrerer Wörter allein („Home Office“) leitet nicht um
        let office = Topic(id: "t_job", title: "Kessler Digital", icon: .briefcase, owner: .user, note: "Beratung, Home Office montags")
        #expect(redirect("Home Office", among: [office]) == nil)
        #expect(hits(office, "Home Office ab nächster Woche") == ["Home", "Office"])
    }

    @Test func titleBeatsANameFromAnotherDescription() {
        let both = [Self.kessler, Self.brandt]
        // „Brandt Logistik“ steht auch in Kesslers Beschreibung – der Titel entscheidet
        #expect(redirect("Brandt Logistik", among: both) == "t_brandt")
        #expect(redirect("brandt logistik", among: both) == "t_brandt")
        #expect(redirect("Brandts", among: both) == nil)
        #expect(redirect("Okafor", among: both) == nil)
    }

    /// Mehrdeutig: zwei Themen mit gleichem Titel nach Normalisierung bzw. zwei Beschreibungen mit demselben Namen –
    /// keine Umleitung, beide Treffer gehen als `mentioned` an die KI.
    @Test func ambiguousMatchesNeverDecide() async {
        let a = Topic(id: "t_a", title: "Paply App", icon: .code, owner: .user)
        let b = Topic(id: "t_b", title: "Paply-App", icon: .code, owner: .ai)
        #expect(TopicHygiene.sameNamed("paply app", among: [a, b]).map(\.id) == ["t_a", "t_b"])
        #expect(redirect("paply app", among: [a, b]) == nil)
        #expect(redirect("PAPLY-APP", among: [a, b]) == nil)
        #expect(redirect("Paply App", among: [a]) == "t_a")
        // dasselbe Thema über zwei Einträge ist nicht mehrdeutig
        #expect(TopicHygiene.matchExisting("Paply App", among: [Self.entry(a), Self.entry(a, count: 3)])?.topicID == "t_a")

        let shop = Topic(id: "t_shop2", title: "Werkstatt", icon: .briefcase, owner: .user, note: "Kunde Kowalski, Reparaturen")
        let clubKowalski = Topic(id: "t_club2", title: "Schachclub", icon: .users, owner: .user, note: "Trainer Kowalski")
        var options = CandidateFinder.Options()
        options.models = []
        let finder = CandidateFinder(thoughts: [], topics: [shop, clubKowalski], options: options, now: { Date() })
        let index = await finder.topicIndex(forText: "Kowalski hat angerufen", languages: ["de"])
        #expect(Set(index.entries.filter(\.mentioned).map(\.topicID)) == ["t_shop2", "t_club2"])
        #expect(redirect("Kowalski", among: [shop, clubKowalski]) == nil)
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

    /// Validator: Ein Name aus einer Beschreibung bleibt ein neues Thema (die KI hatte den Hinweis), der Titel eines
    /// beschriebenen Themas wird umgeleitet – auch wenn keine neuen Themen mehr erlaubt sind.
    @Test func onlyTheTitleOfADescribedTopicIsRedirected() {
        var topics = AIFixture.topics
        topics.append(TopicIndexEntry(topicID: "t_aram", name: "Aram UG", count: 0, hint: [], about: Self.aramNote, mentioned: true))
        topics.append(TopicIndexEntry(topicID: "t_club", name: "Ruderclub", count: 2, hint: [], about: Self.club.note))
        topics.append(Self.entry(Self.grandma))
        let transcript = AIFixture.transcript + " Müller Bau will das Angebot bis Freitag, Kowalski auch."
        let answer = AIFixture.answer(topic: AIFixture.topic("new", name: "Müller Bau", symbol: "briefcase"))
        let result = AIFixture.validate(answer, AIFixture.input(transcript: transcript, topics: topics))
        #expect(result.topic == .new(name: "Müller Bau", icon: .briefcase))
        #expect(!result.rejections.contains { $0.hasPrefix("topic:") })
        let full = AIFixture.validate(answer, AIFixture.input(transcript: transcript, topics: topics, topicsFull: true))
        #expect(full.topic == .none && full.rejections.contains("topic:full"))
        // der Titel (Variante) leitet um, auch bei vollem Index
        let title = AIFixture.answer(topic: AIFixture.topic("new", name: "Aram-UG", symbol: "briefcase"))
        for input in [AIFixture.input(transcript: transcript, topics: topics), AIFixture.input(transcript: transcript, topics: topics, topicsFull: true)] {
            let redirected = AIFixture.validate(title, input)
            #expect(redirected.topic == .existing("t_aram") && redirected.rejections.contains("topic:duplicate"))
        }
        // gemeinsamer Ort, gewöhnliches Wort, Eigenname aus der Beschreibung: bleiben neue Themen
        for (name, symbol, icon) in [("Kita Beuel", "home", TopicIcon.home), ("Köln", "map-pin", .mapPin), ("Kowalski", "users", .users)] {
            let other = AIFixture.validate(AIFixture.answer(topic: AIFixture.topic("new", name: name, symbol: symbol)),
                                           AIFixture.input(transcript: transcript + " Danach mit Oma nach Köln.", topics: topics))
            #expect(other.topic == .new(name: name, icon: icon), "\(name)")
        }
    }

    /// Validator: Zwei Themen mit gleichem Titel nach Normalisierung – keine Umleitung und kein drittes gleichnamiges.
    @Test func ambiguousTitlesBecomeNone() {
        var topics = AIFixture.topics
        topics.append(TopicIndexEntry(topicID: "t_app1", name: "Paply App", count: 3, hint: []))
        topics.append(TopicIndexEntry(topicID: "t_app2", name: "Paply-App", count: 1, hint: []))
        let result = AIFixture.validate(AIFixture.answer(topic: AIFixture.topic("new", name: "paply app", symbol: "code")),
                                        AIFixture.input(topics: topics))
        #expect(result.topic == .none && result.rejections.contains("topic:ambiguous"))
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

        // 1. neues Thema mit dem Titel eines beschriebenen Themas (Variante) → dieses Thema, Themen unverändert
        await h.structurer.push(ProcessingTests.success(topic: .new(name: "Aram-UG", icon: .briefcase),
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
