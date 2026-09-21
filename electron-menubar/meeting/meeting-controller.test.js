import { describe, it, expect } from 'vitest';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { EventEmitter } from 'node:events';
const { createMeetingController, transcriptToText } = require('./meeting-controller.js');
const { createMeetingStore } = require('./meeting-store.js');
const { wavDurationSec } = require('../audio/wav-encoder.js');

const SR = 100; // kleine Rate → kleine Puffer in Tests

function fakeStore(init = {}) {
  const d = { language: 'de', groqApiKey: 'k', geminiApiKey: 'g', meetings: [], ...init };
  return { get: (k) => d[k], set: (k, v) => { d[k] = v; } };
}

class FakeTee extends EventEmitter {
  constructor() { super(); this.isRunning = false; }
  start() { this.isRunning = true; }
  stop() { this.isRunning = false; }
}

// Nicht-stilles PCM (200 Byte = 100 Samples = 1 s bei SR 100)
function signal(bytes = 200, amp = 8000) {
  const b = Buffer.alloc(bytes);
  for (let i = 0; i + 1 < bytes; i += 2) b.writeInt16LE(amp, i);
  return b;
}

// Fake-Auswertung (statt Gemini): liefert zwei Sprecher; protokolliert die übergebenen Pfade.
function fakeAnalyze(calls = []) {
  return async (opts) => {
    calls.push(opts);
    await new Promise((r) => setTimeout(r, 2)); // echte Auswertung dauert → 'processing' ist beobachtbar
    return {
      segments: [
        { tStart: 0, tEnd: 1, speaker: 'Sprecher 1', channel: 'mic', text: 'Hallo zusammen, fangen wir an.' },
        { tStart: 1, tEnd: 2, speaker: 'Sprecher 2', channel: 'mic', text: 'Gerne.' },
      ],
      speakers: [{ id: 'S1', label: 'Sprecher 1', channel: 'mic', beschreibung: '' }],
      model: 'fake-gemini',
    };
  };
}
const fakeSummary = async () => ({ schema: 2, titel: 'Kickoff', kurzfassung: 'Z', themen: [], entscheidungen: [], offeneFragen: [], todos: [], generatedAt: '', model: 'm' });

function makeCtl(overrides = {}) {
  const baseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-ctl-'));
  const store = overrides.store || fakeStore(overrides.storeInit);
  const meetingStore = createMeetingStore({ baseDir, store });
  const tee = new FakeTee();
  const events = [];
  const win = { webContents: { send: (ch, p) => events.push({ ch, p }) } };
  let t = 1700000000000;
  const clock = { now: () => t, advance: (ms) => { t += ms; } };
  const ctl = createMeetingController({
    store, meetingStore, audioTee: tee,
    showOverlay: () => win, hideOverlay: () => { events.push({ ch: 'overlay:hide' }); }, getMainWindow: () => win,
    windowSeconds: 1, sampleRate: SR, captureStopTimeoutMs: 5, systemChunkMs: 0,
    analyzeAudio: fakeAnalyze(overrides.analyzeCalls), fallbackAnalyze: overrides.fallbackAnalyze, summarize: fakeSummary,
    cleanRetention: overrides.cleanRetention || (() => []),
    now: clock.now, sleep: async () => {},
    ...(overrides.deps || {}),
  });
  return { ctl, store, meetingStore, tee, events, win, clock, baseDir };
}

