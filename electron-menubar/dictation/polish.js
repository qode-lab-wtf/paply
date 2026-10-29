// Sicherheitsnetz auf PaplyKit-Stand. Bei Ablehnung behält der Aufrufer den Rohtext.
const T = require('./polish-text');
const E = require('./polish-edit-check');
const SpokenNumbers = require('./polish-spoken-numbers');
const { contentWords, negationCount } = T;

function finalPolishText(content) {
  if (typeof content !== 'string') return '';
  let text = content.replace(/<(think|analysis)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
    .replace(/^[\s\S]*?<\/(?:think|analysis)\s*>/i, '')
    .replace(/<(?:think|analysis)\b[\s\S]*$/gi, '').trim();
  const final = text.match(/(?:<\|channel\|>final(?:<\|message\|>|\|>)|<\|final\|>)([\s\S]*)/);
  if (final) text = final[1].replace(/<\|[^>]+\|>/g, '').trim();
  return /<\|(?:channel\|>analysis|start\|>)/i.test(text) ? '' : text;
}

const PROFILES = Object.freeze({
  dictation: Object.freeze({ lengthLow: 0.7, lengthHigh: 1.3, missingContent: 0.3, addedShare: 0.15, ignoresLayout: false, spoken: false }),
  thought: Object.freeze({ lengthLow: 0.55, lengthHigh: 1.15, missingContent: 0.25, addedShare: 0.10, ignoresLayout: true, spoken: true }),
});
const metaAnswer = new RegExp(T.lexicon.metaAnswer, 'iu');
const wrappedInQuotes = new RegExp(T.lexicon.wrappedInQuotes, 'u');
const spokenNegationCount = text => negationCount(text.replace(/[\p{L}\p{M}]+/gu, w => ['nee', 'nein', 'nö'].includes(T.normalizedLower(w)) ? '' : w));
function polishRejection(raw, result, { vocabulary = '', strictEdits = true, profile } = {}) {
  const limits = PROFILES[profile ?? 'dictation'];
  if (!limits) throw new RangeError('Unbekanntes Polier-Profil');
  if (profile) strictEdits = profile === 'dictation';
  if (!result) return 'empty';
  if ((metaAnswer.test(result) && !metaAnswer.test(raw.trim())) || (wrappedInQuotes.test(result) && !wrappedInQuotes.test(raw.trim()))) return 'meta';
  const reason = check(raw, result, vocabulary, strictEdits, raw, limits);
  if (!reason) return null;
  const resolved = E.resolvedSelfCorrection(raw);
  if (resolved !== null && !check(resolved, result, vocabulary, strictEdits, raw, limits)) return null;
  return reason;
}
function check(raw, result, vocabulary, strictEdits, lengthReference, limits) {
  const measured = limits.ignoresLayout ? result.replaceAll('• ', '').replaceAll('\n', '') : result;
  const length = Array.from(measured).length;
  if (length / Math.max(1, Array.from(raw.trim()).length) < limits.lengthLow || length / Math.max(1, Array.from(lengthReference.trim()).length) > limits.lengthHigh) return 'length';
  const [r, h] = E.compoundAligned(T.letterRuns(T.normalizedLower(raw)), T.letterRuns(T.normalizedLower(result)));
  let before = contentWords(r.join(' ')), after = contentWords(h.join(' '));
  if (limits.spoken) { before = before.filter(w => !SpokenNumbers.isNumberWord(w)); after = after.filter(w => !SpokenNumbers.isNumberWord(w)); }
  const remaining = new Map();
  for (const w of after) remaining.set(w, (remaining.get(w) || 0) + 1);
  let missing = 0;
  for (const w of before) {
    if (remaining.get(w) > 0) remaining.set(w, remaining.get(w) - 1); else missing++;
  }
  if (before.length && missing / before.length > limits.missingContent) return 'content';
  const countNegations = limits.spoken ? spokenNegationCount : negationCount;
  if (countNegations(raw) !== countNegations(result)) return 'negation';
  if (!(limits.spoken ? SpokenNumbers.preserved(raw, result) : E.digitsPreserved(raw, result))) return 'digits';
  if (strictEdits) { const reason = E.substitutionRejection(raw, result, vocabulary); if (reason) return reason; }
  const allowed = new Set([...before, ...contentWords(vocabulary)]);
  const added = after.filter(w => !allowed.has(w)).length;
  return added - missing > Math.max(2, Math.ceil(before.length * limits.addedShare)) ? 'added' : null;
}
module.exports = { finalPolishText, contentWords, polishRejection, negationCount, PROFILES };
