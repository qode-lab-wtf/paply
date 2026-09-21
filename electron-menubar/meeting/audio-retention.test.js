import { describe, it, expect } from 'vitest';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
const { createMeetingStore } = require('./meeting-store.js');
const { cleanExpiredAudio, expiresAtMs, RETENTION_MS } = require('./audio-retention.js');

function fakeStore() { const d = { meetings: [] }; return { get: (k) => d[k], set: (k, v) => { d[k] = v; } }; }

describe('audio-retention', () => {
  it('löscht WAV + chunks nur bei abgelaufenen, fertigen Meetings und markiert audioDeleted', () => {
    const baseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ret-'));
    const ms = createMeetingStore({ baseDir, store: fakeStore() });
    const t0 = Date.parse('2026-09-01T10:00:00Z');
    const mk = (startMs, patch) => {
      const id = ms.create(new Date(startMs).toISOString());
      fs.writeFileSync(path.join(ms.meetingDir(id), 'audio_mic.wav'), Buffer.alloc(100));
      fs.writeFileSync(ms.chunkPath(id, 'mic', 0), Buffer.alloc(50));
      fs.writeFileSync(path.join(ms.meetingDir(id), 'transcript.json'), '{}');
      ms.finalizeIndex(id, { status: 'ready', audioExpiresAt: new Date(startMs + RETENTION_MS).toISOString(), ...patch });
      return id;
    };
    const expired = mk(t0);
    const fresh = mk(t0 + 5 * 24 * 3600 * 1000);
    const processing = mk(t0, { status: 'processing' });
    const legacyId = ms.create(new Date(t0).toISOString());
    fs.writeFileSync(path.join(ms.meetingDir(legacyId), 'audio_mic.opus'), Buffer.alloc(10));
    ms.finalizeIndex(legacyId, { audioExpiresAt: null, status: undefined });

    const now = t0 + 8 * 24 * 3600 * 1000;
    const deleted = cleanExpiredAudio(ms, { now });
    expect(deleted.sort()).toEqual([expired, legacyId].sort());
    expect(fs.existsSync(path.join(ms.meetingDir(expired), 'audio_mic.wav'))).toBe(false);
    expect(fs.existsSync(path.join(ms.meetingDir(expired), 'chunks'))).toBe(false);
    expect(fs.existsSync(path.join(ms.meetingDir(expired), 'transcript.json'))).toBe(true);
    expect(fs.existsSync(path.join(ms.meetingDir(fresh), 'audio_mic.wav'))).toBe(true);
    expect(fs.existsSync(path.join(ms.meetingDir(processing), 'audio_mic.wav'))).toBe(true);
    expect(ms.get(expired).index.audioDeleted).toBe(true);
    expect(ms.get(expired).audio.mic).toBeNull();
    expect(ms.get(fresh).index.audioDeleted).toBe(false);
    // Zweiter Lauf: nichts mehr zu tun
    expect(cleanExpiredAudio(ms, { now })).toEqual([]);
  });

  it('expiresAtMs: audioExpiresAt vor startTime+7d', () => {
    expect(expiresAtMs({ audioExpiresAt: '2026-01-02T00:00:00Z' })).toBe(Date.parse('2026-01-02T00:00:00Z'));
    expect(expiresAtMs({ startTime: '2026-01-01T00:00:00Z' })).toBe(Date.parse('2026-01-01T00:00:00Z') + RETENTION_MS);
  });
});
