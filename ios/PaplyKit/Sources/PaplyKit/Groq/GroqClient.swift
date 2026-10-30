import Foundation
import Synchronization

/// Technischer Fehler einer Groq-Anfrage. Enthält nie Diktattext oder Schlüssel.
package enum GroqFailure: Error, Sendable, Equatable {
    case http(status: Int, code: String?, retryAfter: Double?)
    case network(code: Int)
    case invalidResponse
    case cancelled

    /// Echte, vorübergehende Fehler: genau einmal neu versuchen. 400/401/403/404/413/422
    /// sind deterministisch – ein zweiter Versuch ändert nichts.
    var isRetryable: Bool {
        switch self {
        case .http(let status, _, _): return status == 408 || status == 409 || status == 429 || status >= 500
        case .network: return true
        case .invalidResponse: return true
        case .cancelled: return false
        }
    }

    var isModelMissing: Bool {
        guard case .http(let status, let code, _) = self else { return false }
        return status == 404 || (status == 400 && (code == "model_decommissioned" || code == "model_not_found"))
    }

    /// Kurzcode für Protokolle/Messungen.
    var code: String {
        switch self {
        case .http(let status, _, _): return "http-\(status)"
        case .network(let code): return "network-\(code)"
        case .invalidResponse: return "invalid-response"
        case .cancelled: return "cancelled"
        }
    }

    /// Stabiler Polier-Fehlercode für die App.
    var polishCode: PolishFailureCode {
        switch self {
        case .http(429, _, _): return .rateLimited
        case .http(let status, _, _) where status == 401 || status == 403: return .unauthorized
        case .http(let status, _, _) where status >= 500: return .serverError
        case .http: return .requestRejected
        case .network: return .network
        case .invalidResponse: return .invalidResponse
        case .cancelled: return .cancelled
        }
    }

    /// Verständliche deutsche Meldung (Wortlaut wie Desktop `explainDictationStatus`).
    var germanMessage: String {
        switch self {
        case .http(let status, _, _) where status == 401 || status == 403:
            return "Ungültiger Groq-Schlüssel – bitte in den Einstellungen prüfen."
        case .http(429, _, _):
            return "Groq-Limit erreicht – bitte später erneut versuchen."
        case .http(413, _, _):
            return "Die Aufnahme ist zu lang für eine Übertragung."
        case .http(let status, _, _) where status >= 500:
            return "Groq ist gerade gestört (Fehler \(status)) – bitte erneut versuchen."
        case .http(let status, _, _):
            return "Transkription fehlgeschlagen (Fehler \(status))."
        case .network:
            return "Keine Verbindung – Netzwerk prüfen und erneut versuchen."
        case .invalidResponse:
            return "Groq hat eine unlesbare Antwort geschickt – bitte erneut versuchen."
        case .cancelled:
            return "Abgebrochen."
        }
    }
}

