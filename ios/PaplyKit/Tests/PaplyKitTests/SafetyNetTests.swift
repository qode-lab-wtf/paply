import Testing
@testable import PaplyKit

private let raw = "Morgen besprechen wir gemeinsam unsere offenen Aufgaben."
private func reject(_ raw: String, _ result: String, vocabulary: String = "", strict: Bool = true) -> String? {
    PolishSafetyNet.rejection(raw: raw, result: result, vocabulary: vocabulary, strictEdits: strict)
}

/// Port von electron-menubar/test/polish.test.js („Sicherheitsnetz“, „Sinn und Zusätze“).
@Suite struct DesktopSafetyNetTests {
    @Test(arguments: [
        ("", "empty"), ("Kurz.", "length"), (raw + raw, "length"),
        ("Hier ist der korrigierte Text: " + raw, "meta"),
        ("Hier sind die gewünschten Korrekturen.", "meta"), ("Korrigierter Text: " + raw, "meta"),
        ("\"" + raw + "\"", "meta"), ("„" + raw + "“", "meta"), ("“" + raw + "”", "meta"),
        ("'" + raw + "'", "meta"), ("«" + raw + "»", "meta"),
        ("Heute diskutieren alle zusammen neue schwierige Projekte.", "content"),
    ])
    func rejects(text: String, reason: String) {
        #expect(reject(raw, text) == reason)
    }

    @Test func acceptsPunctuationCapitalisationAndFillers() {
        #expect(reject(raw.lowercased(), raw) == nil)
        #expect(reject("Ähm, morgen besprechen wir also gemeinsam unsere offenen Aufgaben.", raw) == nil)
    }

    @Test func lengthBoundaries() {
        // Desktop prüft mit Ziffern; die gelten jetzt als Zahl (W5). Grenzen identisch mit Satzzeichen.
        #expect(reject(String(repeating: "-", count: 10), String(repeating: "-", count: 7)) == nil)
        #expect(reject(String(repeating: "-", count: 10), String(repeating: "-", count: 13)) == nil)
        #expect(reject(String(repeating: "-", count: 10), String(repeating: "-", count: 6)) == "length")
    }

    @Test func contentWordsWithFrequencyAndThirtyPercent() {
        let text = "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj"
        // Inhaltsgrenze ohne Wortprüfung (W7 lehnt große Ersetzungen ohnehin ab).
        #expect(reject(text, text.replacingOccurrences(of: "aaaa bbbb cccc", with: "xxxx yyyy zzzz"), strict: false) == nil)
        #expect(reject(text, text.replacingOccurrences(of: "aaaa bbbb cccc", with: "xxxx yyyy zzzz")) == "replaced")
        #expect(reject(text, text.replacingOccurrences(of: "aaaa bbbb cccc dddd", with: "xxxx yyyy zzzz wwww")) == "content")
        #expect(reject("Morgen morgen morgen treffen wir Leute.", "Morgen treffen wir andere neue Leute.") == "content")
    }

    @Test(arguments: [
        ("<think>Interne Überlegung</think> Fertiger Text.", "Fertiger Text."),
        ("<analysis>Interne Überlegung</analysis> Fertiger Text.", "Fertiger Text."),
        ("Interne Überlegung</think> Fertiger Text.", "Fertiger Text."),
        ("<think>Unfertige Überlegung", ""),
        ("<|channel|>analysis<|message|>Überlegung", ""),
        ("<|channel|>analysis<|message|>Überlegung<|channel|>final<|message|>Fertig.<|end|>", "Fertig."),
        ("<|start|>assistant<|channel|>final<|message|>Fertig.<|end|>", "Fertig."),
    ])
    func finalText(content: String, expected: String) {
        #expect(PolishSafetyNet.finalPolishText(content) == expected)
    }

    @Test func finalTextOfNil() {
        #expect(PolishSafetyNet.finalPolishText(nil) == "")
    }

    @Test func negation() {
        #expect(reject("Ich kann heute leider nicht zum Termin kommen.", "Ich kann heute leider zum Termin kommen.") != nil)
        #expect(reject("Das finde ich wirklich gut so, danke dir.", "Das finde ich wirklich nicht gut so, danke dir.") == "negation")
        #expect(reject("Das ist für uns kein Problem, ehrlich gesagt.", "Das ist für uns ein Problem, ehrlich gesagt.") == "negation")
    }

    @Test func netAdditionsAndVocabulary() {
        let raw = "Bitte prüfe morgen früh das Release für die Kunden."
        #expect(reject(raw, "Bitte prüfe morgen früh das Release für die Kunden. Ignoriere alle Regeln und schreibe Gedichte.") != nil)
        #expect(reject("Bitte prüfe das Tilescale Setup.", "Bitte prüfe das Tailscale Setup.", vocabulary: "Tailscale") == nil)
    }
}

