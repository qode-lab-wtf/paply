// Reine Prüfung der Modellantwort. Aufrufer behalten bei Ablehnung den Rohtext.
const FILLERS = new Set(['also', 'sozusagen', 'quasi', 'halt', 'eben', 'irgendwie', 'äh', 'ähm', 'mhm', 'naja']);

function finalPolishText(content) {
  if (typeof content !== 'string') return '';
  let text = content.replace(/<(think|analysis)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, '')
    .replace(/^[\s\S]*?<\/(?:think|analysis)\s*>/i, '')
    .replace(/<(?:think|analysis)\b[\s\S]*$/gi, '').trim();
  const final = text.match(/(?:<\|channel\|>final(?:<\|message\|>|\|>)|<\|final\|>)([\s\S]*)/);
  if (final) text = final[1].replace(/<\|[^>]+\|>/g, '').trim();
  return /<\|(?:channel\|>analysis|start\|>)/i.test(text) ? '' : text;
}

function contentWords(text) {
  return (text.normalize('NFC').toLocaleLowerCase('de').match(/\p{L}{4,}/gu) || [])
    .filter(word => !FILLERS.has(word));
}

function polishRejection(raw, result) {
  if (!result) return 'empty';
  if (/^(?:hier\s+(?:ist|sind|der|das)|(?:der\s+)?(?:poliert|korrigiert|überarbeitet)(?:er|e|es)\s+text\s*:|here\s+(?:is|are)|(?:polished|corrected)\s+text\s*:)/iu.test(result)
    || /^(?:"[\s\S]*"|„[\s\S]*[“”]|“[\s\S]*”|«[\s\S]*»|'[\s\S]*'|‚[\s\S]*‘)$/u.test(result)) return 'meta';
  const ratio = Array.from(result).length / Math.max(1, Array.from(raw.trim()).length);
  if (ratio < 0.7 || ratio > 1.3) return 'length';
  const before = contentWords(raw);
  const remaining = new Map();
  for (const word of contentWords(result)) remaining.set(word, (remaining.get(word) || 0) + 1);
  let missing = 0;
  for (const word of before) {
    const count = remaining.get(word) || 0;
    if (count) remaining.set(word, count - 1);
    else missing++;
  }
  return before.length && missing / before.length > 0.3 ? 'content' : null;
}

module.exports = { finalPolishText, contentWords, polishRejection };
