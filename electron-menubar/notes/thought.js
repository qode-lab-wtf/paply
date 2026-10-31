'use strict';
const C = require('./contracts');
const { polishRejection, contentWords, negationCount } = require('./safety');
const { VERSION } = require('./prompt');
const obj = properties => ({ type: 'object', additionalProperties: false, required: Object.keys(properties).sort(), properties });
const string = { type: 'string' }, nullable = { type: ['string', 'null'] }, array = items => ({ type: 'array', items }), enumeration = values => ({ type: 'string', enum: values });
const SCHEMA = obj({ title: string, clean_text: string, topic: obj({ choice: enumeration(['existing','new','none']), id: nullable, new_name: nullable, symbol: enumeration(C.ICONS) }), tasks: array(obj({ text: string, quote: string, due_hint: nullable })), related: array(obj({ ref: string, kind: enumeration(['continues','same_matter','changes']), reason: string, confidence: enumeration(['high','medium','low']) })) });
const words = s => s.toLowerCase().match(/[\p{L}\p{N}]+/gu) || [];
const { languageCode } = require('../dictation/language-guard');
const { normalizedLower } = require('../dictation/polish-text');
const digits = require('./numbers').digitsContained;
const fallbackTitle = text => [...text.trim().split(/\s+/).slice(0, 6).join(' ')].slice(0, 60).join('');
const effectiveNegations = s => negationCount(s.replace(/nicht vergessen|vergiss nicht|don't forget|do not forget|n'oublie(?:z)? pas/gi, ''));
const taskStopwords = new Set('der die das den dem des ein eine einen einem einer und oder für mit von vom zu zum zur im in ins an am ans auf bei beim wegen noch the a an and or for with to of in on at le la les un une de du des et pour el los las y para con il lo gli e per o os as um uma het een en voor met'.split(' '));
function dueInQuote(hint, quote) {
  const due = words(hint), source = words(quote);
  if (!due.length) return false;
  for (let start = 0; start < source.length; start++) {
    if (source[start] !== due[0]) continue;
    let pos = start, pieces = 1, matches = true;
    for (const word of due.slice(1)) { const next = source.indexOf(word, pos + 1); if (next < 0) { matches = false; break; } if (next !== pos + 1) pieces++; pos = next; }
    if (matches && pieces <= 3 && pos - start < 20) return true;
  }
  return false;
}
function validate(value, ctx) {
  const raw = ctx.sentences.map(s => s.text).join(' ');
  if (!value || typeof value.title !== 'string' || typeof value.clean_text !== 'string' || !value.topic || !Array.isArray(value.tasks) || !Array.isArray(value.related) || (!value.title.trim() && !value.clean_text.trim())) throw Object.assign(new Error('Einordnung nicht lesbar'), { kind: 'plan' });
  const clean = value.clean_text.trim();
  const text = polishRejection(raw, clean, { profile: 'thought', vocabulary: ctx.custom_terms || '' }) ? raw : clean;
  let title = value.title.split('\n')[0].trim().replace(/^["'„“«]+|["'„“».,!?;:… –—-]+$/g, '');
  const languages = (ctx.spoken_languages || []).map(languageCode).filter(c => c && c !== 'und');
  const strict = languages.length > 0 && !languages.includes(languageCode(ctx.ui_language || ''));
  const content = contentWords(title), source = normalizedLower(raw);
  const grounded = w => contentWords(source).includes(w);
  if (!title || [...title].length > 60 || !digits(title, raw) || !content.length || !(strict ? content.every(grounded) : content.some(grounded))) title = fallbackTitle(text);
  let topic = null;
  if (value.topic.choice === 'existing' && ctx.topics.some(t => t.id === value.topic.id)) topic = { id: value.topic.id };
  if (value.topic.choice === 'new' && typeof value.topic.new_name === 'string') {
    const name = value.topic.new_name.trim(), same = ctx.topics.filter(t => t.title.toLowerCase() === name.toLowerCase());
    if (same.length === 1) topic = { id: same[0].id };
    else if (!same.length && !ctx.topics_full && name && [...name].length <= 24 && name.split(/\s+/).length <= 3 && !/\d/.test(name) && !/^(Ideen|Gedanken|Notizen|Sonstiges|Allgemein|Aufgaben|Wichtig|Privat|Arbeit|Ideas|Notes|Misc|Todo)$/i.test(name)) topic = { name, icon: C.ICONS.includes(value.topic.symbol) ? value.topic.symbol : 'sparkles' };
  }
  const tasks = [], seen = new Set();
  for (const t of value.tasks.slice(0, 5)) {
    if (!t || typeof t.text !== 'string' || typeof t.quote !== 'string') continue;
    const quote = t.quote.trim(), text = t.text.trim().replace(/\n/g, ' ');
    if ([...quote].length < 2 || [...quote].length > 80 || !raw.includes(quote) || [...text].length < 2 || [...text].length > 80) continue;
    if (words(text).filter(w => w.length >= 2 && !taskStopwords.has(w) && !words(quote).includes(w)).length > 1 || !digits(text, quote) || effectiveNegations(text) !== effectiveNegations(quote)) continue;
    const due_hint = typeof t.due_hint === 'string' && t.due_hint.trim() && dueInQuote(t.due_hint, quote) ? t.due_hint.trim() : null;
    const key = words(text).join(' ') + '|' + (due_hint || '').toLowerCase();
    if (!seen.has(key)) { seen.add(key); tasks.push({ text, quote, due_hint }); }
  }
  const related = [], refs = new Set();
  for (const r of value.related.slice(0, 3)) {
    const candidate = ctx.existing.find(n => n.id === r?.ref);
    if (!candidate || candidate.score < .75 || !['high','medium'].includes(r.confidence) || !['continues','same_matter','changes'].includes(r.kind) || typeof r.reason !== 'string' || !r.reason.trim() || [...r.reason].length > 60 || !digits(r.reason, raw + candidate.text + candidate.label) || refs.has(r.ref)) continue;
    refs.add(r.ref); related.push(r);
  }
  return { title, text, topic, tasks, related };
}
function applyThought(board, result, { rawId, rawRev }) {
  const n = board.nodes[rawId];
  if (!n || n.rev !== rawRev || n.owner === 'user') return false;
  let topicId = result.topic?.id;
  if (result.topic?.name) {
    const same = Object.values(board.topics).find(t => t.title.toLowerCase() === result.topic.name.toLowerCase());
    topicId = same?.id || C.uid('t');
    if (!same) board.topics[topicId] = { id: topicId, title: result.topic.name, icon: result.topic.icon, owner: 'ai', createdAt: Date.now() };
  }
  Object.assign(n, { label: result.title, text: result.text, topicId: board.topics[topicId] ? topicId : null, owner: 'ai', ruleVersion: VERSION, rev: n.rev + 1 });
  board.tasks ||= {};
  // User-owned and completed tasks survive every later AI result, even if its wording changes.
  const protectedQuotes = Object.values(board.tasks).filter(t => t.sourceId === n.sourceId && (t.owner === 'user' || t.done)).map(t => t.quote);
  for (const [id, t] of Object.entries(board.tasks)) if (t.nodeId === n.id && t.owner !== 'user' && !t.done) delete board.tasks[id];
  const sourceTasks = Object.values(board.tasks).filter(t => t.sourceId === n.sourceId);
  for (const task of result.tasks.slice(0, Math.max(0, 5 - sourceTasks.length))) {
    if (protectedQuotes.includes(task.quote) || sourceTasks.some(t => t.text === task.text && t.due_hint === task.due_hint)) continue;
    const id = C.uid('task'); board.tasks[id] = { ...task, id, sourceId: n.sourceId, nodeId: n.id, owner: 'ai', done: false };
  }
  for (const r of result.related) {
    if (!board.nodes[r.ref] || r.ref === n.id || Object.values(board.edges).some(e => e.source === n.id && e.target === r.ref)) continue;
    const id = C.uid('e'); board.edges[id] = { id, source: n.id, target: r.ref, sourceHandle: 'right', targetHandle: 'left', arrow: false, inferred: true, label: r.reason, rev: 1 };
  }
  return true;
}
module.exports = { SCHEMA, validate, applyThought, fallbackTitle };
