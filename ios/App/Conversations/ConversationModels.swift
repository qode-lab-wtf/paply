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
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("verified").path)
    }
    private(set) var ready = ConversationModels.isReady
    private(set) var fraction = 0.0
    private(set) var failed = false
    @ObservationIgnored var completion: (() -> Void)?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var verifying = 0
    @ObservationIgnored private var finishedEvents = false
    @ObservationIgnored private var session: URLSession!
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
        guard !ready, !started else { return }
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
                    if tasks.contains(where: { $0.taskDescription == file.local }) { continue }
                    let url = URL(string: "https://huggingface.co/FluidInference/nemotron-3-diarization-coreml/resolve/\(ConversationModelManifest.revision)/\(file.remote)")!
                    let resumeFile = Self.directory.appendingPathComponent(file.sha256 + ".resume")
                    let task: URLSessionDownloadTask
                    if let data = try? Data(contentsOf: resumeFile) {
                        task = session.downloadTask(withResumeData: data)
                        try? FileManager.default.removeItem(at: resumeFile)
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
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let name = downloadTask.taskDescription,
              let file = ConversationModelManifest.files.first(where: { $0.local == name }),
              (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            Task { @MainActor in self.failed = true; self.started = false }; return
        }
        // Die URLSession-Datei verschwindet nach Rückkehr aus diesem Delegate-Aufruf.
        let staging = Self.directory.appendingPathComponent(UUID().uuidString + ".download")
        do { try FileManager.default.moveItem(at: location, to: staging) }
        catch { Task { @MainActor in self.failed = true; self.started = false }; return }
        Task { @MainActor in
            self.verifying += 1
            defer {
                try? FileManager.default.removeItem(at: staging)
                self.verifying -= 1
                self.completeBackgroundEvents()
            }
            guard await Self.valid(staging, sha: file.sha256) else { self.failed = true; self.started = false; return }
            do {
                let target = Self.directory.appendingPathComponent(file.local)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.moveItem(at: staging, to: target)
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
        Task { @MainActor in self.failed = true; self.started = false }
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
