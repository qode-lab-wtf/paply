import AppIntents

/// Kurzbefehl für „Rückseite doppelt tippen“ (Bedienungshilfen → Tippen → Rückseite) und Siri.
struct PaplyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
