import { describe, it, expect } from 'vitest';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
const { encodeWav } = require('../audio/wav-encoder.js');
const {
  transcribeWithGemini, planWindows, readWavSlice, buildTranscribePrompt, parseTranscriptResponse,
  correctTracksByEnergy, dedupeEcho, assignLabels, withRetry, INLINE_LIMIT_BYTES,
} = require('./gemini-audio.js');

const SR = 16000;

// PCM mit Signal (amp) für `sec` Sekunden, optional nur in [from,to)
function pcm(sec, amp = 8000, from = 0, to = sec) {
  const n = Math.floor(sec * SR);
  const b = Buffer.alloc(n * 2);
  for (let i = 0; i < n; i++) { const t = i / SR; if (t >= from && t < to) b.writeInt16LE(i % 2 ? amp : -amp, i * 2); }
  return b;
}

function writeWav(dir, name, pcmBuf) {
  const p = path.join(dir, name);
  fs.writeFileSync(p, encodeWav(pcmBuf, { sampleRate: SR, channels: 1 }));
  return p;
}

describe('planWindows', () => {
  it('kurze Aufnahme → ein Fenster', () => {
    expect(planWindows([10, 20], 30)).toEqual([{ startSec: 0, endSec: 30 }]);
  });
  it('schneidet an der letzten Chunk-Grenze vor dem Limit', () => {
    const w = planWindows([25, 50, 75, 100, 125], 130, { maxSeconds: 60 });
    expect(w).toEqual([{ startSec: 0, endSec: 50 }, { startSec: 50, endSec: 100 }, { startSec: 100, endSec: 130 }]);
  });
  it('ohne passende Grenze hart am Limit; winziger Rest wird angehängt', () => {
    expect(planWindows([], 125, { maxSeconds: 60, minTailSeconds: 20 })).toEqual([{ startSec: 0, endSec: 60 }, { startSec: 60, endSec: 125 }]);
  });
  it('leer bei 0 s', () => { expect(planWindows([], 0)).toEqual([]); });
});

describe('readWavSlice', () => {
  it('liest den Zeitausschnitt ohne Header', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ga-'));
    const p = writeWav(dir, 'a.wav', pcm(3));
    const s = readWavSlice(p, 1, 2, SR);
    expect(s.length).toBe(SR * 2);
    expect(readWavSlice(p, 2.5, 10, SR).length).toBe(SR); // Ende geklemmt
  });
});

describe('buildTranscribePrompt', () => {
  it('nennt beide Spuren nur bei System-Audio und trägt die Legende weiter', () => {
    const p1 = buildTranscribePrompt({ hasSystem: false });
    expect(p1).toContain('Spur A');
    expect(p1).not.toContain('Spur B');
    const p2 = buildTranscribePrompt({ hasSystem: true, windowIndex: 1, windowCount: 3, windowStartSec: 1500, legend: [{ id: 'S1', spur: 'A', beschreibung: 'tief' }, { id: 'S2', spur: 'B', beschreibung: 'hell' }] });
    expect(p2).toContain('Spur B');
    expect(p2).toContain('S1 (Spur A): tief');
    expect(p2).toContain('ab S3');
    expect(p2).toContain('25:00');
  });
});

describe('parseTranscriptResponse', () => {
  it('verschiebt Zeiten um den Fensteroffset, sortiert, ignoriert Leertext', () => {
    const r = parseTranscriptResponse(JSON.stringify({
      sprecher: [{ id: 'S1', spur: 'A', beschreibung: 'x' }],
      segmente: [
        { start: 5, ende: 7, sprecher: 'S2', spur: 'B', text: 'Zwei' },
        { start: 1.25, ende: 3, sprecher: 'S1', spur: 'A', text: 'Eins', unsicher: true },
        { start: 8, ende: 9, sprecher: 'S1', spur: 'A', text: '   ' },
      ],
    }), { windowStartSec: 100, windowEndSec: 200, hasSystem: true });
    expect(r.segments.map((s) => s.text)).toEqual(['Eins', 'Zwei']);
    expect(r.segments[0]).toMatchObject({ tStart: 101.3, tEnd: 103, speakerId: 'S1', track: 'A', unsicher: true });
    expect(r.segments[1].track).toBe('B');
  });
  it('ohne System-Spur wird spur B auf A gezwungen; JSON in Fences wird gelesen', () => {
    const r = parseTranscriptResponse('```json\n{"sprecher":[],"segmente":[{"start":0,"ende":1,"sprecher":"S1","spur":"B","text":"a"}]}\n```', { hasSystem: false });
    expect(r.segments[0].track).toBe('A');
  });
});

