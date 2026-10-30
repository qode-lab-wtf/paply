import Foundation
import Synchronization

/// JSON wie am Mac (KONZEPT §7.2): Zeiten als ganze Millisekunden seit 1970, Schlüssel in camelCase.
public enum ThoughtJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(milliseconds(date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSince1970: try container.decode(Double.self) / 1000)
        }
        return decoder
    }

    public static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

/// Ein Ereignisstrom für beliebig viele Zuhörer: jeder Zugriff auf `stream` liefert einen eigenen
/// `AsyncStream` (ein einzelner AsyncStream verteilt Elemente nur an einen Zuhörer).
public final class Broadcast<Element: Sendable>: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Element>.Continuation]>([:])

    public init() {}

    public var stream: AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingNewest(256))
        continuation.onTermination = { [weak self] _ in
            _ = self?.continuations.withLock { $0.removeValue(forKey: id) }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    public func yield(_ element: Element) {
        let targets = continuations.withLock { Array($0.values) }
        for continuation in targets { continuation.yield(element) }
    }

    public func finish() {
        let targets = continuations.withLock { all -> [AsyncStream<Element>.Continuation] in
            defer { all.removeAll() }
            return Array(all.values)
        }
        for continuation in targets { continuation.finish() }
    }
}

/// Stabiler 64-Bit-Hash (FNV-1a) für abgeleitete Daten auf der Platte; `Hasher` ist je Prozess zufällig.
enum StableHash {
    static func of(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// Reine Arbeit je Element parallel über alle Kerne (Laden, Suche). Ergebnisse in Eingabereihenfolge.
/// Sendable-sicher: jeder Block sammelt lokal und übergibt einmal unter einer Sperre.
enum Parallel {
    static func map<T: Sendable>(_ count: Int, _ transform: @Sendable (Int) -> T?) -> [T?] {
        guard count > 0 else { return [] }
        let chunks = max(1, min(count, ProcessInfo.processInfo.activeProcessorCount * 2))
        let collector = Collector<T>(count: count)
        DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
            var local: [(Int, T)] = []
            var index = chunk
            while index < count {
                if let value = transform(index) { local.append((index, value)) }
                index += chunks
            }
            collector.add(local)
        }
        return collector.values
    }

    private final class Collector<T: Sendable>: Sendable {
        private let state: Mutex<[T?]>
        init(count: Int) { state = Mutex([T?](repeating: nil, count: count)) }
        func add(_ items: [(Int, T)]) {
            state.withLock { values in for (index, value) in items { values[index] = value } }
        }
        var values: [T?] { state.withLock { $0 } }
    }
}
