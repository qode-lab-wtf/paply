import Foundation

// Schnittstellen-Verträge für „Gedanken“ (KONZEPT.md §9.2). Vom Koordinator vorab festgelegt –
// Änderungen nur in Absprache. Zeiten sind `Date`; auf der Platte als Millisekunden seit 1970
// (Encoder/Decoder mit `.millisecondsSince1970`, siehe §7.2). Schlüssel in camelCase wie am Mac.

public enum ThoughtIDs {
    /// "s_" + 32 hex (= Mac-Quellen-ID)
    public static func thought() -> String { "s_" + hex32() }
    /// "t_" + 32 hex
    public static func topic() -> String { "t_" + hex32() }
    /// "k_" + 32 hex
    public static func task() -> String { "k_" + hex32() }

    private static func hex32() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

public enum Owner: String, Codable, Sendable { case ai, user, system }

public enum ThoughtTrigger: String, Codable, Sendable { case control, shortcut, app, liveActivity, unknown }

public enum ThoughtState: String, Codable, Sendable {
    case recording, captured, transcribing, transcribed, structuring, done
    case waitingNetwork, waitingKey, waitingLimit, waitingBudget, needsAttention, empty
}

public enum TopicIcon: String, Codable, Sendable, CaseIterable {
    case sparkles, lightbulb, home, code, mapPin = "map-pin", sun, moon, heart, coffee, briefcase, calendar
    case messageCircle = "message-circle", book, music, camera, leaf, flag, circleHelp = "circle-help", pencil
    case plane, wallet, users, list, zap
}

public enum LinkKind: String, Codable, Sendable { case continues, sameMatter = "same_matter", changes }

public struct ThoughtTask: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var text: String
    public var quote: String?
    public var dueHint: String?
    public var dueAt: Date?
    /// Im Wortlaut stand eine Uhrzeit, und `dueAt` liegt auf ihr („morgen um 12 Uhr“, „um halb drei“) – festgehalten
    /// beim Auflösen von `dueHint`. Fehlt in älteren Dateien (nil): Dann entscheidet der Wortlaut (`TaskDueLabel`).
    public var dueHasTime: Bool?
    public var done: Bool
    public var doneAt: Date?
    public var owner: Owner
    public var createdAt: Date

    public init(id: String = ThoughtIDs.task(), text: String, quote: String? = nil, dueHint: String? = nil,
                dueAt: Date? = nil, dueHasTime: Bool? = nil, done: Bool = false, doneAt: Date? = nil, owner: Owner,
                createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.quote = quote
        self.dueHint = dueHint
        self.dueAt = dueAt
        self.dueHasTime = dueHasTime
        self.done = done
        self.doneAt = doneAt
        self.owner = owner
        self.createdAt = createdAt
    }
}

public struct ThoughtLink: Codable, Sendable, Equatable {
    public var target: String
    public var kind: LinkKind
    public var reason: String
    public var origin: Owner
    public var createdAt: Date

    public init(target: String, kind: LinkKind, reason: String, origin: Owner, createdAt: Date = Date()) {
        self.target = target
        self.kind = kind
        self.reason = reason
        self.origin = origin
        self.createdAt = createdAt
    }
}

/// `thought.json` (§7.3). Eine Datei je Gedanke, atomar geschrieben, `rev` steigt bei jeder Änderung.
public struct Thought: Codable, Sendable, Identifiable, Equatable {
    public struct AIInfo: Codable, Sendable, Equatable {
        public var model: String
        public var promptVersion: Int
        public var tokens: Int
        public var at: Date
        /// Codes des Sicherheitsnetzes, nie Text
        public var rejections: [String]

        public init(model: String, promptVersion: Int, tokens: Int, at: Date, rejections: [String] = []) {
            self.model = model
            self.promptVersion = promptVersion
            self.tokens = tokens
            self.at = at
            self.rejections = rejections
        }
    }

    /// Ton nur bis zum Rohtext: Liegt `source.json`, löscht der Speicher die Datei und setzt `audio = nil`.
    public struct AudioInfo: Codable, Sendable, Equatable {
        /// "audio.wav" im Ordner des Gedankens (Altbestand: "audio.m4a")
        public var file: String