describe('correctTracksByEnergy + dedupeEcho + assignLabels', () => {
  it('korrigiert die Spur, wenn die gewählte Spur still ist', () => {
    const mic = pcm(10, 8000, 0, 5);   // nur 0–5 s Signal
    const sys = pcm(10, 8000, 5, 10);  // nur 5–10 s Signal
    const segs = [
      { tStart: 1, tEnd: 2, speakerId: 'S1', track: 'B', text: 'a' }, // falsch: sys ist still
      { tStart: 6, tEnd: 7, speakerId: 'S2', track: 'A', text: 'b' }, // falsch: mic ist still
      { tStart: 3, tEnd: 4, speakerId: 'S1', track: 'A', text: 'c' }, // korrekt
    ];
    const out = correctTracksByEnergy(segs, { micPcm: mic, sysPcm: sys, sampleRate: SR });
    expect(out.map((s) => s.track)).toEqual(['A', 'B', 'A']);
  });
  it('entfernt Mikro-Echo mit gleichem Text zeitgleich auf der System-Spur', () => {
    const segs = [
      { tStart: 10, tEnd: 13, speakerId: 'S1', track: 'A', text: 'Wir treffen uns morgen um zehn Uhr' },
      { tStart: 10.5, tEnd: 13, speakerId: 'S2', track: 'B', text: 'Wir treffen uns morgen um zehn Uhr.' },
      { tStart: 14, tEnd: 15, speakerId: 'S1', track: 'A', text: 'Alles klar, passt gut für mich' },
    ];
    expect(dedupeEcho(segs).map((s) => s.text)).toEqual(['Wir treffen uns morgen um zehn Uhr.', 'Alles klar, passt gut für mich']);
  });
  it('vergibt Sprecher N / Gegenstelle nach Kanal-Mehrheit und erstem Auftreten', () => {
    const segs = [
      { tStart: 0, tEnd: 1, speakerId: 'S2', track: 'A', text: 'a' },
      { tStart: 1, tEnd: 2, speakerId: 'S1', track: 'B', text: 'b' },
      { tStart: 2, tEnd: 3, speakerId: 'S3', track: 'A', text: 'c', unsicher: true },
      { tStart: 3, tEnd: 4, speakerId: 'S4', track: 'B', text: 'd' },
    ];
    const r = assignLabels(segs);
    expect(r.segments.map((s) => s.speaker)).toEqual(['Sprecher 1', 'Gegenstelle', 'Sprecher 2', 'Gegenstelle 2']);
    expect(r.segments[2]).toMatchObject({ channel: 'mic', unsicher: true });
    expect(r.segments[1].channel).toBe('system');
    expect(r.speakers.map((s) => s.label)).toEqual(['Sprecher 1', 'Gegenstelle', 'Sprecher 2', 'Gegenstelle 2']);
  });
});

describe('withRetry', () => {
  it('wiederholt bei 429 und gibt danach das Ergebnis zurück', async () => {
    let n = 0;
    const r = await withRetry(async () => { n++; if (n < 3) { const e = new Error('x'); e.status = 429; e.code = 'rate_limit'; throw e; } return 'ok'; }, { sleep: async () => {} });
    expect(r).toBe('ok'); expect(n).toBe(3);
  });
  it('gibt nach allen Versuchen den letzten Fehler weiter; 400 wird nicht wiederholt', async () => {
    let n = 0;
    await expect(withRetry(async () => { n++; const e = new Error('x'); e.status = 429; e.code = 'rate_limit'; throw e; }, { sleep: async () => {} })).rejects.toMatchObject({ code: 'rate_limit' });
    expect(n).toBe(4);
    n = 0;
    await expect(withRetry(async () => { n++; const e = new Error('bad'); e.status = 400; throw e; }, { sleep: async () => {} })).rejects.toThrow('bad');
    expect(n).toBe(1);
  });
});

