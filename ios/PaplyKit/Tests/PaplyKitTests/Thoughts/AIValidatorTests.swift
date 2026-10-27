import Foundation
import Testing
@testable import PaplyKit

private typealias F = AIFixture

@Suite struct AIValidatorTitleTests {
    @Test func goodTitleIsKept() {
        #expect(F.validate(F.answer()).title == "Wohnung Oranienstraße Unterlagen")
    }

    @Test func quotesAndFinalPeriodAreRemoved() {
        #expect(F.validate(F.answer(title: "„Wohnung Oranienstraße.“")).title == "Wohnung Oranienstraße")
        #expect(F.validate(F.answer(title: "\"Makler Oranienstraße\"…")).title == "Makler Oranienstraße")
    }

    @Test func onlyTheFirstLineCounts() {
        #expect(F.validate(F.answer(title: "Makler Oranienstraße\nzweite Zeile")).title == "Makler Oranienstraße")
    }

    @Test func tooLongTitleFallsBack() {
        let result = F.validate(F.answer(title: String(repeating: "Wohnung ", count: 10)))
        #expect(result.rejections.contains("title"))
        #expect(result.title == "Zur Wohnung in der Oranienstraße: Ich …")
    }

    @Test func newDigitInTitleFallsBack() {
        #expect(F.validate(F.answer(title: "Miete 1.500 Euro")).rejections.contains("title"))
        #expect(F.validate(F.answer(title: "Miete 1.450 Euro")).title == "Miete 1.450 Euro")
    }

    @Test func titleWithoutTranscriptWordFallsBack() {
        let result = F.validate(F.answer(title: "Neues Zuhause"))
        #expect(result.rejections.contains("title"))
    }

    @Test func inflectedWordCountsAsTranscriptWord() {
        #expect(!F.validate(F.answer(title: "Unterlagen an Makler")).rejections.contains("title"))
    }

    @Test func emptyTitleUsesTextStart() {
        let result = F.validate(F.answer(title: ""))
        #expect(result.title == "Zur Wohnung in der Oranienstraße: Ich …")
        #expect(result.rejections.contains("title"))
    }

    @Test func fallbackFromRawSkipsFillersAndShortTextHasNoEllipsis() {
        #expect(ThoughtValidator.fallbackTitle("Ähm, zur Wohnung in der Oranienstraße, ich hab") == "zur Wohnung in der Oranienstraße, ich …")
        #expect(ThoughtValidator.fallbackTitle("Ähm, zur Wohnung in der Oranienstraße, ich") == "zur Wohnung in der Oranienstraße, ich")
        #expect(ThoughtValidator.fallbackTitle("Ähm, äh Milch kaufen.") == "Milch kaufen")
        #expect(ThoughtValidator.fallbackTitle("Eins zwei drei vier fünf sechs sieben") == "Eins zwei drei vier fünf sechs …")
    }

    @Test func cjkTitleNeedsASharedCharacterPair() {
        let input = F.input(transcript: "我明天要去看那套公寓，然后给中介打电话。", topics: [], candidates: [])
        let ok = F.validate(F.answer(title: "那套公寓", clean: "我明天要去看那套公寓，然后给中介打电话。", topic: F.topic("none")), input)
        #expect(ok.title == "那套公寓")
        let bad = F.validate(F.answer(title: "旅行计划", clean: "我明天要去看那套公寓，然后给中介打电话。", topic: F.topic("none")), input)
        #expect(bad.rejections.contains("title"))
    }
}

@Suite struct AIValidatorTextTests {
    @Test func cleanTextWithParagraphsIsKept() {
        let result = F.validate(F.answer())
        #expect(result.cleanText == F.goodClean)
        #expect(!result.rejections.contains { $0.hasPrefix("text") })
    }

    @Test func summaryIsRejected() {
        let result = F.validate(F.answer(clean: "Makler angerufen, Unterlagen bis Freitag."))
        #expect(result.cleanText == nil)
        #expect(result.rejections.contains("text:length"))
    }

    @Test func droppedNegationIsRejected() {
        let clean = F.goodClean.replacingOccurrences(of: "und nicht verhandelbar", with: "und verhandelbar")
        #expect(F.validate(F.answer(clean: clean)).rejections.contains("text:negation"))
    }

    @Test func changedNumberIsRejected() {
        let clean = F.goodClean.replacingOccurrences(of: "1.450", with: "1.540")
        #expect(F.validate(F.answer(clean: clean)).rejections.contains("text:digits"))
    }

    @Test func inventedContentIsRejected() {
        let clean = F.goodClean + " Außerdem sollte ich unbedingt einen Umzugswagen reservieren, die Nachbarn informieren und Kartons besorgen."
        let result = F.validate(F.answer(clean: clean))
        #expect(result.cleanText == nil)
        #expect(result.rejections.contains { $0 == "text:length" || $0 == "text:added" })
    }

    @Test func metaAnswerIsRejected() {
        #expect(F.validate(F.answer(clean: "Hier ist der bereinigte Text: " + F.goodClean)).rejections.contains("text:meta"))
    }

    @Test func bulletListFromSpokenEnumerationIsKept() {
        let transcript = "Für den Umzug brauche ich ähm Kartons, Klebeband, Luftpolsterfolie und einen Transporter."
        let clean = "Für den Umzug brauche ich:\n• Kartons\n• Klebeband\n• Luftpolsterfolie\n• einen Transporter"
        let result = F.validate(F.answer(title: "Umzug Material", clean: clean), F.input(transcript: transcript))
        #expect(result.cleanText == clean)
    }

    @Test func emptyCleanTextButTitleKeepsTheRest() {
        let result = F.validate(F.answer(clean: ""))
        #expect(result.cleanText == nil)
        #expect(result.rejections.contains("text:empty"))
        #expect(result.topic == .existing("t_umzug"))
    }

    @Test func bothEmptyIsUnusable() {
        let input = F.input()
        let aliases = try! ThoughtPrompt.build(input).aliases
        #expect(ThoughtValidator.validate(json: F.answer(title: " ", clean: ""), input: input, aliases: aliases) == .failure(.empty))
    }

