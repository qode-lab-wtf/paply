import PaplyKit
import SwiftUI
import UIKit

// MARK: - Bausteine

/// Kleines Symbol vor einer Zeile: ruhige, einheitliche Kachel mit Linien-Glyphe (Lucide).
struct SettingsIcon: View {
    let glyph: Lucide

    var body: some View {
        LucideImage(glyph, size: 17, stroke: 1.9, scales: false)
            .foregroundStyle(Color.paplyText.opacity(0.92))
            .frame(width: 29, height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.1)))
            .accessibilityHidden(true)
    }
}

struct SettingsRow: View {
    let title: String
    let glyph: Lucide
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(glyph: glyph)
            Text(title).foregroundStyle(Color.paplyText)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(Color.paplyText.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }
}

/// Symbol des Gedanken-Knopfs: p-Kopf in Mint auf derselben ruhigen Kachel
struct ThoughtSettingsIcon: View {
    var body: some View {
        PaplyMark(monochrome: ThoughtTint.mint)
            .frame(width: 15, height: 16)
            .frame(width: 29, height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.1)))
            .accessibilityHidden(true)
    }
}

/// „Feedback senden“: kurzer Text + Diagnose-Protokoll (nur Ereignisse, IDs, Zeiten – nie Diktattext).
/// Das Protokoll entsteht erst, wenn ein Ziel gewählt ist (Mail, Nachrichten, AirDrop …).
struct FeedbackPackage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .utf8PlainText) { _ in
            let url = await Task.detached(priority: .userInitiated) { DiagReader.export() }.value
            guard let url else { throw CocoaError(.fileWriteUnknown) }
            return SentTransferredFile(url)
        }
    }

    @MainActor
    static var message: String {
        "Feedback zu Paply \(SettingsView.versionText), iOS \(UIDevice.current.systemVersion):\n\n"
    }
}

private extension View {
    /// Zeilen-Hintergrund passend zum Waldgrün
    func paplyRows() -> some View {
        listRowBackground(Color.white.opacity(0.07))
    }
}

// MARK: - Einstellungen

/// Nur das, was man im Alltag braucht. Alles Technische liegt im Entwicklerbereich
/// (erscheint nach 5× Tippen auf die Version).
struct SettingsView: View {
    /// Abschnitt „Beta“ (Ziel für `focus`, Hinweis „Gedanken sind Beta“)
    static let betaAnchor = "beta"

    /// Abschnitt, zu dem die Seite beim Öffnen rollt
    var focus: String?
    @Bindable private var settings = AppSettings.shared
    private let setup = SetupStatus.shared
    @State private var keyDraft = ""
    @State private var keyCheck: KeyCheckState = .idle
    @State private var versionTaps = 0
    @State private var devHint: String?

    enum KeyCheckState: Equatable {
        case idle
        case checking
        case done(PaplyKit.KeyCheck)
    }

    var body: some View {
        ScrollViewReader { proxy in
            form
                .task {
                    guard let target = scrollTarget else { return }
                    try? await Task.sleep(for: .milliseconds(450))
                    withAnimation(.paplySmooth) { proxy.scrollTo(target, anchor: .top) }
                }
        }
    }

