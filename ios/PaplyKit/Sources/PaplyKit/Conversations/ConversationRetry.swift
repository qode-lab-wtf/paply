import Foundation

enum ConversationRetry {
    /// Kurze Fenster bleiben innerhalb des Laufs; Tageskontingente gehen an die Oberfläche.
    static func run<T>(isolation: isolated (any Actor)? = #isolation, _ operation: () async throws -> T) async throws -> T {
        var attempts = 0
        while true {
            do { return try await operation() }
            catch {
                let delay: TimeInterval
                switch error {
                case TokenLedger.Refusal.minute(let date): delay = date.timeIntervalSinceNow
                case GroqFailure.http(429, _, let retry): delay = retry ?? 60
                default: throw error
                }
                guard delay <= 75, attempts < 3 else { throw error }
                attempts += 1
                ConversationDiagnostics.record("conversation.limit.wait", ["ms": Int(max(0, delay) * 1000), "attempt": attempts])
                try await Task.sleep(for: .seconds(max(0.01, delay)))
            }
        }
    }
}
