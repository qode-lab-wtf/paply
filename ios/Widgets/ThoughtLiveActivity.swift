import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Live Activity eines Gedankens (KONZEPT §3.5). Nie Titel oder Text, höchstens der Themenname
/// (`.privacySensitive()`). Gedanken-Kennung: p-Kopf mit dünnem Mint-Gold-Ring – das Diktat hat keinen.
struct ThoughtLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ThoughtActivityAttributes.self) { context in
            ThoughtLockScreenView(state: context.state, thoughtID: context.attributes.thoughtID)
                .activityBackgroundTint(Color.paplyForest.opacity(0.92))
                .activitySystemActionForegroundColor(Color.paplyText)
                .widgetURL(Self.url(context.attributes.thoughtID))
        } dynamicIsland: { context in
            let state = context.state
            let id = context.attributes.thoughtID
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ThoughtMark(size: 36).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ThoughtTrailing(state: state, large: true)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    if state.phase == .recording {
                        Text(state.warnLimit ? "Gedanke · noch 1 Min." : "Gedanke")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(state.warnLimit ? Color.paplyBeak : Color.paplyText)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.phase == .recording {
                        // „Fertig“ primär, „Verwerfen“ sekundär – beide gut treffbar
                        HStack(spacing: 10) {
                            DiscardButton(thoughtID: id, fullWidth: false)
                            FinishButton(thoughtID: id, fullWidth: true)
                        }
                    } else {
                        ThoughtStatusText(state: state)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                ThoughtLeading(state: state, size: 20)
            } compactTrailing: {
                ThoughtTrailing(state: state, large: false)
                    .frame(maxWidth: 44)
            } minimal: {
                ThoughtLeading(state: state, size: 16)
            }
            .widgetURL(Self.url(id))
            .keylineTint(Color.paplyGreenBright)
        }
    }

    static func url(_ id: String) -> URL? {
        URL(string: "paply-ios://thought/current?id=\(id)")
    }
}

// MARK: - Bausteine

/// Mint-Gold der Mac-Notes-Pille (KONZEPT §3)
private let mintGold = [
    Color(red: 0xD8 / 255, green: 0xF3 / 255, blue: 0x9A / 255),
    Color(red: 0x7E / 255, green: 0xD9 / 255, blue: 0x57 / 255),
    Color(red: 0xDC / 255, green: 0xE5 / 255, blue: 0x68 / 255),
    Color(red: 0xF5 / 255, green: 0xBF / 255, blue: 0x50 / 255),
    Color(red: 0xBF / 255, green: 0xEE / 255, blue: 0xC4 / 255),
    Color(red: 0xD8 / 255, green: 0xF3 / 255, blue: 0x9A / 255),
]

/// p-Kopf mit Mint-Gold-Ring (statisch, 2 pt)
struct ThoughtMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().strokeBorder(AngularGradient(colors: mintGold, center: .center), lineWidth: max(1.5, size / 18))
            PaplyMark().padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Paply-Gedanke")
    }
}

private struct ThoughtLeading: View {
    let state: ThoughtActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        switch state.phase {
        case .recording, .processing, .waiting:
            ThoughtMark(size: size)
        case .saved:
            Image(systemName: "checkmark").font(.system(size: size * 0.7, weight: .bold)).foregroundStyle(Color.paplyGreenBright)
        case .empty, .failed:
            Image(systemName: "exclamationmark").font(.system(size: size * 0.7, weight: .bold)).foregroundStyle(Color.paplyBeak)
        case .discarded:
            Image(systemName: "trash").font(.system(size: size * 0.6, weight: .semibold)).foregroundStyle(Color.paplyText.opacity(0.7))
        }
    }
}

private struct ThoughtTrailing: View {
    let state: ThoughtActivityAttributes.ContentState
    let large: Bool

