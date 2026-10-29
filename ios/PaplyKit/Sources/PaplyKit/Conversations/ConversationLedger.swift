import Foundation

public enum ConversationLedger {
    public static func make(root: URL, now: @escaping @Sendable () -> Date = Date.init) -> TokenLedger {
        TokenLedger(fileURL: root.appendingPathComponent("ledger.json"), limits: {
            var limits = TokenLedger.Limits()
            limits.dailyTokens = 100_000
            limits.dailyAudioSeconds = 360 * 60
            limits.minuteTokens = 7_600
            return limits
        }, now: now)
    }
}
