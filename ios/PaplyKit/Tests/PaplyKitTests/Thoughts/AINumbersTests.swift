import Foundation
import Testing
@testable import PaplyKit

/// Gesprochene Zahlen im Gedanken-Profil (README der Fixtures §7, Spannungen 1–3). Diktat bleibt unverändert.
@Suite struct AINumbersTests {
    @Test(arguments: [
        ("achtundzwanzigsten", 28), ("dreißigste", 30), ("zweitausendsechsundzwanzig", 2026),
        ("vierzehnhundertfünfzig", 1450), ("elfhundertzwanzig", 1120), ("siebenhundertfünfzig", 750),
        ("sechstausendfünfhundert", 6500), ("viertausenddreihundertfünfzig", 4350), ("zehnten", 10), ("elften", 11),
        ("dritte", 3), ("siebte", 7), ("sechste", 6), ("zweimal", 2), ("fünfundzwanzigsten", 25), ("neunundneunzig", 99),
        ("einhundert", 100), ("eintausend", 1000), ("zwanzig", 20),
    ])
    func germanCompounds(word: String, value: Int) {
        #expect(SpokenNumbers.germanValue(word) == value)
    }

    @Test(arguments: ["minuten", "weihnachten", "mitte", "kiste", "leute", "hunderte", "manchmal", "einmal", "starten"])
    func germanNonNumbers(word: String) {
        #expect(SpokenNumbers.germanValue(word) == nil)
    }

    @Test func englishSequences() {
        #expect(SpokenNumbers.tokens("twenty eight").map(\.value) == [28])
        #expect(SpokenNumbers.tokens("seven hundred and fifty euros").map(\.value) == [750])
        #expect(SpokenNumbers.tokens("in two thousand twenty six").map(\.value) == [2026])
        #expect(SpokenNumbers.tokens("one two three").map(\.value) == [1, 2, 3])
        #expect(SpokenNumbers.tokens("before November third").map(\.value) == [11, 3])
        #expect(SpokenNumbers.tokens("twenty-first").map(\.value) == [21])
    }

    @Test func digitGroups() {
        #expect(SpokenNumbers.tokens("6.500 € und 6 500 Leute").map(\.value) == [6500, 6500])
        #expect(SpokenNumbers.tokens("um 15:30").map(\.value) == [15, 30])
        #expect(SpokenNumbers.tokens("am 28.12.2026").map(\.value) == [28, 12, 2026])
        #expect(SpokenNumbers.tokens("1,5 Liter").map(\.value) == [1, 5])
    }

    @Test func optionalKinds() {
        let kinds = SpokenNumbers.tokens("ein Termin erstens im Dezember erster Gedanke").map(\.kind)
        #expect(kinds == [.optional, .optional, .optional, .optional])
    }

    @Test func numberWordsBecomeDigits() {
        #expect(SpokenNumbers.preserved(raw: "am achtundzwanzigsten Dezember um neun", result: "Am 28. Dezember um 9 Uhr."))
        #expect(SpokenNumbers.preserved(raw: "das kostet siebenhundertfünfzig Euro", result: "Das kostet 750 €."))
        #expect(SpokenNumbers.preserved(raw: "we need twenty eight seats", result: "We need 28 seats."))
    }

    @Test func changedMissingOrNewNumbersFail() {
        #expect(!SpokenNumbers.preserved(raw: "am achtundzwanzigsten Dezember", result: "Am 27. Dezember."))
        #expect(!SpokenNumbers.preserved(raw: "um neun mit zwanzig Leuten", result: "Um 9 Uhr mit Leuten."))
        #expect(!SpokenNumbers.preserved(raw: "mit Leuten", result: "Mit 20 Leuten."))
        #expect(!SpokenNumbers.preserved(raw: "im Dezember", result: "Im Dezember 2026."))
    }

    @Test func optionalSourcesAreNotRequired() {
        #expect(SpokenNumbers.preserved(raw: "erstens Kartons zweitens Transporter", result: "• Kartons\n• Transporter"))
        #expect(SpokenNumbers.preserved(raw: "erstens Kartons", result: "1. Kartons"))
        #expect(SpokenNumbers.preserved(raw: "am achtundzwanzigsten Dezember", result: "Am 28.12."))
    }

