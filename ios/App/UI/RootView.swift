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

private struct HomeView: View {
    let showToast: (String) -> Void
    private let session = SessionController.shared
    private let history = HistoryStore.shared
    private let settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                SessionCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                if !settings.hasAPIKey {
                    NavigationLink(value: Route.settings) {
                        Label("Groq-Schlüssel eintragen", systemImage: "key.fill")
                            .foregroundStyle(Color.paplyBeak)
                    }
                    .listRowBackground(Color.white.opacity(0.07))
                }
            }

            Section {
                if history.entries.isEmpty {
                    Text("Noch keine Diktate. Tippe in einem Textfeld auf 🌐 und wähle Paply – oder probier es auf der Testseite.")
                        .font(.subheadline)
                        .foregroundStyle(Color.paplyText.opacity(0.6))
                        .listRowBackground(Color.white.opacity(0.05))
                }
                ForEach(history.entries) { entry in
                    HistoryRow(entry: entry) {
                        copy(entry)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .onDelete { offsets in
                    history.delete(Set(offsets.map { history.entries[$0].id }))
                }
            } header: {
                Text("Verlauf")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.paplyText)
                    .textCase(nil)
                    .padding(.leading, -16)
            } footer: {
                if !history.entries.isEmpty {
                    Text("Antippen kopiert den Text. ⓘ zeigt Rohtext, Polieren und Zeiten.")
                }
            }
        }
        .paplyList()
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

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayText)
                        .font(.body)
                        .foregroundStyle(entry.errorMessage != nil && entry.text.isEmpty ? Color.paplyDanger : Color.paplyText)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink(value: Route.entry(entry.id)) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.paplyText.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details")
        }
        .padding(.vertical, 4)
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
