import PaplyKit
import SwiftUI
import UIKit

// Gemeinsame Bausteine der Gedanken-Oberfläche (KONZEPT §3, §4): Farben, Glas, Bewegung,
// Datum-Abschnitte, Anzeige-Hilfen für Gedanken und der Navigationszustand.

// MARK: - Farben

/// Gedanken-Akzent „Mint-Gold“ (Aura der Mac-Notes-Pille). Diktat bleibt reines Grün.
enum ThoughtTint {
    static let mint = Color(uiColor: UIColor(hex: 0xD8F39A))
    static let leaf = Color(uiColor: UIColor(hex: 0x7ED957))
    static let lime = Color(uiColor: UIColor(hex: 0xDCE568))
    static let gold = Color(uiColor: UIColor(hex: 0xF5BF50))
    static let pale = Color(uiColor: UIColor(hex: 0xBFEEC4))
    /// Farbkreis der Aura (Reihenfolge wie `conic-gradient` am Mac)
    static let aura: [Color] = [mint, leaf, lime, gold, pale, leaf]
    /// Wisch-Aktion „Thema“ (dunkles Gold, damit Weiß darauf lesbar bleibt)
    static let swipe = Color(uiColor: UIColor(hex: 0xB8862B))

    /// Fläche für Kennungen (Themen-Symbol, Gedanken-Knopf): Mint oben links → Gold unten rechts
    static var fill: LinearGradient {
        LinearGradient(colors: [mint, lime, gold], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    static let paplySecondaryText = Color.paplyText.opacity(0.62)
    static let paplyTertiaryText = Color.paplyText.opacity(0.42)
    /// Zeilen auf dem Waldhintergrund (wie die Einstellungen)
    static let paplyRow = Color.white.opacity(0.07)
}

// MARK: - Bewegung (§4)

/// Federn der Desktop-Pille; bei reduzierter Bewegung 0,15 s lineare Deckkraft.
enum PaplyMotion {
    static func smooth(_ reduce: Bool) -> Animation { reduce ? .linear(duration: 0.15) : .paplySmooth }
    static func bouncy(_ reduce: Bool) -> Animation { reduce ? .linear(duration: 0.15) : .paplyBouncy }
}

/// Knopf, der beim Halten auf 0,92 schrumpft (Smooth).
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    @Environment(\.accessibilityReduceMotion) private var reduce

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? scale : 1)
            .opacity(configuration.isPressed && reduce ? 0.7 : 1)
            .animation(PaplyMotion.smooth(reduce), value: configuration.isPressed)
    }
}

// MARK: - Glas (§3)

enum PaplyGlassStyle {
    /// neutrale Fläche (Chips): iOS 26 Glas, sonst Weiß 8 %
    case plain
    /// schwebende Leiste/Hinweis: iOS 26 Glas, sonst Material mit feiner Kante
    case bar
    /// getönte Fläche, z. B. der Aufnahme-Knopf: iOS 26 getöntes Glas, sonst volle Farbe
    case prominent(Color)
}

enum PaplyStyle {
    /// Liquid Glass ab iOS 26 (im Debug abschaltbar mit `-PaplyClassic`, um den iOS-18-Look zu prüfen)
    static var usesGlass: Bool {
        if #available(iOS 26, *) { return !ThoughtsLaunch.forceClassic }
        return false
    }
}

extension View {
    /// Eigene Flächen: ab iOS 26 `glassEffect`, auf iOS 18 Karte bzw. Material.
    @ViewBuilder
    func paplyGlass<S: Shape>(_ style: PaplyGlassStyle = .plain, interactive: Bool = false, in shape: S) -> some View {
        if #available(iOS 26, *) {
            if PaplyStyle.usesGlass {
                switch style {
                case .plain, .bar:
                    glassEffect(.regular.interactive(interactive), in: shape)
                case .prominent(let color):
                    glassEffect(.regular.tint(color).interactive(interactive), in: shape)
                }
            } else {
                classicGlass(style, in: shape)
            }
        } else {
            classicGlass(style, in: shape)
        }
    }

    func paplyGlass(_ style: PaplyGlassStyle = .plain, interactive: Bool = false) -> some View {
        paplyGlass(style, interactive: interactive, in: Capsule())
    }

    @ViewBuilder
    private func classicGlass<S: Shape>(_ style: PaplyGlassStyle, in shape: S) -> some View {
        switch style {
        case .plain:
            background(shape.fill(Color.white.opacity(0.08)))
                .overlay(shape.stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        case .bar:
            background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(Color.paplyForest.opacity(0.55)))
                .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        case .prominent(let color):
            background(shape.fill(color))
        }
    }

    /// Blätter: iOS 26 behält das System-Glas, iOS 18 bekommt den Waldhintergrund.
    @ViewBuilder
    func paplySheetBackground() -> some View {
        if PaplyStyle.usesGlass {
            scrollContentBackground(.hidden)
        } else {
            scrollContentBackground(.hidden).background(PaplyBackground())
        }
    }
}

