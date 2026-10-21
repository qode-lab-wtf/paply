import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { words, normalize, align, wer, consensus, fidelity, removableIndices, profileFor, appPrompts, similarity, STRICT_PROMPT, unanimousDeviations, selfCorrectionCase } from './core.mjs';
import { Api, finalText, readJson, writeJson, acquireLock } from './api.mjs';
import { referenceFor, aggregate, parseArgs, validateJudge } from './bench.mjs';
import { reportHtml } from './report.mjs';

const temp = async t => { const dir = await mkdtemp(path.join(os.tmpdir(), 'paply-bench-unit-')); t.after(() => rm(dir, { recursive: true, force: true })); return dir; };
const response = (data, status = 200, headers = {}) => new Response(JSON.stringify(data), { status, headers });

test('WER handles Unicode, punctuation, substitutions/deletions/insertions and empty input', () => {
  assert.deepEqual(normalize('Ähm, Müller: 42!'), ['ähm', 'müller', '42']);
  assert.deepEqual(words('Next.js / TypeScript'), ['Next', 'js', 'TypeScript']);
  assert.equal(wer('Hallo, WELT!', 'hallo welt').rate, 0);
  const s = wer('a b c d', 'a x c extra more');
  assert.deepEqual([s.substitutions, s.insertions, s.deletions, s.rate], [2, 1, 0, .75]);
  assert.equal(wer('a b c', 'a').deletions, 2);
  assert.equal(wer('', 'x').rate, null);
  assert.ok(Math.abs(similarity('a b c', 'a b x') - 2 / 3) < 1e-12);
  assert.throws(() => align(Array(3000).fill('a'), Array(3000).fill('a')), /zu lang/);
});
test('consensus uses word alignment across insertions and deletions, not raw positions', () => {
  const c = consensus([{ text: 'ich gehe heute nach berlin', segments: [] }, { text: 'ich gehe nach berlin' }, { text: 'ich gehe morgen nach berlin' }]);
  assert.equal(c.text, 'ich gehe heute nach berlin');
  assert.equal(c.uncertain.length, 1);
  assert.deepEqual(c.uncertain[0].candidates, ['heute', '∅', 'morgen']);
  assert.equal(c.uncertain[0].seconds, null);
  const extra = consensus([{ text: 'ich gehe' }, { text: 'ich gehe nach hause' }, { text: 'ich gehe nach hause' }]);
  assert.equal(extra.text, 'ich gehe nach hause');
  assert.equal(extra.uncertain.length, 0);
  const gone = consensus([{ text: 'ich gehe heute' }, { text: 'ich gehe' }, { text: 'ich gehe' }]);
  assert.equal(gone.text, 'ich gehe');
  assert.equal(consensus([{ text: 'hallo' }]).status, 'unavailable');
});
test('uncertainty carries a segment start, missing timing remains explicitly unknown', () => {
  const c = consensus([{ text: 'ich sehe anna', segments: [{ text: 'ich', start: 0 }, { text: 'sehe anna', start: 3.5 }] }, { text: 'ich sehe emma' }, { text: 'ich sehe ella' }]);
  assert.equal(c.uncertain[0].seconds, 3.5);
  assert.match(c.uncertain[0].timing, /Segment/);
});
test('fidelity ignores fillers/adjacent repeated phrases but counts facts and number changes', () => {
  const f = fidelity('Also, ähm, Frau Müller bringt drei drei Unterlagen.', 'Frau Müller bringt vier Unterlagen.');
  assert.equal(f.substituted.length, 1);
  assert.equal(f.omitted.length, 0);
  assert.deepEqual(f.numbers.missing, ['drei']);
  assert.deepEqual(f.numbers.added, ['vier']);
  assert.equal(fidelity('Bitte lösche die Datei nicht.', 'Bitte lösche die Datei.').omitted.includes('nicht'), true);
  assert.equal(removableIndices('Also bleibt es so. Es ist also richtig.').has(6), false);
  assert.equal(removableIndices('Ich gehe. Also weiter.').has(2), true);
  assert.equal(fidelity('Test Test bleibt', 'Test bleibt').risk, 0);
});
test('human reference always wins, and malformed confirmed references fail clearly', () => {
  assert.equal(referenceFor('x', { x: { text: 'Bestätigt', kind: 'frei' } }, { x: { text: 'automatisch', status: 'provisional' } }).source, 'human');
  assert.equal(referenceFor('x', {}, { x: { text: 'automatisch', status: 'provisional' } }).source, 'auto');
  assert.equal(referenceFor('x', {}, { x: { status: 'unavailable' } }), null);
  assert.throws(() => referenceFor('x', { x: { text: '', kind: 'frei' } }, {}));
});
test('P0 loads all current app prompts and system without Electron; profiles resolve', async () => {
  const p = await appPrompts();
  assert.match(p.getPrompt('Originaltext', 'de', 'code'), /TECH-BEGRIFFE KORREKTUR/);
  assert.match(p.getPrompt('Originaltext', 'de', 'plain'), /GESPROCHENE SATZZEICHEN/);
  assert.match(p.getPrompt('Originaltext', 'de', 'meeting'), /Protokoll/);
  assert.match(p.getPrompt('Originaltext', 'de', 'custom', { name: 'Test' }), /Test/);
  assert.equal(p.system, 'Du bist ein Transkriptions-Polierer. Gib NUR den korrigierten Text zurück. Keine Kommentare, keine Erklärungen.');
  assert.equal(profileFor({ activeProfile: 'dictation' }, {}).flavor, 'plain');
  assert.equal(profileFor({ activeProfile: 'coding' }, { profiles: { coding: { polishFlavor: 'meeting' } } }).flavor, 'meeting');
});
test('leaderboard uses micro-WER, separates reference origins and excludes incomplete coverage', () => {
  const rows = [{ id: '1', reference: { source: 'human' }, scores: { a: { type: 'transcribe', wer: { words: 10, errors: 1 } }, b: { type: 'transcribe', wer: { words: 10, errors: 0 } } } }, { id: '2', reference: { source: 'human' }, scores: { a: { type: 'transcribe', wer: { words: 90, errors: 9 } } } }, { id: '3', reference: { source: 'auto' }, scores: { a: { type: 'transcribe', wer: { words: 20, errors: 10 } } } }];
  const s = aggregate(rows);
  assert.equal(s[0].wer, .1);
  assert.equal(s[0].best, true);
  assert.equal(s[1].best, undefined);
  assert.equal(s[2].wer, .5);
});
test('reasoning and truncated outputs are never accepted as polished text', () => {
  const wrap = (text, finish_reason = 'stop') => ({ choices: [{ finish_reason, message: { content: text, reasoning: 'private analysis' } }] });
  assert.equal(finalText(wrap('<think>analysis</think>Finaler Text.')), 'Finaler Text.');
  assert.throws(() => finalText(wrap('Abgeschnitten', 'length')), /abgeschnitten/);
  assert.throws(() => finalText(wrap('<think>unfinished')), /Reasoning/);
});
test('successful request cache prevents any network activity, even offline with no key', async t => {
  const data = await temp(t); let calls = 0;
  const api = new Api({ data, config: { groqApiKey: 'secret-for-test' }, fetchImpl: async () => { calls++; return response({ data: [{ id: 'test' }] }); } });
  assert.deepEqual(await api.models(), ['test']);
  assert.deepEqual(await api.models(), ['test']);
  const offline = new Api({ data, config: {}, offline: true, fetchImpl: () => assert.fail('network') });
  assert.deepEqual(await offline.models(), ['test']);
  assert.equal(calls, 1);
});
test('429 waits per Retry-After; exhausted and negative requests are cached', async t => {
  const data = await temp(t); let now = 1_000_000, calls = 0; const waits = [];
  const api = new Api({ data, config: { groqApiKey: 'secret' }, now: () => now, sleepImpl: async ms => { waits.push(ms); now += ms; }, fetchImpl: async () => ++calls < 2 ? response({}, 429, { 'retry-after': '20' }) : response({ data: [{ id: 'ok' }] }) });
  assert.deepEqual(await api.models(), ['ok']); assert.equal(calls, 2); assert.deepEqual(waits, [20000]);
  const bad = new Api({ data, config: { geminiApiKey: 'secret' }, now: () => now, fetchImpl: async () => { calls++; return response({}, 404); } });
  await assert.rejects(bad.request('Gemini', 'not-found', {}), /404/);
  await assert.rejects(bad.request('Gemini', 'not-found', {}), /Fehlercache/);
  assert.equal(calls, 3);
});
test('daily quota aborts without waiting an hour, trying each distinct fallback model only once', async t => {
  const data = await temp(t); let calls = 0;
  const api = new Api({ data, config: { geminiApiKey: 'secret' }, sleepImpl: async ms => assert.ok(ms <= 6500, 'only short pacing, no quota wait'), fetchImpl: async () => { calls++; return response({ error: { message: 'per day quota limit: 0' } }, 429); } });
  await assert.rejects(api.gemini({ mime: 'audio/wav', buffer: Buffer.from('wav') }), /429/);
  assert.equal(calls, 3);
});
test('invalid successful output is cached as a failure to prevent repeated costs', async t => {
  const data = await temp(t); let calls = 0;
  const api = new Api({ data, config: { groqApiKey: 'secret' }, fetchImpl: async () => { calls++; return response({}); } });
  await assert.rejects(api.models(), /ungültig/);
  await assert.rejects(api.models(), /Fehlercache/);
  assert.equal(calls, 1);
});
test('lock protects a data folder from concurrent benchmark processes', async t => {
  const data = await temp(t), file = path.join(data, '.lock');
  const unlock = await acquireLock(file);
  await assert.rejects(acquireLock(file), /bereits/);
  await unlock();
  const release = await acquireLock(file); await release();
});
test('judge schema, CLI options and escaping are strict', () => {
  assert.throws(() => parseArgs(['all', '--models', 'paid-other-model']));
  assert.throws(() => parseArgs(['all', '--data']));
  assert.throws(() => parseArgs(['all', '--limit', '0']));
  assert.throws(() => validateJudge('{"changes":[],"meaning":6,"sentences":1}'));
  assert.equal(validateJudge('{"changes":[],"meaning":5,"sentences":4}').meaning, 5);
  const html = reportHtml({ recordings: [{ id: '<script>danger</script>', file: 'a " x.wav', meta: {}, reference: { source: 'human', text: '<script>evil</script>' }, transcripts: { a: { text: '<script>evil</script>', model: 'm' } }, polish: {} }], summary: [] });
  assert.equal(html.includes('<script>evil</script>'), false);
  assert.equal(html.includes('<script>danger</script>'), false);
  assert.match(html, /a%20%22%20x.wav/);
  const deletion = reportHtml({ recordings: [{ id: 'x', file: 'x.wav', meta: {}, reference: { source: 'human', text: 'Wir gehen jetzt.' }, transcripts: { a: { text: 'Wir jetzt.', model: 'm' } }, polish: {} }], summary: [] });
  assert.match(deletion, /Wir <del[^>]*>gehen<\/del>/);
});


