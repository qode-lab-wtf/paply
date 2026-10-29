import Foundation

/// Vorläufig; wird durch die Messung kalibriert.
public enum SpeakerThresholds {
    public static let match = 0.82
    public static let suggestion = 0.65
    public static let learning = 0.70
    public static let merge = 0.92
    public static let fragmentMerge = 0.80
    public static let fragmentSeconds = 2.0
    public static let minimumLearningSeconds = 8.0

    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard !a.isEmpty, a.count == b.count, a.allSatisfy(\.isFinite), b.allSatisfy(\.isFinite) else { return 0 }
        let dot = zip(a, b).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
        let norm = sqrt(a.reduce(0.0) { $0 + Double($1) * Double($1) } * b.reduce(0.0) { $0 + Double($1) * Double($1) })
        return norm > 0 ? max(-1, min(1, dot / norm)) : 0
    }

    public static func score(_ print: VoicePrint, against person: VoicePerson) -> Double {
        let best = person.prints.filter { $0.model == print.model && $0.vector.count == print.vector.count }
            .map { cosine(print.vector, $0.vector) }.sorted(by: >).prefix(3)
        return best.isEmpty ? 0 : best.reduce(0, +) / Double(best.count)
    }
}