        public init(file: String) {
            self.file = file
        }
    }

    public struct Status: Codable, Sendable, Equatable {
        /// kurzer deutscher Hinweis (z. B. „wartet auf Netz“), nie Diktattext
        public var message: String?
        public var attempts: Int
        public var retryAt: Date?

        public init(message: String? = nil, attempts: Int = 0, retryAt: Date? = nil) {
            self.message = message
            self.attempts = attempts
            self.retryAt = retryAt
        }
    }

    public var schemaVersion: Int
    public var id: String
    /// "voice" (später ggf. weitere Arten)
    public var kind: String
    public var createdAt: Date
    public var durationMs: Int
    public var trigger: ThoughtTrigger
    public var state: ThoughtState
    public var title: String?
    public var titleOwner: Owner
    public var text: String?
    public var textOwner: Owner
    public var textIsRaw: Bool
    public var topicId: String?
    public var topicOwner: Owner
    public var tasks: [ThoughtTask]
    public var links: [ThoughtLink]
    public var languages: [String]
    public var keywords: [String]
    public var ai: AIInfo?
    public var audio: AudioInfo?
    public var status: Status
    public var rev: Int
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        schemaVersion: Int = 1,
        id: String = ThoughtIDs.thought(),
        kind: String = "voice",
        createdAt: Date = Date(),
        durationMs: Int = 0,
        trigger: ThoughtTrigger,
        state: ThoughtState,
        title: String? = nil,
        titleOwner: Owner = .system,
        text: String? = nil,
        textOwner: Owner = .system,
        textIsRaw: Bool = false,
        topicId: String? = nil,
        topicOwner: Owner = .system,
        tasks: [ThoughtTask] = [],
        links: [ThoughtLink] = [],
        languages: [String] = [],
        keywords: [String] = [],
        ai: AIInfo? = nil,
        audio: AudioInfo? = nil,
        status: Status = Status(),
        rev: Int = 1,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.trigger = trigger
        self.state = state
        self.title = title
        self.titleOwner = titleOwner
        self.text = text
        self.textOwner = textOwner
        self.textIsRaw = textIsRaw
        self.topicId = topicId
        self.topicOwner = topicOwner
        self.tasks = tasks
        self.links = links
        self.languages = languages
        self.keywords = keywords
        self.ai = ai
        self.audio = audio
        self.status = status
        self.rev = rev
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// `source.json` (§7.3) – einmal geschrieben, danach unveränderlich.
public struct ThoughtSource: Codable, Sendable, Equatable {
    public struct Sentence: Codable, Sendable, Equatable {
        /// "<Gedanken-ID>_s<i>"
        public var id: String
        public var text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    public var text: String
    public var sentences: [Sentence]
    public var model: String
    public var createdAt: Date
    public var languages: [String]
    public var audioSeconds: Double

    public init(text: String, sentences: [Sentence], model: String, createdAt: Date, languages: [String], audioSeconds: Double) {
        self.text = text
        self.sentences = sentences
        self.model = model
        self.createdAt = createdAt
        self.languages = languages
        self.audioSeconds = audioSeconds
    }
}

public struct Topic: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var icon: TopicIcon
    public var owner: Owner
    public var createdAt: Date
    public var mergedInto: String?
    /// „Worum geht's?“ – kurze Beschreibung des Nutzers (Namen, Firmen, Personen), höchstens
    /// `maxNoteLength` Zeichen. nil = keine. Fehlt in älteren `topics.json` und wird dann nicht geschrieben.
    public var note: String?

    public init(id: String = ThoughtIDs.topic(), title: String, icon: TopicIcon, owner: Owner, createdAt: Date = Date(),
                mergedInto: String? = nil, note: String? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.owner = owner
        self.createdAt = createdAt
        self.mergedInto = mergedInto
        self.note = note
    }

    public static let maxNoteLength = 200

