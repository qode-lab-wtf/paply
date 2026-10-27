import PaplyKit
import SwiftUI

// Kopf der Startseite über der Karte (Entwurf „Landkarte“): nur die Einrichtung, sonst nichts – die Karte bekommt
// den Platz. Die Aufgaben haben einen eigenen Reiter (TasksTab.swift), die frühere Leiste „Offen“ ist weg; laufende
// und wartende Gedanken zeigt die Karte als Kugel „Eingang“ (statt der früheren Pille). Der Überblick („320 Gedanken
// · 8 Themen“) steht als Untertitel (iOS 26) bzw. in der unteren Leiste (iOS 18).

/// „40 Gedanken · 8 Themen“
enum ThoughtsSummary {
    @MainActor
    static func text(_ model: ThoughtsModel) -> String {
        let thoughts = model.thoughts.count
        let topics = model.topics.reduce(0) { $0 + (model.count(of: $1.id) > 0 ? 1 : 0) }
        let t = thoughts == 1 ? "1 Gedanke" : "\(thoughts) Gedanken"
        guard topics > 0 else { return t }
        return t + " · " + (topics == 1 ? "1 Thema" : "\(topics) Themen")
    }
}

/// Kopf über der Karte: nur die Einrichtung. Ist sie erledigt, gibt es keinen Kopf – die Karte reicht bis oben.
/// Laufende und wartende Gedanken zeigt die Karte selbst (Kugel „Eingang“, Map/MapScene.swift).
struct ThoughtsHomeHeader: View {
    /// Gibt es etwas zu zeigen?
    @MainActor
    static func isVisible(_ model: ThoughtsModel) -> Bool {
        SetupGuide.shared.isVisible(model: model)
    }

    var body: some View {
        SetupBanner()
    }
}

// MARK: - Einrichten (kompakt)

/// Über der Karte ist kein Platz für die große Einrichtungskarte: ein Band mit Fortschritt, das sie als
/// Blatt öffnet. Sind alle Schritte erledigt, verschwindet es (wie die Karte).
struct SetupBanner: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.scenePhase) private var scenePhase
    @State private var open = false
    private let guide = SetupGuide.shared

    var body: some View {
        let done = guide.doneCount(model: model)
        let total = SetupGuide.Step.allCases.count
        Button {
            open = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.14), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(done) / CGFloat(total))
                        .stroke(Color.paplyGreenBright, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Einrichten")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paplyText)
                    Text("\(done) von \(total) erledigt")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color.paplySecondaryText)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.paplyTertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ThoughtCardSurface(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel("Einrichten, \(done) von \(total) erledigt")
        .onAppear { guide.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { guide.refresh() }
        }
        .onChange(of: nav.showSettings) { _, show in
            // „Eintragen“ (Groq-Schlüssel) öffnet die Einstellungen – erst dieses Blatt schließen
            guard show, open else { return }
            nav.showSettings = false
            open = false
            Task {
                try? await Task.sleep(for: .seconds(0.5))
                nav.showSettings = true
            }
        }
        .sheet(isPresented: $open) {
            NavigationStack {
                ScrollView {
                    SetupCard()
                        .padding(16)
                }
                .background(PaplyBackground())
                .navigationTitle("Einrichten")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { open = false }.fontWeight(.semibold)
                    }
                }
            }
            .presentationDetents([.large])
            .preferredColorScheme(.dark)
            .tint(.paplyGreenBright)
        }
    }
}
