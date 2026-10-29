// Port von PaplyKit/Thoughts/AI/SpokenNumbers, ausschließlich für Profil „thought“.
const { normalizedLower } = require('./polish-text');
const indexed = (words, start = 0, step = 1) => Object.fromEntries(words.split(' ').map((w, i) => [w, start + i * step]));
const english = { ...indexed('zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'), ...indexed('first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth', 1), ...indexed('twenty thirty forty fifty sixty seventy eighty ninety', 20, 10) };
for (const w of 'twenty thirty forty fifty sixty seventy eighty ninety'.split(' ')) english[w.slice(0, -1) + 'ieth'] = english[w];
const units = indexed('eins zwei drei vier fünf sechs sieben acht neun', 1);
const teens = indexed('zehn elf zwölf dreizehn vierzehn fünfzehn sechzehn siebzehn achtzehn neunzehn', 10);
const tens = indexed('zwanzig dreißig vierzig fünfzig sechzig siebzig achtzig neunzig', 20, 10);
const articles = new Set('ein eine einen einem einer eines a an'.split(' '));
const enumerators = { ...indexed('erstens zweitens drittens viertens fünftens sechstens siebtens achtens neuntens zehntens', 1), ...indexed('firstly secondly thirdly', 1) };
const months = { ...indexed('januar februar märz april mai juni juli august september oktober november dezember', 1), ...indexed('january february march april may june july august september october november december', 1), jänner: 1 };
// Wortlisten dürfen keine geerbten Object-Eigenschaften als Zahl behandeln.
for (const map of [english, units, teens, tens, enumerators, months]) Object.setPrototypeOf(map, null);
function below100(w) {
  if (Object.hasOwn(units, w) || Object.hasOwn(teens, w) || Object.hasOwn(tens, w)) return units[w] ?? teens[w] ?? tens[w];
  const k = w.indexOf('und');
  if (k < 0) return null;
  const a = w.slice(0, k), b = w.slice(k + 3), unit = a === 'ein' ? 1 : units[a];
  return unit && tens[b] ? unit + tens[b] : null;
}
function composed(w, separator, factor, parseHigh, parseLow, maxHigh = Infinity) {
  const k = w.indexOf(separator);
  if (k < 0) return parseLow(w);
  const head = w.slice(0, k), tail = w.slice(k + separator.length);
  const high = !head || head === 'ein' ? 1 : parseHigh(head);
  const low = !tail ? 0 : parseLow(tail.startsWith('und') ? tail.slice(3) : tail);
  return high !== null && low !== null && high > 0 && high <= maxHigh ? high * factor + low : null;
}
const below1000 = w => composed(w, 'hundert', 100, below100, below100, 99);
const cardinal = w => w ? composed(w, 'tausend', 1000, below1000, below1000) : null;
function germanValue(w) {
  if (w.length < 3) return null;
  const value = cardinal(w);
  if (value !== null) return value;
  if (w.endsWith('mal') && w.length > 5 && cardinal(w.slice(0, -3)) !== null) return cardinal(w.slice(0, -3));
  for (const ending of ['e', 'en', 'er', 'es', 'em']) for (const [stem, v] of Object.entries({ erst: 1, dritt: 3, siebt: 7, acht: 8 })) if (w === stem + ending) return v;
  for (const ending of ['sten', 'ster', 'stes', 'stem', 'ste', 'ten', 'ter', 'tes', 'tem', 'te']) if (w.endsWith(ending)) {
    const v = cardinal(w.slice(0, -ending.length)); if (v > 1) return v;
  }
  return null;
}
function words(text) {
  return [...normalizedLower(text).matchAll(/[0-9]+(?:[. ’'\u202f\u00a0][0-9]{3}(?![0-9]))*|\p{L}[\p{L}\p{M}]*/gu)].map(m => {
    const digits = m[0].replace(/[. ’'\u202f\u00a0]/g, '');
    return { text: /^[0-9]/.test(m[0]) ? digits : m[0], digits: /^[0-9]+$/.test(digits) && digits.length <= 12 ? Number(digits) : null };
  });
}
function englishSequence(words, start) {
  let total = 0, current = 0, last = 'none', k = start;
  for (; k < words.length && words[k].digits === null; k++) {
    const w = words[k].text, v = english[w];
    if (v !== undefined) {
      if (last === 'none') current = v;
      else if ((last === 'tens' && v >= 1 && v <= 9) || last === 'hundred' || last === 'thousand') current += v;
      else break;
      last = v >= 20 && v % 10 === 0 ? 'tens' : 'unit';
    } else if (w === 'hundred' && ['none', 'unit', 'tens'].includes(last)) { current = Math.max(1, current) * 100; last = 'hundred'; }
    else if (w === 'thousand' && last !== 'thousand') { total += Math.max(1, current) * 1000; current = 0; last = 'thousand'; }
    else if (w === 'and' && ['hundred', 'thousand'].includes(last) && english[words[k + 1]?.text] !== undefined) continue;
    else break;
  }
  return last === 'none' ? null : [total + current, k - start];
}
function tokens(words) {
  const out = [];
  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    if (w.digits !== null) { out.push({ value: w.digits, kind: 'digits', word: i }); continue; }
    const sequence = englishSequence(words, i);
    if (sequence) {
      const [value, used] = sequence;
      out.push({ value, kind: used === 1 && ['one', 'first', 'second'].includes(w.text) ? 'optional' : 'word', word: i }); i += used - 1; continue;
    }
    const optional = articles.has(w.text) ? 1 : enumerators[w.text] ?? months[w.text];
    const value = optional ?? germanValue(w.text);
    if (value !== null) out.push({ value, kind: optional !== undefined || (value === 1 && w.text.startsWith('erst')) ? 'optional' : 'word', word: i });
  }
  return out;
}
function correctedWords(words, tokens) {
  const texts = words.map(w => w.text), corrected = new Set();
  const negators = new Set('nee nein ne nö no nope non'.split(' ')), after = new Set('warte moment quatsch falsch sorry stopp wait scratch'.split(' '));
  const standalone = ['ich meine', 'ich mein', 'i mean', 'scratch that', 'korrektur'].map(s => s.split(' '));
  for (let i = 0; i < texts.length; i++) {
    let end;
    if (negators.has(texts[i])) {
      if (after.has(texts[i + 1])) end = i + 2;
      else if (tokens.some(t => t.word === i + 1 && t.kind !== 'optional')) end = i + 1;
    } else {
      const marker = standalone.find(m => m.every((w, k) => texts[i + k] === w));
      if (marker) end = i + marker.length;
    }
    if (end === undefined) continue;
    const next = tokens.find(t => t.word >= end && t.word <= end + 3 && t.kind !== 'optional');
    const previous = tokens.filter(t => t.word < i && t.word >= i - 6 && t.kind !== 'optional').at(-1);
    if (next && previous) corrected.add(previous.word);
    i = end - 1;
  }
  return corrected;
}
function preserved(raw, result) {
  const rawWords = words(raw), source = tokens(rawWords), target = tokens(words(result));
  const found = new Set(target.map(t => t.value)), corrected = correctedWords(rawWords, source), available = new Set(source.map(t => t.value));
  return source.every(t => t.kind === 'optional' || found.has(t.value) || corrected.has(t.word)) && target.every(t => t.kind !== 'digits' || available.has(t.value));
}
function isNumberWord(word) {
  const w = normalizedLower(word);
  if (english[w] !== undefined || ['hundred', 'thousand'].includes(w) || enumerators[w] !== undefined) return true;
  if (articles.has(w) || months[w] !== undefined) return false;
  return germanValue(w) !== null;
}
module.exports = { preserved, isNumberWord, germanValue, words, tokens };
