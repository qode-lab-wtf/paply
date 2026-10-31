import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRepo } from './repo';
import { createCommands } from './commands';
import { blankBoard, node } from './contracts';
import { createCapture } from './capture';
import { createSettings, defaults } from './settings';
import { createLedger } from './ledger';
import { createQueue, levels, audioChunks } from './queue';
import { createGroq, retryAfter } from './groq';
import { splitSentences, chunks, context } from './context';
let root, repo, commands;
beforeEach(() => { root = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-notes-unit-')); repo = createRepo(root); commands = createCommands(repo); });
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); fs.rmSync(root, { force: true, recursive: true }); });
const textOp = (text = 'Nicht vergessen.') => ({ type: 'create', node: { kind: 'note', text, position: { x: 10, y: 20 } } });
const single = () => Object.values(repo.current().nodes)[0];
function fixturePlan(sentences = [{ id: 's1', text: 'Ich möchte keine rote Lampe.' }]) {
  const ctx = { topics: [], existing: [], sentences };
  const plan = { title: 'Lampe', clean_text: sentences.map(s => s.text).join(' '), topic: { choice: 'new', id: null, new_name: 'Zuhause', symbol: 'home' }, tasks: [], related: [] };
  return { ctx, plan };
}
function rawFor(sentences) {
  const raw = node({ kind: 'note', text: sentences.map(s => s.text).join(' ') }); raw.id = 'raw_s'; raw.owner = 'system'; raw.sourceId = 's'; raw.sentenceIds = sentences.map(s => s.id);
  commands.commit(b => { b.nodes[raw.id] = raw; raw.sentenceIds.forEach(sid => { b.claims[sid] = raw.id; }); }, false); return raw;
}
describe('durable store and commands', () => {
  it('persists canonical content and viewport across a fresh process object', () => { commands.apply([textOp()]); commands.viewport({ x: 90, y: -22, zoom: .7 }); const loaded = createRepo(root).snapshot(); expect(Object.values(loaded.nodes)[0].text).toBe('Nicht vergessen.'); expect(loaded.viewport).toEqual({ x: 90, y: -22, zoom: .7 }); });
  it('recovers a torn main file from the last valid generation', () => { commands.apply([textOp('erste')]); commands.apply([textOp('zweite')]); fs.writeFileSync(path.join(root, 'board.json'), '{torn'); const loaded = createRepo(root); expect(loaded.recovered).toBe(true); expect(Object.values(loaded.current().nodes)).toHaveLength(1); expect(Object.values(loaded.current().nodes)[0].text).toBe('erste'); });
  it('refuses to silently reset an entirely damaged store', () => { fs.writeFileSync(path.join(root, 'board.json'), 'invalid'); expect(() => createRepo(root)).toThrow('beschädigt'); });
  it('also recovers parseable JSON with malformed node data', () => {
    commands.apply([textOp('erhalten')]); commands.apply([{ type: 'update', id: single().id, patch: { label: 'Letzter Stand' } }]);
    const damaged = repo.snapshot(); Object.values(damaged.nodes)[0].attachments = null;
    fs.writeFileSync(path.join(root, 'board.json'), JSON.stringify(damaged));
    const recovered = createRepo(root); expect(recovered.recovered).toBe(true); expect(Object.values(recovered.current().nodes)[0].text).toBe('erhalten');
  });
  it('keeps memory and old disk state when rename fails', () => { commands.apply([textOp('first')]); const before = repo.snapshot(); vi.spyOn(fs, 'renameSync').mockImplementation(() => { throw Object.assign(new Error('disk busy'), { code: 'EPERM' }); }); expect(() => commands.apply([textOp('second')])).toThrow(); expect(repo.snapshot()).toEqual(before); expect(JSON.parse(fs.readFileSync(path.join(root, 'board.json')))).toEqual(before); });
  it('deletes incident edges and restores edges plus source claims on undo', () => { const { ctx } = fixturePlan(); const a = rawFor(ctx.sentences); commands.apply([textOp('other')]); const other = Object.values(repo.current().nodes).find(n => n.id !== a.id); commands.apply([{ type: 'edge', source: a.id, target: other.id }]); commands.apply([{ type: 'delete', id: a.id }]); expect(repo.current().claims.s1).toEqual({ tomb: true }); expect(Object.keys(repo.current().edges)).toHaveLength(0); commands.undo(); expect(repo.current().nodes[a.id]).toBeTruthy(); expect(repo.current().claims.s1).toBe(a.id); expect(Object.keys(repo.current().edges)).toHaveLength(1); commands.redo(); expect(repo.current().nodes[a.id]).toBeUndefined(); });
  it('undo does not remove an unrelated AI commit', () => { commands.apply([textOp('user')]); commands.commit(b => { const n = node({ kind: 'note', text: 'AI' }); b.nodes[n.id] = n; }, false); commands.undo(); expect(Object.values(repo.current().nodes).map(n => n.text)).toEqual(['AI']); });
  it('rejects stale edit revisions and prevents partial batch writes', () => { commands.apply([textOp()]); const n = single(); const before = repo.snapshot(); expect(() => commands.apply([{ type: 'update', id: n.id, rev: 0, patch: { text: 'stale' } }])).toThrow('geändert'); expect(() => commands.apply([textOp('partial'), { type: 'update', id: n.id, patch: { sourceId: 'fake' } }])).toThrow(); expect(repo.snapshot()).toEqual(before); });
  it('does not move placed nodes in a repeated placement command', () => { commands.apply([textOp()]); const n = single(); commands.place([{ id: n.id, position: { x: 999, y: 888 } }]); expect(single().position).toEqual({ x: 10, y: 20 }); });
  it('independent copies have no source claim ownership', () => { const { ctx } = fixturePlan(); const a = rawFor(ctx.sentences); commands.apply([{ type: 'duplicate', id: a.id }]); const copy = Object.values(repo.current().nodes).find(n => n.id !== a.id); expect(copy.sentenceIds).toEqual([]); expect(copy.sourceId).toBeNull(); expect(repo.current().claims.s1).toBe(a.id); });
  it('keeps AI text provenance when pinning its geometry', () => { const raw = rawFor([{ id: 's1', text: 'Ein Gedanke.' }]); commands.commit(b => { b.nodes[raw.id].owner = 'ai'; b.nodes[raw.id].kind = 'text'; }, false); commands.apply([{ type: 'update', id: raw.id, patch: { position: { x: 1, y: 2 }, width: 420 } }]); expect(single()).toMatchObject({ owner: 'ai', pinned: true, kind: 'text' }); });
  it('connecting an AI note also pins it without changing its text provenance', () => { const raw = rawFor([{ id: 's1', text: 'Ein Gedanke.' }]); commands.commit(b => { b.nodes[raw.id].owner = 'ai'; }, false); commands.apply([textOp('Ziel')]); const target = Object.keys(repo.current().nodes).find(id => id !== raw.id); commands.apply([{ type: 'edge', source: raw.id, target }]); expect(repo.current().nodes[raw.id]).toMatchObject({ owner: 'ai', pinned: true }); });
  it('deleting a free edge removes orphan endpoints and undo restores the whole line', () => { commands.apply([{ type: 'line', from: { x: 0, y: 0 }, to: { x: 100, y: 100 } }]); commands.apply([{ type: 'deleteEdge', id: Object.keys(repo.current().edges)[0] }]); expect(Object.keys(repo.current().nodes)).toHaveLength(0); commands.undo(); expect(Object.keys(repo.current().nodes)).toHaveLength(2); expect(Object.keys(repo.current().edges)).toHaveLength(1); });
  it.each(['toString','valueOf','__defineGetter__'])('rejects inherited object IDs: %s', id => { expect(() => commands.apply([{ type: 'edge', source: id, target: id }])).toThrow(); expect(Object.keys(repo.current().edges)).toHaveLength(0); });
});
describe('quota and HTTP failures', () => {
  it('reserves before use, survives restart and rolls off after 24 hours', () => { let now = 100000000; const ledger = createLedger(repo, () => ({ dailyTokens: 8000, dailyAudioMinutes: 60 }), () => now); const id = ledger.reserve('20b', 6000); expect(() => ledger.reserve('20b', 2000)).toThrow('Pause'); ledger.settle(id, 3000); now += 61000; ledger.reserve('20b', 5000); const recovered = createLedger(repo, () => ({ dailyTokens: 8000, dailyAudioMinutes: 60 }), () => now); expect(() => recovered.reserve('120b', 1)).toThrow('Budget'); now += 86400001; expect(recovered.reserve('20b', 3000)).toBeTruthy(); });
  it('separates audio seconds from text tokens', () => { const ledger = createLedger(repo, () => ({ dailyTokens: 10000, dailyAudioMinutes: 1 })); ledger.reserve('whisper', 50, 'audio'); expect(() => ledger.reserve('whisper', 20, 'audio')).toThrow('Budget'); expect(ledger.reserve('20b', 5000)).toBeTruthy(); });
  it('does not call fetch without a key', async () => { const fetchImpl = vi.fn(); const groq = createGroq({ getKey: () => '', ledger: { reserve: vi.fn() }, fetchImpl }); await expect(groq.plan({}, false)).rejects.toMatchObject({ kind: 'key' }); expect(fetchImpl).not.toHaveBeenCalled(); });
  it('preserves retry-after and does not return an echoed API body', async () => { const groq = createGroq({ getKey: () => 'fake', ledger: { reserve: () => 'r', settle: vi.fn() }, fetchImpl: async () => new Response('sensitive body', { status: 429, headers: { 'retry-after': '74' } }) }); await expect(groq.plan({}, false)).rejects.toMatchObject({ kind: 'rate', retryMs: 900000 }); });
  it('rejects truncated strict output instead of applying it', async () => { const groq = createGroq({ getKey: () => 'fake', ledger: { reserve: () => 'r', settle: vi.fn() }, fetchImpl: async () => new Response(JSON.stringify({ choices: [{ finish_reason: 'length', message: { content: '{}' } }], usage: { total_tokens: 19 } })) }); await expect(groq.plan({}, false)).rejects.toMatchObject({ kind: 'plan' }); });
  it('supports date-form retry-after without spinning on invalid headers', () => { expect(retryAfter('bad', 0)).toBe(30000); expect(retryAfter('Thu, 01 Jan 1970 00:01:00 GMT', 0)).toBe(60000); });
  it('fails a request larger than its daily budget without an infinite retry date', () => { const ledger = createLedger(repo, () => ({ dailyTokens: 5000, dailyAudioMinutes: 1 })); expect(() => ledger.reserve('120b', 6000)).toThrow('zu klein'); try { ledger.reserve('whisper', 120, 'audio'); } catch (e) { expect(e.kind).toBe('budget_small'); expect(e.retryMs).toBeUndefined(); } expect(ledger.summary().requests).toBe(0); });
});
describe('hotkey replacement', () => {
  it('never changes the system login item from an isolated packaged test app', async () => {
    const source = fs.readFileSync(path.join(__dirname, '../electron-main.js'), 'utf8');
    const start = source.indexOf('async function updateAutoLaunch()'), end = source.indexOf('// ===', start);
    const disable = vi.fn(), getAutoLauncher = vi.fn(() => ({ disable, enable: vi.fn() }));
    const env = { PAPLY_USER_DATA: '/isolated/test' }, scope = vm.createContext({ process: { env }, app: { isPackaged: true }, getAutoLauncher, getStore: () => ({ get: () => false }), console });
    vm.runInContext(source.slice(start, end), scope); await scope.updateAutoLaunch(); expect(getAutoLauncher).not.toHaveBeenCalled();
    delete env.PAPLY_USER_DATA; await scope.updateAutoLaunch(); expect(disable).toHaveBeenCalledOnce();
  });
  function settingsFixture(platform = 'darwin') { const registrations = new Map(); const data = {}; const globalShortcut = { register: vi.fn((key, fn) => { if (registrations.has(key) || key === 'Command+Q') return false; registrations.set(key, fn); return true; }), unregister: vi.fn(key => registrations.delete(key)) }; const s = createSettings({ loadKeyLabels: () => ({}), store: { get: (k, d) => data[k] ?? d, set: (k, v) => { data[k] = v; } }, globalShortcut, otherShortcuts: () => ['Command+X'], capture: vi.fn(), open: vi.fn(), platform }); s.start(); return { s, registrations, globalShortcut }; }
  it('keeps both old keys when the second replacement fails', () => { const { s, registrations } = settingsFixture(); expect(() => s.set({ captureHotkey: 'Command+U', openHotkey: 'Command+Q' })).toThrow('belegt'); expect([...registrations.keys()]).toEqual(['Command+Y','Command+Alt+Y']); expect(s.get().captureHotkey).toBe('Command+Y'); });
  it('catches aliases and cross-collisions with dictation', () => { const { s } = settingsFixture(); expect(() => s.set({ captureHotkey: 'Cmd+X' })).toThrow('bereits'); expect(() => s.set({ openHotkey: 'Cmd+Y' })).toThrow('unterschiedliche'); });
  it('can atomically swap roles without dropping a registration', () => { const { s, registrations } = settingsFixture(); s.set({ openHotkey: 'Command+Y', captureHotkey: 'Command+Alt+Y' }); expect(registrations.size).toBe(2); s.set({ enabled: false }); expect(registrations.size).toBe(0); });
});
describe('durable PCM, epochs and recovery', () => {
  function fixture(overrides = {}) { const send = vi.fn(); let dictating = false; const c = createCapture({ repo, commands, getSettings: () => ({ enabled: true, screenContext: false, hasGroqKey: false }), isDictating: () => dictating, isMeetingActive: () => false, show: async () => {}, send, hide: vi.fn(), screenshot: vi.fn(), ...overrides }); return { c, send, dictating: value => { dictating = value; c.dictationState(value); } }; }
  it('persists every accepted chunk once and refuses missing sequence numbers', async () => { const { c } = fixture(); await c.start(); const id = c.status().entryId, bytes = new Int16Array(8000).fill(123).buffer; expect(c.accept({ entryId: id, epoch: 1, seq: 1, bytes }).accepted).toBe(true); c.accept({ entryId: id, epoch: 1, seq: 1, bytes }); expect(() => c.accept({ entryId: id, epoch: 1, seq: 3, bytes })).toThrow('fehlt'); c.shutdown(); expect(fs.statSync(path.join(repo.sourcePath(id), 'rec.pcm')).size).toBe(16000); expect(repo.entry(id).state).toBe('captured'); });
  it('drops dictation packets synchronously and all packets from older epochs', async () => { vi.useFakeTimers(); const { c, send, dictating } = fixture(); await c.start(); const id = c.status().entryId, bytes = new Int16Array(8000).fill(123).buffer; c.accept({ entryId: id, epoch: 1, seq: 1, bytes }); dictating(true); expect(c.accept({ entryId: id, epoch: 1, seq: 2, bytes }).accepted).toBe(false); dictating(false); vi.advanceTimersByTime(350); const resumed = send.mock.calls.map(c => c[0]).find(s => s.phase === 'resume'); expect(resumed.epoch).toBeGreaterThan(1); expect(c.accept({ entryId: id, epoch: 1, seq: 3, bytes }).accepted).toBe(false); expect(c.accept({ entryId: id, epoch: resumed.epoch, seq: 1, bytes }).accepted).toBe(true); c.shutdown(); expect(repo.entry(id).durationMs).toBe(1000); expect(repo.entry(id).droppedPackets).toBe(2); });
  it('refuses starting while dictation is active without creating an entry', async () => { const { c } = fixture({ isDictating: () => true }); await c.start(); expect(c.status().active).toBe(false); expect(repo.entries()).toHaveLength(0); });
  it('meeting interruption closes the audio sink and preserves accepted PCM', async () => { const { c } = fixture(); await c.start(); const id = c.status().entryId; c.accept({ entryId: id, epoch: 1, seq: 1, bytes: new Int16Array(1000).buffer }); c.meetingStarted(); expect(c.status().active).toBe(false); expect(repo.entry(id).state).toBe('captured'); });
  it('releases the capture lease after a failed initial board write', async () => {
    const { c, send } = fixture(); const fail = vi.spyOn(commands, 'commit').mockImplementationOnce(() => { throw new Error('disk full'); });
    await c.start(); expect(c.status().active).toBe(false); expect(send.mock.calls.some(([s]) => s.phase === 'abort')).toBe(true);
    fail.mockRestore(); await c.start(); expect(c.status().active).toBe(true); c.shutdown();
  });
  it('closes the microphone and recovers PCM when the final metadata write fails', async () => {
    const { c, send } = fixture(); await c.start(); const id = c.status().entryId;
    c.accept({ entryId: id, epoch: 1, seq: 1, bytes: new Int16Array(8000).buffer });
    const fail = vi.spyOn(repo, 'saveEntry').mockImplementationOnce(() => { throw new Error('disk full'); });
    expect(() => c.fail('Speicher voll')).not.toThrow(); expect(c.status().active).toBe(false); expect(repo.entry(id).state).toBe('recording');
    expect(send.mock.calls.some(([s]) => s.phase === 'error')).toBe(true);
    fail.mockRestore(); c.recover(); expect(repo.entry(id)).toMatchObject({ state: 'captured', durationMs: 500 });
  });
  it('repairs a torn PCM byte after process restart', () => { repo.saveEntry({ id: 's_crash', state: 'recording', durationMs: 0 }); fs.writeFileSync(path.join(repo.sourcePath('s_crash'), 'rec.pcm'), Buffer.alloc(32001)); const { c } = fixture(); c.recover(); expect(fs.statSync(path.join(repo.sourcePath('s_crash'), 'rec.pcm')).size).toBe(32000); expect(repo.entry('s_crash')).toMatchObject({ state: 'captured', durationMs: 1000 }); });
  it('resolves an empty recorder placeholder instead of leaving a spinner', async () => { const { c } = fixture(); await c.start(); const id = c.status().entryId; c.stop(); c.flushed({ entryId: id, epoch: 1 }); expect(single()).toMatchObject({ pending: false, label: 'Kein Ton aufgenommen' }); });
  it('retains an opted-in start screenshot while transcription is pending after restart', () => { repo.saveEntry({ id: 's_screen', state: 'captured' }); const file = path.join(root, 'tmp', 's_screen.png'); fs.writeFileSync(file, 'synthetic bytes'); const { c } = fixture(); c.recover(); expect(fs.existsSync(file)).toBe(true); repo.saveTranscript('s_screen', { text: 'Fertig' }); c.recover(); expect(fs.existsSync(file)).toBe(false); });
  it('matches exact output duration across arbitrary worklet blocks at 44.1/48 kHz and 8 kHz', () => {
    const source = fs.readFileSync(path.join(__dirname, '../src/apps/notes-pill/pcm-worklet.js'), 'utf8');
    for (const rate of [44100,48000,8000,16000]) {
      let Processor; const messages = [];
      class Base { constructor() { this.port = { postMessage: v => messages.push(v) }; } }
      vm.runInNewContext(source, { AudioWorkletProcessor: Base, sampleRate: rate, Int16Array, Math, registerProcessor: (_n, C) => { Processor = C; } });
      const p = new Processor(); for (let i = 0; i < rate; i += 128) p.process([[new Float32Array(Math.min(128, rate-i)).fill(.5)]]); p.port.onmessage({ data: 'flush' });
      const chunks = messages.filter(m => m.type === 'pcm'); expect(chunks.reduce((v, c) => v + c.bytes.byteLength, 0)).toBe(32000); expect(new Int16Array(chunks[0].bytes)[0]).toBe(16383);
    }
  });
});
describe('queue boundaries', () => {
  it('passes recorded languages and UI language through to title validation', async () => {
    const text = 'Demain je vais retrouver Sophie au café.';
    const groq = { plan: vi.fn(async ctx => ({ ...fixturePlan(ctx.sentences).plan, title: 'Treffen mit Sophie', topic: { choice: 'none' } })) };
    const q = fixture(groq, { getUILanguage: () => 'de-DE' });
    const sentences = splitSentences(text, 's');
    rawFor(sentences);
    repo.saveEntry({ id: 's', kind: 'voice', createdAt: Date.now(), state: 'transcribed', partsDone: 0 });
    repo.saveTranscript('s', { text, sentences, languages: ['fr'] });
    for (let i = 0; i < 4; i++) await q.tick();
    expect(groq.plan.mock.calls[0][0]).toMatchObject({ spoken_languages: ['fr'], ui_language: 'de-DE' });
    expect(single().label).toBe('Demain je vais retrouver Sophie au');
    q.stop();
  });
  function fixture(groq, extra = {}) { return createQueue({ repo, commands, groq, ...extra, assets: { pending: () => [] }, getSettings: () => defaults(), getKey: () => 'fake', onChange: vi.fn() }); }
  it.each([{ position: { x: 40, y: 80 } }, { width: 480, height: 240 }, { text: 'Mein Zusatz' }])('fills a touched pending placeholder and keeps all later parts: %j', async patch => {
    const sentences = splitSentences(Array.from({ length: 60 }, (_, i) => `Gedanke ${i} bleibt erhalten.`).join(' '), 's'); const raw = rawFor([]);
    commands.commit(b => { b.nodes[raw.id].pending = true; }, false); commands.apply([{ type: 'update', id: raw.id, patch }]);
    repo.saveEntry({ id: 's', kind: 'voice', createdAt: Date.now(), state: 'transcribed', partsDone: 0 }); repo.saveTranscript('s', { text: sentences.map(s => s.text).join(' '), sentences });
    const q = fixture({ plan: vi.fn() }); await q.tick(); const notes = Object.values(repo.current().nodes);
    expect(notes).toHaveLength(3); expect(notes.flatMap(n => n.sentenceIds)).toHaveLength(60); expect(repo.current().nodes[raw.id].text).toContain('Gedanke 0 bleibt erhalten.'); expect(repo.current().nodes[raw.id].pending).toBe(false);
    if (patch.text) expect(repo.current().nodes[raw.id].text).toContain('Mein Zusatz'); else expect(repo.current().nodes[raw.id]).toMatchObject(patch); q.stop();
  });
  it('shows fallback honestly and explicitly retries the untouched raw note', async () => {
    const groq = { plan: vi.fn(async () => { const e = new Error('Plan falsch'); e.kind = 'plan'; throw e; }) }; const q = fixture(groq); const id = q.addText('Eins. Zwei. Drei.');
    for (let i = 0; i < 6; i++) await q.tick(); expect(repo.entry(id).state).toBe('complete'); expect(groq.plan).toHaveBeenCalledTimes(1);
    q.retry(id); for (let i = 0; i < 6; i++) await q.tick(); expect(groq.plan).toHaveBeenCalledTimes(2); expect(single().text).toBe('Eins. Zwei. Drei.'); q.stop();
  });
  it('excludes its own raw source from retrieval and matches Unicode words', () => { const sentences = [{ id: 's1', text: 'Größe für die Küche' }]; const raw = rawFor(sentences); commands.apply([textOp('Größe der Küche')]); const ctx = context(repo.current(), sentences, 's'); expect(ctx.existing.map(n => n.id)).not.toContain(raw.id); expect(ctx.existing[0].text).toBe('Größe der Küche'); });
  it('persists plain text before the asynchronous model and does not resurrect a deletion', async () => {
    let resolve; const pending = new Promise(r => { resolve = r; }); const groq = { plan: vi.fn(async ctx => { const f = fixturePlan(ctx.sentences); await pending; return f.plan; }) }; const q = fixture(groq);
    const id = q.addText('Kein neues Projekt starten.'); const raw = single(); expect(repo.transcript(id).text).toBe('Kein neues Projekt starten.'); expect(raw.text).toBe('Kein neues Projekt starten.');
    await Promise.resolve(); commands.apply([{ type: 'delete', id: raw.id }]); resolve(); for (let i=0;i<20;i++) await Promise.resolve(); expect(repo.current().nodes[raw.id]).toBeUndefined(); expect(Object.values(repo.current().nodes)).toHaveLength(0); q.stop();
  });
  it('allows only one network plan at a time', async () => { let resolve; const groq = { plan: vi.fn(() => new Promise(r => { resolve = r; })) }; const q = fixture(groq); q.addText('Gedanke eins.'); q.addText('Gedanke zwei.'); await Promise.all([q.tick(),q.tick(),q.tick()]); expect(groq.plan).toHaveBeenCalledTimes(1); q.stop(); resolve({}); });
  it('stores missing-key entries without consuming requests', async () => { const groq = { plan: vi.fn() }; const q = createQueue({ repo, commands, groq, assets: { pending: () => [] }, getSettings: () => defaults(), getKey: () => '' }); q.addText('Ein Gedanke.'); for(let i=0;i<5;i++) await Promise.resolve(); expect(repo.entries()[0].state).toBe('waiting_key'); expect(groq.plan).not.toHaveBeenCalled(); q.stop(); });
  it('restores source visibility when a discarded moment is undone and hides it on redo', () => {
    const q = createQueue({ repo, commands, groq: {}, assets: { pending: () => [] }, getSettings: () => defaults(), getKey: () => '', isBusy: () => true });
    const id = q.addText('Behalten, auch nach Undo.'); q.discard(id); expect(repo.entry(id).state).toBe('discarded');
    commands.undo(); q.reconcileUndo(); expect(repo.entry(id).state).toBe('kept_user'); expect(single().sourceId).toBe(id);
    commands.redo(); q.reconcileUndo(); expect(repo.entry(id).state).toBe('discarded'); expect(Object.values(repo.current().nodes)).toHaveLength(0); q.stop();
  });
  it.each([false, true])('holds an in-flight plan during editing and reuses it after closing (changed=%s)', async changed => {
    let release, editing = null;
    const delayed = new Promise(resolve => { release = resolve; });
    const groq = { plan: vi.fn(async ctx => { await delayed; return fixturePlan(ctx.sentences).plan; }) };
    const q = fixture(groq, { isEditing: id => editing === id });
    const id = q.addText('Ein Gedanke bleibt sichtbar.'), raw = single(); editing = raw.id;
    release(); for (let i = 0; i < 30; i++) await Promise.resolve();
    expect(single().id).toBe(raw.id); expect(repo.readLocal(`sources/${id}/thought-v6-0.json`, null)?.rawRev).toBe(raw.rev);
    if (changed) commands.apply([{ type: 'update', id: raw.id, rev: raw.rev, patch: { text: 'Mein korrigierter Gedanke.' } }]);
    editing = null; repo.saveEntry({ ...repo.entry(id), retryAt: 0 });
    for (let i = 0; i < 5; i++) await q.tick();
    expect(groq.plan).toHaveBeenCalledTimes(1);
    expect(repo.entry(id).state).toBe(changed ? 'kept_user' : 'complete');
    expect(single().text).toBe(changed ? 'Mein korrigierter Gedanke.' : 'Ein Gedanke bleibt sichtbar.'); q.stop();
  });

  it('retains a cached plan across a failed board write without requesting it again', async () => {
    let release; const delayed = new Promise(resolve => { release = resolve; });
    const groq = { plan: vi.fn(async ctx => { await delayed; return fixturePlan(ctx.sentences).plan; }) }, q = fixture(groq);
    const id = q.addText('Lokal sichern.');
    vi.spyOn(commands, 'commit').mockImplementationOnce(() => { throw new Error('disk full'); });
    release(); for (let i = 0; i < 30; i++) await Promise.resolve();
    expect(single().owner).toBe('system'); repo.saveEntry({ ...repo.entry(id), retryAt: 0 });
    for (let i = 0; i < 5; i++) await q.tick();
    expect(groq.plan).toHaveBeenCalledTimes(1); expect(repo.entry(id).state).toBe('complete'); q.stop();
  });
  it('uses a deterministic fallback instead of retrying a failed projection validation', async () => {
    let release; const delayed = new Promise(resolve => { release = resolve; });
    const groq = { plan: vi.fn(async ctx => { await delayed; return fixturePlan(ctx.sentences).plan; }) }, q = fixture(groq);
    const id = q.addText('Original bleibt.');
    vi.spyOn(commands, 'commit').mockImplementationOnce(() => { throw new Error('Ungültige Notes-Daten'); });
    release(); for (let i = 0; i < 30; i++) await Promise.resolve();
    for (let i = 0; i < 5; i++) await q.tick();
    expect(groq.plan).toHaveBeenCalledTimes(1); expect(repo.entry(id).state).toBe('complete'); expect(single().text).toBe('Original bleibt.'); q.stop();
  });
  it('revalidates a waiting cached plan against its original allowed IDs when retrieval changes', async () => {
    commands.commit(b => { for (let i = 0; i < 40; i++) b.topics[`t_${i}`] = { id: `t_${i}`, title: `Thema ${i}`, icon: 'leaf', owner: 'user', createdAt: i }; }, false);
    commands.apply([{ type: 'create', node: { kind: 'note', text: 'Gewächshaus Tomaten', topicId: 't_24' } }]);
    let editing = null, release; const gate = new Promise(resolve => { release = resolve; });
    const groq = { plan: vi.fn(async ctx => { await gate; const plan = fixturePlan(ctx.sentences).plan; plan.topic = { choice: 'existing', id: 't_24' }; return plan; }) };
    const q = fixture(groq, { isEditing: id => editing === id }), id = q.addText('Tomaten im Gewächshaus gießen.'); editing = `raw_${id}`;
    release(); for (let i = 0; i < 30; i++) await Promise.resolve();
    commands.apply(Array.from({ length: 10 }, (_, i) => ({ type: 'create', node: { kind: 'note', text: `Tomaten Gewächshaus gießen ${i}`, topicId: `t_${i}` } })));
    expect(context(repo.current(), repo.transcript(id).sentences, id).topics.some(t => t.id === 't_24')).toBe(true);
    editing = null; repo.saveEntry({ ...repo.entry(id), retryAt: 0 }); for (let i = 0; i < 6; i++) await q.tick();
    expect(repo.entry(id).state).toBe('complete'); expect(groq.plan).toHaveBeenCalledTimes(1);
    expect(Object.values(repo.current().nodes).find(n => n.sourceId === id)?.topicId).toBe('t_24'); q.stop();
  });
  it('makes an explicit retry request a fresh plan after a cached projection fallback', async () => {
    let release; const gate = new Promise(resolve => { release = resolve; });
    const groq = { plan: vi.fn(async ctx => { await gate; return fixturePlan(ctx.sentences).plan; }) }, q = fixture(groq), id = q.addText('Original bleibt sichtbar.');
    vi.spyOn(commands, 'commit').mockImplementationOnce(() => { throw new Error('Ungültige Notes-Daten'); });
    release(); for (let i = 0; i < 30; i++) await Promise.resolve(); for (let i = 0; i < 5; i++) await q.tick();
    expect(repo.entry(id).state).toBe('complete'); expect(groq.plan).toHaveBeenCalledTimes(1);
    q.retry(id); for (let i = 0; i < 8; i++) await q.tick();
    expect(repo.entry(id).state).toBe('complete'); expect(groq.plan).toHaveBeenCalledTimes(2); q.stop();
  });
  it('resolves a user-edited pending card after an empty transcript', async () => {
    const raw = rawFor([]); commands.commit(b => { b.nodes[raw.id].pending = true; }, false);
    commands.apply([{ type: 'update', id: raw.id, patch: { text: 'Eigener Text' } }]);
    repo.saveEntry({ id: 's', state: 'transcribed', createdAt: Date.now() }); repo.saveTranscript('s', { text: '', sentences: [] });
    const q = fixture({ plan: vi.fn() }); await q.tick(); expect(single()).toMatchObject({ pending: false, text: 'Eigener Text' }); q.stop();
  });

  it('leaves completed legacy thoughts alone until explicit retry and preserves every card', async () => {
    const sentences = splitSentences('Die erste Lampe bleibt. Die zweite Lampe auch.', 'legacy');
    repo.saveEntry({ id: 'legacy', state: 'complete', createdAt: Date.now(), parts: 1, partsDone: 1 });
    repo.saveTranscript('legacy', { text: sentences.map(s => s.text).join(' '), sentences });
    commands.commit(b => { for (const sentence of sentences) { const n = node({ kind: 'note', text: sentence.text }); n.owner = 'ai'; n.sourceId = 'legacy'; n.sentenceIds = [sentence.id]; b.nodes[n.id] = n; b.claims[sentence.id] = n.id; } }, false);
    const groq = { plan: vi.fn(async ctx => fixturePlan(ctx.sentences).plan) }, q = fixture(groq), before = repo.snapshot();
    await q.tick(); expect(groq.plan).not.toHaveBeenCalled(); expect(repo.snapshot()).toEqual(before);
    q.retry('legacy'); for (let i = 0; i < 8; i++) await q.tick();
    expect(groq.plan).toHaveBeenCalledTimes(2); expect(repo.entry('legacy').state).toBe('complete');
    expect(Object.values(repo.current().nodes).map(n => n.text)).toEqual(sentences.map(s => s.text));
    expect(Object.keys(repo.current().nodes)).toEqual(Object.keys(before.nodes)); q.stop();
  });
  it('digital silence produces no speech duration and chunking covers every PCM byte', () => { const pcm = Buffer.alloc(20*60*32000); expect(levels(pcm.subarray(0,32000))).toMatchObject({ speechMs: 0, peakDbfs: -120, durationMs: 1000 }); const pieces = audioChunks(pcm); expect(pieces.every(p => p.length < 25*1024*1024)).toBe(true); expect(Buffer.concat(pieces).equals(pcm)).toBe(true); });
});
