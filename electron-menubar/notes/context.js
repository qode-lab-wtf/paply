'use strict';
function splitSentences(text, prefix) {
  const segmenter = new Intl.Segmenter('de', { granularity: 'sentence' });
  const parts = [...segmenter.segment(text)].map(s => s.segment.trim()).filter(Boolean);
  // Keep even very long unpunctuated speech intact. Such input can remain a raw note.
  return parts.map((value, i) => ({ id: `${prefix}_s${i}`, text: value }));
}
function chunks(sentences) {
  const result = []; let current = [], size = 0;
  for (const s of sentences) {
    if (current.length && (current.length >= 24 || size + s.text.length > 3000)) { result.push(current); current = []; size = 0; }
    current.push(s); size += s.text.length;
  }
  if (current.length) result.push(current); return result;
}
function context(board, sentences, entryId = null) {
  const words = new Set(sentences.map(s => s.text).join(' ').toLocaleLowerCase('de').match(/[\p{L}\d]{3,}/gu) || []);
  const score = n => ((n.text + ' ' + n.label).toLocaleLowerCase('de').match(/[\p{L}\d]{3,}/gu) || []).reduce((v, w) => v + (words.has(w) ? 1 : 0), 0);
  const localScore = n => { const other = new Set(((n.text + ' ' + n.label).toLowerCase().match(/[\p{L}\d]{3,}/gu) || [])); return [...words].filter(w => other.has(w)).length / Math.max(1, new Set([...words, ...other]).size); };
  const candidates = Object.values(board.nodes).filter(n => !['point', 'hub'].includes(n.kind) && !n.pending && (!entryId || n.sourceId !== entryId)).sort((a, b) => score(b) - score(a) || b.createdAt - a.createdAt).slice(0, 8);
  const spoken = ' ' + sentences.map(s => s.text).join(' ').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ') + ' ';
  const mentioned = t => t.mentioned || spoken.includes(' ' + t.title.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ') + ' ');
  const topics = Object.values(board.topics).sort((a, b) => (candidates.some(n => n.topicId === b.id) ? 1 : 0) - (candidates.some(n => n.topicId === a.id) ? 1 : 0)).slice(0, 32);
  return { topics: topics.map(t => ({ id: t.id, title: t.title, ...(t.about || t.note ? { about: t.about || t.note } : {}), ...(mentioned(t) ? { mentioned: true } : {}), n: new Set(Object.values(board.nodes).filter(n => n.topicId === t.id).map(n => n.sourceId || n.id)).size })), existing: candidates.map(n => ({ id: n.id, topic: n.topicId, label: n.label, text: n.text.slice(0, 160), score: localScore(n), createdAt: n.createdAt, when: new Date(n.createdAt).toLocaleString() })), sentences };
}

module.exports = { splitSentences, chunks, context };
