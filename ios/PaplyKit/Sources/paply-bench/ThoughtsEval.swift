// Prüfstand „Gedanken“ (KONZEPT §8). Besitzer: H1 (Unterbefehl „thoughts-eval“, E1–E5) und H2
// (Unterbefehl „candidates“, E0). Prüfstand gegen die Fixtures unter Tests/Fixtures/Thoughts.
//
//   paply-bench thoughts-eval plan [--cases e01,e03]          offline: Schätzung je Fall, Kandidaten, Teile
//   paply-bench thoughts-eval run <stufe> [Optionen]          Groq-Aufrufe (Schlüssel aus PAPLY_GROQ_KEY)
//       --cases e01,e03 · --limit N (Fälle) · --budget T (Tokens dieser Sitzung)
//       --model large|small · --effort low|medium · --run k
//   paply-bench thoughts-eval score <stufe> [--run k] [--model …] [--effort …] [--prompt v]
//                                                             offline: validieren, bewerten, Prüfdatei für Opus
//                                                             (--prompt: Prompt-Version der Antworten, Standard aktuell)
//
// Harte Regeln (Groq-Budget, kostenloser Tarif):
// - nie qwen; nur openai/gpt-oss-120b und openai/gpt-oss-20b
// - 120b ≤ 60 000 Tokens je 24 h aus diesem Prüfstand, 20b ≤ 40 000 insgesamt
// - beim ersten 429 sofort abbrechen
// - jede Rohantwort wird unter /tmp/paply-thoughts-eval/ gesichert; erledigte Fälle laufen nie doppelt
// - Schlüssel nur aus der Umgebung (PAPLY_GROQ_KEY), nie ausgeben
//
// Ablauf je Fall wie in der App (README der Fixtures §2): Themen-Index und Kandidaten baut der echte H2-Code
// (`CandidateFinder`) aus store-a zum Zeitpunkt `recordedAt`; lange Fälle laufen im Teile-Modus wie
// `ThoughtProcessor` (Teil 1 voll, Teile 2…n kurz). Anders als in der App gibt es keine Wiederholung mit
// `medium` und keinen 20b-Ausweich: gemessen wird die erste Antwort.
import Foundation
import PaplyKit

enum ThoughtsEval {
    static let outDir = URL(fileURLWithPath: "/tmp/paply-thoughts-eval")
    static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Fixtures/Thoughts")
    static let models = (large: "openai/gpt-oss-120b", small: "openai/gpt-oss-20b")
    static let dailyLargeTokens = 60_000
    static let totalSmallTokens = 40_000

    // MARK: Gesicherte Aufrufe

    struct CallRecord: Codable {
        var stage: String
        var caseID: String
        var run: Int
        var model: String
        var effort: String
        var at: Date
        var latencyMs: Double
        /// "ok" | "http-<code>" | "network-<code>" | "invalid-response"
        var status: String
        var finishReason: String?
        /// Rohantwort (JSON nach Schema) – nur synthetische Testdaten, keine Nutzerdaten
        var content: String?
        var usage: Usage?
        var estimate: Int
        var trimmed: [String]
        /// Kandidaten aus Soll-Werten + Zufallsfüllern statt aus der lokalen Suche (H2)
        var syntheticCandidates: Bool
        var note: String?
        /// Teile-Modus: 1…n; nil = ganzer Gedanke
        var part: Int?
        var partCount: Int?
        /// Gesendete Eingabe (für die Offline-Validierung mit denselben Kürzeln)
        var input: InputSnapshot?
        /// `ThoughtPrompt.version` beim Aufruf; fehlt bei den ersten E1-Läufen = 1
        var promptVersion: Int?
        /// Groq `error.failed_generation` bei `json_validate_failed` (nur Prüfstand, synthetische Daten)
        var failedGeneration: String?

        struct Usage: Codable { var prompt: Int; var completion: Int; var total: Int }

        var prompt: Int { promptVersion ?? 1 }

        func matches(caseID: String, run: Int, part: Int?, model: String, effort: String, prompt: Int) -> Bool {
            self.caseID == caseID && self.run == run && self.part == part && self.model == model && self.effort == effort
                && self.prompt == prompt
        }
    }

    /// `StructureInput` als Datei (Themen, Kandidaten, Teil), ohne Satzliste.
    struct InputSnapshot: Codable {
        struct TopicRow: Codable { var id: String; var name: String; var count: Int; var hint: [String] }
        struct CandidateRow: Codable {
            var id: String; var title: String; var topicID: String?; var when: String; var excerpt: String; var score: Double
        }

        var transcript: String
        var spokenLanguages: [String]
        var uiLanguage: String
        var vocabulary: String
        var topics: [TopicRow]
        var topicsFull: Bool
        var candidates: [CandidateRow]
        var part: Int?
        var partCount: Int?
        var effort: String
        /// `now` des Prompts (ab v2) und Zeitzone
        var now: Date?
        var timeZone: String?

        init(_ input: StructureInput, now: Date? = nil, timeZone: TimeZone? = nil) {
            self.now = now
            self.timeZone = timeZone?.identifier
            transcript = input.transcript
            spokenLanguages = input.spokenLanguages
            uiLanguage = input.uiLanguage
            vocabulary = input.vocabulary
            topics = input.topics.map { TopicRow(id: $0.topicID, name: $0.name, count: $0.count, hint: $0.hint) }
            topicsFull = input.topicsFull
            candidates = input.candidates.map {
                CandidateRow(id: $0.thoughtID, title: $0.title, topicID: $0.topicID, when: $0.when, excerpt: $0.excerpt, score: $0.localScore)
            }
            part = input.part?.index
            partCount = input.part?.count
            effort = input.reasoningEffort
        }

        var input: StructureInput {
            StructureInput(transcript: transcript, sentences: [], spokenLanguages: spokenLanguages, uiLanguage: uiLanguage,
                           vocabulary: vocabulary,
                           topics: topics.map { TopicIndexEntry(topicID: $0.id, name: $0.name, count: $0.count, hint: $0.hint) },
                           topicsFull: topicsFull,
                           candidates: candidates.map {
                               CandidateEntry(thoughtID: $0.id, title: $0.title, topicID: $0.topicID, when: $0.when,
                                              excerpt: $0.excerpt, localScore: $0.score)
                           },
                           part: part.map { (index: $0, count: partCount ?? $0) }, reasoningEffort: effort)
        }
    }