// MARK: - Themen-Symbole

extension TopicIcon {
    /// SF-Ersatz (eine Zuordnung für App und Widgets: `TopicIconKey`)
    var systemImage: String { TopicIconKey.sfSymbol(rawValue) }

    /// Linien-Glyphe aus Lucide (wie am Mac)
    var lucide: Lucide { Lucide.topic(rawValue) }

    /// Name für VoiceOver
    var spokenName: String {
        switch self {
        case .sparkles: "Funken"
        case .lightbulb: "Glühbirne"
        case .home: "Haus"
        case .code: "Code"
        case .mapPin: "Ort"
        case .sun: "Sonne"
        case .moon: "Mond"
        case .heart: "Herz"
        case .coffee: "Kaffee"
        case .briefcase: "Aktentasche"
        case .calendar: "Kalender"
        case .messageCircle: "Sprechblase"
        case .book: "Buch"
        case .music: "Musik"
        case .camera: "Kamera"
        case .leaf: "Blatt"
        case .flag: "Flagge"
        case .circleHelp: "Fragezeichen"
        case .pencil: "Stift"
        case .plane: "Flugzeug"
        case .wallet: "Karte"
        case .users: "Personen"
        case .list: "Liste"
        case .zap: "Blitz"
        }
    }
}

/// Themen-Kennung: Symbol auf Mint-Gold, abgerundetes Quadrat. Hat das Thema ein Bild (`topicID`), steht das Bild
/// im gleichen Quadrat.
struct TopicBadge: View {
    let icon: TopicIcon
    var size: CGFloat = 44
    /// Thema, dessen Bild statt des Symbols erscheint (nil = immer das Symbol)
    var topicID: String?

