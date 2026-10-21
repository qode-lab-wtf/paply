import test from 'node:test';
import appPrompt from '../../dictation/polish-prompt.js';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { Api, hash } from './api.mjs';
import { CONTEXT_PROMPT, contextMessages, previousDictations, whisperContext, uncertainSegments, chronological, isPolishFresh, baseTranscriptHash } from './context.mjs';
import { experimentSummary, knownRepairs, median } from './evaluation.mjs';
import { fidelity, wer } from './core.mjs';
const row = (id, date, text) => ({ id, meta: { createdAt: date }, transcripts: { a: { text, segments: [] } } });

test('chronology and history use only the last three preceding baseline raw dictations', () => {
  const rows = [row('z', '2026-01-01T10:00:00Z', 'first'), row('x', '2026-01-01T11:00:00Z', 'second'), row('a', '2026-01-01T12:00:00Z', 'third'), row('b', '2026-01-01T13:00:00Z', 'fourth'), row('c', '2026-01-01T14:00:00Z', 'fifth')];
  rows[0].reference = { text: 'SECRET REFERENCE', ideal: 'SECRET IDEAL' };
  rows[0].polish = { any: { text: 'SECRET POLISH' } };
  assert.deepEqual([...rows].reverse().sort(chronological).map(r => r.id), ['z', 'x', 'a', 'b', 'c']);
  assert.deepEqual(previousDictations(rows, 0), []);
  assert.deepEqual(previousDictations(rows, 4).map(r => r.text), ['second', 'third', 'fourth']);
  const messages = contextMessages(rows[1].transcripts.a, previousDictations(rows, 1));
  assert.equal(JSON.stringify(messages).includes('SECRET'), false);
  assert.deepEqual(JSON.parse(messages[1].content).hintergrund_nicht_bearbeiten, ['first']);
  assert.equal(JSON.stringify(messages).includes('third'), false);
});
test('conditioning is bounded, uses recent raw text and never adds vocabulary', () => {
  assert.equal(whisperContext([]), '');
  const history = [{ text: 'old '.repeat(100) }, { text: 'recent '.repeat(40) }];
  const result = whisperContext(history);
  assert.ok(Array.from(result).length <= 200);
  assert.equal(result.includes('old'), false);
  assert.ok(history.map(h => h.text).join('\n').endsWith(result));
});
test('only avg_logprob below -0.5 marks an uncertain segment', () => {
  const t = { text: 'raw', segments: [{ text: 'low', avg_logprob: -.6, start: 3, end: 5 }, { text: 'edge', avg_logprob: -.5 }, { text: 'high', avg_logprob: -.1 }, { text: 'unknown' }] };
  assert.deepEqual(uncertainSegments(t).map(s => s.text), ['low']);
  assert.equal(JSON.parse(contextMessages(t, [])[1].content).unsicher_gehoert[0].start, 3);
});
test('new static prompt has no corpus-specific correction dictionary or examples', () => {
  for (const word of ['Push-to-Torque', 'reflektore', 'Tilescale', 'Codelab', 'Pipo', 'Slicer', 'in dieser Zeit verbringen', 'Paply', 'Schillerstraße', 'Tailscale', 'Vitest']) assert.equal(CONTEXT_PROMPT.includes(word), false);
  assert.match(CONTEXT_PROMPT, /hoher Sicherheit/);
  assert.match(CONTEXT_PROMPT, /Dateinamen/);
});
test('context result invalidates on changed history, confidence, order or conditioned input', () => {
  const rows = [row('a', '', 'old'), row('b', '', 'current')];
  const t = rows[1].transcripts.a;
  const p = { variant: 'P2', inputHash: hash(t.text), promptHash: hash(contextMessages(t, previousDictations(rows, 1))) };
  assert.equal(isPolishFresh(p, rows, 1), true);
  rows[0].transcripts.a.text = 'changed';
  assert.equal(isPolishFresh(p, rows, 1), false);
  rows[0].transcripts.a.text = 'old';
  t.segments = [{ text: 'uncertain', avg_logprob: -.8 }];
  assert.equal(isPolishFresh(p, rows, 1), false);
  const before = baseTranscriptHash(rows[0]);
  rows[0].transcripts.wctx = { text: 'conditioned' };
  assert.equal(baseTranscriptHash(rows[0]), before);
});
test('latency is measured for a real request and retained on cache replay', async t => {
  const data = await mkdtemp(path.join(os.tmpdir(), 'paply-bench-context-'));
  t.after(() => rm(data, { recursive: true, force: true }));
  let requests = 0;
  const api = new Api({ data, config: { groqApiKey: 'dummy' }, fetchImpl: async () => {
    requests++; await new Promise(r => setTimeout(r, 25));
    return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: 'Text.' } }] }));
  } });
  const first = await api.chat('qwen/qwen3.8-27b', [{ role: 'user', content: 'raw' }], { temperature: 0 });
  const replay = await api.chat('qwen/qwen3.8-27b', [{ role: 'user', content: 'raw' }], { temperature: 0 });
  assert.ok(first.latencyMs >= 10);
  assert.equal(replay.latencyMs, first.latencyMs);
  assert.equal(requests, 1);
});
test('known-error metrics are evaluation-only; incomplete or stale semantic review is unknown, not zero', () => {
  const r = row('x', '', 'wrong token'); r.reference = { nr: 1, kind: 'frei', text: 'right token' };
  const p = { variant: 'P2', model: 'qwen/qwen3.8-27b', inputHash: hash('wrong token'), text: 'right token', latencyMs: 20 };
  const name = 'P2/qwen/qwen3.8-27b';
  r.polish = { [name]: p }; r.scores = { [name]: { fidelity: fidelity('right token', p.text), idealWer: wer('right token', p.text) } };
  const cases = [{ id: 'one', nr: 1, bad: '\\bwrong\\b', good: '\\bright\\b' }];
  assert.equal(knownRepairs(r, p, cases)[0].fixed, true);
  assert.equal(knownRepairs(r, { text: 'token' }, cases)[0].fixed, false); // Deletion is not correction.
  let summary = experimentSummary([r], cases, {});
  assert.equal(summary[0].knownFixed, 1); assert.equal(summary[0].newMeaningChanges, null);
  const review = { entries: { x: { [name]: { inputHash: hash('wrong token'), baselineHash: hash('wrong token'), outputHash: hash('right token'), changes: [] } } } };
  assert.equal(experimentSummary([r], cases, review)[0].newMeaningChanges, 0);
  review.entries.x[name].outputHash = 'stale';
  assert.equal(experimentSummary([r], cases, review)[0].newMeaningChanges, null);
  assert.equal(median([30, 10, 20, 40]), 25);
});

