import Foundation
import Testing

@testable import PaplyKit

@Suite("Sprachabschnitte für den Gesprächs-Rückfall")
struct SpeechRegionsTests {
    @Test func silenceHasNoSpeaker() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try WAVWriter(url: url)
        writer.append(Array(repeating: 0, count: 32_000))
        _ = writer.close()
        #expect(try SpeechRegions.read(url).isEmpty)
    }
    @Test func voicedRegionsExcludeLongPause() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try WAVWriter(url: url)
        let voice = (0..<16_000).map { Float(sin(Double($0) * 2 * .pi * 180 / 16_000)) * 0.2 }
        writer.append(voice)
        writer.append(Array(repeating: 0, count: 32_000))
        writer.append(voice)
        _ = writer.close()
        let regions = try SpeechRegions.read(url)
        #expect(!regions.isEmpty)
        #expect(regions.contains { $0.lowerBound < 1 })
        #expect(regions.contains { $0.upperBound > 3 })
        #expect(!regions.contains { $0.contains(2) })
    }
}
