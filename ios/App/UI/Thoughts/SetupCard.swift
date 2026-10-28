import AVFAudio
import PaplyKit
import SwiftUI
import UIKit

// Einrichtung an einer Stelle: eine ruhige Karte oben in beiden Tabs mit vier Häkchen. Erledigte
// Schritte erkennt die App selbst; sind alle erledigt, verschwindet die Karte. Ist die Beta „Gedanken & Aufgaben“
// aus, entfällt der Schritt „Gedanken-Knopf“ (drei Häkchen).

@MainActor
@Observable
final class SetupGuide {
    static let shared = SetupGuide()
    /// Der Nutzer hat in der Anleitung „Ist eingerichtet“ getippt
    static let buttonConfirmedKey = "paply.setup.thoughtButtonDone"

    enum Step: Int, CaseIterable, Identifiable {
        case mic, key, keyboard, button
        var id: Int { rawValue }
    }

    private(set) var mic: AVAudioApplication.recordPermission = AVAudioApplication.shared.recordPermission
    private(set) var buttonConfirmed = UserDefaults.standard.bool(forKey: SetupGuide.buttonConfirmedKey)

    private init() {}

    /// Beim Erscheinen und wenn die App nach vorne kommt
    func refresh() {
        mic = AVAudioApplication.shared.recordPermission
        SetupStatus.shared.refresh()
    }

    func confirmButton() {
        buttonConfirmed = true
        UserDefaults.standard.set(true, forKey: Self.buttonConfirmedKey)
    }

    func requestMic() {
        switch mic {
        case .undetermined:
            Task {
                _ = await AVAudioApplication.requestRecordPermission()
                mic = AVAudioApplication.shared.recordPermission
            }
        default:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
    }

    func isDone(_ step: Step, model: ThoughtsModel) -> Bool {
        switch step {
        case .mic: mic == .granted
        case .key: AppSettings.shared.hasAPIKey
        case .keyboard: !SetupStatus.shared.needsKeyboardSetup
        case .button:
            // eingerichtet, sobald ein Gedanke über Knopf, Kurzbefehl oder Live Activity kam – oder bestätigt
            buttonConfirmed || model.thoughts.contains { $0.trigger == .control || $0.trigger == .shortcut || $0.trigger == .liveActivity }
        }
    }

    /// Schritte, die gerade zählen: ohne Beta „Gedanken & Aufgaben“ kein Gedanken-Knopf
    var steps: [Step] {
        AppSettings.shared.betaThoughts ? Step.allCases : Step.allCases.filter { $0 != .button }
    }

    func doneCount(model: ThoughtsModel) -> Int {
        steps.reduce(0) { $0 + (isDone($1, model: model) ? 1 : 0) }
    }

    func isVisible(model: ThoughtsModel) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PaplyNoSetup") { return false }
        #endif
        return doneCount(model: model) < steps.count
    }
}

struct SetupCard: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var sheet: SetupSheet?
    private let guide = SetupGuide.shared

    private enum SetupSheet: String, Identifiable {
        case keyboard, button
        var id: String { rawValue }
    }

    var body: some View {
        let steps = guide.steps
        let done = guide.doneCount(model: model)
        let next = steps.first { !guide.isDone($0, model: model) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Einrichten")
                    .font(.paplyTitle(.title3))
                    .foregroundStyle(Color.paplyText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(done) von \(steps.count)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.paplySecondaryText)
                    .contentTransition(.numericText())
            }
            .padding(.bottom, 6)

            ForEach(steps) { step in
                row(step, isDone: guide.isDone(step, model: model), isNext: step == next)
                if step != steps.last {
                    Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 36)
                }
            }

            // Datenschutz in drei Sätzen, nicht als Fußnote versteckt
            HStack(alignment: .top, spacing: 10) {
                LucideImage(.shieldCheck, size: 16, stroke: 1.9, relativeTo: .footnote)
                    .foregroundStyle(ThoughtTint.mint)
                    .padding(.top, 1)
                Text("Dein Ton geht zur Erkennung an Groq, mit deinem Schlüssel – Paply behält davon nur den Text. \(AppSettings.shared.betaThoughts ? "Gedanken und Verlauf liegen" : "Der Verlauf liegt") nur auf diesem iPhone. Im Bereitschaftsmodus wird nichts gespeichert oder gesendet.")
                    .font(.footnote)
                    .foregroundStyle(Color.paplySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .paplyCard(cornerRadius: 20)
        .animation(PaplyMotion.smooth(reduce), value: done)
        .onAppear { guide.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { guide.refresh() }
        }
        .sheet(item: $sheet) { which in
            NavigationStack {
                Group {
                    switch which {
                    case .keyboard: KeyboardSetupView()
                    case .button: ThoughtButtonGuideView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { sheet = nil }.fontWeight(.semibold)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .tint(.paplyGreenBright)
        }
    }

    @ViewBuilder
    private func row(_ step: SetupGuide.Step, isDone: Bool, isNext: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? Color.clear : Color.paplyText.opacity(0.3), lineWidth: 1.5)
                    .background(Circle().fill(isDone ? Color.paplyGreenBright : Color.clear))
                if isDone {
                    LucideImage(.check, size: 14, stroke: 3, scales: false)
                        .foregroundStyle(Color.paplyForest)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(step))
                    .font(.body.weight(isNext ? .semibold : .regular))
                    .foregroundStyle(isDone ? Color.paplySecondaryText : Color.paplyText)
                if isNext, !isDone {
                    Text(detail(step))
                        .font(.footnote)
                        .foregroundStyle(Color.paplySecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if step == .key, !isDone {
                    Link(destination: SettingsView.groqKeysURL) {
                        HStack(spacing: 3) {
                            Text("Kostenlosen Schlüssel holen")
                            Image(systemName: "arrow.up.right").imageScale(.small)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.paplyGreenBright)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if !isDone { actions(step, prominent: isNext) }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title(step)), \(isDone ? "erledigt" : "offen")")
    }

    private func title(_ step: SetupGuide.Step) -> String {
        switch step {
        case .mic: "Mikro erlauben"
        case .key: "Groq-Schlüssel"
        case .keyboard: "Tastatur mit Vollzugriff"
        case .button: "Gedanken-Knopf"
        }
    }

    private func detail(_ step: SetupGuide.Step) -> String {
        switch step {
        case .mic:
            guide.mic == .denied ? "Ist aus. In den iPhone-Einstellungen bei Paply einschalten."
                : AppSettings.shared.betaThoughts ? "Für Diktat und Gedanken." : "Fürs Diktat."
        case .key:
            "Kostenlos bei Groq, in einer Minute erledigt."
        case .keyboard:
            "Vollzugriff braucht die Tastatur nur, um mit der App zu sprechen. Danach Paply in der Tastaturliste direkt hinter deine Haupttastatur ziehen."
        case .button:
            "Als Widget unter die Uhr auf den Sperrbildschirm – ein Tipp, und du sprichst."
        }
    }

    @ViewBuilder
    private func actions(_ step: SetupGuide.Step, prominent: Bool) -> some View {
        switch step {
        case .mic:
            pill(guide.mic == .denied ? "Öffnen" : "Erlauben", prominent: prominent) { guide.requestMic() }
        case .key:
            pill("Eintragen", prominent: prominent) { nav.showSettings = true }
        case .keyboard:
            pill("Einrichten", prominent: prominent) { sheet = .keyboard }
        case .button:
            pill("Anleitung", prominent: prominent) { sheet = .button }
        }
    }

    private func pill(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Color.paplyForest : Color.paplyText)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule().fill(prominent ? Color.paplyGreenBright : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .fixedSize()
    }
}
