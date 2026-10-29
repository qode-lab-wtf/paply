import Testing
@testable import PaplyKit

struct CAMFbankTests {
    @Test func matchesKaldiReferenceIncludingReflectedEdges() throws {
        let samples = (0..<128000).map { Float(($0 * 17) % 1001 - 500) / 500 }
        let features = try CAMVoiceEmbedding.features(samples: samples)
        // kaldi-native-fbank; 16 kHz, Povey, 80 Bänder, 20–7600 Hz, snip_edges=false.
        let reference: [(Int, Float)] = [
            (0, 3.99151111),
            (1, 5.44414520),
            (7, 1.61645365),
            (22, 1.32279396),
            (79, -0.19901371),
            (80, -1.01799107),
            (127, 0.13999248),
            (511, 1.45951605),
            (1000, 0.82057714),
            (20000, 1.55468035),
            (63900, -0.02039766),
            (63999, -0.12729883)
        ]
        for (index, expected) in reference { #expect(abs(features[index] - expected) < 0.003) }
    }
}
