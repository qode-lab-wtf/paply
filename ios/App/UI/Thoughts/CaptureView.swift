import PaplyKit
import SwiftUI

// Große Aufnahme-Ansicht (KONZEPT §3.4): Vollbild, Zoom vom Aufnahme-Knopf. Kein Live-Text –
// die Zeit läuft, der Orb hört zu. „⌄“ oder nach unten wischen verkleinert (die Aufnahme läuft weiter).

struct CaptureView: View {
    /// Wie oft der Hinweis „Sprich einfach …“ schon kam (nur bei den ersten 3 Aufnahmen)
    static let hintKey = "paply.thoughts.captureHints"

    @Environment(CaptureFlow.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduce
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 64
    @State private var showHint = UserDefaults.standard.integer(forKey: CaptureView.hintKey) < 3
    @State private var confirmDiscard = false
    @State private var discarded = false
    @State private var discardPulse = 0
    @State private var errorPulse = 0

    private enum Phase: Equatable {
        case starting
        case recording(ThoughtCapture.Active)
        case done
        case stoppedElsewhere
        case error(String)
    }

    private var phase: Phase {
        if flow.finishing != nil { return .done }
        if let error = flow.startError { return .error(error) }
        if let active = flow.driver.active { return .recording(active) }
        if flow.stoppedElsewhere { return .stoppedElsewhere }
        return .starting
    }

    private var orbMode: EchoOrb.Mode {
        switch phase {
        case .starting: .starting
        case .recording(let active): active.speechDetected ? .heard : .listening
        case .done, .stoppedElsewhere: .done
        case .error: .error
        }
    }

    var body: some View {
        stage
            .preferredColorScheme(.dark)
            .accessibilityAction(.magicTap) { finish() }
            .modifier(haptics)
            .onChange(of: flow.startError) { _, error in
                if error != nil { errorPulse += 1 }
            }
            .confirmationDialog("Gedanken verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { discardNow() }
                Button("Weiter aufnehmen", role: .cancel) {}
            }
    }

    private var stage: some View {
        ZStack {
            PaplyBackground()
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                orb
                clock
                caption
                    .padding(.top, 6)
                hint
                    .padding(.top, 28)
                Spacer(minLength: 24)
                primaryButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
    }

    private var orb: some View {
        EchoOrb(size: 220, mode: orbMode, level: { flow.driver.level })
            .scaleEffect(discarded ? 0.8 : 1)
            .opacity(discarded ? 0 : 1)
            .padding(.bottom, 44)
            .shake(errorPulse)
    }

    /// Haptik nach §4
    private var haptics: CaptureHaptics {
        CaptureHaptics(activeID: activeID, speech: speechDetected, finishing: flow.finishing,
                       saved: flow.savedPulse, error: errorPulse, discard: discardPulse)
    }

    private var activeID: String? { flow.driver.active?.id }
    private var speechDetected: Bool { flow.driver.active?.speechDetected ?? false }

    // MARK: Teile

    private var topBar: some View {
        HStack {
            Button("Verwerfen") { askDiscard() }
                .font(.body)
                .foregroundStyle(Color.paplyText.opacity(0.85))
                .opacity(canDiscard ? 1 : 0)
                .disabled(!canDiscard)
                .animation(PaplyMotion.smooth(reduce), value: canDiscard)
                .padding(.vertical, 8)
            Spacer()
            Button {
                flow.closeBig()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.paplyText)
                    .frame(width: 44, height: 44)
                    .paplyGlass(.plain, interactive: true, in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(flow.driver.active != nil ? "Verkleinern, Aufnahme läuft weiter" : "Schließen")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var clock: some View {
        switch phase {
        case .recording(let active):
            TimelineView(.periodic(from: active.startedAt, by: 1)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(active.startedAt))
                VStack(spacing: 8) {
                    RollingClock(seconds: Int(elapsed), font: .system(size: min(clockSize, 96), weight: .light, design: .rounded))
                        .foregroundStyle(Color.paplyText)
                        .accessibilityLabel("Aufnahme läuft, \(ThoughtDate.spokenClock(elapsed))")
                    if elapsed >= ThoughtCapture.warnAfter {
                        Text("Noch \(max(1, Int((ThoughtCapture.limit - elapsed) / 60 + 0.999))) Min.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.paplyBeak)
                            .transition(.opacity)
                    }
                }
            }
        case .done, .stoppedElsewhere:
            Text("Wird geordnet …")
                .font(.system(size: min(clockSize, 96) * 0.42, weight: .medium, design: .rounded))
                .foregroundStyle(Color.paplyText)
                .frame(height: min(clockSize, 96) * 1.2)
                .transition(.opacity)
        case .starting:
            Text("0:00")
                .font(.system(size: min(clockSize, 96), weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.paplyText.opacity(0.35))
        case .error(let message):
            Text(message)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.paplyText)
                .padding(.horizontal, 32)
                .frame(minHeight: min(clockSize, 96) * 1.2)
        }
    }

    @ViewBuilder
    private var caption: some View {
        switch phase {
        case .stoppedElsewhere:
            Text(flow.stopNote)
                .font(.subheadline)
                .foregroundStyle(Color.paplySecondaryText)
        case .done:
            // „Wird geordnet …“ steht schon groß darüber
            Text(" ")
                .font(.subheadline)
                .accessibilityHidden(true)
        case .error:
            Text("Der Gedanke wurde nicht aufgenommen.")
                .font(.subheadline)
                .foregroundStyle(Color.paplySecondaryText)
        case .starting:
            Text("Mikro startet …")
                .font(.subheadline)
                .foregroundStyle(Color.paplySecondaryText)
        default:
            Text("Gedanke")
                .font(.subheadline)
                .foregroundStyle(Color.paplySecondaryText)
        }
    }

    @ViewBuilder
    private var hint: some View {
        if showHint, case .recording = phase {
            Text("Sprich einfach. Paply ordnet danach.")
                .font(.callout)
                .foregroundStyle(Color.paplyTertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch phase {
        case .error:
            Button {
                flow.closeBig()
            } label: {
                Text("Schließen")
                    .font(.headline)
                    .foregroundStyle(Color.paplyText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .padding(.vertical, 2)
                    .paplyGlass(.plain, interactive: true)
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .keyboardShortcut(.defaultAction)
        default:
            Button(action: finish) {
                Label("Fertig", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(Color.paplyForest)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.paplyGreenBright))
                    .contentShape(Capsule())
                    .opacity(canFinish ? 1 : (phase == .starting ? 0.45 : 0))
                    .animation(PaplyMotion.smooth(reduce), value: canFinish)
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .disabled(!canFinish)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Beendet die Aufnahme. Paply ordnet den Gedanken danach.")
        }
    }

    // MARK: Aktionen

    private var canFinish: Bool {
        if case .recording = phase { return true }
        return false
    }

    private var canDiscard: Bool { canFinish }

    private func finish() {
        guard canFinish else { return }
        flow.finishFromBig()
    }

    private func askDiscard() {
        guard let active = flow.driver.active else { return }
        if Date().timeIntervalSince(active.startedAt) >= 5 {
            confirmDiscard = true
        } else {
            discardNow()
        }
    }

    private func discardNow() {
        discardPulse += 1
        withAnimation(PaplyMotion.smooth(reduce)) { discarded = true }
        flow.discard()
        Task {
            try? await Task.sleep(for: .seconds(0.28))
            flow.closeBig()
        }
    }
}

private struct CaptureHaptics: ViewModifier {
    let activeID: String?
    let speech: Bool
    let finishing: String?
    let saved: Int
    let error: Int
    let discard: Int

    func body(content: Content) -> some View {
        let started: (String?, String?) -> Bool = { old, new in old == nil && new != nil }
        let heard: (Bool, Bool) -> Bool = { old, new in !old && new }
        let first = content
            .sensoryFeedback(SensoryFeedback.start, trigger: activeID, condition: started)
            .sensoryFeedback(SensoryFeedback.impact(weight: .light, intensity: 0.6), trigger: speech, condition: heard)
            .sensoryFeedback(SensoryFeedback.stop, trigger: finishing, condition: started)
        return first
            .sensoryFeedback(SensoryFeedback.success, trigger: saved)
            .sensoryFeedback(SensoryFeedback.warning, trigger: error)
            .sensoryFeedback(SensoryFeedback.impact(weight: .medium), trigger: discard)
    }
}
