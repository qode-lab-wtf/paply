// Sprachentscheidung vor jeder Textfilterung; ohne Electron testbar.
const SHORT_SPEECH_SECONDS = 5;
const CHECK_GAP = 0.15;
const WHISPER_MODEL = 'whisper-large-v3';
const names = {
  english: 'en',
  german: 'de',
  french: 'fr',
  spanish: 'es',
  italian: 'it',
  portuguese: 'pt',
  dutch: 'nl',
  turkish: 'tr',
  polish: 'pl',
  russian: 'ru',
  ukrainian: 'uk',
  chinese: 'zh',
  japanese: 'ja',
  korean: 'ko',
  arabic: 'ar',
  hindi: 'hi',
  swedish: 'sv',
  danish: 'da',
  norwegian: 'no',
  nynorsk: 'nn',
  finnish: 'fi',
  czech: 'cs',
  greek: 'el',
  hungarian: 'hu',
  romanian: 'ro',
  hebrew: 'he',
  vietnamese: 'vi',
  thai: 'th',
  indonesian: 'id',
  malay: 'ms',
  persian: 'fa',
  catalan: 'ca',
  croatian: 'hr',
  serbian: 'sr',
  slovak: 'sk',
  slovenian: 'sl',
  bulgarian: 'bg',
  lithuanian: 'lt',
  latvian: 'lv',
  estonian: 'et',
  tagalog: 'tl',
  urdu: 'ur',
  bengali: 'bn',
  tamil: 'ta',
  afrikaans: 'af',
  welsh: 'cy',
  icelandic: 'is',
  bosnian: 'bs',
  macedonian: 'mk',
  galician: 'gl',
  basque: 'eu',
  swahili: 'sw',
  albanian: 'sq',
  cantonese: 'yue',
  telugu: 'te', malayalam: 'ml', latin: 'la', maori: 'mi',
  javanese: 'jv', myanmar: 'my', armenian: 'hy', nepali: 'ne',
  sanskrit: 'sa', marathi: 'mr', belarusian: 'be', kazakh: 'kk',
  azerbaijani: 'az', luxembourgish: 'lb', kannada: 'kn', tajik: 'tg',
  hawaiian: 'haw', lingala: 'ln', hausa: 'ha', bashkir: 'ba',
  sundanese: 'su', burmese: 'my', mongolian: 'mn', tatar: 'tt',
  assamese: 'as', punjabi: 'pa', sindhi: 'sd', gujarati: 'gu',
  amharic: 'am', yiddish: 'yi', lao: 'lo', uzbek: 'uz', faroese: 'fo',
  haitian: 'ht', 'haitian creole': 'ht', pashto: 'ps', turkmen: 'tk',
  shona: 'sn', yoruba: 'yo', somali: 'so', tibetan: 'bo',
  khmer: 'km', maltese: 'mt', georgian: 'ka', breton: 'br',
  sinhala: 'si', irish: 'ga', malagasy: 'mg', occitan: 'oc',
};
function languageCode(value) {
  const raw = typeof value === 'string' ? value.trim().toLowerCase() : '';
  const code = names[raw] || raw.split(/[-_]/)[0];
  return ({ nb: 'no', fil: 'tl', iw: 'he', in: 'id', ji: 'yi', jw: 'jv' })[code] || code || null;
}
function userLanguages(main, system = []) {
  const list = [
    ...new Set([main, ...system].map(languageCode).filter(Boolean)),
  ];
  if (list.length === 1 && list[0] !== 'en') list.push('en');
  return list;
}
function needsCheck({ spoken, expected, detected, users = [] }) {
  expected = languageCode(expected);
  detected = languageCode(detected);
  return !!(
    expected &&
    detected &&
    expected !== detected &&
    (spoken <= SHORT_SPEECH_SECONDS ||
      !users.map(languageCode).includes(detected))
  );
}
function decide({ sameText, lpDetected, lpExpected, failed = false, spoken = 0 }) {
  if (sameText) return 'expected';
  if (failed) return 'detected';
  if (!Number.isFinite(lpDetected) || !Number.isFinite(lpExpected))
    return 'detected';
  if (spoken > SHORT_SPEECH_SECONDS) return lpExpected - lpDetected >= CHECK_GAP ? 'expected' : 'detected';
  return lpDetected - lpExpected >= CHECK_GAP ? 'detected' : 'expected';
}
function confidence(response) {
  const segments = response?.segments;
  if (
    !segments?.length ||
    segments.some((s) => !Number.isFinite(s.avg_logprob))
  )
    return null;
  let total = 0,
    weight = 0;
  for (const s of segments) {
    const w = Number.isFinite(s.end - s.start)
      ? Math.max(0.01, s.end - s.start)
      : 0.01;
    total += w * s.avg_logprob;
    weight += w;
  }
  return total / weight;
}
const normalize = (text) =>
  String(text || '')
    .toLowerCase()
    .replace(/\s+/gu, ' ')
    .replace(/^[\s\p{P}]+|[\s\p{P}]+$/gu, '');
async function guardedTranscription(
  request,
  { expected, users = [], spoken, duration } = {},
) {
  const started = Date.now();
  const first = await request();
  const checkTimeout = Math.min(60000, 2 * (Date.now() - started) + 5000);
  const detected = languageCode(first.language);
  const original = { ...first, language: detected };
  if (
    !needsCheck({
      expected,
      detected,
      users,
      spoken: Number.isFinite(spoken)
        ? spoken
        : (duration ?? first.duration ?? Infinity),
    })
  )
    return original;
  let check, timer;
  try {
    check = await Promise.race([
      request(languageCode(expected)),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Gegenprobe abgelaufen')), checkTimeout); }),
    ]);
  } catch {
    return original;
  } finally { clearTimeout(timer); }
  return decide({
    spoken: Number.isFinite(spoken) ? spoken : (duration ?? first.duration ?? Infinity),
    sameText: normalize(first.text) === normalize(check.text),
    lpDetected: confidence(first),
    lpExpected: confidence(check),
  }) === 'expected'
    ? { ...check, language: languageCode(expected) }
    : original;
}
module.exports = {
  SHORT_SPEECH_SECONDS,
  CHECK_GAP,
  WHISPER_MODEL,
  languageCode,
  userLanguages,
  needsCheck,
  decide,
  confidence,
  guardedTranscription,
};
