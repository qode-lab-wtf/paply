import Foundation

/// Ein Aufruf je Gedanke an gpt-oss (KONZEPT §6.1/§6.8).
///
/// Ablauf: Prompt bauen (ggf. kürzen) → im Ledger reservieren → `chatStructured` (striktes Schema,
/// ohne Stream) → abrechnen → `finish_reason == "stop"` → `ThoughtValidator`.
///
/// | Ereignis | Verhalten |
/// | --- | --- |
/// | 429, Retry-After ≤ 20 s | einmal warten, gleiches Modell |
/// | 429 lang / 404 bei 120b | einmal 20b |
/// | 429 auch bei 20b | `.wait(.waitingLimit)`, mindestens 15 Min. |
/// | 404 auch bei 20b | `.unusable("model_missing")` |
/// | 401/403 | `.wait(.waitingKey)` |
/// | ungültige Ausgabe / Abbruch / Validierung gescheitert | einmal mit `reasoning_effort: "medium"`, dann `.unusable("invalid_output")` |
/// | Netz / Zeitüberschreitung / 5xx | `.wait(.waitingNetwork)` (Backoff macht der Prozessor) |
/// | Ledger voll / Minutenfenster | `.wait(.waitingBudget)` mit `retryAt` |
/// | Anfrage größer als das Tagesbudget | `.unusable("budget_small")` |
/// | auch gekürzt > 7 600 Tokens | `.unusable("too_large")` (Teile-Modus beim Aufrufer) |
///
/// Kein Zeitlimit für die Antwort, nur ein Leerlauf-Timeout gegen tote Verbindungen.
public struct ThoughtStructurer: ThoughtStructuring {
    public static let primaryModel = "openai/gpt-oss-120b"
    public static let fallbackModel = "openai/gpt-oss-20b"
    /// Mindestwartezeit, wenn beide Modelle im Limit sind.
    static let limitWait: TimeInterval = 15 * 60

    /// Modell und Ausweichmodell (Entwicklerbereich `paply.thoughts.model`). Standard: 120b, Ausweich 20b.
    /// Ohne Ausweich (nil oder gleich dem Modell) führt ein langes 429 direkt zu `.waitingLimit`, ein 404 zu
    /// `.unusable("model_missing")`.
    public struct Models: Sendable, Equatable {
        public var primary: String
        public var fallback: String?

        public init(primary: String, fallback: String?) {
            self.primary = primary
            self.fallback = fallback
        }

        public static let standard = Models(primary: ThoughtStructurer.primaryModel, fallback: ThoughtStructurer.fallbackModel)
    }

    let ledger: TokenLedger?
    let transport: GroqTransport
    let baseURL: URL
    /// ID des Gedankens selbst (kein Selbstbezug in `related`), falls bekannt.
    let selfID: String?
    /// Je Gedanke neu gelesen, damit eine Änderung im Entwicklerbereich sofort wirkt.
    let models: @Sendable () -> Models
    /// Uhr für Wartezeiten; `now` im Prompt nur, wenn `input.recordedAt` fehlt.
    let now: @Sendable () -> Date

    public init() {
        self.init(ledger: nil)
    }

    public init(ledger: TokenLedger?, selfID: String? = nil, models: @escaping @Sendable () -> Models = { .standard }) {
        self.init(ledger: ledger, transport: .shared, baseURL: GroqClient.defaultBaseURL, selfID: selfID, models: models)
    }

    package init(ledger: TokenLedger?, transport: GroqTransport, baseURL: URL, selfID: String? = nil,
                 models: @escaping @Sendable () -> Models = { .standard },
                 now: @escaping @Sendable () -> Date = Date.init) {
        self.ledger = ledger
        self.transport = transport
        self.baseURL = baseURL
        self.selfID = selfID
        self.models = models
        self.now = now
    }

