import AppIntents
import SwiftUI
import WidgetKit

/// Gedanken-Knopf für Sperrbildschirm, Kontrollzentrum und Aktionstaste (KONZEPT §3.6).
/// Zustand aus `thought-state.json` (nur recording/id/startedAt). Die App lädt das Control bei
/// jedem Wechsel neu (`ControlCenter.shared.reloadControls(ofKind:)`).
struct ThoughtControl: ControlWidget {
    static let kind = ControlKinds.thought

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ThoughtControlValueProvider()) { isOn in
            ControlWidgetToggle("Gedanke", isOn: isOn, action: SetThoughtRecordingIntent()) { on in
                // Eigenes SF-Symbol (p-Kopf) aus Widgets/Assets.xcassets, erzeugt mit
                // scripts/make-control-symbol.swift
                Label(on ? "Aufnahme" : "Gedanke", image: on ? "paply.mark.fill" : "paply.mark")
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
