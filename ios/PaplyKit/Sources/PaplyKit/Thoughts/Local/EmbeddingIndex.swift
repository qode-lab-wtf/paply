import Foundation
import NaturalLanguage

/// Welches NaturalLanguage-Modell einen Vektor erzeugt hat. Nur gleiche Modelle (und beim Satz-Embedding
/// gleiche Sprachen) sind vergleichbar.
public enum EmbeddingModel: String, Codable, Sendable, CaseIterable {
    /// `NLContextualEmbedding(script: .latin)`: ein mehrsprachiges Modell für lateinische Schrift (de/en/fr/…),
    /// Mittel der Token-Vektoren. Braucht geladene Assets (iOS lädt sie bei Bedarf nach).
    case contextual
    /// `NLEmbedding.sentenceEmbedding(for:)` je Sprache, Mittel der Satzvektoren.
    case sentence
}

/// Ein normierter Vektor samt Herkunft.
public struct EmbeddingVector: Sendable, Equatable {
    public var model: EmbeddingModel
    /// Vergleichsraum: beim Satz-Embedding die Sprache, beim kontextuellen Modell die Schrift („latn“).
    public var space: String
    public var values: [Float]

    public init(model: EmbeddingModel, space: String, values: [Float]) {
        self.model = model
        self.space = space
        self.values = values
    }

    public func isComparable(to other: EmbeddingVector) -> Bool {
        model == other.model && space == other.space && values.count == other.values.count
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return Double(dot / (na.squareRoot() * nb.squareRoot()))
    }

    static func normalized(_ values: [Float]) -> [Float] {
        let norm = values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0, norm.isFinite else { return values }
        return values.map { $0 / norm }
    }
}

/// NaturalLanguage-Embedding (KONZEPT §6.3). Robust, wenn ein Modell fehlt: dann das nächste in
/// `preference`, sonst nil (die Kandidatensuche nutzt dann nur Schlagwörter).
///
/// Nicht threadsicher (NLEmbedding/NLContextualEmbedding): nur aus einem Akteur heraus benutzen.
public final class EmbeddingIndex: @unchecked Sendable {
    public let preference: [EmbeddingModel]
    private var sentenceModels: [String: NLEmbedding?] = [:]
    private var contextual: NLContextualEmbedding?
    private var contextualState: ContextualState = .unknown
    private enum ContextualState { case unknown, ready, unavailable }

    /// Satz-Embeddings gibt es für diese Sprachen (KONZEPT §6.3).
    public static let sentenceLanguages: Set<String> = ["de", "en", "fr", "es", "it", "pt", "zh"]

    public init(preference: [EmbeddingModel] = [.contextual]) {
        self.preference = preference
    }

    /// Bestes verfügbares Modell für diese Sprache (ohne zu rechnen).
    public func availableModel(language: String?) -> EmbeddingModel? {
        for model in preference {
            switch model {
            case .contextual where contextualModel(language: language) != nil: return model
            case .sentence where sentenceModel(language) != nil: return model
            default: continue
            }
        }
        return nil
    }

    /// Normierter Vektor des Textes mit dem ersten verfügbaren Modell aus `models` (Standard: `preference`).
    public func vector(for text: String, language: String?, models: [EmbeddingModel]? = nil) -> EmbeddingVector? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return nil }
        for model in models ?? preference {
            switch model {
            case .contextual:
                if let values = contextualVector(trimmed, language: language) {
                    return EmbeddingVector(model: .contextual, space: "latn", values: values)
                }
            case .sentence:
                if let language = baseLanguage(language), let values = sentenceVector(trimmed, language: language) {
                    return EmbeddingVector(model: .sentence, space: language, values: values)
                }
            }
        }
        return nil
    }

    // MARK: Satz-Embedding

    private func baseLanguage(_ language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        return language.components(separatedBy: "-").first?.lowercased()
    }

    private func sentenceModel(_ language: String?) -> NLEmbedding? {
        guard let code = baseLanguage(language), Self.sentenceLanguages.contains(code) else { return nil }
        if let cached = sentenceModels[code] { return cached }
        let model = NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: code))
        sentenceModels[code] = model
        return model
    }

    private func sentenceVector(_ text: String, language: String) -> [Float]? {
        guard let model = sentenceModel(language) else { return nil }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        for sentence in Self.sentences(text) {
            guard let vector = model.vector(for: sentence), vector.count == sum.count else { continue }
            for i in 0..<sum.count { sum[i] += vector[i] }
            count += 1
        }
        guard count > 0 else { return nil }
        return EmbeddingVector.normalized(sum.map { Float($0 / Double(count)) })
    }

    // MARK: Kontextuelles Embedding

    private func contextualModel(language: String?) -> NLContextualEmbedding? {
        switch contextualState {
        case .unavailable: return nil
        case .ready:
            break
        case .unknown:
            guard let model = NLContextualEmbedding(script: .latin), model.hasAvailableAssets,
                  (try? model.load()) != nil else {
                contextualState = .unavailable
                Self.requestContextualAssets()
                return nil
            }
            contextual = model
            contextualState = .ready
        }
        guard let model = contextual else { return nil }
        if let code = baseLanguage(language), !model.languages.contains(NLLanguage(rawValue: code)) { return nil }
        return model
    }

    /// iOS lädt das Modell bei Bedarf im Hintergrund; bis dahin gilt das nächste Modell.
    private static func requestContextualAssets() {
        guard let model = NLContextualEmbedding(script: .latin), !model.hasAvailableAssets else { return }
        model.requestAssets { _, _ in }
    }

    private func contextualVector(_ text: String, language: String?) -> [Float]? {
        guard let model = contextualModel(language: language) else { return nil }
        let nlLanguage = baseLanguage(language).map { NLLanguage(rawValue: $0) }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        // Abschnitte aus ganzen Sätzen, damit die Sequenzgrenze des Modells nicht abschneidet
        for piece in Self.pieces(text, maxCharacters: 900) {
            guard let result = try? model.embeddingResult(for: piece, language: nlLanguage) else { continue }
            result.enumerateTokenVectors(in: piece.startIndex..<piece.endIndex) { vector, _ in
                if vector.count == sum.count {
                    for i in 0..<sum.count { sum[i] += vector[i] }
                    count += 1
                }
                return true
            }
        }
        guard count > 0 else { return nil }
        return EmbeddingVector.normalized(sum.map { Float($0 / Double(count)) })
    }

    // MARK: Text zerlegen

    static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmed
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result.isEmpty ? [text] : result
    }

    static func pieces(_ text: String, maxCharacters: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for sentence in sentences(text) {
            if !current.isEmpty, current.count + sentence.count + 1 > maxCharacters {
                result.append(current)
                current = ""
            }
            current += current.isEmpty ? sentence : " " + sentence
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
