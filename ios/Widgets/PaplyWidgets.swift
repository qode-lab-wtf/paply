import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct PaplyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DictationLiveActivity()
        // „Paply-Diktat“ als Steuerelement nicht mehr anbieten: Diktat läuft über 🌐,
        // Gedanken über den Knopf (zwei klare Wege). DictationControl bleibt im Code.
        ConversationLiveActivity()
        ConversationControl()
        ThoughtLiveActivity()
        ThoughtControl()
        ThoughtWidget()
        TasksWidget()
    }
}

/// Kontrollzentrum (und Aktionstaste): Diktat an/aus.
struct DictationControl: ControlWidget {
    static let kind = "dictation-toggle"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleDictationIntent()) {
                Label("Paply-Diktat", systemImage: "waveform")
            }
        }
        .displayName("Paply-Diktat")
        .description("Startet oder beendet ein Diktat. Der Text landet in der Zwischenablage.")
    }
}

/// Live Activity nur während eines Schnelltasten-Diktats: Marke + Zeit.
struct DictationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.paplyForest)
                .activitySystemActionForegroundColor(Color.paplyText)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PaplyMark().frame(width: 28, height: 30).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeOrStatus(state: context.state)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(caption(for: context.state))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                PaplyMark().frame(width: 18, height: 20)
            } compactTrailing: {
                TimeOrStatus(state: context.state)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                PaplyMark().frame(width: 16, height: 18)
            }
            .keylineTint(Color.paplyGreenBright)
        }
    }
}

private func caption(for state: DictationActivityAttributes.ContentState) -> String {
    switch state.phase {
    case .recording: "Paply hört zu – Schnelltaste nochmal = fertig"
    case .polishing: "Poliere …"
    case .done: state.note ?? "Fertig"
    case .failed: state.note ?? "Das hat nicht geklappt"
    }
}

private struct TimeOrStatus: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .foregroundStyle(Color.paplyGreenBright)
                .multilineTextAlignment(.trailing)
        case .polishing:
            Image(systemName: "ellipsis").foregroundStyle(Color.paplyGreenBright)
        case .done:
            Image(systemName: "checkmark").foregroundStyle(Color.paplyGreenBright)
        case .failed:
            Image(systemName: "exclamationmark").foregroundStyle(Color.paplyDanger)
        }
    }
}

private struct LockScreenView: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            PaplyMark().frame(width: 34, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Paply").font(.headline).foregroundStyle(Color.paplyText)
                Text(caption(for: state)).font(.subheadline).foregroundStyle(Color.paplyText.opacity(0.7))
            }
            Spacer()
            TimeOrStatus(state: state).font(.title2.weight(.semibold).monospacedDigit())
        }
        .padding(16)
    }
}
