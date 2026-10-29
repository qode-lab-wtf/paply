import AppIntents

/// Siri und Kurzbefehle: nur noch der Gedanke. Das Diktat läuft über 🌐 (zwei klare Wege);
/// ToggleDictationIntent bleibt im Code, wird aber nicht mehr angeboten.
struct PaplyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleConversationIntent(),
            phrases: ["\(.applicationName) Gespräch", "Gespräch mit \(.applicationName) aufnehmen"],
            shortTitle: "Gespräch", systemImageName: "person.2.wave.2")
        // Gedanke (KONZEPT §3.6): antwortet ohne Dialog, sonst spricht Siri in die Aufnahme
        AppShortcut(
            intent: ToggleThoughtIntent(),
            phrases: [
                "\(.applicationName) Gedanke",
                "Gedanke mit \(.applicationName)",
                "Neuer Gedanke in \(.applicationName)",
            ],
            shortTitle: "Gedanke",
            systemImageName: "text.bubble"
        )
    }
}