    /// Beschreibung in Speicherform: getrimmt, höchstens `maxNoteLength` Zeichen, leer = nil.
    public static func normalizedNote(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxNoteLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Die Beschreibung, falls vorhanden (getrimmt, nicht leer).
    public var describedNote: String? { Self.normalizedNote(note) }

    /// Vom Nutzer angelegt oder beschrieben: wird nie automatisch zusammengeführt oder umbenannt.
    /// Entfernt wird es wie jedes Thema, wenn sein letzter Gedanke endgültig gelöscht ist – außer es hat eine
    /// Beschreibung, dann bleibt es immer (`ThoughtStore.pruneTopics`, ENTSCHEIDUNGEN 2026-10-27). Ein von Hand
    /// angelegtes, noch leeres Thema bleibt ebenfalls stehen.
    public var isUserDefined: Bool { owner == .user || describedNote != nil }
}

// MARK: - KI (H1 implementiert, H2 ruft auf)

public struct TopicIndexEntry: Sendable, Equatable {
    public var topicID: String
    public var name: String
    public var count: Int
    public var hint: [String]
    /// Beschreibung des Nutzers (`Topic.note`), geht als `about` mit; nil = keine
    public var about: String?
    /// Ein Name oder Stichwort aus Name/Beschreibung steht im Transkript (`TopicMentions`). Solche Themen
    /// kommen immer in den Index und überstehen jede Kürzung des Prompts.
    public var mentioned: Bool

    public init(topicID: String, name: String, count: Int, hint: [String], about: String? = nil, mentioned: Bool = false) {
        self.topicID = topicID
        self.name = name
        self.count = count
        self.hint = hint
        self.about = about
        self.mentioned = mentioned
    }
}

public struct CandidateEntry: Sendable, Equatable {
    public var thoughtID: String
    public var title: String
    public var topicID: String?
    public var when: String
    public var excerpt: String
    public var localScore: Double

    public init(thoughtID: String, title: String, topicID: String?, when: String, excerpt: String, localScore: Double) {
        self.thoughtID = thoughtID
        self.title = title
        self.topicID = topicID
        self.when = when
        self.excerpt = excerpt
        self.localScore = localScore
    }
}

public struct StructureInput: Sendable {
    public var transcript: String
    public var sentences: [ThoughtSource.Sentence]
    public var spokenLanguages: [String]
    public var uiLanguage: String
    public var vocabulary: String
    public var topics: [TopicIndexEntry]
    public var topicsFull: Bool
    public var candidates: [CandidateEntry]
    /// nil = ganzer Gedanke
    public var part: (index: Int, count: Int)?
    /// "low" | "medium"
    public var reasoningEffort: String
    /// Aufnahmezeit des Gedankens (`thought.createdAt`); `now` im Prompt. nil = Zeitpunkt der Verarbeitung.
    public var recordedAt: Date?

    public init(transcript: String, sentences: [ThoughtSource.Sentence], spokenLanguages: [String], uiLanguage: String,
                vocabulary: String, topics: [TopicIndexEntry], topicsFull: Bool, candidates: [CandidateEntry],
                part: (index: Int, count: Int)? = nil, reasoningEffort: String = "low", recordedAt: Date? = nil) {
        self.transcript = transcript
        self.sentences = sentences
        self.spokenLanguages = spokenLanguages
        self.uiLanguage = uiLanguage
        self.vocabulary = vocabulary
        self.topics = topics
        self.topicsFull = topicsFull
        self.candidates = candidates
        self.part = part
        self.reasoningEffort = reasoningEffort
        self.recordedAt = recordedAt
    }
}

public enum TopicDecision: Sendable, Equatable {
    case existing(String)
    case new(name: String, icon: TopicIcon)
    case none
}

public struct TaskDraft: Sendable, Equatable {
    public var text: String
    public var quote: String
    public var dueHint: String?

    public init(text: String, quote: String, dueHint: String? = nil) {
        self.text = text
        self.quote = quote
        self.dueHint = dueHint
    }
}

public struct RelatedDraft: Sendable, Equatable {
    public var thoughtID: String
    public var kind: LinkKind
    public var reason: String