    /// `focus`; im Debug für Bildschirmfotos auch `-PaplySettingsThoughts` bzw. `-PaplySettingsBeta`
    private var scrollTarget: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-PaplySettingsThoughts") { return "thoughts" }
        if args.contains("-PaplySettingsBeta") { return Self.betaAnchor }
        #endif
        return focus
    }

    private var form: some View {
        Form {
            keySection

            Section {
                NavigationLink(value: Route.spokenLanguages) {
                    SettingsRow(title: "Sprachen", glyph: .globe, value: languagesSummary)
                }
                NavigationLink(value: Route.vocabulary) {
                    SettingsRow(title: "Eigene Begriffe", glyph: .bookA, value: vocabularySummary)
                }
            } header: {
                Text("Erkennung")
            } footer: {
                Text(settings.betaThoughts ? "Gilt für Diktat und Gedanken." : "Gilt fürs Diktat.")
            }
            .paplyRows()

            Section {
                Picker(selection: $settings.holdDuration) {
                    ForEach(HoldDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(glyph: .mic)
                        Text("Mikro bereit halten").foregroundStyle(Color.paplyText)
                    }
                }
            } footer: {
                Text(holdFooter)
            }
            .paplyRows()

            betaSection

            if settings.betaThoughts {
                Section {
                    NavigationLink(value: Route.thoughtButton) {
                        HStack(spacing: 12) {
                            ThoughtSettingsIcon()
                            Text("Gedanken-Knopf").foregroundStyle(Color.paplyText)
                        }
                    }
                } header: {
                    Text("Gedanken")
                } footer: {
                    Text("Aufnahmen werden nach der Umschrift sofort gelöscht, Text und Aufgaben bleiben. Gesendet wird nur an Groq, mit deinem Schlüssel.")
                }
                .paplyRows()
                .id("thoughts")

                // Erinnerungen zur Uhrzeit (TaskReminders)
                TaskReminderSettingsSection()
            }

            Section {
                if setup.needsKeyboardSetup {
                    NavigationLink(value: Route.keyboardSetup) {
                        SettingsRow(title: "Tastatur einrichten", glyph: .keyboard, value: "fehlt noch")
                    }
                }
                if settings.developerMode {
                    NavigationLink(value: Route.developer) {
                        SettingsRow(title: "Entwicklerbereich", glyph: .hammer)
                    }
                }
            }
            .paplyRows()

            Section {
                ShareLink(item: FeedbackPackage(), subject: Text("Paply-Feedback"), message: Text(FeedbackPackage.message),
                          preview: SharePreview("Paply-Diagnose")) {
                    HStack(spacing: 12) {
                        SettingsIcon(glyph: .messageSquare)
                        Text("Feedback senden").foregroundStyle(Color.paplyText)
                        Spacer()
                    }
                }
            } footer: {
                Text("Mit Diagnose-Protokoll: nur Abläufe, Zeiten und Kennungen – keine Diktate, keine Gedanken.")
            }
            .paplyRows()

            Section {
                Button {
                    countVersionTap()
                } label: {
                    HStack {
                        Text("Version").foregroundStyle(Color.paplyText.opacity(0.55))
                        Spacer()
                        Text(Self.versionText).foregroundStyle(Color.paplyText.opacity(0.55)).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                if let devHint { Text(devHint) }
            }
            .paplyRows()
        }
        .paplyList()
        .navigationTitle("Einstellungen")
        .onAppear { setup.refresh() }
        .onChange(of: settings.holdDuration) { _, value in
            Diag.log("settings.hold", ["hold": .s(value.rawValue)])
            SessionController.shared.refreshShared()
        }
    }

    private var holdFooter: String {
        let base = "So lange nach der letzten Nutzung hört Paply sofort zu, wenn du in der Tastatur diktierst. Den orangen Punkt bzw. das Mikro-Symbol oben zeigt iOS – Paply speichert und sendet dabei nichts, bis du sprichst."
        guard settings.betaThoughts else { return base }
        return base + " Der Gedanken-Knopf braucht das nicht: Er startet das Mikro selbst, auch wenn Paply nicht läuft."
    }

    // MARK: Beta

    /// Beta „Gedanken & Aufgaben“ (`AppSettings.betaThoughts`). Aus: nur das Diktat; Gedanken, Aufgaben und
    /// Erinnerungen blendet die App aus, gespeichert bleibt alles.
    private var betaSection: some View {
        Section {
            Toggle(isOn: $settings.betaThoughts) {
                HStack(spacing: 12) {
                    SettingsIcon(glyph: .flaskConical)
                    Text("Gedanken & Aufgaben").foregroundStyle(Color.paplyText)
                }
            }
        } header: {
            Text("Beta")
        } footer: {
            Text("Neue Funktionen im Test: Gedanken per Knopf festhalten, Landkarte, Aufgaben, Erinnerungen und Widgets. Aus heißt nur ausgeblendet – deine Gedanken und Aufgaben bleiben gespeichert.")
        }
        .paplyRows()
        .id(Self.betaAnchor)
    }

    // MARK: Groq-Schlüssel

    private var keySection: some View {
        Section {
            if settings.hasAPIKey {
                HStack(spacing: 12) {
                    SettingsIcon(glyph: .keyRound)
                    Text("Schlüssel gespeichert").foregroundStyle(Color.paplyText)
                    Spacer()
                    Text(maskedKey).foregroundStyle(Color.paplyText.opacity(0.55)).monospaced()
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
                Link(destination: Self.groqKeysURL) {
                    HStack(spacing: 12) {
                        SettingsIcon(glyph: .keyRound)
                        Text("Kostenlosen Schlüssel holen").foregroundStyle(Color.paplyText)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.paplyGreenBright)
                    }
                }
                KeySteps()
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
            Text("Der Schlüssel bleibt nur auf diesem iPhone. Tipp: Am Mac kopieren, am iPhone „Einsetzen“ – die Zwischenablage wandert mit. Gilt für Diktat und Gedanken.")
        }
        .paplyRows()
    }

    static let groqKeysURL = URL(string: "https://console.groq.com/keys")!

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

    // MARK: Zusammenfassungen

    private var languagesSummary: String {
        let names = settings.effectiveSpokenLanguages.map(AppSettings.languageName)
        let list = names.isEmpty ? "" : " (\(names.prefix(3).joined(separator: ", "))\(names.count > 3 ? " …" : ""))"
        return (settings.spokenLanguagesAuto ? "Automatisch" : "Eigene") + list
    }

    private var vocabularySummary: String {
        let words = settings.paply.vocabulary
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return words.isEmpty ? "keine" : "\(words.count)"
    }

    // MARK: Entwicklerbereich freischalten

    static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func countVersionTap() {
        guard !settings.developerMode else {
            devHint = "Der Entwicklerbereich ist schon an."
            return
        }
        versionTaps += 1
        if versionTaps >= 5 {
            settings.developerMode = true
            versionTaps = 0
            devHint = "Entwicklerbereich ist an."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Diag.log("settings.developerMode", ["on": .b(true)])
        } else if versionTaps >= 3 {
            devHint = "Noch \(5 - versionTaps)× tippen …"
        }
    }
}

// MARK: - Sprachen

/// Eine Zeile „Sprachen“: automatisch aus Tastaturen + Gerätesprachen oder eigene Liste.
struct SpokenLanguagesView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Automatisch", isOn: $settings.spokenLanguagesAuto)
            } footer: {
                Text(settings.spokenLanguagesAuto
                     ? "Erkannt: \(names(settings.detectedSpokenLanguages)). Aus deinen Tastaturen und den Sprachen des iPhones; ist es nur eine, kommt Englisch dazu."
                     : "Wähle die Sprachen, die du sprichst – auch gemischt in einem Satz.")
            }
            .paplyRows()
            if !settings.spokenLanguagesAuto {
                Section("Deine Sprachen") {
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
                .paplyRows()
            }
            if !settings.effectiveSpokenLanguages.isEmpty {
                Section {
                    Picker("Hauptsprache", selection: primaryLanguage) {
                        ForEach(settings.effectiveSpokenLanguages, id: \.self) { code in
                            Text(AppSettings.languageName(code)).tag(code)
                        }
                    }
                } footer: {
                    Text("Kurze Sätze schreibt Paply direkt in der Hauptsprache, statt die Sprache zu raten.")
                }
                .paplyRows()
            }
            Section {
                EmptyView()
            } footer: {
                Text("Bei längeren Sätzen erkennt Paply die Sprache selbst. Die Liste hilft, wenn du mitten im Satz wechselst – zum Beispiel ein englischer Satz in einer deutschen Nachricht. Erkennt Paply eine Sprache, die nicht in der Liste steht, schreibt es in der Hauptsprache.")
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

    /// Auswahl der Hauptsprache; ohne (gültige) Wahl die erste iPhone-Sprache bzw. die erste der Liste.
    private var primaryLanguage: Binding<String> {
        Binding(
            get: { settings.effectivePrimaryLanguage ?? "" },
            set: { code in
                guard code != settings.paply.primaryLanguage else { return }
                settings.paply.primaryLanguage = code
                Diag.log("settings.primaryLanguage", ["lang": .s(code), "langs": .s(settings.effectiveSpokenLanguages.joined(separator: ","))])
            }
        )
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

// MARK: - Eigene Begriffe

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
                Text("Namen und Fachwörter, getrennt durch Komma oder neue Zeile. Paply schreibt sie dann richtig.")
            }
            .paplyRows()
        }
        .paplyList()
        .navigationTitle("Eigene Begriffe")
    }
}

