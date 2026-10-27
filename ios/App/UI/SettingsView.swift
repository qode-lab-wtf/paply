import PaplyKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var keyDraft = ""
    @State private var keyCheck: KeyCheckState = .idle

    enum KeyCheckState: Equatable {
        case idle
        case checking
        case done(PaplyKit.KeyCheck)
    }

    var body: some View {
        Form {
            Section {
                if settings.hasAPIKey {
                    HStack {
                        Text("Gespeichert")
                        Spacer()
                        Text(maskedKey).foregroundStyle(.secondary).monospaced()
                    }
                    keyStatusRow
                    Button("Schlüssel prüfen") { validate(settings.apiKey) }
                        .disabled(keyCheck == .checking)
                    Button("Schlüssel entfernen", role: .destructive) {
                        settings.saveAPIKey("")
                        keyCheck = .idle
                        SessionController.shared.refreshShared()
                    }
                } else {
                    SecureField("gsk_…", text: $keyDraft)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { saveDraft() }
                    HStack {
                        // onPaste kommt nach dem asynchronen Laden auf einer fremden Queue an.
                        // Ohne @Sendable gälte die Closure als MainActor-isoliert und Swift 6
                        // bricht zur Laufzeit ab (dispatch_assert_queue). Deshalb erst hier
                        // ausdrücklich zurück auf den Main-Actor.
                        PasteButton(payloadType: String.self) { @Sendable strings in
                            guard let first = strings.first else { return }
                            Task { @MainActor in
                                keyDraft = first
                                saveDraft()
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        Spacer()
                        Button("Sichern") { saveDraft() }
                            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    keyStatusRow
                }
            } header: {
                Text("Groq-Schlüssel")
            } footer: {
                Text("Der Schlüssel liegt nur im Schlüsselbund dieses iPhones. Am Mac kopieren, hier „Einsetzen“ tippen.")
            }

            Section {
                Picker("Transkription", selection: $settings.paply.transcriptionModel) {
                    ForEach(AppSettings.transcriptionModels, id: \.id) { model in
                        Text(model.label).tag(model.id)
                    }
                }
                Toggle("Stücke-Upload", isOn: $settings.paply.chunkedUpload)
                HStack {
                    Text("Sprache")
                    Spacer()
                    Text("Automatisch").foregroundStyle(.secondary)
                }
                NavigationLink(value: Route.spokenLanguages) {
                    HStack {
                        Text("Sprachen, die du sprichst")
                        Spacer()
                        Text(spokenSummary).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                NavigationLink(value: Route.vocabulary) {
                    HStack {
                        Text("Eigene Begriffe")
                        Spacer()
                        Text(vocabularySummary).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Diktat")
            } footer: {
                Text("Paply erkennt die gesprochene Sprache selbst. „Sprachen, die du sprichst“ hilft nur beim Wechsel mitten im Satz. Stücke-Upload schickt lange Diktate schon während der Aufnahme in Teilen.")
            }

            Section {
                Picker("Mikro bereit halten", selection: $settings.holdDuration) {
                    ForEach(HoldDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }
            } header: {
                Text("Sitzung")
            } footer: {
                Text("Gezählt ab der letzten Nutzung. Solange das Mikro bereit ist, zeigt iOS oben den orangen Punkt – ausblenden kann ihn keine App. Im Leerlauf wird nichts gespeichert oder gesendet.")
            }

            Section {
                Toggle("App automatisch öffnen", isOn: $settings.autoOpenApp)
                Toggle("Host-App protokollieren", isOn: $settings.logHostBundleID)
                NavigationLink(value: Route.testVariants) {
                    HStack {
                        Text("Testvarianten der Pipeline")
                        Spacer()
                        Text(settings.testOptions.isDefault ? "Standard" : "geändert")
                            .foregroundStyle(settings.testOptions.isDefault ? Color.secondary : Color.paplyBeak)
                    }
                }
                NavigationLink("Testseite (Höhe, Diktat)", value: Route.testPage)
                NavigationLink("Diagnose", value: Route.diagnostics)
                Button("Tastatur einrichten") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                Text("Labor (Phase 0)")
            } footer: {
                Text("Ohne Sitzung öffnet die Tastatur Paply automatisch (Variante A) oder zeigt „Paply starten“ (Variante B). „Host-App protokollieren“ ist experimentell: Die Tastatur liest dann über private Felder, welche App sie zeigt, und schreibt das nur ins Protokoll.")
            }

            Section("Info") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                LabeledContent("App Group", value: AppGroup.containerURL == nil ? "fehlt!" : "ok")
                LabeledContent("Polieren", value: settings.paply.polishModel)
            }
        }
        .paplyList()
        .navigationTitle("Einstellungen")
        .onChange(of: settings.paply) { _, value in
            Diag.log("settings.change", [
                "model": .s(value.transcriptionModel),
                "chunked": .b(value.chunkedUpload),
                "vocabLen": .i(value.vocabulary.count),
            ])
        }
        .onChange(of: settings.holdDuration) { _, value in
            Diag.log("settings.hold", ["hold": .s(value.rawValue)])
            SessionController.shared.refreshShared()
        }
        .onChange(of: settings.autoOpenApp) { _, value in
            Diag.log("settings.autoOpen", ["on": .b(value)])
        }
    }

    @ViewBuilder
    private var keyStatusRow: some View {
        switch keyCheck {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Prüfe …").foregroundStyle(.secondary)
            }
        case .done(.valid):
            Label("Schlüssel funktioniert", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.paplyGreenBright)
        case .done(.invalid):
            Label("Groq lehnt diesen Schlüssel ab. Bitte am Mac neu kopieren und nochmal einsetzen.", systemImage: "xmark.octagon.fill")
                .foregroundStyle(Color.paplyDanger)
        case .done(.offline):
            Label("Keine Verbindung zu Groq. Der Schlüssel ist gespeichert – prüf ihn, sobald du wieder Netz hast.", systemImage: "wifi.slash")
                .foregroundStyle(Color.paplyBeak)
        case .done(.failed(let message)):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.paplyBeak)
        }
    }

    private var maskedKey: String {
        settings.apiKeySuffix.map { "••••" + $0 } ?? "–"
    }

    private var vocabularySummary: String {
        let words = settings.paply.vocabulary
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return words.isEmpty ? "keine" : "\(words.count)"
    }

    private func saveDraft() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        settings.saveAPIKey(key)
        keyDraft = ""
        SessionController.shared.refreshShared()
        validate(key)
    }

    private func validate(_ key: String?) {
        guard let key else { return }
        keyCheck = .checking
        Task {
            let result = await GroqConnection.checkKey(apiKey: key)
            let name = switch result {
            case .valid: "valid"
            case .invalid: "invalid"
            case .offline: "offline"
            case .failed: "failed"
            }
            Diag.log("settings.apiKey.check", ["result": .s(name)])
            keyCheck = .done(result)
        }
    }

    private var spokenSummary: String {
        let codes = settings.effectiveSpokenLanguages
        let names = codes.prefix(3).map(AppSettings.languageName).joined(separator: ", ")
        let prefix = settings.spokenLanguagesAuto ? "automatisch" : "eigene"
        return codes.isEmpty ? prefix : "\(prefix): \(names)\(codes.count > 3 ? " …" : "")"
    }
}

struct VocabularyView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.paply.vocabulary)
                    .frame(minHeight: 220)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } footer: {
                Text("Namen und Fachwörter, getrennt durch Komma oder neue Zeile. Sie helfen beim Erkennen und Polieren.")
            }
        }
        .paplyList()
        .navigationTitle("Eigene Begriffe")
    }
}

