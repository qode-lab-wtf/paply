import AVFoundation
import Foundation
import PaplyKit

// paply-bench – Latenzmessung der PaplyKit-Pipeline auf dem Mac.
// Schlüssel nur über die Umgebungsvariable PAPLY_GROQ_KEY; er wird nie ausgegeben.
//
//   paply-bench gen                      Testaudio mit `say` erzeugen
//   paply-bench probe <id> <model>       Rohantwort-Felder von Groq zeigen
//   paply-bench run <out.json> [opts]    Messmatrix (Echtzeit-Einspeisung)
//   paply-bench formats <out.json>       FLAC gegen WAV
//   paply-bench report <a.json> …        Markdown-Tabellen

let workDir = URL(fileURLWithPath: "/tmp/paply-bench-ios")
let sampleRate = 16_000.0

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func apiKey() -> String {
    guard let key = ProcessInfo.processInfo.environment["PAPLY_GROQ_KEY"], !key.isEmpty else {
        fail("PAPLY_GROQ_KEY fehlt")
    }
    return key
}

// MARK: Audio

func readWav(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard file.processingFormat.sampleRate == sampleRate, file.processingFormat.channelCount == 1 else {
        fail("Unerwartetes Format: \(url.lastPathComponent)")
    }
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

func audioURL(_ id: String) -> URL { workDir.appendingPathComponent("\(id).f32") }

func loadAudio(_ id: String) -> [Float] {
    guard let data = try? Data(contentsOf: audioURL(id)) else { fail("Audio fehlt: \(id) – erst `gen`") }
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

/// Deterministisches Rauschen (Raumgeräusch ~ −60 dBFS), damit die VAD realistisch arbeitet.
struct Noise {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    mutating func next() -> Float {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Float(Double(state % 2_000_001) / 1_000_000 - 1)
    }
}

func generate() throws {
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    for script in benchScripts {
        var samples = [Float](repeating: 0, count: Int(0.5 * sampleRate))
        for (index, part) in script.parts.enumerated() {
            let partURL = workDir.appendingPathComponent("\(script.id)-\(index).wav")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", part.voice, "-r", "155", "-o", partURL.path, "--data-format=LEI16@16000", part.text]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else { fail("say fehlgeschlagen: \(script.id)") }
            samples += try readWav(partURL)
            samples += [Float](repeating: 0, count: Int(Double(part.gapMs) / 1000 * sampleRate))
            try? FileManager.default.removeItem(at: partURL)
        }
        samples += [Float](repeating: 0, count: Int(0.6 * sampleRate))
        var noise = Noise()
        let amplitude: Float = 0.001 * 1.732 // RMS ≈ 0.001 → −60 dBFS
        for i in samples.indices { samples[i] = max(-1, min(1, samples[i] + noise.next() * amplitude)) }
        let data = samples.withUnsafeBytes { Data($0) }
        try data.write(to: audioURL(script.id))
        print(String(format: "%@  %.1f s", script.id, Double(samples.count) / sampleRate))
    }
    let scripts = try JSONEncoder().encode(benchScripts)
    try scripts.write(to: workDir.appendingPathComponent("scripts.json"))
}

/// Kürzt die Stille nach dem letzten lauten 30-ms-Fenster (> −45 dBFS).
func trimTail(_ audio: [Float], seconds: Double) -> [Float] {
    let frame = 480
    var last = 0
    for start in stride(from: 0, to: audio.count - frame, by: frame) {
        let rms = sqrt(audio[start..<(start + frame)].reduce(0) { $0 + $1 * $1 } / Float(frame))
        if 20 * log10(max(rms, 1e-9)) > -45 { last = start + frame }
    }
    return Array(audio.prefix(min(audio.count, last + Int(seconds * sampleRate))))
}

// MARK: Auswertung

func words(_ text: String) -> [String] {
    let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        .replacingOccurrences(of: "’", with: "'")
    var cleaned = ""
    for scalar in folded.unicodeScalars {
        if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
            cleaned.unicodeScalars.append(scalar)
        } else if scalar == "'" {
            continue
        } else {
            cleaned.append(" ")
        }
    }
    return cleaned.split(separator: " ").map(String.init)
}

func wordErrorRate(reference: String, hypothesis: String) -> Double {
    let r = words(reference), h = words(hypothesis)
    guard !r.isEmpty else { return h.isEmpty ? 0 : 1 }
    var previous = Array(0...h.count)
    for i in 1...r.count {
        var current = [i] + [Int](repeating: 0, count: h.count)
        for j in stride(from: 1, through: h.count, by: 1) {
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
        }
        previous = current
    }
    return Double(previous[h.count]) / Double(r.count)
}

/// Anteil der Inhaltswörter (≥ 4 Buchstaben) jeder Sprache, die im Ergebnis vorkommen.
/// Wird eine Passage übersetzt, bricht dieser Wert für ihre Sprache ein.
func languageRecall(_ script: BenchScript, output: String) -> [String: Double] {
    let present = Set(words(output))
    var result: [String: Double] = [:]
    for lang in Set(script.parts.map(\.lang)) {
        let text = script.parts.filter { $0.lang == lang }.map(\.text).joined(separator: " ")
        let content = words(text.replacingOccurrences(of: #"\[\[[^\]]*\]\]"#, with: " ", options: .regularExpression))
            .filter { $0.count >= 4 }
        guard !content.isEmpty else { continue }
        result[lang] = Double(content.filter { present.contains($0) }.count) / Double(content.count)
    }
    return result
}

// MARK: Läufe

struct RunConfig: Codable, Sendable {
    var script: String
    var model: String
    var chunked: Bool
    var prewarm: Bool
    var format: String = "flac"
    var primer: Bool? = true
    /// Stille nach dem letzten Wort auf so viele Sekunden kürzen (nil = wie erzeugt).
    var tail: Double? = nil
    /// false = ohne Polieren (nur Transkription messen, schont das Token-Kontingent).
    var polish: Bool? = nil
    /// Sprachen des Nutzers (Primer); nil = ["de", "en"].
    var languages: [String]? = nil
    var realtime: Bool
    var run: Int

    var key: String { "\(script)|\(model)|\(chunked)|\(prewarm)|\(format)|\(primer ?? true)|\(tail ?? -1)|\(run)" }
    var group: String { "\(script)|\(model)|\(format)|\(primer ?? true)|\(tail ?? -1)|\(chunked)|\(prewarm)" }
}

struct RunResult: Codable, Sendable {
    var config: RunConfig
    var lang: String
    var length: String
    var audioSeconds: Double
    var transcriptionMs: Double?
    var polishMs: Double?
    var totalMs: Double?
    var chunkCount: Int
    var uploadedBytes: Int
    var languages: [String]
    var polishModel: String?
    var polished: Bool
    var rejection: String?
    var polishError: String?
    var errorMessage: String?
    var werRaw: Double
    var werFinal: Double
    var recallRaw: [String: Double]
    var recallFinal: [String: Double]
    var raw: String
    var final: String
    var startedAt: Date
}

func perform(_ config: RunConfig, key: String) async -> RunResult {
    guard let script = benchScripts.first(where: { $0.id == config.script }) else { fail("Unbekannt: \(config.script)") }
    var audio = loadAudio(script.id)
    if let tail = config.tail { audio = trimTail(audio, seconds: tail) }
    let connection = IsolatedConnection()
    defer { connection.invalidate() }
    var settings = PaplySettings()
    settings.transcriptionModel = config.model
    settings.chunkedUpload = config.chunked
    settings.spokenLanguages = config.languages ?? ["de", "en"]
    var options = PipelineOptions()
    options.codeSwitchPrimer = config.primer ?? true
    options.polish = config.polish ?? true
    options.uploadFormat = config.format == "wav" ? .wav : .flac
    let startedAt = Date()
    // Aufnahmebeginn: Vorwärmen läuft wie in der App parallel zur Aufnahme.
    let prewarm = config.prewarm ? Task { await connection.prewarm(apiKey: key) } : nil
    let pipeline = DictationPipeline(settings: settings, recentRawDictations: [], options: options,
                                     client: connection.client(apiKey: key), catalog: connection.catalog)
    let block = 1_600
    let clock = ContinuousClock()
    let start = clock.now
    var index = 0
    for offset in stride(from: 0, to: audio.count, by: block) {
        await pipeline.append(Array(audio[offset..<min(offset + block, audio.count)]))
        index += 1
        if config.realtime { try? await clock.sleep(until: start + .milliseconds(100 * index)) }
    }
    if !config.realtime { await prewarm?.value }
    let outcome = await pipeline.finish()
    let t = outcome.timings
    return RunResult(
        config: config, lang: script.lang, length: script.length, audioSeconds: t.audioSeconds,
        transcriptionMs: t.transcriptionDoneMs,
        polishMs: t.polishDoneMs.flatMap { p in t.transcriptionDoneMs.map { p - $0 } },
        totalMs: t.totalMs, chunkCount: t.chunkCount, uploadedBytes: t.uploadedBytes,
        languages: outcome.languages, polishModel: outcome.polishModel, polished: outcome.polished != nil,
        rejection: outcome.polishRejection, polishError: outcome.polishError, errorMessage: outcome.errorMessage,
        werRaw: wordErrorRate(reference: script.reference, hypothesis: outcome.raw),
        werFinal: wordErrorRate(reference: script.reference, hypothesis: outcome.text),
        recallRaw: languageRecall(script, output: outcome.raw),
        recallFinal: languageRecall(script, output: outcome.text),
        raw: outcome.raw, final: outcome.text, startedAt: startedAt)
}

/// Läufe mit begrenzter Parallelität; Ergebnisse werden laufend gespeichert.
func runAll(_ configs: [RunConfig], parallel: Int, out: URL) async {
    let key = apiKey()
    var results: [RunResult] = (try? JSONDecoder().decode([RunResult].self, from: Data(contentsOf: out))) ?? []
    let done = Set(results.map { $0.config.key })
    let pending = configs.filter { !done.contains($0.key) }
    print("\(pending.count) Läufe offen (\(results.count) vorhanden)")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    await withTaskGroup(of: RunResult.self) { group in
        var iterator = pending.makeIterator()
        for _ in 0..<parallel {
            if let config = iterator.next() { group.addTask { await perform(config, key: key) } }
        }
        while let result = await group.next() {
            results.append(result)
            try? encoder.encode(results).write(to: out)
            let c = result.config
            print(String(format: "%@ %@ chunk=%d warm=%d %@ primer=%d #%d  trans=%5.0f pol=%5.0f total=%5.0f ms  wer=%.2f/%.2f  lang=%@ %@",
                         c.script, c.model, c.chunked ? 1 : 0, c.prewarm ? 1 : 0, c.format, (c.primer ?? true) ? 1 : 0, c.run,
                         result.transcriptionMs ?? -1, result.polishMs ?? -1, result.totalMs ?? -1,
                         result.werRaw, result.werFinal, result.languages.joined(separator: "+"),
                         result.errorMessage != nil ? "FEHLER" : (result.rejection ?? result.polishError ?? "ok")))
            // Free-Tier: 20 Transkriptionen/Minute. Schnelle Läufe (ohne Echtzeit) abbremsen.
            if !c.realtime { try? await Task.sleep(for: .seconds(3.5)) }
            if let config = iterator.next() { group.addTask { await perform(config, key: key) } }
        }
    }
}

func matrix(runs: Int, scripts: [String]) -> [RunConfig] {
    var configs: [RunConfig] = []
    for run in 1...runs {
        for script in benchScripts where scripts.isEmpty ? !script.extra : scripts.contains(script.id) {
            for model in ["whisper-large-v3", "whisper-large-v3-turbo"] {
                for chunked in [false, true] {
                    // Unter 10 s gibt es keinen Schnitt: Stücke an = Stücke aus.
                    if chunked && script.length == "8s" { continue }
                    for prewarm in [false, true] {
                        // Ohne Stücke und ohne Vorwärmen passiert vor finish() nichts im Netz:
                        // Einspeisen in Echtzeit ändert nichts, spart aber Messzeit.
                        configs.append(RunConfig(script: script.id, model: model, chunked: chunked, prewarm: prewarm,
                                                 realtime: chunked || prewarm, run: run))
                    }
                }
            }
        }
    }
    return configs
}

// MARK: Bericht

func median(_ values: [Double]) -> Double? {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return nil }
    return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
}

func fmt(_ value: Double?, _ digits: Int = 0) -> String {
    guard let value else { return "–" }
    return String(format: "%.\(digits)f", value)
}

func report(_ files: [String]) {
    var results: [RunResult] = []
    for file in files {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
              let list = try? JSONDecoder().decode([RunResult].self, from: data) else { fail("Nicht lesbar: \(file)") }
        results += list
    }
    let groups = Dictionary(grouping: results) { $0.config.group }
    print("| Audio | Modell | Format | Primer | Stücke | Vorwärmen | n | finish→Text (Median) | Transkription | Polieren | Stücke | Upload KB | WER roh | WER Ergebnis | Sprachen | Sprache gehalten | Netz |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    let order = benchScripts.map(\.id)
    for key in groups.keys.sorted(by: { a, b in
        let pa = a.split(separator: "|"), pb = b.split(separator: "|")
        let ia = order.firstIndex(of: String(pa[0])) ?? 0, ib = order.firstIndex(of: String(pb[0])) ?? 0
        return ia != ib ? ia < ib : a < b
    }) {
        let list = groups[key]!
        let c = list[0].config
        let languages = Set(list.map { $0.languages.joined(separator: "+") }).sorted().joined(separator: ", ")
        let held = list.filter { r in r.errorMessage == nil && r.recallFinal.values.allSatisfy { $0 >= 0.7 } }.count
        let net = list.map { $0.errorMessage != nil ? "Fehler" : ($0.rejection ?? $0.polishError ?? "ok") }
        let netSummary = Dictionary(grouping: net, by: { $0 }).map { "\($0.key)×\($0.value.count)" }.sorted().joined(separator: " ")
        let model = c.model == "whisper-large-v3" ? "v3" : "v3-turbo"
        let tail = c.tail.map { String(format: " (Nachlauf %.2f s)", $0) } ?? ""
        print("| \(c.script)\(tail) | \(model) | \(c.format) | \((c.primer ?? true) ? "an" : "aus") | \(c.chunked ? "an" : "aus") | \(c.prewarm ? "an" : "aus") | \(list.count) "
              + "| \(fmt(median(list.compactMap(\.totalMs)))) ms | \(fmt(median(list.compactMap(\.transcriptionMs)))) ms "
              + "| \(fmt(median(list.compactMap(\.polishMs)))) ms | \(fmt(median(list.map { Double($0.chunkCount) }))) "
              + "| \(fmt(median(list.map { Double($0.uploadedBytes) / 1024 }))) "
              + "| \(fmt(list.map(\.werRaw).reduce(0, +) / Double(list.count), 3)) "
              + "| \(fmt(list.map(\.werFinal).reduce(0, +) / Double(list.count), 3)) "
              + "| \(languages) | \(held)/\(list.count) | \(netSummary) |")
    }
}

// MARK: Sonde

func probe(_ id: String, model: String) async {
    let key = apiKey()
    var floats: [Float]
    if id.contains(".wav") {
        floats = [Float](repeating: 0, count: 8000)
        for name in id.split(separator: ",") {
            floats += (try? readWav(workDir.appendingPathComponent(String(name)))) ?? []
            floats += [Float](repeating: 0, count: 2400)
        }
        var noise = Noise()
        for i in floats.indices { floats[i] += noise.next() * 0.0017 }
    } else {
        floats = loadAudio(id)
    }
    let samples = floats.map { Int16(max(-1, min(1, $0)) * 32767) }
    let connection = IsolatedConnection()
    let env = ProcessInfo.processInfo.environment
    guard let (status, headers, body) = await connection.rawTranscription(
        apiKey: key, samples: samples, model: model, wav: true, prompt: env["PROMPT"], language: env["LANG_PARAM"]) else {
        fail("Keine Antwort")
    }
    print("HTTP \(status)")
    print("Rate-Limit-Header: \(headers.sorted { $0.key < $1.key })")
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { fail("Kein JSON") }
    print("Felder: \(object.keys.sorted())")
    print("language: \(object["language"] ?? "FEHLT")")
    if let segments = object["segments"] as? [[String: Any]], let first = segments.first {
        print("Segment-Felder: \(first.keys.sorted())")
        print("no_speech_prob: \(segments.compactMap { $0["no_speech_prob"] as? Double })")
    }
    if let segments = object["segments"] as? [[String: Any]] {
        for s in segments { print(String(format: "  [%5.1f–%5.1f] %@", s["start"] as? Double ?? 0, s["end"] as? Double ?? 0, (s["text"] as? String) ?? "")) }
    }
}

func probeChat(model: String) async {
    var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey())", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
        "model": model, "max_tokens": Int(ProcessInfo.processInfo.environment["MAXTOK"] ?? "20")!, "messages": [["role": "user", "content": ProcessInfo.processInfo.environment["LONG"] != nil
                                ? String(repeating: "Bitte nur OK antworten. ", count: 250) : "Say OK."]],
        "reasoning_effort": model.hasPrefix("qwen/") ? "none" : "low",
    ])
    guard let (data, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse else { fail("Keine Antwort") }
    print("HTTP \(http.statusCode)  retry-after: \(http.value(forHTTPHeaderField: "retry-after") ?? "–")")
    if http.statusCode != 200, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let error = object["error"] as? [String: Any] {
        print("Fehler: \(error["code"] ?? "") – \(error["message"] ?? "")")
    }
    for (key, value) in http.allHeaderFields where String(describing: key).lowercased().hasPrefix("x-ratelimit") {
        print("  \(key): \(value)")
    }
}

// MARK: Start

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "gen":
    try generate()
case "probe":
    guard args.count == 3 else { fail("probe <id> <model>") }
    await probe(args[1], model: args[2])
case "run":
    guard args.count >= 2 else { fail("run <out.json> [runs] [parallel] [scripts,…]") }
    let runs = args.count > 2 ? Int(args[2]) ?? 3 : 3
    let parallel = args.count > 3 ? Int(args[3]) ?? 1 : 1
    let scripts = args.count > 4 ? args[4].split(separator: ",").map(String.init) : []
    await runAll(matrix(runs: runs, scripts: scripts), parallel: parallel, out: URL(fileURLWithPath: args[1]))
case "formats":
    guard args.count >= 2 else { fail("formats <out.json> [runs]") }
    let runs = args.count > 2 ? Int(args[2]) ?? 3 : 3
    var configs: [RunConfig] = []
    for run in 1...runs {
        for script in ["de-8", "de-30", "de-75", "mix-75"] {
            for model in ["whisper-large-v3", "whisper-large-v3-turbo"] {
                for format in ["flac", "wav"] {
                    configs.append(RunConfig(script: script, model: model, chunked: false, prewarm: true,
                                             format: format, realtime: false, run: run))
                }
            }
        }
    }
    await runAll(configs, parallel: 1, out: URL(fileURLWithPath: args[1]))
case "probechat":
    await probeChat(model: args.count > 1 ? args[1] : "qwen/qwen3.8-27b")
case "polishab":
    guard args.count >= 3 else { fail("polishab <main.json> <out.json> [repeats] [model]") }
    let strict = BenchPolish.systemPrompt.replacingOccurrences(
        of: "Otherwise do not exchange words.",
        with: "Otherwise do not exchange words: leave every word that is already correct exactly as it is – no synonyms, no other inflection, number or tense, no gender-inclusive forms and no stylistic rewording.")
    await polishAB(source: URL(fileURLWithPath: args[1]), out: URL(fileURLWithPath: args[2]),
                   variants: [("en", BenchPolish.systemPrompt, BenchPolish.userMessage),
                              ("en-strikt", strict, BenchPolish.userMessage),
                              ("desktop-de", desktopPrompt, desktopUserMessage)],
                   repeats: args.count > 3 ? Int(args[3]) ?? 2 : 2,
                   model: args.count > 4 ? args[4] : "qwen/qwen3.8-27b")
case "chunks":
    // Prüft, ob jeder Schnitt in einer Pause liegt: lautestes 30-ms-Fenster ±150 ms um den Schnitt.
    print("| Audio | Schnitte (s) | Stücklängen (s) | lautestes Fenster am Schnitt (dBFS) |")
    print("|---|---|---|---|")
    for script in benchScripts {
        let audio = loadAudio(script.id)
        let cuts = BenchChunks.cuts(audio)
        var lengths: [Double] = []
        var previous = 0.0
        for cut in cuts { lengths.append(cut - previous); previous = cut }
        lengths.append(Double(audio.count) / sampleRate - previous)
        let levels = cuts.map { cut -> Double in
            let center = Int(cut * sampleRate)
            var loudest = -120.0
            for start in stride(from: max(0, center - 2400), to: min(audio.count - 480, center + 2400 - 480), by: 160) {
                let rms = sqrt(audio[start..<(start + 480)].reduce(0) { $0 + $1 * $1 } / 480)
                loudest = max(loudest, 20 * log10(max(Double(rms), 1e-9)))
            }
            return loudest
        }
        print("| \(script.id) | \(cuts.map { String(format: "%.2f", $0) }.joined(separator: ", ")) "
              + "| \(lengths.map { String(format: "%.1f", $0) }.joined(separator: ", ")) "
              + "| \(levels.map { String(format: "%.0f", $0) }.joined(separator: ", ")) |")
    }
case "chunkstudy":
    // Reststück bei sofortigem Stopp (0,25 s Nachlauf) je Mindestlänge; netzfrei.
    let minimums = [10.0, 8, 6, 5]
    print("| Audio | " + minimums.map { String(format: "min %.0f s: Reststück / Anfragen", $0) }.joined(separator: " | ") + " |")
    print("|---|" + minimums.map { _ in "---|" }.joined())
    for script in benchScripts where script.length != "8s" {
        let audio = trimTail(loadAudio(script.id), seconds: 0.25)
        let total = Double(audio.count) / sampleRate
        let cells = minimums.map { minimum -> String in
            let cuts = BenchChunks.cuts(audio, minSeconds: minimum)
            return String(format: "%.1f s / %d", total - (cuts.last ?? 0), cuts.count + 1)
        }
        print("| \(script.id) | " + cells.joined(separator: " | ") + " |")
    }
case "netcheck":
    // Offline: neue Netzregeln (Ziffern, Wortprüfung) gegen gespeicherte Polier-Ergebnisse.
    var pairs: [(source: String, raw: String, output: String)] = []
    for file in args.dropFirst() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else { continue }
        let name = URL(fileURLWithPath: file).lastPathComponent
        if let runs = try? JSONDecoder().decode([RunResult].self, from: data) {
            for r in runs where r.polished && !r.raw.isEmpty { pairs.append((name + ":" + r.config.script, r.raw, r.final)) }
        } else if let runs = try? JSONDecoder().decode([ABResult].self, from: data) {
            for r in runs where !r.output.isEmpty { pairs.append((name + ":" + r.script + ":" + r.variant, r.raw, r.output)) }
        }
    }
    var seen = Set<String>()
    var unique = 0, changed = 0, oldRejected = 0
    var newReasons: [String: Int] = [:]
    for pair in pairs {
        let key = pair.raw + "\u{1}" + pair.output
        if seen.contains(key) { continue }
        seen.insert(key)
        unique += 1
        if words(pair.raw) != words(pair.output) { changed += 1 }
        let old = BenchPolish.rejection(raw: pair.raw, result: pair.output, strict: false)
        let new = BenchPolish.rejection(raw: pair.raw, result: pair.output, strict: true)
        if old != nil { oldRejected += 1 }
        if let new, old == nil {
            newReasons[new, default: 0] += 1
            let a = words(pair.raw), b = words(pair.output)
            var diff: [String] = []
            var i = 0, j = 0
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] { i += 1; j += 1; continue }
                // einfache Anzeige: nächstes gemeinsames Wort suchen
                var found = false
                for di in 0..<6 where !found {
                    for dj in 0..<6 where i + di < a.count && j + dj < b.count && a[i + di] == b[j + dj] {
                        diff.append("\(a[i..<(i + di)].joined(separator: " "))→\(b[j..<(j + dj)].joined(separator: " "))")
                        i += di; j += dj; found = true; break
                    }
                }
                if !found { diff.append("\(a[i...].joined(separator: " "))→\(b[j...].joined(separator: " "))"); break }
            }
            print("NEU ABGELEHNT [\(new)] \(pair.source): \(diff.joined(separator: "; "))")
        }
    }
    var occurrenceRejected = 0, occurrenceChanged = 0
    for pair in pairs {
        if words(pair.raw) != words(pair.output) { occurrenceChanged += 1 }
        if BenchPolish.rejection(raw: pair.raw, result: pair.output, strict: true) != nil { occurrenceRejected += 1 }
    }
    print("Läufe mit Wortänderung: \(occurrenceChanged); davon neu abgelehnt: \(occurrenceRejected)")
    let occurrences = pairs.count
    print("Paare gesamt \(occurrences), verschieden \(unique), davon mit Wortänderung \(changed); altes Netz lehnte \(oldRejected) ab; neu zusätzlich abgelehnt: \(newReasons)")