    @Test func unreadableJSONIsUnusable() {
        let input = F.input()
        let aliases = try! ThoughtPrompt.build(input).aliases
        #expect(ThoughtValidator.validate(json: "{\"title\": \"x\"", input: input, aliases: aliases) == .failure(.unreadable))
        #expect(ThoughtValidator.validate(json: "{\"title\": \"x\", \"clean_text\": \"y\"}", input: input, aliases: aliases)
                == .failure(.unreadable))
    }

    @Test func resolvedSelfCorrectionIsAccepted() {
        let transcript = "Wir treffen uns am Donnerstag um 15 Uhr, ich meine um 16 Uhr, im Café am Markt."
        let clean = "Wir treffen uns am Donnerstag um 16 Uhr im Café am Markt."
        let result = F.validate(F.answer(title: "Treffen Café am Markt", clean: clean, topic: F.topic("none")),
                                F.input(transcript: transcript))
        #expect(result.cleanText == clean)
    }
}

@Suite struct AIValidatorTopicTests {
    @Test func existingAliasMapsToRealID() {
        #expect(F.validate(F.answer(topic: F.topic("existing", id: "t1"))).topic == .existing("t_paply"))
    }

    @Test func unknownAliasBecomesNone() {
        let result = F.validate(F.answer(topic: F.topic("existing", id: "t9")))
        #expect(result.topic == .none && result.rejections.contains("topic:alias"))
        #expect(F.validate(F.answer(topic: F.topic("existing", id: "t_umzug"))).topic == .none)
    }

    @Test func existingWithoutIDBecomesNone() {
        #expect(F.validate(F.answer(topic: F.topic("existing"))).topic == .none)
    }

    @Test func validNewTopic() {
        #expect(F.validate(F.answer(topic: F.topic("new", name: "Schufa", symbol: "wallet"))).topic
                == .new(name: "Schufa", icon: .wallet))
    }

    @Test func unknownSymbolFallsBackToSparkles() {
        #expect(F.validate(F.answer(topic: F.topic("new", name: "Schufa", symbol: "rocket"))).topic
                == .new(name: "Schufa", icon: .sparkles))
    }

    @Test(arguments: ["Ideen", "Notiz", "Todo", "To-dos", "Sonstiges", "Ideas", "Aufgabe"])
    func genericNamesAreBlocked(name: String) {
        let result = F.validate(F.answer(topic: F.topic("new", name: name)))
        #expect(result.topic == .none && result.rejections.contains("topic:name"))
    }

    @Test(arguments: [("Wohnungen", "t_wohnung"), ("lissabon", "t_lissabon"), ("Lissbaon", "t_lissabon"), ("PAPLY", "t_paply"),
                      ("Umzugs", "t_umzug"), ("Paply.", "t_paply")])
    func variantsOfExistingTopicsBecomeExisting(name: String, id: String) {
        let result = F.validate(F.answer(topic: F.topic("new", name: name)))
        #expect(result.topic == .existing(id), "\(name)")
        #expect(result.rejections.contains("topic:duplicate"))
    }

    /// Unscharfe Nähe leitet nicht mehr um (früher Präfix, Levenshtein ≤ 2, ä = a): Es bleibt ein neues Thema;
    /// zusammenführen kann später ein Vorschlag der Themenpflege, den der Nutzer bestätigt.
    @Test(arguments: ["Wohnungssuche", "Lisabon", "Gärten", "Umzugsplanung"])
    func nearNamesStayNew(name: String) {
        let result = F.validate(F.answer(topic: F.topic("new", name: name)))
        #expect(result.topic == .new(name: name, icon: .home), "\(name)")
        #expect(!result.rejections.contains("topic:duplicate"))
    }

    @Test(arguments: ["Ein sehr langer Themenname", "Viel zu viele Wörter hier", "2024", "x"])
    func invalidNewNamesBecomeNone(name: String) {
        #expect(F.validate(F.answer(topic: F.topic("new", name: name))).topic == .none, "\(name)")
    }

    @Test func fullIndexAllowsNoNewTopic() {
        let input = F.input(topicsFull: true)
        let result = F.validate(F.answer(topic: F.topic("new", name: "Schufa")), input)
        #expect(result.topic == .none && result.rejections.contains("topic:full"))
        #expect(F.validate(F.answer(topic: F.topic("new", name: "Wohnungen")), input).topic == .existing("t_wohnung"))
    }

    @Test func noneStaysNone() {
        let result = F.validate(F.answer(topic: F.topic("none")))
        #expect(result.topic == .none && !result.rejections.contains { $0.hasPrefix("topic") })
    }
}

@Suite struct AIValidatorTaskTests {
    @Test func taskWithExactQuoteIsKeptAndQuoteIsTheRealSpan() {
        let result = F.validate(F.answer(tasks: [F.task("Unterlagen schicken", "ich muss bis freitag die unterlagen schicken", due: "bis Freitag")]))
        #expect(result.tasks == [TaskDraft(text: "Unterlagen schicken", quote: "Ich muss bis Freitag die Unterlagen schicken", dueHint: "bis Freitag")])
    }

    @Test func inventedQuoteDropsTheTask() {
        let result = F.validate(F.answer(tasks: [F.task("Umzugswagen buchen", "ich muss einen Umzugswagen buchen")]))
        #expect(result.tasks.isEmpty && result.rejections.contains("task:quote"))
    }

    @Test func fuzzyQuoteIsReplacedByTheRealSpan() {
        let transcript = "Ich muss morgen früh unbedingt noch beim Bürgeramt in Kreuzberg wegen der Anmeldung der neuen Wohnung anrufen."
        let quote = "Ich muss morgen früh unbedingt noch beim Bürgeramt in Kreuzberg wegen der Ummeldung der neuen Wohnung anrufen"
        let result = F.validate(F.answer(title: "Bürgeramt Kreuzberg", clean: transcript, topic: F.topic("none"),
                                         tasks: [F.task("Bürgeramt wegen Anmeldung anrufen", quote, due: "morgen früh")]),
                                F.input(transcript: transcript))
        #expect(result.tasks.first?.quote == "Ich muss morgen früh unbedingt noch beim Bürgeramt in Kreuzberg wegen der Anmeldung der neuen Wohnung anrufen")
    }

