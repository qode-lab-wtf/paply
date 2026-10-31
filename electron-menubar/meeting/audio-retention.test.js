import { describe, it, expect, afterEach } from 'vitest';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
const { createMeetingStore } = require('./meeting-store.js');
const { cleanExpiredAudio, expiresAtMs, RETENTION_MS } = require('./audio-retention.js');
let baseDir;
afterEach(() => fs.rmSync(baseDir, { recursive: true, force: true }));
function fixture() {
  baseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ret-'));
  let entries = [];
  const ms = createMeetingStore({ baseDir, store: { get: () => entries, set: (_, v) => { entries = v; } } });
  const now = Date.now();
  function make(status, age, patch = {}) {
    const id = ms.create(new Date(now - age).toISOString());
    fs.writeFileSync(path.join(ms.meetingDir(id), 'audio_mic.wav'), 'audio');
    fs.writeFileSync(ms.chunkPath(id, 'mic', 0), 'chunk');
    ms.saveTranscript(id, { segments: [{ text: 'Text bleibt' }] });
    ms.finalizeIndex(id, { status, ...patch });
    return id;
  }
  return { ms, now, make };
}
describe('Ton-Regel 8', () => {
  it('löscht fertige Altdaten sofort, auch ohne Status, behält Text und ist idempotent', () => {
    const { ms, now, make } = fixture();
    const ids = [make('ready', 1000), make(undefined, 1000)];
    expect(cleanExpiredAudio(ms, { now }).sort()).toEqual(ids.sort());
    for (const id of ids) {
      expect(ms.get(id).index.audioDeleted).toBe(true);
      expect(ms.get(id).audio.mic).toBeNull();
      expect(fs.existsSync(path.join(ms.meetingDir(id), 'chunks'))).toBe(false);
      expect(ms.loadTranscript(id).segments[0].text).toBe('Text bleibt');
    }
    expect(cleanExpiredAudio(ms, { now })).toEqual([]);
  });
  it('behält Fehler und processing unter 30 Tagen, löscht beide ab 30 Tagen, lässt recording unberührt', () => {
    const { ms, now, make } = fixture();
    const kept = [make('failed', RETENTION_MS - 1), make('processing', RETENTION_MS - 1), make('recording', RETENTION_MS * 2)];
    const expired = [make('failed', RETENTION_MS), make('processing', RETENTION_MS)];
    expect(cleanExpiredAudio(ms, { now }).sort()).toEqual(expired.sort());
    for (const id of kept) expect(ms.get(id).audio.mic).not.toBeNull();
  });
  it('berechnet 30 Tage ab Stopp und ersetzt alte 7-Tage-Fristen ohne vorzeitiges Löschen', () => {
    const { ms, now, make } = fixture();
    const id = make('failed', 8 * 86400000, { durationMs: 1000, audioExpiresAt: new Date(now - 86400000).toISOString() });
    expect(cleanExpiredAudio(ms, { now })).toEqual([]);
    expect(Date.parse(ms.get(id).index.audioExpiresAt)).toBe(now - 8 * 86400000 + 1000 + RETENTION_MS);
    expect(expiresAtMs({ startTime: new Date(0).toISOString(), stoppedAt: new Date(2000).toISOString() })).toBe(2000 + RETENTION_MS);
  });
});

it.each([[[]], [[{text:'  '}]]])('behält ready-Altdaten ohne Text bis zur Frist', segments => {
 const {ms,now,make}=fixture(); const id=make('ready',1000);
 ms.saveTranscript(id,{segments}); expect(cleanExpiredAudio(ms,{now})).toEqual([]);
 expect(ms.get(id).audio.mic).not.toBeNull();
 expect(cleanExpiredAudio(ms,{now:now+RETENTION_MS})).toEqual([id]);
});