    var body: some View {
        switch state.phase {
        case .recording:
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .font(large ? .title2.weight(.semibold).monospacedDigit() : .callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.paplyGreenBright)
                .multilineTextAlignment(.trailing)
        case .processing:
            Image(systemName: "ellipsis").foregroundStyle(Color.paplyGreenBright)
        case .saved:
            if let title = state.topicTitle {
                HStack(spacing: 3) {
                    Image(systemName: TopicIconKey.sfSymbol(state.topicSymbol))
                    Text(title).lineLimit(1)
                }
                .font(large ? .callout.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(Color.paplyGreenBright)
                .privacySensitive()
            } else {
                Image(systemName: "checkmark").foregroundStyle(Color.paplyGreenBright)
            }
        case .waiting:
            Image(systemName: state.waitSymbol ?? "hourglass").foregroundStyle(Color.paplyBeak)
        case .empty:
            Text("Nichts").font(.caption.weight(.semibold)).foregroundStyle(Color.paplyBeak)
        case .failed:
            EmptyView()
        case .discarded:
            Text("Weg").font(.caption.weight(.semibold)).foregroundStyle(Color.paplyText.opacity(0.7))
        }
    }
}

/// Zustand in Worten (Expanded und Sperrbildschirm)
private struct ThoughtStatusText: View {
    let state: ThoughtActivityAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            Text(state.warnLimit ? "Aufnahme läuft · noch 1 Min." : "Aufnahme läuft")
        case .processing:
            Text(state.note ?? "Wird geordnet …")
        case .saved:
            if let title = state.topicTitle {
                HStack(spacing: 4) {
                    Text("Gespeichert ·")
                    Image(systemName: TopicIconKey.sfSymbol(state.topicSymbol))
                    Text(title).privacySensitive()
                }
            } else {
                Text(state.note ?? "Gespeichert")
            }
        case .waiting:
            Text(state.note ?? "Gesichert · wartet auf Netz")
        case .empty:
            Text("Nichts verstanden – nichts gespeichert")
        case .failed:
            Text(state.note ?? "Ton gesichert · Paply versucht es später")
        case .discarded:
            Text("Verworfen · in „Zuletzt gelöscht“")
        }
    }
}

/// Kapsel „Fertig“ – ein LiveActivityIntent, läuft im App-Prozess.
private struct FinishButton: View {
    let thoughtID: String
    let fullWidth: Bool

    var body: some View {
        Button(intent: FinishThoughtIntent(thoughtID: thoughtID)) {
            Label("Fertig", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(Color.paplyForest)
                .background(Capsule().fill(Color.paplyGreenBright))
        }
        .buttonStyle(.plain)
    }
}

/// „Verwerfen“ – sekundär (dezent), aber gut treffbar. Ein LiveActivityIntent, läuft im App-Prozess.
private struct DiscardButton: View {
    let thoughtID: String
    let fullWidth: Bool

    var body: some View {
        Button(intent: DiscardThoughtIntent(thoughtID: thoughtID)) {
            Label("Verwerfen", systemImage: "trash")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(Color.paplyText.opacity(0.85))
                .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Gedanken verwerfen")
    }
}

private struct ThoughtLockScreenView: View {
    let state: ThoughtActivityAttributes.ContentState
    let thoughtID: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                switch state.phase {
                case .recording, .processing, .waiting:
                    ThoughtMark(size: 44)
                default:
                    ThoughtLeading(state: state, size: 30).frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gedanke").font(.headline).foregroundStyle(Color.paplyText)
                    ThoughtStatusText(state: state)
                        .font(.subheadline)
                        .foregroundStyle(Color.paplyText.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if state.phase == .recording {
                    Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.title.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.paplyGreenBright)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
            }
            if state.phase == .recording {
                HStack(spacing: 10) {
                    DiscardButton(thoughtID: thoughtID, fullWidth: false)
                    FinishButton(thoughtID: thoughtID, fullWidth: true)
                }
            }
        }
        .padding(16)
    }
}