case "encode":
    print("| Audio | Dauer | WAV KB | FLAC KB | FLAC/WAV | FLAC-Kodierung ms |")
    print("|---|---|---|---|---|---|")
    for script in benchScripts {
        let samples = loadAudio(script.id).map { Int16(max(-1, min(1, $0)) * 32767) }
        let wav = AudioEncoder.encode(samples, preferFLAC: false)
        var times: [Double] = []
        var flacBytes = 0
        for _ in 0..<5 {
            let flac = AudioEncoder.encode(samples)
            times.append(flac.encodeMs)
            flacBytes = flac.data.count
        }
        print(String(format: "| %@ | %.1f s | %.0f | %.0f | %.2f | %.1f |", script.id, Double(samples.count) / sampleRate,
                     Double(wav.data.count) / 1024, Double(flacBytes) / 1024, Double(flacBytes) / Double(wav.data.count),
                     median(times) ?? 0))
    }
case "w8", "w8b":
    // Nachmessung neuer Primer (nur Whisper, ohne Polieren, ohne Modellliste).
    let plan: [(String, String, Int, [String])] = args[0] == "w8b" ? [
        ("fr-mix", "whisper-large-v3", 1, ["fr", "en"]), ("de-30", "whisper-large-v3", 1, ["de", "en"]),
        ("en-30", "whisper-large-v3", 1, ["de", "en"]),
    ] : [
        ("mix-8", "whisper-large-v3", 3, ["de", "en"]), ("mix-30", "whisper-large-v3", 3, ["de", "en"]),
        ("mix-75", "whisper-large-v3", 2, ["de", "en"]), ("de-30", "whisper-large-v3", 2, ["de", "en"]),
        ("en-30", "whisper-large-v3", 2, ["de", "en"]), ("fr-mix", "whisper-large-v3", 2, ["fr", "en"]),
        ("de-bild", "whisper-large-v3", 3, ["de", "en"]), ("mix-30", "whisper-large-v3-turbo", 2, ["de", "en"]),
    ]
    var configs: [RunConfig] = []
    for (script, model, runs, languages) in plan {
        for run in 1...runs {
            configs.append(RunConfig(script: script, model: model, chunked: false, prewarm: false,
                                     polish: false, languages: languages, realtime: false, run: run))
        }
    }
    let audioSeconds = configs.reduce(0.0) { sum, c in sum + Double(loadAudio(c.script).count) / sampleRate }
    print("Budget: \(configs.count) Transkriptionen, \(Int(audioSeconds)) s Audio")
    guard configs.count <= 60, audioSeconds <= 15 * 60 else { fail("Budget überschritten") }
    await runAll(configs, parallel: 1, out: URL(fileURLWithPath: args.count > 1 ? args[1] : "/tmp/paply-bench-ios/w8.json"))
