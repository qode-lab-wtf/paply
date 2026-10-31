// Diktat-Stillefilter. Fehlende/zweifelhafte Signale bedeuten immer: behalten.
// Groq dokumentiert diese Segmentfelder für verbose_json:
// https://console.groq.com/docs/speech-to-text#understanding-metadata-fields
const NO_SPEECH_PROB = 0.6;
const LOW_LOGPROB = -1.0;

function normalizeTranscript(text) {
  return text.normalize('NFKC').toLowerCase()
    .replace(/[^\p{L}\p{N}\p{M}\s]/gu, '').replace(/\s+/g, ' ').trim();
}

const SILENCE_PHRASES = new Set([
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
  "Merci.",
  "Merci beaucoup.",
  "Merci d'avoir regardé.",
  "Merci de votre attention.",
  "Au revoir.",
  "Gracias.",
  "Muchas gracias.",
  "Gracias por ver.",
  "Gracias por ver el video.",
  "¡Suscríbete!",
  "Grazie.",
  "Grazie mille.",
  "Grazie per la visione.",
  "Grazie a tutti.",
  "Obrigado.",
  "Obrigada.",
  "Muito obrigado.",
  "Obrigado por assistir.",
  "Dank je.",
  "Dank je wel.",
  "Dank u wel.",
  "Bedankt.",
  "Bedankt voor het kijken.",
  "Teşekkürler.",
  "Teşekkür ederim.",
  "İzlediğiniz için teşekkürler.",
  "Dziękuję.",
  "Dzięki.",
  "Dziękuję za uwagę.",
  "Dziękuję bardzo.",
  "Спасибо.",
  "Спасибо за внимание.",
  "Продолжение следует...",
  "ご視聴ありがとうございました",
  "ありがとうございました",
  "谢谢观看",
  "謝謝觀看",
  "谢谢",
  "감사합니다.",
  "시청해주셔서 감사합니다."
].map(normalizeTranscript));

const ARTIFACT_PHRASES = new Set([
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
  "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目"
].map(normalizeTranscript));

// Vom Besitzer ausdrücklich freigegebene, eindeutige Whisper-Artefakte. Nur
// vollständige Phrasen treffen: Erwähnungen innerhalb eines Diktats bleiben.
function isArtifactPhrase(text) {
  return ARTIFACT_PHRASES.has(text) || text === 'amaraorg' || text === 'untertitel von der amaraorgcommunity'
    || /^untertitel im auftrag des zdf(?: für funk)?(?: \d{4})?$/.test(text)
    || /^untertitelung des zdf für funk(?: \d{4})?$/.test(text)
    || /^copyright(?: (?:wdr|zdf|ndr|swr|ard)(?: \d{4})?)?$/.test(text);
}

function validateVoiceActivity(meta) {
  if (!meta || typeof meta !== 'object') return undefined;
  const { durationMs, measuredMs, speechMs, peakDbfs, floorDbfs, maxGapMs } = meta;
  // Ohne floorDbfs stammt speechMs noch von der alten absoluten Schwelle und
  // darf keine lokale Verwerfentscheidung auslösen (z. B. bei alten Backups).
  if (![durationMs, measuredMs, speechMs, peakDbfs, floorDbfs, maxGapMs].every(Number.isFinite)
    || durationMs <= 0 || measuredMs < 0 || measuredMs > durationMs
    || speechMs < 0 || speechMs > measuredMs || maxGapMs < 0 || peakDbfs > 0 || peakDbfs < -120
    || floorDbfs < -120 || floorDbfs > peakDbfs) {
    return undefined;
  }
  return { durationMs, measuredMs, speechMs, peakDbfs, floorDbfs, maxGapMs,
    voicedMs: Number.isFinite(meta.voicedMs) && meta.voicedMs >= 0 && meta.voicedMs <= measuredMs ? meta.voicedMs : undefined };
}

function hasReliableMeasurement(meta) {
  return meta && meta.durationMs >= 500 && meta.measuredMs / meta.durationMs >= 0.95 && meta.maxGapMs <= 100;
}

function hasLowSpeechActivity(meta) {
  return hasReliableMeasurement(meta) && (meta.peakDbfs - meta.floorDbfs < 12
    || (meta.floorDbfs < -45 && meta.speechMs < 120) || meta.voicedMs < 60);
}

function shouldSkipTranscription(input) {
  const meta = validateVoiceActivity(input);
  // Nur sehr stationäre Signale überspringen, unabhängig von ihrem absoluten
  // Pegel. Deutliche Spitzen (auch Klicks) werden zunächst transkribiert.
  return Boolean(meta && (meta.peakDbfs <= -100
    || (hasReliableMeasurement(meta) && meta.speechMs < 80 && meta.peakDbfs - meta.floorDbfs < 6)));
}

function noSpeechProbability(segment) {
  const value = segment?.no_speech_prob;
  return Number.isFinite(value) && value >= 0 && value <= 1 ? value : undefined;
}

function isSilentSegment(segment) {
  const probability = noSpeechProbability(segment);
  return probability > NO_SPEECH_PROB
    && Number.isFinite(segment.avg_logprob) && segment.avg_logprob < LOW_LOGPROB;
}

// Bisherige Behandlung reiner Satzzeichen und sehr kurzer trivialer Ergebnisse.
function isTrivialTranscript(input) {
  const trimmed = input.trim();
  const lettersOrDigits = trimmed.replace(/[^\p{L}\p{N}]+/gu, '');
  if (/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Thai}]/u.test(lettersOrDigits)) return false;
  return !lettersOrDigits || (lettersOrDigits.length < 2 && trimmed.length <= 3);
}

function filterTranscription(response, inputMeta, { bypassLocalFilters = false } = {}) {
  const meta = validateVoiceActivity(inputMeta);
  const rawText = typeof response?.text === 'string' ? response.text.trim() : '';
  const segments = Array.isArray(response?.segments) && response.segments.length > 0
    && response.segments.every(segment => segment && typeof segment.text === 'string')
    ? response.segments.filter(segment => segment.text.trim()) : null;
  const kept = bypassLocalFilters ? segments : segments?.filter(segment => !isSilentSegment(segment));
  const droppedSegments = segments ? segments.length - kept.length : 0;
  // Bei fehlenden/ungültigen Segmenten bleibt der bisherige Text maßgeblich.
  let text = droppedSegments ? kept.map(segment => segment.text.trim()).join(' ')
    : rawText || segments?.map(segment => segment.text.trim()).join(' ') || '';
  let reason = droppedSegments && !text ? 'no-speech-segments' : null;

  // Groq liefert laut realen Vergleichsmessungen selbst bei digitaler Stille
  // no_speech_prob=0. avg_logprob trennt dabei echte Dankesformeln nicht von
  // Halluzinationen: Niemals allein anhand der Text-Konfidenz verwerfen.
  const normalized = normalizeTranscript(text);
  if (isArtifactPhrase(normalized)) {
    text = '';
    reason = 'known-artifact-phrase';
  } else if (!bypassLocalFilters && SILENCE_PHRASES.has(normalized) && hasLowSpeechActivity(meta)) {
    text = '';
    reason = 'known-silence-phrase';
  }
  if (isTrivialTranscript(text)) {
    text = '';
    reason ||= 'trivial';
  }
  return { text, droppedSegments, reason };
}

module.exports = { filterTranscription, shouldSkipTranscription, validateVoiceActivity, isSilentSegment };
