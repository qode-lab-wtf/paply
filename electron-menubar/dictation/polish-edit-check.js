// Wortgenauer Port von PaplyKit/EditCheck; Reihenfolge und Grenzen sind absichtlich gleich.
const T = require('./polish-text');
const numberWords = T.lexicon.numberWords;
const numberValue = word => /^[0-9]+$/.test(word) ? BigInt(word) : (Object.hasOwn(numberWords, word) ? BigInt(numberWords[word]) : null);
const isQuantity = word => numberValue(word) !== null && (numberValue(word) !== 1n || /^[0-9]+$/.test(word));
function numberTokens(text) {
  const chars = Array.from(T.normalizedLower(text)), tokens = [];
  let i = 0;
  const digit = c => c !== undefined && /^[0-9]$/.test(c);
  while (i < chars.length) {
    if (digit(chars[i])) {
      let value = '';
      while (i < chars.length) {
        if (digit(chars[i])) { value += chars[i++]; continue; }
        let j = i;
        while (j < chars.length && !digit(chars[j]) && !/\p{L}/u.test(chars[j])) j++;
        if (j < chars.length && digit(chars[j])) i = j; else break;
      }
      tokens.push({ digits: value });
    } else if (/\p{L}/u.test(chars[i])) {
      let word = '';
      while (i < chars.length && /[\p{L}\p{M}]/u.test(chars[i])) word += chars[i++];
      if (Object.hasOwn(numberWords, word)) tokens.push({ word: BigInt(numberWords[word]) });
    } else i++;
  }
  return tokens;
}
function digitsPreserved(raw, result) {
  const source = numberTokens(raw), available = numberTokens(result), used = new Set();
  let position = 0;
  for (const token of source.filter(t => t.digits !== undefined)) {
    const index = available.findIndex((t, i) => i >= position && (t.digits !== undefined ? t.digits === token.digits : t.word === BigInt(token.digits)));
    if (index < 0) return false;
    used.add(index); position = index + 1;
  }
  const words = source.filter(t => t.word !== undefined).map(t => t.word);
  for (const [i, token] of available.entries()) {
    if (used.has(i) || token.digits === undefined) continue;
    const k = words.indexOf(BigInt(token.digits));
    if (k < 0) return false;
    words.splice(k, 1);
  }
  return true;
}
function resolvedSelfCorrection(raw) {
  const tokens = [...raw.matchAll(/[\p{L}\p{M}\p{N}]+/gu)];
  const words = tokens.map(m => T.normalizedLower(m[0]));
  const between = (a, b) => raw.slice(tokens[a].index + tokens[a][0].length, tokens[b].index);
  const markers = T.lexicon.correctionMarkers.map(s => T.alphanumericRuns(T.normalizedLower(s)));
  const cuts = [];
  let i = 0;
  while (i < words.length) {
    const marker = markers.find(m => m.every((w, k) => words[i + k] === w));
    if (!marker) { i++; continue; }
    let start = i;
    if (start > 0 && T.answerNegators.has(words[start - 1])) start--;
    const end = i + marker.length;
    if (!(start > 0 && /[,–—\-…;]/u.test(between(start - 1, start))) || end >= words.length) { i = end; continue; }
    let replacement = 1;
    while (end + replacement < words.length && replacement < 6 && !/[,.;!?:–—…]/u.test(between(end + replacement - 1, end + replacement))) replacement++;
    let spanStart = start;
    while (spanStart > 0 && start - spanStart < replacement && !/[.!?…]/u.test(between(spanStart - 1, spanStart))) spanStart--;
    if (spanStart >= start) { i = end; continue; }
    cuts.push([tokens[spanStart].index, tokens[end].index]); i = end + replacement;
  }
  if (!cuts.length) return null;
  let resolved = raw;
  for (const [start, end] of cuts.reverse()) resolved = resolved.slice(0, start) + resolved.slice(end);
  return resolved;
}
function editDistance(a, b) {
  const x = Array.from(a), y = Array.from(b);
  const d = Array.from({ length: x.length + 1 }, (_, i) => Array.from({ length: y.length + 1 }, (_, j) => i ? (j ? 0 : i) : j));
  for (let i = 1; i <= x.length; i++) for (let j = 1; j <= y.length; j++) {
    d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (x[i - 1] === y[j - 1] ? 0 : 1));
    if (i > 1 && j > 1 && x[i - 1] === y[j - 2] && x[i - 2] === y[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
  }
  return d[x.length][y.length];
}
const isSmallCorrection = (a, b) => editDistance(a, b) <= Math.max(1, Math.floor(Math.min(Array.from(a).length, Array.from(b).length) / 4));
const variants = new Set(['ok', 'okay', 'okey', 'oke', 'okej', 'okee']);
const areVariants = (a, b) => variants.has(a) && variants.has(b);
function compoundAligned(raw, result) {
  function merge(words, other) {
    const out = [];
    for (let i = 0; i < words.length; i++) {
      if (i + 1 < words.length && !(other.has(words[i]) && other.has(words[i + 1])) && other.has(words[i] + words[i + 1])) out.push(words[i] + words[++i]);
      else out.push(words[i]);
    }
    return out;
  }
  const r = merge(raw, new Set(result));
  return [r, merge(result, new Set(r))];
}
function expandContractions(text) {
  for (const [pattern, replacement] of [[/\bcan['’]t\b/g, 'can not'], [/\bcannot\b/g, 'can not'], [/\bwon['’]t\b/g, 'will not'], [/n['’]t\b/g, ' not'], [/['’]re\b/g, ' are'], [/['’]ve\b/g, ' have'], [/['’]ll\b/g, ' will'], [/\bi['’]m\b/g, 'i am']]) text = text.replace(pattern, replacement);
  return text;
}
function lcsPairs(a, b) {
  const n = a.length, m = b.length, table = new Uint16Array((n + 1) * (m + 1));
  const at = (i, j) => i * (m + 1) + j;
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) table[at(i, j)] = a[i] === b[j] ? table[at(i + 1, j + 1)] + 1 : Math.max(table[at(i + 1, j)], table[at(i, j + 1)]);
  const pairs = [];
  let i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) { pairs.push([i++, j++]); }
    else if (table[at(i + 1, j)] >= table[at(i, j + 1)]) i++; else j++;
  }
  return pairs;
}
function substitutionRejection(raw, result, vocabulary = '') {
  if (T.continua.test(raw) || T.continua.test(result)) return null;
  const cleaned = [];
  for (const w of T.alphanumericRuns(expandContractions(T.normalizedLower(raw)))) if (!T.fillers.has(w) && cleaned.at(-1) !== w) cleaned.push(w);
  const [r, h] = compoundAligned(cleaned, T.alphanumericRuns(expandContractions(T.normalizedLower(result))));
  if (!r.length || !h.length || r.length * h.length > 4000000) return null;
  const custom = new Set(T.alphanumericRuns(T.normalizedLower(vocabulary))), pairs = lcsPairs(r, h);
  const matchedRaw = new Set(pairs.map(([i]) => i)), movable = new Map();
  r.forEach((w, i) => { if (!matchedRaw.has(i)) movable.set(w, (movable.get(w) || 0) + 1); });
  const numberEquivalent = (a, b) => numberValue(a) !== null && numberValue(a) === numberValue(b);
  const compatible = (a, b) => a === b || numberEquivalent(a, b) || areVariants(a, b) || isSmallCorrection(a, b);
  let previous = [-1, -1];
  for (const [i, j] of [...pairs, [r.length, h.length]]) {
    const rawStart = previous[0] + 1, gapRaw = r.slice(rawStart, i), gapResult = h.slice(previous[1] + 1, j);
    previous = [i, j];
    if (!gapResult.length || gapRaw.join('') === gapResult.join('')) continue;
    let pointer = 0;
    for (const b of gapResult) {
      const k = gapRaw.findIndex((a, index) => index >= pointer && compatible(a, b));
      if (k >= 0) {
        const a = gapRaw[k], before = rawStart + k - 1;
        if (a !== b && !numberEquivalent(a, b) && !areVariants(a, b) && before >= 0 && isQuantity(r[before])) return 'replaced';
        pointer = k + 1; continue;
      }
      if (movable.get(b) > 0) { movable.set(b, movable.get(b) - 1); continue; }
      if (custom.has(b)) { pointer = Math.min(pointer + 1, gapRaw.length); continue; }
      if (T.weightedLength(b) < 4 || T.fillers.has(b) || numberValue(b) !== null) continue;
      return pointer < gapRaw.length ? 'replaced' : 'inserted';
    }
  }
  return null;
}
module.exports = { numberValue, numberTokens, digitsPreserved, resolvedSelfCorrection, editDistance, isSmallCorrection, compoundAligned, substitutionRejection, lcsPairs };