/// Geteilte URLSession: Vorwärmen nützt nur, wenn alle Anfragen dieselbe Verbindung nutzen.
///
/// Jede Anfrage holt sich die Session hier ab (nicht beim Erzeugen eines Clients).
/// `reset()` tauscht die Session; die alte wird erst ungültig gemacht, wenn keine
/// Anfrage mehr auf ihr läuft – sonst stürzt `URLSession` mit NSGenericException ab.
package final class GroqTransport: Sendable {
    package static let shared = GroqTransport()

    private struct Factory: @unchecked Sendable {
        let protocolClasses: [AnyClass]?
        func make() -> URLSession { GroqTransport.makeSession(protocolClasses: protocolClasses) }
    }

    private struct State {
        var current: URLSession
        var active: [ObjectIdentifier: Int] = [:]
        var retired: [ObjectIdentifier: URLSession] = [:]
    }

    private let factory: Factory
    private let state: Mutex<State>

    package init(protocolClasses: [AnyClass]? = nil) {
        let factory = Factory(protocolClasses: protocolClasses)
        self.factory = factory
        state = Mutex(State(current: factory.make()))
    }

    /// Aktuelle Session für genau eine Anfrage.
    package func withSession<T>(_ body: (URLSession) async throws -> T) async throws -> T {
        let session = state.withLock { s -> URLSession in
            s.active[ObjectIdentifier(s.current), default: 0] += 1
            return s.current
        }
        defer { release(session) }
        return try await body(session)
    }

    private func release(_ session: URLSession) {
        state.withLock { s in
            let id = ObjectIdentifier(session)
            let remaining = (s.active[id] ?? 1) - 1
            s.active[id] = remaining > 0 ? remaining : nil
            if remaining <= 0, let retired = s.retired.removeValue(forKey: id) {
                retired.finishTasksAndInvalidate()
            }
        }
    }

    /// Verbindungen verwerfen (z. B. nach Netzwechsel oder für Messungen ohne Vorwärmen).
    package func reset() {
        state.withLock { s in
            let old = s.current
            s.current = factory.make()
            let id = ObjectIdentifier(old)
            if (s.active[id] ?? 0) > 0 { s.retired[id] = old } else { old.finishTasksAndInvalidate() }
        }
    }

    package static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let config = URLSessionConfiguration.default
        // Kein Gesamtlimit fürs Polieren („Tempo geht nicht vor Perfektion“): Nur ein
        // Leerlauf-Timeout erkennt tote Verbindungen; das Ressourcen-Timeout ist praktisch
        // unbegrenzt. Einzelne Anfragen setzen ihr eigenes Leerlauf-Timeout.
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 30 * 60
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        if let protocolClasses { config.protocolClasses = protocolClasses }
        return URLSession(configuration: config)
    }
}

package struct Transcription: Sendable, Equatable {
    var text: String?
    var language: String?
    var duration: Double?
    /// nil, wenn Segmente fehlen oder unbrauchbar sind.
    var segments: [WhisperSegment]?
}

struct ChatCompletion: Sendable, Equatable {
    var content: String?
    var finishReason: String?
}