    /// E1 e29: Das Modell kürzt das Zitat mit „…“. Die Stücke stehen wörtlich und nah beieinander → echte Stelle.
    @Test func elidedQuoteBecomesTheRealSpan() {
        let transcript = "was ich aber wirklich noch machen muss sind die Screenshots für den App Store die müssen bis zur Einreichung am zehnten fertig sein und zwar nur fürs große iPhone"
        let quote = "die Screenshots für den App Store ... bis zur Einreichung am zehnten fertig sein"
        #expect(ThoughtValidator.locateQuote(quote, in: transcript)
            == "die Screenshots für den App Store die müssen bis zur Einreichung am zehnten fertig sein")
        let far = (1...40).map { "wort\($0)" }.joined(separator: " ")
        #expect(ThoughtValidator.locateQuote("die Screenshots … fertig sein", in: "die Screenshots \(far) fertig sein") == nil)
        #expect(ThoughtValidator.locateQuote("die Screenshots … Laptop kaufen", in: transcript) == nil)
    }

    /// E1: gpt-oss schreibt geschützte Bindestriche (U+2011); gespeichert wird der normale.
    @Test func nonBreakingHyphensBecomePlain() {
        #expect(ThoughtValidator.plainHyphens("{\"title\":\"RevenueCat\u{2011}Dashboard\",\"x\":\"a\\u2011b\"}")
            == "{\"title\":\"RevenueCat-Dashboard\",\"x\":\"a-b\"}")
    }

    @Test func atMostFiveTasks() {
        let transcript = (1...7).map { "Ich muss Punkt \($0) erledigen." }.joined(separator: " ")
        let tasks = (1...7).map { F.task("Punkt \($0) erledigen", "Ich muss Punkt \($0) erledigen") }
        let result = F.validate(F.answer(title: "Punkte erledigen", clean: transcript, topic: F.topic("none"), tasks: tasks),
                                F.input(transcript: transcript))
        #expect(result.tasks.count == 5 && result.rejections.contains("tasks:limit"))
    }

    @Test func newDigitInTaskTextDropsIt() {
        let result = F.validate(F.answer(tasks: [F.task("3 Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken")]))
        #expect(result.tasks.isEmpty && result.rejections.contains("task:digits"))
    }

    @Test func missingNegationDropsIt() {
        let transcript = "Ich darf morgen auf keinen Fall den Schlüssel abgeben, bevor der Makler da ist."
        let result = F.validate(F.answer(title: "Schlüssel Makler", clean: transcript, topic: F.topic("none"),
                                         tasks: [F.task("Schlüssel abgeben", "Ich darf morgen auf keinen Fall den Schlüssel abgeben")]),
                                F.input(transcript: transcript))
        #expect(result.tasks.isEmpty && result.rejections.contains("task:negation"))
    }

    @Test func reminderNegationMayBeDropped() {
        let result = F.validate(F.answer(tasks: [F.task("Schufa-Auskunft bestellen", "nicht vergessen, die Schufa-Auskunft zu bestellen")]))
        #expect(result.tasks.map(\.text) == ["Schufa-Auskunft bestellen"])
    }

    @Test func ungroundedWordsDropTheTask() {
        let result = F.validate(F.answer(tasks: [F.task("Dringend Anwalt kontaktieren", "Ich muss bis Freitag die Unterlagen schicken")]))
        #expect(result.tasks.isEmpty && result.rejections.contains("task:words"))
    }

    @Test func oneExtraWordIsTolerated() {
        let result = F.validate(F.answer(tasks: [F.task("Unterlagen an Makler schicken", "Ich muss bis Freitag die Unterlagen schicken")]))
        #expect(result.tasks.count == 1)
    }

    @Test func dueHintMustBeInTheQuote() {
        let result = F.validate(F.answer(tasks: [F.task("Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken", due: "morgen")]))
        #expect(result.tasks.first?.dueHint == nil && result.rejections.contains("task:due"))
    }

    @Test func duplicateTasksCollapse() {
        let result = F.validate(F.answer(tasks: [F.task("Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken"),
                                                 F.task("unterlagen schicken!", "die Unterlagen schicken")]))
        #expect(result.tasks.count == 1)
    }

    /// Dritte Prüfrunde (Astra): Gleicher Text an zwei Tagen sind zwei Aufgaben. Der Schlüssel für Doppelte enthält
    /// den Zeitausdruck – sonst wären „Morgen Mama anrufen“ und „Übermorgen Mama anrufen“ nach `TaskText` gleich.
    @Test func sameTextOnDifferentDaysStaysTwoTasks() {
        let transcript = "Ich muss morgen Mama anrufen. Und übermorgen nochmal Mama anrufen."
        let input = F.input(transcript: transcript)
        func run(_ tasks: [[String: Any]]) -> StructureResult {
            F.validate(F.answer(title: "Mama anrufen", clean: transcript, topic: F.topic("none"), tasks: tasks), input)
        }
        let withTime = run([F.task("Morgen Mama anrufen", "morgen Mama anrufen", due: "morgen"),
                            F.task("Übermorgen Mama anrufen", "übermorgen nochmal Mama anrufen", due: "übermorgen")])
        #expect(withTime.tasks.map(\.text) == ["Mama anrufen", "Mama anrufen"])
        #expect(withTime.tasks.map(\.dueHint) == ["morgen", "übermorgen"])
        #expect(!withTime.rejections.contains("task:duplicate"))
        // die KI hat den Zeitausdruck schon weggelassen
        let withoutTime = run([F.task("Mama anrufen", "morgen Mama anrufen", due: "morgen"),
                               F.task("Mama anrufen", "übermorgen nochmal Mama anrufen", due: "übermorgen")])
        #expect(withoutTime.tasks.map(\.dueHint) == ["morgen", "übermorgen"])
        // wirklich doppelt (gleicher Text, gleicher Tag): eine Aufgabe
        let twice = run([F.task("Morgen Mama anrufen", "morgen Mama anrufen", due: "morgen"),
                         F.task("Mama anrufen", "morgen Mama anrufen", due: "Morgen")])
        #expect(twice.tasks.count == 1 && twice.rejections.contains("task:duplicate"))
    }

    @Test func assembledPartsKeepTasksOnDifferentDays() {
        let first = StructureResult(title: "Mama", cleanText: "Teil eins.", topic: .none,
                                    tasks: [TaskDraft(text: "Mama anrufen", quote: "morgen Mama anrufen", dueHint: "morgen")], related: [])
        let part = StructureResult(title: "", cleanText: "Teil zwei.", topic: .none,
                                   tasks: [TaskDraft(text: "Mama anrufen", quote: "übermorgen Mama anrufen", dueHint: "übermorgen"),
                                           TaskDraft(text: "mama anrufen", quote: "morgen Mama anrufen", dueHint: "morgen")],
                                   related: [])
        let result = ThoughtValidator.assemble(first: first, firstTranscript: "a", parts: [(part, "b")])
        #expect(result.tasks.map(\.dueHint) == ["morgen", "übermorgen"])
        #expect(RawText.taskKey("Mama anrufen", dueHint: "morgen") != RawText.taskKey("Mama anrufen", dueHint: "übermorgen"))
        #expect(RawText.taskKey("Mama anrufen!", dueHint: "Morgen") == RawText.taskKey("mama anrufen", dueHint: "morgen"))
        // „Erneut ordnen“ gegen Erledigte/Eigene: ohne Zeitausdruck zählt nur der Text, zwei Tage bleiben zwei
        let done = ThoughtTask(text: "Mama anrufen", dueHint: "morgen", owner: .ai)
        #expect(RawText.sameTask(done, ThoughtTask(text: "mama anrufen", dueHint: "Morgen", owner: .ai)))
        #expect(RawText.sameTask(done, ThoughtTask(text: "Mama anrufen", owner: .ai)))
        #expect(RawText.sameTask(ThoughtTask(text: "Mama anrufen", owner: .user), ThoughtTask(text: "Mama anrufen", dueHint: "morgen", owner: .ai)))
        #expect(!RawText.sameTask(done, ThoughtTask(text: "Mama anrufen", dueHint: "übermorgen", owner: .ai)))
    }

    @Test func tooLongTaskTextDropsIt() {
        let text = "Unterlagen schicken " + String(repeating: "Unterlagen ", count: 7)
        #expect(F.validate(F.answer(tasks: [F.task(text, "Ich muss bis Freitag die Unterlagen schicken")])).tasks.isEmpty)
    }

    @Test func englishTaskWithInflection() {
        let transcript = "Quick note for the flat. I need to call Anna about Friday and remind me to order boxes next week."
        let result = F.validate(F.answer(title: "Flat Anna Friday", clean: transcript, topic: F.topic("none"),
                                         tasks: [F.task("Call Anna about Friday", "I need to call Anna about Friday"),
                                                 F.task("Order boxes", "remind me to order boxes next week", due: "next week")]),
                                F.input(transcript: transcript))
        #expect(result.tasks.map(\.text) == ["Call Anna about Friday", "Order boxes"])
        #expect(result.tasks.last?.dueHint == "next week")
    }
}