/// Karte mit Symbol, nummerierten Schritten und Knöpfen.
struct GuideCard: View {
    let title: String
    let symbol: String
    /// Linien-Glyphe statt SF-Symbol (Gedanken-Anleitung)
    var glyph: Lucide?
    let steps: [String]
    let buttons: [(String, URL?)]
    var tint: AnyShapeStyle = AnyShapeStyle(Color.paplyGreenBright)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Group {
                    if let glyph {
                        LucideImage(glyph, size: 21, stroke: 2, scales: false)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.paplyForest)
                .frame(width: 42, height: 42)
                .background(Circle().fill(tint))
                Text(title).font(.paplyTitle(.headline, weight: .semibold)).foregroundStyle(Color.paplyText)
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.paplyForest)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.paplyText.opacity(0.85)))
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(Color.paplyText.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !buttons.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                        if let url = button.1 {
                            Button(button.0) { UIApplication.shared.open(url) }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                                .tint(Color.white.opacity(0.14))
                                .foregroundStyle(Color.paplyText)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paplyCard()
    }
}

// MARK: - Tastatur einrichten

struct KeyboardSetupView: View {
    private let setup = SetupStatus.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Erst erklären, warum – dann die Schritte
                HStack(alignment: .top, spacing: 10) {
                    LucideImage(.shieldCheck, size: 18, stroke: 1.9, relativeTo: .subheadline)
                        .foregroundStyle(ThoughtTint.mint)
                        .padding(.top, 1)
                    Text("Vollzugriff braucht die Tastatur nur, um mit der Paply-App zu sprechen. Die Tastatur selbst sendet nichts ins Internet und merkt sich nichts, was du tippst.")
                        .font(.subheadline)
                        .foregroundStyle(Color.paplyText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 10) {
                    statusLine("Paply als Tastatur hinzugefügt", done: setup.keyboardEnabled)
                    statusLine("Vollzugriff erlaubt", done: setup.fullAccessSeen)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paplyCard()

                GuideCard(title: "So geht’s", symbol: "keyboard.fill", glyph: .keyboard, steps: [
                    "„Einstellungen öffnen“ tippen – du landest bei Paply.",
                    "„Tastaturen“ → „Paply“ einschalten.",
                    "„Vollen Zugriff erlauben“ einschalten.",
                    "Unter Allgemein → Tastatur → Tastaturen auf „Bearbeiten“ tippen und Paply direkt hinter deine Haupttastatur ziehen.",
                    "In einem Textfeld die Weltkugel tippen, bis Paply erscheint.",
                ], buttons: [
                    ("Einstellungen öffnen", URL(string: UIApplication.openSettingsURLString)),
                ])

                Text("Falls schon alles erlaubt ist: einmal Paply in der Tastatur öffnen, dann wird es hier abgehakt.")
                    .font(.footnote)
                    .foregroundStyle(Color.paplyText.opacity(0.55))
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(PaplyBackground())
        .navigationTitle("Tastatur einrichten")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setup.refresh() }
    }