/// Schlanker Groq-Client (OpenAI-kompatible API) mit genau einem Wiederholversuch.
package struct GroqClient: Sendable {
    package static let defaultBaseURL = URL(string: "https://api.groq.com/openai/v1/")!

    /// Leerlauf-Timeouts je Anfrage (Sekunden ohne ein einziges übertragenes Byte).
    static let transcriptionIdleTimeout: TimeInterval = 30
    static let polishIdleTimeout: TimeInterval = 60
    static let keyCheckTimeout: TimeInterval = 15

    package let apiKey: String
    package let transport: GroqTransport
    package let baseURL: URL
    /// Längste Wartezeit, die ein Retry-After respektiert wird; darüber kein zweiter Versuch.
    var maxRetryAfterSeconds = 20.0
    /// Wartezeit vor dem Wiederholen ohne Retry-After.
    var retryDelaySeconds = 0.4
    /// Optionaler Taktgeber für Gespräche; bestehende Aufrufer bleiben unverändert.
    var responseHeaders: (@Sendable (HTTPURLResponse) -> Void)?

    package init(apiKey: String, transport: GroqTransport = .shared, baseURL: URL = GroqClient.defaultBaseURL) {
        self.apiKey = apiKey
        self.transport = transport
        self.baseURL = baseURL
    }

    // MARK: Transport

    func send(_ request: URLRequest) async -> Result<Data, GroqFailure> {
        if Task.isCancelled { return .failure(.cancelled) }
        do {
            let (data, response) = try await transport.withSession { try await $0.data(for: request) }
            guard let http = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.http(status: http.statusCode, code: Self.errorCode(data),
                                      retryAfter: Self.retryAfter(http) ?? Self.retryAfter(message: Self.errorMessage(data))))
            }
            return .success(data)
        } catch {
            return .failure(Self.failure(for: error))
        }
    }

    static func failure(for error: Error) -> GroqFailure {
        if Task.isCancelled || error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .network(code: urlError.code.rawValue)
        }
        return .network(code: -1)
    }

    /// Einmal senden, bei echtem Fehler genau einmal wiederholen.
    func sendWithRetry(_ request: URLRequest, onAttempt: (() -> Void)? = nil) async -> Result<Data, GroqFailure> {
        onAttempt?()
        let first = await send(request)
        guard case .failure(let failure) = first, failure.isRetryable,
              let delay = retryDelay(for: failure) else { return first }
        do { try await Task.sleep(for: .seconds(delay)) } catch { return .failure(.cancelled) }
        onAttempt?()
        return await send(request)
    }

    func retryDelay(for failure: GroqFailure) -> Double? {
        if case .http(429, _, let retryAfter) = failure {
            let wait = retryAfter ?? 1
            return wait <= maxRetryAfterSeconds ? wait : nil
        }
        if case .http(_, _, let retryAfter?) = failure {
            return retryAfter <= maxRetryAfterSeconds ? retryAfter : nil
        }
        return retryDelaySeconds
    }

    static func retryAfter(_ response: HTTPURLResponse) -> Double? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmed else { return nil }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    /// Wartezeit aus Groqs Fehlertext („Please try again in 7m11.135s“), in Sekunden.
    static func retryAfter(message: String?) -> Double? {
        guard let message, let range = message.range(of: "try again in ") else { return nil }
        let rest = message[range.upperBound...]
        var seconds = 0.0, number = "", found = false
        for character in rest {
            if character.isNumber || character == "." {
                number.append(character)
            } else if let value = Double(number), "hms".contains(character) {
                seconds += value * (character == "h" ? 3600 : character == "m" ? 60 : 1)
                number = ""
                found = true
                if character == "s" { break }
            } else {
                break
            }
        }
        return found ? seconds : nil
    }

    static func errorMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    static func errorCode(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return error["code"] as? String
    }

    package func request(_ path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: Endpunkte

    /// Aktive Modell-IDs.
    func listModels() async -> Result<[String], GroqFailure> {
        let result = await send(request("models"))
        return result.flatMap { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = object["data"] as? [[String: Any]] else { return .failure(.invalidResponse) }
            return .success(list.filter { ($0["active"] as? Bool) != false }.compactMap { $0["id"] as? String })
        }
    }

    /// Transkription (`verbose_json`, Temperatur 0). Zählt die gesendeten Audio-Bytes.
    /// Leerlauf-Timeout der Transkription: mindestens 30 s, bei langem Audio 15 s + 5 s je
    /// Minute (Groq rechnet erst nach dem vollständigen Upload und schweigt so lange).
    static func transcriptionTimeout(audioSeconds: Double?) -> TimeInterval {
        max(transcriptionIdleTimeout, 15 + 5 * (audioSeconds ?? 0) / 60)
    }

    package func transcribe(audio: AudioEncoder.Encoded, model: String, language: String?, prompt: String?,
                            audioSeconds: Double? = nil,
                            bytesSent: (@Sendable (Int) -> Void)? = nil) async -> Result<Transcription, GroqFailure> {
        var fields: [(String, String)] = [("model", model), ("response_format", "verbose_json"), ("temperature", "0")]
        if let language, !language.trimmed.isEmpty { fields.append(("language", language.trimmed)) }
        if let prompt, !prompt.isEmpty { fields.append(("prompt", prompt)) }
        let boundary = "paply-\(UUID().uuidString)"
        var request = request("audio/transcriptions", method: "POST")
        request.timeoutInterval = Self.transcriptionTimeout(audioSeconds: audioSeconds)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipart(boundary: boundary, fields: fields, audio: audio)
        let size = audio.data.count
        let result = await sendWithRetry(request, onAttempt: { bytesSent?(size) })
        return result.flatMap { data in
            guard let parsed = Self.parseTranscription(data) else { return .failure(.invalidResponse) }
            return .success(parsed)
        }
    }

    package static func multipart(boundary: String, fields: [(String, String)], audio: AudioEncoder.Encoded) -> Data {
        var body = Data()
        func line(_ text: String) { body.append(Data((text + "\r\n").utf8)) }
        for (name, value) in fields {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(name)\"")
            line("Content-Type: text/plain; charset=utf-8")
            line("")
            line(value)
        }
        line("--\(boundary)")
        line("Content-Disposition: form-data; name=\"file\"; filename=\"\(audio.fileName)\"")
        line("Content-Type: \(audio.mimeType)")
        line("")
        body.append(audio.data)
        line("")
        line("--\(boundary)--")
        return body
    }

    static func parseTranscription(_ data: Data) -> Transcription? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var segments: [WhisperSegment]?
        if let list = object["segments"] as? [Any], !list.isEmpty {
            let decoded = list.map { item -> WhisperSegment? in
                guard let dict = item as? [String: Any],
                      let json = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                return try? JSONDecoder().decode(WhisperSegment.self, from: json)
            }
            if decoded.allSatisfy({ $0 != nil }) { segments = decoded.compactMap { $0 } }
        }
        return Transcription(text: object["text"] as? String, language: object["language"] as? String,
                             duration: object["duration"] as? Double, segments: segments)
    }

    struct ChatBody: Encodable {
        var model: String
        var max_tokens: Int
        var messages: [ChatMessage]
        var temperature: Double?
        var reasoning_effort: String?
        var reasoning_format: String?
        var stream: Bool?
    }

    /// Chat-Anfrage als Stream (Server-Sent Events). Das Leerlauf-Timeout greift so nur
    /// bei einer toten Verbindung, nie als Gesamtlimit – auch lange Antworten laufen
    /// durch. Antwortet der Server ohne Stream (reines JSON), wird das ebenso gelesen.
    func chat(model: String, messages: [ChatMessage], maxTokens: Int, temperature: Double? = 0) async -> Result<ChatCompletion, GroqFailure> {
        if Task.isCancelled { return .failure(.cancelled) }
        let options = GroqModels.reasoningOptions(model)
        let body = ChatBody(model: model, max_tokens: maxTokens, messages: messages, temperature: temperature,
                            reasoning_effort: options.effort, reasoning_format: options.format, stream: true)
        var request = request("chat/completions", method: "POST")
        request.timeoutInterval = Self.polishIdleTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(body)
        do {
            return try await transport.withSession { session -> Result<ChatCompletion, GroqFailure> in
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
                var collected = Data()
                guard (200..<300).contains(http.statusCode) else {
                    for try await byte in bytes { collected.append(byte) }
                    return .failure(.http(status: http.statusCode, code: Self.errorCode(collected),
                                          retryAfter: Self.retryAfter(http) ?? Self.retryAfter(message: Self.errorMessage(collected))))
                }
                var stream = ChatStreamParser()
                var line = Data()
                // Selbst nur an \n trennen: `bytes.lines` trennt auch an U+2028/U+2029/NEL,
                // die in JSON-Strings stehen dürfen.
                for try await byte in bytes {
                    if byte == 0x0A {
                        if stream.consume(ChatStreamParser.decodeLine(line)) == .done { return stream.completion() }
                        line.removeAll(keepingCapacity: true)
                    } else {
                        line.append(byte)
                    }
                }
                if !line.isEmpty { _ = stream.consume(ChatStreamParser.decodeLine(line)) }
                return stream.completion()
            }
        } catch {
            return .failure(Self.failure(for: error))
        }
    }
}