test('CLI pipeline works fully offline, preserves scores on replay and rejects stale references', async t => {
  const data = await temp(t);
  const config = { groqApiKey: 'dummy-only-in-temp', geminiApiKey: 'dummy-only-in-temp' };
  const configFile = path.join(data, 'config.json');
  await writeJson(configFile, config);
  await writeJson(path.join(data, 'references.json'), { x: { text: 'Wir sehen Anna.', ideal: 'Wir sehen Anna.', kind: 'vorgelesen' }, y: { kind: 'frei' } });
  await writeFile(path.join(data, 'vocab.txt'), 'Paply');
  await writeJson(path.join(data, 'scripts.json'), [{ nr: 1, text: 'Wir sehen Anna.' }]);
  const models = ['whisper-large-v3-turbo', 'whisper-large-v3', 'openai/gpt-oss-120b', 'openai/gpt-oss-20b', 'qwen/qwen3.8-27b'];
  const api = new Api({ data, config, sleepImpl: async () => {}, fetchImpl: async (url, opts) => {
    if (url.endsWith('/models')) return response({ data: models.map(id => ({ id })) });
    if (url.endsWith('/audio/transcriptions')) {
      const text = opts.body.get('model') === 'whisper-large-v3' ? 'Wir sehen Emma.' : 'Wir sehen Anna.';
      return response({ text, segments: [{ text, start: 2, end: 4 }] });
    }
    if (url.includes(':generateContent')) return response({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: 'Wir sehen Ella.' }] } }] });
    return response({ choices: [{ finish_reason: 'stop', message: { content: 'Wir sehen Anna.' } }] });
  } });
  await api.models();
  for (const id of ['x', 'y']) {
    const audio = { name: id + '.wav', buffer: Buffer.from('fake audio ' + id), mime: 'audio/wav' };
    await writeFile(path.join(data, audio.name), audio.buffer);
    await writeJson(path.join(data, id + '.json'), { id, activeProfile: 'coding', language: 'de' });
    await api.whisper(audio, 'whisper-large-v3-turbo');
    await api.whisper(audio, 'whisper-large-v3');
    await api.whisper(audio, 'whisper-large-v3-turbo', 'Paply');
    await api.gemini(audio);
  }
  const prompts = await appPrompts();
  for (const variant of ['P0', 'P1']) for (const model of models.slice(2)) {
    const messages = [{ role: 'system', content: variant === 'P0' ? prompts.system : 'Du polierst Diktate minimal und wortgetreu. Ausgabe nur des Textes.' }, { role: 'user', content: variant === 'P0' ? prompts.getPrompt('Wir sehen Anna.', 'de', 'code', null) : STRICT_PROMPT + 'Wir sehen Anna.' }];
    await api.chat(model, messages, { temperature: variant === 'P1' ? 0 : undefined });
  }
  const cli = fileURLToPath(new URL('./bench.mjs', import.meta.url));
  const invoke = command => spawnSync(process.execPath, [cli, command, '--data', data, '--config', configFile, '--offline'], { encoding: 'utf8' });
  const all = invoke('all');
  assert.equal(all.status, 0, all.stdout + all.stderr);
  assert.match(all.stdout, /API: 0 Aufrufe/);
  let state = await readJson(path.join(data, 'results.json'));
  assert.equal(state.recordings[0].scores.a.wer.rate, 0);
  assert.equal(state.recordings[0].scores['P0/openai/gpt-oss-120b'].idealWer.rate, 0);
  assert.equal(state.recordings[1].reference.source, 'auto');
  assert.equal(state.recordings[1].reference.uncertain[0].seconds, 2);
  assert.equal(Object.keys(state.recordings[0].polish).length, 6);
  assert.equal(Object.keys(state.recordings[0].scores).length, 10);
  assert.match(await readFile(path.join(data, 'bericht.html'), 'utf8'), /data-time="2"/);
  assert.equal(invoke('match').status, 0);
  assert.equal((await readJson(path.join(data, 'references.suggested.json'))).x.ideal, 'Wir sehen Anna.');
  assert.equal((await readJson(path.join(data, 'references.json'))).y.text, undefined);
  const confirmed = await readJson(path.join(data, 'references.json'));
  await writeJson(path.join(data, 'references.json'), { x: confirmed.x });
  assert.equal(invoke('match').status, 0);
  assert.equal((await readJson(path.join(data, 'references.suggested.json'))).y.kind, 'vorgelesen');
  assert.equal((await readJson(path.join(data, 'matches.json'))).find(m => m.id === 'y').candidates[0].similarity, 1);
  await writeJson(path.join(data, 'scripts.json'), [{ nr: 2, text: 'Andere völlig verschiedene Wörter in dieser Vorlage.' }]);
  assert.equal(invoke('match').status, 0);
  assert.equal((await readJson(path.join(data, 'references.suggested.json'))).y.kind, 'frei');
  await writeJson(path.join(data, 'references.json'), confirmed);
  assert.equal(invoke('transcribe').status, 0);
  const report = invoke('report');
  assert.equal(report.status, 0, report.stdout + report.stderr);
  state = await readJson(path.join(data, 'results.json'));
  assert.equal(state.recordings[0].scores.a.wer.rate, 0);
  assert.equal(state.recordings[0].scores['P0/openai/gpt-oss-120b'].idealWer.rate, 0);
  await writeJson(path.join(data, 'references.json'), { x: { text: 'Anderer Wortlaut.', kind: 'vorgelesen' } });
  const stale = invoke('report');
  assert.equal(stale.status, 1);
  assert.match(stale.stderr, /veraltet/);
  assert.equal(invoke('score').status, 0);
  assert.equal(invoke('report').status, 0);
});


