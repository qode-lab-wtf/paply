import PaplyKit
import SwiftUI

// Oberfläche der Erinnerung zur Uhrzeit (TaskReminders):
// - Karte „Bei Uhrzeit erinnern?“ oben im Reiter „Aufgaben“ – nur wenn es eine offene Aufgabe mit Uhrzeit in der
//   Zukunft gibt und noch nie gefragt wurde; „Nicht jetzt“ blendet sie 7 Tage aus.
// - Einstellungen → Aufgaben: Schalter „Erinnerungen zur Uhrzeit“; bei verweigerter Erlaubnis der Weg in die
//   iOS-Einstellungen.
// - Entwicklerbereich → Erinnerungen: „Erinnerungen dringlich“, „Abhaken nur mit Face ID“.

/// Karte im Reiter „Aufgaben“ (als eigener Abschnitt der Liste)
struct TaskReminderPromptSection: View {
    let thoughts: [Thought]

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var requesting = false
    private let reminders = TaskReminders.shared

    var body: some View {
        if reminders.offersPrompt(thoughts: thoughts) {
            Section {
                card
                    .listRowBackground(Color.paplyRow)
                    .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 16))
            }
            .transition(.opacity)
        }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            LucideImage(.bell, size: 17, stroke: 2, relativeTo: .body)
                .foregroundStyle(ThoughtTint.mint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(ThoughtTint.mint.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Bei Uhrzeit erinnern?")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.paplyText)
                    .accessibilityAddTraits(.isHeader)
                Text("Hat eine Aufgabe eine Uhrzeit, meldet sich Paply genau dann – auch auf dem Sperrbildschirm. Abhaken geht direkt in der Mitteilung. Aufgaben ohne Uhrzeit bleiben still.")
                    .font(.subheadline)
                    .foregroundStyle(Color.paplySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    pill("Erinnern", prominent: true) {
                        guard !requesting else { return }
                        requesting = true
                        Task {
                            await reminders.requestAuthorization()
                            requesting = false
                        }
                    }
                    pill("Nicht jetzt", prominent: false) {
                        withAnimation(PaplyMotion.smooth(reduce)) { reminders.dismissPrompt() }
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func pill(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Color.paplyForest : Color.paplyText)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(prominent ? Color.paplyGreenBright : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .fixedSize()
    }
}

/// Einstellungen → Aufgaben
struct TaskReminderSettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    private let reminders = TaskReminders.shared

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { reminders.isOn }, set: { reminders.setEnabled($0) })) {
                HStack(spacing: 12) {
                    SettingsIcon(glyph: .bell)
                    Text("Erinnerungen zur Uhrzeit").foregroundStyle(Color.paplyText)
                }
            }
            .disabled(reminders.isDenied)
            if reminders.isDenied {
                Button {
                    reminders.openSystemSettings()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(glyph: .toggleRight)
                        Text("Mitteilungen erlauben").foregroundStyle(Color.paplyText)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.paplyText.opacity(0.45))
                    }
                }
                .accessibilityHint("Öffnet die Mitteilungen von Paply in den iOS-Einstellungen")
            }
        } header: {
            Text("Aufgaben")
        } footer: {
            if reminders.isDenied {
                Text("Mitteilungen für Paply sind in den iOS-Einstellungen aus. Schalte sie dort ein, dann meldet sich Paply zur Uhrzeit einer Aufgabe.")
            } else {
                Text("Hat eine Aufgabe eine Uhrzeit – etwa „morgen um 8“ –, meldet sich Paply genau dann. In der Mitteilung kannst du sie abhaken oder eine Stunde später erinnern lassen. Aufgaben nur mit Tag bleiben still.")
            }
        }
        .listRowBackground(Color.white.opacity(0.07))
        .task { await reminders.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reminders.refreshAuthorization() } }
        }
    }
}

/// Entwicklerbereich → Erinnerungen
struct TaskReminderDeveloperSection: View {
    private let reminders = TaskReminders.shared

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { reminders.urgent }, set: { reminders.setUrgent($0) })) {
                labeled("Erinnerungen dringlich",
                        "Als „Zeitkritisch“: bricht durch den Fokus. Schon geplante werden neu geplant.")
            }
            Toggle(isOn: Binding(get: { reminders.requireAuth }, set: { reminders.setRequireAuth($0) })) {
                labeled("Abhaken nur mit Face ID",
                        "„Erledigt“ in Mitteilung und Widget erst nach dem Entsperren. Aus: auch am gesperrten iPhone.")
            }
            LabeledContent("Geplant", value: reminders.plannedCount.map(String.init) ?? "–")
            LabeledContent("Erlaubnis", value: authorizationText)
            #if DEBUG
            Button("Test-Mitteilung in 5 s") { TaskReminderDebug.scheduleTest(after: 5) }
            #endif
        } header: {
            Text("Erinnerungen")
        } footer: {
            Text("Erinnerungen zur Uhrzeit: höchstens die nächsten 50, abgeglichen bei jeder Änderung der Aufgaben.")
        }
        .listRowBackground(Color.paplyRow)
        .task { await reminders.refreshAuthorization() }
    }

    private func labeled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.paplySecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authorizationText: String {
        switch reminders.authorization {
        case .authorized?: "erlaubt"
        case .provisional?: "vorläufig"
        case .ephemeral?: "kurzzeitig"
        case .denied?: "verweigert"
        case .notDetermined?: "noch nicht gefragt"
        default: "–"
        }
    }
}
