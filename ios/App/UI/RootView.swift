import SwiftUI
import UIKit

enum Route: Hashable {
    case settings
    case vocabulary
    case spokenLanguages
    case shortcuts
    case keyboardSetup
    case developer
    case testVariants
    case testPage
    case diagnostics
    case storageCheck
    case entry(String)
}

/// Die App ist nur Einstellungen + Verlauf (kein Aufnahme-Bildschirm).
struct RootView: View {
    @State private var path = NavigationPath()
    @State private var toast: String?
    private let session = SessionController.shared

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(showToast: show)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .settings: SettingsView()
                    case .vocabulary: VocabularyView()
                    case .spokenLanguages: SpokenLanguagesView()
                    case .shortcuts: ShortcutsGuideView()
                    case .keyboardSetup: KeyboardSetupView()
                    case .developer: DeveloperView()
                    case .testVariants: TestVariantsView()
                    case .testPage: TestPageView()
                    case .diagnostics: DiagnosticsView()
                    case .storageCheck: StorageCheckView()
                    case .entry(let id): HistoryDetailView(id: id, showToast: show)
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(text: toast)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let flash = session.flash {
                FlashView(flash: flash) {
                    withAnimation(.paplySmooth) { session.flash = nil }
                } openSettings: {
                    session.flash = nil
                    path.append(Route.settings)
                }
                .transition(.opacity)
            }
        }
        .animation(.paplySmooth, value: session.flash)
        .preferredColorScheme(.dark)
    }

    private func show(_ text: String) {
        withAnimation(.paplyBouncy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.paplySmooth) { if toast == text { toast = nil } }
        }
    }
}

/// Startseite als ScrollView statt List: In einer List werden Zeilen mit mehreren
/// Knöpfen (bzw. die Sitzungskarte mit ihrem Knopf) als Ganzes antippbar oder schlucken
/// Berührungen in Teilen der Zeile. Hier hat jede Fläche genau ein klares Tippziel.
private struct HomeView: View {
    let showToast: (String) -> Void
    private let history = HistoryStore.shared
    private let settings = AppSettings.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                SessionCard()

                Text("Verlauf")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.paplyText)
                    .padding(.top, 14)
                    .padding(.leading, 4)

                if history.entries.isEmpty {
                    Text("Noch keine Diktate. Tippe in einem Textfeld auf 🌐 und wähle Paply – oder probier es auf der Testseite.")
                        .font(.subheadline)
                        .foregroundStyle(Color.paplyText.opacity(0.6))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .paplyCard(cornerRadius: 16)
                } else {
                    ForEach(history.entries) { entry in
                        HistoryRow(entry: entry) { copy(entry) }
                            .contextMenu {
                                Button("Kopieren", systemImage: "doc.on.doc") { copy(entry) }
                                Button("Löschen", systemImage: "trash", role: .destructive) {
                                    history.delete([entry.id])
                                }
                            }
                    }
                    Text("Antippen kopiert den Text. ⓘ zeigt Rohtext, Polieren und Zeiten. Lange drücken: löschen.")
                        .font(.footnote)
                        .foregroundStyle(Color.paplyText.opacity(0.45))
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(PaplyBackground())
        .onAppear { SetupStatus.shared.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { PaplyWordmark() }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Einstellungen")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func copy(_ entry: HistoryEntry) {
        let text = entry.text.isEmpty ? entry.raw : entry.text
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Kopiert")
    }
}

/// Karte: links (Text + Zeile darunter) kopiert, rechts eigener ⓘ-Knopf über die volle Höhe.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayText)
                        .font(.body)
                        .foregroundStyle(entry.errorMessage != nil && entry.text.isEmpty ? Color.paplyDanger : Color.paplyText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Image(systemName: entry.source == .keyboard ? "keyboard" : "hand.tap")
                        Text(Format.dayTime.string(from: entry.date))
                        if let total = entry.timings.totalMs {
                            Text("·")
                            Text(Format.seconds(total))
                        }
                        if entry.polishRejection != nil || entry.polishError != nil {
                            Text("·")
                            Text("Rohtext")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.paplyText.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.leading, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink(value: Route.entry(entry.id)) {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(Color.paplyText.opacity(0.5))
                    .frame(width: 48)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05))
        )
    }

    private var displayText: String {
        if !entry.text.isEmpty { return entry.text }
        if let error = entry.errorMessage { return error }
        return entry.raw.isEmpty ? "Nichts gehört" : entry.raw
    }
}

