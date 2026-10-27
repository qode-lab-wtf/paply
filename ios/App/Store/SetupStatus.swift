import Foundation
import Observation
import UIKit

/// Ist die Paply-Tastatur eingerichtet? Für die Startseite („nächster Schritt“) und die
/// Einstellungen („Tastatur einrichten“ nur, solange etwas fehlt).
@MainActor
@Observable
final class SetupStatus {
    static let shared = SetupStatus()

    /// Paply steht in der Liste der aktiven Tastaturen
    private(set) var keyboardEnabled = true
    /// Die Tastatur hat schon mit Vollzugriff in die App Group geschrieben
    private(set) var fullAccessSeen = true

    private init() {}

    var needsKeyboardSetup: Bool { !keyboardEnabled || !fullAccessSeen }

    /// Beim Erscheinen und wenn die App nach vorne kommt.
    func refresh() {
        keyboardEnabled = Self.paplyKeyboardActive()
        Task.detached(priority: .utility) {
            let seen = Self.fullAccessEvidence()
            await MainActor.run { SetupStatus.shared.fullAccessSeen = seen }
        }
    }

    /// Ist Paply unter den aktiven Tastaturen?
    /// Release: öffentlich über die Sprache „mul“ (PrimaryLanguage der Paply-Tastatur).
    /// Debug: zusätzlich die genaue, aber nicht öffentliche Kennung – im Release nicht einkompiliert.
    private static func paplyKeyboardActive() -> Bool {
        let modes = UITextInputMode.activeInputModes
        #if DEBUG
        let bundleID = AppGroup.keyboardBundleID
        let byIdentifier = modes.contains { mode in
            guard mode.responds(to: NSSelectorFromString("identifier")),
                  let id = mode.value(forKey: "identifier") as? String
            else { return false }
            return !bundleID.isEmpty && id.contains(bundleID)
        }
        if byIdentifier { return true }
        #endif
        return modes.contains { $0.primaryLanguage == "mul" }
    }

    /// Ohne Vollzugriff kann die Tastatur nicht in die App Group schreiben – liegt dort ihre
    /// Höhenmeldung oder ihr Protokoll, hatte sie Vollzugriff.
    nonisolated private static func fullAccessEvidence() -> Bool {
        if let url = SharedStore.url(.keyboardReport), FileManager.default.fileExists(atPath: url.path) { return true }
        guard let dir = AppGroup.directory(Diag.directoryName),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return false }
        if let dir = AppGroup.directory("selftest"), FileManager.default.fileExists(atPath: dir.appendingPathComponent("kb.json").path) {
            return true
        }
        return files.contains { $0.hasSuffix("-kb.jsonl") }
    }
}

/// Hat dieses iPhone eine Aktionstaste? (ab iPhone 15 Pro)
enum DeviceInfo {
    static let hasActionButton: Bool = {
        var info = utsname()
        uname(&info)
        var machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { machine = simulated }
        // „iPhone16,1“ → 16, 1
        guard machine.hasPrefix("iPhone") else { return false }
        let numbers = machine.dropFirst("iPhone".count).split(separator: ",").compactMap { Int($0) }
        guard numbers.count == 2 else { return false }
        let (major, minor) = (numbers[0], numbers[1])
        // 15 Pro / Pro Max = iPhone16,1 / 16,2; ab iPhone17,x (16er-Reihe) haben alle eine
        return major > 16 || (major == 16 && (minor == 1 || minor == 2))
    }()
}

/// Ergebnis des Speicher-Selbsttests für den Entwicklerbereich.
@MainActor
@Observable
final class StorageCheck {
    static let shared = StorageCheck()

    private(set) var result: StorageSelfTest.Result?
    private(set) var files: [(path: String, bytes: Int)] = []
    private(set) var checkedAt: Date?

    private init() {}

    /// Selbsttest + Bestandsliste auf der I/O-Queue, Ergebnis zurück auf den Main-Actor.
    func run(reason: String) {
        SharedIO.async {
            let result = StorageSelfTest.run(as: .app)
            let files = StorageSelfTest.inventory()
            Diag.log("storage.inventory", [
                "reason": .s(reason),
                "base": .opt(AppGroup.baseURL?.path),
                "files": .i(files.count),
                "list": .s(files.prefix(25).map { "\($0.path)=\($0.bytes)" }.joined(separator: ", ")),
            ])
            Task { @MainActor in
                let check = StorageCheck.shared
                check.result = result
                check.files = files
                check.checkedAt = Date()
            }
        }
    }

    /// Alte Ablage im Container-Wurzelordner (bis Phase-0-Build vom 27.10.) aufräumen:
    /// Diagnose übernehmen, Rest löschen. Läuft auf der I/O-Queue.
    nonisolated static func migrateOldLayout() {
        guard let container = AppGroup.containerURL, AppGroup.baseURL != nil else { return }
        let fm = FileManager.default
        let oldDiag = container.appendingPathComponent(Diag.directoryName, isDirectory: true)
        if fm.fileExists(atPath: oldDiag.path), let newDiag = AppGroup.directory(Diag.directoryName) {
            let files = (try? fm.contentsOfDirectory(at: oldDiag, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                var target = newDiag.appendingPathComponent(file.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    target = newDiag.appendingPathComponent("alt-" + file.lastPathComponent)
                }
                try? fm.moveItem(at: file, to: target)
            }
            try? fm.removeItem(at: oldDiag)
            Diag.log("storage.migrated", ["diagFiles": .i(files.count)])
        }
        for name in ["session.json", "keyboard-command.json", "pending-text.json", "shortcut-command.json",
                     "shortcut-ack.json", "keyboard-report.json", "levels.bin", "results", "selftest"] {
            try? fm.removeItem(at: container.appendingPathComponent(name))
        }
    }
}
