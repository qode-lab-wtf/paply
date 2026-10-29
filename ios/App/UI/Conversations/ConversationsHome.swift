import PaplyKit
import SwiftUI

struct ConversationsHome: View {
    let items: [ConversationDisplay]
    let showPrivacyHint: Bool
    let onRecord: () -> Void
    let onOpen: (String) -> Void
    let onVoices: () -> Void
    let onDeleted: () -> Void
    let onSettings: () -> Void

    private var days: [Date] {
        Set(items.map { Calendar.current.startOfDay(for: $0.conversation.createdAt) }).sorted(by: >)
    }
    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Heute" }
        if Calendar.current.isDateInYesterday(day) { return "Gestern" }
        return day.formatted(.dateTime.day().month(.wide).year())
    }
    var body: some View {
        List {
            Section {
                Button(action: onRecord) {
                    HStack(spacing: 14) {
                        Image(systemName: "record.circle").font(.largeTitle)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Gespräch aufnehmen").font(.headline)
                            Text("iPhone hinlegen – Paply erkennt, wer spricht").font(.caption)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.paplyForestDeep)
                    .padding(16).frame(minHeight: 64)
                    .background(ConversationTint.fill, in: RoundedRectangle(cornerRadius: 24))
                    .paplyGlass(.prominent(ConversationTint.blue), interactive: true, in: RoundedRectangle(cornerRadius: 24))
                }
                .buttonStyle(PressScaleStyle())
                if showPrivacyHint {
                    Text("Sag den anderen, dass Paply mitschreibt.")
                        .font(.footnote).foregroundStyle(Color.paplySecondaryText)
                }
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            if items.isEmpty {
                Section {
                    ContentUnavailableView("Gespräche bleiben im Kopf. Und hier.", systemImage: "person.2.wave.2",
                        description: Text("Nimm ein Gespräch auf. Paply hält fest, wer was gesagt hat, und sammelt deine Aufgaben."))
                    Text("Telefonate auf diesem iPhone: Anruf mit der iOS-Aufnahme mitschneiden, danach Teilen → Paply.")
                        .font(.subheadline).foregroundStyle(Color.paplySecondaryText)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            ForEach(days, id: \.self) { day in
                Section(dayTitle(day)) {
                    ForEach(items.filter { Calendar.current.isDate($0.conversation.createdAt, inSameDayAs: day) }
                        .sorted { $0.conversation.createdAt > $1.conversation.createdAt }) { item in
                        Button { onOpen(item.id) } label: {
                            ConversationThoughtRow(item: item, time: item.conversation.createdAt.formatted(date: .omitted, time: .shortened))
                        }.buttonStyle(.plain)
                    }
                }.listRowBackground(Color.paplyRow)
            }
        }
        .paplyList().navigationTitle("Gespräche")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Stimmen verwalten", systemImage: "person.wave.2", action: onVoices)
                    Button("Zuletzt gelöscht", systemImage: "trash", action: onDeleted)
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Weitere Gesprächsaktionen")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Einstellungen", systemImage: "gearshape", action: onSettings)
            }
        }
        .tint(ConversationTint.blue)
    }
}

#Preview("Übersicht") { NavigationStack { ConversationsPreviewHost() }.preferredColorScheme(.dark) }
#Preview("Leer") {
    NavigationStack {
        ConversationsHome(items: [], showPrivacyHint: true, onRecord: {}, onOpen: { _ in }, onVoices: {}, onDeleted: {}, onSettings: {})
    }.preferredColorScheme(.dark)
}
