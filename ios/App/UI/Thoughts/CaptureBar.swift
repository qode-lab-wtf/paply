import PaplyKit
import SwiftUI

// Aufnahme-Leiste (KONZEPT §3.4): über der Tab-Leiste in beiden Tabs.
// iOS 26.1+: `tabViewBottomAccessory` (Platz für „läuft gerade“ wie der Mini-Player in Musik).
// iOS 18 (und 26.0): schwebende Kapsel per `safeAreaInset(edge: .bottom)` je Tab.

enum CaptureBarPlacement {
    /// Die Leiste sitzt im System-Zubehör der Tab-Leiste
    static var usesAccessory: Bool {
        #if compiler(>=6.2.1)
        if #available(iOS 26.1, *) { return PaplyStyle.usesGlass }
        #endif
        return false
    }
}

/// iOS 26.1+: Leiste als Zubehör der Tab-Leiste
struct CaptureAccessoryModifier: ViewModifier {
    let flow: CaptureFlow

    func body(content: Content) -> some View {
        #if compiler(>=6.2.1)
        if #available(iOS 26.1, *) {
            if CaptureBarPlacement.usesAccessory {
                content.tabViewBottomAccessory(isEnabled: flow.bar != .hidden) {
                    AccessoryCaptureBar(flow: flow)
                }
            } else {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

@available(iOS 26.0, *)
private struct AccessoryCaptureBar: View {
    let flow: CaptureFlow
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        CaptureBarContent(flow: flow, compact: placement == .inline)
            .padding(.horizontal, 14)
    }
}

/// iOS 18: schwebende Kapsel über der Tab-Leiste
struct CaptureInsetBarModifier: ViewModifier {
    @Environment(CaptureFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if !CaptureBarPlacement.usesAccessory, flow.bar != .hidden {
                CaptureBarContent(flow: flow, compact: false)
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .paplyGlass(.bar, interactive: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(reduce ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PaplyMotion.bouncy(reduce), value: flow.bar == .hidden)
    }
}

/// Inhalt der Leiste je Zustand
struct CaptureBarContent: View {
    let flow: CaptureFlow
    var compact: Bool
    @Environment(ThoughtsNav.self) private var nav
    @Environment(ThoughtsModel.self) private var model
    @Environment(\.captureZoom) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .captureZoomSource(CaptureFlow.barSource, in: zoom)
            .shake(flow.nothingPulse)
            .sensoryFeedback(.warning, trigger: flow.nothingPulse)
            .sensoryFeedback(.stop, trigger: flow.barStopPulse)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
    }

    @ViewBuilder
    private var content: some View {
        switch flow.bar {
        case .recording:
            recording
        case .ordering:
            line(icon: AnyView(markIcon), text: "Wird geordnet …", shimmer: true)
        case .saved(let id):
            savedLine(id)
        case .waiting(_, let symbol, let text):
            line(icon: AnyView(symbolIcon(symbol, tint: .paplySecondaryText)), text: text)
        case .nothing:
            line(icon: AnyView(symbolIcon("exclamationmark.circle.fill", tint: .paplyBeak)), text: "Nichts verstanden – nichts gespeichert")
        case .note(let text):
            line(icon: AnyView(markIcon), text: text)
        case .hidden:
            EmptyView()
        }
    }

    private var recording: some View {
        HStack(spacing: 12) {
            EchoOrb(size: compact ? 22 : 30, mode: flow.driver.active?.speechDetected == true ? .heard : .listening,
                    showsAura: false, level: { flow.driver.level })
            if let active = flow.driver.active {
                TimelineView(.periodic(from: active.startedAt, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(active.startedAt)
                    HStack(spacing: 6) {
                        if !compact {
                            Text("Gedanke")
                                .foregroundStyle(Color.paplyText)
                            Text("·").foregroundStyle(Color.paplyTertiaryText)
                        }
                        Text(ThoughtDate.clock(elapsed))
                            .monospacedDigit()
                            .foregroundStyle(compact ? Color.paplyText : Color.paplySecondaryText)
                            .contentTransition(.numericText())
                            .animation(PaplyMotion.smooth(reduce), value: Int(elapsed))
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Gedanke, Aufnahme läuft, \(ThoughtDate.spokenClock(elapsed))")
                }
            }
            Spacer(minLength: 6)
            Button(action: flow.finishFromBar) {
                Text("Fertig")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.paplyForest)
                    .padding(.horizontal, compact ? 12 : 16)
                    .padding(.vertical, compact ? 5 : 8)
                    .background(Capsule().fill(Color.paplyGreenBright))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Fertig, Gedanke beenden")
        }
    }

    private func savedLine(_ id: String) -> some View {
        let topic = model.thoughts.first { $0.id == id }.flatMap { model.topic($0.topicId) }
        return HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: compact ? 18 : 22, weight: .semibold))
                .foregroundStyle(Color.paplyGreenBright)
                .symbolEffect(.bounce, value: flow.bar)
            HStack(spacing: 6) {
                Text("Gespeichert")
                    .foregroundStyle(Color.paplyText)
                if let topic {
                    Text("·").foregroundStyle(Color.paplyTertiaryText)
                    Label(topic.title, systemImage: topic.icon.systemImage)
                        .labelStyle(TopicLabelStyle())
                        .foregroundStyle(ThoughtTint.mint)
                        .lineLimit(1)
                }
            }
            .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
    }

    private func line(icon: AnyView, text: String, shimmer: Bool = false) -> some View {
        HStack(spacing: 10) {
            icon
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.paplyText)
                .lineLimit(1)
                .shimmer(shimmer)
            Spacer(minLength: 0)
        }
    }

    private var markIcon: some View {
        PaplyMark()
            .frame(width: compact ? 16 : 20, height: compact ? 17 : 22)
            .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)
    }

    private func symbolIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: compact ? 15 : 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)
    }

    private func open() {
        switch flow.bar {
        case .recording:
            flow.openBig(source: CaptureFlow.barSource)
        case .ordering(let id), .saved(let id), .waiting(let id, _, _):
            nav.open(id)
        case .nothing, .note, .hidden:
            break
        }
    }
}

/// Symbol + Name eng beieinander (Themen-Etikett)
struct TopicLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