/// „Sprachen, die du sprichst“: automatisch aus Tastaturen + Gerätesprachen oder eigene Liste.
struct SpokenLanguagesView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Automatisch", isOn: $settings.spokenLanguagesAuto)
            } footer: {
                Text(settings.spokenLanguagesAuto
                     ? "Automatisch: \(names(settings.detectedSpokenLanguages)). Aus deinen aktivierten Tastaturen und den Gerätesprachen; findet Paply nur eine Sprache, kommt Englisch dazu."
                     : "Wähle die Sprachen, zwischen denen du beim Sprechen wechselst.")
            }
            if !settings.spokenLanguagesAuto {
                Section("Eigene Liste") {
                    ForEach(choices, id: \.self) { code in
                        Button {
                            toggle(code)
                        } label: {
                            HStack {
                                Text(AppSettings.languageName(code)).foregroundStyle(Color.paplyText)
                                Spacer()
                                if settings.paply.spokenLanguages.contains(code) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.paplyGreenBright)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Hilft Whisper, wenn du mitten im Satz die Sprache wechselst (z. B. Deutsch mit einem englischen Satz). Die Erkennung selbst bleibt automatisch.")
            }
        }
        .paplyList()
        .navigationTitle("Sprachen")
        .onAppear { settings.refreshDetectedSpokenLanguages() }
        .onChange(of: settings.spokenLanguagesAuto) { _, auto in
            if !auto, settings.paply.spokenLanguages.isEmpty {
                settings.paply.spokenLanguages = settings.detectedSpokenLanguages
            }
            Diag.log("settings.spokenLanguages", ["auto": .b(auto), "langs": .s(settings.effectiveSpokenLanguages.joined(separator: ","))])
        }
    }

    private var choices: [String] {
        var list = AppSettings.commonLanguages
        for code in settings.detectedSpokenLanguages + settings.paply.spokenLanguages where !list.contains(code) {
            list.append(code)
        }
        return list
    }

    private func names(_ codes: [String]) -> String {
        codes.isEmpty ? "–" : codes.map(AppSettings.languageName).joined(separator: ", ")
    }

    private func toggle(_ code: String) {
        if let index = settings.paply.spokenLanguages.firstIndex(of: code) {
            settings.paply.spokenLanguages.remove(at: index)
        } else {
            settings.paply.spokenLanguages.append(code)
        }
        Diag.log("settings.spokenLanguages", ["auto": .b(false), "langs": .s(settings.paply.spokenLanguages.joined(separator: ","))])
    }
}

/// Testschalter der Pipeline (PipelineOptions) – nur für Messungen.
struct TestVariantsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker("Upload-Format", selection: $settings.testOptions.wav) {
                    Text("FLAC (Standard)").tag(false)
                    Text("WAV").tag(true)
                }
                Toggle("Sprachwechsel-Beispiel", isOn: $settings.testOptions.codeSwitchPrimer)
                Toggle("Polieren", isOn: $settings.testOptions.polish)
                Toggle("Strenge Polier-Prüfung", isOn: $settings.testOptions.strictPolishCheck)
                    .disabled(!settings.testOptions.polish)
            } footer: {
                Text("Nur für Messreihen. „Polieren“ aus nur für reine Transkriptions-Messungen – dann wird der Rohtext eingesetzt. „Strenge Polier-Prüfung“ verwirft polierten Text schon bei ersetzten oder eingefügten Wörtern (Standard an). Jede Einstellung steht im Protokoll (opts).")
            }
            Section {
                Button("Auf Standard zurücksetzen") { settings.testOptions = PipelineTestOptions() }
                    .disabled(settings.testOptions.isDefault)
            }
        }
        .paplyList()
        .navigationTitle("Testvarianten")
        .onChange(of: settings.testOptions) { _, value in
            Diag.log("settings.testOptions", ["opts": .s(value.logName)])
        }
    }
}