    private func statusLine(_ text: String, done: Bool) -> some View {
        Label {
            Text(text).foregroundStyle(Color.paplyText)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.paplyGreenBright : Color.paplyText.opacity(0.4))
        }
    }
}

// MARK: - Entwicklerbereich

/// Alles Technische für Phase 0. Funktionen und Standardwerte unverändert.
struct DeveloperView: View {
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    private let storage = StorageCheck.shared

    private var storageSummary: String {
        guard let result = storage.result else { return "–" }
        if !result.ok { return "Fehler" }
        return result.other == nil ? "App ok · Tastatur fehlt" : "App + Tastatur ok"
    }

    var body: some View {
        Form {
            Section("Diktat") {
                Picker("Transkription", selection: $settings.paply.transcriptionModel) {
                    ForEach(AppSettings.transcriptionModels, id: \.id) { model in
                        Text(model.label).tag(model.id)
                    }
                }
                Toggle("Stücke-Upload", isOn: $settings.paply.chunkedUpload)
                NavigationLink(value: Route.testVariants) {
                    HStack {
                        Text("Testvarianten der Pipeline")
                        Spacer()
                        Text(settings.testOptions.isDefault ? "Standard" : "geändert")
                            .foregroundStyle(settings.testOptions.isDefault ? Color.secondary : Color.paplyBeak)
                    }
                }
                LabeledContent("Polier-Modell", value: settings.paply.polishModel)
            }
            .paplyRows()

            Section {
                Toggle("Mikro im Leerlauf pausieren (Experiment)", isOn: Binding(
                    get: { settings.idlePause != .off },
                    set: { settings.idlePause = $0 ? .pause : .off }
                ))
                if settings.idlePause != .off {
                    Picker("Art", selection: $settings.idlePause) {
                        Text("engine.pause()").tag(IdlePauseMode.pause)
                        Text("engine.stop()").tag(IdlePauseMode.stop)
                    }
                }
            } header: {
                Text("Sitzung")
            } footer: {
                Text("Hält die Aufnahme an, sobald Paply im Hintergrund nichts zu tun hat (Sitzung bleibt aktiv), und startet sie erst beim nächsten 🌐 – ohne Vorlauf. Klappt das nicht, gilt „Mikro aus“.")
            }
            .paplyRows()

            Section {
                Toggle("App automatisch öffnen", isOn: $settings.autoOpenApp)
                #if DEBUG
                Toggle("Host-App protokollieren", isOn: $settings.logHostBundleID)
                #endif
            } header: {
                Text("Tastatur")
            } footer: {
                Text("Ohne Sitzung öffnet die Tastatur Paply automatisch (Variante A) oder zeigt „Paply starten“ (Variante B). „Host-App protokollieren“ liest über private Felder, welche App die Tastatur zeigt, und schreibt das nur ins Protokoll.")
            }
            .paplyRows()

            ThoughtsDeveloperSection()

            TaskReminderDeveloperSection()

            Section("Werkzeuge") {
                NavigationLink("Testseite (Höhe, Diktat)", value: Route.testPage)
                NavigationLink("Diagnose", value: Route.diagnostics)
                NavigationLink(value: Route.storageCheck) {
                    HStack {
                        Text("Speicher-Selbsttest")
                        Spacer()
                        Text(storageSummary).foregroundStyle(storage.result?.ok == false ? Color.paplyDanger : Color.secondary)
                    }
                }
            }
            .paplyRows()

            Section("Info") {
                LabeledContent("Version", value: SettingsView.versionText)
                LabeledContent("App Group", value: AppGroup.identifier)
            }
            .paplyRows()

            Section {
                Toggle("Entwicklerbereich anzeigen", isOn: $settings.developerMode)
            } footer: {
                Text("Ausblenden ändert keine Einstellung. Wieder einblenden: 5× auf die Version tippen.")
            }
            .paplyRows()
        }
        .paplyList()
        .navigationTitle("Entwicklerbereich")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.paply) { _, value in
            Diag.log("settings.change", [
                "model": .s(value.transcriptionModel),
                "chunked": .b(value.chunkedUpload),
                "vocabLen": .i(value.vocabulary.count),
            ])
        }
        .onChange(of: settings.autoOpenApp) { _, value in
            Diag.log("settings.autoOpen", ["on": .b(value)])
        }
        .onChange(of: settings.idlePause) { _, value in
            Diag.log("settings.idlePause", ["mode": .s(value.rawValue)])
        }
        .onChange(of: settings.developerMode) { _, on in
            Diag.log("settings.developerMode", ["on": .b(on)])
            if !on { dismiss() }
        }
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
            .paplyRows()
            Section {
                Button("Auf Standard zurücksetzen") { settings.testOptions = PipelineTestOptions() }
                    .disabled(settings.testOptions.isDefault)
            }
            .paplyRows()
        }
        .paplyList()
        .navigationTitle("Testvarianten")
        .onChange(of: settings.testOptions) { _, value in
            Diag.log("settings.testOptions", ["opts": .s(value.logName)])
        }
    }
}