case "primerprobe":
    // Einzelanfragen mit frei vorgegebenem Prompt (Umgebung PRIMER_TEXT), v3, FLAC.
    guard args.count >= 2, let prompt = ProcessInfo.processInfo.environment["PRIMER_TEXT"] else { fail("primerprobe <ids,…>") }
    let key = apiKey()
    for id in args[1].split(separator: ",").map(String.init) {
        guard let script = benchScripts.first(where: { $0.id == id }) else { fail("Unbekannt: \(id)") }
        let samples = loadAudio(id).map { Int16(max(-1, min(1, $0)) * 32767) }
        let connection = IsolatedConnection()
        guard let (status, _, body) = await connection.rawTranscription(apiKey: key, samples: samples,
                                                                        model: "whisper-large-v3", wav: false, prompt: prompt),
              status == 200, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let text = object["text"] as? String else { print("\(id): Fehler"); continue }
        let recall = languageRecall(script, output: text).sorted { $0.key < $1.key }
            .map { String(format: "%@=%.2f", $0.key, $0.value) }.joined(separator: ",")
        print(String(format: "%@ wer=%.3f %@ | %@", id, wordErrorRate(reference: script.reference, hypothesis: text), recall,
                     String(text.prefix(220))))
        try? await Task.sleep(for: .seconds(3.5))
    }
