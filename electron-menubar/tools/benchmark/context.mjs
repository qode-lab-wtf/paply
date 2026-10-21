import polishPrompt from '../../dictation/polish-prompt.js';
import groqModels from '../../dictation/groq-models.js';
const { POLISH_SYSTEM_PROMPT, buildPolishMessages, uncertainSegments } = polishPrompt;
import { hash } from './api.mjs';

export const CONTEXT_MODELS = [groqModels.POLISH_MODEL, groqModels.POLISH_FALLBACK_MODEL];
export const CONTEXT_PROMPT = POLISH_SYSTEM_PROMPT;

export function previousDictations(rows, index) {
  return rows.slice(Math.max(0, index - 3), index).map(r => {
    if (typeof r.transcripts.a?.text !== 'string') throw new Error(`Vorheriger Rohtext a fehlt: ${r.id}`);
    return { id: r.id, text: r.transcripts.a.text };
  });
}
export function whisperContext(history, maxChars = 200) {
  const text = history.map(r => r.text).join('\n');
  const chars = Array.from(text);
  if (chars.length <= maxChars) return text;
  // Keep the recent end, cutting at a word boundary, never adding vocabulary.
  const tail = chars.slice(-maxChars).join('');
  return /\s/u.test(chars[chars.length - maxChars - 1]) ? tail : tail.replace(/^\S+\s*/u, '');
}
export { uncertainSegments };
export function contextMessages(transcript, history) {
  return buildPolishMessages(transcript.text, { history: history.map(r => r.text), segments: transcript.segments });
}
export const baseTranscriptHash = row => hash(['a', 'b', 'c'].map(k => row.transcripts[k] || null));
export function chronological(a, b) {
  const time = r => typeof r.meta.createdAt === 'number' ? r.meta.createdAt : Date.parse(r.meta.createdAt || '');
  const ta = time(a), tb = time(b);
  if (Number.isFinite(ta) && Number.isFinite(tb)) return ta - tb || a.id.localeCompare(b.id);
  if (Number.isFinite(ta) !== Number.isFinite(tb)) return Number.isFinite(ta) ? -1 : 1;
  return a.id.localeCompare(b.id);
}
export function isPolishFresh(polished, rows, index) {
  const row = rows[index], input = row.transcripts[polished.inputVariant || 'a'];
  if (!input || polished.inputHash !== hash(input.text)) return false;
  if (!['P2', 'W-ctx+P2'].includes(polished.variant)) return true;
  try { return polished.promptHash === hash(contextMessages(input, previousDictations(rows, index))); }
  catch { return false; }
}
