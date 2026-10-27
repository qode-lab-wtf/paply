import Foundation

/// Zusammenfassung der Sprachaktivität einer Aufnahme (wie Desktop `VoiceActivityMeta`).
struct VoiceActivityMeta: Sendable, Codable, Equatable {
    var durationMs: Double
    var measuredMs: Double
    /// Zeit mit Pegel über Grundrauschen + 15 dB (mind. −65 dBFS).
    var speechMs: Double
    /// Höchster RMS-Pegel eines Messfensters.
    var peakDbfs: Double
    /// 15. Perzentil der Fensterpegel.
    var floorDbfs: Double
    var maxGapMs: Double
    /// iOS-Ergänzung: Zeit mit stimmhafter (periodischer) Sprache; nil = nicht gemessen.
    var voicedMs: Double?

    init(durationMs: Double, measuredMs: Double, speechMs: Double, peakDbfs: Double,
                floorDbfs: Double, maxGapMs: Double, voicedMs: Double? = nil) {
        self.durationMs = durationMs
        self.measuredMs = measuredMs
        self.speechMs = speechMs
        self.peakDbfs = peakDbfs
        self.floorDbfs = floorDbfs
        self.maxGapMs = maxGapMs
        self.voicedMs = voicedMs
    }
}

/// Whisper-Segment aus `verbose_json`; alle Felder tolerant optional.
package struct WhisperSegment: Codable, Sendable, Equatable {
    var start: Double?
    var end: Double?
    var text: String?
    var avgLogprob: Double?
    var noSpeechProb: Double?
    var compressionRatio: Double?

    enum CodingKeys: String, CodingKey {
        case start, end, text
        case avgLogprob = "avg_logprob"
        case noSpeechProb = "no_speech_prob"
        case compressionRatio = "compression_ratio"
    }

    init(text: String?, start: Double? = nil, end: Double? = nil, avgLogprob: Double? = nil,
         noSpeechProb: Double? = nil, compressionRatio: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.avgLogprob = avgLogprob
        self.noSpeechProb = noSpeechProb
        self.compressionRatio = compressionRatio
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try? c.decodeIfPresent(Double.self, forKey: .start)
        end = try? c.decodeIfPresent(Double.self, forKey: .end)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        avgLogprob = try? c.decodeIfPresent(Double.self, forKey: .avgLogprob)
        noSpeechProb = try? c.decodeIfPresent(Double.self, forKey: .noSpeechProb)
        compressionRatio = try? c.decodeIfPresent(Double.self, forKey: .compressionRatio)
    }
}

/// Stille- und Halluzinationsfilter (Port von electron-menubar/audio/silence-filter.js,
/// mehrsprachig erweitert). Fehlende/zweifelhafte Signale bedeuten immer: behalten.
enum SilenceFilter {
    static let noSpeechProb = 0.6
    static let lowLogprob = -1.0

    struct Result: Equatable {
        var text: String
        var droppedSegments: Int
        var reason: String?
        /// Behaltene Segmente (für „unsicher gehört“).
        var keptSegments: [WhisperSegment]
    }

