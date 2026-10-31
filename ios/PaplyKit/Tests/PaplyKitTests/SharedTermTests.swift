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
    @Test(arguments: cases) func shared(_ c: Case) {
        if let near = c.near { #expect(TermGuard.near(c.term,c.text!) == near) }
        else { #expect(TermGuard.accept(c.term, first: c.first!, second: c.second!, lpFirst: c.lpFirst, lpSecond: c.lpSecond) == c.accept!) }
    }
    @Test(arguments: ["accept","reject","empty","fail"]) func pipeline(_ mode: String) async {
        let server = MockServer { _, index in
            if index == 0 { return Groq.transcription("Hallo Lavi Min, wie geht es dir?", logprob: -0.3) }
            if mode == "fail" { return Groq.error(422) }
            return Groq.transcription("Hallo Law Min, wie geht es dir?", logprob: mode == "reject" ? -0.9 : -0.1)
        }
        var settings = PaplySettings()
        settings.spokenLanguages = ["de","en"]; settings.primaryLanguage = "de"; settings.chunkedUpload = false
        settings.vocabulary = mode == "empty" ? "" : "Law Min"
        var options = PipelineOptions(); options.polish = false
        let p = DictationPipeline(settings: settings, recentRawDictations: [], options: options, client: server.client(), catalog: ModelCatalog())
        let audio = Synth.withFloor(Synth.speech(3))
        for start in stride(from: 0, to: audio.count, by: 1600) { await p.append(Array(audio[start..<min(start+1600,audio.count)])) }
        let result = await p.finish()
        #expect(server.requests("/audio/transcriptions").count == (mode == "empty" ? 1 : 2))
        #expect(result.raw == (mode == "accept" ? "Hallo Law Min, wie geht es dir?" : "Hallo Lavi Min, wie geht es dir?"))
    }
}
