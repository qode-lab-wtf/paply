import CryptoKit
import Foundation
import Observation

@MainActor @Observable
final class ConversationModels: NSObject, URLSessionDownloadDelegate {
    static let shared = ConversationModels()
    nonisolated static let sessionID = "com.paply.conversations.models"
    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gespraeche/models/nemotron-fast128")
    }
    nonisolated static var isReady: Bool {
        (try? String(contentsOf: directory.appendingPathComponent("verified"), encoding: .utf8)) == ConversationModelManifest.revision
            && ConversationModelManifest.files.allSatisfy {
                let size = try? directory.appendingPathComponent($0.local).resourceValues(forKeys: [.fileSizeKey]).fileSize
                return size == Int($0.bytes)
            }
    }
    private(set) var ready = ConversationModels.isReady
    private(set) var fraction = 0.0
    private(set) var failed = false
    private(set) var storageNotice: String?
    var statusLine: String {
        storageNotice ?? (failed ? "Fehler – erneut versuchen" : "Sprechererkennung wird geladen · 199 MB")
    }
    func invalidate() {
        try? FileManager.default.removeItem(at: Self.directory)
        ready = false
        completed = []
        received = [:]
        started = false
        start()
    }
    @ObservationIgnored var completion: (() -> Void)?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var verifying = 0
    @ObservationIgnored private var finishedEvents = false
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var rejectedResume: Set<String> = []
    @ObservationIgnored private var completed: Set<String> = []
    @ObservationIgnored private var received: [String: Int64] = [:]
    override private init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    func start() {
        guard AppSettings.shared.betaConversations else { return }
        ready = Self.isReady
        guard !ready, !started, verifying == 0 else { return }
        let available = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
        let required = ConversationModelManifest.files.reduce(Int64(0)) { $0 + $1.bytes } + 1_000_000_000
        guard available >= required else {
            storageNotice = "Zu wenig Speicher: Für die Sprechererkennung bitte 1,2 GB freimachen."
            return
        }
        storageNotice = nil
        started = true
        failed = false
        Task {
            do {
                var directory = Self.directory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                let tasks = await session.allTasks
                for file in ConversationModelManifest.files {
                    if await Self.valid(Self.directory.appendingPathComponent(file.local), sha: file.sha256) {
                        completed.insert(file.local); received[file.local] = file.bytes
                        continue
                    }
                    completed.remove(file.local)
                    if inFlight.contains(file.local) || tasks.contains(where: { $0.taskDescription == file.local }) { continue }
                    inFlight.insert(file.local)
                    let url = URL(string: "https://huggingface.co/FluidInference/nemotron-3-diarization-coreml/resolve/\(ConversationModelManifest.revision)/\(file.remote)")!
                    let resumeFile = Self.directory.appendingPathComponent(file.sha256 + ".resume")
                    let task: URLSessionDownloadTask
                    if !rejectedResume.contains(file.local), let data = try? Data(contentsOf: resumeFile) {
                        task = session.downloadTask(withResumeData: data)
                    } else { task = session.downloadTask(with: url) }
                    task.taskDescription = file.local
                    task.resume()
                }
                try finishIfReady()
            } catch { failed = true; started = false }
        }
    }
    private func finishIfReady() throws {
        fraction = Double(received.values.reduce(0, +)) / Double(ConversationModelManifest.files.reduce(0) { $0 + $1.bytes })
        guard completed.count == ConversationModelManifest.files.count else { return }
        try Data(ConversationModelManifest.revision.utf8).write(to: Self.directory.appendingPathComponent("verified"), options: .atomic)
        for file in (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "resume" {
            try? FileManager.default.removeItem(at: file)
        }
        ready = true
        Task { await ConversationsEnvironment.run() }
    }
    nonisolated private static func valid(_ url: URL, sha: String) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let file = try? FileHandle(forReadingFrom: url) else { return false }
            defer { try? file.close() }
            do {
                var hash = SHA256()
                while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
                return hash.finalize().map { String(format: "%02x", $0) }.joined() == sha
            } catch { return false }
        }.value
    }
    private func downloadFailed(_ name: String?) {
        if let name { inFlight.remove(name); rejectedResume.insert(name) }
        failed = true
        started = false
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let failedName = downloadTask.taskDescription
        guard let name = downloadTask.taskDescription,
              let file = ConversationModelManifest.files.first(where: { $0.local == name }),
              [200, 206].contains((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0) else {
            Task { @MainActor in self.downloadFailed(failedName) }; return
        }
        // Die URLSession-Datei verschwindet nach Rückkehr aus diesem Delegate-Aufruf.
        let staging = Self.directory.appendingPathComponent(UUID().uuidString + ".download")
        do { try FileManager.default.moveItem(at: location, to: staging) }
        catch { Task { @MainActor in self.downloadFailed(failedName) }; return }
        Task { @MainActor in
            self.verifying += 1
            defer {
                try? FileManager.default.removeItem(at: staging)
                self.inFlight.remove(name)
                self.verifying -= 1
                self.completeBackgroundEvents()
            }
            guard await Self.valid(staging, sha: file.sha256) else { self.downloadFailed(name); return }
            do {
                let target = Self.directory.appendingPathComponent(file.local)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.moveItem(at: staging, to: target)
                try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(file.sha256 + ".resume"))
                self.completed.insert(file.local); self.received[file.local] = file.bytes
                try self.finishIfReady()
            } catch { self.failed = true; self.started = false }
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let name = downloadTask.taskDescription else { return }
        Task { @MainActor in
            self.received[name] = totalBytesWritten
            self.fraction = min(1, Double(self.received.values.reduce(0, +)) / Double(ConversationModelManifest.files.reduce(0) { $0 + $1.bytes }))
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        if let name = task.taskDescription,
           let file = ConversationModelManifest.files.first(where: { $0.local == name }),
           let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? data.write(to: Self.directory.appendingPathComponent(file.sha256 + ".resume"), options: .atomic)
        }
        let name = task.taskDescription
        let hasResume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] is Data
        Task { @MainActor in
            if let name {
                self.inFlight.remove(name)
                if hasResume { self.rejectedResume.remove(name) } else { self.rejectedResume.insert(name) }
            }
            self.failed = true; self.started = false
        }
    }
    private func completeBackgroundEvents() {
        guard finishedEvents, verifying == 0, let completion else { return }
        self.completion = nil
        finishedEvents = false
        completion()
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in self.finishedEvents = true; self.completeBackgroundEvents() }
    }
}
