import SwiftUI

struct ConversationRecordingView: View {
    let elapsed: Double
    let paused: Bool
    let showGuidance: Bool
    let level: () -> Float
    var onPause: () -> Void = {}
    let onFinish: () -> Void
    let onDiscard: () -> Void
    let onMinimize: () -> Void
    @State private var confirmDiscard = false
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Verwerfen", role: .destructive) {
                    if elapsed >= 5 { confirmDiscard = true } else { onDiscard() }
                }.frame(minHeight: 44)
                Spacer()
                Button("Verkleinern", systemImage: "chevron.down", action: onMinimize)
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 24)
            ScrollView {
                VStack(spacing: 26) {
                    if paused { Text("Pausiert").padding(12).paplyGlass(.bar) }
                    EchoOrb(size: 200, mode: paused ? .starting : .listening,
                            primary: ConversationTint.blue, secondary: ConversationTint.turquoise,
                            auraColors: [ConversationTint.blue, ConversationTint.turquoise], level: level)
                        .padding(.vertical, 44)
                    Text(ConversationTint.clock(elapsed))
                        .font(.system(size: min(clockSize, 96), weight: .light, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityLabel("Aufnahmedauer \(ConversationTint.clock(elapsed))")
                    Text("Gespräch").font(.title3)
                    if showGuidance {
                        Text("Leg das iPhone in die Mitte, damit alle gut zu hören sind.")
                            .font(.subheadline).foregroundStyle(Color.paplySecondaryText).multilineTextAlignment(.center)
                    }
                }.padding(24).frame(maxWidth: .infinity)
            }
            Button(paused ? "Weiter" : "Pause", action: onPause).buttonStyle(.bordered).frame(minHeight: 44)
            Button(action: onFinish) {
                Label("Fertig", systemImage: "checkmark").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Color.paplyForestDeep).background(ConversationTint.fill, in: Capsule())
                    .paplyGlass(.prominent(ConversationTint.blue), interactive: true)
            }.buttonStyle(PressScaleStyle()).padding(24)
        }
        .foregroundStyle(Color.paplyText).background(PaplyBackground())
        .accessibilityAction(.magicTap, onFinish)
        .tint(ConversationTint.blue)
        .confirmationDialog("Aufnahme verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive, action: onDiscard)
            Button("Weiter aufnehmen", role: .cancel) {}
        }
        .gesture(DragGesture().onEnded { if $0.translation.height > 100 { onMinimize() } })
    }
}

struct ConversationRecordingBar: View {
    let elapsed: Double
    let paused: Bool
    let level: () -> Float
    let onOpen: () -> Void
    var onPause: () -> Void = {}
    let onFinish: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack {
                    EchoOrb(size: 28, mode: paused ? .starting : .listening, showsAura: false,
                            primary: ConversationTint.blue, secondary: ConversationTint.turquoise, level: level)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(paused ? "Pausiert" : "Gespräch").font(.subheadline.weight(.semibold))
                        Text(ConversationTint.clock(elapsed)).font(.caption).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Gespräch öffnen, \(ConversationTint.clock(elapsed))")
            Button(paused ? "Weiter" : "Pause", action: onPause).frame(minWidth: 44, minHeight: 44)
            Button("Fertig", action: onFinish).font(.subheadline.weight(.semibold))
                .frame(minWidth: 64, minHeight: 44)
                .foregroundStyle(Color.paplyForestDeep).background(ConversationTint.fill, in: Capsule())
        }
        .foregroundStyle(Color.paplyText).padding(10).paplyGlass(.bar, interactive: true)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }
}

#Preview("Aufnahme") {
    ConversationRecordingView(elapsed: 1421, paused: false, showGuidance: true, level: { 0.3 }, onFinish: {}, onDiscard: {}, onMinimize: {})
        .preferredColorScheme(.dark)
}
#Preview("Aufnahmeleiste") {
    ConversationRecordingBar(elapsed: 1421, paused: true, level: { 0 }, onOpen: {}, onFinish: {})
        .background(PaplyBackground()).preferredColorScheme(.dark)
}
