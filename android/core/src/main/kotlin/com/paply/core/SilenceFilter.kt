package com.paply.core

import java.text.Normalizer
import java.util.Locale

data class VoiceActivityMeta(
    val durationMs: Double,
    val measuredMs: Double,
    val speechMs: Double,
    val peakDbfs: Double,
    val floorDbfs: Double,
    val maxGapMs: Double,
    val voicedMs: Double? = null,
)

internal object SilenceFilter {
    const val noSpeechProb = 0.6
    const val lowLogprob = -1.0

    data class Result(
        val text: String,
        val droppedSegments: Int,
        val reason: String?,
        val keptSegments: List<WhisperSegment>,
    )

    fun normalize(text: String): String {
        val folded = Normalizer.normalize(text, Normalizer.Form.NFKC).lowercase(Locale.ROOT)
        val out = StringBuilder()
        var lastWasSpace = false
        for (s in folded.scalars()) {
            if (TextAnalysis.isWordScalar(s)) {
                out.appendCodePoint(s)
                lastWasSpace = false
            } else if (s.isUnicodeWhitespace()) {
                if (!lastWasSpace) out.append(' ')
                lastWasSpace = true
            }
        }
        return out.toString().trimmed()
    }

    val silencePhrases =
        listOf(
                // Deutsch (wie Desktop)
                "Vielen Dank.",
                "Danke.",
                "Vielen Dank fürs Zuschauen.",
                "Danke fürs Zuschauen.",
                "Vielen Dank für Ihre Aufmerksamkeit.",
                "Bis zum nächsten Mal.",
                "Tschüss.",
                "Danke fürs Zuhören.",
                "Vielen Dank fürs Zuhören.",
                "Bis bald.",
                // Englisch
                "Thank you.",
                "Thanks.",
                "Thanks for watching!",
                "Thank you for watching!",
                "Thank you very much.",
                "Thank you so much.",
                "Thanks for listening.",
                "Bye.",
                "Bye-bye.",
                "You",
                "Please subscribe.",
                "See you next time.",
                // Französisch
                "Merci.",
                "Merci beaucoup.",
                "Merci d'avoir regardé.",
                "Merci de votre attention.",
                "Au revoir.",
                // Spanisch
                "Gracias.",
                "Muchas gracias.",
                "Gracias por ver.",
                "Gracias por ver el video.",
                "¡Suscríbete!",
                // Italienisch
                "Grazie.",
                "Grazie mille.",
                "Grazie per la visione.",
                "Grazie a tutti.",
                // Portugiesisch
                "Obrigado.",
                "Obrigada.",
                "Muito obrigado.",
                "Obrigado por assistir.",
                // Niederländisch
                "Dank je.",
                "Dank je wel.",
                "Dank u wel.",
                "Bedankt.",
                "Bedankt voor het kijken.",
                // Türkisch
                "Teşekkürler.",
                "Teşekkür ederim.",
                "İzlediğiniz için teşekkürler.",
                // Polnisch
                "Dziękuję.",
                "Dzięki.",
                "Dziękuję za uwagę.",
                "Dziękuję bardzo.",
                // Russisch
                "Спасибо.",
                "Спасибо за внимание.",
                "Продолжение следует...",
                // Japanisch, Chinesisch, Koreanisch
                "ご視聴ありがとうございました",
                "ありがとうございました",
                "谢谢观看",
                "謝謝觀看",
                "谢谢",
                "감사합니다.",
                "시청해주셔서 감사합니다.",
            )
            .map(::normalize)
            .toSet()

    /// Eindeutige Untertitel-/Abspann-Artefakte. Nur vollständige Phrasen treffen:
    /// Erwähnungen innerhalb eines Diktats bleiben.
    val artifactPhrases =
        listOf(
                "Amara.org",
                "Untertitel von der Amara.org-Community",
                "Untertitel der Amara.org-Community",
                "Subtitles by the Amara.org community",
                "Sous-titres réalisés par la communauté d'Amara.org",
                "Sous-titrage Société Radio-Canada",
                "Sous-titrage ST' 501",
                "Subtítulos realizados por la comunidad de Amara.org",
                "Subtítulos por la comunidad de Amara.org",
                "Sottotitoli creati dalla comunità Amara.org",
                "Sottotitoli a cura di QTSS",
                "Legendas pela comunidade Amara.org",
                "Legendas pela comunidade de Amara.org",
                "Ondertiteld door de Amara.org gemeenschap",
                "Ondertiteling door de Amara.org gemeenschap",
                "Napisy stworzone przez społeczność Amara.org",
                "Napisy wykonane przez społeczność Amara.org",
                "Altyazı M.K.",
                "Субтитры сделал DimaTorzok",
                "Субтитры создавал DimaTorzok",
                "字幕由Amara.org社区提供",
                "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目",
            )
            .map(::normalize)
            .toSet()

