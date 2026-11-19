const { languageCode } = require('./language-guard');
const { vocabularyPrompt, isVocabularyEcho } = require('./polish-prompt');
const { hasLowSpeechActivity, validateVoiceActivity } = require('../audio/silence-filter');
const phrases = {
  de: [
    ['Kurzes Update: Das Meeting ist verschoben', 'Ich schreibe dir später'],
    ['und der neue Termin ist nächsten Freitag', 'bis morgen'],
  ],
  en: [
    ['Quick update: the meeting has been moved', "I'll write to you later"],
    ['and the new date is next Friday', 'see you tomorrow'],
  ],
  fr: [
    ['Petit point : la réunion est reportée', "Je t'écris plus tard"],
    ['et la nouvelle date est vendredi prochain', 'à demain'],
  ],
  es: [
    ['Breve novedad: la reunión se aplaza', 'Te escribo luego'],
    ['y la nueva fecha es el viernes', 'hasta mañana'],
  ],
  it: [
    ['Breve aggiornamento: la riunione è spostata', 'Ti scrivo dopo'],
    ['e la nuova data è venerdì prossimo', 'a domani'],
  ],
  pt: [
    ['Novidade rápida: a reunião foi adiada', 'Te escrevo depois'],
    ['e a nova data é sexta-feira', 'até amanhã'],
  ],
  nl: [
    ['Korte update: de vergadering is verplaatst', 'Ik schrijf je later'],
    ['en de nieuwe datum is volgende vrijdag', 'tot morgen'],
  ],
  tr: [
    ['Kısa bilgi: toplantı ertelendi', 'Sana sonra yazarım'],
    ['ve yeni tarih cuma', 'yarın görüşürüz'],
  ],
  pl: [
    ['Krótko: spotkanie jest przełożone', 'Napiszę później'],
    ['a nowy termin to piątek', 'do jutra'],
  ],
};
function primer(languages) {
  const codes = [...new Set(languages.map(languageCode))].filter(
    (c) => phrases[c],
  );
  if (codes.length < 2) return '';
  const [a, b] = codes.map((c) => phrases[c]);
  return `${a[0][0]}, ${b[1][0]}. ${a[0][1]}, ${b[1][1]}.`;
}
function scalarCost(c) {
  const n = c.codePointAt(0);
  return n <= 0x24f ? 1 : n < 0x800 ? 2 : Buffer.byteLength(c);
}
function estimateTokens(text) {
  return (text.match(/\S+/gu) || []).reduce((sum, w) => {
    let ascii = 0,
      cost = 0;
    for (const c of w) {
      if (/[a-z0-9]/i.test(c)) ascii++;
      else cost += scalarCost(c);
    }
    return sum + Math.max(1, cost + Math.ceil(ascii / 2));
  }, 0);
}
function buildPrompt(vocabulary = '', previousText = '', example = '') {
  const parts = [];
  let used = 0;
  if (example.trim() && estimateTokens(example) <= 64) {
    parts.push(example.trim());
    used = estimateTokens(example);
  }
  const kept = [];
  for (const item of vocabulary.split(/[,;\r\n]+/).map(s => s.trim()).filter(Boolean)) {
    if (estimateTokens([...kept, item].join(', ')) > 90) break;
    kept.push(item);
  }
  const vocab = kept.join(', ');
  if (vocab) {
    const item = vocab.endsWith('.') ? vocab : vocab + '.';
    parts.push(item);
    used += estimateTokens(item);
  }
  const words = previousText.trim().split(/\s+/).filter(Boolean),
    tail = [];
  for (const word of words.reverse()) {
    const cost = estimateTokens(word);
    if (used + cost > 200) break;
    used += cost;
    tail.unshift(word);
  }
  if (!tail.length && words.length) {
    let cost = 0;
    for (const c of Array.from(words[0]).reverse()) {
      cost += scalarCost(c);
      if (used + cost > 200) break;
      tail.unshift(c);
    }
    if (tail.length) parts.push(tail.join(''));
  } else if (tail.length) parts.push(tail.join(' '));
  return parts.join(' ');
}
// Misst die App verlässlich kaum Stimme, geht das Stück ohne Prompt an Whisper:
// Mit Prompt erfand Whisper bei leisem Ton Englisch, ohne kam nur „.“.
function whisperPrompt(vocabulary, previousText, example, voiceActivity) {
  return hasLowSpeechActivity(validateVoiceActivity(voiceActivity)) ? '' : buildPrompt(vocabulary, previousText, example);
}
// Begriffe nur bei sehr kurzer Sprechzeit verwerfen. Längere Primer-Echos
// sind auch ohne Messung verdächtig; nachweislich viel Sprache schützt sie.
function removeEchoes(
  response,
  { example = '', previousText = '', vocabulary = '', speechMs } = {},
) {
  vocabulary = vocabularyPrompt(vocabulary);
  const words = (s) =>
    s
      .normalize('NFC')
      .toLowerCase()
      .match(/[\p{L}\p{N}\p{M}]+/gu) || [];
  const contains = (hay, needle, min) =>
    needle.length >= min &&
    hay.some((_, i) => needle.every((w, j) => hay[i + j] === w));
  const echo = (text) => {
    const w = words(text);
    return (
      (vocabulary && Number.isFinite(speechMs) && speechMs < 300 && isVocabularyEcho(text, vocabulary)) ||
      (!(Number.isFinite(speechMs) && speechMs >= Math.max(3000, w.length * 100)) &&
        words(example).some((_, i, e) => contains(w, e.slice(i, i + 5), 5)) &&
        words(buildPrompt(vocabulary, previousText, example)).some((_, i, p) => contains(w, p.slice(i, i + 5), 5))) ||
      (Number.isFinite(speechMs) &&
        speechMs < 100 * w.length &&
        (contains(words(example), w, 3) || contains(words(previousText), w, 2)))
    );
  };
  if (response.segments?.length) {
    const kept = response.segments.filter((s) => !echo(s.text || ''));
    if (kept.length !== response.segments.length)
      return {
        ...response,
        echoRemoved: true,
        text: kept.map((s) => s.text.trim()).join(' '),
        segments: kept,
      };
  } else if (echo(response.text || '')) return { ...response, text: '', echoRemoved: true };
  return response;
}
// Echo-Gegenprobe: Sieht ein Ergebnis nach dem eigenen Prompt aus, läuft dasselbe
// Stück ohne Prompt noch einmal, und dieser Lauf gilt. Die Erkennung darf großzügig
// sein, ein Fehlalarm kostet nur eine Anfrage, nie Text.
const tokens = (s) => [...String(s || '').normalize('NFC').matchAll(/[\p{L}\p{N}\p{M}]+/gu)];
const lower = (s) => tokens(s).map((m) => m[0].toLowerCase());
// Wortläufe aus `text`, die mindestens `min` Wörter am Stück aus `source` sind.
function runs(text, source, min) {
  const t = tokens(text), w = t.map((m) => m[0].toLowerCase()), s = lower(source), found = [];
  for (let i = 0; i < w.length; ) {
    let best = 0;
    for (let j = 0; j < s.length; j++) {
      let n = 0;
      while (w[i + n] !== undefined && w[i + n] === s[j + n]) n++;
      best = Math.max(best, n);
    }
    if (best >= min) { found.push([t[i].index, t[i + best - 1].index + t[i + best - 1][0].length]); i += best; } else i++;
  }
  return found;
}
// Sätze aus mindestens drei Wörtern, die fast nur aus eigenen Begriffen bestehen.
const listSentences = (text, vocabulary) =>
  vocabulary ? [...String(text || '').matchAll(/[^.!?。]+[.!?。]*/gu)]
    .filter((m) => lower(m[0]).length >= 3 && isVocabularyEcho(m[0], vocabulary))
    .map((m) => [m.index, m.index + m[0].length]) : [];