    public func structure(_ input: StructureInput, apiKey: String) async -> StructureOutcome {
        let key = apiKey.trimmed
        guard !key.isEmpty else { return .wait(.waitingKey, retryAt: nil, message: "Groq-Schlüssel fehlt") }
        let built: ThoughtPrompt.Built
        do { built = try ThoughtPrompt.build(input, now: input.recordedAt ?? now()) } catch { return .unusable(code: "too_large") }
        let client = GroqClient(apiKey: key, transport: transport, baseURL: baseURL)

        let chosen = models()
        let fallback = chosen.fallback.flatMap { $0 == chosen.primary || $0.isEmpty ? nil : $0 }
        var model = chosen.primary
        var effort = input.reasoningEffort
        var usedShortRetry = false, usedFallback = false, usedEffortRetry = false
        var usage = TokenUsage(prompt: 0, completion: 0, total: 0)

        /// Einmal mit mehr Nachdenken versuchen, sonst unbrauchbar.
        func retryWithMoreReasoning() -> Bool {
            guard !usedEffortRetry else { return false }
            usedEffortRetry = true
            effort = "medium"
            return true
        }

        while true {
            if Task.isCancelled { return .wait(.waitingNetwork, retryAt: nil, message: "Abgebrochen") }
            let reservation: TokenLedger.Reservation?
            do {
                reservation = try await ledger?.reserve(model: model, amount: built.estimate, unit: .tokens)
            } catch {
                switch error {
                case .budgetTooSmall: return .unusable(code: "budget_small")
                case .budget(let retryAt): return .wait(.waitingBudget, retryAt: retryAt, message: "Gedanken-Budget für heute erreicht")
                case .minute(let retryAt): return .wait(.waitingBudget, retryAt: retryAt, message: "Kurze Pause für das Groq-Limit")
                }
            }
            let request = StructuredChatRequest(
                model: model, system: built.system, user: built.user,
                schemaName: built.isPart ? ThoughtSchema.partName : ThoughtSchema.name,
                schema: ThoughtSchema.data(built.isPart ? ThoughtSchema.part : ThoughtSchema.full),
                maxCompletionTokens: built.maxCompletionTokens, reasoningEffort: effort)
            let result = await client.chatStructured(request)

            switch result {
            case .success(let response):
                if let reservation { await ledger?.settle(reservation, actual: response.usage?.total) }
                if let u = response.usage {
                    usage = TokenUsage(prompt: usage.prompt + u.prompt, completion: usage.completion + u.completion,
                                       total: usage.total + u.total)
                }
                guard response.finishReason == "stop", let content = response.content else {
                    if retryWithMoreReasoning() { continue }
                    return .unusable(code: "invalid_output")
                }
                let validated = built.isPart
                    ? ThoughtValidator.validatePart(json: content, input: input)
                    : ThoughtValidator.validate(json: content, input: input, aliases: built.aliases, selfID: selfID)
                switch validated {
                case .success(let structure):
                    return .success(structure, model: model, usage: usage)
                case .failure:
                    if retryWithMoreReasoning() { continue }
                    return .unusable(code: "invalid_output")
                }

            case .failure(let failure):
                switch failure {
                case .http(let status, _, _) where [401, 403, 404, 429].contains(status):
                    if let reservation { await ledger?.settle(reservation, actual: 0) }
                default:
                    if let reservation { await ledger?.settle(reservation, actual: nil) }
                }
                switch failure {
                case .http(400, "json_validate_failed", _), .invalidResponse:
                    if retryWithMoreReasoning() { continue }
                    return .unusable(code: "invalid_output")
                case .http(429, _, let retryAfter):
                    if let wait = retryAfter, wait <= client.maxRetryAfterSeconds, !usedShortRetry {
                        usedShortRetry = true
                        do { try await Task.sleep(for: .seconds(wait)) } catch {
                            return .wait(.waitingNetwork, retryAt: nil, message: "Abgebrochen")
                        }
                        continue
                    }
                    if let fallback, !usedFallback {
                        usedFallback = true
                        model = fallback
                        continue
                    }
                    let wait = max(retryAfter ?? 0, Self.limitWait)
                    return .wait(.waitingLimit, retryAt: now().addingTimeInterval(wait), message: "Groq-Limit · später erneut")
                case .http(401, _, _), .http(403, _, _):
                    return .wait(.waitingKey, retryAt: nil, message: "Groq-Schlüssel prüfen")
                case _ where failure.isModelMissing:
                    if let fallback, !usedFallback {
                        usedFallback = true
                        model = fallback
                        continue
                    }
                    return .unusable(code: "model_missing")
                case .http(let status, _, _) where status >= 500:
                    return .wait(.waitingNetwork, retryAt: nil, message: "Groq ist gerade gestört")
                case .http:
                    return .unusable(code: "request_rejected")
                case .network:
                    return .wait(.waitingNetwork, retryAt: nil, message: "Wartet auf Netz")
                case .cancelled:
                    return .wait(.waitingNetwork, retryAt: nil, message: "Abgebrochen")
                }
            }
        }
    }
}
