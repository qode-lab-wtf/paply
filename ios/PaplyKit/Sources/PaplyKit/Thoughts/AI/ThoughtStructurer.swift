// GERÜST (G0.1, Koordinator). Besitzer: H1. Signatur aus KONZEPT.md §9.2 bitte nicht ändern.
import Foundation

/// Ein Aufruf je Gedanke an gpt-oss (KONZEPT §6.1/§6.8).
public struct ThoughtStructurer: ThoughtStructuring {
    public init() {}

    public func structure(_ input: StructureInput, apiKey: String) async -> StructureOutcome {
        .unusable(code: "not-implemented")
    }
}