describe('MeetingController v2 (Fakes statt Netz)', () => {
  it('nimmt beide Spuren auf, stoppt schnell (processing), wertet asynchron aus (ready) und erzeugt den Bericht', async () => {
    const calls = [];
    const { ctl, meetingStore, tee, events } = makeCtl({ analyzeCalls: calls });
    const { id } = ctl.start();
    expect(tee.isRunning).toBe(true);
    expect(meetingStore.get(id).index.status).toBe('recording');
    tee.emit('pcm', signal());
    ctl.onMicCaptureStarted({ firstSampleAtMs: 1700000000000 });
    ctl.onMicPcm(signal());

    const r = await ctl.stop();
    expect(r.id).toBe(id);
    // Phase 1 fertig: Status processing, Audio-Dateien liegen, Overlay zu, Events raus
    const afterStop = meetingStore.get(id);
    expect(afterStop.index.status).toBe('processing');
    expect(afterStop.index.systemRemote).toBe(true); // System-Signal ohne Detektor → Gegenstelle
    expect(afterStop.index.audioExpiresAt).toBe(new Date(1700000000000 + 7 * 86400000).toISOString());
    expect(afterStop.audio.mic).not.toBeNull();
    expect(afterStop.audio.system).not.toBeNull();
    expect(events.some((e) => e.ch === 'meeting:capture-stop')).toBe(true);
    expect(events.some((e) => e.ch === 'meeting:stopped')).toBe(true);
    expect(events.some((e) => e.ch === 'overlay:hide')).toBe(true);
    expect(tee.isRunning).toBe(false);

    await ctl.whenIdle();
    const full = meetingStore.get(id);
    expect(full.index.status).toBe('ready');
    expect(full.index.analysis).toBe('gemini');
    expect(full.transcript.segments.length).toBe(2);
    expect(full.index.speakerCount).toBe(2);
    expect(full.index.speakerNames).toEqual(['Sprecher 1', 'Sprecher 2']);
    expect(full.summary.titel).toBe('Kickoff');
    expect(full.index.title).toBe('Kickoff');
    expect(full.index.hasSummary).toBe(true);
    // Auswertung bekam beide Spuren (System als Gegenstelle)
    expect(calls[0].systemWavPath).not.toBeNull();
    expect(calls[0].apiKey).toBe('g');
    // Chunks nach Erfolg weg, Audio bleibt (7 Tage)
    expect(fs.existsSync(path.join(meetingStore.meetingDir(id), 'chunks'))).toBe(false);
    expect(full.audio.mic).not.toBeNull();
    const statuses = events.filter((e) => e.ch === 'meetings:updated').map((e) => e.p.status);
    expect(statuses).toContain('processing');
    expect(statuses[statuses.length - 1]).toBe('ready');
  });

  it('Startlücke: Mikro-Stille wird vorangestellt, Index merkt sich die Lücke; System ohne Detektor', async () => {
    const { ctl, meetingStore, clock } = makeCtl();
    const { id } = ctl.start();
    clock.advance(2500);
    ctl.onMicCaptureStarted({ firstSampleAtMs: clock.now() }); // 2,5 s nach Start
    ctl.onMicPcm(signal()); // 1 s Signal
    clock.advance(1000);
    await ctl.stop();
    const full = meetingStore.get(id);
    expect(full.index.captureStartGapMs.mic).toBe(2500);
    // audio_mic.wav = 2,5 s Stille + 1 s Signal
    expect(wavDurationSec(full.audio.mic, SR)).toBeCloseTo(3.5, 5);
    expect(full.index.chunkBoundariesSec).toEqual([1, 2, 3, 3.5]);
    expect(full.index.durationMs).toBe(3500);
    await ctl.whenIdle();
  });

  it('Stop-Handshake: Restpuffer aus dem Renderer landet noch in der Aufnahme (Ack vor Timeout)', async () => {
    const { ctl, meetingStore, events } = makeCtl({ deps: { captureStopTimeoutMs: 500 } });
    const { id } = ctl.start();
    ctl.onMicCaptureStarted({ firstSampleAtMs: 1700000000000 });
    ctl.onMicPcm(signal());
    const p = ctl.stop();
    // Renderer reagiert auf capture-stop: sendet Rest + Ack
    expect(events.some((e) => e.ch === 'meeting:capture-stop')).toBe(true);
    expect(ctl.isActive()).toBe(false); // während des Stops nicht mehr „aktiv“ (Hotkey startet nichts Neues)
    ctl.onMicPcm(signal(100));
    ctl.onCaptureFlushed();
    await p;
    expect(wavDurationSec(meetingStore.get(id).audio.mic, SR)).toBeCloseTo(1.5, 5);
    await ctl.whenIdle();
  });

  it('systemAudioMode "never": System-Spur wird nicht an die Auswertung übergeben', async () => {
    const calls = [];
    const { ctl, meetingStore, tee } = makeCtl({ storeInit: { systemAudioMode: 'never' }, analyzeCalls: calls });
    const { id } = ctl.start();
    tee.emit('pcm', signal());
    ctl.onMicPcm(signal());
    await ctl.stop();
    await ctl.whenIdle();
    expect(meetingStore.get(id).index.systemRemote).toBe(false);
    expect(calls[0].systemWavPath).toBeNull();
  });

  it('auto + Detektor lief ohne Anruf (Musik): System nicht als Gegenstelle; mit Anruf: ja', async () => {
    for (const call of [false, true]) {
      const calls = [];
      const detector = new EventEmitter(); detector.isSupported = true; detector.start = () => {}; detector.stop = () => {};
      const { ctl, meetingStore, tee } = makeCtl({ analyzeCalls: calls, deps: { callDetector: detector } });
      const { id } = ctl.start();
      if (call) detector.emit('call-state', true);
      tee.emit('pcm', signal());
      ctl.onMicPcm(signal());
      await ctl.stop();
      await ctl.whenIdle();
      expect(meetingStore.get(id).index.systemRemote).toBe(call);
      expect(meetingStore.get(id).index.callDetected).toBe(call);
      expect(calls[0].systemWavPath === null).toBe(!call);
    }
  });

  it('Detektor-Fehler: Fallback auf Signal-Heuristik (System wird einbezogen)', async () => {
    const calls = [];
    const detector = new EventEmitter(); detector.isSupported = true; detector.start = () => {}; detector.stop = () => {};
    const { ctl, meetingStore, tee } = makeCtl({ analyzeCalls: calls, deps: { callDetector: detector } });
    const { id } = ctl.start();
    detector.emit('error', new Error('binary fehlt'));
    tee.emit('pcm', signal());
    ctl.onMicPcm(signal());
    await ctl.stop();
    await ctl.whenIdle();
    expect(meetingStore.get(id).index.systemRemote).toBe(true);
  });

  it('Gemini scheitert → Groq-Fallback ohne Sprecher, Hinweis bleibt im Index', async () => {
    const fallbackCalls = [];
    const { ctl, meetingStore } = makeCtl({
      deps: { analyzeAudio: async () => { const e = new Error('HTTP 429'); e.code = 'rate_limit'; throw e; } },
      fallbackAnalyze: async (o) => { fallbackCalls.push(o); return { segments: [{ tStart: 0, tEnd: 1, speaker: 'Sprecher 1', channel: 'mic', text: 'Nur Text.' }], model: 'whisper' }; },
    });
    const { id } = ctl.start();
    ctl.onMicPcm(signal());
    await ctl.stop();
    await ctl.whenIdle();
    const full = meetingStore.get(id);
    expect(full.index.status).toBe('ready');
    expect(full.index.analysis).toBe('groq-fallback');
    expect(full.index.analysisError).toContain('Gemini');
    expect(fallbackCalls[0].apiKey).toBe('k');
    expect(full.transcript.segments[0].text).toBe('Nur Text.');
  });

  it('ohne Gemini-Key direkt Fallback; ohne beide Keys → failed mit Klartext', async () => {
    const { ctl, meetingStore } = makeCtl({ storeInit: { geminiApiKey: '' }, fallbackAnalyze: async () => ({ segments: [{ tStart: 0, tEnd: 1, speaker: 'Sprecher 1', channel: 'mic', text: 'x' }], model: 'w' }) });
    const { id } = ctl.start(); ctl.onMicPcm(signal()); await ctl.stop(); await ctl.whenIdle();
    expect(meetingStore.get(id).index.analysis).toBe('groq-fallback');

    const c2 = makeCtl({ storeInit: { geminiApiKey: '', groqApiKey: '' } });
    const r = c2.ctl.start(); c2.ctl.onMicPcm(signal()); await c2.ctl.stop(); await c2.ctl.whenIdle();
    const idx = c2.meetingStore.get(r.id).index;
    expect(idx.status).toBe('failed');
    expect(idx.analysisError).toContain('Kein Gemini-Key');
    expect(c2.meetingStore.get(r.id).audio.mic).not.toBeNull(); // Audio bleibt für „Neu auswerten“
  });

  it('reanalyze: erneute Auswertung aus dem gespeicherten Audio; ohne Audio Fehler', async () => {
    const calls = [];
    const { ctl, meetingStore } = makeCtl({ analyzeCalls: calls });
    const { id } = ctl.start(); ctl.onMicPcm(signal()); await ctl.stop(); await ctl.whenIdle();
    expect(calls.length).toBe(1);
    expect(ctl.reanalyze(id)).toEqual({ ok: true });
    await ctl.whenIdle();
    expect(calls.length).toBe(2);
    expect(meetingStore.get(id).index.status).toBe('ready');
    fs.rmSync(meetingStore.audioPath(id, 'mic'));
    expect(ctl.reanalyze(id)).toEqual({ error: 'no_audio' });
  });

  it('resumePending: abgebrochene Aufnahme wird aus Chunks gerettet und ausgewertet; zu viele Versuche → failed', async () => {
    const { ctl, meetingStore } = makeCtl();
    // Simulierter Absturz während der Aufnahme: Index 'recording', nur Chunks vorhanden
    const id = meetingStore.create(new Date(1700000000000).toISOString());
    meetingStore.finalizeIndex(id, { status: 'recording' });
    fs.writeFileSync(meetingStore.chunkPath(id, 'mic', 0), require('../audio/wav-encoder.js').encodeWav(signal(400), { sampleRate: SR, channels: 1 }));
    // Abgebrochene Auswertung, schon 3 Versuche
    const id2 = meetingStore.create(new Date(1700000001000).toISOString());
    meetingStore.finalizeIndex(id2, { status: 'processing', analysisAttempts: 3 });

    const resumed = ctl.resumePending();
    expect(resumed).toEqual([id]);
    await ctl.whenIdle();
    const full = meetingStore.get(id);
    expect(full.index.status).toBe('ready');
    expect(full.index.durationMs).toBe(2000);
    expect(full.audio.mic).not.toBeNull();
    expect(meetingStore.get(id2).index.status).toBe('failed');
  });

  it('Retention läuft nach der Auswertung; regenerateSummary aktualisiert Titel', async () => {
    let ran = 0;
    const { ctl, meetingStore } = makeCtl({ cleanRetention: () => { ran++; return []; } });
    const { id } = ctl.start(); ctl.onMicPcm(signal()); await ctl.stop(); await ctl.whenIdle();
    expect(ran).toBe(1);
    const s = await ctl.regenerateSummary(id);
    expect(s.titel).toBe('Kickoff');
    expect(ctl.runRetention()).toEqual([]);
    expect(ran).toBe(2);
  });

  it('start während stop wird ignoriert; isActive/getStatus spiegeln den Zustand', async () => {
    const { ctl } = makeCtl();
    expect(ctl.isActive()).toBe(false);
    const { id } = ctl.start();
    expect(ctl.isActive()).toBe(true);
    expect(ctl.getStatus()).toMatchObject({ active: true, id, micReady: false });
    ctl.onMicPcm(signal());
    expect(ctl.getStatus().micReady).toBe(true);
    const p = ctl.stop();
    expect(ctl.start().id).toBe(id); // kein neuer Start während des Stops
    await p;
    expect(ctl.isActive()).toBe(false);
    await ctl.whenIdle();
  });

  it('transcriptToText: Zeitmarke + Sprecher je Zeile', () => {
    expect(transcriptToText([{ tStart: 65, speaker: 'Sprecher 1', text: 'Hi' }])).toBe('[01:05] Sprecher 1: Hi');
  });
});
