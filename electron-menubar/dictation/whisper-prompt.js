const { languageCode } = require('./language-guard');
const { vocabularyPrompt, isVocabularyEcho } = require('./polish-prompt');
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
  let vocab = vocabularyPrompt(vocabulary);
  if (estimateTokens(vocab) > 90) {
    const kept = [];
    for (const item of vocab.split(', ')) {
      if (estimateTokens([...kept, item].join(', ')) > 90) break;
      kept.push(item);
    }
    vocab = kept.join(', ');
  }
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
// Ohne segmentgenaue VAD nur mit der gesamten Sprechzeit verwerfen: konservativ.
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
      (vocabulary && isVocabularyEcho(text, vocabulary)) ||
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
        text: kept.map((s) => s.text.trim()).join(' '),
        segments: kept,
      };
  } else if (echo(response.text || '')) return { ...response, text: '' };
  return response;
}
module.exports = { primer, estimateTokens, buildPrompt, removeEchoes };
