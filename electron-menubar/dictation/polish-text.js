// Port von PaplyKit/TextAnalysis und Lexicon. Nur für den Polier-Schritt.
const lexicon = require('./polish-lexicon.json');
const normalizedLower = text => text.normalize('NFC').toLowerCase().replace(/i\u0307/g, 'i').replace(/ı/g, 'i').normalize('NFC');
const sets = Object.fromEntries(['fillers', 'negations', 'answerNegators'].map(k => [k, new Set(lexicon[k].map(normalizedLower))]));
const letterRuns = text => text.match(/[\p{L}\p{M}]+/gu) || [];
const alphanumericRuns = text => text.match(/[\p{L}\p{M}\p{N}]+/gu) || [];
const continua = /[\u3005-\u3007\u3040-\u30ff\u31f0-\u31ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff66-\uff9d\u{20000}-\u{2fa1f}\u0e00-\u0e7f\u0e80-\u0eff\u1000-\u109f\u1780-\u17ff]/u;
const weightedLength = word => Array.from(word).reduce((n, c) => n + (/[\uac00-\ud7a3]/u.test(c) ? 2 : 1), 0);
function contentWords(text) {
  const units = [];
  for (const run of letterRuns(normalizedLower(text))) {
    let latin = '', sequence = [];
    const flushLatin = () => { if (weightedLength(latin) >= 4 && !sets.fillers.has(latin)) units.push(latin); latin = ''; };
    const flushSequence = () => {
      if (sequence.length === 1) units.push(sequence[0]);
      for (let i = 1; i < sequence.length; i++) units.push(sequence[i - 1] + sequence[i]);
      sequence = [];
    };
    for (const c of run) {
      if (continua.test(c)) { flushLatin(); sequence.push(c); }
      else { flushSequence(); latin += c; }
    }
    flushLatin(); flushSequence();
  }
  return units;
}
function negationCount(text) {
  const lower = normalizedLower(text);
  let count = 0;
  for (const m of lower.matchAll(/[\p{L}\p{M}]+/gu)) {
    if (sets.negations.has(m[0])) count++;
    else if (sets.answerNegators.has(m[0])) {
      const head = lower.slice(0, m.index).replace(/[ \t\n¡¿"„“«(‚']+$/u, '');
      const rest = lower.slice(m.index + m[0].length).replace(/^[ \t]+/, '');
      const correction = lexicon.correctionPhrases.some(p => rest.startsWith(p) && !/^[\p{L}\p{M}\p{N}]/u.test(rest.slice(p.length)));
      if (!head || /[.!?…:]$/u.test(head) || (/^\p{L}/u.test(rest) && !correction)) count++;
    }
  }
  count += (lower.match(/n['’]t\b/gu) || []).length;
  count += Array.from(lower).filter(c => '不没沒无無别別未莫勿않없못'.includes(c)).length;
  for (const fragment of lexicon.negationFragments) count += lower.split(fragment).length - 1;
  return count;
}
module.exports = { lexicon, ...sets, normalizedLower, letterRuns, alphanumericRuns, continua, weightedLength, contentWords, negationCount };
