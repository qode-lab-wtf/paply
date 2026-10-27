import SwiftUI
import UIKit

enum Route: Hashable {
    case settings
    case vocabulary
    case spokenLanguages
    case testVariants
    case testPage
    case diagnostics
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
                    case .testVariants: TestVariantsView()
                    case .testPage: TestPageView()
                    case .diagnostics: DiagnosticsView()
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
                if !settings.hasAPIKey {
                    NavigationLink(value: Route.settings) {
                        HStack {
                            Label("Groq-Schlüssel eintragen", systemImage: "key.fill")
                                .foregroundStyle(Color.paplyBeak)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.paplyText.opacity(0.35))
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                        .paplyCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                }

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

/// Status der Sitzung mit Starten/Beenden.
private struct SessionCard: View {
    private let session = SessionController.shared
    private let settings = AppSettings.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 12) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: dotColor.opacity(0.6), radius: session.status == .off ? 0 : 5)
                    .padding(.leading, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color.paplyText)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.paplyText.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(buttonTitle) { toggle() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(session.status == .off || session.status == .interrupted ? .paplyGreen : Color.white.opacity(0.14))
                    .foregroundStyle(session.status == .off || session.status == .interrupted ? Color.paplyForest : Color.paplyText)
                    .clipShape(Capsule())
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 14))
            .paplyCard()
        }
    }

    private var dotColor: Color {
        switch session.status {
        case .off: Color.white.opacity(0.28)
        case .ready, .recording: .paplyMicDot
        case .interrupted: .paplyDanger
        }
    }

    private var title: String {
        switch session.status {
        case .off: "Mikro aus"
        case .ready: "Mikro bereit"
        case .recording: "Diktat läuft"
        case .interrupted: "Unterbrochen"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        switch session.status {
        case .off:
            parts.append(session.detail ?? "Startet, sobald du Paply in der Tastatur wählst.")
        case .interrupted:
            parts.append(session.detail ?? "Neu starten, damit Paply wieder zuhört.")
        case .ready, .recording:
            if let since = session.startedAt { parts.append("seit \(Format.time.string(from: since))") }
            if let until = session.holdUntil {
                parts.append("bis \(Format.time.string(from: until))")
            } else {
                parts.append(settings.holdDuration.label)
            }
            if let battery = session.monitor.batteryPercent { parts.append("Akku \(battery) %") }
            if session.idlePaused { parts.append("im Leerlauf angehalten (Experiment)") }
            if session.processingCount > 0 { parts.append("poliert …") }
        }
        return parts.joined(separator: " · ")
    }

    private var buttonTitle: String {
        switch session.status {
        case .off: "Starten"
        case .interrupted: "Neu starten"
        case .ready, .recording: "Beenden"
        }
    }

    private func toggle() {
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
