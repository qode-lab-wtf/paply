import SwiftUI

// Beta „Gedanken & Aufgaben“ (`BetaFeatures`, `AppSettings.betaThoughts`): Zeichen in den Reitern und Hinweis, wenn
// bei ausgeschalteter Beta ein Gedanke aufgenommen werden soll.

/// Hinweis „Gedanken sind Beta“ (RootView): Gedanken-Knopf, Steuerelement, Widget, Kurzbefehl oder ein Gedanken-/
/// Aufgaben-Link bei ausgeschalteter Beta.
@MainActor
@Observable
final class BetaHint {
    static let shared = BetaHint()

    var isPresented = false

    private init() {}

    func show() {
        isPresented = true
    }
}

/// Ruhige Kapsel „Beta“ neben dem Titel der Reiter „Gedanken“ und „Aufgaben“
struct BetaBadge: View {
    var body: some View {
        Text("Beta")
            .font(.caption.weight(.semibold))
            .foregroundStyle(ThoughtTint.mint.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(ThoughtTint.mint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(ThoughtTint.mint.opacity(0.22), lineWidth: 0.5))
            .fixedSize()
            .accessibilityLabel("Beta-Funktion")
    }
}

/// „Beta“ links in der Navigationsleiste (über dem großen bzw. neben dem kleinen Titel). iOS 26: ohne Glas-Hintergrund,
/// sonst säße die Kapsel in einer zweiten Kapsel.
struct BetaToolbarBadge: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarLeading) { BetaBadge() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { BetaBadge() }
        }
    }
}

extension View {
    /// Hinweis „Gedanken sind Beta“ mit dem Weg in die Einstellungen
    func betaHintAlert(openSettings: @escaping () -> Void) -> some View {
        modifier(BetaHintAlert(openSettings: openSettings))
    }
}

private struct BetaHintAlert: ViewModifier {
    let openSettings: () -> Void
    @Bindable private var hint = BetaHint.shared

    func body(content: Content) -> some View {
        content.alert("Gedanken sind Beta", isPresented: $hint.isPresented) {
            Button("Einstellungen", action: openSettings)
            Button("OK", role: .cancel) {}
        } message: {
            Text("In den Einstellungen unter „Beta“ einschalten. Deine Gedanken und Aufgaben bleiben gespeichert.")
        }
    }
}
