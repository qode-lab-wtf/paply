import Foundation
import Synchronization

/// WAV 16 kHz mono Int16, eigene serielle Queue (KONZEPT §5.3).
///
/// - `append` kopiert nur und kehrt sofort zurück (Audio-Thread blockiert nie).
/// - Alle 2 s Ton: Kopf-Längen nachtragen und `fsync` – nach einem Absturz fehlen höchstens ≈ 2 s.
/// - `close()` schreibt den Rest, trägt die endgültigen Längen ein und gibt die Dauer in ms zurück.
/// - Schlägt das Schreiben fehl (Speicher voll), bleibt der bisherige Ton gültig; `hasFailed` wird true.
public final class WAVWriter: Sendable {
    public static let sampleRate = 16_000
    public static let headerSize = 44
    /// fsync-Abstand in Samples (2 s)
    static let syncInterval = 2 * sampleRate

    public let url: URL
    private let queue: DispatchQueue
    private let state: Mutex<State>

    private struct State {
        var handle: FileHandle?
        var dataBytes = 0
        var unsyncedSamples = 0
        var failed = false
        var closed = false
    }

    public enum WAVError: Error, Sendable, Equatable {
        case create
        case notWAV
    }

    /// Legt die Datei mit Platzhalter-Kopf (Längen 0) an. Vom Backup ausgeschlossen.
    public init(url: URL) throws {
        self.url = url
        queue = DispatchQueue(label: "paply.thought.wav", qos: .userInitiated)
        guard FileManager.default.createFile(atPath: url.path, contents: Self.header(dataBytes: 0),
                                             attributes: FileSafety.protectionAttributes),
              let handle = try? FileHandle(forWritingTo: url) else { throw WAVError.create }
        FileSafety.excludeFromBackup(url)
        _ = try? handle.seekToEnd()
        state = Mutex(State(handle: handle))
    }

    /// blockiert nie
    public func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        queue.async { [self] in
            state.withLock { s in
                guard !s.closed, !s.failed, let handle = s.handle else { return }
                let pcm = AudioEncoder.int16(samples)
                let data = pcm.withUnsafeBytes { Data($0) }
                do {
                    try handle.write(contentsOf: data)
                    s.dataBytes += data.count
                    s.unsyncedSamples += pcm.count
                    if s.unsyncedSamples >= Self.syncInterval {
                        s.unsyncedSamples = 0
                        try Self.patchHeader(handle, dataBytes: s.dataBytes)
                        try handle.synchronize()
                    }
                } catch {
                    // Speicher voll o. Ä.: bisherigen Ton gültig halten, nichts mehr anhängen
                    s.failed = true
                    s.dataBytes = Self.validLength(handle, fallback: s.dataBytes)
                    try? Self.patchHeader(handle, dataBytes: s.dataBytes)
                    try? handle.synchronize()
                }
            }
        }
    }

    /// durationMs. Wartet die Queue ab; mehrfacher Aufruf liefert dieselbe Dauer.
    public func close() -> Int {
        queue.sync {
            state.withLock { s in
                if !s.closed, let handle = s.handle {
                    s.closed = true
                    try? Self.patchHeader(handle, dataBytes: s.dataBytes)
                    try? handle.synchronize()
                    try? handle.close()
                    s.handle = nil
                }
                return Self.durationMs(dataBytes: s.dataBytes)
            }
        }
    }

    /// Wartet, bis alle angehängten Blöcke geschrieben sind (Tests).
    func waitForPendingWrites() {
        queue.sync {}
    }

    /// bisher geschriebene Dauer (ohne noch wartende Blöcke)
    public var durationMs: Int { state.withLock { Self.durationMs(dataBytes: $0.dataBytes) } }

    /// true nach einem Schreibfehler (z. B. Speicher voll)
    public var hasFailed: Bool { state.withLock { $0.failed } }

    // MARK: Kopf

    static func durationMs(dataBytes: Int) -> Int { dataBytes / 2 * 1000 / sampleRate }

    static func header(dataBytes: Int) -> Data {
        var data = Data(capacity: headerSize)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(clamping: 36 + dataBytes))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(clamping: dataBytes))
        return data
    }

    private static func patchHeader(_ handle: FileHandle, dataBytes: Int) throws {
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header(dataBytes: dataBytes))
        try handle.seekToEnd()
    }

    /// Nach einem Schreibfehler: tatsächlich vorhandene, gerade Datenlänge.
    private static func validLength(_ handle: FileHandle, fallback: Int) -> Int {
        guard let end = try? handle.seekToEnd() else { return fallback }
        let bytes = max(0, Int(end) - headerSize)
        return bytes - bytes % 2
    }

    // MARK: Wiederherstellung

    /// Repariert eine WAV nach Absturz: Längen aus der Dateigröße, ungerades Byte abschneiden
    /// (Mac `capture.js`). Ein unvollständiger Kopf wird neu geschrieben. Gibt die Dauer in ms zurück.
    @discardableResult
    public static func repair(_ url: URL) throws -> Int {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let size = Int(try handle.seekToEnd())
        if size < headerSize {
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: header(dataBytes: 0))
            try handle.synchronize()
            return 0
        }
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: 12) ?? Data()
        guard head.count == 12, head.prefix(4) == Data("RIFF".utf8), head.suffix(4) == Data("WAVE".utf8) else {
            throw WAVError.notWAV
        }
        var dataBytes = size - headerSize
        if dataBytes % 2 != 0 {
            dataBytes -= 1
            try handle.truncate(atOffset: UInt64(headerSize + dataBytes))
        }
        try patchHeader(handle, dataBytes: dataBytes)
        try handle.synchronize()
        return durationMs(dataBytes: dataBytes)
    }

    /// Dauer laut Kopf (ms); nil, wenn keine eigene WAV.
    public static func headerDurationMs(_ url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headerSize), head.count == headerSize,
              head.prefix(4) == Data("RIFF".utf8) else { return nil }
        let bytes = head.subdata(in: 40..<44).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        return durationMs(dataBytes: Int(bytes))
    }
}