test('CLI context ignores vocab/references, uses chronological raw history and invalidates stale results', async t => {
  const { writeFile } = await import('node:fs/promises');
  const { spawnSync } = await import('node:child_process');
  const { fileURLToPath } = await import('node:url');
  const { readJson, writeJson } = await import('./api.mjs');
  const data = await mkdtemp(path.join(os.tmpdir(), 'paply-bench-context-cli-'));
  t.after(() => rm(data, { recursive: true, force: true }));
  const configFile = path.join(data, 'config.json');
  const config = { groqApiKey: 'dummy' }; await writeJson(configFile, config);
  await writeFile(path.join(data, 'vocab.txt'), 'FORBIDDEN_VOCAB');
  await writeJson(path.join(data, 'references.json'), { z: { kind: 'vorgelesen', text: 'FORBIDDEN_REFERENCE', ideal: 'FORBIDDEN_IDEAL' }, a: { kind: 'frei' } });
  const api = new Api({ data, config, sleepImpl: async () => {}, fetchImpl: async (url, opts) => {
    if (url.endsWith('/models')) return new Response(JSON.stringify({ data: ['qwen/qwen3.8-27b', 'openai/gpt-oss-120b', 'whisper-large-v3-turbo'].map(id => ({ id })) }));
    if (url.endsWith('/audio/transcriptions')) {
      assert.equal(String(opts.body.get('prompt')).includes('FORBIDDEN'), false);
      return new Response(JSON.stringify({ text: 'Rohtext.', segments: [{ text: 'Rohtext.', avg_logprob: -.6, start: 0, end: 1 }] }));
    }
    assert.equal(opts.body.includes('FORBIDDEN'), false);
    return new Response(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: 'Rohtext.' } }] }));
  } });
  await api.models();
  const rows = [];
  for (const [id, createdAt] of [['z', '2026-01-01T10:00:00Z'], ['a', '2026-01-01T11:00:00Z']]) {
    const buffer = Buffer.from('audio ' + id), meta = { id, createdAt };
    const audio = { name: id + '.wav', buffer, mime: 'audio/wav' };
    await writeFile(path.join(data, audio.name), buffer); await writeJson(path.join(data, id + '.json'), meta);
    const a = await api.whisper(audio, 'whisper-large-v3-turbo');
    rows.push({ id, meta, file: audio.name, fingerprint: hash(buffer), audio, transcripts: { a }, polish: {}, errors: {} });
  }
  for (let i = 0; i < rows.length; i++) {
    const h = previousDictations(rows, i);
    const wctx = await api.whisper(rows[i].audio, 'whisper-large-v3-turbo', whisperContext(h) || null);
    for (const input of [rows[i].transcripts.a, wctx]) for (const model of ['qwen/qwen3.8-27b', 'openai/gpt-oss-120b']) await api.chat(model, contextMessages(input, h), { temperature: 0 });
  }
  await writeJson(path.join(data, 'results.json'), { schema: 1, recordings: rows.map(({ audio, ...r }) => r), models: {} });
  const cli = fileURLToPath(new URL('./bench.mjs', import.meta.url));
  const invoke = command => spawnSync(process.execPath, [cli, command, '--data', data, '--config', configFile, '--offline'], { encoding: 'utf8' });
  const run = invoke('context'); assert.equal(run.status, 0, run.stdout + run.stderr); assert.match(run.stdout, /API: 0 Aufrufe/);
  let state = await readJson(path.join(data, 'results.json'));
  assert.deepEqual(state.recordings.map(r => r.id), ['z', 'a']);
  assert.equal(state.recordings[0].transcripts.wctx.conditioning, '');
  assert.equal(state.recordings[1].transcripts.wctx.conditioning, 'Rohtext.');
  assert.equal(Object.keys(state.recordings[0].polish).length, 4);
  const p = state.recordings[1].polish['P2/qwen/qwen3.8-27b'];
  assert.deepEqual(JSON.parse(p.messages[1].content).hintergrund_nicht_bearbeiten, ['Rohtext.']);
  assert.equal(JSON.stringify(p.messages).includes('FORBIDDEN'), false);
  state.recordings[0].transcripts.a.text = 'Korrigierter früherer Rohtext.';
  await writeJson(path.join(data, 'results.json'), state);
  assert.equal(invoke('audit').status, 0);
  state = await readJson(path.join(data, 'results.json'));
  assert.equal(state.recordings[1].transcripts.wctx, undefined);
  assert.equal(Object.keys(state.recordings[1].polish).length, 0);
  delete state.recordings[0].transcripts.a;
  await writeJson(path.join(data, 'results.json'), state);
  const missing = invoke('context');
  assert.equal(missing.status, 2, missing.stdout + missing.stderr);
  assert.match(missing.stdout, /API: 0 Aufrufe/);
});


test('P2 uses the exact shared app messages for identical raw inputs', () => {
  const transcript = { text: 'Aktuell.', segments: [{ text: 'Aktuell.', avg_logprob: -0.7, start: 0, end: 1 }] };
  const history = [{ text: 'Alt.' }, { text: 'Neuer.' }];
  assert.deepEqual(contextMessages(transcript, history), appPrompt.buildPolishMessages(transcript.text, {
    history: history.map(item => item.text), segments: transcript.segments,
  }));
  assert.equal(CONTEXT_PROMPT, appPrompt.POLISH_SYSTEM_PROMPT);
});