    var body: some View {
        if let image = TopicImages.shared.image(for: topicID) {
            TopicImageTile(image: image, topicID: topicID, size: size, cornerRatio: 0.27)
                .accessibilityHidden(true)
        } else {
            TopicGlyph(key: icon.rawValue, size: size * 0.52, stroke: 2, scales: false)
                .foregroundStyle(Color.paplyForest)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(ThoughtTint.fill))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Anzeige eines Gedankens

extension Thought {
    /// Aufnahme bzw. Verarbeitung läuft noch
    var isProcessing: Bool {
        switch state {
        case .recording, .captured, .transcribing, .transcribed, .structuring: true
        default: false
        }
    }

    var isWaiting: Bool {
        switch state {
        case .waitingNetwork, .waitingKey, .waitingLimit, .waitingBudget, .needsAttention: true
        default: false
        }
    }

    /// Titel; noch nicht geordnet: „Gedanke · 0:42“ (Dauer), damit Wartende unterscheidbar sind
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if state == .done { return "Ohne Titel" }
        return durationMs > 0 ? "Gedanke · \(ThoughtDate.clock(Double(durationMs) / 1000))" : "Gedanke"
    }

    /// Eine Zeile Vorschau (ohne Zeilenumbrüche)
    var previewLine: String {
        guard let text, !text.isEmpty else { return "" }
        let cut = text.prefix(160)
        return cut.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    var openTaskCount: Int { tasks.reduce(0) { $0 + ($1.done ? 0 : 1) } }

    /// „Erneut ordnen“ ist sinnvoll (nicht geordnet oder Ton ohne Text)
    var canReorganize: Bool { (state == .done && textIsRaw) || state == .needsAttention }

    /// Hinweis für Warte- und Fehlerzustände (§3.7)
    var stateNote: ThoughtStateNote? {
        switch state {
        case .waitingNetwork:
            ThoughtStateNote(icon: .wifiOff, text: status.message ?? "Gesichert · wartet auf Netz", tint: .paplySecondaryText)
        case .waitingKey:
            ThoughtStateNote(icon: .keyRound, text: status.message ?? "Gesichert · Groq-Schlüssel fehlt", tint: .paplySecondaryText, action: .enterKey)
        case .waitingLimit:
            ThoughtStateNote(icon: .hourglass, text: status.message ?? Self.limitText(status.retryAt), tint: .paplySecondaryText)
        case .waitingBudget:
            ThoughtStateNote(icon: .hourglass, text: status.message ?? "Gesichert · Kontingent für heute erreicht", tint: .paplySecondaryText)
        case .needsAttention:
            ThoughtStateNote(icon: .triangleAlert, text: status.message ?? "Ton gesichert · nicht verschriftlicht", tint: .paplyBeak, action: .retry)
        case .done where textIsRaw:
            ThoughtStateNote(icon: .quote, text: "Nicht geordnet · Original-Wortlaut", tint: .paplySecondaryText, action: .reorganize)
        default:
            nil
        }
    }

    private static func limitText(_ retryAt: Date?) -> String {
        guard let retryAt else { return "Gesichert · Groq-Limit, später" }
        return "Gesichert · Groq-Limit, ab ca. \(Format.time.string(from: retryAt))"
    }
}

struct ThoughtStateNote: Equatable {
    enum Action: Equatable { case enterKey, retry, reorganize }
    let icon: Lucide
    let text: String
    let tint: Color
    var action: Action?

    var actionTitle: String? {
        switch action {
        case .enterKey: "Eintragen"
        case .retry: "Erneut versuchen"
        case .reorganize: "Erneut ordnen"
        case nil: nil
        }
    }
}

extension LinkKind {
    /// Wie der ANDERE Gedanke zu diesem steht (Etikett in „Verwandt“)
    func label(incoming: Bool) -> String {
        switch self {
        case .continues: incoming ? "Fortsetzung" : "Vorher"
        case .sameMatter: "Gleiches Anliegen"
        case .changes: incoming ? "Neuer Stand" : "Alter Stand"
        }
    }
}

/// Text zum Teilen (§3.2): Titel, Leerzeile, Text, Leerzeile, „Aufgaben:“ mit ☐/☑.
enum ThoughtShare {
    static func text(_ thought: Thought) -> String {
        var parts = [thought.displayTitle]
        if let text = thought.text, !text.isEmpty { parts.append(text) }
        if !thought.tasks.isEmpty {
            parts.append((["Aufgaben:"] + thought.tasks.map { ($0.done ? "☑ " : "☐ ") + $0.text }).joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Schrift

/// Titel der Navigationsleisten in SF Pro Rounded: groß 31 pt fett (etwas kompakter als 34),
/// inline 17 pt halbfett. Folgt Dynamic Type beim Start.
enum PaplyNavigationBar {
    @MainActor
    static func apply() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: rounded(31, .bold, .largeTitle), .foregroundColor: Brand.text]
        bar.titleTextAttributes = [.font: rounded(17, .semibold, .headline), .foregroundColor: Brand.text]
    }
}

extension View {
    /// Umbruch nur an Wortgrenzen, ohne Silbentrennung: SwiftUI trennt deutsche Wörter in schmalen Spalten
    /// („Taschen-lampe“, „Klau-sel“) und bietet dafür keinen Schalter. Eine Satzsprache ohne Trennregeln
    /// („zxx“ = kein sprachlicher Inhalt) lässt nur die Umbruchstellen zwischen Wörtern übrig.
    func withoutHyphenation() -> some View {
        typesettingLanguage(.explicit(Locale.Language(identifier: "zxx")))
    }
}

extension Font {
    /// Titel mit Charakter: SF Pro Rounded, folgt Dynamic Type
    static func paplyTitle(_ style: Font.TextStyle = .title2, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// Zeit „1:12“ mit festen Ziffernzellen: Jede Ziffer rollt in ihrer eigenen Zelle (numericText),
/// nichts springt oder überlappt, die Breite bleibt gleich.
struct RollingClock: View {
    let seconds: Int
    let font: Font
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let text = ThoughtDate.clock(TimeInterval(seconds))
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, ch in
                if ch.isNumber {
                    // Zelle so breit wie „0“ (Ziffern sind gleich breit), Ziffer darin
                    Text("0").hidden()
                        .overlay {
                            Text(String(ch))
                                .contentTransition(reduce ? .identity : .numericText(countsDown: false))
                                .animation(reduce ? nil : .smooth(duration: 0.28), value: ch)
                        }
                        .clipped()
                } else {
                    Text(String(ch))
                }
            }
        }
        .font(font)
        .monospacedDigit()
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ThoughtDate.spokenClock(TimeInterval(seconds)))
    }
}

// MARK: - Datum

enum ThoughtDate {
    private static let locale = Locale(identifier: "de_DE")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }

    static let weekday = formatter("EEEE")
    static let dayMonth = formatter("ddMM")
    static let dayMonthYear = formatter("ddMMyy")
    static let month = formatter("MMMM")
    static let monthYear = formatter("MMMMyyyy")
    /// „Di., 27. Okt.“
    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "EE, d. MMM"
        return f
    }()

