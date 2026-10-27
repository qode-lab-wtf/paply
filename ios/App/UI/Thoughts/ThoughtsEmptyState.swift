import SwiftUI
import UIKit

// Leerer Zustand = Onboarding (KONZEPT §3.1) und die Anleitung zum Gedanken-Knopf (§3.9).

struct ThoughtsEmptyState: View {
    let setup: () -> Void
    let tryIt: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    LockScreenIllustration()
                        .frame(height: 248)
                        .padding(.bottom, 30)
                    Text("Deine Gedanken")
                        .font(.title.weight(.bold))
                        .foregroundStyle(Color.paplyText)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Drück den Paply-Knopf auf dem Sperrbildschirm und sprich – wie in ein Diktiergerät. Paply räumt auf, findet das Thema und merkt sich Aufgaben.")
                        .font(.body)
                        .foregroundStyle(Color.paplySecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    VStack(spacing: 6) {
                        Button(action: setup) {
                            Text("Knopf einrichten")
                                .font(.headline)
                                .foregroundStyle(Color.paplyForest)
                                .frame(maxWidth: 300)
                                .frame(minHeight: 52)
                                .background(Capsule().fill(Color.paplyGreenBright))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.97))
                        Button(action: tryIt) {
                            Text("Hier ausprobieren")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.paplyGreenBright)
                                .frame(minHeight: 44)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 28)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Sperrbildschirm unten links mit Paply-Knopf statt Taschenlampe (nur SwiftUI-Formen, kein Bild).
struct LockScreenIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var press = false

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = height * 0.6
            ZStack {
                // Gerät
                RoundedRectangle(cornerRadius: width * 0.2, style: .continuous)
                    .fill(LinearGradient(colors: [Color(uiColor: UIColor(hex: 0x23503A)), Color(uiColor: UIColor(hex: 0x0B1F16))],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: width * 0.2, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 14)
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.black)
                        .frame(width: width * 0.3, height: width * 0.085)
                        .padding(.top, width * 0.06)
                    Text("Dienstag, 27. Oktober")
                        .font(.system(size: width * 0.055, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.top, width * 0.1)
                    Text("9:41")
                        .font(.system(size: width * 0.27, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .monospacedDigit()
                    Spacer()
                    HStack {
                        paplyButton(width)
                        Spacer()
                        cornerButton(width, symbol: "camera.fill")
                    }
                    .padding(.horizontal, width * 0.11)
                    Capsule()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: width * 0.36, height: 3)
                        .padding(.top, width * 0.08)
                        .padding(.bottom, width * 0.05)
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sperrbildschirm mit Paply-Knopf unten links statt der Taschenlampe")
        .onAppear { press = true }
    }

    private func paplyButton(_ width: CGFloat) -> some View {
        let size = width * 0.24
        return ZStack {
            Circle()
                .fill(AngularGradient(colors: ThoughtTint.aura, center: .center))
                .frame(width: size * 1.5, height: size * 1.5)
                .blur(radius: size * 0.28)
                .opacity(press && !reduce ? 0.75 : 0.45)
            Circle()
                .fill(Color.black.opacity(0.45))
                .overlay(Circle().strokeBorder(AngularGradient(colors: ThoughtTint.aura, center: .center), lineWidth: 2))
                .frame(width: size, height: size)
            PaplyMark(monochrome: .white)
                .frame(width: size * 0.42, height: size * 0.46)
        }
        .frame(width: size, height: size)
        .scaleEffect(press && !reduce ? 0.94 : 1)
        .animation(reduce ? nil : .easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: press)
    }

    private func cornerButton(_ width: CGFloat, symbol: String) -> some View {
        let size = width * 0.24
        return Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.black.opacity(0.45)))
    }
}

// MARK: - Anleitung Gedanken-Knopf (§3.9)

struct ThoughtButtonGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LockScreenIllustration()
                    .frame(height: 210)
                    .padding(.vertical, 8)
                Text("Ein Druck nimmt einen Gedanken auf, nochmal drücken beendet. Paply ordnet ihn danach in der App – auch wenn das iPhone gesperrt ist.")
                    .font(.subheadline)
                    .foregroundStyle(Color.paplyText.opacity(0.75))
                    .padding(.horizontal, 4)

                GuideCard(title: "Sperrbildschirm", symbol: "lock.fill", steps: [
                    "Sperrbildschirm lange drücken → Anpassen → Sperrbildschirm.",
                    "Bei der Taschenlampe auf „–“ tippen, dann „+“.",
                    "„Paply-Gedanke“ wählen.",
                ], buttons: [], tint: AnyShapeStyle(ThoughtTint.fill))

                GuideCard(title: "Kontrollzentrum", symbol: "switch.2", steps: [
                    "Kontrollzentrum öffnen → oben links „+“ → „Steuerelement hinzufügen“.",
                    "„Paply-Gedanke“ suchen und antippen.",
                ], buttons: [], tint: AnyShapeStyle(ThoughtTint.fill))

                if DeviceInfo.hasActionButton {
                    GuideCard(title: "Aktionstaste", symbol: "button.programmable", steps: [
                        "Einstellungen → Aktionstaste → Steuerelement.",
                        "„Paply-Gedanke“ wählen.",
                    ], buttons: [
                        ("Einstellungen öffnen", URL(string: UIApplication.openSettingsURLString)),
                    ], tint: AnyShapeStyle(ThoughtTint.fill))
                }

                GuideCard(title: "Siri", symbol: "waveform", steps: [
                    "„Hey Siri, Gedanke mit Paply“.",
                    "Beenden: nochmal sagen oder „Fertig“ tippen.",
                ], buttons: [], tint: AnyShapeStyle(ThoughtTint.fill))

                Text("Diktat in die Zwischenablage gibt es weiter als Steuerelement „Paply-Diktat“.")
                    .font(.footnote)
                    .foregroundStyle(Color.paplyTertiaryText)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(PaplyBackground())
        .navigationTitle("Gedanken-Knopf")
        .navigationBarTitleDisplayMode(.inline)
    }
}
