import Foundation
import Testing
@testable import PaplyKit

struct SharedTermTests {
    struct Case: Decodable {
        let name: String, term: String
        var text: String?, near: Bool?, first: String?, second: String?, lpFirst: Double?, lpSecond: Double?, accept: Bool?
    }
    static let cases: [Case] = {
        let url = SharedPolishTests.shared.deletingLastPathComponent().appendingPathComponent("begriffe/faelle.json")
        let data = try! JSONDecoder().decode([String: [Case]].self, from: Data(contentsOf: url))
        return data["klang"]! + data["annahme"]!
    }()
    @Test func survivesPolish() {
        #expect(PolishSafetyNet.rejection(raw: "hallo Law Min wie geht es dir", result: "Hallo Law Min, wie geht es dir?", vocabulary: "Law Min") == nil)
    }
    @Test(arguments: cases) func shared(_ c: Case) {
        if let near = c.near { #expect(TermGuard.near(c.term,c.text!) == near) }
        else { #expect(TermGuard.accept(c.term, first: c.first!, second: c.second!, lpFirst: c.lpFirst, lpSecond: c.lpSecond) == c.accept!) }
    }
    @Test func vocabularyPerformance() {
        let text = Array(repeating: "Planung", count: 1000).joined(separator: " ")
        let vocabulary = (0..<200).map { "Datenschutzregel\($0)" }.joined(separator: ",")
        let start = Date()
        let result = TermGuard.candidates(vocabulary, Transcription(text: text))
        let elapsed = Date().timeIntervalSince(start)
        print("TermGuard 200 terms / 1000 words: \(elapsed) s")
        #expect(result.terms.isEmpty)
        #expect(elapsed < 5)
    }
    @Test(arguments: ["accept","reject","empty","fail","echo","plain","uncertain","silence"]) func pipeline(_ mode: String) async {
        let input = mode == "echo" ? "Lamin danke." : mode == "silence" ? "Vielen Dank." : ["plain","uncertain"].contains(mode) ? "Das Wetter ist heute schön." : "Hallo Lavi Min, wie geht es dir?"
        let one = ["empty","plain","uncertain","silence"].contains(mode)
        let server = MockServer { _, index in
            if index == 0 { return Groq.transcription(input, logprob: mode == "uncertain" ? -0.8 : -0.3) }
            if mode == "fail" { return Groq.error(422) }
            return Groq.transcription(mode == "echo" ? "Law Min, Law Min." : "Hallo Law Min, wie geht es dir?", logprob: mode == "reject" ? -0.9 : -0.1)
        }
        var settings = PaplySettings()
        settings.spokenLanguages = ["de","en"]; settings.primaryLanguage = "de"; settings.chunkedUpload = false
        settings.vocabulary = mode == "empty" ? "" : "Law Min"
        var options = PipelineOptions(); options.polish = false
        let p = DictationPipeline(settings: settings, recentRawDictations: [], options: options, client: server.client(), catalog: ModelCatalog())
        let audio = Synth.withFloor(Synth.speech(3))
        for start in stride(from: 0, to: audio.count, by: 1600) { await p.append(Array(audio[start..<min(start+1600,audio.count)])) }
        let result = await p.finish()
        #expect(server.requests("/audio/transcriptions").count == (one ? 1 : 2))
        #expect(abs((result.timings.requestedAudioSeconds ?? -1) - (one ? 3 : 6)) < 0.01)
        if !one {
            #expect(server.requests("/audio/transcriptions")[1].field("language") == "de")
            #expect(server.requests("/audio/transcriptions")[1].field("prompt") == "Law Min, Law Min.")
        }
        #expect(result.raw == (mode == "accept" ? "Hallo Law Min, wie geht es dir?" : input))
    }
}
