import Foundation
import NaturalLanguage

/// Rückfall, falls Groq keine Sprache meldet: Erkennung auf dem Gerät (NaturalLanguage).
func detectLanguage(_ text: String) -> String? {
    guard TextAnalysis.letterRuns(text).count >= 2 else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    return recognizer.dominantLanguage.map { $0.rawValue.components(separatedBy: "-").first ?? $0.rawValue }
}