    static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        var out = String.UnicodeScalarView()
        var lastWasSpace = false
        for scalar in folded.unicodeScalars {
            if TextAnalysis.isLetter(scalar) || TextAnalysis.isNumber(scalar) || TextAnalysis.isMark(scalar) {
                out.append(scalar)
                lastWasSpace = false
            } else if scalar.properties.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            }
        }
        return String(out).trimmed
    }

    /// Typische Whisper-Phrasen bei Stille. Nur bei kaum Sprachaktivität verwerfen –
    /// absichtlich diktiertes „Danke.“ bleibt.
    static let silencePhrases: Set<String> = Set([
        // Deutsch (wie Desktop)
        "Vielen Dank.", "Danke.", "Vielen Dank fürs Zuschauen.", "Danke fürs Zuschauen.",
        "Vielen Dank für Ihre Aufmerksamkeit.", "Bis zum nächsten Mal.", "Tschüss.",
        "Danke fürs Zuhören.", "Vielen Dank fürs Zuhören.", "Bis bald.",
        // Englisch
        "Thank you.", "Thanks.", "Thanks for watching!", "Thank you for watching!",
        "Thank you very much.", "Thank you so much.", "Thanks for listening.", "Bye.", "Bye-bye.",
        "You", "Please subscribe.", "See you next time.",
        // Französisch
        "Merci.", "Merci beaucoup.", "Merci d'avoir regardé.", "Merci de votre attention.", "Au revoir.",
        // Spanisch
        "Gracias.", "Muchas gracias.", "Gracias por ver.", "Gracias por ver el video.", "¡Suscríbete!",
        // Italienisch
        "Grazie.", "Grazie mille.", "Grazie per la visione.", "Grazie a tutti.",
        // Portugiesisch
        "Obrigado.", "Obrigada.", "Muito obrigado.", "Obrigado por assistir.",
        // Niederländisch
        "Dank je.", "Dank je wel.", "Dank u wel.", "Bedankt.", "Bedankt voor het kijken.",
        // Türkisch
        "Teşekkürler.", "Teşekkür ederim.", "İzlediğiniz için teşekkürler.",
        // Polnisch
        "Dziękuję.", "Dzięki.", "Dziękuję za uwagę.", "Dziękuję bardzo.",
        // Russisch
        "Спасибо.", "Спасибо за внимание.", "Продолжение следует...",
        // Japanisch, Chinesisch, Koreanisch
        "ご視聴ありがとうございました", "ありがとうございました", "谢谢观看", "謝謝觀看", "谢谢", "감사합니다.",
        "시청해주셔서 감사합니다.",
    ].map(normalize))

    /// Eindeutige Untertitel-/Abspann-Artefakte. Nur vollständige Phrasen treffen:
    /// Erwähnungen innerhalb eines Diktats bleiben.
    static let artifactPhrases: Set<String> = Set([
        "Amara.org", "Untertitel von der Amara.org-Community", "Untertitel der Amara.org-Community",
        "Subtitles by the Amara.org community", "Sous-titres réalisés par la communauté d'Amara.org",
        "Sous-titrage Société Radio-Canada", "Sous-titrage ST' 501",
        "Subtítulos realizados por la comunidad de Amara.org", "Subtítulos por la comunidad de Amara.org",
        "Sottotitoli creati dalla comunità Amara.org", "Sottotitoli a cura di QTSS",
        "Legendas pela comunidade Amara.org", "Legendas pela comunidade de Amara.org",
        "Ondertiteld door de Amara.org gemeenschap", "Ondertiteling door de Amara.org gemeenschap",
        "Napisy stworzone przez społeczność Amara.org", "Napisy wykonane przez społeczność Amara.org",
        "Altyazı M.K.", "Субтитры сделал DimaTorzok", "Субтитры создавал DimaTorzok",
        "字幕由Amara.org社区提供", "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目",
    ].map(normalize))

    private static let zdf = Pattern("^untertitel im auftrag des zdf(?: für funk)?(?: \\d{4})?$")
    private static let zdfFunk = Pattern("^untertitelung des zdf für funk(?: \\d{4})?$")
    private static let copyright = Pattern("^copyright(?: (?:wdr|zdf|ndr|swr|ard)(?: \\d{4})?)?$")

    static func isArtifactPhrase(_ normalized: String) -> Bool {
        artifactPhrases.contains(normalized) || zdf.matches(normalized)
            || zdfFunk.matches(normalized) || copyright.matches(normalized)
    }

    static func validate(_ meta: VoiceActivityMeta?) -> VoiceActivityMeta? {
        guard let m = meta else { return nil }
        let values = [m.durationMs, m.measuredMs, m.speechMs, m.peakDbfs, m.floorDbfs, m.maxGapMs]
        guard values.allSatisfy(\.isFinite),
              m.durationMs > 0, m.measuredMs >= 0, m.measuredMs <= m.durationMs,
              m.speechMs >= 0, m.speechMs <= m.measuredMs, m.maxGapMs >= 0,
              m.peakDbfs <= 0, m.peakDbfs >= -120, m.floorDbfs >= -120, m.floorDbfs <= m.peakDbfs
        else { return nil }
        if let voiced = m.voicedMs, !(voiced.isFinite && voiced >= 0 && voiced <= m.measuredMs) {
            var copy = m
            copy.voicedMs = nil
            return copy
        }
        return m
    }

    static func hasReliableMeasurement(_ m: VoiceActivityMeta) -> Bool {
        m.durationMs >= 500 && m.measuredMs / m.durationMs >= 0.95 && m.maxGapMs <= 100
    }

    /// Kaum Sprachaktivität. iOS-Ergänzung: Ohne jede stimmhafte Sprache (< 60 ms
    /// periodisches Signal) gilt eine reine Dankesformel ebenfalls als Stille – Atmen
    /// oder Rascheln kann den Pegel heben, klingt aber nicht nach Vokalen.
    static func hasLowSpeechActivity(_ m: VoiceActivityMeta?) -> Bool {
        guard let m, hasReliableMeasurement(m) else { return false }
        if m.peakDbfs - m.floorDbfs < 12 || (m.floorDbfs < -45 && m.speechMs < 120) { return true }
        if let voiced = m.voicedMs, voiced < 60 { return true }
        return false
    }

    /// Groq gar nicht erst aufrufen: nur bei sehr stationären Signalen (wie Desktop).
    static func shouldSkipTranscription(_ input: VoiceActivityMeta?) -> Bool {
        guard let m = validate(input) else { return false }
        return m.peakDbfs <= -100
            || (hasReliableMeasurement(m) && m.speechMs < 80 && m.peakDbfs - m.floorDbfs < 6)
    }

    static func isSilentSegment(_ segment: WhisperSegment) -> Bool {
        guard let p = segment.noSpeechProb, p >= 0, p <= 1, p > noSpeechProb,
              let logprob = segment.avgLogprob, logprob.isFinite else { return false }
        return logprob < lowLogprob
    }

    static func isTrivialTranscript(_ input: String) -> Bool {
        let trimmed = input.trimmed
        let lettersOrDigits = trimmed.unicodeScalars.filter { TextAnalysis.isLetter($0) || TextAnalysis.isNumber($0) }
        // Ein einzelnes CJK-Zeichen (好, 是, 对) ist ein vollständiges Wort.
        if lettersOrDigits.contains(where: TextAnalysis.isScriptioContinua) { return false }
        return lettersOrDigits.isEmpty || (lettersOrDigits.count < 2 && trimmed.unicodeScalars.count <= 3)
    }

    static func filter(text responseText: String?, segments rawSegments: [WhisperSegment]?,
                       meta inputMeta: VoiceActivityMeta?, bypassLocalFilters: Bool = false) -> Result {
        let meta = validate(inputMeta)
        let rawText = responseText?.trimmed ?? ""
        let segments: [WhisperSegment]? = {
            guard let all = rawSegments, !all.isEmpty, all.allSatisfy({ $0.text != nil }) else { return nil }
            return all.filter { !($0.text ?? "").trimmed.isEmpty }
        }()
        let kept = bypassLocalFilters ? segments : segments?.filter { !isSilentSegment($0) }
        let dropped = (segments?.count ?? 0) - (kept?.count ?? 0)
        var text: String
        if dropped > 0 {
            text = (kept ?? []).map { ($0.text ?? "").trimmed }.joined(separator: " ")
        } else if !rawText.isEmpty {
            text = rawText
        } else {
            text = segments?.map { ($0.text ?? "").trimmed }.joined(separator: " ") ?? ""
        }
        var reason: String? = dropped > 0 && text.isEmpty ? "no-speech-segments" : nil

        // Groq liefert selbst bei digitaler Stille no_speech_prob=0; avg_logprob trennt
        // echte Dankesformeln nicht von Halluzinationen. Nie allein nach Konfidenz verwerfen.
        let normalized = normalize(text)
        if isArtifactPhrase(normalized) {
            text = ""
            reason = "known-artifact-phrase"
        } else if !bypassLocalFilters && silencePhrases.contains(normalized) && hasLowSpeechActivity(meta) {
            text = ""
            reason = "known-silence-phrase"
        }
        if isTrivialTranscript(text) {
            text = ""
            if reason == nil { reason = "trivial" }
        }
        return Result(text: text, droppedSegments: dropped, reason: reason,
                      keptSegments: text.isEmpty ? [] : (kept ?? []))
    }
}
