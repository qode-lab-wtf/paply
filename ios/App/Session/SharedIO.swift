import Foundation

/// Dateien in der App Group schreiben und danach das passende Darwin-Signal senden –
/// seriell auf einer eigenen Queue: kein Datei-I/O auf dem Main-Thread, und die
/// Reihenfolge (erst Datei, dann Signal) bleibt für die Tastatur erhalten.
enum SharedIO {
    private static let queue = DispatchQueue(label: "paply.shared-io", qos: .userInitiated)

    static func async(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }
}