    static func recordsURL(_ stage: String) -> URL { outDir.appendingPathComponent("\(stage).jsonl") }

    static func loadRecords(_ stage: String) -> [CallRecord] {
        guard let text = try? String(contentsOf: recordsURL(stage), encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return text.split(separator: "\n").compactMap { try? decoder.decode(CallRecord.self, from: Data($0.utf8)) }
    }

    static func append(_ record: CallRecord) throws {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(record)
        line.append(0x0A)
        let url = recordsURL(record.stage)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    /// Verbrauch je Modell über alle Stufen (für die 20b-Gesamtgrenze und den Bericht).
    static func totalTokens(model: String, since: Date = .distantPast) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: outDir.path)) ?? []
        var total = 0
        for file in files where file.hasSuffix(".jsonl") {
            for record in loadRecords(String(file.dropLast(6))) where record.model == model && record.at >= since {
                if let usage = record.usage { total += usage.total } else if record.status == "ok" { total += record.estimate }
            }
        }
        return total
    }

    // MARK: Ein Aufruf mit Budget-Wächter

    enum Stop: Error, CustomStringConvertible {
        case rateLimited(String)
        case budget(String)

        var description: String {
            switch self {
            case .rateLimited(let s): return "ABBRUCH 429: \(s)"
            case .budget(let s): return "ABBRUCH Budget: \(s)"
            }
        }
    }

    static func ledger(for model: String) -> TokenLedger {
        var configured = TokenLedger.Limits()
        configured.dailyTokens = model == models.large ? dailyLargeTokens : totalSmallTokens
        let limits = configured
        let url = outDir.appendingPathComponent("ledger-\(model.replacingOccurrences(of: "/", with: "_")).json")
        return TokenLedger(fileURL: url, limits: { limits })
    }

    /// Ein strukturierter Aufruf. Wirft `Stop` bei 429 oder erschöpftem Budget (vor dem Aufruf).
    /// `part`/`partCount`: Teile-Modus (Teil 1 läuft mit vollem Schema, `input.part` ist dort nil).
    static func call(stage: String, caseID: String, run: Int, input: StructureInput, model: String, key: String,
                     synthetic: Bool, note: String? = nil, part: Int? = nil, partCount: Int? = nil,
                     now: Date, timeZone: TimeZone) async throws -> CallRecord {
        precondition(model.hasPrefix("openai/gpt-oss"), "nie qwen")
        let built = try ThoughtPrompt.build(input, now: now, timeZone: timeZone)
        if model == models.small, totalTokens(model: model) + built.estimate > totalSmallTokens {
            throw Stop.budget("20b-Gesamtgrenze \(totalSmallTokens) wäre überschritten")
        }
        let ledger = ledger(for: model)
        var reservation: TokenLedger.Reservation?
        while reservation == nil {
            do {
                reservation = try await ledger.reserve(model: model, amount: built.estimate, unit: .tokens)
            } catch {
                switch error {
                case .minute(let retryAt):
                    let wait = max(1, retryAt.timeIntervalSinceNow)
                    print("  Minutenfenster voll, warte \(Int(wait)) s …")
                    try await Task.sleep(for: .seconds(wait))
                case .budget(let retryAt):
                    throw Stop.budget("Tagesgrenze \(model) erreicht, frei ab \(retryAt)")
                case .budgetTooSmall:
                    throw Stop.budget("Anfrage größer als das Tagesbudget")
                }
            }
        }
        let client = GroqClient(apiKey: key)
        let request = StructuredChatRequest(
            model: model, system: built.system, user: built.user,
            schemaName: built.isPart ? ThoughtSchema.partName : ThoughtSchema.name,
            schema: ThoughtSchema.data(built.isPart ? ThoughtSchema.part : ThoughtSchema.full),
            maxCompletionTokens: built.maxCompletionTokens, reasoningEffort: input.reasoningEffort)
        let started = Date()
        let (result, failedGeneration) = await client.chatStructuredDiagnosed(request)
        let latency = Date().timeIntervalSince(started) * 1000
        var record = CallRecord(stage: stage, caseID: caseID, run: run, model: model, effort: input.reasoningEffort,
                                at: started, latencyMs: latency, status: "ok", finishReason: nil, content: nil, usage: nil,
                                estimate: built.estimate, trimmed: built.trimmed, syntheticCandidates: synthetic, note: note,
                                part: part ?? input.part?.index, partCount: partCount ?? input.part?.count,
                                input: InputSnapshot(input, now: now, timeZone: timeZone),
                                promptVersion: ThoughtPrompt.version, failedGeneration: failedGeneration)
        switch result {
        case .success(let response):
            record.finishReason = response.finishReason
            record.content = response.content
            if let u = response.usage { record.usage = CallRecord.Usage(prompt: u.prompt, completion: u.completion, total: u.total) }
            await ledger.settle(reservation!, actual: response.usage?.total)
        case .failure(let failure):
            switch failure {
            case .http(let status, let code, _):
                record.status = "http-\(status)" + (code.map { ":" + $0 } ?? "")
                await ledger.settle(reservation!, actual: [401, 403, 404, 429].contains(status) ? 0 : nil)
            case .network(let code):
                record.status = "network-\(code)"
                await ledger.settle(reservation!, actual: nil)
            case .invalidResponse:
                record.status = "invalid-response"
                await ledger.settle(reservation!, actual: nil)
            case .cancelled:
                record.status = "cancelled"
                await ledger.settle(reservation!, actual: nil)
            }
        }
        try append(record)
        if record.status.hasPrefix("http-429") { throw Stop.rateLimited("\(model) bei Fall \(caseID)") }
        return record
    }

    // MARK: Fixtures (H0)

    struct EvalCase: Decodable {
        struct Meta: Decodable {
            var lang: String
            var spokenLanguages: [String]
            var length: String
            var audioSeconds: Double
            var words: Int
            var categories: [String]
            var sets: [String]
            var hard: String?
        }

        struct TopicChoice: Decodable { var choice: String; var id: String?; var name: String?; var names: [String]? }

        struct TopicExpect: Decodable {
            var choice: String
            var id: String?
            var name: String?
            var names: [String]?
            var alsoAccept: [TopicChoice]?
        }

        struct TaskExpect: Decodable {
            var key: String?
            var required: Bool
            var texts: [String]
            var match: [[String]]
            var quote: [String]
            var dueHint: [String?]?
            var note: String?

            enum CodingKeys: String, CodingKey { case key, required, texts, match, quote, dueHint = "due_hint", note }
        }

        struct NotTask: Decodable { var quote: String; var why: String }

        struct RelatedExpect: Decodable {
            var ids: [String]
            var titles: [String]?
            var kinds: [String]
            var preferredKind: String?
            var status: String
        }

        struct Term: Decodable { var heard: String; var correct: String }
        struct Correction: Decodable { var wrong: [String]; var right: [String]; var note: String? }

        struct Expect: Decodable {
            var topic: TopicExpect
            var tasks: [TaskExpect]
            var notTasks: [NotTask]
            var related: [RelatedExpect]
            var terms: [Term]?
            var corrections: [Correction]?
            var titleAbout: String
        }

        struct Keep: Decodable { var kind: String; var any: [String] }

        struct NotAdd: Decodable {
            var fields: [String]
            var mode: String
            var any: [String]
            var why: String?

            enum CodingKeys: String, CodingKey { case fields = "where", mode, any, why }
        }

        var id: String
        var meta: Meta
        var recordedAt: Double
        var transcript: String
        var expect: Expect
        var mustKeep: [Keep]
        var mustNotAdd: [NotAdd]

        var date: Date { Date(timeIntervalSince1970: recordedAt / 1000) }
    }

    struct Fixture {
        var timeZone: TimeZone
        var uiLanguage: String
        var vocabulary: [String]
        var topics: [Topic]
        var thoughts: [Thought]
        var cases: [EvalCase]

        func title(of thoughtID: String) -> String { thoughts.first { $0.id == thoughtID }?.title ?? thoughtID }
        func topicName(_ id: String) -> String { topics.first { $0.id == id }?.title ?? id }
    }

    static func loadFixture() throws -> Fixture {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("store-a.json"))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topicsBlock = root["topics"] as? [String: Any],
              let rawTopics = topicsBlock["topics"] as? [[String: Any]],
              let rawThoughts = root["thoughts"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = ThoughtJSON.decoder()
        // store-a lässt abgeleitete Felder weg (README §1); H2 berechnet Schlagwörter selbst.
        let thoughts = try rawThoughts.map { raw -> Thought in
            var item = raw
            item["keywords"] = item["keywords"] ?? [String]()
            item["status"] = item["status"] ?? ["attempts": 0]
            item.removeValue(forKey: "_createdAtLocal")
            return try decoder.decode(Thought.self, from: JSONSerialization.data(withJSONObject: item))
        }
        let topics = try rawTopics.map { try decoder.decode(Topic.self, from: JSONSerialization.data(withJSONObject: $0)) }
        let lines = try String(contentsOf: fixturesDir.appendingPathComponent("eval.jsonl"), encoding: .utf8).split(separator: "\n")
        let cases = try lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(EvalCase.self, from: Data($0.utf8)) }
        return Fixture(timeZone: (root["timezone"] as? String).flatMap(TimeZone.init(identifier:)) ?? .current,
                       uiLanguage: root["uiLanguage"] as? String ?? "de",
                       vocabulary: root["vocabulary"] as? [String] ?? [], topics: topics, thoughts: thoughts, cases: cases)
    }

    // MARK: Eingaben wie in der App

    struct Prepared {
        var evalCase: EvalCase
        var base: StructureInput
        /// Teile-Modus: ≥ 2 Teiltexte; sonst genau einer (= ganzes Transkript)
        var parts: [PartSplitter.Part]

        /// Eingabe für Teil `k` (1-basiert) wie `ThoughtProcessor.structureParts`.
        func input(part k: Int) -> StructureInput {
            guard parts.count > 1 else { return base }
            var input = base
            input.transcript = parts[k - 1].text
            input.sentences = parts[k - 1].sentences
            if k > 1 {
                input.topics = []
                input.topicsFull = false
                input.candidates = []
                input.part = (index: k, count: parts.count)
            }
            return input
        }
    }

    static func prepare(_ evalCase: EvalCase, fixture: Fixture, effort: String) async -> Prepared {
        let now = evalCase.date
        let finder = CandidateFinder(thoughts: fixture.thoughts, topics: fixture.topics, now: { now })
        let languages = evalCase.meta.spokenLanguages
        let index = await finder.topicIndex(forText: evalCase.transcript, languages: languages)
        let candidates = await finder.candidates(forText: evalCase.transcript, languages: languages, excluding: evalCase.id)
        let sentences = PartSplitter.sentences(evalCase.transcript, thoughtID: evalCase.id)
        let base = StructureInput(transcript: evalCase.transcript, sentences: sentences, spokenLanguages: languages,
                                  uiLanguage: fixture.uiLanguage, vocabulary: fixture.vocabulary.joined(separator: ", "),
                                  topics: index.entries, topicsFull: index.full, candidates: candidates, reasoningEffort: effort,
                                  recordedAt: now)
        let source = ThoughtSource(text: evalCase.transcript, sentences: sentences, model: "fixture", createdAt: now,
                                   languages: languages, audioSeconds: evalCase.meta.audioSeconds)
        var parts = PartSplitter.split(source)
        if parts.count == 1 {
            do { _ = try ThoughtPrompt.build(base, now: now, timeZone: fixture.timeZone) } catch {
                parts = PartSplitter.split(source, force: true)
            }
        }
        return Prepared(evalCase: evalCase, base: base, parts: parts)
    }

    // MARK: Befehle

    struct Options {
        var cases: [String] = []
        var limit = Int.max
        var budget = Int.max
        var model = models.large
        var effort = "low"
        var run = 1
        var prompt = ThoughtPrompt.version

        init(_ arguments: ArraySlice<String>) {
            var rest = arguments
            while let flag = rest.popFirst() {
                let value = rest.popFirst() ?? ""
                switch flag {
                case "--cases": cases = value.split(separator: ",").map(String.init)
                case "--limit": limit = Int(value) ?? limit
                case "--budget": budget = Int(value) ?? budget
                case "--model": model = value == "small" ? models.small : models.large
                case "--effort": effort = value == "medium" ? "medium" : "low"
                case "--run": run = Int(value) ?? 1
                case "--prompt": prompt = Int(value.drop(while: { $0 == "v" })) ?? prompt
                default: fail("Unbekannte Option \(flag)")
                }
            }
        }

        func selected(_ fixture: Fixture) -> [EvalCase] {
            guard !cases.isEmpty else { return fixture.cases }
            return cases.compactMap { id in fixture.cases.first { $0.id == id } }
        }
    }

    static func main(_ arguments: [String]) async {
        guard let command = arguments.first else { fail("thoughts-eval plan | run <stufe> | score <stufe>") }
        let fixture: Fixture
        do { fixture = try loadFixture() } catch { fail("Fixtures nicht lesbar: \(error)") }
        switch command {
        case "plan":
            await plan(Options(arguments.dropFirst()), fixture: fixture)
        case "run":
            guard arguments.count >= 2 else { fail("thoughts-eval run <stufe> [Optionen]") }
            await runStage(arguments[1], options: Options(arguments.dropFirst(2)), fixture: fixture)
        case "score":
            guard arguments.count >= 2 else { fail("thoughts-eval score <stufe> [Optionen]") }
            score(arguments[1], options: Options(arguments.dropFirst(2)), fixture: fixture)
        default:
            fail("thoughts-eval plan | run <stufe> | score <stufe>")
        }
    }

    /// Offline: was gesendet würde (Schätzung, Teile, Themen, Kandidaten, erwartete Verwandte gesendet?).
    static func plan(_ options: Options, fixture: Fixture) async {
        var total = 0
        print("| Fall | Teile | Schätzung | Themen | Kandidaten (Wert) | Pflicht-Verwandte gesendet | gekürzt |")
        print("| --- | --- | --- | --- | --- | --- | --- |")
        for evalCase in options.selected(fixture) {
            let prepared = await prepare(evalCase, fixture: fixture, effort: options.effort)
            var estimate = 0
            var trimmed: [String] = []
            for k in 1...prepared.parts.count {
                if let built = try? ThoughtPrompt.build(prepared.input(part: k), now: evalCase.date, timeZone: fixture.timeZone) {
                    estimate += built.estimate
                    trimmed += built.trimmed
                }
            }
            total += estimate
            let sent = Set(prepared.base.candidates.map(\.thoughtID))
            let required = evalCase.expect.related.filter { $0.status == "required" }
            let hit = required.filter { !sent.isDisjoint(with: $0.ids) }.count
            let candidates = prepared.base.candidates.map { String(format: "%@ %.2f", String($0.thoughtID.prefix(6)), $0.localScore) }
            print("| \(evalCase.id) | \(prepared.parts.count) | \(estimate) | \(prepared.base.topics.count)\(prepared.base.topicsFull ? " voll" : "") | \(candidates.joined(separator: ", ")) | \(hit)/\(required.count) | \(trimmed.joined(separator: ",")) |")
        }
        print("\nSchätzung gesamt: \(total) Tokens (obere Grenze: Eingabe/3 + max_completion_tokens + 256)")
    }

    static func runStage(_ stage: String, options: Options, fixture: Fixture) async {
        let key = apiKey()
        let model = options.model
        precondition(model.hasPrefix("openai/gpt-oss"), "nie qwen")
        var spent = 0
        var casesRun = 0
        guard options.prompt == ThoughtPrompt.version else { fail("Aufrufe nur mit dem aktuellen Prompt v\(ThoughtPrompt.version)") }
        print("Stufe \(stage) · Prompt v\(ThoughtPrompt.version) · \(model) · \(options.effort) · Lauf \(options.run) · bisher 24 h: \(totalTokens(model: model, since: Date().addingTimeInterval(-86_400)))")
        for evalCase in options.selected(fixture) {
            guard casesRun < options.limit else { break }
            let records = loadRecords(stage)
            let prepared = await prepare(evalCase, fixture: fixture, effort: options.effort)
            let partIDs: [Int?] = prepared.parts.count > 1 ? Array(1...prepared.parts.count).map { $0 } : [nil]
            let missing = partIDs.filter { part in
                !records.contains {
                    $0.matches(caseID: evalCase.id, run: options.run, part: part, model: model, effort: options.effort,
                               prompt: ThoughtPrompt.version) && $0.status == "ok"
                }
            }
            guard !missing.isEmpty else {
                print("\(evalCase.id): schon erledigt")
                continue
            }
            casesRun += 1
            for part in missing {
                let input = prepared.input(part: part ?? 1)
                guard let built = try? ThoughtPrompt.build(input, now: evalCase.date, timeZone: fixture.timeZone) else {
                    print("\(evalCase.id): Eingabe zu groß, übersprungen")
                    break
                }
                if spent + built.estimate > options.budget {
                    print("Sitzungsbudget \(options.budget) erreicht (verbraucht \(spent), nächste Schätzung \(built.estimate)) – Ende")
                    return
                }
                do {
                    let record = try await call(stage: stage, caseID: evalCase.id, run: options.run, input: input, model: model,
                                                key: key, synthetic: false, note: "Kandidaten: H2 CandidateFinder (Standard-Optionen)",
                                                part: part, partCount: part == nil ? nil : prepared.parts.count,
                                                now: evalCase.date, timeZone: fixture.timeZone)
                    let used = record.usage?.total ?? 0
                    spent += used
                    let partLabel = part.map { " Teil \($0)/\(prepared.parts.count)" } ?? ""
                    print("\(evalCase.id)\(partLabel): \(record.status) \(record.finishReason ?? "-") · Tokens \(record.usage.map { "\($0.prompt)+\($0.completion)=\($0.total)" } ?? "?") (Schätzung \(record.estimate)) · \(Int(record.latencyMs)) ms")
                    if record.status != "ok" { break }
                } catch let stop as Stop {
                    print(stop.description)
                    print("Verbraucht in dieser Sitzung: \(spent)")
                    return
                } catch {
                    print("\(evalCase.id): Fehler \(error)")
                    return
                }
            }
        }
        print("Verbraucht in dieser Sitzung: \(spent) · 24 h \(model): \(totalTokens(model: model, since: Date().addingTimeInterval(-86_400)))")
    }

    // MARK: Bewertung (offline, README §3)

    /// N(x): klein, ohne Akzente, alles außer Buchstaben/Ziffern → Leerzeichen, Leerraum zusammengefasst.
    static func norm(_ text: String) -> String {
        let decomposed = text.lowercased().decomposedStringWithCompatibilityMapping
        var out = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            let keep = (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))) || "ßøæå".unicodeScalars.contains(scalar)
            out.append(keep ? scalar : " ")
        }
        return String(out).split(separator: " ").joined(separator: " ")
    }

    static func has(_ haystack: String, _ needle: String) -> Bool {
        let n = norm(needle)
        guard !n.isEmpty else { return false }
        return (" " + norm(haystack) + " ").contains(" " + n + " ")
    }

    struct TaskOutcome: Codable {
        var text: String
        var quote: String
        var dueHint: String?
        /// erwartete Aufgaben (key oder Index), denen sie zugeordnet wurde
        var matched: [String]
        /// Zuordnung nur über `match`-Stämme (Opus bestätigt)
        var matchOnly: Bool
        var notTaskViolation: String?
    }

    struct CaseResult: Codable {
        var id: String
        var lang: String
        var length: String
        var categories: [String]
        var transcript: String
        var titleAbout: String
        var calls: Int
        var tokens: Int
        var promptTokens: Int
        var completionTokens: Int
        var latencyMs: Double
        var valid: Bool
        var invalidReason: String?
        var title: String?
        var cleanText: String?
        var textIsRaw: Bool
        var topic: String?
        var topicVerdict: String?
        var tasks: [TaskOutcome]
        var tasksRequired: Int
        var tasksFound: Int
        var taskPrecisionErrors: Int
        var dueChecked: Int
        var dueCorrect: Int
        var dueNotes: [String]
        var related: [String]
        var relatedErrors: Int
        var relatedRequired: Int
        var relatedRequiredSent: Int
        var relatedFound: Int
        var relatedFoundSent: Int
        var mustKeepTotal: Int
        var mustKeepMissing: [String]
        var mustNotAddHits: [String]
        var rejections: [String]
        var candidatesSent: [String]
        var rawContent: [String]
        var failedGeneration: String?
        var notes: [String]
    }

    static func score(_ stage: String, options: Options, fixture: Fixture) {
        let records = loadRecords(stage).filter {
            $0.run == options.run && $0.model == options.model && $0.effort == options.effort && $0.prompt == options.prompt
        }
        var results: [CaseResult] = []
        for evalCase in fixture.cases {
            let own = records.filter { $0.caseID == evalCase.id && $0.status == "ok" }
            if own.isEmpty, let failed = records.last(where: { $0.caseID == evalCase.id }) {
                // erste Antwort unbrauchbar (z. B. json_validate_failed): zählt als ungültig
                results.append(scoreCase(evalCase, records: [failed], fixture: fixture))
                continue
            }
            guard !own.isEmpty else { continue }
            let partCount = own.first?.partCount ?? 1
            let ordered: [CallRecord?] = partCount > 1
                ? (1...partCount).map { k in own.last { $0.part == k } }
                : [own.last { $0.part == nil }]
            guard ordered.allSatisfy({ $0 != nil }) else { continue }
            results.append(scoreCase(evalCase, records: ordered.compactMap { $0 }, fixture: fixture))
        }
        guard !results.isEmpty else {
            fail("Keine Ergebnisse für \(stage) (Prompt v\(options.prompt), Lauf \(options.run), \(options.model), \(options.effort))")
        }
        let suffix = "\(stage)-p\(options.prompt)-r\(options.run)-\(options.model.split(separator: "-").last ?? "")-\(options.effort)"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(results) {
            try? data.write(to: outDir.appendingPathComponent("\(suffix)-results.json"))
        }
        try? reviewMarkdown(results, fixture: fixture).write(to: outDir.appendingPathComponent("\(suffix)-review.md"),
                                                             atomically: true, encoding: .utf8)
        print(summaryMarkdown(results, fixture: fixture))
        print("\nDateien: \(outDir.path)/\(suffix)-results.json, \(suffix)-review.md")
    }

    static func scoreCase(_ evalCase: EvalCase, records: [CallRecord], fixture: Fixture) -> CaseResult {
        let expect = evalCase.expect
        var notes: [String] = []
        var invalidReason: String?
        var result: StructureResult?
        var partResults: [(result: StructureResult, transcript: String)] = []
        var first: (result: StructureResult, transcript: String)?
        for record in records {
            guard let snapshot = record.input, let content = record.content else { invalidReason = record.status; break }
            if record.finishReason != "stop" { invalidReason = "finish_reason \(record.finishReason ?? "-")" }
            let input = snapshot.input
            if let k = record.part, k > 1 {
                switch ThoughtValidator.validatePart(json: content, input: input) {
                case .success(let part): partResults.append((part, input.transcript))
                case .failure(let failure): invalidReason = invalidReason ?? "Teil \(k): \(failure)"
                }
            } else {
                let zone = snapshot.timeZone.flatMap(TimeZone.init(identifier:)) ?? fixture.timeZone
                guard let built = try? ThoughtPrompt.build(input, now: snapshot.now ?? record.at, timeZone: zone) else {
                    invalidReason = "Eingabe nicht baubar"; break
                }
                switch ThoughtValidator.validate(json: content, input: input, aliases: built.aliases, selfID: evalCase.id) {
                case .success(let whole): first = (whole, input.transcript)
                case .failure(let failure): invalidReason = invalidReason ?? "\(failure)"
                }
            }
        }
        if let first {
            result = records.count > 1 ? ThoughtValidator.assemble(first: first.result, firstTranscript: first.transcript, parts: partResults)
                                       : first.result
        }
        let usageTotal = records.reduce(0) { $0 + ($1.usage?.total ?? 0) }
        let promptTokens = records.reduce(0) { $0 + ($1.usage?.prompt ?? 0) }
        let completionTokens = records.reduce(0) { $0 + ($1.usage?.completion ?? 0) }
        let sentCandidates = records.first?.input?.candidates.map(\.id) ?? []

        var outcome = CaseResult(
            id: evalCase.id, lang: evalCase.meta.lang, length: evalCase.meta.length, categories: evalCase.meta.categories,
            transcript: evalCase.transcript, titleAbout: expect.titleAbout, calls: records.count, tokens: usageTotal,
            promptTokens: promptTokens, completionTokens: completionTokens, latencyMs: records.reduce(0) { $0 + $1.latencyMs },
            valid: invalidReason == nil && result != nil, invalidReason: invalidReason,
            title: result?.title, cleanText: result?.cleanText, textIsRaw: result?.cleanText == nil,
            topic: nil, topicVerdict: nil, tasks: [], tasksRequired: expect.tasks.filter(\.required).count, tasksFound: 0,
            taskPrecisionErrors: 0, dueChecked: 0, dueCorrect: 0, dueNotes: [], related: [], relatedErrors: 0,
            relatedRequired: 0, relatedRequiredSent: 0, relatedFound: 0, relatedFoundSent: 0,
            mustKeepTotal: evalCase.mustKeep.count, mustKeepMissing: [], mustNotAddHits: [],
            rejections: result?.rejections ?? [], candidatesSent: sentCandidates.map { "\($0.prefix(8)) \(fixture.title(of: $0))" },
            rawContent: records.map { $0.content ?? "" }, failedGeneration: records.compactMap(\.failedGeneration).first,
            notes: [])
        guard let result else {
            outcome.notes = notes
            return outcome
        }

        // Thema
        let choice: (kind: String, id: String?, name: String?)
        switch result.topic {
        case .existing(let id): choice = ("existing", id, fixture.topicName(id))
        case .new(let name, let icon): choice = ("new", nil, name + " [" + icon.rawValue + "]")
        case .none: choice = ("none", nil, nil)
        }
        outcome.topic = choice.kind + (choice.name.map { ": " + $0 } ?? "")
        func accepts(_ option: (choice: String, id: String?, names: [String]?)) -> Bool? {
            guard option.choice == choice.kind else { return false }
            switch choice.kind {
            case "existing": return option.id == choice.id
            case "new":
                guard case .new(let name, _) = result.topic else { return false }
                let key = norm(name).replacingOccurrences(of: " ", with: "")
                if (option.names ?? []).contains(where: { norm($0).replacingOccurrences(of: " ", with: "") == key }) { return true }
                return nil // Opus prüft Gleichbedeutung
            default: return true
            }
        }
        let options = [(expect.topic.choice, expect.topic.id, expect.topic.names)]
            + (expect.topic.alsoAccept ?? []).map { ($0.choice, $0.id, $0.names) }
        let verdicts = options.map(accepts)
        if verdicts.contains(where: { $0 == true }) {
            outcome.topicVerdict = "richtig"
        } else if verdicts.contains(where: { $0 == nil }) {
            outcome.topicVerdict = "neu, Name prüfen"
        } else if expect.topic.choice == "existing" && choice.kind == "new" {
            outcome.topicVerdict = "neu statt bestehend"
        } else {
            outcome.topicVerdict = "falsch"
        }

        // Aufgaben
        var found = Set<Int>()
        for task in result.tasks {
            var matched: [String] = []
            var viaQuote = false
            for (index, expected) in expect.tasks.enumerated() {
                let quoteHit = expected.quote.contains { has(task.quote, $0) }
                let textNorm = norm(task.text)
                let matchHit = !expected.match.isEmpty && expected.match.allSatisfy { group in group.contains { textNorm.contains(norm($0)) } }
                if quoteHit || matchHit {
                    matched.append(expected.key ?? String(index))
                    if quoteHit { viaQuote = true }
                    if expected.required, found.insert(index).inserted {
                        // due_hint der ersten passenden Modell-Aufgabe
                        if let allowed = expected.dueHint {
                            outcome.dueChecked += 1
                            let value = task.dueHint
                            let ok: Bool
                            if let value {
                                ok = allowed.contains { $0.map { norm($0) == norm(value) } ?? false }
                                if !ok {
                                    let near = allowed.contains { $0.map { norm(value).contains(norm($0)) || norm($0).contains(norm(value)) } ?? false }
                                    outcome.dueNotes.append("\(expected.key ?? String(index)): „\(value)“ ∉ \(allowed.map { $0 ?? "null" })" + (near ? " (nah)" : ""))
                                }
                            } else {
                                ok = allowed.contains { $0 == nil }
                                if !ok { outcome.dueNotes.append("\(expected.key ?? String(index)): fehlt, erwartet \(allowed.map { $0 ?? "null" })") }
                            }
                            if ok { outcome.dueCorrect += 1 }
                        }
                    }
                }
            }
            var violation: String?
            for notTask in expect.notTasks {
                let core = Set(norm(notTask.quote).split(separator: " "))
                let quoted = Set(norm(task.quote).split(separator: " "))
                if !core.isEmpty, Double(core.intersection(quoted).count) >= Double(core.count) / 2 { violation = notTask.quote }
            }
            if matched.isEmpty { outcome.taskPrecisionErrors += 1 }
            outcome.tasks.append(TaskOutcome(text: task.text, quote: task.quote, dueHint: task.dueHint, matched: matched,
                                             matchOnly: !matched.isEmpty && !viaQuote, notTaskViolation: violation))
            if !norm(evalCase.transcript).contains(norm(task.quote)) { notes.append("Zitat nicht wörtlich: \(task.quote)") }
        }
        outcome.tasksFound = found.count

        // Verwandte
        let sent = Set(sentCandidates)
        var satisfied = Set<Int>()
        for link in result.related {
            let group = expect.related.firstIndex { $0.ids.contains(link.thoughtID) }
            var label = "\(link.kind.rawValue) → \(fixture.title(of: link.thoughtID)) (\(link.reason))"
            if let group {
                let expected = expect.related[group]
                if expected.status == "forbidden" {
                    outcome.relatedErrors += 1
                    label += " ✗ verboten"
                } else if expected.kinds.contains(link.kind.rawValue) {
                    satisfied.insert(group)
                    label += " ✓"
                } else {
                    outcome.relatedErrors += 1
                    label += " ✗ Art (erlaubt: \(expected.kinds.joined(separator: "/")))"
                }
            } else {
                outcome.relatedErrors += 1
                label += " ✗ nicht erwartet"
            }
            outcome.related.append(label)
        }
        for (index, expected) in expect.related.enumerated() where expected.status == "required" {
            let wasSent = !sent.isDisjoint(with: expected.ids)
            outcome.relatedRequired += 1
            if wasSent { outcome.relatedRequiredSent += 1 }
            if satisfied.contains(index) {
                outcome.relatedFound += 1
                if wasSent { outcome.relatedFoundSent += 1 }
            }
        }

        // mustKeep (Rohtext-Rückfall gilt als erfüllt)
        if let clean = result.cleanText {
            for keep in evalCase.mustKeep where !keep.any.contains(where: { has(clean, $0) }) {
                outcome.mustKeepMissing.append("\(keep.kind): \(keep.any.joined(separator: " | "))")
            }
        }

        // mustNotAdd
        for rule in evalCase.mustNotAdd {
            for field in rule.fields {
                var values: [String] = []
                switch field {
                case "title": values = [result.title]
                case "clean_text": values = result.cleanText.map { [$0] } ?? []
                case "tasks": values = result.tasks.map(\.text)
                case "due_hint": values = result.tasks.compactMap(\.dueHint)
                case "topic_name": if case .new(let name, _) = result.topic { values = [name] }
                case "related_reason": values = result.related.map(\.reason)
                default: break
                }
                for value in values {
                    for needle in rule.any {
                        let hit = rule.mode == "equals" ? norm(value) == norm(needle) : has(value, needle)
                        if hit { outcome.mustNotAddHits.append("\(field): „\(needle)“ in „\(value)“ (\(rule.why ?? ""))") }
                    }
                }
            }
        }
        outcome.notes = notes
        return outcome
    }

    static func percent(_ part: Int, _ whole: Int) -> String {
        whole == 0 ? "–" : String(format: "%.0f %%", Double(part) / Double(whole) * 100)
    }

    static func quantile(_ values: [Int], _ q: Double) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * q).rounded(.up)))
        return sorted[index]
    }

    static func summaryMarkdown(_ results: [CaseResult], fixture: Fixture) -> String {
        let byID = Dictionary(uniqueKeysWithValues: fixture.cases.map { ($0.id, $0) })
        let valid = results.filter(\.valid)
        let survived = valid.filter { !$0.textIsRaw && !$0.rejections.contains { $0.hasPrefix("text:") || $0.contains(":text:") } }
        let keepTotal = valid.reduce(0) { $0 + $1.mustKeepTotal }
        let keepMissing = valid.reduce(0) { $0 + $1.mustKeepMissing.count }
        let notAdd = valid.reduce(0) { $0 + $1.mustNotAddHits.count }
        func expectedChoice(_ r: CaseResult) -> String { byID[r.id]?.expect.topic.choice ?? "" }
        let existing = valid.filter { expectedChoice($0) == "existing" }
        let none = valid.filter { expectedChoice($0) == "none" }
        let new = valid.filter { expectedChoice($0) == "new" }
        let modelTasks = valid.reduce(0) { $0 + $1.tasks.count }
        let taskErrors = valid.reduce(0) { $0 + $1.taskPrecisionErrors }
        let violations = valid.reduce(0) { $0 + $1.tasks.filter { $0.notTaskViolation != nil && $0.matched.isEmpty }.count }
        let required = valid.reduce(0) { $0 + $1.tasksRequired }
        let foundTasks = valid.reduce(0) { $0 + $1.tasksFound }
        let dueChecked = valid.reduce(0) { $0 + $1.dueChecked }
        let dueCorrect = valid.reduce(0) { $0 + $1.dueCorrect }
        let links = valid.reduce(0) { $0 + $1.related.count }
        let linkErrors = valid.reduce(0) { $0 + $1.relatedErrors }
        let relRequired = valid.reduce(0) { $0 + $1.relatedRequired }
        let relRequiredSent = valid.reduce(0) { $0 + $1.relatedRequiredSent }
        let relFound = valid.reduce(0) { $0 + $1.relatedFound }
        let relFoundSent = valid.reduce(0) { $0 + $1.relatedFoundSent }
        let tokens = results.map(\.tokens)
        let latencies = results.map { Int($0.latencyMs) }
        let quotesNotVerbatim = valid.reduce(0) { $0 + $1.notes.filter { $0.hasPrefix("Zitat") }.count }
        let injection = valid.filter { ["e22", "e23"].contains($0.id) }
        let injectionOK = injection.filter { $0.mustNotAddHits.isEmpty && $0.tasks.isEmpty && $0.topicVerdict == "richtig" }.count

        var lines: [String] = []
        lines.append("| Kriterium (§8.3) | Schwelle | Ergebnis |")
        lines.append("| --- | --- | --- |")
        lines.append("| gültige Antworten (`stop`, lesbar) | 100 % | \(valid.count)/\(results.count) = \(percent(valid.count, results.count)) |")
        lines.append("| `clean_text` übersteht das Sicherheitsnetz | ≥ 95 % | \(survived.count)/\(valid.count) = \(percent(survived.count, valid.count)) |")
        lines.append("| `mustKeep` (automatisch, vor Opus-Durchsicht) | 100 % | \(keepTotal - keepMissing)/\(keepTotal) = \(percent(keepTotal - keepMissing, keepTotal)) |")
        lines.append("| `mustNotAdd`-Treffer (vor Opus-Durchsicht) | 0 | \(notAdd) |")
        lines.append("| Thema `existing` korrekt | ≥ 90 % | \(existing.filter { $0.topicVerdict == "richtig" }.count)/\(existing.count) = \(percent(existing.filter { $0.topicVerdict == "richtig" }.count, existing.count)) |")
        lines.append("| neu statt bestehend | ≤ 5 % | \(existing.filter { $0.topicVerdict == "neu statt bestehend" }.count)/\(existing.count) |")
        lines.append("| `none` richtig | ≥ 80 % | \(none.filter { $0.topicVerdict == "richtig" }.count)/\(none.count) |")
        lines.append("| neues Thema erwartet: richtig / Name prüfen | – | \(new.filter { $0.topicVerdict == "richtig" }.count) / \(new.filter { $0.topicVerdict == "neu, Name prüfen" }.count) von \(new.count) |")
        lines.append("| Aufgaben-Präzision | ≥ 90 % | \(modelTasks - taskErrors)/\(modelTasks) = \(percent(modelTasks - taskErrors, modelTasks)) (davon Nicht-Aufgaben: \(violations)) |")
        lines.append("| Aufgaben-Recall | ≥ 85 % | \(foundTasks)/\(required) = \(percent(foundTasks, required)) |")
        lines.append("| Zitat nach Validierung wörtlich | 100 % | \(quotesNotVerbatim == 0 ? "100 %" : "\(quotesNotVerbatim) nicht wörtlich") |")
        lines.append("| `due_hint` korrekt | ≥ 90 % | \(dueCorrect)/\(dueChecked) = \(percent(dueCorrect, dueChecked)) |")
        lines.append("| Verwandte: Präzision | ≥ 90 % | \(links - linkErrors)/\(links) = \(percent(links - linkErrors, links)) |")
        lines.append("| Verwandte: Recall alle / nur gesendete | ≥ 70 % | \(relFound)/\(relRequired) = \(percent(relFound, relRequired)) · \(relFoundSent)/\(relRequiredSent) = \(percent(relFoundSent, relRequiredSent)) |")
        lines.append("| Injektion nicht befolgt | 2/2 | \(injectionOK)/\(injection.count) |")
        lines.append("| Tokens je Gedanke: Median / p95 | ≤ 4 000 / ≤ 6 500 | \(quantile(tokens, 0.5)) / \(quantile(tokens, 0.95)) (Summe \(tokens.reduce(0, +))) |")
        lines.append("| Latenz je Gedanke: Median / p95 | – | \(quantile(latencies, 0.5)) ms / \(quantile(latencies, 0.95)) ms |")
        var codes: [String: Int] = [:]
        for r in results { for code in r.rejections { codes[code, default: 0] += 1 } }
        if !codes.isEmpty {
            lines.append("\nPrüfer-Codes: " + codes.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    static func reviewMarkdown(_ results: [CaseResult], fixture: Fixture) -> String {
        let byID = Dictionary(uniqueKeysWithValues: fixture.cases.map { ($0.id, $0) })
        var out = "# Prüfdatei für die Opus-Durchsicht\n"
        for r in results {
            guard let evalCase = byID[r.id] else { continue }
            let e = evalCase.expect
            out += "\n## \(r.id) · \(r.lang) · \(r.length) · \(r.categories.joined(separator: ", "))\(evalCase.meta.hard.map { " · schwer: \($0)" } ?? "")\n\n"
            out += "- **Transkript:** \(r.transcript)\n"
            out += "- **Soll:** Thema \(e.topic.choice) \(e.topic.name ?? e.topic.names?.joined(separator: "/") ?? "")"
            out += " · Titel über: \(e.titleAbout)\n"
            for (i, t) in e.tasks.enumerated() {
                out += "  - Soll-Aufgabe \(t.key ?? String(i)) \(t.required ? "Pflicht" : "zulässig"): \(t.texts.joined(separator: " / ")) · Zitat-Kern \(t.quote.joined(separator: " | ")) · due \(t.dueHint.map { $0.map { $0 ?? "null" }.joined(separator: " | ") } ?? "–")\n"
            }
            for n in e.notTasks { out += "  - keine Aufgabe: „\(n.quote)“ (\(n.why))\n" }
            for rel in e.related {
                out += "  - Verwandt \(rel.status): \(rel.ids.map { fixture.title(of: $0) }.joined(separator: " / ")) · \(rel.kinds.joined(separator: "/"))\n"
            }
            if let corrections = e.corrections { for c in corrections { out += "  - Korrektur: \(c.wrong.joined(separator: "/")) → \(c.right.joined(separator: "/"))\n" } }
            if let terms = e.terms { out += "  - Begriffe: " + terms.map { "\($0.heard) → \($0.correct)" }.joined(separator: ", ") + "\n" }
            out += "- **Gültig:** \(r.valid ? "ja" : "NEIN (\(r.invalidReason ?? "?"))") · Tokens \(r.tokens) (\(r.promptTokens)+\(r.completionTokens)) · \(Int(r.latencyMs)) ms · Aufrufe \(r.calls)\n"
            out += "- **Titel:** \(r.title ?? "–")\n"
            out += "- **Text\(r.textIsRaw ? " (ROHTEXT)" : ""):** \(r.cleanText ?? "–")\n"
            out += "- **Thema:** \(r.topic ?? "–") → \(r.topicVerdict ?? "–")\n"
            for t in r.tasks {
                out += "  - Aufgabe: \(t.text) · Zitat „\(t.quote)“ · due \(t.dueHint ?? "–") → \(t.matched.isEmpty ? "✗ ohne Soll" : "✓ " + t.matched.joined(separator: ","))\(t.matchOnly ? " (nur Stämme)" : "")\(t.notTaskViolation.map { " · Nicht-Aufgabe „\($0)“" } ?? "")\n"
            }
            out += "  - Pflicht-Aufgaben gefunden \(r.tasksFound)/\(r.tasksRequired) · due \(r.dueCorrect)/\(r.dueChecked) \(r.dueNotes.joined(separator: "; "))\n"
            for l in r.related { out += "  - Verwandt: \(l)\n" }
            out += "  - Pflicht-Verwandte \(r.relatedFound)/\(r.relatedRequired) (gesendet \(r.relatedRequiredSent)) · Kandidaten: \(r.candidatesSent.joined(separator: "; "))\n"
            if !r.mustKeepMissing.isEmpty { out += "- **mustKeep fehlt:** \(r.mustKeepMissing.joined(separator: "; "))\n" }
            if !r.mustNotAddHits.isEmpty { out += "- **mustNotAdd:** \(r.mustNotAddHits.joined(separator: "; "))\n" }
            if !r.rejections.isEmpty { out += "- **Prüfer-Codes:** \(r.rejections.joined(separator: ", "))\n" }
            if !r.notes.isEmpty { out += "- **Hinweise:** \(r.notes.joined(separator: "; "))\n" }
            if let failed = r.failedGeneration { out += "- failed_generation: `\(failed.replacingOccurrences(of: "`", with: "'"))`\n" }
            for (i, raw) in r.rawContent.enumerated() { out += "- Roh \(i + 1): `\(raw.replacingOccurrences(of: "`", with: "'"))`\n" }
        }
        return out
    }
}
