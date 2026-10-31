import Foundation
import Testing
@testable import PaplyKit

struct SharedLanguageTests {
    struct Case: Decodable, CustomTestStringConvertible {
        var name: String
        var spoken: Double
        var expected: String?
        var detected: String?
        var users: [String]
        var check: Bool
        var lpDetected: Double?
        var lpExpected: Double?
        var sameText: Bool?
        var result: String
        var testDescription: String { name }
    }
    static let cases: [Case] = {
        let url = SharedPolishTests.shared.deletingLastPathComponent().appendingPathComponent("sprache/faelle.json")
        return try! JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }()
    @Test(arguments: cases) func sharedCases(_ c: Case) {
        let check = LanguageGuard.needsCheck(expected: c.expected, detected: c.detected, userLanguages: c.users, spokenSeconds: c.spoken)
        #expect(check == c.check)
        let choice = check ? LanguageGuard.choose(detectedText: "original", expectedText: c.sameText == true ? "original" : "other", detectedConfidence: c.lpDetected, expectedConfidence: c.lpExpected, spokenSeconds: c.spoken) : .detected
        #expect((choice == .detected ? "detected" : "expected") == c.result)
    }
}
