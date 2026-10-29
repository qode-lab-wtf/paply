import Foundation

// Schnittstellen-Verträge für „Gespräche“ (ios/docs/gespraeche/KONZEPT.md §9). Von der Leitung vorab festgelegt –
// Änderungen nur in Absprache. Zeiten auf der Platte als Millisekunden seit 1970 (wie bei den Gedanken),
// Positionen in der Aufnahme als Sekunden (Double) ab Aufnahmebeginn. Schlüssel in camelCase.
//
// Ein Gespräch hat immer einen verknüpften Gedanken mit derselben ID (`Thought.kind == "conversation"`). Der Gedanke
// trägt Titel, Zusammenfassung als Text, Thema und die Aufgaben des Besitzers – so erscheinen sie ohne Sonderweg im
// Reiter „Aufgaben“, in Widgets, Erinnerungen und unter dem Thema. Das Gespräch trägt Sprecher, Wortlaut und Ton.

public enum ConversationKind {
    /// `Thought.kind` des verknüpften Gedankens
    public static let thoughtKind = "conversation"
}

public enum ConversationState: String, Codable, Sendable {
    /// Aufnahme läuft
    case recording
    /// Ton gesichert, Auswertung steht aus
    case captured
    /// Auswertung läuft (Stufe in `Conversation.progress`)
    case analyzing
    case done
    case waitingNetwork, waitingKey, waitingLimit, waitingBudget
    /// Nach wiederholtem Fehler; Ton bleibt, „Erneut versuchen“
    case needsAttention
    /// Nichts Gesprochenes erkannt
    case empty
}

public enum ConversationOrigin: String, Codable, Sendable {
    /// Paply hat selbst aufgenommen
    case recording
    /// Über Teilen → Paply (z. B. iOS-Anrufaufnahme, Sprachmemo)
    case imported
}

/// Stufen der Auswertung, in dieser Reihenfolge. Fertige Stufen werden nach einer Unterbrechung nicht wiederholt.
public enum ConversationStage: String, Codable, Sendable, CaseIterable {
    /// Wer spricht wann (auf dem Gerät)
    case speakers
    /// Wortlaut (Groq Whisper) und Zuordnung Wort → Sprecher
    case transcript
    /// Titel, Zusammenfassung, Aufgaben, Thema, Namensvorschläge (Groq-LLM)
    case summary
}

public struct ConversationProgress: Codable, Sendable, Equatable {
    public var stage: ConversationStage
    /// 0…1 innerhalb der Stufe; nil = unbestimmt
    public var fraction: Double?

    public init(stage: ConversationStage, fraction: Double? = nil) {
        self.stage = stage
        self.fraction = fraction
    }
}

/// Lücke in der Aufnahme (z. B. Anruf hat unterbrochen). Sekunden ab Aufnahmebeginn, auf der Zeitachse der Datei.
public struct ConversationGap: Codable, Sendable, Equatable {
    public var at: Double
    /// Dauer der Unterbrechung in Echtzeit (in der Datei fehlt dieser Ton)
    public var seconds: Double
    /// "call", "interruption", "dictation" – nie Inhalt
    public var reason: String

    public init(at: Double, seconds: Double, reason: String) {
        self.at = at
        self.seconds = seconds
        self.reason = reason
    }
}

// MARK: - Sprecher

public enum SpeakerNameSource: String, Codable, Sendable {
    /// Unbekannt → Anzeige „Sprecher n“
    case none
    /// Stimmprofil des iPhone-Besitzers erkannt
    case owner
    /// Gespeichertes Stimmprofil einer Person sicher erkannt
    case profile
    /// Vom Nutzer gesetzt oder bestätigt (fasst die KI nie wieder an)
    case user
}

/// Vorschlag „Ist das Testname?“ – ein Tipp bestätigt, dann wird daraus ein Name mit `nameSource == .user`.
public struct SpeakerSuggestion: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// Stimme ähnelt einem gespeicherten Profil, aber nicht sicher genug für eine feste Zuordnung
        case profile
        /// Name stammt aus dem Gespräch („Hallo Herr Müller“, „Ich bin Testname“)
        case transcript
    }

    public var name: String
    public var personID: String?
    public var source: Source
    /// Wörtlicher Beleg aus dem Wortlaut (nur bei `.transcript`), vom Code im Text gefunden
    public var evidence: String?
    /// Ähnlichkeit 0…1 (nur bei `.profile`)
    public var score: Double?

    public init(name: String, personID: String? = nil, source: Source, evidence: String? = nil, score: Double? = nil) {
        self.name = name
        self.personID = personID
        self.source = source
        self.evidence = evidence
        self.score = score
    }
}

