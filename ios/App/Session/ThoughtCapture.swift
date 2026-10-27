import Foundation
import Observation
import PaplyKit

// Aufnahme eines Gedankens (KONZEPT §5). Besitzer: H3.

enum ThoughtToggleOutcome: Sendable, Equatable {
    case started(String)
    case stopped(String)
    case ignored
    case needsForeground(String)
    case refused(String)
}

enum ThoughtFinishReason: String, Sendable {
    case button, liveActivity, app, interruption, keyboardTookOver, limit, storage
}

@MainActor
@Observable
final class ThoughtCapture {
    static let shared = ThoughtCapture()

    struct Active: Equatable {
        let id: String
        let startedAt: Date
        var speechDetected: Bool
    }

    private(set) var active: Active?

    @ObservationIgnored private let levelBox = ThoughtLevelBox()

    /// Lock-Wert (0…1), für TimelineView – keine SwiftUI-Invalidierung je Sample.
    var level: Float { levelBox.value }

    private init() {}

    func toggle(trigger: ThoughtTrigger) async -> ThoughtToggleOutcome {
        .refused("Gedanken sind noch nicht verfügbar.")
    }

    func finish(_ reason: ThoughtFinishReason) {}

    func discard() {}
}

/// Pegel als Lock-Wert: der Audio-Thread schreibt, die Oberfläche liest per TimelineView.
final class ThoughtLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Float = 0

    var value: Float {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func set(_ value: Float) {
        lock.lock()
        current = value
        lock.unlock()
    }
}