@Suite struct AIValidatorRelatedTests {
    @Test func highConfidenceLinkIsKept() {
        let result = F.validate(F.answer(related: [F.link("c1", "continues", "Gleiche Wohnung in der Oranienstraße")]))
        #expect(result.related == [RelatedDraft(thoughtID: "s_oranien", kind: .continues, reason: "Gleiche Wohnung in der Oranienstraße")])
    }

    @Test func refOutsideTheCandidatesIsDropped() {
        let result = F.validate(F.answer(related: [F.link("c9"), F.link("s_oranien")]))
        #expect(result.related.isEmpty && result.rejections.filter { $0 == "related:ref" }.count == 2)
    }

    @Test func mediumNeedsAHighLocalScore() {
        let result = F.validate(F.answer(related: [F.link("c1", "same_matter", "Wohnung", "medium"),
                                                   F.link("c2", "same_matter", "Garten", "medium")]))
        #expect(result.related.map(\.thoughtID) == ["s_oranien"])
    }

    @Test func lowConfidenceIsDropped() {
        #expect(F.validate(F.answer(related: [F.link("c1", "continues", "Wohnung", "low")])).related.isEmpty)
    }

    @Test func longReasonIsDropped() {
        #expect(F.validate(F.answer(related: [F.link("c1", "continues", String(repeating: "Wohnung ", count: 9))])).related.isEmpty)
    }

    @Test func reasonWithNewDigitIsDropped() {
        #expect(F.validate(F.answer(related: [F.link("c1", "changes", "Miete jetzt 2.000 Euro")])).related.isEmpty)
        #expect(F.validate(F.answer(related: [F.link("c1", "changes", "Miete 1.450 Euro")])).related.count == 1)
    }

    @Test func atMostThreeAndNoDuplicates() {
        let result = F.validate(F.answer(related: [F.link("c1"), F.link("c1"), F.link("c3", "same_matter", "Knopf"),
                                                   F.link("c2", "same_matter", "Garten")]))
        #expect(result.related.map(\.thoughtID) == ["s_oranien", "s_sperr"])
        #expect(result.rejections.contains("related:limit"))
    }

    @Test func noSelfReference() {
        let result = F.validate(F.answer(related: [F.link("c1")]), selfID: "s_oranien")
        #expect(result.related.isEmpty && result.rejections.contains("related:self"))
    }

    @Test func unknownKindIsDropped() {
        #expect(F.validate(F.answer(related: [F.link("c1", "merges")])).related.isEmpty)
    }
}

