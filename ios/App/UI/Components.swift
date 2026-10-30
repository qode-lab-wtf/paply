import SwiftUI

/// Hintergrund wie im Prototyp: dunkler Wald mit hellem Schein oben.
struct PaplyBackground: View {
    var body: some View {
        RadialGradient(
            colors: [Color(uiColor: UIColor(hex: 0x1D4A35)), .paplyForest, Color(uiColor: UIColor(hex: 0x08160F))],
            center: UnitPoint(x: 0.5, y: -0.05),
            startRadius: 0,
            endRadius: 900
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// Halbtransparente Karte mit feiner Kante
    func paplyCard(cornerRadius: CGFloat = 20) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    /// Einheitlicher Look für Listen auf dem Waldhintergrund
    func paplyList() -> some View {
        scrollContentBackground(.hidden)
            .background(PaplyBackground())
    }
}

/// Kurze Bestätigung unten („Kopiert“).
struct ToastView: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.paplyForest)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.paplyGreenBright))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

/// Marke + Wortmarke als Kopfzeile
struct PaplyWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            PaplyMark().frame(width: 26, height: 28)
            Text("paply")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.paplyText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paply")
    }
}

enum Format {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    static func seconds(_ ms: Double?) -> String {
        guard let ms else { return "–" }
        return String(format: "%.2f s", ms / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func milliseconds(_ ms: Double?) -> String {
        guard let ms else { return "–" }
        return "\(Int(ms.rounded())) ms"
    }
}
