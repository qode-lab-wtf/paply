// GERÜST (G0.1, Koordinator). Besitzer: H1. Signatur aus KONZEPT.md §9.2 bitte nicht ändern.
import Foundation

/// Eigener Ledger, Port von ledger.js (KONZEPT §6.2).
public actor TokenLedger {
    public struct Limits: Sendable {
        public var dailyTokens = 80_000
        public var dailyAudioSeconds = 7_200
        public var minuteTokens = 7_600
        public var minuteRequests = 15
        public init() {}
    }

    public enum Unit: String, Codable, Sendable { case tokens, audio }

    public struct Reservation: Sendable, Hashable {
        public let id: String
        public init(id: String) { self.id = id }
    }

    public enum Refusal: Error, Sendable, Equatable {
        case budget(retryAt: Date)
        case budgetTooSmall
        case minute(retryAt: Date)
    }

    private let fileURL: URL
    private let limits: @Sendable () -> Limits
    private let now: @Sendable () -> Date

    public init(fileURL: URL, limits: @escaping @Sendable () -> Limits, now: @escaping @Sendable () -> Date = Date.init) {
        self.fileURL = fileURL
        self.limits = limits
        self.now = now
    }

    public func reserve(model: String, amount: Int, unit: Unit) throws(Refusal) -> Reservation {
        Reservation(id: UUID().uuidString)
    }

    public func settle(_ reservation: Reservation, actual: Int?) {}

    public func summary() -> (tokens: Int, audioSeconds: Int, requests: Int) {
        (0, 0, 0)
    }
}