/// Liest OpenAI-kompatible Server-Sent Events („data: {…}“) und hilfsweise eine
/// gewöhnliche JSON-Antwort.
struct ChatStreamParser {
    enum Step { case more, done }

    private var content = ""
    private var finishReason: String?
    private var sawEvent = false
    private var sawDone = false
    private var failure: GroqFailure?
    private var plain = ""

    /// Eine Zeile ohne abschließendes \r.
    static func decodeLine(_ data: Data) -> String {
        var bytes = data
        if bytes.last == 0x0D { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }

    mutating func consume(_ line: String) -> Step {
        guard line.hasPrefix("data:") else {
            plain += line + "\n"
            return .more
        }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { sawDone = true; return .done }
        sawEvent = true
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            failure = .invalidResponse
            return .done
        }
        if let error = object["error"] as? [String: Any] {
            failure = Self.failure(for: error)
            return .done
        }
        if let choice = (object["choices"] as? [[String: Any]])?.first {
            if let delta = choice["delta"] as? [String: Any], let text = delta["content"] as? String { content += text }
            if let reason = choice["finish_reason"] as? String { finishReason = reason }
        }
        return .more
    }

    /// Fehler im Stream: Limit wie HTTP 429 (Wartezeit aus Groqs Text), sonst unlesbar.
    static func failure(for error: [String: Any]) -> GroqFailure {
        let code = error["code"] as? String
        if code == "rate_limit_exceeded" || (error["type"] as? String)?.contains("rate_limit") == true {
            return .http(status: 429, code: code, retryAfter: GroqClient.retryAfter(message: error["message"] as? String))
        }
        return .invalidResponse
    }

