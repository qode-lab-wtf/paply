import Foundation

/// Pilotwerte aus MESSUNG.md; unabhängige Geräte-/Negativtests stehen aus.
public enum SpeakerThresholds {
    public static let match = 0.80
    public static let margin = 0.10
    public static let enrollmentOutlier = 0.60
    // 0,65 bleibt ein bestätigungspflichtiger Vorschlag, niemals eine Identität.
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
        let compatible = person.prints.filter { $0.model == print.model && $0.vector.count == print.vector.count }
        if compatible.count >= 3, let center = enrollmentCentroid(compatible) {
            return cosine(print.vector, center)
        }
        let best = compatible
            .map { cosine(print.vector, $0.vector) }.sorted(by: >).prefix(3)
        return best.isEmpty ? 0 : best.reduce(0, +) / Double(best.count)
    }
}

extension SpeakerThresholds {
    public static func enrollmentInliers(_ prints: [VoicePrint]) -> [VoicePrint] {
        guard !prints.isEmpty else { return [] }
        let medoid = prints.indices.max { a, b in
            prints.reduce(0) { $0 + cosine(prints[a].vector, $1.vector) } <
            prints.reduce(0) { $0 + cosine(prints[b].vector, $1.vector) }
        }!
        return prints.filter { cosine($0.vector, prints[medoid].vector) >= enrollmentOutlier }
    }
    /// Einzelne fremde Clips beeinflussen den Profilmittelwert nicht.
    public static func enrollmentCentroid(_ prints: [VoicePrint]) -> [Float]? {
        guard let first = prints.first, !first.vector.isEmpty,
              prints.allSatisfy({ $0.model == first.model && $0.vector.count == first.vector.count && $0.vector.allSatisfy(\.isFinite) })
        else { return nil }
        let accepted = enrollmentInliers(prints)
        var mean = Array(repeating: Float(0), count: first.vector.count)
        for print in accepted {
            let norm = sqrt(print.vector.reduce(0) { $0 + $1 * $1 })
            guard norm > 0 else { continue }
            for i in mean.indices { mean[i] += print.vector[i] / norm }
        }
        let norm = sqrt(mean.reduce(0) { $0 + $1 * $1 })
        return norm > 0 ? mean.map { $0 / norm } : nil
    }
}
