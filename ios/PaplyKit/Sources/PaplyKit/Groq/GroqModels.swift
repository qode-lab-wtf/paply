import Foundation

/// Modellnamen und -optionen (wie electron-menubar/dictation/groq-models.js).
enum GroqModels {
    static let polish = "qwen/qwen3.8-27b"
    static let polishFallback = "openai/gpt-oss-120b"

    /// Erstes bevorzugtes Modell, das in der Liste verfügbar ist.
    static func select(available: [String], preferred: [String]) -> String? {
        let ids = Set(available)
        return preferred.first { ids.contains($0) }
    }

    struct ReasoningOptions: Equatable {
        var format: String?
        var effort: String?
    }

    static func reasoningOptions(_ model: String) -> ReasoningOptions {
        if model.hasPrefix("openai/gpt-oss-") { return ReasoningOptions(format: "hidden", effort: "low") }
        // Qwen: kein Nachdenk-Modus fürs Polieren (schneller, kein abgeschnittener <think>-Block).
        if model.hasPrefix("qwen/") { return ReasoningOptions(format: nil, effort: "none") }
        return ReasoningOptions()
    }

    /// Großzügiges Ausgabebudget; abgeschnittene Antworten werden vollständig verworfen.
    static func polishTokenBudget(_ text: String) -> Int {
        min(32768, max(4096, Int((Double(text.utf16.count) / 3).rounded(.up)) * 2))
    }

    /// Whisper liefert in `verbose_json` den Sprachnamen („German“); vereinheitlicht auf ISO 639-1.
    static func languageCode(_ value: String?) -> String? {
        guard let raw = value?.trimmed.lowercased(), !raw.isEmpty else { return nil }
        if raw.count <= 3, raw.allSatisfy(\.isLetter) { return raw }
        return whisperLanguages[raw] ?? raw
    }

    static let whisperLanguages: [String: String] = [
        "english": "en", "german": "de", "french": "fr", "spanish": "es", "italian": "it",
        "portuguese": "pt", "dutch": "nl", "turkish": "tr", "polish": "pl", "russian": "ru",
        "ukrainian": "uk", "chinese": "zh", "japanese": "ja", "korean": "ko", "arabic": "ar",
        "hindi": "hi", "swedish": "sv", "danish": "da", "norwegian": "no", "nynorsk": "nn",
        "finnish": "fi", "czech": "cs", "greek": "el", "hungarian": "hu", "romanian": "ro",
        "hebrew": "he", "vietnamese": "vi", "thai": "th", "indonesian": "id", "malay": "ms",
        "persian": "fa", "catalan": "ca", "croatian": "hr", "serbian": "sr", "slovak": "sk",
        "slovenian": "sl", "bulgarian": "bg", "lithuanian": "lt", "latvian": "lv",
        "estonian": "et", "tagalog": "tl", "urdu": "ur", "bengali": "bn", "tamil": "ta",
        "afrikaans": "af", "welsh": "cy", "icelandic": "is", "bosnian": "bs", "macedonian": "mk",
        "galician": "gl", "basque": "eu", "swahili": "sw", "albanian": "sq", "cantonese": "yue",
    ]
}