    static let longDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "EEEE, d. MMM"
        return f
    }()

    nonisolated(unsafe) static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        return f
    }()

    /// Kurz und ohne Jahr, wo es passt: heute „08:14“, „Gestern“, Wochentag, „12.10.“, „12.10.25“
    static func compact(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        if date >= today { return Format.time.string(from: date) }
        if date >= today.addingTimeInterval(-86_400) { return "Gestern" }
        if date >= today.addingTimeInterval(-6 * 86_400) { return weekday.string(from: date) }
        return calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? dayMonth.string(from: date) : dayMonthYear.string(from: date)
    }

    /// Karte: heute „08:14“, „Gestern“, Wochentag kurz „Mo.“, sonst „14. Sept.“ (anderes Jahr „14.09.25“)
    static func card(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        if date >= today { return Format.time.string(from: date) }
        if date >= today.addingTimeInterval(-86_400) { return "Gestern" }
        if date >= today.addingTimeInterval(-6 * 86_400) { return weekdayShort.string(from: date) }
        return calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? dayMonthShort.string(from: date) : dayMonthYear.string(from: date)
    }

    /// „Mo.“
    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "EE"
        return f
    }()

    /// „14. Sept.“
    static let dayMonthShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d. MMM"
        return f
    }()

    /// „1:12 Min.“ bzw. „42 Sek.“
    static func duration(ms: Int) -> String {
        let seconds = max(0, Int((Double(ms) / 1000).rounded()))
        if seconds < 60 { return "\(seconds) Sek." }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) Min."
    }

    /// Uhr der Aufnahme „1:12“
    static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    /// VoiceOver: „1 Minute, 12 Sekunden“
    static func spokenClock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let m = seconds / 60, s = seconds % 60
        let minutes = m == 1 ? "1 Minute" : "\(m) Minuten"
        let secs = s == 1 ? "1 Sekunde" : "\(s) Sekunden"
        return m == 0 ? secs : "\(minutes), \(secs)"
    }
}

/// Abschnitt der Liste („Heute“, „Gestern“, „Vorherige 7 Tage“, „Vorherige 30 Tage“, Monate).
struct ThoughtSection: Identifiable {
    enum Kind { case today, yesterday, week, month30, month }
    let id: String
    let title: String
    let kind: Kind
    var thoughts: [Thought]

    /// Zeit in der Zeile: heute/gestern Uhrzeit, Woche Wochentag, älter Datum
    func timeLabel(_ date: Date, thisYear: Int) -> String {
        switch kind {
        case .today, .yesterday: return Format.time.string(from: date)
        case .week: return ThoughtDate.weekday.string(from: date)
        case .month30, .month:
            let year = Calendar.current.component(.year, from: date)
            return year == thisYear ? ThoughtDate.dayMonth.string(from: date) : ThoughtDate.dayMonthYear.string(from: date)
        }
    }
}

