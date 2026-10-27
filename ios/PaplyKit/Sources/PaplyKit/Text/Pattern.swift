import Foundation

/// Dünner Wrapper um NSRegularExpression (ICU, unterstützt \p{L} usw.).
/// NSRegularExpression ist unveränderlich und laut Apple thread-sicher.
struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        // Muster sind Konstanten im Code; ein Fehler ist ein Programmierfehler.
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func count(in text: String) -> Int {
        regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func replacing(in text: String, with template: String = "") -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Ersetzt nur den ersten Treffer.
    func replacingFirst(in text: String, with replacement: String = "") -> String {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return text }
        return text.replacingCharacters(in: range, with: replacement)
    }

    /// Inhalt der ersten Gruppe des ersten Treffers.
    func firstGroup(in text: String, group: Int = 1) -> String? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