test('Gemini replays a cached fallback offline after the primary error cache expired', async t => {
  const data = await temp(t); let calls = 0, now = 1_000_000;
  const audio = { mime: 'audio/wav', buffer: Buffer.from('audio') };
  const online = new Api({ data, config: { geminiApiKey: 'dummy' }, now: () => now, sleepImpl: async ms => { now += ms; }, fetchImpl: async url => {
    calls++;
    return url.includes('3.6') ? response({}, 404) : response({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: 'Hallo.' }] } }] });
  } });
  assert.equal((await online.gemini(audio)).model, 'gemini-3.5-flash');
  now += 2 * 86_400_000;
  const offline = new Api({ data, config: {}, offline: true, now: () => now, fetchImpl: () => assert.fail('network') });
  assert.equal((await offline.gemini(audio)).text, 'Hallo.');
  assert.equal((await online.gemini(audio)).text, 'Hallo.');
  assert.equal(calls, 2);
});


test('ideal WER drives polishing rank even when reference fidelity favors another variant', () => {
  const f = risk => ({ ...fidelity('Wir gehen nach Hause.', 'Wir gehen nach Hause.'), risk });
  const rows = [{ id: 'x', reference: { source: 'human', ideal: 'Wir gehen nach Hause.' }, scores: {
    P0: { type: 'polish', fidelity: f(0), idealWer: { words: 4, errors: 2 } },
    P1: { type: 'polish', fidelity: f(3), idealWer: { words: 4, errors: 0 } },
  } }];
  const groups = aggregate(rows);
  assert.equal(groups[0].idealWer, .5);
  assert.equal(groups[0].best, false);
  assert.equal(groups[1].best, true);
  assert.equal(referenceFor('free', { free: { kind: 'frei' } }, {}), null);
});