@Suite struct AIValidatorPartTests {
    @Test func partValidation() {
        let input = F.input(part: (index: 2, count: 3))
        let json = String(decoding: try! JSONSerialization.data(withJSONObject: [
            "clean_text": F.goodClean, "tasks": [F.task("Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken")],
        ]), as: UTF8.self)
        guard case .success(let part) = ThoughtValidator.validatePart(json: json, input: input) else {
            Issue.record("Teil erwartet"); return
        }
        #expect(part.title.isEmpty && part.topic == .none && part.related.isEmpty)
        #expect(part.cleanText == F.goodClean && part.tasks.count == 1)
        #expect(ThoughtValidator.validatePart(json: "{}", input: input) == .failure(.unreadable))
    }

    @Test func assembleJoinsTextsAndDeduplicatesTasks() {
        let task = TaskDraft(text: "Unterlagen schicken", quote: "Unterlagen schicken")
        let first = StructureResult(title: "Wohnung", cleanText: "Teil eins.", topic: .existing("t_umzug"), tasks: [task],
                                    related: [RelatedDraft(thoughtID: "s_oranien", kind: .continues, reason: "Wohnung")])
        let second = StructureResult(title: "", cleanText: nil, topic: .none,
                                     tasks: [task, TaskDraft(text: "Makler anrufen", quote: "Makler anrufen")],
                                     related: [], rejections: ["text:length"])
        let third = StructureResult(title: "", cleanText: "Teil drei.", topic: .none, tasks: [], related: [])
        let result = ThoughtValidator.assemble(first: first, firstTranscript: "teil eins",
                                               parts: [(second, "ähm teil zwei roh"), (third, "teil drei")])
        #expect(result.cleanText == "Teil eins.\n\nähm teil zwei roh\n\nTeil drei.")
        #expect(result.tasks.map(\.text) == ["Unterlagen schicken", "Makler anrufen"])
        #expect(result.rejections == ["part2:text:length"])
        #expect(result.title == "Wohnung" && result.topic == .existing("t_umzug") && result.related.count == 1)
    }

    @Test func assembleWithAllTextsRejectedIsRaw() {
        let first = StructureResult(title: "Wohnung", cleanText: nil, topic: .none, tasks: [], related: [])
        let part = StructureResult(title: "", cleanText: nil, topic: .none, tasks: [], related: [])
        #expect(ThoughtValidator.assemble(first: first, firstTranscript: "a", parts: [(part, "b")]).cleanText == nil)
    }
}

/// Prompt v4: Form des Aufgabentexts im Code (`TaskText`) – nur Weglassen am Rand und Großschreiben.
@Suite struct AITaskTextTests {
    @Test(arguments: [
        ("tomaten gießen", "Tomaten gießen"),
        ("übergabe vorbereiten", "Übergabe vorbereiten"),
        ("ärzte anrufen", "Ärzte anrufen"),
        ("3 Kartons bestellen", "3 Kartons bestellen"),
        ("20 kartons bestellen", "20 kartons bestellen"),
        ("iPhone reparieren lassen", "iPhone reparieren lassen"),
        ("eBay-Konto löschen", "eBay-Konto löschen"),
        ("schufa-Auskunft bestellen", "Schufa-Auskunft bestellen"),
        ("„paply“ testen", "„Paply“ testen"),
        ("call the bank", "Call the bank"),
        ("Anna anrufen", "Anna anrufen"),
    ])
    func firstLetterIsCapitalizedSafely(raw: String, expected: String) {
        #expect(TaskText.tidy(raw, dueHint: nil) == expected)
    }

    /// Gestrichen wird nur ganz am Anfang oder Ende – ohne Verneinung, mit freiem Nachbarwort, ≥ 2 Wörtern danach,
    /// Zeitpunkt oder Frist (kein Zeitraum) und am Ende ohne Präposition davor im Text.
    @Test(arguments: [
        ("morgen einkaufen gehen", "morgen", "Einkaufen gehen"),
        ("Morgen, einkaufen gehen", "morgen", "Einkaufen gehen"),
        ("Morgen Mama anrufen", "morgen", "Mama anrufen"),
        ("Übermorgen Mama anrufen", "übermorgen", "Mama anrufen"),
        ("am Freitag Anna anrufen", "am Freitag", "Anna anrufen"),
        ("Anna anrufen, morgen früh", "morgen früh", "Anna anrufen"),
        ("Morgen um 10 Uhr Kunden empfangen", "morgen um 10 Uhr", "Kunden empfangen"),
        ("call the bank tomorrow", "tomorrow", "Call the bank"),
        ("renew the fluxo dot app domain before November third", "before November third", "Renew the fluxo dot app domain"),
        // „bis spätestens …“ ist eine Frist
        ("bis spätestens Freitag Unterlagen schicken", "bis spätestens Freitag", "Unterlagen schicken"),
    ])
    func timeExpressionAtTheEdgeIsRemoved(raw: String, due: String, expected: String) {
        #expect(TaskText.tidy(raw, dueHint: due) == expected)
    }