function looksLikeEcho(response, { example = '', vocabulary = '', previousText = '' } = {}) {
  const text = response?.text || '';
  return runs(text, example, 3).length > 0 || listSentences(text, vocabularyPrompt(vocabulary)).length > 0
    || (response?.segments || []).some((s) => lower(s.text).length >= 3 && runs(s.text, previousText, lower(s.text).length).length > 0);
}
// Rückfall, wenn die Gegenprobe scheitert: nur die eindeutigen Echo-Wörter streichen,
// nicht ganze Segmente, denn mit Prompt liefert Whisper oft Segmente über 20 Sekunden.
function cutEchoes(response, { example = '', vocabulary = '' } = {}) {
  const cut = (text) => {
    let out = text || '';
    for (const [a, b] of [...runs(out, example, 5), ...listSentences(out, vocabularyPrompt(vocabulary))].sort((x, y) => y[0] - x[0]))
      out = out.slice(0, a) + out.slice(b).replace(/^[\s,.;:!?]+/u, ' ');
    return out.replace(/\s+/g, ' ').trim();
  };
  if (!response.segments?.length) return { ...response, text: cut(response.text) };
  const segments = response.segments.map((s) => ({ ...s, text: cut(s.text) })).filter((s) => s.text);
  return { ...response, segments, text: segments.map((s) => s.text).join(' ') };
}
async function echoCheck(first, request, { firstMs, signal, diagnose = (requested, accepted) => console.log('[Echo]', requested, accepted), ...prompt } = {}) {
  if (!looksLikeEcho(first, prompt)) { diagnose(0, 0); return first; }
  let timer, accepted = false;
  try {
    signal?.throwIfAborted();
    // Die Sprache ist schon entschieden; ein leerer termPrompt heißt: kein Prompt.
    const second = await Promise.race([request(first.language, ''), new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('timeout')), Math.min(60000, 2 * (firstMs || 0) + 5000)); })]);
    signal?.throwIfAborted();
    accepted = true;
    return { ...second, language: first.language, echoRemoved: true };
  } catch (error) {
    if (signal?.aborted) throw error;
    return { ...cutEchoes(first, prompt), echoRemoved: true };
  } finally { clearTimeout(timer); diagnose(1, Number(accepted)); }
}
module.exports = { primer, estimateTokens, buildPrompt, whisperPrompt, removeEchoes, looksLikeEcho, cutEchoes, echoCheck };
