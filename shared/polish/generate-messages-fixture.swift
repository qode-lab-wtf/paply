import Foundation
struct Segment: Codable { var text: String; var start: Double?; var end: Double?; var avg_logprob: Double }
struct Payload: Codable { var background_do_not_edit: [String]; var current_dictation: String; var uncertain_segments: [Segment]; var custom_terms: String? }
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let payloads = [Payload(background_do_not_edit: ["eins", "zwei", "drei"], current_dictation: "Hallo / Welt\n\"Zitat\" 😀", uncertain_segments: [Segment(text: "Papli / App", start: 1, end: 2.5, avg_logprob: -0.7), Segment(text: "ohne Zeit", avg_logprob: -0.8)], custom_terms: "Paply, Müller, OS11"), Payload(background_do_not_edit: [], current_dictation: "Hallo", uncertain_segments: [], custom_terms: nil), Payload(background_do_not_edit: [], current_dictation: "Zahlen", uncertain_segments: [Segment(text: "klein", start: -0.0, end: 1e-7, avg_logprob: -1e-5 - 1), Segment(text: "groß", start: 1e16, end: 1e20, avg_logprob: -0.7)], custom_terms: nil)]
let strings = try payloads.map { String(data: try encoder.encode($0), encoding: .utf8)! }
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: strings, options: [.prettyPrinted, .withoutEscapingSlashes]))
