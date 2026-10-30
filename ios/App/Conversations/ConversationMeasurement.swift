import Darwin
import Foundation
import PaplyKit

@MainActor
enum ConversationMeasurement {
    private static var running = false
    static func run() async {
        guard !running, ConversationModels.isReady,
              !SessionController.shared.isConversationActive,
              !SessionController.shared.isThoughtActive,
              SessionController.shared.active == nil else { return }
        running = true
        defer { running = false }
        do {
            let items = try await ConversationsEnvironment.store.all().filter { $0.deletedAt == nil }
                .sorted { $0.createdAt > $1.createdAt }
            guard let latest = items.first,
                  let audio = try await ConversationsEnvironment.store.audioURL(latest.id) else { return }
            let start = Date()
            let result = try await ConversationsEnvironment.makeDiarizer().diarize(audio: audio, expectedSpeakers: nil) { _ in }
            let seconds = Date().timeIntervalSince(start)
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            var system = utsname(); uname(&system)
            let machine = withUnsafePointer(to: &system.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            let hardware = machine.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            Diag.log("conversation.measurement", [
                "hardwareMajor": .i(hardware.first ?? 0), "hardwareMinor": .i(hardware.dropFirst().first ?? 0),
                "seconds": .d(seconds), "rtf": .d(seconds / max(0.001, Double(latest.durationMs) / 1000)),
                "processPeakBytes": .d(Double(usage.ru_maxrss)), "speakers": .i(result.speechSeconds.count),
                // Tatsächliche CoreML-Platzierung ist hier nicht beobachtbar.
                "computePlacementKnown": .i(0)
            ])
        } catch { Diag.log("conversation.measurement.failed", ["code": .i((error as NSError).code)]) }
    }
}
