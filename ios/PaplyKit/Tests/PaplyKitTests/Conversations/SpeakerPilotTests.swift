import Foundation
import Testing
@testable import PaplyKit

struct SpeakerPilotTests {
    private func print(_ vector: [Float]) -> VoicePrint {
        .init(vector: vector, model: "cam", seconds: 10, source: .enrollment)
    }
    @Test func competingClustersRemainSuggestions() {
        let speakers = [ConversationSpeaker(id: "S1", speechSeconds: 10, colorIndex: 1),
                        ConversationSpeaker(id: "S2", speechSeconds: 10, colorIndex: 2)]
        let result = SpeakerIdentifier.identify(speakers, prints: ["S1": print([1, 0]), "S2": print([0.99, 0.1])],
            people: [.init(id: "owner", name: "", prints: [print([1, 0])])])
        #expect(result.allSatisfy { $0.personID == nil })
        #expect(result.contains { $0.suggestion != nil })
    }
    @Test func competingProfilesRemainSuggestions() {
        let result = SpeakerIdentifier.identify([.init(id: "S1", speechSeconds: 10, colorIndex: 1)],
            prints: ["S1": print([1, 0])], people: [
                .init(id: "owner", name: "", prints: [print([1, 0])]),
                .init(id: "other", name: "Andere", prints: [print([0.99, 0.1])])])
        #expect(result.first?.personID == nil)
    }
    @Test func clearMatchIsAccepted() {
        let result = SpeakerIdentifier.identify([.init(id: "S1", speechSeconds: 10, colorIndex: 1)],
            prints: ["S1": print([1, 0])], people: [.init(id: "owner", name: "", prints: [print([1, 0])])])
        #expect(result.first?.isOwner == true)
    }
    @Test func medoidRejectsForeignClip() {
        let center = SpeakerThresholds.enrollmentCentroid([print([1, 0]), print([1, 0.1]), print([0, 1])])!
        #expect(SpeakerThresholds.cosine(center, [1, 0]) > 0.99)
    }
    @Test func turnsContinueAcrossReadBoundaries() throws {
        var accumulator = NemotronTurnAccumulator()
        var first = Array(repeating: Float(0), count: 3 * 8)
        for frame in 0..<3 { first[frame * 8] = 0.9 }
        try accumulator.append(first, frames: 3)
        try accumulator.append(first, frames: 3)
        let segments = accumulator.finish()
        #expect(segments == [.init(start: 0, end: 0.06, cluster: 0)])
    }
    @Test func shortTurnsAreRemovedAndOverlapPreserved() throws {
        var accumulator = NemotronTurnAccumulator()
        var values = Array(repeating: Float(0), count: 8 * 8)
        for frame in 0..<8 { values[frame * 8] = 0.9; if frame < 5 { values[frame * 8 + 1] = 0.9 }; if frame < 4 { values[frame * 8 + 2] = 0.9 } }
        try accumulator.append(values, frames: 8)
        #expect(accumulator.finish().map(\.cluster) == [0, 1])
    }
}
