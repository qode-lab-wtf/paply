import PaplyKit
import SwiftUI

// Themen bearbeiten (KONZEPT §3.8): Vorschläge zum Zusammenführen, Themen nach Name, vorläufige
// Themen im Abschnitt „Neu“. Bearbeiten-Modus: mehrere wählen → „Zusammenführen“.

struct TopicsEditView: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(ThoughtsNav.self) private var nav
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var editing: Topic?
    @State private var deleting: Topic?
    @State private var mergeChoice: MergeChoice?
    @State private var successPulse = 0

    private struct MergeChoice: Identifiable {
        let id = UUID()
        let topics: [Topic]
    }

    private var sorted: [Topic] {
        model.topics.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        let active = sorted.filter { model.isActive($0) }
        let provisional = sorted.filter { !model.isActive($0) }
        List(selection: $selection) {
            if !model.suggestions.isEmpty, !editMode.isEditing {
                Section {
                    ForEach(model.suggestions.prefix(2)) { suggestion in
                        SuggestionCard(suggestion: suggestion) {
                            accept(suggestion)
                        } onDecline: {
                            withAnimation(PaplyMotion.smooth(reduce)) { model.decline(suggestion) }
                        }
                        .listRowBackground(Color.paplyRow)
                        .selectionDisabled()
                    }
                } header: {
                    header("Vorschläge")
                }
            }

            Section {
                ForEach(active) { topic in
                    topicRow(topic)
                        .tag(topic.id)
                }
            } header: {
                header("Themen")
            } footer: {
                if active.isEmpty {
                    Text("Themen entstehen von selbst, sobald zwei Gedanken zusammenpassen.")
                }
            }

            if !provisional.isEmpty {
                Section {
                    ForEach(provisional) { topic in
                        topicRow(topic, provisional: true)
                            .tag(topic.id)
                    }
                } header: {
                    header("Neu")
                } footer: {
                    Text("Vorläufige Themen mit einem Gedanken. Als Chip erscheinen sie, sobald ein zweiter dazukommt – oder wenn du sie behältst. Umbenennen allein behält sie nicht.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PaplyBackground())
        .environment(\.editMode, $editMode)
        .navigationTitle("Themen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Fertig" : "Auswählen") {
                    withAnimation(PaplyMotion.smooth(reduce)) {
                        editMode = editMode.isEditing ? .inactive : .active
                        selection.removeAll()
                    }
                }
                .fontWeight(editMode.isEditing ? .semibold : .regular)
            }
            if editMode.isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        mergeChoice = MergeChoice(topics: sorted.filter { selection.contains($0.id) })
                    } label: {
                        Text(selection.count >= 2 ? "\(selection.count) zusammenführen" : "Zusammenführen")
                            .fontWeight(.semibold)
                    }
                    .disabled(selection.count < 2)
                }
            }
        }
        .sheet(item: $editing) { topic in
            NavigationStack {
                TopicEditor(mode: .edit(topic)) { title, icon in
                    if title != topic.title { model.renameTopic(topic.id, title: title) }
                    if icon != topic.icon { model.setTopicIcon(topic.id, icon) }
                }
            }
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
        .sheet(item: $mergeChoice) { choice in
            MergeNameSheet(topics: choice.topics) { target in
                merge(choice.topics.map(\.id), into: target)
            }
        }
        .confirmationDialog(deleting.map { "„\($0.title)“ löschen?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Thema löschen", role: .destructive) {
                if let topic = deleting {
                    if nav.filter == .topic(topic.id) { nav.filter = .all }
                    withAnimation(PaplyMotion.smooth(reduce)) { model.deleteTopic(topic.id) }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            if let topic = deleting {
                let n = model.count(of: topic.id)
                Text(n == 1 ? "1 Gedanke bleibt, nur ohne Thema." : "\(n) Gedanken bleiben, nur ohne Thema.")
            }
        }
        .sensoryFeedback(.success, trigger: successPulse)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(Color.paplyText)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func topicRow(_ topic: Topic, provisional: Bool = false) -> some View {
        let count = model.count(of: topic.id)
        return HStack(spacing: 12) {
            TopicBadge(icon: topic.icon, size: 32)
            Text(topic.title)
                .foregroundStyle(Color.paplyText)
                .lineLimit(2)
            Spacer(minLength: 8)
            if provisional, !editMode.isEditing {
                // Nur „Behalten“ macht ein vorläufiges Thema aktiv (Umbenennen/Symbol nicht, §3.8)
                Button {
                    withAnimation(PaplyMotion.smooth(reduce)) { model.keepProvisional(topic.id) }
                    successPulse += 1
                } label: {
                    Text("Behalten")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paplyForest)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.paplyGreenBright))
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Macht das Thema dauerhaft und zeigt es als Chip")
            } else {
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(Color.paplyTertiaryText)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !editMode.isEditing else { return }
            editing = topic
        }
        .listRowBackground(Color.paplyRow)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleting = topic
            } label: {
                Label(provisional ? "Auflösen" : "Löschen", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.title), \(count == 1 ? "1 Gedanke" : "\(count) Gedanken")")
        .accessibilityAction(named: "Bearbeiten") { editing = topic }
    }

    private func accept(_ suggestion: TopicSuggestion) {
        withAnimation(PaplyMotion.smooth(reduce)) { model.accept(suggestion) }
        successPulse += 1
    }

    private func merge(_ ids: [String], into target: String) {
        var token: UndoToken?
        withAnimation(PaplyMotion.smooth(reduce)) {
            token = model.mergeTopics(ids, into: target, title: nil)
            editMode = .inactive
            selection.removeAll()
        }
        if case .topic(let current) = nav.filter, ids.contains(current) { nav.filter = .topic(target) }
        successPulse += 1
        guard let token else { return }
        nav.show(ThoughtsToast(text: "Zusammengeführt", undo: token, seconds: 5), reduceMotion: reduce)
        ThoughtsUndo.register(undoManager, name: "Zusammenführen", model: model, token: token)
    }
}

/// „Vorschlag: ‚Wohnung‘ und ‚Umzug‘ zusammenführen?“ + Grund + [Zusammenführen] [Nein]
private struct SuggestionCard: View {
    let suggestion: TopicSuggestion
    let onAccept: () -> Void
    let onDecline: () -> Void
    @Environment(ThoughtsModel.self) private var model

    var body: some View {
        let a = model.topic(suggestion.a)?.title ?? "?"
        let b = model.topic(suggestion.b)?.title ?? "?"
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                LucideImage(.merge, size: 17, stroke: 2, relativeTo: .body)
                    .foregroundStyle(ThoughtTint.mint)
                Text("„\(a)“ und „\(b)“ zusammenführen?")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.paplyText)
            }
            if !suggestion.reason.isEmpty {
                Text(suggestion.reason)
                    .font(.subheadline)
                    .foregroundStyle(Color.paplySecondaryText)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button(action: onAccept) {
                    Text("Zusammenführen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paplyForest)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.paplyGreenBright))
                }
                .buttonStyle(.borderless)
                Button(action: onDecline) {
                    Text("Nein")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.paplyText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.borderless)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }
}

/// Namen wählen (Vorauswahl: Thema mit den meisten Gedanken)
private struct MergeNameSheet: View {
    let topics: [Topic]
    let onMerge: (String) -> Void
    @Environment(ThoughtsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(topics) { topic in
                        Button {
                            chosen = topic.id
                        } label: {
                            HStack(spacing: 12) {
                                TopicBadge(icon: topic.icon, size: 30)
                                Text(topic.title).foregroundStyle(Color.paplyText)
                                Spacer()
                                Text("\(model.count(of: topic.id))")
                                    .monospacedDigit()
                                    .foregroundStyle(Color.paplyTertiaryText)
                                Image(systemName: chosen == topic.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen == topic.id ? Color.paplyGreenBright : Color.paplyTertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } header: {
                    Text("Welcher Name bleibt?")
                } footer: {
                    Text("Alle Gedanken kommen unter dieses Thema. Danach lässt es sich widerrufen.")
                }
                .listRowBackground(Color.paplyRow)
            }
            .paplySheetBackground()
            .navigationTitle("Zusammenführen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zusammenführen") {
                        if let chosen { onMerge(chosen) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(chosen == nil)
                }
            }
            .onAppear {
                chosen = topics.max { model.count(of: $0.id) < model.count(of: $1.id) }?.id
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

// MARK: - Zuletzt gelöscht (§3.8)

struct RecentlyDeletedView: View {
    @Environment(ThoughtsModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var confirmAll = false
    @State private var purging: Thought?
    @State private var restorePulse = 0

    var body: some View {
        let topics = Dictionary(model.topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let deleted = model.deleted.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        Group {
            if deleted.isEmpty {
                ContentUnavailableView {
                    Label("Nichts gelöscht", systemImage: "trash")
                } description: {
                    Text("Gelöschte Gedanken bleiben hier 30 Tage, dann werden sie endgültig entfernt.")
                }
                .foregroundStyle(Color.paplyText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(deleted) { thought in
                            ThoughtRow(thought: thought, topic: topics[thought.topicId ?? ""], showTopic: true, time: remaining(thought))
                                .listRowBackground(Color.paplyRow)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button { restore(thought) } label: { Label("Wiederherstellen", systemImage: "arrow.uturn.backward") }
                                    Button(role: .destructive) { purging = thought } label: { Label("Endgültig löschen", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { restore(thought) } label: { Label("Wiederherstellen", systemImage: "arrow.uturn.backward") }
                                        .tint(Color.paplyGreen)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { purging = thought } label: { Label("Endgültig löschen", systemImage: "trash") }
                                }
                        }
                    } footer: {
                        Text("Gelöschte Gedanken werden nach 30 Tagen endgültig entfernt.")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(PaplyBackground())
        .navigationTitle("Zuletzt gelöscht")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !deleted.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Alle löschen", role: .destructive) { confirmAll = true }
                        .foregroundStyle(Color.paplyDanger)
                }
            }
        }
        .confirmationDialog("Alle endgültig löschen?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Alle löschen", role: .destructive) {
                withAnimation(PaplyMotion.smooth(reduce)) { model.purgeAllDeleted() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Ton, Text und Aufgaben werden sofort entfernt. Das lässt sich nicht widerrufen.")
        }
        .confirmationDialog("Endgültig löschen?", isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } }), titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                if let thought = purging {
                    withAnimation(PaplyMotion.smooth(reduce)) { model.purge(thought.id) }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Ton, Text und Aufgaben werden sofort entfernt.")
        }
        .sensoryFeedback(.success, trigger: restorePulse)
    }

    private func restore(_ thought: Thought) {
        withAnimation(PaplyMotion.smooth(reduce)) { model.restore(thought.id) }
        restorePulse += 1
    }

    /// „noch 27 Tage“
    private func remaining(_ thought: Thought) -> String {
        guard let deletedAt = thought.deletedAt else { return "" }
        let end = deletedAt.addingTimeInterval(30 * 86_400)
        let days = max(0, Int(ceil(end.timeIntervalSinceNow / 86_400)))
        return days == 1 ? "noch 1 Tag" : "noch \(days) Tage"
    }
}

// MARK: - Verknüpfen … (Suchauswahl)

struct LinkPickerSheet: View {
    let thoughtID: String
    @Environment(ThoughtsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var linkedPulse = 0

    var body: some View {
        let linked = Set(model.linked(thoughtID).map(\.thought.id))
        let topics = Dictionary(model.topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let candidates: [Thought] = {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                return Array(model.thoughts.lazy.filter { $0.id != thoughtID && !linked.contains($0.id) && $0.state == .done }.prefix(40))
            }
            let byID = Dictionary(model.thoughts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return model.search(q).compactMap { byID[$0.thoughtID] }.filter { $0.id != thoughtID && !linked.contains($0.id) }
        }()
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { thought in
                        Button {
                            model.addLink(thoughtID, to: thought.id)
                            linkedPulse += 1
                            dismiss()
                        } label: {
                            ThoughtRow(thought: thought, topic: topics[thought.topicId ?? ""], showTopic: true,
                                       time: ThoughtDate.compact(thought.createdAt))
                        }
                        .listRowBackground(Color.paplyRow)
                    }
                } header: {
                    if query.isEmpty { Text("Zuletzt") }
                }
            }
            .overlay {
                if candidates.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .paplySheetBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Gedanken suchen")
            .navigationTitle("Verknüpfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: linkedPulse)
    }
}