test('unanimous script deviations include deleted self-corrections and shared additions, not 2/3 votes', () => {
  const reference = 'Wir treffen uns Dienstag nein Moment Mittwoch.';
  const transcripts = [1, 2, 3].map(() => ({ text: 'Wir treffen uns Mittwoch.', segments: [{ text: 'Wir treffen uns Mittwoch.', start: 4 }] }));
  const deviations = unanimousDeviations(reference, transcripts);
  assert.deepEqual(deviations.map(d => d.from), ['dienstag nein moment']);
  assert.equal(deviations[0].to, '');
  assert.equal(deviations[0].seconds, 4);
  assert.equal(unanimousDeviations('Wir gehen.', [{ text: 'Wir gehen heute.' }, { text: 'Wir gehen heute.' }, { text: 'Wir gehen heute.' }])[0].to, 'heute');
  assert.equal(unanimousDeviations('Wir gehen.', [{ text: 'Wir bleiben.' }, { text: 'Wir bleiben.' }, { text: 'Wir gehen.' }]).length, 0);
  assert.equal(unanimousDeviations('Wir gehen.', [undefined]).length, 0);
  const special = selfCorrectionCase({ nr: 5, text: reference }, transcripts[0].text);
  assert.equal(special.turboAlreadyResolved, true);
  assert.match(special.note, /eindeutig/);
});
