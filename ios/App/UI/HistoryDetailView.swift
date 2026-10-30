import PaplyKit
import SwiftUI
import UIKit

struct HistoryDetailView: View {
    let id: String
    let showToast: (String) -> Void
    private let history = HistoryStore.shared

    var body: some View {
        Group {
            if let entry = history.entries.first(where: { $0.id == id }) {
                content(entry)
            } else {
                ContentUnavailableView("Nicht mehr im Verlauf", systemImage: "clock.arrow.circlepath")
            }
        }
        .paplyList()
        .navigationTitle("Diktat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ entry: HistoryEntry) -> some View {
        List {
            Section("Eingesetzt") { copyable(entry.text, empty: "nichts") }
            Section("Rohtext") { copyable(entry.raw, empty: "leer") }
            if let polished = entry.polished, polished != entry.text {
                Section("Poliert (verworfen)") { copyable(polished, empty: "leer") }
            }
            Section("Polieren") {
                LabeledContent("Ergebnis", value: Self.polishStatus(entry))
                LabeledContent("Modell", value: entry.polishModel ?? "–")
                if let error = entry.polishError {
                    Text("Unpoliert eingesetzt – Grund: \(Self.describePolishError(error))")
                        .foregroundStyle(Color.paplyBeak)
                }
                if let reason = entry.polishRejection {
                    Text("Sicherheitsnetz hat den polierten Text verworfen – Grund: \(Self.describeRejection(reason))")
                        .foregroundStyle(Color.paplyBeak)
                }
                if let retries = entry.retries {
                    LabeledContent("Erneut gesendet", value: "\(retries)×")
                }
            }
            if let error = entry.errorMessage {
                Section("Fehler") { Text(error).foregroundStyle(Color.paplyDanger) }
            }
            Section("Zeiten") {
                LabeledContent("Transkription fertig", value: Format.seconds(entry.timings.transcriptionDoneMs))
                LabeledContent("Polieren fertig", value: Format.seconds(entry.timings.polishDoneMs))
                LabeledContent("Gesamt ab „fertig“", value: Format.seconds(entry.timings.totalMs))
                LabeledContent("Nachlauf Audio", value: Format.milliseconds(entry.timings.flushMs))
                LabeledContent("Befehl Tastatur → App", value: Format.milliseconds(entry.timings.commandLatencyMs))
                LabeledContent("Audio", value: String(format: "%.1f s", entry.timings.audioSeconds))
                LabeledContent("Stücke", value: "\(entry.timings.chunkCount)")
                LabeledContent("Hochgeladen", value: ByteCountFormatter.string(fromByteCount: Int64(entry.timings.uploadedBytes), countStyle: .file))
            }
            Section("Sonst") {
                LabeledContent("Quelle", value: entry.source == .keyboard ? "Tastatur" : "Schnelltaste")
                LabeledContent("Sprachen", value: entry.languages.isEmpty ? "–" : entry.languages.joined(separator: ", "))
                LabeledContent("Zeit", value: Format.dayTime.string(from: entry.date))
            }
        }
    }

    static func polishStatus(_ entry: HistoryEntry) -> String {
        if entry.polishError != nil { return "unpoliert" }
        if entry.polishRejection != nil { return "Rohtext (Sicherheitsnetz)" }
        if entry.polished != nil { return "poliert" }
        return "–"
    }

    /// PolishFailureCode → deutscher Text (Code bleibt sichtbar). Alte Einträge mit
    /// früheren Werten (z. B. „http-503“) werden roh angezeigt.
    static func describePolishError(_ raw: String) -> String {
        guard let code = PolishFailureCode(rawValue: raw) else { return raw }
        let text = switch code {
        case .disabled: "Polieren war ausgeschaltet (Testvariante)"
        case .modelUnavailable: "Polier-Modell nicht verfügbar"
        case .rateLimited: "Groq-Kontingent erschöpft"
        case .unauthorized: "Schlüssel fürs Polieren abgelehnt"
        case .serverError: "Störung bei Groq"
        case .requestRejected: "Groq hat die Anfrage abgelehnt"
        case .network: "Keine oder abgerissene Verbindung"
        case .invalidResponse: "Unlesbare Antwort von Groq"
        case .cancelled: "Abgebrochen"
        }
        return "\(text) (\(raw))"
    }

    /// PolishRejectionCode → deutscher Text (Code bleibt sichtbar); Unbekanntes roh.
    static func describeRejection(_ raw: String) -> String {
        guard let code = PolishRejectionCode(rawValue: raw) else { return raw }
        let text = switch code {
        case .empty: "polierter Text war leer"
        case .meta: "Antwort enthielt Kommentar statt Text"
        case .length: "Länge wich zu stark ab"
        case .content: "Inhalt wich zu stark ab"
        case .negation: "Verneinung verändert"
        case .digits: "Zahlen verändert"
        case .replaced: "Wörter ersetzt"
        case .inserted: "Wörter eingefügt"
        case .added: "Inhalt hinzugefügt"
        case .truncated: "Antwort abgeschnitten"
        }
        return "\(text) (\(raw))"
    }

    @ViewBuilder
    private func copyable(_ text: String, empty: String) -> some View {
        if text.isEmpty {
            Text(empty).foregroundStyle(.secondary)
        } else {
            Button {
                UIPasteboard.general.string = text
                showToast("Kopiert")
            } label: {
                Text(text)
                    .foregroundStyle(Color.paplyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }
}
