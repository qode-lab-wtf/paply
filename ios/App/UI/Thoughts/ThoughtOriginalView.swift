import PaplyKit
import SwiftUI

// „Original“ im Detail (KONZEPT §3.2): zugeklappt. Darin nur der Rohtext (auswählbar) – Paply behält
// keinen Ton, die Aufnahme ist nach der Umschrift gelöscht.

struct ThoughtOriginalSection: View {
    let source: ThoughtSource?

    @State private var expanded = ThoughtOriginalSection.startExpanded
    @Environment(\.accessibilityReduceMotion) private var reduce

    #if DEBUG
    static var startExpanded: Bool { ProcessInfo.processInfo.arguments.contains("-PaplyExpandOriginal") }
    #else
    static var startExpanded: Bool { false }
    #endif

    var body: some View {
        if let raw = source?.text, !raw.isEmpty {
            Button {
                withAnimation(PaplyMotion.smooth(reduce)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Original")
                        .font(.paplyTitle(.subheadline, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Spacer()
                }
                .foregroundStyle(Color.paplySecondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .docRow(top: 10, bottom: 6)
            .accessibilityLabel("Original")
            .accessibilityValue(expanded ? "aufgeklappt" : "zugeklappt")
            .accessibilityHint("Rohtext, wie gesprochen")

            if expanded {
                Text(raw)
                    .font(.callout)
                    .foregroundStyle(Color.paplyText.opacity(0.78))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
                    .docRow(top: 4, bottom: 10)
            }
        }
    }
}