    private val zdf = Pattern("^untertitel im auftrag des zdf(?: für funk)?(?: \\d{4})?$")
    private val zdfFunk = Pattern("^untertitelung des zdf für funk(?: \\d{4})?$")
    private val copyright = Pattern("^copyright(?: (?:wdr|zdf|ndr|swr|ard)(?: \\d{4})?)?$")

    fun isArtifactPhrase(normalized: String) =
        normalized in artifactPhrases ||
            zdf.matches(normalized) ||
            zdfFunk.matches(normalized) ||
            copyright.matches(normalized)

    fun validate(m: VoiceActivityMeta?): VoiceActivityMeta? {
        m ?: return null
        val values =
            listOf(m.durationMs, m.measuredMs, m.speechMs, m.peakDbfs, m.floorDbfs, m.maxGapMs)
        if (
            !values.all { it.isFinite() } ||
                m.durationMs <= 0 ||
                m.measuredMs < 0 ||
                m.measuredMs > m.durationMs ||
                m.speechMs < 0 ||
                m.speechMs > m.measuredMs ||
                m.maxGapMs < 0 ||
                m.peakDbfs > 0 ||
                m.peakDbfs < -120 ||
                m.floorDbfs < -120 ||
                m.floorDbfs > m.peakDbfs
        )
            return null
        if (
            m.voicedMs != null &&
                (!m.voicedMs.isFinite() || m.voicedMs < 0 || m.voicedMs > m.measuredMs)
        )
            return m.copy(voicedMs = null)
        return m
    }

    fun hasReliableMeasurement(m: VoiceActivityMeta) =
        m.durationMs >= 500 && m.measuredMs / m.durationMs >= 0.95 && m.maxGapMs <= 100

    fun hasLowSpeechActivity(m: VoiceActivityMeta?): Boolean {
        if (m == null || !hasReliableMeasurement(m)) return false
        return m.peakDbfs - m.floorDbfs < 12 ||
            (m.floorDbfs < -45 && m.speechMs < 120) ||
            (m.voicedMs != null && m.voicedMs < 60)
    }

    fun shouldSkipTranscription(input: VoiceActivityMeta?): Boolean {
        val m = validate(input) ?: return false
        return m.peakDbfs <= -100 ||
            (hasReliableMeasurement(m) && m.speechMs < 80 && m.peakDbfs - m.floorDbfs < 6)
    }

    fun isSilentSegment(s: WhisperSegment): Boolean {
        val p = s.noSpeechProb ?: return false
        val l = s.avgLogprob ?: return false
        return p >= 0 && p <= 1 && p > noSpeechProb && l.isFinite() && l < lowLogprob
    }

    fun isTrivialTranscript(input: String): Boolean {
        val trimmed = input.trimmed()
        val letters =
            trimmed.scalars().filter { TextAnalysis.isLetter(it) || TextAnalysis.isNumber(it) }
        if (letters.any(TextAnalysis::isScriptioContinua)) return false
        return letters.isEmpty() || (letters.size < 2 && trimmed.scalarCount <= 3)
    }

    fun filter(
        text: String?,
        segments: List<WhisperSegment>?,
        meta: VoiceActivityMeta?,
        bypassLocalFilters: Boolean = false,
    ): Result {
        val valid = validate(meta)
        val rawText = text?.trimmed().orEmpty()
        val usable =
            segments
                ?.takeIf { it.isNotEmpty() && it.all { s -> s.text != null } }
                ?.filter { it.text.orEmpty().trimmed().isNotEmpty() }
        val kept = if (bypassLocalFilters) usable else usable?.filter { !isSilentSegment(it) }
        val dropped = (usable?.size ?: 0) - (kept?.size ?: 0)
        var output =
            if (dropped > 0) kept.orEmpty().joinToString(" ") { it.text.orEmpty().trimmed() }
            else
                rawText.ifEmpty {
                    usable.orEmpty().joinToString(" ") { it.text.orEmpty().trimmed() }
                }
        var reason: String? = if (dropped > 0 && output.isEmpty()) "no-speech-segments" else null
        val normalized = normalize(output)
        if (isArtifactPhrase(normalized)) {
            output = ""
            reason = "known-artifact-phrase"
        } else if (
            !bypassLocalFilters && normalized in silencePhrases && hasLowSpeechActivity(valid)
        ) {
            output = ""
            reason = "known-silence-phrase"
        }
        if (isTrivialTranscript(output)) {
            output = ""
            if (reason == null) reason = "trivial"
        }
        return Result(
            output,
            dropped,
            reason,
            if (output.isEmpty()) emptyList() else kept.orEmpty(),
        )
    }
}