enum ThoughtSections {
    /// O(n) mit reinen Datumsvergleichen; Kalender nur an Monatsgrenzen. Erwartet „neueste zuerst“,
    /// verkraftet aber auch Ausreißer.
    static func make(_ thoughts: [Thought], now: Date = Date()) -> [ThoughtSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let month30 = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let thisYear = calendar.component(.year, from: now)

        var sections: [ThoughtSection] = []
        var index: [String: Int] = [:]
        var monthStart = Date.distantFuture
        var monthKey = ""
        var monthTitle = ""

        for thought in thoughts {
            let date = thought.createdAt
            let key: String
            let title: String
            let kind: ThoughtSection.Kind
            if date >= today {
                (key, title, kind) = ("today", "Heute", .today)
            } else if date >= yesterday {
                (key, title, kind) = ("yesterday", "Gestern", .yesterday)
            } else if date >= week {
                (key, title, kind) = ("week", "Vorherige 7 Tage", .week)
            } else if date >= month30 {
                (key, title, kind) = ("month30", "Vorherige 30 Tage", .month30)
            } else {
                if !(date >= monthStart && date < (calendar.date(byAdding: .month, value: 1, to: monthStart) ?? .distantFuture)) {
                    let parts = calendar.dateComponents([.year, .month], from: date)
                    monthStart = calendar.date(from: parts) ?? date
                    monthKey = "m\(parts.year ?? 0)-\(parts.month ?? 0)"
                    monthTitle = (parts.year == thisYear ? ThoughtDate.month : ThoughtDate.monthYear).string(from: monthStart)
                }
                (key, title, kind) = (monthKey, monthTitle, .month)
            }
            if let i = index[key] {
                sections[i].thoughts.append(thought)
            } else {
                index[key] = sections.count
                sections.append(ThoughtSection(id: key, title: title, kind: kind, thoughts: [thought]))
            }
        }
        return sections
    }
}

// MARK: - Navigation und Hinweise

/// Reiter: Gedanken | Aufgaben | Diktat
enum RootTab: Hashable { case thoughts, tasks, dictation }

enum ThoughtsRoute: Hashable {
    /// `zoom`: Kennung der Karte bzw. Zeile, aus der das Detail heraus-zoomt (nil = normal schieben)
    case thought(String, task: String? = nil, zoom: String? = nil)
    case search
    case topics
    case deleted
    case buttonGuide
}

/// Was die Startseite zeigt: Übersicht der Karte oder ein Thema (Karte hineingezoomt, Panel offen).
/// Die Aufgaben sind ein eigener Reiter (`RootTab.tasks`).
enum ThoughtsFilter: Hashable {
    case all
    case topic(String)
}

/// Raststufen des Themen-Panels (wie Apple Karten)
enum PanelDetent: Int, Comparable, CaseIterable {
    case small, medium, large
    static func < (a: PanelDetent, b: PanelDetent) -> Bool { a.rawValue < b.rawValue }
}

/// Für `.sheet(item:)` mit einer Kennung
struct SheetID: Identifiable, Hashable {
    let id: String
}

struct ThoughtsToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var undo: UndoToken?
    var seconds: Double = 1.4
}

/// Zustand der Oberfläche, den mehrere Stellen setzen (Tab, Pfad, Filter, Blätter, Hinweise).
@MainActor
@Observable
final class ThoughtsNav {
    /// Navigationsstapel, in dem eine Ansicht steht (Detail aus dem Reiter Gedanken oder Aufgaben)
    enum Stack: Hashable { case thoughts, tasks }

    var tab: RootTab = .thoughts
    /// Stapel des Reiters Gedanken
    var path: [ThoughtsRoute] = []
    /// Stapel des Reiters Aufgaben
    var tasksPath: [ThoughtsRoute] = []
    var filter: ThoughtsFilter = .all {
        didSet {
            // Ein Thema aus der Übersicht öffnet das Panel in mittlerer Höhe
            if case .topic = filter, filter != oldValue, oldValue == .all || panelDetent == .small {
                panelDetent = .medium
            }
        }
    }
    /// Höhe des Themen-Panels
    var panelDetent: PanelDetent = .medium
    var searchText = ""
    var showSettings = false
    /// Abschnitt der Einstellungen, zu dem das Blatt beim Öffnen rollt (z. B. `SettingsView.betaAnchor`)
    var settingsFocus: String?
    /// Themenwahl für diesen Gedanken
    var topicPicker: SheetID?
    private(set) var toast: ThoughtsToast?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func open(_ id: String, task: String? = nil) {
        tab = .thoughts
        path = [.thought(id, task: task)]
    }

    /// Im Stapel, in dem die Ansicht steht, eine Seite weiter (z. B. „Verwandt“ im Detail)
    func push(_ route: ThoughtsRoute, on stack: Stack) {
        switch stack {
        case .thoughts: path.append(route)
        case .tasks: tasksPath.append(route)
        }
    }

    /// Reiter Aufgaben, an seinem Anfang
    func showTasks() {
        tab = .tasks
        tasksPath = []
    }