    /// Ohne `[DONE]` und ohne `finish_reason` ist die Antwort unvollständig (Verbindung
    /// abgerissen) – dann fehlte womöglich der Schluss des Diktats: ein Neuversuch.
    func completion() -> Result<ChatCompletion, GroqFailure> {
        if let failure { return .failure(failure) }
        if sawEvent {
            guard sawDone || finishReason != nil else { return .failure(.invalidResponse) }
            return .success(ChatCompletion(content: content, finishReason: finishReason))
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any],
              let first = (object["choices"] as? [[String: Any]])?.first else { return .failure(.invalidResponse) }
        let message = first["message"] as? [String: Any]
        return .success(ChatCompletion(content: message?["content"] as? String, finishReason: first["finish_reason"] as? String))
    }
}

// MARK: - Strukturierte Antworten (Gedanken, KONZEPT §6.2)

/// Eine Anfrage mit striktem JSON-Schema (`response_format: json_schema, strict: true`).
package struct StructuredChatRequest: Sendable {
    package var model: String
    package var system: String
    package var user: String
    package var schemaName: String
    /// Schema als JSON-Bytes (siehe `ThoughtSchema.data`).
    package var schema: Data
    package var maxCompletionTokens: Int
    /// "low" | "medium"
    package var reasoningEffort: String
    package var temperature: Double

    package init(model: String, system: String, user: String, schemaName: String, schema: Data,
                 maxCompletionTokens: Int, reasoningEffort: String = "low", temperature: Double = 0.1) {
        self.model = model
        self.system = system
        self.user = user
        self.schemaName = schemaName
        self.schema = schema
        self.maxCompletionTokens = maxCompletionTokens
        self.reasoningEffort = reasoningEffort
        self.temperature = temperature
    }
}

package struct StructuredChatResponse: Sendable, Equatable {
    package var content: String?
    package var finishReason: String?
    package var usage: TokenUsage?

    package init(content: String?, finishReason: String?, usage: TokenUsage?) {
        self.content = content
        self.finishReason = finishReason
        self.usage = usage
    }
}

extension GroqClient {
    /// Leerlauf-Timeout der strukturierten Anfrage. Ohne Stream schweigt die Verbindung, bis die
    /// ganze Antwort fertig ist (Reasoning + JSON), deshalb großzügiger als beim Polieren.
    static let structuredIdleTimeout: TimeInterval = 120

