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
