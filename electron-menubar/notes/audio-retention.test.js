import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const { createRepo } = require('./repo');
const { createCommands } = require('./commands');
const { createQueue } = require('./queue');
const { createAssets } = require('./assets');
let root, repo, q;
beforeEach(() => { root = fs.mkdtempSync(path.join(os.tmpdir(), 'notes-ret-')); repo = createRepo(root); });
afterEach(() => { q?.stop(); vi.restoreAllMocks(); vi.useRealTimers(); fs.rmSync(root, { recursive: true, force: true }); });
function make(state, age = 0, text) {
  const id = `s_${repo.entries().length}`;
  repo.saveEntry({ id, kind: 'voice', state, createdAt: Date.now() - age });
  fs.writeFileSync(path.join(repo.sourcePath(id), 'rec.pcm'), Buffer.alloc(32000));
  if (text !== undefined) repo.saveTranscript(id, { text, sentences: [] });
  return id;
}
const audio = id => fs.existsSync(path.join(repo.sourcePath(id), 'rec.pcm'));
function queue(extra = {}) { q = createQueue({ repo, commands: createCommands(repo), getKey: () => '', getSettings: () => ({}), assets: { pending: () => [] }, ...extra }); return q; }
describe('Notes Ton', () => {
  it('löscht nach erfolgreichem gespeichertem Transkript auch ein leeres Ergebnis sofort', async () => {
    const id = make('captured');
    queue({ getKey: () => 'k' });
    await q.tick(); // digital silence → erfolgreiches leeres Transkript
    expect(repo.transcript(id).text).toBe(''); expect(audio(id)).toBe(false);
  });
  it('löscht nichtleeren Ton vor der späteren KI-Einordnung', async () => {
    const id = make('captured');
    repo.writeLocal(`sources/${id}/stt.json`, [{ text: 'Mein gespeicherter Gedanke.', durationMs: 1000 }]);
    queue({ getKey: () => 'k' }); await q.tick();
    expect(repo.transcript(id).text).toBe('Mein gespeicherter Gedanke.');
    expect(repo.entry(id).state).toBe('transcribed'); expect(audio(id)).toBe(false);
  });
  it.each([['Schlüssel fehlt', () => ''], ['offline', () => 'k']])('behält bei %s ohne Text den Ton', async (_, getKey) => {
    const id = make('captured'); queue({ getKey, isOnline: () => false }); await q.tick();
    expect(audio(id)).toBe(true); expect(repo.transcript(id)).toBeNull();
  });
  it('räumt fertige Altdaten mit Text und leerem Text auf, ohne Text zu ändern', () => {
    const ids = [make('complete', 0, 'Original'), make('empty', 0, '')];
    queue().cleanAudio();
    expect(ids.map(audio)).toEqual([false, false]); expect(repo.transcript(ids[0]).text).toBe('Original');
  });
  it.each(['waiting_key', 'waiting_network', 'needs_attention', 'captured'])('behält %s ohne Text bis 30 Tage und räumt auch nie fertige Einträge auf', state => {
    vi.useFakeTimers();
    const young = make(state, 30 * 86400000 - 1), old = make(state, 30 * 86400000);
    queue().cleanAudio(); expect(audio(young)).toBe(true); expect(audio(old)).toBe(false);
  });
  it('behält Audio bei Transkript-Speicherfehler', async () => {
    const id = make('captured'); vi.spyOn(repo, 'saveTranscript').mockImplementation(() => { throw new Error('Disk full'); });
    queue({ getKey: () => 'k' }); await q.tick(); expect(audio(id)).toBe(true); expect(repo.transcript(id)).toBeNull();
  });
  it('prüft beim Start und stündlich, schützt laufende Aufnahme', () => {
    vi.useFakeTimers(); const done = make('complete', 0, 'Text'), pending = make('needs_attention', 30 * 86400000 - 3600000), recording = make('recording', 40 * 86400000);
    queue().start(); expect(audio(done)).toBe(false); expect(audio(pending)).toBe(true);
    vi.advanceTimersByTime(3600000); expect(audio(pending)).toBe(false); expect(audio(recording)).toBe(true);
  });
  it('liefert kein Audio mehr über das Notes-Protokoll', async () => {
    const assets = createAssets({ repo });
    expect((await assets.serve({ url: 'paply-notes://audio/s_0' })).status).toBe(403);
  });
});