    /// Genau ein Versuch, ohne Stream (wie Mac `groq.js`). Wiederholungen, Ausweichmodell und
    /// Ledger regelt `ThoughtStructurer` (§6.8). Fehler kommen als `GroqFailure`:
    /// `.http(400, "json_validate_failed", _)` = Schema nicht erfüllt, 401/403/404/429/5xx,
    /// `.network`, `.invalidResponse`. `finish_reason` prüft der Aufrufer.
    package func chatStructured(_ request: StructuredChatRequest) async -> Result<StructuredChatResponse, GroqFailure> {
        await structuredCall(request).result
    }

    /// **Nur Prüfstand und Debug-Diagnose.** Wie `chatStructured`, dazu bei `json_validate_failed` das Feld
    /// `error.failed_generation` von Groq: die verworfene Modellantwort. Sie enthält Nutzertext und darf in der
    /// App nie ins Protokoll – die App-Pfade (`ThoughtStructurer`) rufen nur `chatStructured` auf und bekommen
    /// den Text gar nicht erst. Bewusst nicht als Feld an `GroqFailure`: Das Enum wird im Diktat an ~20 Stellen
    /// zerlegt, ein weiterer Wert hätte alle diese Stellen geändert.
    package func chatStructuredDiagnosed(_ request: StructuredChatRequest) async
        -> (result: Result<StructuredChatResponse, GroqFailure>, failedGeneration: String?) {
        await structuredCall(request)
    }

    private func structuredCall(_ request: StructuredChatRequest) async
        -> (result: Result<StructuredChatResponse, GroqFailure>, failedGeneration: String?) {
        guard let schema = try? JSONSerialization.jsonObject(with: request.schema) else { return (.failure(.invalidResponse), nil) }
        let body: [String: Any] = [
            "model": request.model,
            "messages": [["role": "system", "content": request.system], ["role": "user", "content": request.user]],
            "temperature": request.temperature,
            "reasoning_effort": request.reasoningEffort,
            "max_completion_tokens": request.maxCompletionTokens,
            "response_format": ["type": "json_schema",
                                "json_schema": ["name": request.schemaName, "strict": true, "schema": schema]],
        ]
        var urlRequest = self.request("chat/completions", method: "POST")
        urlRequest.timeoutInterval = Self.structuredIdleTimeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (sent, errorBody) = await sendKeepingErrorBody(urlRequest)
        let result: Result<StructuredChatResponse, GroqFailure> = sent.flatMap { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choice = (object["choices"] as? [[String: Any]])?.first else { return .failure(.invalidResponse) }
            let message = choice["message"] as? [String: Any]
            var usage: TokenUsage?
            if let u = object["usage"] as? [String: Any], let total = u["total_tokens"] as? Int {
                usage = TokenUsage(prompt: u["prompt_tokens"] as? Int ?? 0, completion: u["completion_tokens"] as? Int ?? 0,
                                   total: total)
            }
            return .success(StructuredChatResponse(content: message?["content"] as? String,
                                                   finishReason: choice["finish_reason"] as? String, usage: usage))
        }
        return (result, errorBody.flatMap(Self.failedGeneration))
    }

    /// Wie `send`, behält aber bei HTTP-Fehlern den Antwortkörper (für `failed_generation`).
    /// `send` selbst bleibt unverändert (Diktat).
    private func sendKeepingErrorBody(_ request: URLRequest) async -> (Result<Data, GroqFailure>, Data?) {
        if Task.isCancelled { return (.failure(.cancelled), nil) }
        do {
            let (data, response) = try await transport.withSession { try await $0.data(for: request) }
            guard let http = response as? HTTPURLResponse else { return (.failure(.invalidResponse), nil) }
            responseHeaders?(http)
            guard (200..<300).contains(http.statusCode) else {
                let failure = GroqFailure.http(status: http.statusCode, code: Self.errorCode(data),
                                               retryAfter: Self.retryAfter(http) ?? Self.retryAfter(message: Self.errorMessage(data)))
                return (.failure(failure), data)
            }
            return (.success(data), nil)
        } catch {
            return (.failure(Self.failure(for: error)), nil)
        }
    }

    static func failedGeneration(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return error["failed_generation"] as? String
    }
}
