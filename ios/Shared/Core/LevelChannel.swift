import Darwin
import Foundation
import Synchronization

/// Pegel von der App zur Tastatur über eine gemeinsam gemappte Datei (`levels.bin`),
/// statt einer Flut von Darwin-Notifications. Die App schreibt ~30 Werte pro Sekunde
/// mit Zeitstempel; die Tastatur liest mit ihrer Bildrate und zeichnet leicht verzögert,
/// damit auch blockweise ankommende Pegel (Tap-Puffer ~100 ms) gleichmäßig laufen.
///
/// Aufbau: magic u32 · tag u32 · count u64 · level f32[64] · ns u64[64]
/// Ein Schreiber, ein Leser; ausgerichtete 32/64-Bit-Zugriffe sind auf arm64 atomar.
/// Speicherbarrieren sorgen dafür, dass der Leser einen Zähler nie vor seinem Wert sieht.
final class LevelChannel: @unchecked Sendable {
    static let slots = 64
    private static let magic: UInt32 = 0x504C_5631 // "PLV1"
    private static let fileSize = 4096
    private static let levelsOffset = 16
    private static let nsOffset = levelsOffset + slots * 4
    /// MAP_FAILED ist ein C-Makro und in Swift nicht verfügbar.
    private static var mapFailed: UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: -1) }

    private let base: UnsafeMutableRawPointer
    private let writable: Bool

    private init(base: UnsafeMutableRawPointer, writable: Bool) {
        self.base = base
        self.writable = writable
    }

    deinit {
        munmap(base, Self.fileSize)
    }

    private static var fileURL: URL? {
        AppGroup.baseURL?.appendingPathComponent("levels.bin")
    }

    static func openWriter() -> LevelChannel? {
        guard let url = fileURL else { return nil }
        let fd = open(url.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard ftruncate(fd, off_t(fileSize)) == 0 else { return nil }
        guard let ptr = mmap(nil, fileSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0), ptr != Self.mapFailed else { return nil }
        ptr.storeBytes(of: magic, toByteOffset: 0, as: UInt32.self)
        return LevelChannel(base: ptr, writable: true)
    }

    static func openReader() -> LevelChannel? {
        guard let url = fileURL else { return nil }
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size >= off_t(fileSize) else { return nil }
        guard let ptr = mmap(nil, fileSize, PROT_READ, MAP_SHARED, fd, 0), ptr != Self.mapFailed else { return nil }
        guard ptr.load(fromByteOffset: 0, as: UInt32.self) == magic else {
            munmap(ptr, fileSize)
            return nil
        }
        return LevelChannel(base: ptr, writable: false)
    }

    /// Stabiler Kurzwert einer Diktat-ID (prozessübergreifend gleich, FNV-1a).
    static func tag(for dictationID: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in dictationID.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    // MARK: Schreiben (App)

    /// Nur aus dem Audio-Tap-Lock aufrufen (AudioTapProcessor), damit kein alter Schreiber dazwischenkommt.
    func begin(tag: UInt32) {
        guard writable else { return }
        base.storeBytes(of: UInt64(0), toByteOffset: 8, as: UInt64.self)
        atomicMemoryFence(ordering: .releasing)
        base.storeBytes(of: tag, toByteOffset: 4, as: UInt32.self)
    }

    func push(level: Float, ns: UInt64) {
        guard writable else { return }
        let count = base.load(fromByteOffset: 8, as: UInt64.self)
        let slot = Int(count % UInt64(Self.slots))
        base.storeBytes(of: level, toByteOffset: Self.levelsOffset + slot * 4, as: Float.self)
        base.storeBytes(of: ns, toByteOffset: Self.nsOffset + slot * 8, as: UInt64.self)
        atomicMemoryFence(ordering: .releasing)
        base.storeBytes(of: count + 1, toByteOffset: 8, as: UInt64.self)
    }

    // MARK: Lesen (Tastatur)

    var tag: UInt32 { base.load(fromByteOffset: 4, as: UInt32.self) }
    var count: UInt64 { base.load(fromByteOffset: 8, as: UInt64.self) }

    /// Die letzten `max` Pegel mit Zeitstempel ≤ `notAfter`, älteste zuerst.
    func recent(max: Int, notAfter limit: UInt64) -> [Float] {
        let total = count
        atomicMemoryFence(ordering: .acquiring)
        guard total > 0 else { return [] }
        let available = Int(min(total, UInt64(Self.slots - 2)))
        var newest = -1
        for back in 0..<available {
            let index = Int((total - 1 - UInt64(back)) % UInt64(Self.slots))
            if base.load(fromByteOffset: Self.nsOffset + index * 8, as: UInt64.self) <= limit {
                newest = back
                break
            }
        }
        guard newest >= 0 else { return [] }
        let n = Swift.min(max, available - newest)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let index = Int((total - 1 - UInt64(newest + i)) % UInt64(Self.slots))
            out[n - 1 - i] = base.load(fromByteOffset: Self.levelsOffset + index * 4, as: Float.self)
        }
        return out
    }
}
