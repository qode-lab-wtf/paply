import Foundation
import Testing
@testable import PaplyKit

/// Gemeinsame Polier-Quelle (`shared/polish/`): Prompt byte-gleich, Prüffälle wie Desktop und Android.
struct SharedPolishTests {
    static let shared = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/polish")

    struct SafetyCase: Decodable, CustomTestStringConvertible {
        var raw: String
        var result: String
        var vocabulary: String
        var expected: String?
        var profile: String?
        var strictEdits: Bool?
        var testDescription: String { "\(raw) → \(result)" }
    }

    static let cases: [SafetyCase] = {
        let data = try! Data(contentsOf: shared.appendingPathComponent("safety-cases.json"))
        return try! JSONDecoder().decode([SafetyCase].self, from: data)
    }()

    @Test func promptMatchesSharedSource() throws {
        let source = try String(contentsOf: Self.shared.appendingPathComponent("system-prompt.txt"), encoding: .utf8)
        #expect(PolishPrompt.systemPrompt == source)
    }

    @Test(arguments: cases)
    func safetyNetMatchesSharedCases(_ c: SafetyCase) {
        let rejection: String? = switch c.profile {
        case "thought": PolishSafetyNet.rejection(raw: c.raw, result: c.result, vocabulary: c.vocabulary, profile: .thought)
        case "dictation": PolishSafetyNet.rejection(raw: c.raw, result: c.result, vocabulary: c.vocabulary, profile: .dictation)
        default: PolishSafetyNet.rejection(raw: c.raw, result: c.result, vocabulary: c.vocabulary, strictEdits: c.strictEdits ?? true)
        }
        #expect(rejection == c.expected)
    }
}
