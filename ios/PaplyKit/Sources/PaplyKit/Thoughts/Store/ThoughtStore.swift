// GERÜST (G0.1, Koordinator). Besitzer: H2. Signatur aus KONZEPT.md §9.2 bitte nicht ändern.
import Foundation

public enum ThoughtStoreError: Error, Sendable {
    case notImplemented
}

/// JSON-Dateien je Gedanke (KONZEPT §7).
public actor ThoughtStore {
    private let root: URL
    private let changeStream: AsyncStream<String>

    public init(root: URL) throws {
        self.root = root
        self.changeStream = AsyncStream { _ in }
    }

    public func beginCapture(trigger: ThoughtTrigger, at: Date) throws -> (thought: Thought, audio: WAVWriter) {
        throw ThoughtStoreError.notImplemented
    }

    public func all() -> [Thought] { [] }
    public func thought(_ id: String) -> Thought? { nil }
    public func source(_ id: String) -> ThoughtSource? { nil }
    /// atomar, rev + 1
    public func save(_ thought: Thought) throws { throw ThoughtStoreError.notImplemented }
    public func saveSourceOnce(_ id: String, _ source: ThoughtSource) throws { throw ThoughtStoreError.notImplemented }
    public func saveAIResult(_ id: String, _ result: StructureResult) throws { throw ThoughtStoreError.notImplemented }
    public func aiResult(_ id: String) -> StructureResult? { nil }
    public func topics() -> [Topic] { [] }
    public func saveTopics(_ topics: [Topic]) throws { throw ThoughtStoreError.notImplemented }
    public func audioURL(_ id: String) -> URL? { nil }
    /// reparierte IDs
    public func recover() throws -> [String] { [] }
    /// Ton 30 d, Zuletzt gelöscht 30 d
    public func housekeeping(now: Date) {}
    /// geänderte Gedanken-ID
    public nonisolated var changes: AsyncStream<String> { changeStream }
}
