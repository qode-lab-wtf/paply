import Foundation
import PaplyKit

// Messhilfen. Nutzen `package`-Zugriff auf PaplyKit; für die App unsichtbar.

/// Eigene Verbindung samt Modell-Cache: Messläufe beeinflussen sich so nicht gegenseitig.
struct IsolatedConnection: Sendable {
    let transport = GroqTransport()
    let catalog = ModelCatalog()

    func client(apiKey: String) -> GroqClient { GroqClient(apiKey: apiKey, transport: transport) }

    func prewarm(apiKey: String) async {
        await GroqConnection.prewarm(client(apiKey: apiKey), catalog: catalog)
    }

    func invalidate() { transport.reset() }

    /// Rohe Transkription für Sonden (Antwort-JSON unverändert).
    func rawTranscription(apiKey: String, samples: [Int16], model: String, wav: Bool,
                          prompt: String? = nil, language: String? = nil) async -> (status: Int, headers: [String: String], body: Data)? {
        let client = client(apiKey: apiKey)
        let audio = AudioEncoder.encode(samples, preferFLAC: !wav)
        let boundary = "paply-\(UUID().uuidString)"
        var request = client.request("audio/transcriptions", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = GroqClient.multipart(
            boundary: boundary,
            fields: [("model", model), ("response_format", "verbose_json"), ("temperature", "0")]
                + (prompt.map { [("prompt", $0)] } ?? []) + (language.map { [("language", $0)] } ?? []),
            audio: audio)
        guard let (data, response) = try? await transport.withSession({ try await $0.data(for: request) }),
              let http = response as? HTTPURLResponse else { return nil }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            let name = String(describing: key).lowercased()
            if name.hasPrefix("x-ratelimit") || name == "retry-after" { headers[name] = String(describing: value) }
        }
        return (http.statusCode, headers, data)
    }
}

/// Polier-Bausteine für A/B-Vergleiche und die Offline-Prüfung des Sicherheitsnetzes.
enum BenchPolish {
    static var systemPrompt: String { PolishPrompt.systemPrompt }

    static func userMessage(_ text: String) -> String {
        PolishPrompt.buildMessages(text: text, history: [], vocabulary: "")[1].content
    }

    static func finalText(_ content: String?) -> String { PolishSafetyNet.finalPolishText(content) }

    static func rejection(raw: String, result: String, strict: Bool = true) -> String? {
        PolishSafetyNet.rejection(raw: raw, result: result, strictEdits: strict)
    }
}

/// Schnittpunkte der Stücke-Logik für eine Aufnahme (Sekunden), offline berechnet.
enum BenchChunks {
    static func cuts(_ samples: [Float], block: Int = 1_600, minSeconds: Double = 10) -> [Double] {
        var vad = VoiceActivityDetector()
        var planner = ChunkPlanner()
        planner.minChunkSeconds = minSeconds
        var result: [Double] = []
        var offset = 0
        while offset < samples.count {
            vad.process(Array(samples[offset..<min(offset + block, samples.count)]))
            while let range = planner.nextCut(vad) {
                result.append(Double(range.upperBound) * VoiceActivityDetector.frameMs / 1000)
            }
            offset += block
        }
        return result
    }
}