// MARK: - Speicher-Selbsttest

/// App und Tastatur schreiben je eine Markierung in den gemeinsamen Speicher und lesen die
/// des anderen. Zeigt Pfade, Ergebnis und die Dateien mit Größe.
struct StorageCheckView: View {
    private let storage = StorageCheck.shared

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM. HH:mm:ss"
        return f
    }()

    var body: some View {
        Form {
            if let result = storage.result {
                Section("App") {
                    check("Ordner angelegt", result.basePath != nil)
                    check("Markierung geschrieben", result.wroteOwn)
                    check("Markierung zurückgelesen", result.readBackOwn)
                    if !result.errors.isEmpty {
                        Text(result.errors.joined(separator: "\n")).foregroundStyle(Color.paplyDanger)
                    }
                }
                .listRowBackground(Color.white.opacity(0.07))
                Section {
                    if let other = result.other {
                        check("Markierung der Tastatur gelesen", true)
                        LabeledContent("Zuletzt von der Tastatur", value: Self.time.string(from: other.date))
                        check("Tastatur konnte die App lesen", other.readOther)
                    } else {
                        check("Markierung der Tastatur gelesen", false)
                        Text("Einmal 🌐 → Paply in einem Textfeld öffnen (mit Vollzugriff), dann „Erneut prüfen“.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Tastatur")
                }
                .listRowBackground(Color.white.opacity(0.07))
                Section("Pfade") {
                    Text(result.containerPath ?? "kein Container").font(.caption.monospaced()).textSelection(.enabled)
                    Text(result.basePath ?? "kein Paply-Ordner").font(.caption.monospaced()).textSelection(.enabled)
                }
                .listRowBackground(Color.white.opacity(0.07))
            } else {
                Section { ProgressView() }
            }
            Section("Dateien (\(storage.files.count))") {
                ForEach(storage.files, id: \.path) { file in
                    HStack {
                        Text(file.path).font(.caption.monospaced())
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(Color.white.opacity(0.07))
            Section {
                Button("Erneut prüfen") { storage.run(reason: "button") }
            } footer: {
                if let at = storage.checkedAt { Text("Geprüft: \(Self.time.string(from: at))") }
            }
            .listRowBackground(Color.white.opacity(0.07))
        }
        .paplyList()
        .navigationTitle("Speicher-Selbsttest")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { storage.run(reason: "open") }
    }

    private func check(_ title: String, _ ok: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.paplyGreenBright : Color.paplyDanger)
        }
    }
}

/// Drei kurze Schritte zum Groq-Schlüssel.
private struct KeySteps: View {
    private let steps = [
        "Bei Groq kostenlos anmelden",
        "„Create API Key“ tippen und kopieren",
        "Hier „Einsetzen“",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.paplyForest)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.paplyText.opacity(0.85)))
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(Color.paplyText.opacity(0.85))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