public struct ConversationSpeaker: Codable, Sendable, Identifiable, Equatable {
    /// "S1", "S2" … – stabil innerhalb des Gesprächs, nach Sprechanteil absteigend vergeben
    public var id: String
    /// Anzeigename; nil → „Sprecher n“. Für den Besitzer nil + `personID == VoicePerson.ownerID` (Anzeige „Ich“).
    public var name: String?
    public var personID: String?
    public var nameSource: SpeakerNameSource
    public var suggestion: SpeakerSuggestion?
    public var speechSeconds: Double
    /// Index in die Sprecher-Palette der Oberfläche (stabil, auch nach Zusammenlegen)
    public var colorIndex: Int

    public init(id: String, name: String? = nil, personID: String? = nil, nameSource: SpeakerNameSource = .none,
                suggestion: SpeakerSuggestion? = nil, speechSeconds: Double, colorIndex: Int) {
        self.id = id
        self.name = name
        self.personID = personID
        self.nameSource = nameSource
        self.suggestion = suggestion
        self.speechSeconds = speechSeconds
        self.colorIndex = colorIndex
    }

    public var isOwner: Bool { personID == VoicePerson.ownerID }
}

/// Ein Redebeitrag: zusammenhängende Sätze eines Sprechers.
public struct ConversationUtterance: Codable, Sendable, Identifiable, Equatable {
    /// "u0", "u1" …
    public var id: String
    public var speakerID: String
    public var start: Double
    public var end: Double
    public var text: String
    /// `.user`, wenn der Nutzer den Beitrag einem anderen Sprecher zugeordnet hat (fasst die KI nie wieder an)
    public var speakerOwner: Owner
    /// Zuordnung unsicher (Überlappung, sehr kurzer Einwurf) – Oberfläche markiert dezent
    public var uncertain: Bool

    public init(id: String, speakerID: String, start: Double, end: Double, text: String,
                speakerOwner: Owner = .ai, uncertain: Bool = false) {
        self.id = id
        self.speakerID = speakerID
        self.start = start
        self.end = end
        self.text = text
        self.speakerOwner = speakerOwner
        self.uncertain = uncertain
    }
}

/// `transcript.json` – kann groß werden (1 Std. ≈ 10 000 Wörter), deshalb getrennt von `conversation.json`.
public struct ConversationTranscript: Codable, Sendable, Equatable {
    public var utterances: [ConversationUtterance]
    public var languages: [String]
    public var model: String
    public var createdAt: Date

    public init(utterances: [ConversationUtterance], languages: [String], model: String, createdAt: Date) {
        self.utterances = utterances
        self.languages = languages
        self.model = model
        self.createdAt = createdAt
    }
}

// MARK: - Zusammenfassung

/// Zusage einer anderen Person („Ich schicke Ihnen das Angebot bis Freitag“) – steht im Gespräch, nicht im Aufgaben-Reiter.
public struct ConversationCommitment: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var speakerID: String
    public var text: String
    public var quote: String?
    public var dueHint: String?

    public init(id: String, speakerID: String, text: String, quote: String? = nil, dueHint: String? = nil) {
        self.id = id
        self.speakerID = speakerID
        self.text = text
        self.quote = quote
        self.dueHint = dueHint
    }
}

public struct ConversationSummary: Codable, Sendable, Equatable {
    /// 1–3 Sätze: Worum ging es, was kam heraus
    public var overview: String
    /// Kernpunkte und Entscheidungen, je ein kurzer Satz (höchstens 8)
    public var points: [String]
    public var commitments: [ConversationCommitment]

    public init(overview: String, points: [String], commitments: [ConversationCommitment] = []) {
        self.overview = overview
        self.points = points
        self.commitments = commitments
    }
}

// MARK: - Gespräch

