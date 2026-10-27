import SwiftUI

struct DiagEntry: Identifiable, Sendable {
    let id: Int
    let date: Date
    let process: String
    let event: String
    let detail: String
    let line: String
}

/// Liest die JSONL-Dateien aller Prozesse und führt sie zeitlich zusammen.
enum DiagReader {
    static func load(maxEntries: Int = 4000) -> [DiagEntry] {
        guard let dir = AppGroup.directory(Diag.directoryName),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var entries: [DiagEntry] = []
        var counter = 0
        for file in files where file.pathExtension == "jsonl" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let date = (object["ts"] as? String).flatMap(parser.date(from:)) ?? .distantPast
                let skip: Set<String> = ["ts", "mono", "p", "pid", "ev"]
                let detail = object.keys.filter { !skip.contains($0) }.sorted().map { key in
                    "\(key)=\(describe(object[key]))"
                }.joined(separator: " · ")
                counter += 1
                entries.append(DiagEntry(
                    id: counter,
                    date: date,
                    process: object["p"] as? String ?? "?",
                    event: object["ev"] as? String ?? "?",
                    detail: detail,
                    line: String(line)
                ))
            }
        }
        entries.sort { $0.date > $1.date }
        return Array(entries.prefix(maxEntries))
    }

    /// Alle Einträge (älteste zuerst) als eine Datei zum Teilen.
    static func export() -> URL? {
        Diag.flush()
        let entries = load(maxEntries: .max).reversed()
        let stamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("paply-diagnose-\(stamp).jsonl")
        let body = entries.map(\.line).joined(separator: "\n") + "\n"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func describe(_ value: Any?) -> String {
        switch value {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        case nil, is NSNull: "–"
        default: "\(value!)"
        }
    }
}

struct DiagnosticsView: View {
    @State private var entries: [DiagEntry] = []
    @State private var filter = "alle"
    @State private var exportURL: URL?
    @State private var confirmDelete = false
    @State private var loading = true

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM. HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        List {
            Section {
                Picker("Prozess", selection: $filter) {
                    Text("Alle").tag("alle")
                    Text("App").tag("app")
                    Text("Tastatur").tag("kb")
                    Text("Widgets").tag("wg")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Enthält keine Diktat-Texte, nur Längen und Zeiten. \(entries.count) Einträge.")
            }
            ForEach(filtered) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.process)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(color(for: entry.process).opacity(0.25)))
                            .foregroundStyle(color(for: entry.process))
                        Text(entry.event).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Self.time.string(from: entry.date))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.paplyText.opacity(0.7))
                            .textSelection(.enabled)
                    }
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
        }
        .paplyList()
        .overlay {
            if loading { ProgressView() }
        }
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
            }
        }
        .confirmationDialog("Diagnose löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) {
                Diag.deleteAll()
                Task { await reload() }
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
    }

    private var filtered: [DiagEntry] {
        filter == "alle" ? entries : entries.filter { $0.process == filter }
    }

    private func reload() async {
        loading = true
        let result = await Task.detached(priority: .userInitiated) {
            (DiagReader.load(), DiagReader.export())
        }.value
        entries = result.0
        exportURL = result.1
        loading = false
    }

    private func color(for process: String) -> Color {
        switch process {
        case "app": .paplyGreenBright
        case "kb": .paplyBeak
        default: .cyan
        }
    }
}