    public init(thoughtID: String, kind: LinkKind, reason: String) {
        self.thoughtID = thoughtID
        self.kind = kind
        self.reason = reason
    }
}

public struct StructureResult: Sendable, Equatable {
    public var title: String
    /// nil = Sicherheitsnetz → Rohtext
    public var cleanText: String?
    public var topic: TopicDecision
    public var tasks: [TaskDraft]
    public var related: [RelatedDraft]
    /// Codes, nie Text
    public var rejections: [String]

    public init(title: String, cleanText: String?, topic: TopicDecision, tasks: [TaskDraft], related: [RelatedDraft], rejections: [String] = []) {
        self.title = title
        self.cleanText = cleanText
        self.topic = topic
        self.tasks = tasks
        self.related = related
        self.rejections = rejections
    }
}

public struct TokenUsage: Sendable, Equatable {
    public var prompt: Int
    public var completion: Int
    public var total: Int

    public init(prompt: Int, completion: Int, total: Int) {
        self.prompt = prompt
        self.completion = completion
        self.total = total
    }
}

public enum StructureOutcome: Sendable, Equatable {
    case success(StructureResult, model: String, usage: TokenUsage)
    /// waitingKey/Network/Limit/Budget
    case wait(ThoughtState, retryAt: Date?, message: String)
    /// nach Wiederholung → Rohtext
    case unusable(code: String)
}

public protocol ThoughtStructuring: Sendable {
    func structure(_ input: StructureInput, apiKey: String) async -> StructureOutcome
}

// MARK: - Lokal (H2)

public protocol CandidateFinding: Sendable {
    func topicIndex(forText: String, languages: [String]) async -> (entries: [TopicIndexEntry], full: Bool)
    func candidates(forText: String, languages: [String], excluding: String) async -> [CandidateEntry]
    /// Wie `candidates(forText:languages:excluding:)`, aber Zeitbezug (`when` wie „heute 09:40“, 3-h-Fenster,
    /// Aktualität) relativ zu `reference` – der Aufnahmezeit des Gedankens.
    func candidates(forText: String, languages: [String], excluding: String, relativeTo reference: Date) async -> [CandidateEntry]
    /// Embedding/Schlagwörter fortschreiben
    func didChange(_ thought: Thought) async
}

extension CandidateFinding {
    /// Standard für einfache Umsetzungen (Tests): ohne eigenen Zeitbezug.
    public func candidates(forText text: String, languages: [String], excluding: String,
                           relativeTo reference: Date) async -> [CandidateEntry] {
        await candidates(forText: text, languages: languages, excluding: excluding)
    }
}

public enum ProcessorEvent: Sendable, Equatable {
    case processing(String)
    case saved(String, topicTitle: String?, topicIcon: TopicIcon?)
    case waiting(String, ThoughtState, message: String)
    case empty(String)
    case failed(String, message: String)
}

public struct ProcessorEnvironment: Sendable {
    public var apiKey: @Sendable () async -> String?
    public var isOnline: @Sendable () async -> Bool
    public var isDictationBusy: @Sendable () async -> Bool
    public var settings: @Sendable () async -> PaplySettings
    public var uiLanguage: String

    public init(apiKey: @escaping @Sendable () async -> String?, isOnline: @escaping @Sendable () async -> Bool,
                isDictationBusy: @escaping @Sendable () async -> Bool, settings: @escaping @Sendable () async -> PaplySettings,
                uiLanguage: String) {
        self.apiKey = apiKey
        self.isOnline = isOnline
        self.isDictationBusy = isDictationBusy
        self.settings = settings
        self.uiLanguage = uiLanguage
    }
}

// Die Akteure/Klassen des Vertrags liegen bei ihren Besitzern (gleiche Signaturen wie §9.2):
// TokenLedger → Thoughts/Budget/TokenLedger.swift (H1)
// ThoughtStore, WAVWriter → Thoughts/Store/ (H2)
// ThoughtProcessor → Thoughts/Processing/ThoughtProcessor.swift (H2)