    @Test(arguments: [
        // aus der Mitte nie (bis v5 gestrichen)
        ("Reisepass bis Ende November verlängern", "bis Ende November", "Reisepass bis Ende November verlängern"),
        ("Reisepass, bis Ende November, verlängern", "bis Ende November", "Reisepass, bis Ende November, verlängern"),
        ("Unterlagen bis Freitag schicken", "bis Freitag", "Unterlagen bis Freitag schicken"),
        ("Laufrad im Dezember kaufen", "im Dezember", "Laufrad im Dezember kaufen"),
        ("Anna morgen anrufen", "morgen", "Anna morgen anrufen"),
        // d) Zeitraum: Der Endtermin kann zum Objekt gehören – Frist oder Endtermin steht nicht sicher im Text
        ("Urlaub verlängern bis Freitag", "bis Freitag", "Urlaub verlängern bis Freitag"),
        ("bis Freitag Urlaub verlängern", "bis Freitag", "Bis Freitag Urlaub verlängern"),
        ("bis Freitag die Unterlagen schicken", "bis Freitag", "Bis Freitag die Unterlagen schicken"),
        ("ab Montag Sport machen", "ab Montag", "Ab Montag Sport machen"),
        ("extend the lease until May", "until May", "Extend the lease until May"),
        // b) Nachbarwort regiert oder gehört zur Zeitangabe
        ("Anna wegen Freitag anrufen", "Freitag", "Anna wegen Freitag anrufen"),
        ("Kuchen backen für morgen", "morgen", "Kuchen backen für morgen"),
        ("morgen nur Anna anrufen", "morgen", "Morgen nur Anna anrufen"),
        ("morgen erst Anna anrufen", "morgen", "Morgen erst Anna anrufen"),
        ("morgen oder übermorgen Anna anrufen", "morgen", "Morgen oder übermorgen Anna anrufen"),
        ("morgen Abend Anna anrufen", "morgen", "Morgen Abend Anna anrufen"),
        ("Anna anrufen nächsten Freitag", "Freitag", "Anna anrufen nächsten Freitag"),
        ("Anna anrufen am 3. Mai", "Mai", "Anna anrufen am 3. Mai"),
        // e) Am Ende hängt die Zeit womöglich an einer Präposition davor (Samstag = das Ausmessen, E1 e29)
        ("Frau Brandt fragen wegen Ausmessen am Samstag", "am Samstag", "Frau Brandt fragen wegen Ausmessen am Samstag"),
        ("ask Anna about the meeting on Friday", "on Friday", "Ask Anna about the meeting on Friday"),
        // nur wörtlich gleich
        ("Reisepass bis Ende November verlängern", "Ende November", "Reisepass bis Ende November verlängern"),
        ("am Freitag Anna anrufen", "Freitag", "Am Freitag Anna anrufen"),
        ("Unterlagen bis spätestens Freitag schicken", "bis Freitag", "Unterlagen bis spätestens Freitag schicken"),
        ("Halteverbotszone beantragen bis Freitag", "bis spätestens Freitag", "Halteverbotszone beantragen bis Freitag"),
        // nichts übrig → Text bleibt
        ("morgen", "morgen", "Morgen"),
    ])
    func timeExpressionStaysWhenInDoubt(raw: String, due: String, expected: String) {
        #expect(TaskText.tidy(raw, dueHint: due) == expected)
    }

    /// Dritte Prüfrunde, Befund 1 (Blocker): Neben einer Verneinung fällt nie etwas weg.
    @Test(arguments: [
        ("nicht morgen anrufen", "morgen", "Nicht morgen anrufen"),
        ("morgen nicht anrufen", "morgen", "Morgen nicht anrufen"),
        ("bis morgen nicht anrufen", "bis morgen", "Bis morgen nicht anrufen"),
        ("bis morgen nicht anrufen", "morgen", "Bis morgen nicht anrufen"),
        ("Kein Termin morgen", "morgen", "Kein Termin morgen"),
        ("Anna anrufen, aber nicht morgen", "morgen", "Anna anrufen, aber nicht morgen"),
        ("nicht heute, sondern morgen anrufen", "morgen", "Nicht heute, sondern morgen anrufen"),
        ("nicht heute, sondern morgen anrufen", "heute", "Nicht heute, sondern morgen anrufen"),
        ("Nicht morgen bezahlen", "morgen", "Nicht morgen bezahlen"),
        ("Nicht morgen Mama besuchen", "morgen", "Nicht morgen Mama besuchen"),
        ("Mama besuchen, nur nicht morgen", "morgen", "Mama besuchen, nur nicht morgen"),
        ("morgen keine Pakete annehmen", "morgen", "Morgen keine Pakete annehmen"),
        ("morgen ohne Auto zum Arzt fahren", "morgen", "Morgen ohne Auto zum Arzt fahren"),
        ("don't call the bank tomorrow", "tomorrow", "Don't call the bank tomorrow"),
        ("dont call the bank tomorrow", "tomorrow", "Dont call the bank tomorrow"),
        ("tomorrow never call the bank", "tomorrow", "Tomorrow never call the bank"),
        ("nicht vor Freitag bezahlen", "nicht vor Freitag", "Nicht vor Freitag bezahlen"),
        // Astra: Endtermin als Objekt
        ("Urlaub bis Freitag verlängern", "bis Freitag", "Urlaub bis Freitag verlängern"),
    ])
    func negationKeepsEverything(raw: String, due: String, expected: String) {
        #expect(TaskText.tidy(raw, dueHint: due) == expected)
    }

    /// Befund 2: Ein einzelnes Wort bleibt nie übrig. Befund 3: kein Torso mit Bindewort am Rand.
    @Test(arguments: [
        ("Freitag absagen", "Freitag", "Freitag absagen"),
        ("absagen Freitag", "Freitag", "Absagen Freitag"),
        ("Weihnachten planen", "Weihnachten", "Weihnachten planen"),
        ("morgen anrufen", "morgen", "Morgen anrufen"),
        ("morgen früh und abends gießen", "morgen früh", "Morgen früh und abends gießen"),
        ("morgen früh und abends gießen", "morgen", "Morgen früh und abends gießen"),
        ("statt morgen übermorgen kommen", "übermorgen", "Statt morgen übermorgen kommen"),
        ("statt morgen übermorgen kommen", "morgen", "Statt morgen übermorgen kommen"),
        ("morgen statt heute Anna anrufen", "morgen", "Morgen statt heute Anna anrufen"),
        ("morgen bzw. übermorgen Anna anrufen", "morgen", "Morgen bzw. übermorgen Anna anrufen"),
        ("Anna anrufen und morgen", "morgen", "Anna anrufen und morgen"),
        ("call Anna and tomorrow", "tomorrow", "Call Anna and tomorrow"),
    ])
    func noSingleWordAndNoTorso(raw: String, due: String, expected: String) {
        #expect(TaskText.tidy(raw, dueHint: due) == expected)
    }

