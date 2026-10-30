import Foundation

/// Einstellungen, die die App an die Pipeline gibt.
public struct PaplySettings: Sendable, Codable, Equatable {
    public var transcriptionModel: String
    public var polishModel: String
    public var fallbackPolishModel: String
    /// „Eigene Begriffe“, Komma- oder Zeilen-getrennt.
    public var vocabulary: String
    /// nil = automatisch erkennen (Standard).
    public var language: String?
    public var chunkedUpload: Bool
    /// Ergänzung: Sprachen, die der Nutzer spricht (ISO 639-1, z. B. ["de", "en"]).
    /// Leer = Gerätesprachen. Dient dem Sprachwechsel-Beispiel im Whisper-Prompt und der
    /// Sprachwache (`LanguageGuard`: kurze Stücke, fremd erkannte Sprachen).
    public var spokenLanguages: [String]
    /// Ergänzung: Hauptsprache (ISO 639-1). Kurze Stücke werden ohne Erkennung direkt in ihr
    /// geschrieben, fremd erkannte Sprachen mit ihr neu transkribiert (`LanguageGuard`).
    /// nil/leer oder nicht unter den Nutzersprachen = die erste Nutzersprache.
    public var primaryLanguage: String?

    public init() {
        transcriptionModel = "whisper-large-v3"
        polishModel = "qwen/qwen3.8-27b"
        fallbackPolishModel = "openai/gpt-oss-120b"
        vocabulary = ""
        language = nil
        chunkedUpload = true
        spokenLanguages = []
        primaryLanguage = nil
    }

    private enum CodingKeys: String, CodingKey {
        case transcriptionModel, polishModel, fallbackPolishModel, vocabulary, language, chunkedUpload, spokenLanguages,
             primaryLanguage
    }

    /// Fehlende Felder (ältere gespeicherte Einstellungen) bekommen den Standardwert.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transcriptionModel = try c.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? transcriptionModel
        polishModel = try c.decodeIfPresent(String.self, forKey: .polishModel) ?? polishModel
        fallbackPolishModel = try c.decodeIfPresent(String.self, forKey: .fallbackPolishModel) ?? fallbackPolishModel
        vocabulary = try c.decodeIfPresent(String.self, forKey: .vocabulary) ?? vocabulary
        language = try c.decodeIfPresent(String.self, forKey: .language)
        chunkedUpload = try c.decodeIfPresent(Bool.self, forKey: .chunkedUpload) ?? chunkedUpload
        spokenLanguages = try c.decodeIfPresent([String].self, forKey: .spokenLanguages) ?? spokenLanguages
        primaryLanguage = try c.decodeIfPresent(String.self, forKey: .primaryLanguage)
    }
}

/// Zeiten in Millisekunden ab `finish()`.
public struct DictationTimings: Sendable, Codable {
    public var transcriptionDoneMs: Double?
    public var polishDoneMs: Double?
    public var totalMs: Double?
    public var chunkCount: Int
    public var uploadedBytes: Int
    public var audioSeconds: Double

    public init(
        transcriptionDoneMs: Double? = nil,
        polishDoneMs: Double? = nil,
        totalMs: Double? = nil,
        chunkCount: Int = 0,
        uploadedBytes: Int = 0,
        audioSeconds: Double = 0
    ) {
        self.transcriptionDoneMs = transcriptionDoneMs
        self.polishDoneMs = polishDoneMs
        self.totalMs = totalMs
        self.chunkCount = chunkCount
        self.uploadedBytes = uploadedBytes
        self.audioSeconds = audioSeconds
    }
}

public struct DictationOutcome: Sendable, Codable {
    /// Einzusetzender Text (poliert oder Rohtext-Rückfall); "" = nichts einsetzen.
    public var text: String
    public var raw: String
    public var polished: String?
    /// Grund, falls das Sicherheitsnetz anschlug (`PolishRejectionCode.rawValue`).
    public var polishRejection: String?
    /// Deutscher Text bei echtem Fehler.
    public var errorMessage: String?
    /// Erkannte Sprachen (ISO 639-1), in Reihenfolge des Auftretens.
    public var languages: [String]
    public var timings: DictationTimings
    /// Ergänzung: technischer Grund, warum nicht poliert wurde (`PolishFailureCode.rawValue`);
    /// nie Diktattext. `text` ist dann der Rohtext.
    public var polishError: String?
    /// Ergänzung: tatsächlich verwendetes Polier-Modell.
    public var polishModel: String?
    /// Ergänzung: true, wenn nichts eingesetzt wird, weil keine Sprache erkannt wurde
    /// (Stille, Rauschen, nur Halluzination/Echo verworfen). Die App kann dann
    /// „Nichts verstanden“ zeigen statt still zu bleiben. Bei Fehlern false.
    public var noSpeech: Bool
    /// Ergänzung: woher die Sprache je Teil kam (`LanguageSource.rawValue`), in Reihenfolge
    /// der Teile – fürs Diagnoseprotokoll (Sprachwache).
    public var languageSources: [String]