/// `conversation.json`. Eine Datei je Gespräch, atomar geschrieben, `rev` steigt bei jeder Änderung.
public struct Conversation: Codable, Sendable, Identifiable, Equatable {
    public var schemaVersion: Int
    /// = ID des verknüpften Gedankens (`ThoughtIDs.thought()`)
    public var id: String
    public var createdAt: Date
    public var durationMs: Int
    public var origin: ConversationOrigin
    public var trigger: ThoughtTrigger
    public var state: ConversationState
    public var progress: ConversationProgress?
    public var status: Thought.Status
    /// Fertige Stufen (Wiederaufnahme nach Netz/Limit ohne Doppelarbeit)
    public var stagesDone: [ConversationStage]
    public var title: String?
    public var titleOwner: Owner
    public var summary: ConversationSummary?
    public var speakers: [ConversationSpeaker]
    /// Vorgabe für die Sprecherzahl (z. B. 2 bei einem Anruf-Import mit zwei Kanälen); nil = automatisch
    public var expectedSpeakers: Int?
    public var gaps: [ConversationGap]
    public var audio: Thought.AudioInfo?
    public var ai: Thought.AIInfo?
    public var rev: Int
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(schemaVersion: Int = 1, id: String = ThoughtIDs.thought(), createdAt: Date = Date(), durationMs: Int = 0,
                origin: ConversationOrigin, trigger: ThoughtTrigger, state: ConversationState,
                progress: ConversationProgress? = nil, status: Thought.Status = Thought.Status(),
                stagesDone: [ConversationStage] = [], title: String? = nil, titleOwner: Owner = .system,
                summary: ConversationSummary? = nil, speakers: [ConversationSpeaker] = [], expectedSpeakers: Int? = nil,
                gaps: [ConversationGap] = [], audio: Thought.AudioInfo? = nil, ai: Thought.AIInfo? = nil, rev: Int = 1,
                updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.origin = origin
        self.trigger = trigger
        self.state = state
        self.progress = progress
        self.status = status
        self.stagesDone = stagesDone
        self.title = title
        self.titleOwner = titleOwner
        self.summary = summary
        self.speakers = speakers
        self.expectedSpeakers = expectedSpeakers
        self.gaps = gaps
        self.audio = audio
        self.ai = ai
        self.rev = rev
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: - Stimmprofile (nur lokal, nie ins Netz)

public struct VoicePrint: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// Nebenbei aus einer Gedanken-Aufnahme gelernt
        case thought
        /// Aus einem Gespräch (nach Bestätigung oder sicherer Erkennung)
        case conversation
        /// Bewusst eingesprochen (Rückfall)
        case enrollment
    }

    /// L2-normalisiert
    public var vector: [Float]
    /// Embedding-Modell samt Version – Abdrücke verschiedener Modelle werden nie verglichen
    public var model: String
    /// Sprechzeit, aus der der Abdruck stammt
    public var seconds: Double
    public var source: Source
    public var createdAt: Date

    public init(vector: [Float], model: String, seconds: Double, source: Source, createdAt: Date = Date()) {
        self.vector = vector
        self.model = model
        self.seconds = seconds
        self.source = source
        self.createdAt = createdAt
    }
}

/// Eine bekannte Stimme. Der Besitzer hat die feste ID `ownerID`.
public struct VoicePerson: Codable, Sendable, Identifiable, Equatable {
    public static let ownerID = "owner"

    public var id: String
    /// Anzeigename; beim Besitzer leer (Oberfläche zeigt „Ich“)
    public var name: String
    /// Mehrere Abdrücke aus verschiedenen Lagen (nah, Lautsprecher, Raum); Obergrenze im Profil-Speicher
    public var prints: [VoicePrint]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, name: String, prints: [VoicePrint] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.prints = prints
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isOwner: Bool { id == Self.ownerID }
}

// MARK: - Diarisierung (Motor austauschbar; Android baut dasselbe mit sherpa-onnx)

public struct Diarization: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        public var start: Double
        public var end: Double
        public var cluster: Int

        public init(start: Double, end: Double, cluster: Int) {
            self.start = start
            self.end = end
            self.cluster = cluster
        }
    }

    public var segments: [Segment]
    /// L2-normalisierte Mittelwerte je Cluster
    public var centroids: [Int: [Float]]
    public var speechSeconds: [Int: Double]
    public var model: String

    public init(segments: [Segment], centroids: [Int: [Float]], speechSeconds: [Int: Double], model: String) {
        self.segments = segments
        self.centroids = centroids
        self.speechSeconds = speechSeconds
        self.model = model
    }
}

public protocol SpeakerDiarizing: Sendable {
    /// Name + Version des Embedding-Modells (= `VoicePrint.model`)
    var embeddingModel: String { get }
    /// Ganze Datei (16 kHz mono WAV). `expectedSpeakers` = feste Zahl, nil = automatisch.
    func diarize(audio: URL, expectedSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> Diarization
    /// Stimmabdruck aus einer Einzel-Aufnahme (Gedanke, Einsprechen). nil = zu wenig Sprache oder nicht eindeutig
    /// eine Stimme.
    func voiceprint(audio: URL) async throws -> VoicePrint?
}

// MARK: - Auswertung (PaplyKit, ohne Speicherzugriff)

public struct ConversationAnalysisInput: Sendable {
    public var id: String
    /// 16 kHz mono WAV
    public var audio: URL
    /// Zwischenstände der Stufen (Diarisierung, Whisper-Stücke) – Wiederaufnahme ohne Doppelarbeit
    public var workDirectory: URL
    public var recordedAt: Date
    public var expectedSpeakers: Int?
    public var gaps: [ConversationGap]
    /// Hauptsprache (Einstellung „Hauptsprache“), z. B. "de"
    public var mainLanguage: String
    /// „Eigene Begriffe“ + Namen bekannter Personen + Themennamen (Whisper-Hinweis, gekürzt)
    public var vocabulary: [String]
    public var topics: [TopicIndexEntry]
    /// Inklusive Besitzer (falls schon gelernt)
    public var people: [VoicePerson]
    /// Vom Nutzer schon gesetzte Dinge (Wiederholung der Auswertung): bleiben unangetastet
    public var previous: Conversation?

