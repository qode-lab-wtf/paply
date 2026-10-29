import Foundation
import Synchronization

/// Serverfenster ergänzen den lokalen Ledger (auch Verbrauch anderer Geräte zählt bei Groq).
final class ConversationRateLimits: Sendable {
    struct Window { var remaining: Int; var reset: Date }
    private let windows = Mutex<[String: Window]>([:])
    func receive(_ response: HTTPURLResponse, model: String) {
        guard let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining-tokens").flatMap(Int.init),
              let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset-tokens") else { return }
        let delay = Double(reset) ?? GroqClient.retryAfter(message: "try again in " + reset) ?? 60
        windows.withLock { $0[model] = Window(remaining: remaining, reset: Date().addingTimeInterval(delay)) }
    }
    func check(model: String, amount: Int) throws {
        if let window = windows.withLock({ $0[model] }), window.remaining < amount, window.reset > Date() {
            throw TokenLedger.Refusal.minute(retryAt: window.reset)
        }
    }
}
