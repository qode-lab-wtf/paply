import Foundation

/// Atomar und dauerhaft schreiben (Mac `repo.js`: tmp + fsync + rename), Dateischutz und Backup-Ausschluss
/// (KONZEPT §5.3, §7.2).
enum FileSafety {
    /// Vorsilbe angefangener Schreibvorgänge; `recover()` räumt Reste auf.
    static let tempPrefix = ".tmp-"

    enum Failure: Error, Sendable, Equatable {
        case posix(Int32, String)
    }

    /// Aufnahme bei gesperrtem Gerät: lesbar nach dem ersten Entsperren seit dem Neustart.
    static var protectionAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        [:]
        #endif
    }

    static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: protectionAttributes)
    }

    static func applyProtection(_ url: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes(protectionAttributes, ofItemAtPath: url.path)
        #endif
    }

    static func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    /// Schreibt in eine Nachbardatei, `fsync`, dann `rename` – die Zieldatei ist immer entweder alt oder neu.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(tempPrefix + UUID().uuidString + "-" + url.lastPathComponent)
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw Failure.posix(errno, "open") }
        var ok = false
        defer {
            if !ok { unlink(temp.path) }
        }
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    let code = errno
                    close(fd)
                    throw Failure.posix(code, "write")
                }
                offset += written
            }
        }
        if fsync(fd) != 0 {
            let code = errno
            close(fd)
            throw Failure.posix(code, "fsync")
        }
        close(fd)
        applyProtection(temp)
        guard rename(temp.path, url.path) == 0 else { throw Failure.posix(errno, "rename") }
        ok = true
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}
