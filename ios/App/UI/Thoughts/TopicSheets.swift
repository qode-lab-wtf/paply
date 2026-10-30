import PaplyKit
import PhotosUI
import SwiftUI
import UIKit

// Themenwahl, neues Thema, Symbolraster, Bild statt Symbol und die Themen-Aktionen (KONZEPT §3.1, §3.2, §3.8).

// MARK: - Themenwahl (mittlere Höhe)

struct TopicPickerSheet: View {
    let thoughtID: String
    @Environment(ThoughtsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var query = ""
    @State private var creating = false
    @State private var chosen = 0

    private var current: String? { model.thought(thoughtID)?.topicId }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Button { choose(nil) } label: {
                            pickRow(title: "Ohne Thema", count: nil, selected: current == nil, icon: nil)
                        }
                    }
                    .listRowBackground(Color.paplyRow)
                }
                Section {
                    ForEach(filtered) { topic in
                        Button { choose(topic.id) } label: {
                            pickRow(title: topic.title, count: model.count(of: topic.id),
                                    selected: current == topic.id, icon: topic.icon, topicID: topic.id)
                        }
                    }
                    Button {
                        creating = true
                    } label: {
                        HStack(spacing: 12) {
                            LucideImage(.circlePlus, size: 22, stroke: 1.8)
                                .frame(width: 30, height: 30)
                            Text(query.isEmpty ? "Neues Thema …" : "„\(query)“ anlegen …")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(Color.paplyGreenBright)
                    }
                }
                .listRowBackground(Color.paplyRow)
            }
            .paplySheetBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Thema suchen")
            .navigationTitle("Thema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $creating) {
                TopicEditor(mode: .create(prefill: query)) { result in
                    let made = model.createOrReuseTopic(title: result.title, icon: result.icon, note: result.note)
                    if !made.existed { TopicImages.shared.apply(result.image, to: made.topic.id) }
                    choose(made.topic.id)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: chosen)
    }

    private var filtered: [Topic] {
        let sorted = model.topics.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func pickRow(title: String, count: Int?, selected: Bool, icon: TopicIcon?, topicID: String? = nil) -> some View {
        HStack(spacing: 12) {
            if let icon {
                TopicBadge(icon: icon, size: 30, topicID: topicID)
            } else {
                LucideImage(.circleDashed, size: 17, stroke: 1.9, scales: false)
                    .foregroundStyle(Color.paplySecondaryText)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
            }
            Text(title)
                .foregroundStyle(Color.paplyText)
            Spacer()
            if let count {
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(Color.paplyTertiaryText)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.paplyGreenBright)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose(_ topicID: String?) {
        withAnimation(PaplyMotion.smooth(reduce)) { model.setTopic(thoughtID, topicID: topicID) }
        chosen += 1
        Task {
            try? await Task.sleep(for: .seconds(0.12))
            dismiss()
        }
    }
}

// MARK: - Thema anlegen / bearbeiten (Name, Beschreibung, Bild oder Symbol)

struct TopicEditor: View {
    enum Mode {
        case create(prefill: String)
        case edit(Topic)
    }

    /// Was beim Sichern übernommen wird
    struct Result {
        let title: String
        let icon: TopicIcon
        /// „Worum geht's?“; nil = keine
        let note: String?
        let image: TopicImageChange
    }

    let mode: Mode
    let onDone: (Result) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var name: String
    @State private var icon: TopicIcon
    @State private var note: String
    @State private var image: TopicImageChange = .unchanged
    /// Vorschau des neu gewählten Bilds
    @State private var preview: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadingImage = false
    @State private var imageFailed = false
    @FocusState private var nameFocused: Bool

    init(mode: Mode, onDone: @escaping (Result) -> Void) {
        self.mode = mode
        self.onDone = onDone
        switch mode {
        case .create(let prefill):
            _name = State(initialValue: prefill)
            _icon = State(initialValue: .sparkles)
            _note = State(initialValue: "")
        case .edit(let topic):
            _name = State(initialValue: topic.title)
            _icon = State(initialValue: topic.icon)
            _note = State(initialValue: topic.describedNote ?? "")
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var topicID: String? {
        if case .edit(let topic) = mode { return topic.id }
        return nil
    }

    /// Bild, das nach dem Sichern gilt (neu gewählt, bisheriges oder keins)
    private var shownImage: UIImage? {
        switch image {
        case .set: preview
        case .remove: nil
        case .unchanged: TopicImages.shared.image(for: topicID)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    badge
                    TextField("Name", text: $name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.paplyText)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.paplyRow)
            Section {
                TextField("Namen, Firmen, Personen – damit Paply Gedanken richtig zuordnet", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .foregroundStyle(Color.paplyText)
                    .onChange(of: note) { _, value in
                        if value.count > Topic.maxNoteLength { note = String(value.prefix(Topic.maxNoteLength)) }
                    }
            } header: {
                Text("Worum geht's?")
            } footer: {
                if note.count > Topic.maxNoteLength - 40 {
                    Text("Noch \(Topic.maxNoteLength - note.count) Zeichen")
                        .monospacedDigit()
                }
            }
            .listRowBackground(Color.paplyRow)
            Section {
                PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .current) {
                    Label("Bild wählen …", systemImage: "photo.on.rectangle")
                        .foregroundStyle(Color.paplyGreenBright)
                }
                .disabled(loadingImage)
                if shownImage != nil {
                    Button(role: .destructive) {
                        withAnimation(PaplyMotion.smooth(reduce)) {
                            image = .remove
                            preview = nil
                        }
                    } label: {
                        Label("Bild entfernen", systemImage: "trash")
                            .foregroundStyle(Color.paplyDanger)
                    }
                }
            } header: {
                Text("Bild")
            } footer: {
                Text("Ein Foto, z. B. ein Logo, ersetzt das Symbol. Es bleibt auf diesem iPhone und geht nie an die KI.")
            }
            .listRowBackground(Color.paplyRow)
            Section {
                TopicIconGrid(selection: $icon)
                    .padding(.vertical, 6)
            } header: {
                Text("Symbol")
            } footer: {
                if shownImage != nil {
                    Text("Erscheint, wo kein Bild Platz hat, z. B. auf dem Sperrbildschirm.")
                }
            }
            .listRowBackground(Color.paplyRow)
        }
        .paplySheetBackground()
        .navigationTitle(isCreate ? "Neues Thema" : "Thema")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isCreate ? "Anlegen" : "Sichern", action: save)
                    .fontWeight(.semibold)
                    .disabled(trimmed.isEmpty || loadingImage)
            }
        }
        .onAppear { if isCreate { nameFocused = true } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            load(item)
        }
        .alert("Bild ließ sich nicht öffnen", isPresented: $imageFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte ein anderes Foto wählen.")
        }
        .sensoryFeedback(.selection, trigger: preview)
    }

    /// Kennung oben: Bild (rund abgerundet, Rand in Themenfarbe) oder Symbol auf Mint-Gold; beim Laden ein Kreisel
    private var badge: some View {
        ZStack {
            if let shownImage {
                TopicImageTile(image: shownImage, topicID: topicID, size: 44, cornerRatio: 0.27)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                TopicBadge(icon: icon, size: 44)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if loadingImage {
                RoundedRectangle(cornerRadius: 44 * 0.27, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 44, height: 44)
                ProgressView()
                    .tint(Color.paplyText)
            }
        }
        .animation(.paplyBouncy, value: icon)
        .animation(PaplyMotion.smooth(reduce), value: shownImage != nil)
        .accessibilityHidden(true)
    }

    private func load(_ item: PhotosPickerItem) {
        loadingImage = true
        Task {
            var jpeg: Data?
            if let data = try? await item.loadTransferable(type: Data.self) {
                jpeg = await TopicImages.process(data)
            }
            loadingImage = false
            pickerItem = nil
            guard let jpeg, let picked = UIImage(data: jpeg) else {
                imageFailed = true
                return
            }
            withAnimation(PaplyMotion.smooth(reduce)) {
                image = .set(jpeg)
                preview = picked
            }
        }
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private func save() {
        guard !trimmed.isEmpty, !loadingImage else { return }
        onDone(Result(title: trimmed, icon: icon, note: Topic.normalizedNote(note), image: image))
        if !isCreate { dismiss() }
    }
}

/// Raster mit den 24 Themen-Symbolen
struct TopicIconGrid: View {
    @Binding var selection: TopicIcon
    @ScaledMetric(relativeTo: .body) private var cell: CGFloat = 44

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell + 12), spacing: 10)], spacing: 10) {
            ForEach(TopicIcon.allCases, id: \.self) { icon in
                let selected = icon == selection
                Button {
                    withAnimation(.paplySmooth) { selection = icon }
                } label: {
                    TopicGlyph(key: icon.rawValue, size: cell * 0.46, stroke: selected ? 2 : 1.7, scales: false)
                        .foregroundStyle(selected ? Color.paplyForest : Color.paplyText.opacity(0.85))
                        .frame(width: cell, height: cell)
                        .background {
                            if selected {
                                Circle().fill(ThoughtTint.fill)
                            } else {
                                Circle().fill(Color.white.opacity(0.08))
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .accessibilityLabel(icon.spokenName)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Zusammenführen mit …

struct TopicMergeSheet: View {
    let source: Topic
    let onMerge: (Topic) -> Void
    @Environment(ThoughtsModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.topics.filter { $0.id != source.id }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) { topic in
                        Button {
                            onMerge(topic)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                TopicBadge(icon: topic.icon, size: 30, topicID: topic.id)
                                Text(topic.title).foregroundStyle(Color.paplyText)
                                Spacer()
                                Text("\(model.count(of: topic.id))")
                                    .monospacedDigit()
                                    .foregroundStyle(Color.paplyTertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } footer: {
                    Text("Die Gedanken aus „\(source.title)“ kommen zum gewählten Thema. Danach lässt es sich widerrufen.")
                }
                .listRowBackground(Color.paplyRow)
            }
            .paplySheetBackground()
            .navigationTitle("Zusammenführen mit …")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Themen-Aktionen an einer Stelle

struct TopicDeletion {
    let topics: [Topic]
    var multiple: Bool { topics.count > 1 }

    var title: String {
        if multiple { return "\(topics.count) Themen löschen?" }
        return topics.first.map { "„\($0.title)“ löschen?" } ?? "Thema löschen?"
    }
}

/// Dieselbe Rückfrage für Themen-Chips, Wischen und Mehrfachauswahl.
private struct TopicDeletionModifier: ViewModifier {
    @Binding var choice: TopicDeletion?
    var onDeleted: () -> Void
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var successPulse = 0

    private var count: Int { choice?.topics.reduce(0) { $0 + model.count(of: $1.id) } ?? 0 }
    private var noun: String { choice?.multiple == true ? "Themen" : "Thema" }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(choice?.title ?? "Thema löschen?", isPresented: Binding(
                get: { choice != nil }, set: { if !$0 { choice = nil } }
            ), titleVisibility: .visible) {
                if count > 0 {
                    Button("Nur \(noun) löschen") { delete(withThoughts: false) }
                    Button("\(noun) und \(count) Gedanken löschen", role: .destructive) { delete(withThoughts: true) }
                } else {
                    Button("\(noun) löschen", role: .destructive) { delete(withThoughts: false) }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                if count > 0 {
                    Text(count == 1
                         ? "Bei „Nur \(noun) löschen“ bleibt der Gedanke, nur ohne Thema. Sonst liegt er 30 Tage unter „Zuletzt gelöscht“."
                         : "Bei „Nur \(noun) löschen“ bleiben die Gedanken, nur ohne Thema. Sonst liegen sie 30 Tage unter „Zuletzt gelöscht“.")
                }
            }
            .sensoryFeedback(.success, trigger: successPulse)
    }

    private func delete(withThoughts: Bool) {
        guard let choice else { return }
        let ids = Set(choice.topics.map(\.id))
        let focused = nav.focusedTopic.flatMap { model.topic($0)?.id }
        withAnimation(PaplyMotion.smooth(reduce)) {
            if let focused, ids.contains(focused) { nav.focus(nil) }
            model.deleteTopics(ids, withThoughts: withThoughts)
            onDeleted()
        }
        successPulse += 1
    }
}

/// Umbenennen (Hinweisfenster mit Feld), Bild oder Symbol (Blatt), Zusammenführen (Blatt), Löschen (Rückfrage).
struct TopicActionsModifier: ViewModifier {
    @Binding var action: TopicAction?
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var renameDraft = ""
    @State private var successPulse = 0

    private var renaming: Binding<Bool> {
        Binding(get: { if case .rename = action { true } else { false } }, set: { if !$0 { action = nil } })
    }

    private var deleting: Binding<TopicDeletion?> {
        Binding(get: {
            if case .delete(let topic) = action { TopicDeletion(topics: [topic]) } else { nil }
        }, set: { if $0 == nil { action = nil } })
    }

    private var iconSheet: Binding<SheetID?> {
        Binding(get: { if case .icon(let t) = action { SheetID(id: t.id) } else { nil } }, set: { if $0 == nil { action = nil } })
    }

    private var mergeSheet: Binding<SheetID?> {
        Binding(get: { if case .merge(let t) = action { SheetID(id: t.id) } else { nil } }, set: { if $0 == nil { action = nil } })
    }

    func body(content: Content) -> some View {
        content
            .alert("Thema umbenennen", isPresented: renaming) {
                TextField("Name", text: $renameDraft)
                Button("Abbrechen", role: .cancel) {}
                Button("Umbenennen") {
                    let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if case .rename(let topic) = action, !name.isEmpty { model.renameTopic(topic.id, title: name) }
                }
            }
            .topicDeletion(deleting)
            .sheet(item: iconSheet) { item in
                if let topic = model.topic(item.id) {
                    NavigationStack {
                        TopicEditor(mode: .edit(topic)) { result in
                            TopicEditing.apply(result, to: topic, model: model)
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .preferredColorScheme(.dark)
                }
            }
            .sheet(item: mergeSheet) { item in
                if let topic = model.topic(item.id) {
                    TopicMergeSheet(source: topic) { target in merge(topic, into: target) }
                }
            }
            .onChange(of: action?.id) { _, _ in
                if case .rename(let topic) = action { renameDraft = topic.title }
            }
            .sensoryFeedback(.success, trigger: successPulse)
    }

    private func merge(_ source: Topic, into target: Topic) {
        var token: UndoToken?
        withAnimation(PaplyMotion.smooth(reduce)) {
            token = model.mergeTopics([source.id, target.id], into: target.id, title: nil)
        }
        if nav.filter == .topic(source.id) { nav.filter = .topic(target.id) }
        successPulse += 1
        guard let token else { return }
        nav.show(ThoughtsToast(text: "Zusammengeführt", undo: token, seconds: 5), reduceMotion: reduce)
        ThoughtsUndo.register(undoManager, name: "Zusammenführen", model: model, token: token)
    }
}

/// Ergebnis des Bearbeiten-Blatts auf ein bestehendes Thema anwenden (nur, was sich geändert hat)
enum TopicEditing {
    @MainActor
    static func apply(_ result: TopicEditor.Result, to topic: Topic, model: ThoughtsModel) {
        if result.title != topic.title { model.renameTopic(topic.id, title: result.title) }
        if result.icon != topic.icon { model.setTopicIcon(topic.id, result.icon) }
        if result.note != topic.describedNote { model.setTopicNote(topic.id, result.note) }
        TopicImages.shared.apply(result.image, to: topic.id)
    }
}

extension View {
    func topicDeletion(_ choice: Binding<TopicDeletion?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(TopicDeletionModifier(choice: choice, onDeleted: onDeleted))
    }

    func topicActions(_ action: Binding<TopicAction?>) -> some View {
        modifier(TopicActionsModifier(action: action))
    }
}

/// Schütteln = Widerrufen (System-Undo) zusätzlich zum Hinweis unten – so lange wie der Hinweis: Läuft er ab,
/// trägt `forget` die Aktion wieder aus (das Modell hat sie dann vergessen).
@MainActor
enum ThoughtsUndo {
    /// je Aktion ein eigenes Ziel, damit sie sich einzeln austragen lässt (UndoManager hält Ziele nicht fest)
    private final class Target {}

    private struct Entry {
        weak var manager: UndoManager?
        let target: Target
    }

    private static var entries: [UndoToken: Entry] = [:]

    static func register(_ manager: UndoManager?, name: String, model: ThoughtsModel, token: UndoToken) {
        guard let manager else { return }
        let target = Target()
        entries[token] = Entry(manager: manager, target: target)
        // Ziel bleibt bis `forget` gehalten (der Hinweis endet immer – auch nach Schütteln)
        manager.registerUndo(withTarget: target) { _ in
            MainActor.assumeIsolated { model.undo(token) }
        }
        manager.setActionName(name)
    }

    static func forget(_ token: UndoToken) {
        guard let entry = entries.removeValue(forKey: token) else { return }
        entry.manager?.removeAllActions(withTarget: entry.target)
    }
}
