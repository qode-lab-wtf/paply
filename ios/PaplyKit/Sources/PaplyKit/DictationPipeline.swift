import Foundation
import os

/// Zusätzliche Stellschrauben (vor allem für Messungen). Standard = Produktverhalten.
public struct PipelineOptions: Sendable {
    public enum UploadFormat: String, Sendable, Codable { case flac, wav }
    public var uploadFormat: UploadFormat = .flac
    /// Sprachwechsel-Beispiel im Whisper-Prompt (nur zum Vergleichen abschaltbar).
    public var codeSwitchPrimer = true
    /// Polieren; aus = Rohtext (z. B. für Messungen, die nur die Transkription betreffen).
    public var polish = true
    /// Wortgenaue Prüfung des Polierens (Ersetzungen/Einfügungen), siehe latenz-mac.md.
    public var strictPolishCheck = true
    public init() {}
}

/// Ein Diktat: Audio rein (Echtzeit), Text raus.
///
/// Ablauf: `append` misst Sprachaktivität und schneidet (bei `chunkedUpload`) an
/// Sprechpausen Stücke ab, die sofort im Hintergrund transkribiert werden. `finish`
/// lädt nur noch den Rest hoch, fügt die Stücke in Reihenfolge zusammen, entfernt
/// Stille-Halluzinationen und Prompt-Echos und poliert. Scheitert ein Stück endgültig,
/// werden keine weiteren Stücke gesendet; `finish` lädt dann ab diesem Stück alles in
/// einem Teil hoch (höchstens 10 min je Teil). Diktattexte werden nie protokolliert.
///
/// Zusicherungen:
/// - Solange `speechDetected` false ist, wird nichts hochgeladen.
/// - `cancel()` bricht laufende Uploads sofort ab und verwirft das Audio.
/// - Das Audio bleibt bis `cancel()`, `releaseAudio()` oder zur Freigabe der Pipeline im
///   Speicher; `retry()` sendet nach einem Fehler nur die gescheiterten Teile erneut.
public actor DictationPipeline {
    private static let log = Logger(subsystem: "dev.paply.kit", category: "pipeline")
    /// Längster Teil, der in einer Anfrage hochgeladen wird (WAV ≈ 19 MB < 25 MB Free-Tier).
    static let maxPieceSeconds = 600.0

    private let settings: PaplySettings
    private let options: PipelineOptions
    private let recentRawDictations: [String]
    private let client: GroqClient
    private let catalog: ModelCatalog

    private var samples: [Int16] = []
    private var vad = VoiceActivityDetector()
    private var planner = ChunkPlanner()

    /// Während der Aufnahme geschnittene Stücke.
    private struct Chunk {
        let start: Int
        let end: Int
        let task: Task<ChunkResult, Never>
        var result: ChunkResult?
    }
    private var chunks: [Chunk] = []
    /// Nach dem ersten endgültigen Fehler eines Stücks: keine weiteren Stücke senden.
    private var chunkingStopped = false

    /// Teile für den Abschluss (bleiben für `retry()` erhalten).
    private struct PlanPiece {
        let start: Int
        let end: Int
        var result: ChunkResult?
    }
    private var plan: [PlanPiece]?

    private var finishTask: Task<DictationOutcome, Never>?
    private var finishing = false
    private var finished = false
    private var cancelled = false
    private var audioReleased = false
    private var lastOutcome: DictationOutcome?
    private var lastFailed = false
    private let bytes = Counter()
    private let uploads = Counter()

    public init(apiKey: String, settings: PaplySettings, recentRawDictations: [String] = []) {
        self.init(apiKey: apiKey, settings: settings, recentRawDictations: recentRawDictations, options: PipelineOptions())
    }

    public init(apiKey: String, settings: PaplySettings, recentRawDictations: [String] = [], options: PipelineOptions) {
        self.init(settings: settings, recentRawDictations: recentRawDictations, options: options,
                  client: GroqClient(apiKey: apiKey), catalog: .shared)
    }

    package init(settings: PaplySettings, recentRawDictations: [String], options: PipelineOptions = PipelineOptions(),
                 client: GroqClient, catalog: ModelCatalog) {
        self.settings = settings
        self.options = options
        self.recentRawDictations = recentRawDictations
        self.client = client
        self.catalog = catalog
    }

    /// 16 kHz mono Float32 (−1…1), beliebige Blockgrößen, in Echtzeit.
    public func append(_ newSamples: [Float]) {
        guard !finished, !cancelled, !newSamples.isEmpty else { return }
        samples.append(contentsOf: AudioEncoder.int16(newSamples))
        vad.process(newSamples)
        // Ohne erkannte Sprache wird nie etwas hochgeladen.
        guard settings.chunkedUpload, vad.speechDetected, !chunkingStopped else { return }
        while let range = planner.nextCut(vad) {
            startChunk(frames: range)
        }
    }

    /// Bisheriges Audio verwerfen und die Aufnahme frisch weiterführen – nach einem Neustart
    /// des Mikros, weil es nur digitale Stille lieferte. Wirkt nur, solange noch nichts
    /// erkannt und nichts hochgeladen wurde (dann war das Bisherige ohnehin wertlos).
    /// Liefert true, wenn verworfen wurde.
    @discardableResult
    public func discardSilentStart() -> Bool {
        guard !finished, !cancelled, chunks.isEmpty, !vad.speechDetected else { return false }
        samples = []
        vad = VoiceActivityDetector()
        planner = ChunkPlanner()
        return true
    }

    /// true, sobald echte Sprache erkannt wurde (nicht Rauschen/Klick/Atmen).
    public var speechDetected: Bool { vad.speechDetected }

    /// Aktueller Pegel in dBFS (für eine Pegelanzeige).
    public var levelDbfs: Double { vad.lastLevelDbfs }

    /// Ergänzung: true, wenn der letzte Abschluss an einem Fehler scheiterte und das Audio
    /// für `retry()` noch vorhanden ist.
    public var canRetry: Bool { lastFailed && !audioReleased && !cancelled && !samples.isEmpty }

    public func finish() async -> DictationOutcome {
        if let finishTask { return await finishTask.value }
        return await startFinish()
    }

    /// Ergänzung: Nach einem Fehler nur die gescheiterten Teile erneut senden und neu
    /// polieren. Nach Erfolg das gespeicherte Ergebnis; läuft gerade ein Abschluss, dessen
    /// Ergebnis; vor `finish()` wie `finish()`; nach `cancel()` nichts ("").
    public func retry() async -> DictationOutcome {
        if cancelled { return DictationOutcome() }
        if let finishTask, finishing { return await finishTask.value }
        if let lastOutcome, !lastFailed { return lastOutcome }
        if audioReleased {
            return DictationOutcome(errorMessage: "Die Aufnahme ist nicht mehr verfügbar.")
        }
        return await startFinish()
    }

    /// Ergänzung: Audio freigeben, ohne abzubrechen (z. B. nach erfolgreichem Einsetzen).
    /// Das letzte Ergebnis bleibt abrufbar; ein Neuversuch ist danach nicht mehr möglich.
    /// Während eines laufenden Abschlusses wirkungslos.
    public func releaseAudio() {
        guard finished, !finishing else { return }
        audioReleased = true
        samples = []
        plan = nil
    }

    /// Alles verwerfen, laufende Uploads abbrechen.
    public func cancel() {
        cancelled = true
        finished = true
        chunkingStopped = true
        for chunk in chunks { chunk.task.cancel() }
        finishTask?.cancel()
        samples = []
        plan = nil
    }

    private func startFinish() async -> DictationOutcome {
        finished = true
        finishing = true
        let task = Task { await self.runFinish() }
        finishTask = task
        let outcome = await task.value
        finishing = false
        return outcome
    }

    private var primer: String? {
        options.codeSwitchPrimer ? CodeSwitchPrimer.text(languages: CodeSwitchPrimer.userLanguages(settings)) : nil
    }

    // MARK: Stücke

    struct ChunkResult: Sendable {
        var text: String = ""
        var segments: [WhisperSegment] = []
        var language: String?
        var failure: GroqFailure?
        /// false: wegen eines früheren Fehlers nicht gesendet.
        var sent = true
        /// Woher die Sprache kam (Sprachwache).
        var languageSource: LanguageSource?

        var succeeded: Bool { sent && failure == nil }
    }

    private func startChunk(frames range: Range<Int>) {
        let n = VoiceActivityDetector.frameLength
        let start = range.lowerBound * n
        let end = min(range.upperBound * n, samples.count)
        guard end > start else { return }
        // Kopie: ein Ausschnitt hielte den wachsenden Gesamtpuffer fest (Kopie bei jedem append).
        let audio = Array(samples[start..<end])
        if chunks.isEmpty && options.polish {
            // Netz läuft ohnehin: Modellliste fürs Polieren schon jetzt holen (meist Cache).
            let catalog = catalog, client = client
            Task.detached(priority: .utility) { _ = await catalog.models(client) }
        }
        let index = chunks.count
        let priorTasks = chunks.map(\.task)
        let previous: Task<ChunkResult, Never>? = priorTasks.count <= 1 ? priorTasks.last : Task.detached(priority: .userInitiated) {
            for task in priorTasks.reversed() {
                guard let result = await awaitResult(task) else { return ChunkResult(failure: .cancelled) }
                if result.succeeded && !result.text.isEmpty { return result }
            }
            return ChunkResult()
        }
        let context = makeContext()
        let vad = vad
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> ChunkResult in
            // Prompt-Kontext kurz abwarten; die Erkennung darf parallel starten.
            var before: ChunkResult?
            if let previous { before = await awaitResult(previous, timeout: .milliseconds(1500)) }
            if Task.isCancelled { return ChunkResult(failure: .cancelled) }
            guard let self, await !self.isChunkingStopped else { return ChunkResult(sent: false) }
            let result = await Self.transcribe(audio[...], startSample: start, vad: vad,
                                               previous: before, context: context, previousTask: previous)
            await self.chunkCompleted(index, result)
            return result
        }
        chunks.append(Chunk(start: start, end: end, task: task))
    }

    private var isChunkingStopped: Bool { chunkingStopped }

    private func chunkCompleted(_ index: Int, _ result: ChunkResult) {
        guard chunks.indices.contains(index) else { return }
        chunks[index].result = result
        if let failure = result.failure, failure != .cancelled { chunkingStopped = true }
    }

    /// Alles, was eine Transkription braucht, als Sendable-Paket.
    struct Context: Sendable {
        let client: GroqClient
        let settings: PaplySettings
        let format: PipelineOptions.UploadFormat
        let primer: String?
        let bytes: Counter
        let requestedSamples: Counter
        let uploads: Counter
    }

    private let requestedSamples = Counter()

    private func makeContext() -> Context {
        Context(client: client, settings: settings, format: options.uploadFormat, primer: primer,
                bytes: bytes, requestedSamples: requestedSamples, uploads: uploads)
    }

    /// `previous`: Ergebnis des Vorstücks (Ende als Prompt-Kontext, Sprache für kurze Stücke).
    static func transcribe(_ audio: ArraySlice<Int16>, startSample: Int, vad: VoiceActivityDetector,
                                   previous: ChunkResult?, context: Context, previousTask: Task<ChunkResult, Never>? = nil) async -> ChunkResult {
        let settings = context.settings
        let previousText = previous?.text
        let prompt = WhisperPrompt.build(vocabulary: settings.vocabulary, previousText: previousText, primer: context.primer)
        let encoded = AudioEncoder.encode(audio, preferFLAC: context.format == .flac)
        let seconds = Double(audio.count) / AudioEncoder.sampleRate
        let bytes = context.bytes
        @Sendable func send(_ language: String?, termPrompt: String? = nil) async -> Result<Transcription, GroqFailure> {
            context.uploads.add(1)
            return await context.client.transcribe(audio: encoded, model: settings.transcriptionModel,
                                                   language: language, prompt: termPrompt ?? prompt, audioSeconds: seconds,
                                                   bytesSent: { bytes.add($0); context.requestedSamples.add(audio.count) })
        }
        // Erst erkennen, bei Bedarf mit der erwarteten Sprache gegenprüfen.
        let users = CodeSwitchPrimer.userLanguages(settings)
        let primary = LanguageGuard.primary(settings)
        let frameSamples = VoiceActivityDetector.frameLength
        let firstFrame = startSample / frameSamples
        let lastFrame = (startSample + audio.count + frameSamples - 1) / frameSamples
        // Gesprochene Dauer (VAD-Sprachanteil), nicht die Audiolänge; ohne Messwert die Audiolänge.
        let measured = (firstFrame..<lastFrame).clamped(to: 0..<vad.frameCount)
        let spoken = measured.isEmpty ? seconds : vad.activity(in: measured).speechMs / 1000
        var source = LanguageSource.auto
        var chosenLanguage: String?
        let firstStarted = ContinuousClock.now
        var result = await send(nil)
        let firstDuration = firstStarted.duration(to: .now)
        let firstSeconds = Double(firstDuration.components.seconds) + Double(firstDuration.components.attoseconds) / 1e18
        guard case .success(let first) = result else {
            if case .failure(let failure) = result { return ChunkResult(failure: failure) }
            return ChunkResult(failure: .invalidResponse)
        }
        let canCheck = spoken <= LanguageGuard.shortSpeechSeconds || !users.map(LanguageGuard.code).contains(LanguageGuard.code(GroqModels.languageCode(first.language) ?? ""))
        let checkDeadline = ContinuousClock.now.advanced(by: .seconds(LanguageGuard.checkTimeout(firstSeconds: firstSeconds)))
        // Erst für die Gegenprobe muss die tatsächlich gewählte Vorstücksprache feststehen.
        let resolvedPrevious: ChunkResult?
        if canCheck, let previousTask { resolvedPrevious = await awaitResult(previousTask, timeout: ContinuousClock.now.duration(to: checkDeadline)) }
        else { resolvedPrevious = previous }
        if Task.isCancelled { return ChunkResult(failure: .cancelled) }
        let previousLanguage = resolvedPrevious.flatMap { $0.succeeded && !$0.text.isEmpty ? $0.language : nil }
        let expected = LanguageGuard.expected(previous: previousLanguage, primary: primary)
        if case .success(let first) = result, !Task.isCancelled, ContinuousClock.now < checkDeadline,
           LanguageGuard.needsCheck(expected: expected, detected: GroqModels.languageCode(first.language),
                                    userLanguages: users, spokenSeconds: spoken) {
            let check = await LanguageGuard.boundedCheck(firstSeconds: firstSeconds, timeout: ContinuousClock.now.duration(to: checkDeadline)) { await send(expected) }
            switch check ?? .failure(.cancelled) {
            case .success(let second):
                if LanguageGuard.choose(detectedText: first.text ?? "", expectedText: second.text,
                                        detectedConfidence: LanguageGuard.confidence(first.segments),
                                        expectedConfidence: LanguageGuard.confidence(second.segments), spokenSeconds: spoken) == .expected {
                    result = .success(second)
                    chosenLanguage = expected
                    source = .checkExpected
                } else { source = .checkDetected }
            case .failure:
                source = .checkFailed
            }
        }
        if Task.isCancelled { return ChunkResult(failure: .cancelled) }
        if case .success(let selected) = result {
            chosenLanguage = chosenLanguage ?? GroqModels.languageCode(selected.language)
            let candidates = TermGuard.candidates(settings.vocabulary, selected)
            if !candidates.terms.isEmpty {
                let language = chosenLanguage
                let check = await LanguageGuard.boundedCheck(firstSeconds: firstSeconds) { await send(language, termPrompt: candidates.prompt) }
                if Task.isCancelled { return ChunkResult(failure: .cancelled) }
                if case .success(let second) = check,
                   candidates.terms.contains(where: { TermGuard.accept($0, first: selected.text ?? "", second: second.text ?? "", lpFirst: LanguageGuard.confidence(selected.segments), lpSecond: LanguageGuard.confidence(second.segments)) }) {
                    result = .success(second)
                }
            }
        }
        switch result {
        case .failure(let failure):
            log.error("Transkription fehlgeschlagen: \(failure.code, privacy: .public)")
            return ChunkResult(failure: failure)
        case .success(let transcription):
            let rate = AudioEncoder.sampleRate
            let filtered = SilenceFilter.filter(text: transcription.text, segments: transcription.segments,
                                                meta: vad.meta(frameRange: firstFrame..<lastFrame))
            let offset = Double(startSample) / rate
            let cleaned = TranscriptCleanup.removeEchoes(
                text: filtered.text, segments: filtered.keptSegments, primer: context.primer, previousText: previousText,
                vocabulary: settings.vocabulary,
                duration: Double(audio.count) / rate,
                voiced: { vad.voicedMs(fromSeconds: offset + $0, toSeconds: offset + $1) })
            let text = SilenceFilter.isTrivialTranscript(cleaned.text) ? "" : cleaned.text
            let segments = text.isEmpty ? [] : cleaned.segments.map { segment -> WhisperSegment in
                var shifted = segment
                shifted.start = segment.start.map { $0 + offset }
                shifted.end = segment.end.map { $0 + offset }
                return shifted
            }
            // Die gewählte Sprache, unabhängig von der Meldung der Gegenprobe.
            let guarded = chosenLanguage
            return ChunkResult(text: text, segments: segments,
                               language: guarded ?? GroqModels.languageCode(transcription.language) ?? detectLanguage(text),
                               languageSource: source)
        }
    }

    // MARK: Abschluss

    private func runFinish() async -> DictationOutcome {
        let clock = ContinuousClock()
        let started = clock.now
        func ms() -> Double {
            let d = clock.now - started
            return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }
        // Bytes/Anfragen dieses Laufs; der erste Lauf zählt die Stücke der Aufnahme mit.
        let bytesBefore = plan == nil ? 0 : bytes.value
        let uploadsBefore = plan == nil ? 0 : uploads.value
        let requestedBefore = plan == nil ? 0 : requestedSamples.value
        var timings = DictationTimings(audioSeconds: Double(samples.count) / AudioEncoder.sampleRate)
        func done(_ outcome: DictationOutcome, failed: Bool = false) -> DictationOutcome {
            var outcome = outcome
            timings.totalMs = ms()
            timings.uploadedBytes = bytes.value - bytesBefore
            timings.chunkCount = uploads.value - uploadsBefore
            timings.requestedAudioSeconds = Double(requestedSamples.value - requestedBefore) / AudioEncoder.sampleRate
            outcome.timings = timings
            outcome.languageSources = (plan ?? []).compactMap { $0.result?.languageSource?.rawValue }
            if !cancelled {
                lastFailed = failed
                if !failed { lastOutcome = outcome }
            }
            return outcome
        }
        if cancelled { return DictationOutcome() }

        // Ohne Sprache gar nicht an Groq senden.
        if samples.isEmpty || !vad.speechDetected || SilenceFilter.shouldSkipTranscription(vad.meta()) {
            for chunk in chunks { chunk.task.cancel() }
            return done(DictationOutcome(noSpeech: !samples.isEmpty || plan == nil))
        }

        if options.polish {
            // Modellliste parallel zur letzten Transkription holen (meist schon im Cache).
            let catalog = catalog, client = client
            Task.detached(priority: .userInitiated) { _ = await catalog.models(client) }
        }

        // Laufende Stücke abwarten (abbrechbar).
        for index in chunks.indices where chunks[index].result == nil {
            let task = chunks[index].task
            let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            if chunks.indices.contains(index) { chunks[index].result = result }
        }
        if cancelled || Task.isCancelled { return DictationOutcome() }

        if plan == nil { plan = makePlan() }
        let context = makeContext()
        var failure: GroqFailure?
        for index in (plan ?? []).indices where plan?[index].result?.succeeded != true {
            guard let piece = plan?[index] else { break }
            let previous = plan?[..<index].last(where: { $0.result?.succeeded == true && $0.result?.text.isEmpty == false })?.result
            let result = await Self.transcribe(samples[piece.start..<piece.end], startSample: piece.start, vad: vad,
                                               previous: previous, context: context)
            if cancelled || Task.isCancelled { return DictationOutcome() }
            if let error = result.failure { failure = error; break }
            plan?[index].result = result
        }
        timings.transcriptionDoneMs = ms()
        if let failure {
            return done(DictationOutcome(errorMessage: failure == .cancelled ? nil : failure.germanMessage), failed: true)
        }

        let results = (plan ?? []).compactMap(\.result)
        let raw = TranscriptCleanup.join(results.map(\.text))
        var languages: [String] = []
        for language in results.compactMap(\.language) where !languages.contains(language) {
            languages.append(language)
        }
        guard !raw.isEmpty else { return done(DictationOutcome(languages: languages, noSpeech: true)) }

        guard options.polish else {
            return done(DictationOutcome(text: raw, raw: raw, languages: languages,
                                         polishError: PolishFailureCode.disabled.rawValue))
        }
        let messages = PolishPrompt.buildMessages(text: raw, history: recentRawDictations,
                                                  segments: results.flatMap(\.segments), vocabulary: settings.vocabulary)
        let polish = await PolishService(client: client, catalog: catalog, strictEdits: options.strictPolishCheck)
            .polish(text: raw, messages: messages, vocabulary: settings.vocabulary, settings: settings)
        timings.polishDoneMs = ms()
        if cancelled || Task.isCancelled { return DictationOutcome() }
        if let error = polish.error { Self.log.notice("Polieren übersprungen: \(error.rawValue, privacy: .public)") }
        if let rejection = polish.rejection { Self.log.notice("Sicherheitsnetz: \(rejection, privacy: .public)") }

        return done(DictationOutcome(
            text: polish.polished ?? raw, raw: raw, polished: polish.polished,
            polishRejection: polish.rejection, languages: languages,
            polishError: polish.error?.rawValue, polishModel: polish.model))
    }

    /// Teile für den Abschluss: erfolgreiche Stücke bleiben; gescheiterte oder nicht
    /// gesendete Stücke und der Rest nach dem letzten Schnitt werden zu einem Teil
    /// zusammengefasst (höchstens `maxPieceSeconds` je Teil).
    private func makePlan() -> [PlanPiece] {
        var pieces: [PlanPiece] = []
        func addPending(_ start: Int, _ end: Int) {
            if let last = pieces.last, last.result == nil, last.end == start {
                pieces[pieces.count - 1] = PlanPiece(start: last.start, end: end, result: nil)
            } else {
                pieces.append(PlanPiece(start: start, end: end, result: nil))
            }
        }
        for chunk in chunks {
            if let result = chunk.result, result.succeeded {
                pieces.append(PlanPiece(start: chunk.start, end: chunk.end, result: result))
            } else {
                addPending(chunk.start, chunk.end)
            }
        }
        let tailStart = chunks.last?.end ?? 0
        if tailStart < samples.count {
            let n = VoiceActivityDetector.frameLength
            let tailFrames = (tailStart / n)..<vad.frameCount
            let pendingBefore = pieces.last.map { $0.result == nil } ?? false
            if chunks.isEmpty || pendingBefore || vad.hasAnyActivity(in: tailFrames) {
                addPending(tailStart, samples.count)
            }
        }
        return pieces.flatMap(split)
    }

    /// Zu lange Teile an der leisesten Stelle der letzten 30 s vor der Grenze teilen.
    private func split(_ piece: PlanPiece) -> [PlanPiece] {
        guard piece.result == nil else { return [piece] }
        let rate = AudioEncoder.sampleRate
        let limit = Int(Self.maxPieceSeconds * rate)
        var parts: [PlanPiece] = []
        var start = piece.start
        while piece.end - start > limit {
            let n = VoiceActivityDetector.frameLength
            let lastFrame = (start + limit) / n
            let firstFrame = max(start / n + 1, lastFrame - Int(30_000 / VoiceActivityDetector.frameMs))
            var cutFrame = lastFrame
            var quietest = Float.greatestFiniteMagnitude
            for frame in firstFrame..<min(lastFrame, vad.frameCount) where vad.frames[frame].dbfs < quietest {
                quietest = vad.frames[frame].dbfs
                cutFrame = frame
            }
            let cut = max(start + 1, min(cutFrame * n, piece.end))
            parts.append(PlanPiece(start: start, end: cut, result: nil))
            start = cut
        }
        parts.append(PlanPiece(start: start, end: piece.end, result: nil))
        return parts
    }
}

/// Thread-sicherer Zähler (hochgeladene Bytes, gesendete Teile).
final class Counter: Sendable {
    private let total = OSAllocatedUnfairLock(initialState: 0)
    func add(_ count: Int) { total.withLock { $0 += count } }
    var value: Int { total.withLock { $0 } }
}
