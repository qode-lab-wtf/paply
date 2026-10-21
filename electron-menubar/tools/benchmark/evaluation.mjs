// Evaluation data is loaded only by score/audit, never by the inference prompt builders.
import { hash } from './api.mjs';
import { align, normalize, words } from './core.mjs';
import { CONTEXT_MODELS } from './context.mjs';
export const experimentVariant = (name, value) => ['P1', 'P2', 'W-ctx+P2'].includes(value.variant) && CONTEXT_MODELS.includes(value.model);
export const median = values => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b), mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
export function knownRepairs(row, polished, cases) {
  const compact = text => normalize(text).join(' ');
  return cases.filter(c => c.nr === row.reference?.nr).map(c => {
    if (typeof c.id !== 'string' || typeof c.bad !== 'string' || typeof c.good !== 'string') throw new Error('review-cases.json: id, nr, bad, good erforderlich.');
    const bad = new RegExp(c.bad, 'u'), good = new RegExp(c.good, 'u');
    const applicable = bad.test(compact(row.transcripts.a.text));
    const fixed = applicable && good.test(compact(polished.text)) && !bad.test(compact(polished.text));
    return { id: c.id, applicable, fixed };
  });
}
export function semanticAssessment(row, polished, review) {
  const name = `${polished.variant}/${polished.model}`;
  const a = review.entries?.[row.id]?.[name];
  const input = row.transcripts[polished.inputVariant || 'a'];
  if (!a || a.inputHash !== hash(input?.text || '') || a.outputHash !== hash(polished.text) || a.baselineHash !== hash(row.transcripts.a?.text || '')) return null;
  if (!Array.isArray(a.changes) || a.changes.some(c => ['from', 'to', 'reason'].some(k => typeof c[k] !== 'string'))) throw new Error(`semantic-review.json: ungültige Änderungen für ${row.id}/${name}.`);
  return a;
}
export function experimentSummary(rows, cases = [], review = {}) {
  const groups = new Map();
  for (const row of rows) for (const [name, p] of Object.entries(row.polish || {})) {
    if (!experimentVariant(name, p)) continue;
    const g = groups.get(name) || { variant: name, n: 0, idealN: 0, idealWords: 0, idealErrors: 0, freeN: 0, risk: 0, contentWords: 0, knownFixed: 0, knownTotal: 0, reviewedN: 0, meaningChanges: 0, latencies: [] };
    g.n++;
    const score = row.scores?.[name];
    if (score?.idealWer) { g.idealN++; g.idealWords += score.idealWer.words; g.idealErrors += score.idealWer.errors; }
    if (row.reference?.kind === 'frei' && score?.fidelity) { g.freeN++; g.risk += score.fidelity.risk; g.contentWords += score.fidelity.contentWords; }
    for (const c of knownRepairs(row, p, cases)) if (c.applicable) { g.knownTotal++; g.knownFixed += Number(c.fixed); }
    const assessment = semanticAssessment(row, p, review);
    if (assessment) { g.reviewedN++; g.meaningChanges += assessment.changes.length; }
    if (Number.isFinite(p.latencyMs)) g.latencies.push(p.latencyMs);
    groups.set(name, g);
  }
  return [...groups.values()].map(g => ({ ...g, idealWer: g.idealWords ? g.idealErrors / g.idealWords : null,
    riskRate: g.contentWords ? g.risk / g.contentWords : null, newMeaningChanges: g.reviewedN === g.n ? g.meaningChanges : null,
    latencyN: g.latencies.length, latencyMedianMs: median(g.latencies), latencyMaxMs: g.latencies.length ? Math.max(...g.latencies) : null,
  })).sort((a, b) => a.variant.localeCompare(b.variant));
}
export function reviewInputs(rows) {
  return rows.map(row => ({ id: row.id, nr: row.reference?.nr, kind: row.reference?.kind,
    reference: row.reference?.text, ideal: row.reference?.ideal, baseline: row.transcripts.a?.text,
    variants: Object.fromEntries(Object.entries(row.polish || {}).filter(([name, p]) => experimentVariant(name, p)).map(([name, p]) => {
      const raw = row.transcripts[p.inputVariant || 'a']?.text || '';
      const a = words(raw), b = words(p.text);
      const changes = align(normalize(raw), normalize(p.text)).filter(o => o.type !== 'equal').map(o => ({ type: o.type, from: o.a === null ? '' : a[o.a], to: o.b === null ? '' : b[o.b] }));
      return [name, { input: raw, output: p.text, inputHash: hash(raw), baselineHash: hash(row.transcripts.a?.text || ''), outputHash: hash(p.text), changes }];
    })),
  }));
}