    @Test(arguments: [
        ("noch Milch kaufen", "Milch kaufen"),
        ("Noch Milch kaufen", "Milch kaufen"),
        ("noch die Belege prüfen", "Die Belege prüfen"),
        ("mal Anna anrufen", "Anna anrufen"),
        ("eben Brot holen", "Brot holen"),
        ("Anna anrufen mal", "Anna anrufen"),
        ("Rechnungen sammeln noch", "Rechnungen sammeln"),
        // Sinn bleibt: Verneinung, „noch ein…“ (= weiteres), „noch mal“ (= wieder), „erst mal“, Nomen „Mal“
        ("noch nicht bezahlen", "Noch nicht bezahlen"),
        ("noch keinen Termin machen", "Noch keinen Termin machen"),
        ("noch einen Termin machen", "Noch einen Termin machen"),
        ("noch mal anrufen", "Noch mal anrufen"),
        ("Anna anrufen noch mal", "Anna anrufen noch mal"),
        ("Kaffee trinken erst mal", "Kaffee trinken erst mal"),
        ("Fenster putzen nächstes Mal", "Fenster putzen nächstes Mal"),
        ("einmal Pizza bestellen", "Einmal Pizza bestellen"),
        ("nicht mal anrufen", "Nicht mal anrufen"),
        ("noch", "Noch"),
        // mit Verneinung im Text bleibt jedes Füllwort („noch … nicht“ = noch nicht)
        ("noch Milch nicht kaufen", "Noch Milch nicht kaufen"),
        ("noch die Miete nicht überweisen", "Noch die Miete nicht überweisen"),
        ("Anna nicht anrufen noch", "Anna nicht anrufen noch"),
        ("mal Anna nicht stören", "Mal Anna nicht stören"),
    ])
    func onlySafeFillersAtTheEdgesAreRemoved(raw: String, expected: String) {
        #expect(TaskText.tidy(raw, dueHint: nil) == expected)
    }

    @Test func validatorAppliesTheFormAndStillChecksTheQuote() {
        let result = F.validate(F.answer(tasks: [
            F.task("noch die Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken", due: "bis Freitag"),
            F.task("schufa-Auskunft bestellen", "nicht vergessen, die Schufa-Auskunft zu bestellen"),
        ]))
        #expect(result.tasks.map(\.text) == ["Die Unterlagen schicken", "Schufa-Auskunft bestellen"])
        #expect(result.tasks.first?.dueHint == "bis Freitag")
        // „bis Freitag“ am Anfang: Frist oder Endtermin ist nicht sicher – bleibt (ab der dritten Prüfrunde)
        let span = F.validate(F.answer(tasks: [
            F.task("bis Freitag noch die Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken", due: "bis Freitag"),
        ]))
        #expect(span.tasks.map(\.text) == ["Bis Freitag noch die Unterlagen schicken"])
        // Doppelte nach der Form fallen weg
        let doubled = F.validate(F.answer(tasks: [F.task("Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken"),
                                                  F.task("noch Unterlagen schicken", "die Unterlagen schicken")]))
        #expect(doubled.tasks.count == 1 && doubled.rejections.contains("task:duplicate"))
        // Abgelehnter Zeitausdruck bleibt im Text (nichts geht verloren)
        let rejected = F.validate(F.answer(tasks: [F.task("morgen Unterlagen schicken", "Ich muss bis Freitag die Unterlagen schicken", due: "morgen")]))
        #expect(rejected.tasks.isEmpty || rejected.tasks.first?.text == "Morgen Unterlagen schicken")
    }

    /// Verneinung bleibt: „nicht verlängern“ ist eine echte Aufgabe; „kündigen“ ohne Verneinung fällt weg (Prüfer).
    @Test func negatedTaskKeepsItsNegation() {
        let transcript = "Ich muss beim Fitnessstudio noch Bescheid sagen, dass ich den Vertrag nicht verlängere."
        let quote = "Ich muss beim Fitnessstudio noch Bescheid sagen, dass ich den Vertrag nicht verlängere"
        let result = F.validate(F.answer(title: "Vertrag nicht verlängern", clean: transcript, topic: F.topic("none"),
                                         tasks: [F.task("noch Bescheid sagen: Vertrag nicht verlängern", quote),
                                                 F.task("Vertrag kündigen", quote)]),
                                F.input(transcript: transcript))
        #expect(result.tasks.map(\.text) == ["Bescheid sagen: Vertrag nicht verlängern"])
        #expect(result.rejections.contains("task:negation"))
    }
}

/// Prompt v4: Die Befunde vom iPhone (mit erfundenen Namen) bestehen die Prüfung „nur Wörter des Sprechers“.
@Suite struct AITaskWordingV4Tests {
    @Test func coreOfTheSpeakersWordsIsGrounded() {
        let transcript = "Ich muss bei meiner Firma Brenner noch die neuesten Briefe einmal bearbeiten."
        let result = F.validate(F.answer(title: "Briefe bei Brenner bearbeiten", clean: transcript, topic: F.topic("none"),
                                         tasks: [F.task("Neueste Briefe bei Brenner bearbeiten",
                                                        "Ich muss bei meiner Firma Brenner noch die neuesten Briefe einmal bearbeiten"),
                                                 F.task("Beim Brenner Briefe bearbeiten",
                                                        "Ich muss bei meiner Firma Brenner noch die neuesten Briefe einmal bearbeiten")]),
                                F.input(transcript: transcript))
        #expect(result.tasks.map(\.text) == ["Neueste Briefe bei Brenner bearbeiten", "Beim Brenner Briefe bearbeiten"])
    }