    public init(
        text: String = "",
        raw: String = "",
        polished: String? = nil,
        polishRejection: String? = nil,
        errorMessage: String? = nil,
        languages: [String] = [],
        timings: DictationTimings = DictationTimings(),
        polishError: String? = nil,
        polishModel: String? = nil,
        noSpeech: Bool = false,
        languageSources: [String] = []
    ) {
        self.text = text
        self.raw = raw
        self.polished = polished
        self.polishRejection = polishRejection
        self.errorMessage = errorMessage
        self.languages = languages
        self.timings = timings
        self.polishError = polishError
        self.polishModel = polishModel
        self.noSpeech = noSpeech
        self.languageSources = languageSources
    }

    /// `polishError` als Aufzählung.
    public var polishFailure: PolishFailureCode? { polishError.flatMap(PolishFailureCode.init(rawValue:)) }
    /// `polishRejection` als Aufzählung.
    public var polishRejectionCode: PolishRejectionCode? { polishRejection.flatMap(PolishRejectionCode.init(rawValue:)) }

    private enum CodingKeys: String, CodingKey {
        case text, raw, polished, polishRejection, errorMessage, languages, timings, polishError, polishModel, noSpeech,
             languageSources
    }

    /// Fehlende (neuere) Felder bekommen ihren Standardwert.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
            raw: try c.decodeIfPresent(String.self, forKey: .raw) ?? "",
            polished: try c.decodeIfPresent(String.self, forKey: .polished),
            polishRejection: try c.decodeIfPresent(String.self, forKey: .polishRejection),
            errorMessage: try c.decodeIfPresent(String.self, forKey: .errorMessage),
            languages: try c.decodeIfPresent([String].self, forKey: .languages) ?? [],
            timings: try c.decodeIfPresent(DictationTimings.self, forKey: .timings) ?? DictationTimings(),
            polishError: try c.decodeIfPresent(String.self, forKey: .polishError),
            polishModel: try c.decodeIfPresent(String.self, forKey: .polishModel),
            noSpeech: try c.decodeIfPresent(Bool.self, forKey: .noSpeech) ?? false,
            languageSources: try c.decodeIfPresent([String].self, forKey: .languageSources) ?? [])
    }
}

/// Stabile Gründe, warum nicht poliert wurde (Werte von `DictationOutcome.polishError`).
public enum PolishFailureCode: String, Sendable, Codable, CaseIterable {
    /// Polieren abgeschaltet (`PipelineOptions.polish = false`).
    case disabled
    /// Weder Polier- noch Ausweichmodell verfügbar.
    case modelUnavailable = "model-unavailable"
    /// Groq-Limit (HTTP 429), z. B. Tages-Tokens im Free-Tier.
    case rateLimited = "rate-limited"
    /// Schlüssel abgelehnt (401/403).
    case unauthorized
    /// Störung bei Groq (5xx).
    case serverError = "server-error"
    /// Sonstige abgelehnte Anfrage (4xx).
    case requestRejected = "request-rejected"
    /// Keine oder abgerissene Verbindung.
    case network
    /// Unlesbare Antwort.
    case invalidResponse = "invalid-response"
    /// Abgebrochen.
    case cancelled
}

/// Woher die Sprache eines Teils kam (Werte von `DictationOutcome.languageSources`).
public enum LanguageSource: String, Sendable, Codable, CaseIterable {
    /// Whisper hat selbst erkannt.
    case auto
    /// Kurzes Stück: Sprache direkt mitgeschickt (Vorstück oder Hauptsprache).
    case short
    /// Fremde Sprache erkannt, mit der Hauptsprache neu transkribiert.
    case redo
    /// Fremde Sprache erkannt, Neutranskription scheiterte: erstes Ergebnis behalten.
    case redoFailed = "redo-failed"
    /// Feste Sprache aus den Einstellungen.
    case fixed
}

/// Stabile Gründe des Sicherheitsnetzes (Werte von `DictationOutcome.polishRejection`).
public enum PolishRejectionCode: String, Sendable, Codable, CaseIterable {
    case empty, meta, length, content, negation, digits, replaced, inserted, added, truncated
}
