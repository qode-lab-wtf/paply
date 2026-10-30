import SwiftUI

/// Kurzes Aufblitzen nach Start aus der Tastatur: Mikro ist an, zurück zur vorherigen App.
/// Keine Bedienung nötig – der Hinweis zeigt nur, wie man zurückkommt.
struct FlashView: View {
    let flash: SessionController.Flash
    let dismiss: () -> Void
    let openSettings: () -> Void

    @State private var pulse = false

    var body: some View {
        ZStack {
            PaplyBackground()
            VStack(spacing: 0) {
                Spacer()
                orb
                    .padding(.bottom, 36)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color.paplyText)
                    Text(subtitle)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.paplyText.opacity(0.65))
                        .padding(.horizontal, 32)
                }
                Spacer()
                bottom
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .onAppear { pulse = true }
    }

    private var orb: some View {
        ZStack {
            Circle()
                .stroke(Color.paplyGreenBright.opacity(0.5), lineWidth: 1.5)
                .frame(width: 184, height: 184)
                .scaleEffect(pulse ? 1.45 : 1)
                .opacity(pulse ? 0 : 0.8)
                .animation(isRunning ? .easeOut(duration: 1.6).repeatForever(autoreverses: false) : .default, value: pulse)
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                    center: UnitPoint(x: 0.5, y: 0.28),
                    startRadius: 0,
                    endRadius: 120
                ))
                .background(Circle().fill(Color.paplyForest))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .frame(width: 184, height: 184)
                .shadow(color: .black.opacity(0.6), radius: 30, y: 20)
            PaplyMark().frame(width: 86, height: 92)
        }
    }

    @ViewBuilder
    private var bottom: some View {
        switch flash {
        case .starting:
            ProgressView().tint(Color.paplyGreenBright)
        case .running(let dictating):
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.paplyBeak)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zurück zur vorherigen App").font(.headline)
                        Text(dictating
                             ? "Oben links auf „◀︎“ tippen oder unten am Rand nach rechts wischen. Sprich ruhig schon – Paply hört zu."
                             : "Oben links auf „◀︎“ tippen oder unten am Rand nach rechts wischen.")
                            .font(.subheadline)
                            .foregroundStyle(Color.paplyText.opacity(0.68))
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .paplyCard()
                Button("Hier bleiben", action: dismiss)
                    .font(.subheadline)
                    .foregroundStyle(Color.paplyText.opacity(0.6))
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.paplyText)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .paplyCard()
                HStack {
                    Button("Einstellungen", action: openSettings)
                    Spacer()
                    Button("OK", action: dismiss).fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private var isRunning: Bool {
        if case .running = flash { return true }
        return false
    }

    private var title: String {
        switch flash {
        case .starting: "Mikro startet …"
        case .running: "Mikro ist an"
        case .failed: "Das hat nicht geklappt"
        }
    }

    private var subtitle: String {
        switch flash {
        case .starting: "Einen Moment."
        case .running: "Sitzung läuft – zurück zur vorherigen App."
        case .failed: "Paply konnte das Mikro nicht einschalten."
        }
    }
}
