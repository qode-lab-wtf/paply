import PaplyKit
import SwiftUI

// Themenwahl, neues Thema, Symbolraster und die Themen-Aktionen (KONZEPT §3.1, §3.2, §3.8).

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
                                    selected: current == topic.id, icon: topic.icon)
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
                TopicEditor(mode: .create(prefill: query)) { title, icon in
                    let topic = model.createTopic(title: title, icon: icon)
                    choose(topic.id)
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

    private func pickRow(title: String, count: Int?, selected: Bool, icon: TopicIcon?) -> some View {
        HStack(spacing: 12) {
            if let icon {
                TopicBadge(icon: icon, size: 30)
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

// MARK: - Thema anlegen / bearbeiten (Name + Symbolraster)

struct TopicEditor: View {
    enum Mode {
        case create(prefill: String)
        case edit(Topic)
    }

    let mode: Mode
    let onDone: (String, TopicIcon) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: TopicIcon
    @FocusState private var nameFocused: Bool

    init(mode: Mode, onDone: @escaping (String, TopicIcon) -> Void) {
        self.mode = mode
        self.onDone = onDone
        switch mode {
        case .create(let prefill):
            _name = State(initialValue: prefill)
            _icon = State(initialValue: .sparkles)
        case .edit(let topic):
            _name = State(initialValue: topic.title)
            _icon = State(initialValue: topic.icon)
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    TopicBadge(icon: icon, size: 44)
                        .animation(.paplyBouncy, value: icon)
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
                TopicIconGrid(selection: $icon)
                    .padding(.vertical, 6)
            } header: {
                Text("Symbol")
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
                    .disabled(trimmed.isEmpty)
            }
        }
        .onAppear { if isCreate { nameFocused = true } }
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onDone(trimmed, icon)
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
                                TopicBadge(icon: topic.icon, size: 30)
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

/// Umbenennen (Hinweisfenster mit Feld), Symbol (Blatt), Zusammenführen (Blatt), Löschen (Rückfrage).
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

    private var deleting: Binding<Bool> {
        Binding(get: { if case .delete = action { true } else { false } }, set: { if !$0 { action = nil } })
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
            .confirmationDialog(deleteTitle, isPresented: deleting, titleVisibility: .visible) {
                Button("Thema löschen", role: .destructive) {
                    if case .delete(let topic) = action {
                        if nav.filter == .topic(topic.id) { nav.filter = .all }
                        withAnimation(PaplyMotion.smooth(reduce)) { model.deleteTopic(topic.id) }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            .sheet(item: iconSheet) { item in
                if let topic = model.topic(item.id) {
                    NavigationStack {
                        TopicEditor(mode: .edit(topic)) { title, icon in
                            if title != topic.title { model.renameTopic(topic.id, title: title) }
                            if icon != topic.icon { model.setTopicIcon(topic.id, icon) }
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

    private var deleteTitle: String {
        if case .delete(let topic) = action { return "„\(topic.title)“ löschen?" }
        return "Thema löschen?"
    }

    private var deleteMessage: String {
        guard case .delete(let topic) = action else { return "" }
        let n = model.count(of: topic.id)
        return n == 1 ? "1 Gedanke bleibt, nur ohne Thema." : "\(n) Gedanken bleiben, nur ohne Thema."
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

extension View {
    func topicActions(_ action: Binding<TopicAction?>) -> some View {
        modifier(TopicActionsModifier(action: action))
    }
}

/// Schütteln = Widerrufen (System-Undo) zusätzlich zum Hinweis unten
enum ThoughtsUndo {
    @MainActor
    static func register(_ manager: UndoManager?, name: String, model: ThoughtsModel, token: UndoToken) {
        guard let manager else { return }
        manager.registerUndo(withTarget: model) { model in
            MainActor.assumeIsolated { model.undo(token) }
        }
        manager.setActionName(name)
    }
}