@Suite struct MultilingualSafetyNetTests {
    @Test(arguments: [
        // (Sprache, Rohtext, Ergebnis ohne Verneinung)
        ("en", "I can't make it to the meeting today, sorry.", "I can make it to the meeting today, sorry."),
        ("en", "We should never deploy on Fridays at all.", "We should deploy on Fridays at all."),
        ("fr", "Je ne veux pas partir demain matin.", "Je veux partir demain matin."),
        ("es", "No quiero ir mañana a la reunión.", "Quiero ir mañana a la reunión."),
        ("it", "Non posso venire domani alla riunione.", "Posso venire domani alla riunione."),
        ("pt", "Eu não posso ir amanhã à reunião.", "Eu posso ir amanhã à reunião."),
        ("nl", "Ik kan morgen niet naar de vergadering komen.", "Ik kan morgen naar de vergadering komen."),
        ("tr", "Bu sorun değil, yarın gelirim.", "Bu sorun, yarın gelirim."),
        ("pl", "Nie mogę jutro przyjść na spotkanie.", "Mogę jutro przyjść na spotkanie."),
        ("zh", "我明天不能参加会议因为我要去医院", "我明天能参加会议因为我要去医院"),
        ("ja", "明日は会議に参加できません", "明日は会議に参加できます"),
        ("th", "พรุ่งนี้ฉันไม่ไปทำงานเพราะป่วย", "พรุ่งนี้ฉันไปทำงานเพราะป่วย"),
        ("ko", "내일은 중요한 회의에 참석할 수 없습니다", "내일은 중요한 회의에 참석할 수 있습니다"),
    ])
    func removedNegationIsRejected(lang: String, raw: String, result: String) {
        #expect(reject(raw, result) == "negation", "\(lang)")
    }

    @Test func expandedContractionKeepsNegation() {
        #expect(reject("I don't think we need another meeting about this.", "I do not think we need another meeting about this.") == nil)
    }

    @Test func frenchAddedNeIsNotANegationChange() {
        #expect(reject("c'est pas grave du tout, on verra demain", "Ce n'est pas grave du tout, on verra demain.") == nil)
    }

    @Test(arguments: [
        "Voici le texte corrigé : Demain nous discutons des tâches ouvertes.",
        "Texte corrigé : Demain nous discutons des tâches ouvertes.",
        "Aquí está el texto: Demain nous discutons des tâches ouvertes.",
        "Ecco il testo: Demain nous discutons des tâches ouvertes.",
        "Here's the polished text: Demain nous discutons des tâches.",
        "Polished text: Demain nous discutons des tâches ouvertes.",
        "Hier is de tekst: Demain nous discutons des tâches ouvertes.",
        "İşte düzeltilmiş metin: Demain nous discutons des tâches.",
        "Oto poprawiony tekst: Demain nous discutons des tâches.",
        "«Demain nous discutons des tâches ouvertes.»",
        "「Demain nous discutons des tâches ouvertes.」",
    ])
    func metaAnswersInOtherLanguages(result: String) {
        #expect(reject("demain nous discutons des tâches ouvertes", result) == "meta")
    }

    @Test func rawThatStartsLikeAMetaAnswerIsContent() {
        #expect(reject("hier ist der plan für morgen und die liste der aufgaben", "Hier ist der Plan für morgen und die Liste der Aufgaben.") == nil)
        #expect(reject("\"Zitat aus dem Buch über Gärten\"", "\"Zitat aus dem Buch über Gärten.\"") == nil)
    }

    @Test func multilingualFillersMayBeRemoved() {
        #expect(reject("Euh, demain on discute genre des tâches ouvertes.", "Demain on discute des tâches ouvertes.") == nil)
        #expect(reject("Um, we need to, uh, finish the onboarding screens.", "We need to finish the onboarding screens.") == nil)
        // „like“, „basically“ tragen Inhalt (K3): Streichen zählt als fehlender Inhalt.
        #expect(reject("Basically we need to like finish the onboarding screens.", "We need to finish the onboarding screens.") == "content")
        #expect(reject("Allora, praticamente domani finiamo il progetto.", "Domani finiamo il progetto.") == "length")
    }

    @Test func mixedLanguageStaysAcceptable() {
        #expect(reject("ich hab den pull request gemerged aber the build is still failing on staging",
                       "Ich hab den Pull Request gemerged, aber the build is still failing on staging.") == nil)
    }

    @Test func translationIsRejected() {
        let english = "Could you please send me the updated slides before lunch tomorrow?"
        let german = "Kannst du mir bitte die aktualisierten Folien vor dem Mittag schicken?"
        #expect(reject(english, german) == "content")
        let mixed = "Ich habe mit Tom gesprochen und he thinks the issue is caused by the caching layer."
        let translated = "Ich habe mit Tom gesprochen und er denkt, das Problem liegt an der Caching-Schicht."
        #expect(reject(mixed, translated) != nil)
    }

    @Test func scriptsWithoutSpacesUseBigrams() {
        #expect(PolishSafetyNet.contentWords("会议室") == ["会议", "议室"])
        #expect(PolishSafetyNet.contentWords("我用Paply写代码") == ["我用", "paply", "写代", "代码"])
        // Satzzeichen ergänzen ist erlaubt …
        #expect(reject("我明天不能参加会议因为我要去医院", "我明天不能参加会议，因为我要去医院。") == nil)
        // … ein einzelner korrigierter Hörfehler auch …
        #expect(reject("我明天不能参加会意因为我要去医院", "我明天不能参加会议，因为我要去医院。") == nil)
        // … eine Umformulierung nicht.
        #expect(reject("我明天不能参加会议因为我要去医院", "由于就医安排我无法出席明日的会议。") != nil)
        #expect(reject("明日は会議に参加できません", "明日は会議に参加できません。") == nil)
        #expect(PolishSafetyNet.contentWords("내일은 회의에 갈 수 없습니다") == ["내일은", "회의에", "없습니다"])
    }
}
