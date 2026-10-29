import Foundation

/// Schalten, Kopieren und Aufräumen sind geordnet; Ausschalten hinterlässt keine Kopien.
public final class ConversationLearningGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func configure(enabled: Bool, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled
        guard enabled else { try? FileManager.default.removeItem(at: directory); return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in files {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if now.timeIntervalSince(created) >= 7 * 86400 { try? FileManager.default.removeItem(at: file) }
        }
    }
    public func hook(_ copy: @escaping @Sendable (URL) -> Void) -> @Sendable (URL) -> Void {
        { [self] source in
            lock.lock(); defer { lock.unlock() }
            if enabled { copy(source) }
        }
    }
}
