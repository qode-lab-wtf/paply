import Foundation

public enum GroqConnection {
    /// Höchstalter der Modellliste, bevor `prewarm` sie neu lädt.
    public static let modelListMaxAge: TimeInterval = 6 * 60 * 60

    /// TLS/HTTP-2-Verbindung der geteilten URLSession zu Groq aufbauen (z. B. bei erkannter
    /// Sprache), damit sie steht, wenn die Aufnahme endet. Schickt dafür nur ein `HEAD`
    /// ohne Schlüssel (Antwort egal, ~0,2 s, kein Body). Die Modellliste wird nur geladen,
    /// wenn sie fehlt, älter als `modelListMaxAge` ist oder `refreshModels` gesetzt ist –
    /// diese Anfrage wärmt die Verbindung dann gleich mit. Fehler bleiben still.
    public static func prewarm(apiKey: String, refreshModels: Bool = false) async {
        guard !apiKey.trimmed.isEmpty else { return }
        await prewarm(GroqClient(apiKey: apiKey), catalog: .shared, refreshModels: refreshModels)
    }

    package static func prewarm(_ client: GroqClient, catalog: ModelCatalog, refreshModels: Bool = false) async {
        let age = await catalog.age(apiKey: client.apiKey)
        if refreshModels || age.map({ $0 > modelListMaxAge }) ?? true {
            _ = await catalog.models(client, forceRefresh: true)
        } else {
            var request = URLRequest(url: client.baseURL.appendingPathComponent("models"))
            request.httpMethod = "HEAD"
            request.timeoutInterval = GroqClient.keyCheckTimeout
            _ = try? await client.transport.withSession { try await $0.data(for: request) }
        }
    }

    /// true, wenn Groq den Schlüssel akzeptiert (Hülle um `checkKey`).
    public static func validate(apiKey: String) async -> Bool {
        await checkKey(apiKey: apiKey) == .valid
    }

    /// Ergänzung: Prüft den Schlüssel mit einer leichten Anfrage (Modellliste), höchstens
    /// 15 s ohne Antwort, bei vorübergehendem Fehler genau einmal wiederholt.
    /// Ein Limit (429) heißt: Schlüssel gültig, nur gerade ausgelastet.
    public static func checkKey(apiKey: String) async -> KeyCheck {
        await checkKey(GroqClient(apiKey: apiKey.trimmed))
    }

    static func checkKey(_ client: GroqClient) async -> KeyCheck {
        guard !client.apiKey.isEmpty else { return .invalid }
        var request = client.request("models")
        request.timeoutInterval = GroqClient.keyCheckTimeout
        var limited = client
        limited.maxRetryAfterSeconds = 0
        switch await limited.sendWithRetry(request) {
        case .success: return .valid
        case .failure(.http(429, _, _)): return .valid
        case .failure(.http(let status, _, _)) where status == 401 || status == 403: return .invalid
        case .failure(.network(let code)) where offlineCodes.contains(code): return .offline
        case .failure(.http(let status, _, _)) where status < 500:
            return .failed("Schlüsselprüfung fehlgeschlagen (Fehler \(status)) – bitte später erneut versuchen.")
        case .failure(let failure): return .failed(failure.germanMessage)
        }
    }

    static let offlineCodes: Set<Int> = Set([
        URLError.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
        .callIsActive, .secureConnectionFailed,
    ].map(\.rawValue))

    /// Verwirft offene Verbindungen und den Modell-Cache (z. B. nach Netzwechsel; Messungen).
    /// Laufende Anfragen laufen auf der alten Verbindung zu Ende.
    public static func reset() async {
        GroqTransport.shared.reset()
        await ModelCatalog.shared.reset()
    }
}

/// Ergänzung: Ergebnis der Schlüsselprüfung.
public enum KeyCheck: Sendable, Equatable {
    case valid
    /// Groq lehnt den Schlüssel ab (401/403) oder er ist leer.
    case invalid
    /// Keine Verbindung (kein Netz, DNS, Zeitüberschreitung …).
    case offline
    /// Sonstiger Fehler; deutscher Text zum Anzeigen.
    case failed(String)
}