    /// Thema im Panel zeigen (Karte zoomt hinein)
    func focus(_ topicID: String?) {
        filter = topicID.map { .topic($0) } ?? .all
    }

    var focusedTopic: String? {
        if case .topic(let id) = filter { return id }
        return nil
    }

    func show(_ toast: ThoughtsToast, reduceMotion: Bool = false) {
        toastTask?.cancel()
        withAnimation(PaplyMotion.bouncy(reduceMotion)) { self.toast = toast }
        let id = toast.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(toast.seconds))
            guard !Task.isCancelled, let self, self.toast?.id == id else { return }
            withAnimation(PaplyMotion.smooth(reduceMotion)) { self.toast = nil }
        }
    }

    func hideToast() {
        toastTask?.cancel()
        withAnimation(.paplySmooth) { toast = nil }
    }
}

extension EnvironmentValues {
    /// Namensraum für den Zoom-Übergang Aufnahme-Knopf/Leiste/Zeile ↔ große Aufnahme-Ansicht
    @Entry var captureZoom: Namespace.ID?
    /// Stapel, in dem die Ansicht steht (Reiter Gedanken oder Aufgaben)
    @Entry var thoughtsStack: ThoughtsNav.Stack = .thoughts
}

extension View {
    /// Quelle eines Zoom-Übergangs, falls ein Namensraum gesetzt ist
    @ViewBuilder
    func captureZoomSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Schimmer („Wird geordnet …“, §4)

/// Heller Verlauf, der in 1,4 s linear über den Platzhalter läuft (Deckkraft 0,35).
struct ShimmerModifier: ViewModifier {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        if active, !reduce {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                    let phase = CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4)
                    GeometryReader { geo in
                        let band: CGFloat = max(geo.size.width * 0.5, 60)
                        let travel: CGFloat = geo.size.width + band
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: travel * phase - band)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View { modifier(ShimmerModifier(active: active)) }
}

// MARK: - Schütteln (§4: 0/−7/6/−4/2/0 pt in 440 ms)

struct ShakeModifier: ViewModifier {
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        if reduce {
            content
        } else {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                LinearKeyframe(-7, duration: 0.088)
                LinearKeyframe(6, duration: 0.088)
                LinearKeyframe(-4, duration: 0.088)
                LinearKeyframe(2, duration: 0.088)
                LinearKeyframe(0, duration: 0.088)
            }
        }
    }
}

extension View {
    func shake(_ trigger: Int) -> some View { modifier(ShakeModifier(trigger: trigger)) }
}

// MARK: - Hinweis unten („Gelöscht · Widerrufen“, „Kopiert“)

struct ThoughtsToastHost: View {
    @Environment(ThoughtsNav.self) private var nav
    @Environment(ThoughtsModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        ZStack {
            if let toast = nav.toast {
                Group {
                    if let token = toast.undo {
                        HStack(spacing: 16) {
                            Text(toast.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.paplyText)
                            Button {
                                withAnimation(PaplyMotion.smooth(reduce)) { model.undo(token) }
                                nav.hideToast()
                            } label: {
                                Text("Widerrufen")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.paplyGreenBright)
                            }
                            .sensoryFeedback(.success, trigger: nav.toast?.id) { _, new in new == nil }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .paplyGlass(.bar)
                    } else {
                        ToastView(text: toast.text)
                    }
                }
                .id(toast.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(.bottom, 14)
    }
}

// MARK: - Start (Datenquelle, Debug-Optionen)

/// Welche Daten die Oberfläche nutzt. Im Debug: `-PaplyPreviewData` (ThoughtsModel.preview),
/// `-PaplyEmpty`, `-PaplyMany` (2 000 Gedanken), `-PaplyClassic` (iOS-18-Look auf iOS 26).
enum ThoughtsLaunch {
    static var forceClassic: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PaplyClassic")
        #else
        false
        #endif
    }

    @MainActor
    static func makeModel() -> ThoughtsModel {
        #if DEBUG
        if let model = ThoughtsDebug.model() { return model }
        #endif
        return ThoughtsModel.shared
    }

    @MainActor
    static func makeDriver(model: ThoughtsModel) -> any CaptureDriving {
        #if DEBUG
        if let driver = ThoughtsDebug.driver(model: model) { return driver }
        #endif
        return ThoughtCapture.shared
    }
}