    @Test func errandWithSplitTimeExpression() {
        let transcript = "Ich muss morgen, am besten vormittags, wenn die Kinder in der Schule sind, einkaufen gehen und die drei Gutscheine vom Biomarkt am besten benutzen. Und dafür mir die Einkaufsliste von meinem Agenten nochmal exportieren lassen."
        let first = "Ich muss morgen, am besten vormittags, wenn die Kinder in der Schule sind, einkaufen gehen und die drei Gutscheine vom Biomarkt am besten benutzen"
        let result = F.validate(F.answer(title: "Einkaufen mit Gutscheinen", clean: transcript, topic: F.topic("none"),
                                         tasks: [F.task("Beim Biomarkt einkaufen, Gutscheine nutzen", first, due: "morgen vormittags"),
                                                 F.task("Einkaufsliste vom Agenten exportieren lassen",
                                                        "dafür mir die Einkaufsliste von meinem Agenten nochmal exportieren lassen")]),
                                F.input(transcript: transcript))
        #expect(result.tasks.map(\.text) == ["Beim Biomarkt einkaufen, Gutscheine nutzen", "Einkaufsliste vom Agenten exportieren lassen"])
        #expect(result.tasks.map(\.dueHint) == ["morgen vormittags", nil])
        #expect(!result.rejections.contains("task:due"))
    }

    @Test func appointmentWithTimeFromTwoClauses() {
        let transcript = "Morgen möchte ein Kunde bei Brenner 10 Bildschirme kaufen, um 10 Uhr will er kommen."
        let quote = "Morgen möchte ein Kunde bei Brenner 10 Bildschirme kaufen, um 10 Uhr will er kommen"
        let result = F.validate(F.answer(title: "Kunde kauft 10 Bildschirme", clean: transcript, topic: F.topic("none"),
                                         tasks: [F.task("Kunden wegen 10 Bildschirmen empfangen", quote, due: "morgen um 10 Uhr")]),
                                F.input(transcript: transcript))
        #expect(result.tasks == [TaskDraft(text: "Kunden wegen 10 Bildschirmen empfangen", quote: quote, dueHint: "morgen um 10 Uhr")])
    }

    @Test func dueHintFromPiecesStaysInTheQuote() {
        let quote = "Ich muss morgen, am besten vormittags, wenn die Kinder in der Schule sind, einkaufen gehen"
        #expect(ThoughtValidator.dueHintInQuote("morgen vormittags", quote: quote))
        #expect(ThoughtValidator.dueHintInQuote("morgen, am besten vormittags", quote: quote))
        #expect(ThoughtValidator.dueHintInQuote("Morgen", quote: quote))
        // ein Wort, das nicht gesprochen wurde
        #expect(!ThoughtValidator.dueHintInQuote("morgen nachmittags", quote: quote))
        #expect(!ThoughtValidator.dueHintInQuote("übermorgen", quote: quote))
        // falsche Reihenfolge
        #expect(!ThoughtValidator.dueHintInQuote("vormittags morgen", quote: quote))
        // nur an Wortgrenzen: „morgen“ steckt nicht in „übermorgen“
        #expect(!ThoughtValidator.dueHintInQuote("morgen", quote: "Ich muss übermorgen die Unterlagen schicken"))
        // zu weit auseinander (> 20 Wörter) oder zu viele Stücke (> 3)
        let far = "morgen " + (1...19).map { "wort\($0)" }.joined(separator: " ") + " vormittags"
        #expect(ThoughtValidator.dueHintInQuote("morgen vormittags", quote: "morgen " + (1...18).map { "wort\($0)" }.joined(separator: " ") + " vormittags"))
        #expect(!ThoughtValidator.dueHintInQuote("morgen vormittags", quote: far))
        #expect(!ThoughtValidator.dueHintInQuote("a c e g", quote: "a b c d e f g"))
        #expect(ThoughtValidator.dueHintInQuote("a c e", quote: "a b c d e f g"))
    }
}

/// Bewertungssatz `prompt4.json` (Prompt v4): Die erwarteten Aufgabentexte sind schon in der Form, die der Code
/// herstellt, und bestehen die Prüfung gegen das Gesprochene; jede erwartete Fälligkeit steht im Transkript.
@Suite struct AIPrompt4FixtureTests {
    struct Case: Decodable {
        struct Expect: Decodable { var tasks: [TaskExpect] }
        struct TaskExpect: Decodable {
            var required: Bool
            var texts: [String]
            var quote: [String]
            var due_hint: [String?]?
        }
        var id: String
        var transcript: String
        var expect: Expect
    }

    struct Fixture: Decodable {
        struct Regression: Decodable { var id: String }
        var cases: [Case]
        var regression: [Regression]
    }

    @Test func expectedTasksMatchTheCodeAndTheValidator() throws {
        let data = try Data(contentsOf: StoreSupport.fixtures.appendingPathComponent("prompt4.json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        #expect(fixture.cases.count == 6 && fixture.regression.count == 6)
        for item in fixture.cases {
            for task in item.expect.tasks where task.required {
                let dues = (task.due_hint ?? [nil]).compactMap { $0 }
                for due in dues {
                    #expect(ThoughtValidator.dueHintInQuote(due, quote: item.transcript), "\(item.id): due „\(due)“")
                }
                for core in task.quote {
                    #expect(ThoughtValidator.locateQuote(core, in: item.transcript) != nil, "\(item.id): Zitat „\(core)“")
                }
                for text in task.texts {
                    #expect(TaskText.tidy(text, dueHint: dues.first) == text, "\(item.id): Form „\(text)“")
                    #expect(ThoughtValidator.taskWordsGrounded(text, quote: item.transcript), "\(item.id): Wörter „\(text)“")
                    #expect(ThoughtValidator.digitsContained(text, in: item.transcript), "\(item.id): Ziffern „\(text)“")
                    #expect(ThoughtValidator.effectiveNegations(text) == ThoughtValidator.effectiveNegations(item.transcript),
                            "\(item.id): Verneinung „\(text)“")
                }
            }
            // Beispiele des Prompts kommen im Bewertungssatz nicht vor
            for word in ["Tilda", "Baumarkt"] { #expect(!item.transcript.contains(word)) }
        }
        let eval = try String(contentsOf: StoreSupport.fixtures.appendingPathComponent("eval.jsonl"), encoding: .utf8)
        for entry in fixture.regression { #expect(eval.contains("\"id\": \"\(entry.id)\""), "\(entry.id) fehlt in eval.jsonl") }
    }
}