/// Ruhige Statuskarte: Paply bereit oder aus, EIN Knopf, und falls nötig der nächste Schritt.
/// Keine Technikwerte – die stehen im Entwicklerbereich.
private struct SessionCard: View {
    private let session = SessionController.shared
    private let settings = AppSettings.shared
    private let setup = SetupStatus.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(dotColor.opacity(0.18)).frame(width: 34, height: 34)
                    Circle().fill(dotColor).frame(width: 12, height: 12)
                        .shadow(color: dotColor.opacity(0.7), radius: isOn ? 6 : 0)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.paplyText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.paplyText.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: toggle) {
                Text(buttonTitle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(isOn ? Color.paplyText : Color.paplyForest)
                    .background(Capsule().fill(isOn ? Color.white.opacity(0.12) : Color.paplyGreenBright))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            if let step = nextStep {
                Divider().overlay(Color.white.opacity(0.12)).padding(.vertical, 14)
                NavigationLink(value: step.route) {
                    HStack(spacing: 12) {
                        Image(systemName: step.symbol)
                            .foregroundStyle(Color.paplyBeak)
                            .frame(width: 22)
                        Text(step.text)
                            .font(.subheadline)
                            .foregroundStyle(Color.paplyText)
                        Spacer(minLength: 8)
                        Text(step.action)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.paplyGreenBright)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.paplyText.opacity(0.35))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .paplyCard(cornerRadius: 22)
        .animation(.paplySmooth, value: session.status)
    }

    private var isOn: Bool { session.status == .ready || session.status == .recording }

    private var dotColor: Color {
        switch session.status {
        case .off: Color.white.opacity(0.35)
        case .ready, .recording: .paplyMicDot
        case .interrupted: .paplyDanger
        }
    }

    private var title: String {
        switch session.status {
        case .off: "Paply ist aus"
        case .ready, .recording: "Paply ist bereit"
        case .interrupted: "Mikro aus"
        }
    }

    private var subtitle: String {
        switch session.status {
        case .off:
            "Schalte das Mikro ein, dann hört Paply sofort zu, wenn du 🌐 tippst."
        case .ready, .recording:
            if let until = session.holdUntil {
                "Tippe in einem Textfeld auf 🌐 und sprich. Bereit bis \(Format.time.string(from: until))."
            } else {
                "Tippe in einem Textfeld auf 🌐 und sprich."
            }
        case .interrupted:
            "Zum Beispiel nach einem Anruf. Einmal neu starten, dann geht’s weiter."
        }
    }

    private var buttonTitle: String {
        switch session.status {
        case .off: "Mikro bereit halten"
        case .interrupted: "Neu starten"
        case .ready, .recording: "Ausschalten"
        }
    }

    private struct Step {
        let symbol: String
        let text: String
        let action: String
        let route: Route
    }

    private var nextStep: Step? {
        if !settings.hasAPIKey {
            return Step(symbol: "key.fill", text: "Groq-Schlüssel fehlt", action: "Eintragen", route: .settings)
        }
        if !setup.keyboardEnabled {
            return Step(symbol: "keyboard", text: "Tastatur noch nicht eingerichtet", action: "Einrichten", route: .keyboardSetup)
        }
        if !setup.fullAccessSeen {
            return Step(symbol: "lock.open", text: "Vollzugriff für die Tastatur fehlt", action: "Anleitung", route: .keyboardSetup)
        }
        return nil
    }

    private func toggle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch session.status {
        case .off:
            Task { await session.startSession(trigger: "app-button") }
        case .interrupted:
            session.stopSession(reason: "restart")
            Task { await session.startSession(trigger: "app-restart") }
        case .ready, .recording:
            session.stopSession(reason: "app-button")
        }
    }
}
