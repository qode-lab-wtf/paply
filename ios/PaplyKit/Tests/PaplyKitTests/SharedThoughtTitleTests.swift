import Foundation
import Testing
@testable import PaplyKit

struct SharedThoughtTitleTests {
    struct Case: Decodable, CustomTestStringConvertible {
        var name: String
        var transcript: String
        var title: String
        var spoken: [String]
        var ui: String
        var ok: Bool
        var testDescription: String { name }
    }
    static let cases: [Case] = {
        let url = SharedPolishTests.shared.deletingLastPathComponent().appendingPathComponent("gedanken/titel-faelle.json")
        return try! JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }()
    @Test(arguments: cases) func sharedCases(_ c: Case) {
        var input = AIFixture.input(transcript: c.transcript, topics: [], candidates: [])
        input.spokenLanguages = c.spoken
        input.uiLanguage = c.ui
        let result = AIFixture.validate(AIFixture.answer(title: c.title, clean: c.transcript, topic: AIFixture.topic("none")), input)
        #expect(result.rejections.contains("title") == !c.ok)
        #expect((ThoughtValidator.checkedTitle(c.title, transcript: c.transcript, spoken: c.spoken, ui: c.ui) != nil) == c.ok)
    }
}