    @Test func selfCorrectionWithoutComma() {
        let raw = "7 Kilometer in 38 Minuten nee warte 36 die Uhr sagt 36"
        #expect(SpokenNumbers.preserved(raw: raw, result: "7 Kilometer in 36 Minuten, die Uhr sagt 36."))
        #expect(SpokenNumbers.preserved(raw: raw, result: "7 Kilometer in 38, nein 36 Minuten; die Uhr sagt 36."))
        // ohne Marker darf keine Zahl fehlen
        #expect(!SpokenNumbers.preserved(raw: "in 38 Minuten und dann 36 Liegestütze", result: "In Minuten und dann 36 Liegestütze."))
        // Korrektur mit Zahlwörtern (e31)
        let rent = "das sind dreitausendachthundert nee falsch drei mal vierzehnhundertfünfzig das sind viertausenddreihundertfünfzig"
        #expect(SpokenNumbers.preserved(raw: rent, result: "Das sind 3 × 1.450 €, also 4.350 €."))
        // „nein“ ohne neue Zahl danach ist keine Zahlenkorrektur (e31: 1.120 bleibt als Kaltmiete)
        let warm = "die alten elfhundertzwanzig warm äh nein das ist kalt warm sind's dreizehnhundertvierzig"
        #expect(!SpokenNumbers.preserved(raw: warm, result: "Warm sind es 1.340 €."))
        #expect(SpokenNumbers.preserved(raw: warm, result: "Die alten 1.120 € sind kalt, warm sind es 1.340 €."))
    }

    @Test func validatorAcceptsDigitsFromNumberWords() {
        let transcript = "Herr Kowalski will am achtundzwanzigsten übergeben ich muss zwanzig Kartons bestellen"
        #expect(ThoughtValidator.checkedTitle("Übergabe am 28.", transcript: transcript) == "Übergabe am 28")
        #expect(ThoughtValidator.checkedTitle("Übergabe am 29.", transcript: transcript) == nil)
        var rejections: [String] = []
        let tasks = ThoughtValidator.checkedTasks(
            [.init(text: "20 Kartons bestellen", quote: "ich muss zwanzig Kartons bestellen", due_hint: nil),
             .init(text: "30 Kartons bestellen", quote: "ich muss zwanzig Kartons bestellen", due_hint: nil)],
            transcript: transcript, rejections: &rejections)
        #expect(tasks.map(\.text) == ["20 Kartons bestellen"])
        #expect(rejections == ["task:digits"])
    }

    @Test func spokenNegationIgnoresInterjections() {
        #expect(PolishSafetyNet.spokenNegationCount("bis Donnerstag nee Quatsch bis Mittwoch") == 0)
        #expect(PolishSafetyNet.spokenNegationCount("äh nein das ist kalt") == 0)
        #expect(PolishSafetyNet.spokenNegationCount("das geht nicht") == 1)
        #expect(PolishSafetyNet.spokenNegationCount("we have no staging environment") == 1)
    }

    @Test func thoughtProfileAcceptsCorrectedDeadline() {
        let raw = "ähm ich muss bis Donnerstag nee Quatsch bis Mittwoch den Keller freiräumen weil die von Rhein Zug am Donnerstag um neun zur Besichtigung kommen"
        let clean = "Ich muss bis Mittwoch den Keller freiräumen, weil die von Rheinzug am Donnerstag um 9 Uhr zur Besichtigung kommen."
        #expect(PolishSafetyNet.rejection(raw: raw, result: clean, vocabulary: "Rheinzug", profile: .thought) == nil)
        // Diktat bleibt unverändert streng: zusammengesetzte Zahlwörter kennt es nicht.
        #expect(PolishSafetyNet.rejection(raw: "wir treffen uns am achtundzwanzigsten Dezember im Büro",
                                          result: "Wir treffen uns am 28. Dezember im Büro.", profile: .dictation) == "digits")
        #expect(PolishSafetyNet.rejection(raw: "wir treffen uns am achtundzwanzigsten Dezember im Büro",
                                          result: "Wir treffen uns am 28. Dezember im Büro.", profile: .thought) == nil)
    }
}
