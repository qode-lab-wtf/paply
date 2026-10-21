// Diktat-Stillefilter. Fehlende/zweifelhafte Signale bedeuten immer: behalten.
// Groq dokumentiert diese Segmentfelder für verbose_json:
// https://console.groq.com/docs/speech-to-text#understanding-metadata-fields
const NO_SPEECH_PROB = 0.6;
const LOW_LOGPROB = -1.0;
const PHRASE_NO_SPEECH_PROB = 0.9;
const MIN_PHRASE_SPEECH_MS = 400;

function normalizeTranscript(text) {
  return text.normalize('NFKC').toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, '').replace(/\s+/g, ' ').trim();
}

const SILENCE_PHRASES = new Set([
  'Vielen Dank.', 'Danke.', 'Vielen Dank fürs Zuschauen.', 'Danke fürs Zuschauen.',
  'Vielen Dank für Ihre Aufmerksamkeit.', 'Bis zum nächsten Mal.', 'Tschüss.',
  'Thank you.', 'Thanks.', 'Thanks for watching!', 'Thank you for watching!',
].map(normalizeTranscript));

// Vom Besitzer ausdrücklich freigegebene, eindeutige Whisper-Artefakte. Nur
// vollständige Phrasen treffen: Erwähnungen innerhalb eines Diktats bleiben.
function isArtifactPhrase(text) {
  return text === 'amaraorg' || text === 'untertitel von der amaraorgcommunity'
    || /^untertitel im auftrag des zdf(?: für funk)?(?: \d{4})?$/.test(text)
    || /^untertitelung des zdf für funk(?: \d{4})?$/.test(text)
    || /^copyright(?: (?:wdr|zdf|ndr|swr|ard)(?: \d{4})?)?$/.test(text);
}

function validateVoiceActivity(meta) {
  if (!meta || typeof meta !== 'object') return undefined;
  const { durationMs, measuredMs, speechMs, peakDbfs, maxGapMs } = meta;
  if (![durationMs, measuredMs, speechMs, peakDbfs, maxGapMs].every(Number.isFinite)
    || durationMs <= 0 || measuredMs < 0 || measuredMs > durationMs
    || speechMs < 0 || speechMs > measuredMs || maxGapMs < 0 || peakDbfs > 0 || peakDbfs < -120) {
    return undefined;
  }
  return { durationMs, measuredMs, speechMs, peakDbfs, maxGapMs };
}

function hasReliableMeasurement(meta) {
  return meta && meta.durationMs >= 500 && meta.measuredMs / meta.durationMs >= 0.95 && meta.maxGapMs <= 100;
}

function hasLowSpeechActivity(meta) {
  return hasReliableMeasurement(meta) && meta.speechMs < MIN_PHRASE_SPEECH_MS;
}

function shouldSkipTranscription(input) {
  const meta = validateVoiceActivity(input);
  // Höchstens ein leises Messfenster über -65 dBFS tolerieren (z. B. ein
  // Störimpuls). Lautere Spitzen oder >=80 ms Aktivität immer transkribieren.
  return Boolean(hasReliableMeasurement(meta) && meta.speechMs < 80 && meta.peakDbfs < -60);
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
  return !lettersOrDigits || (lettersOrDigits.length < 2 && trimmed.length <= 3);
}

function filterTranscription(response, inputMeta) {
  const meta = validateVoiceActivity(inputMeta);
  const rawText = typeof response?.text === 'string' ? response.text.trim() : '';
  const segments = Array.isArray(response?.segments) && response.segments.length > 0
    && response.segments.every(segment => segment && typeof segment.text === 'string')
    ? response.segments.filter(segment => segment.text.trim()) : null;
  const kept = segments?.filter(segment => !isSilentSegment(segment));
  const droppedSegments = segments ? segments.length - kept.length : 0;
  // Bei fehlenden/ungültigen Segmenten bleibt der bisherige Text maßgeblich.
  let text = droppedSegments ? kept.map(segment => segment.text.trim()).join(' ')
    : rawText || segments?.map(segment => segment.text.trim()).join(' ') || '';
  let reason = droppedSegments && !text ? 'no-speech-segments' : null;

  // Groq liefert laut realen Vergleichsmessungen selbst bei digitaler Stille
  // no_speech_prob=0. avg_logprob trennt dabei echte Dankesformeln nicht von
  // Halluzinationen: Niemals allein anhand der Text-Konfidenz verwerfen.
  const measuredSpeech = meta && meta.speechMs >= MIN_PHRASE_SPEECH_MS;
  const highNoSpeech = kept?.length > 0 && kept.every(segment => noSpeechProbability(segment) > PHRASE_NO_SPEECH_PROB);
  const normalized = normalizeTranscript(text);
  if (isArtifactPhrase(normalized)) {
    text = '';
    reason = 'known-artifact-phrase';
  } else if (SILENCE_PHRASES.has(normalized)
    && (hasLowSpeechActivity(meta) || (highNoSpeech && !measuredSpeech))) {
    text = '';
    reason = 'known-silence-phrase';
  }
  if (isTrivialTranscript(text)) {
    text = '';
    reason ||= 'trivial';
  }
  return { text, droppedSegments, reason };
}

module.exports = { filterTranscription, shouldSkipTranscription, validateVoiceActivity };