    public init(id: String, audio: URL, workDirectory: URL, recordedAt: Date, expectedSpeakers: Int?, gaps: [ConversationGap],
                mainLanguage: String, vocabulary: [String], topics: [TopicIndexEntry], people: [VoicePerson],
                previous: Conversation?) {
        self.id = id
        self.audio = audio
        self.workDirectory = workDirectory
        self.recordedAt = recordedAt
        self.expectedSpeakers = expectedSpeakers
        self.gaps = gaps
        self.mainLanguage = mainLanguage
        self.vocabulary = vocabulary
        self.topics = topics
        self.people = people
        self.previous = previous
    }
}

public struct ConversationAnalysis: Sendable, Equatable {
    public var stagesDone: [ConversationStage]
    public var speakers: [ConversationSpeaker]
    /// Stimmabdruck je Sprecher-ID (für spätere Bestätigung → Profil), bleibt lokal
    public var speakerPrints: [String: VoicePrint]
    public var transcript: ConversationTranscript?
    public var title: String?
    public var summary: ConversationSummary?
    /// Aufgaben des Besitzers (bzw. ohne klaren Zuständigen) → Gedanke → Reiter „Aufgaben“
    public var tasks: [TaskDraft]
    public var topic: TopicDecision?
    public var audioSeconds: Double
    public var usage: TokenUsage?
    public var model: String?

    public init(stagesDone: [ConversationStage], speakers: [ConversationSpeaker], speakerPrints: [String: VoicePrint],
                transcript: ConversationTranscript?, title: String?, summary: ConversationSummary?, tasks: [TaskDraft],
                topic: TopicDecision?, audioSeconds: Double, usage: TokenUsage?, model: String?) {
        self.stagesDone = stagesDone
        self.speakers = speakers
        self.speakerPrints = speakerPrints
        self.transcript = transcript
        self.title = title
        self.summary = summary
        self.tasks = tasks
        self.topic = topic
        self.audioSeconds = audioSeconds
        self.usage = usage
        self.model = model
    }
}

public enum ConversationAnalysisOutcome: Sendable, Equatable {
    case done(ConversationAnalysis)
    /// Ein Teil ist fertig (z. B. Sprecher + Wortlaut), der Rest wartet (Netz, Schlüssel, Limit, Kontingent).
    /// Die Oberfläche zeigt den fertigen Teil sofort.
    case partial(ConversationAnalysis, waiting: ConversationState, retryAt: Date?, message: String)
    /// Noch nichts fertig, wartet
    case wait(ConversationState, retryAt: Date?, message: String)
    /// Nichts Gesprochenes
    case empty
    /// Fehler ohne Aussicht durch bloßes Warten (Code, nie Inhalt)
    case failed(code: String)
}

public protocol ConversationAnalyzing: Sendable {
    func analyze(_ input: ConversationAnalysisInput, apiKey: String,
                 progress: @escaping @Sendable (ConversationProgress) -> Void) async -> ConversationAnalysisOutcome
}

// MARK: - Aufnahme → Ablage (App ruft, PaplyKit-Speicher setzt um)

/// Was die Aufnahme (App) vom Gesprächs-Speicher braucht.
public protocol ConversationRecordingStore: Sendable {
    /// Legt Eintrag (`state == .recording`) und leere WAV an – synchron vor jedem Netz-/Mikrozugriff.
    func beginRecording(trigger: ThoughtTrigger, at: Date) async throws -> (conversation: Conversation, audio: WAVWriter)
    /// Aufnahme beendet: Dauer und Lücken festhalten, `state → .captured`.
    func finishRecording(_ id: String, durationMs: Int, gaps: [ConversationGap]) async throws -> Conversation?
    /// Verwerfen (landet in „Zuletzt gelöscht“, wiederherstellbar)
    func discardRecording(_ id: String) async
    /// Fremde Audiodatei übernehmen (Teilen → Paply): kopiert, wandelt nach 16 kHz mono WAV, `state == .captured`.
    /// `expectedSpeakers` = 2, wenn die Datei zwei getrennte Kanäle hat.
    func importAudio(from url: URL, at: Date) async throws -> Conversation
}
