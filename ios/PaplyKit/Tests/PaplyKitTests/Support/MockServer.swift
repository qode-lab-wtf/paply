import Foundation
import Synchronization
@testable import PaplyKit

/// Netzwerkfreier Groq-Ersatz. Jeder Server hat einen eigenen Host, damit Tests parallel
/// laufen können; MockURLProtocol leitet nach Host weiter.
final class MockServer: Sendable {
    struct Request: Sendable {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data
        var timeout: TimeInterval = 0
        var path: String { url.path }
        var bodyText: String { String(decoding: body, as: UTF8.self) }
        var json: [String: Any]? { try? JSONSerialization.jsonObject(with: body) as? [String: Any] }

        /// Wert eines Multipart-Textfelds.
        func field(_ name: String) -> String? {
            guard let range = bodyText.range(of: "name=\"\(name)\"\r\n") else { return nil }
            let afterName = bodyText[range.upperBound...]
            guard let headersEnd = afterName.range(of: "\r\n\r\n") ?? (afterName.hasPrefix("\r\n") ? afterName.range(of: "\r\n") : nil) else { return nil }
            let rest = afterName[headersEnd.upperBound...]
            guard let end = rest.range(of: "\r\n--") else { return nil }
            return String(rest[..<end.lowerBound])
        }

        /// Kopfzeilen eines Multipart-Felds (z. B. Content-Type).
        func fieldHeaders(_ name: String) -> String? {
            guard let range = bodyText.range(of: "name=\"\(name)\"") else { return nil }
            let rest = bodyText[range.upperBound...]
            guard let end = rest.range(of: "\r\n\r\n") else { return nil }
            return String(rest[..<end.lowerBound])
        }
    }

    enum Reply: Sendable {
        case raw(Int, Data, headers: [String: String] = [:], delay: Double = 0)
        case failure(URLError.Code, delay: Double = 0)

        static func json(_ status: Int, _ object: Any, headers: [String: String] = [:], delay: Double = 0) -> Reply {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            return .raw(status, data, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a }, delay: delay)
        }

        /// Gleiche Antwort, aber verzögert.
        func delayed(_ seconds: Double) -> Reply {
            switch self {
            case .raw(let s, let d, let h, _): return .raw(s, d, headers: h, delay: seconds)
            case .failure(let c, _): return .failure(c, delay: seconds)
            }
        }
    }

    typealias Handler = @Sendable (Request, Int) -> Reply

    let host = "t\(UUID().uuidString.prefix(8).lowercased()).mock"
    private let state = Mutex<(requests: [Request], handler: Handler?, stopped: Int)>(([], nil, 0))

    init(_ handler: @escaping Handler) {
        state.withLock { $0.handler = handler }
        MockURLProtocol.register(self)
    }

    var baseURL: URL { URL(string: "https://\(host)/openai/v1/")! }
    var requests: [Request] { state.withLock { $0.requests } }
    /// Anfragen, die der Client vor der Antwort abgebrochen hat.
    var stoppedCount: Int { state.withLock { $0.stopped } }
    fileprivate func markStopped() { state.withLock { $0.stopped += 1 } }
    func requests(_ suffix: String) -> [Request] { requests.filter { $0.path.hasSuffix(suffix) } }

    /// Eigener Transport je Server (wie eine eigene Verbindung).
    let transport = GroqTransport(protocolClasses: [MockURLProtocol.self])

    func client(retryDelay: Double = 0.01) -> GroqClient {
        var client = GroqClient(apiKey: "test-placeholder", transport: transport, baseURL: baseURL)
        client.retryDelaySeconds = retryDelay
        return client
    }

    fileprivate func handle(_ request: Request) -> Reply {
        let (handler, index) = state.withLock { s -> (Handler?, Int) in
            s.requests.append(request)
            return (s.handler, s.requests.filter { $0.path == request.path }.count - 1)
        }
        return handler?(request, index) ?? .raw(500, Data())
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let servers = Mutex<[String: MockServer]>([:])
    private let stopped = Mutex(false)
    private let answered = Mutex(false)
    private let server = Mutex<MockServer?>(nil)

    static func register(_ server: MockServer) {
        servers.withLock { $0[server.host] = server }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".mock") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host,
              let server = Self.servers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let recorded = MockServer.Request(
            url: url, method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:], body: Self.body(of: request), timeout: request.timeoutInterval)
        self.server.withLock { $0 = server }
        let reply = server.handle(recorded)
        let delay: Double
        switch reply {
        case .raw(_, _, _, let d), .failure(_, let d): delay = d
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            guard !stopped.withLock({ $0 }) else { return }
            switch reply {
            case .failure(let code, _):
                answered.withLock { $0 = true }
                client?.urlProtocol(self, didFailWithError: URLError(code))
            case .raw(let status, let data, let headers, _):
                respond(status: status, data: data, headers: headers)
            }
        }
    }

    private func respond(status: Int, data: Data, headers: [String: String]) {
        answered.withLock { $0 = true }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/2", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
        if !answered.withLock({ $0 }) { server.withLock { $0 }?.markStopped() }
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: Antwort-Bausteine

enum Groq {
    static func models(_ ids: String...) -> MockServer.Reply {
        .json(200, ["object": "list", "data": ids.map { ["id": $0, "object": "model"] }])
    }

    static func transcription(_ text: String, language: String = "German", logprob: Double = -0.2) -> MockServer.Reply {
        .json(200, [
            "text": " " + text, "language": language, "duration": 3.0, "task": "transcribe",
            "segments": [["id": 0, "start": 0.0, "end": 3.0, "text": " " + text, "avg_logprob": logprob,
                          "no_speech_prob": 0.0, "compression_ratio": 1.1]],
        ])
    }

    /// Polier-Antwort als Server-Sent Events (wie Groq mit `stream: true`), in Teilen.
    static func chat(_ content: String, finish: String = "stop") -> MockServer.Reply {
        var events: [String] = []
        func event(_ object: Any) {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            events.append("data: " + String(decoding: data, as: UTF8.self) + "\n\n")
        }
        event(["choices": [["index": 0, "delta": ["role": "assistant", "content": ""], "finish_reason": NSNull()]]])
        let scalars = Array(content.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let end = min(index + 7, scalars.count)
            event(["choices": [["index": 0, "delta": ["content": String(String.UnicodeScalarView(scalars[index..<end]))],
                                "finish_reason": NSNull()]]])
            index = end
        }
        event(["choices": [["index": 0, "delta": [String: Any](), "finish_reason": finish]], "x_groq": ["usage": ["total_tokens": 1]]])
        events.append("data: [DONE]\n\n")
        return .raw(200, Data(events.joined().utf8), headers: ["Content-Type": "text/event-stream"])
    }

    /// Polier-Antwort als gewöhnliches JSON (ohne Stream).
    static func chatJSON(_ content: String, finish: String = "stop") -> MockServer.Reply {
        .json(200, ["choices": [["index": 0, "finish_reason": finish,
                                 "message": ["role": "assistant", "content": content, "reasoning": "Niemals ausgeben"]]]])
    }

    static func error(_ status: Int, code: String? = nil, headers: [String: String] = [:]) -> MockServer.Reply {
        var error: [String: Any] = ["message": "Fehler"]
        if let code { error["code"] = code }
        return .json(status, ["error": error], headers: headers)
    }
}
