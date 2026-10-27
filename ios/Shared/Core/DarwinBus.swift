import Foundation

/// Darwin-Notifications zwischen App, Tastatur und Widgets.
/// Sie tragen keine Daten – der Inhalt liegt als Datei in der App Group.
enum DarwinSignal: String, CaseIterable, Sendable {
    /// Tastatur → App: neuer Befehl in `keyboard-command.json`
    case command
    /// Tastatur → App: Lebenszeichen-Anfrage
    case ping
    /// App → Tastatur: Antwort auf `ping` (Zeitstempel in `session.json`)
    case pong
    /// App → alle: `session.json` hat sich geändert
    case state
    /// App → Tastatur: Ergebnis liegt in `results/<id>.json`
    case result
    /// App → Tastatur: im laufenden Diktat wurde Sprache erkannt
    case speech
    /// Widget-Prozess → App: Schnelltaste gedrückt (`shortcut-command.json`)
    case shortcut
    /// App → Widget-Prozess: Schnelltaste verarbeitet (`shortcut-ack.json`)
    case shortcutAck

    var notificationName: String { "\(AppGroup.identifier).\(rawValue)" }
}

struct DarwinToken: Hashable, Sendable {
    fileprivate let id: UUID
    fileprivate let signal: DarwinSignal
}

/// Handler laufen immer auf dem Main-Thread.
final class DarwinBus: @unchecked Sendable {
    static let shared = DarwinBus()

    private let lock = NSLock()
    private var handlers: [DarwinSignal: [UUID: @MainActor @Sendable () -> Void]] = [:]
    private var registered: Set<DarwinSignal> = []

    private init() {}

    func post(_ signal: DarwinSignal) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(signal.notificationName as CFString), nil, nil, true)
    }

    @discardableResult
    func observe(_ signal: DarwinSignal, handler: @escaping @MainActor @Sendable () -> Void) -> DarwinToken {
        let id = UUID()
        lock.lock()
        handlers[signal, default: [:]][id] = handler
        let needsRegistration = registered.insert(signal).inserted
        lock.unlock()
        if needsRegistration { register(signal) }
        return DarwinToken(id: id, signal: signal)
    }

    func remove(_ token: DarwinToken) {
        lock.lock()
        handlers[token.signal]?[token.id] = nil
        lock.unlock()
    }

    private func register(_ signal: DarwinSignal) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer, let name else { return }
            let bus = Unmanaged<DarwinBus>.fromOpaque(observer).takeUnretainedValue()
            bus.dispatch(name.rawValue as String)
        }
        CFNotificationCenterAddObserver(center, observer, callback, signal.notificationName as CFString, nil, .deliverImmediately)
    }

    private func dispatch(_ name: String) {
        guard let signal = DarwinSignal.allCases.first(where: { $0.notificationName == name }) else { return }
        lock.lock()
        let list = Array((handlers[signal] ?? [:]).values)
        lock.unlock()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for handler in list { handler() }
            }
        }
    }
}
