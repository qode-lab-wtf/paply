// GERÜST (G0.1, Koordinator). Besitzer: H2. Signatur aus KONZEPT.md §9.2 bitte nicht ändern.
import Foundation

/// WAV 16 kHz mono Int16, eigene serielle Queue (KONZEPT §5.3).
public final class WAVWriter: Sendable {
    public init() {}
    /// blockiert nie
    public func append(_ samples: [Float]) {}
    /// durationMs
    public func close() -> Int { 0 }
}
