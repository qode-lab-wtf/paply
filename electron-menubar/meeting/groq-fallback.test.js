import { describe, it, expect } from 'vitest';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
const { encodeWav } = require('../audio/wav-encoder.js');
const { transcribeWithGroq } = require('./groq-fallback.js');

const SR = 16000;
function pcm(sec, amp = 8000) { const n = sec * SR; const b = Buffer.alloc(n * 2); for (let i = 0; i < n; i++) b.writeInt16LE(i % 2 ? amp : -amp, i * 2); return b; }

describe('groq-fallback', () => {
  it('transkribiert beide Spuren in 30-s-Fenstern, vergibt Sprecher 1 / Gegenstelle, filtert Echo', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-gf-'));
    const mic = path.join(dir, 'audio_mic.wav'); fs.writeFileSync(mic, encodeWav(pcm(45), { sampleRate: SR, channels: 1 }));
    const sys = path.join(dir, 'audio_system.wav'); fs.writeFileSync(sys, encodeWav(pcm(45), { sampleRate: SR, channels: 1 }));
    const calls = [];
    const fetchImpl = async (url, opts) => {
      calls.push(String(url));
      const n = calls.length;
      // Mic-Fenster 1: zwei Segmente (0–3 s echt, 20–23 s Echo), Mic-Fenster 2, System-Fenster 1+2
      const segs = n === 1 ? [{ start: 0, end: 3, text: 'Ich rede.' }, { start: 20, end: 23, text: 'Echo der Gegenstelle' }]
        : n === 2 ? [{ start: 1, end: 2, text: 'Noch was.' }]
          : n === 3 ? [{ start: 20, end: 23, text: 'Die Gegenstelle spricht.' }] : [];
      return { ok: true, json: async () => ({ segments: segs }) };
    };
    const r = await transcribeWithGroq({ micWavPath: mic, systemWavPath: sys, apiKey: 'k', fetchImpl });
    expect(calls.length).toBe(4);
    expect(r.segments.map((s) => [s.tStart, s.speaker, s.channel, s.text])).toEqual([
      [0, 'Sprecher 1', 'mic', 'Ich rede.'],
      [20, 'Gegenstelle', 'system', 'Die Gegenstelle spricht.'],
      [31, 'Sprecher 1', 'mic', 'Noch was.'],
    ]);
  });

  it('stille Fenster werden nicht gesendet; ohne Key → no_key', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-gf-'));
    const mic = path.join(dir, 'audio_mic.wav'); fs.writeFileSync(mic, encodeWav(Buffer.alloc(SR * 2 * 10), { sampleRate: SR, channels: 1 }));
    let n = 0;
    const r = await transcribeWithGroq({ micWavPath: mic, apiKey: 'k', fetchImpl: async () => { n++; return { ok: true, json: async () => ({ segments: [] }) }; } });
    expect(n).toBe(0);
    expect(r.segments).toEqual([]);
    await expect(transcribeWithGroq({ micWavPath: mic, apiKey: '' })).rejects.toMatchObject({ code: 'no_key' });
  });
});
