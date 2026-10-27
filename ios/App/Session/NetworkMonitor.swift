import Foundation
import Network

/// Aktueller Netztyp für die Latenz-Auswertung (WLAN vs. Mobilfunk).
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var kind = "unknown"

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let name: String
            if path.status != .satisfied {
                name = "none"
            } else if path.usesInterfaceType(.wifi) {
                name = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                name = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                name = "wired"
            } else {
                name = "other"
            }
            self?.update(name)
        }
        monitor.start(queue: DispatchQueue(label: "paply.network", qos: .utility))
    }

    var current: String {
        lock.lock()
        defer { lock.unlock() }
        return kind
    }

    private func update(_ name: String) {
        lock.lock()
        let changed = kind != name
        kind = name
        lock.unlock()
        if changed { Diag.log("net.change", ["net": .s(name)]) }
    }
}