// Fake-Gemini: beantwortet generateContent je Aufruf mit vorbereiteten Antworten, protokolliert Requests.
function fakeGemini(responses, log = []) {
  let i = 0;
  return async (url, opts = {}) => {
    const u = String(url);
    if (u.includes(':generateContent')) {
      const body = JSON.parse(opts.body);
      log.push({ model: u.split('/models/')[1].split(':')[0], parts: body.contents[0].parts, gen: body.generationConfig });
      const r = responses[Math.min(i++, responses.length - 1)];
      if (typeof r === 'function') return r(body);
      return { ok: true, status: 200, json: async () => ({ candidates: [{ content: { parts: [{ text: JSON.stringify(r.json) }] }, finishReason: r.finishReason || 'STOP' }] }) };
    }
    if (u.endsWith('/upload/v1beta/files')) return { ok: true, status: 200, headers: { get: () => 'https://upload.example/s' } };
    if (u === 'https://upload.example/s') return { ok: true, status: 200, json: async () => ({ file: { name: 'files/x', uri: 'uri-x', state: 'ACTIVE' } }) };
    if (opts.method === 'DELETE') { log.push({ deleted: u }); return { ok: true, status: 200 }; }
    return { ok: false, status: 404, text: async () => 'nf' };
  };
}

describe('transcribeWithGemini (Fake-Netz)', () => {
  it('kurze Aufnahme: ein Aufruf, Audio inline, Schema + thinkingBudget 0, Labels vergeben', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ga-'));
    const mic = writeWav(dir, 'audio_mic.wav', pcm(4));
    const log = [];
    const fetchImpl = fakeGemini([{ json: { sprecher: [{ id: 'S1', spur: 'A', beschreibung: 'tief' }, { id: 'S2', spur: 'A', beschreibung: 'hell' }], segmente: [
      { start: 0, ende: 1.5, sprecher: 'S1', spur: 'A', text: 'Hallo zusammen.' },
      { start: 1.5, ende: 3, sprecher: 'S2', spur: 'A', text: 'Hallo!' },
    ] } }], log);
    const r = await transcribeWithGemini({ micWavPath: mic, apiKey: 'k', fetchImpl, sleep: async () => {} });
    expect(r.windows).toBe(1);
    expect(r.segments).toEqual([
      { tStart: 0, tEnd: 1.5, speaker: 'Sprecher 1', channel: 'mic', text: 'Hallo zusammen.' },
      { tStart: 1.5, tEnd: 3, speaker: 'Sprecher 2', channel: 'mic', text: 'Hallo!' },
    ]);
    expect(r.speakers[0]).toMatchObject({ label: 'Sprecher 1', beschreibung: 'tief' });
    expect(log[0].model).toBe('gemini-flash-latest');
    expect(log[0].gen.responseMimeType).toBe('application/json');
    expect(log[0].gen.responseSchema.required).toEqual(['sprecher', 'segmente']);
    expect(log[0].gen.thinkingConfig.thinkingBudget).toBe(0);
    expect(log[0].parts.some((p) => p.inlineData && p.inlineData.mimeType === 'audio/wav')).toBe(true);
    expect(log[0].parts.some((p) => p.fileData)).toBe(false);
  });

  it('zwei Spuren, zwei Fenster: Legende wird weitergegeben, Zeiten absolut, Gegenstelle erkannt', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ga-'));
    const mic = writeWav(dir, 'audio_mic.wav', pcm(120));
    const sys = writeWav(dir, 'audio_system.wav', pcm(120));
    const log = [];
    const fetchImpl = fakeGemini([
      { json: { sprecher: [{ id: 'S1', spur: 'A', beschreibung: 'ich' }, { id: 'S2', spur: 'B', beschreibung: 'anrufer' }], segmente: [
        { start: 1, ende: 2, sprecher: 'S1', spur: 'A', text: 'Erstes Fenster.' },
        { start: 3, ende: 4, sprecher: 'S2', spur: 'B', text: 'Antwort am Telefon.' },
      ] } },
      { json: { sprecher: [{ id: 'S3', spur: 'A', beschreibung: 'neu' }], segmente: [
        { start: 2, ende: 3, sprecher: 'S3', spur: 'A', text: 'Zweites Fenster.' },
        { start: 5, ende: 6, sprecher: 'S1', spur: 'A', text: 'Wieder ich.' },
      ] } },
    ], log);
    const r = await transcribeWithGemini({ micWavPath: mic, systemWavPath: sys, chunkBoundariesSec: [30, 60, 90], apiKey: 'k', fetchImpl, sleep: async () => {}, maxWindowSeconds: 70 });
    expect(r.windows).toBe(2);
    expect(log.length).toBe(2);
    const prompt2 = log[1].parts[0].text;
    expect(prompt2).toContain('S2 (Spur B): anrufer');
    expect(prompt2).toContain('Abschnitt 2 von 2');
    expect(r.segments.map((s) => [s.tStart, s.speaker, s.channel])).toEqual([
      [1, 'Sprecher 1', 'mic'], [3, 'Gegenstelle', 'system'], [62, 'Sprecher 2', 'mic'], [65, 'Sprecher 1', 'mic'],
    ]);
    // Systemspur als eigener Part markiert
    expect(log[0].parts.filter((p) => p.inlineData).length).toBe(2);
    expect(log[0].parts.some((p) => p.text === 'Spur B (Systemaudio):')).toBe(true);
  });

  it('großes Fenster geht über die Files API und wird danach gelöscht', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ga-'));
    const sec = Math.ceil(INLINE_LIMIT_BYTES / (SR * 2)) + 2;
    const mic = writeWav(dir, 'audio_mic.wav', pcm(sec, 100));
    const log = [];
    const fetchImpl = fakeGemini([{ json: { sprecher: [], segmente: [{ start: 0, ende: 1, sprecher: 'S1', spur: 'A', text: 'x' }] } }], log);
    const r = await transcribeWithGemini({ micWavPath: mic, apiKey: 'k', fetchImpl, sleep: async () => {} });
    expect(r.segments.length).toBe(1);
    expect(log[0].parts.some((p) => p.fileData && p.fileData.fileUri === 'uri-x')).toBe(true);
    expect(log.some((l) => l.deleted && l.deleted.endsWith('files/x'))).toBe(true);
  });

  it('MAX_TOKENS → Fenster wird geteilt und beide Hälften verarbeitet', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ga-'));
    const mic = writeWav(dir, 'audio_mic.wav', pcm(300, 100));
    const log = [];
    const fetchImpl = fakeGemini([
      { json: { sprecher: [], segmente: [] }, finishReason: 'MAX_TOKENS' },
      { json: { sprecher: [], segmente: [{ start: 1, ende: 2, sprecher: 'S1', spur: 'A', text: 'A' }] } },
      { json: { sprecher: [], segmente: [{ start: 1, ende: 2, sprecher: 'S1', spur: 'A', text: 'B' }] } },
    ], log);
    const r = await transcribeWithGemini({ micWavPath: mic, chunkBoundariesSec: [140], apiKey: 'k', fetchImpl, sleep: async () => {} });
    expect(log.filter((l) => l.model).length).toBe(3);
    expect(r.segments.map((s) => [s.tStart, s.text])).toEqual([[1, 'A'], [141, 'B']]);
  });

  it('429 dauerhaft → Fehler rate_limit; 404 → Fallback-Modell', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ga-'));
    const mic = writeWav(dir, 'audio_mic.wav', pcm(2));
    const f429 = fakeGemini([() => ({ ok: false, status: 429, text: async () => 'quota' })]);
    await expect(transcribeWithGemini({ micWavPath: mic, apiKey: 'k', fetchImpl: f429, sleep: async () => {} })).rejects.toMatchObject({ code: 'rate_limit' });
    const log = [];
    const f404 = fakeGemini([() => ({ ok: false, status: 404, text: async () => 'no model' }), { json: { sprecher: [], segmente: [{ start: 0, ende: 1, sprecher: 'S1', spur: 'A', text: 'ok' }] } }], log);
    const r = await transcribeWithGemini({ micWavPath: mic, apiKey: 'k', fetchImpl: f404, sleep: async () => {} });
    expect(r.model).toBe('gemini-flash-lite-latest');
    expect(r.segments[0].text).toBe('ok');
  });

  it('ohne Key → code no_key', async () => {
    await expect(transcribeWithGemini({ micWavPath: '/nope.wav', apiKey: '' })).rejects.toMatchObject({ code: 'no_key' });
  });
});
