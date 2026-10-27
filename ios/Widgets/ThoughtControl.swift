import AppIntents
import SwiftUI
import WidgetKit

/// Gedanken-Knopf für Sperrbildschirm, Kontrollzentrum und Aktionstaste (KONZEPT §3.6).
/// Zustand aus `thought-state.json` (nur recording/id/startedAt). Die App lädt das Control bei
/// jedem Wechsel neu (`ControlCenter.shared.reloadControls(ofKind:)`).
struct ThoughtControl: ControlWidget {
    static let kind = "thought-toggle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ThoughtControlValueProvider()) { isOn in
            ControlWidgetToggle("Gedanke", isOn: isOn, action: SetThoughtRecordingIntent()) { on in
                Label(on ? "Aufnahme" : "Gedanke", systemImage: on ? "waveform.circle.fill" : "waveform.circle")
            }
            .tint(Color.paplyGreenBright)
        }
        .displayName("Paply-Gedanke")
        .description("Ein Druck nimmt einen Gedanken auf, nochmal drücken beendet. Paply ordnet ihn in der App.")
    }
}

struct ThoughtControlValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        SharedStore.read(ThoughtStateFile.self, .thoughtState)?.recording ?? false
    }
}
