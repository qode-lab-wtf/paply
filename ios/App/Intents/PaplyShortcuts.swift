import AppIntents

/// Kurzbefehl für „Rückseite doppelt tippen“ (Bedienungshilfen → Tippen → Rückseite) und Siri.
struct PaplyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: [
                "\(.applicationName)-Diktat an oder aus",
                "Diktat mit \(.applicationName)",
            ],
            shortTitle: "Diktat an/aus",
            systemImageName: "waveform"
        )
    }
}