case "tail":
    guard args.count >= 2 else { fail("tail <out.json> [runs]") }
    let runs = args.count > 2 ? Int(args[2]) ?? 3 : 3
    var configs: [RunConfig] = []
    for run in 1...runs {
        for script in ["de-30", "en-30", "mix-30", "de-75", "en-75", "mix-75"] {
            for model in ["whisper-large-v3", "whisper-large-v3-turbo"] {
                configs.append(RunConfig(script: script, model: model, chunked: true, prewarm: true,
                                         tail: 0.25, polish: false, realtime: true, run: run))
            }
        }
    }
    await runAll(configs, parallel: 1, out: URL(fileURLWithPath: args[1]))
case "primer":
    guard args.count >= 2 else { fail("primer <out.json> [runs]") }
    let runs = args.count > 2 ? Int(args[2]) ?? 3 : 3
    var configs: [RunConfig] = []
    for run in 1...runs {
        for script in ["mix-8", "mix-30", "mix-75", "de-30", "en-30"] {
            for model in ["whisper-large-v3", "whisper-large-v3-turbo"] {
                configs.append(RunConfig(script: script, model: model, chunked: false, prewarm: true,
                                         primer: false, realtime: false, run: run))
            }
        }
    }
    await runAll(configs, parallel: 1, out: URL(fileURLWithPath: args[1]))
case "report":
    report(Array(args.dropFirst()))
default:
    fail("Befehle: gen | probe | run | formats | report")
}
