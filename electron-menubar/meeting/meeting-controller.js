// MeetingController — orchestriert eine Meeting-Aufnahme im Main-Prozess. CommonJS.
//
// Phase 1 (Aufnahme, live): AudioTee (System-Audio) + Mic-PCM (vom Overlay-Renderer) →
//   ChunkAccumulator (Schnitt an Sprechpausen) → crash-sichere Chunk-Dateien. KEINE Live-
//   Transkription mehr. Startlücken beider Spuren werden mit Stille aufgefüllt, damit die
//   Zeitachse beider Spuren beim Sessionstart beginnt.
// Phase 2 (nach dem Stop, asynchron, seriell): Chunks → audio_mic.wav / audio_system.wav →
//   Gemini-Audio-Auswertung (Wortlaut + Sprecher + Zeitmarken; Fallback Groq Whisper ohne Sprecher)
//   → Bericht v2 → Index-Status ready/failed → 'meetings:updated' ans Dashboard.
// Audio bleibt 7 Tage (Nachhören, Neu-Auswerten), danach löscht audio-retention.js.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { encodeWav, concatWavFiles, wavDurationSec } = require('../audio/wav-encoder');
const { rms } = require('../audio/pcm-utils');
const { ChunkAccumulator } = require('./chunk-accumulator');
const { evaluateHealth } = require('./health-monitor');
const { generateMeetingSummary } = require('./summary');
const { transcribeWithGemini } = require('./gemini-audio');
const { transcribeWithGroq } = require('./groq-fallback');
const { cleanExpiredAudio, RETENTION_MS } = require('./audio-retention');

const MAX_ANALYSIS_ATTEMPTS = 3;

function speakerLabel(s) {
  if (s === 'me') return 'Ich';
  if (s === 'other') return 'Gegenstelle';
  return s;
}

function fmtTime(sec) {
  const s = Math.max(0, Math.floor(sec || 0));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

/** Transkript als Text für den Bericht: „[mm:ss] Sprecher: Text“ je Zeile. */
function transcriptToText(segments) {
  return (segments || []).map((s) => `[${fmtTime(s.tStart)}] ${speakerLabel(s.speaker)}: ${s.text}`).join('\n');
}

function describeError(e) {
  if (!e) return 'Unbekannter Fehler';
  if (e.code === 'no_key') return e.message || 'API-Key fehlt';
  if (e.code === 'rate_limit') return 'Kontingent erschöpft (429) — später „Neu auswerten“';
  if (e.code === 'blocked') return e.message;
  return (e.message || String(e)).slice(0, 300);
}

/**
 * @param {{
 *   store: { get: Function, set?: Function },
 *   meetingStore: object,                // createMeetingStore(...)
 *   audioTee: import('events').EventEmitter & { start: Function, stop: Function, isRunning: boolean },
 *   showOverlay?: () => any,             // zeigt das (vorgeladene) Overlay-Fenster, liefert es
 *   hideOverlay?: () => void,
 *   getOverlayWindow?: () => any,        // Abwärtskompatibel: erzeugt/zeigt das Overlay
 *   getMainWindow: () => any,
 *   fetchImpl?: Function,
 *   sampleRate?: number, windowSeconds?: number, chunkMinSeconds?: number, chunkMaxSeconds?: number, silenceRms?: number,
 *   callDetector?: object|null,          // nativer Anruf-Detektor (macOS); null = Signal-Fallback
 *   analyzeAudio?: Function,             // Default: Gemini (injizierbar für Tests)
 *   fallbackAnalyze?: Function,          // Default: Groq Whisper
 *   summarize?: Function,                // Default: generateMeetingSummary
 *   cleanRetention?: Function,           // Default: cleanExpiredAudio
 *   captureStopTimeoutMs?: number, systemChunkMs?: number, analysisWindowSeconds?: number,
 *   now?: () => number, sleep?: Function,
 * }} deps
 */
function createMeetingController(deps) {
  const {
    store, meetingStore, audioTee, getMainWindow, fetchImpl,
    windowSeconds = 30, sampleRate = 16000, excludePid,
    chunkMinSeconds, chunkMaxSeconds, silenceRms,
    callDetector = null,
    analyzeAudio = transcribeWithGemini,
    fallbackAnalyze = transcribeWithGroq,
    summarize = generateMeetingSummary,
    cleanRetention = cleanExpiredAudio,
    captureStopTimeoutMs = 1500,
    systemChunkMs = 200,
    analysisWindowSeconds = 1500,
    now = () => Date.now(),
    sleep,
  } = deps;
  const showOverlay = deps.showOverlay || deps.getOverlayWindow || (() => null);
  const hideOverlay = deps.hideOverlay || ((w) => { try { if (w && typeof w.hide === 'function') w.hide(); } catch { /* egal */ } });

  function makeAccumulator(onChunk) {
    const opts = { sampleRate, onChunk };
    if (chunkMinSeconds != null || chunkMaxSeconds != null) {
      opts.minSeconds = chunkMinSeconds != null ? chunkMinSeconds : 20;
      opts.maxSeconds = chunkMaxSeconds != null ? chunkMaxSeconds : 40;
      if (silenceRms != null) opts.silenceRms = silenceRms;
    } else {
      opts.windowSeconds = windowSeconds;
    }
    return new ChunkAccumulator(opts);
  }

  // ---------------- Aufnahme-Zustand ----------------
  let active = false;
  let stopping = false;
  let sessionId = null;
  let startedAtMs = 0;
  let micAcc = null;
  let sysAcc = null;
  let healthTimer = null;
  let overlayWin = null;
  let micChunkEnds = [];   // Sekunden-Positionen der Mikro-Chunk-Enden (Fenstergrenzen für die Auswertung)

  let micReady = false;    // erstes Mikro-Paket eingetroffen
  let sysReady = false;
  let micGapMs = 0;
  let sysGapMs = 0;
  let lastSystemPcmMs = 0;
  let micLevel = 0;
  let systemLevel = 0;
  let micWriteOk = true;
  let diskError = false;
  let permissionDenied = false;
  let systemAudioError = null;
  let gotSystemPcm = false;
  let callActive = false;
  let callDetectedEver = false;
  let callDetectorRan = false;
  let captureFlushResolve = null;

  let onTeePcm = null; let onTeeError = null; let onTeeLog = null;
  let onDetectorState = null; let onDetectorError = null;

  // Wird der System-Kanal als „Gegenstelle“ gewertet? Einstellung 'always'/'never' überschreibt;
  // 'auto': lief der native Detektor, ihm vertrauen; sonst Signal-Präsenz.
  function systemIsRemote() {
    const mode = store.get('systemAudioMode') || 'auto';
    if (mode === 'always') return true;
    if (mode === 'never') return false;
    return callDetectorRan ? callDetectedEver : gotSystemPcm;
  }

  function llmConfig() {
    return {
      groqApiKey: store.get('groqApiKey'),
      geminiApiKey: store.get('geminiApiKey'),
      llmProvider: store.get('llmProvider') || 'auto',
      model: store.get('meetingSummaryModel'),
      fetchImpl,
    };
  }

  function _sendTo(w, channel, payload) {
    try {
      if (w && w.webContents && (typeof w.isDestroyed !== 'function' || !w.isDestroyed())) w.webContents.send(channel, payload);
    } catch { /* Fenster evtl. zerstört */ }
  }
  function _emit(channel, payload) {
    _sendTo(overlayWin, channel, payload);
    _sendTo(getMainWindow ? getMainWindow() : null, channel, payload);
  }
  function _emitUpdated(id, status, extra) {
    _sendTo(getMainWindow ? getMainWindow() : null, 'meetings:updated', { id, status, ...(extra || {}) });
  }

  function _handleChunk(channel, { pcm, tOffset }) {
    const wav = encodeWav(pcm, { sampleRate, channels: 1 });
    try {
      fs.writeFileSync(meetingStore.chunkPath(sessionId, channel, _seq[channel]++), wav);
      micWriteOk = true;
    } catch {
      diskError = true;
      micWriteOk = false;
    }
    if (channel === 'mic') micChunkEnds.push(Math.round((tOffset + pcm.length / 2 / sampleRate) * 10) / 10);
  }
  let _seq = { mic: 0, system: 0 };

  function _emitHealth() {
    const secondsSinceStart = (now() - startedAtMs) / 1000;
    const secondsSinceSystemAudio = lastSystemPcmMs ? (now() - lastSystemPcmMs) / 1000 : 0;
    const health = evaluateHealth({
      micWriteOk,
      systemProcessAlive: !!audioTee.isRunning,
      systemPermissionDenied: permissionDenied,
      systemAudioError,
      diskError,
      micLevel,
      systemLevel,
      secondsSinceSystemAudio,
      gotSystemPcm,
      secondsSinceStart,
      micReady,
      micStartGapMs: secondsSinceStart < 20 ? micGapMs : 0,
    });
    _emit('meeting:status', {
      color: health.color,
      reason: health.reason,
      durationMs: now() - startedAtMs,
      micLevel,
      systemLevel,
      micReady,
    });
  }

  // ---------------- Phase 1: Aufnahme ----------------

  function start() {
    if (active || stopping) return { id: sessionId };
    active = true;
    startedAtMs = now();
    sessionId = meetingStore.create(new Date(startedAtMs).toISOString());
    try { meetingStore.finalizeIndex(sessionId, { status: 'recording' }); } catch { /* best effort */ }

    micChunkEnds = []; _seq = { mic: 0, system: 0 };
    micReady = false; sysReady = false; micGapMs = 0; sysGapMs = 0;
    micLevel = 0; systemLevel = 0; micWriteOk = true; diskError = false; permissionDenied = false; systemAudioError = null; gotSystemPcm = false;
    lastSystemPcmMs = startedAtMs;
    callActive = false; callDetectedEver = false; callDetectorRan = false;
    captureFlushResolve = null;

    micAcc = makeAccumulator((c) => _handleChunk('mic', c));
    sysAcc = makeAccumulator((c) => _handleChunk('system', c));

    onTeePcm = (buf) => {
      if (!active) return;
      if (!sysReady) {
        sysReady = true;
        sysGapMs = Math.max(0, now() - startedAtMs - systemChunkMs);
        if (sysGapMs > 50) sysAcc.padSilence(sysGapMs);
      }
      systemLevel = rms(buf);
      if (systemLevel > 0.005) { lastSystemPcmMs = now(); gotSystemPcm = true; }
      sysAcc.push(buf);
    };
    onTeeError = (err) => {
      const msg = err && err.message ? err.message : 'unbekannter Fehler';
      const m = msg.toLowerCase();
      if (m.includes('permission') || m.includes('berechtigung') || m.includes('not authorized') || m.includes('tcc')) permissionDenied = true;
      else systemAudioError = msg;
    };
    onTeeLog = () => {};
    audioTee.on('pcm', onTeePcm);
    audioTee.on('error', onTeeError);
    audioTee.on('log', onTeeLog);
    audioTee.start({ sampleRate, chunkDurationMs: systemChunkMs, excludeProcesses: excludePid ? [excludePid] : undefined });

    if (callDetector && callDetector.isSupported) {
      callDetectorRan = true;
      onDetectorState = (a) => onCallState(a);
      onDetectorError = () => { callDetectorRan = false; };
      callDetector.on('call-state', onDetectorState);
      callDetector.on('error', onDetectorError);
      try { callDetector.start(); } catch { callDetectorRan = false; }
    }

    overlayWin = showOverlay() || null;
    _emit('meeting:started', { id: sessionId, callActive });
    _emitUpdated(sessionId, 'recording');
    healthTimer = setInterval(_emitHealth, 1000);
    return { id: sessionId };
  }

  /** Renderer meldet den Wandzeit-Stempel des ersten Mikro-Samples (vor dem ersten PCM). */
  function onMicCaptureStarted({ firstSampleAtMs } = {}) {
    if (!active || micReady || !micAcc) return;
    micReady = true;
    const t = typeof firstSampleAtMs === 'number' ? firstSampleAtMs : now();
    micGapMs = Math.max(0, t - startedAtMs);
    if (micGapMs > 50) micAcc.padSilence(micGapMs);
    _emit('meeting:capture-ready', { id: sessionId, micGapMs });
  }

  function onMicPcm(buf) {
    if (!active || !micAcc) return;
    if (!micReady) {
      // Kein Start-Stempel erhalten (alter Renderer) → aus Ankunftszeit schätzen
      onMicCaptureStarted({ firstSampleAtMs: now() - (buf.length / 2 / sampleRate) * 1000 });
    }
    micLevel = rms(buf);
    micAcc.push(buf);
  }

  function onMicLevel(lvl) { if (typeof lvl === 'number') micLevel = lvl; }

  /** Windows-Loopback: System-PCM kommt aus dem Renderer. */
  function onSystemPcm(buf) { if (onTeePcm) onTeePcm(buf); }

  /** Renderer bestätigt: Restpuffer gesendet, Capture gestoppt. */
  function onCaptureFlushed() { if (captureFlushResolve) { captureFlushResolve(); captureFlushResolve = null; } }

  function _requestCaptureFlush(id) {
    return new Promise((resolve) => {
      let done = false;
      const finish = () => { if (!done) { done = true; clearTimeout(timer); resolve(); } };
      captureFlushResolve = finish;
      const timer = setTimeout(finish, captureStopTimeoutMs);
      _emit('meeting:capture-stop', { id });
    });
  }

  function _concatChannel(id, channel) {
    const files = meetingStore.listChunkFiles(id, channel);
    if (!files.length) return null;
    const out = path.join(meetingStore.meetingDir(id), `audio_${channel}.wav`);
    concatWavFiles(files, out, { sampleRate, channels: 1 });
    return out;
  }

  function _chunkBoundariesFromFiles(id) {
    const ends = [];
    let acc = 0;
    for (const f of meetingStore.listChunkFiles(id, 'mic')) {
      try { acc += Math.max(0, fs.statSync(f).size - 44) / 2 / sampleRate; ends.push(Math.round(acc * 10) / 10); } catch { /* egal */ }
    }
    return ends;
  }

  async function stop() {
    if (!active || stopping) return { id: null };
    stopping = true; // blockiert start()/erneutes stop(); onMicPcm nimmt Restpuffer noch an
    const id = sessionId;
    try {
      if (healthTimer) { clearInterval(healthTimer); healthTimer = null; }
      // Renderer: Restpuffer senden + Tracks stoppen (Ack oder Timeout), erst dann flushen
      await _requestCaptureFlush(id);
      active = false;
      micAcc.flush();
      sysAcc.flush();
      audioTee.stop();
      if (onTeePcm) audioTee.removeListener('pcm', onTeePcm);
      if (onTeeError) audioTee.removeListener('error', onTeeError);
      if (onTeeLog) audioTee.removeListener('log', onTeeLog);
      if (callDetector) {
        try { callDetector.stop(); } catch { /* best effort */ }
        if (onDetectorState) callDetector.removeListener('call-state', onDetectorState);
        if (onDetectorError) callDetector.removeListener('error', onDetectorError);
      }

      try { _concatChannel(id, 'mic'); _concatChannel(id, 'system'); } catch { diskError = true; }

      const durationMs = now() - startedAtMs;
      const remote = systemIsRemote();
      try {
        meetingStore.saveTranscript(id, { segments: [], language: store.get('language') || 'de' });
        meetingStore.finalizeIndex(id, {
          status: 'processing',
          durationMs,
          title: new Date(startedAtMs).toLocaleString('de-DE'),
          audioExpiresAt: new Date(now() + RETENTION_MS).toISOString(),
          systemRemote: remote,
          callDetected: callDetectedEver,
          captureStartGapMs: { mic: Math.round(micGapMs), system: Math.round(sysGapMs) },
          chunkBoundariesSec: micChunkEnds.slice(),
          analysisAttempts: 0,
          analysisError: diskError ? 'Speicherproblem während der Aufnahme' : null,
        });
      } catch { /* Disk best effort */ }

      _emit('meeting:stopped', { id });
      _emitUpdated(id, 'processing');
      hideOverlay(overlayWin);
      overlayWin = null;
    } finally {
      sessionId = null;
      stopping = false;
    }
    enqueue(id);
    return { id };
  }

  // ---------------- Phase 2: serielle Auswertung ----------------
  const queue = [];
  let running = false;
  let idleResolvers = [];

  function enqueue(id) {
    if (!id || queue.includes(id)) return;
    queue.push(id);
    _drain();
  }
  function whenIdle() {
    if (!running && queue.length === 0) return Promise.resolve();
    return new Promise((r) => idleResolvers.push(r));
  }
  async function _drain() {
    if (running) return;
    running = true;
    try {
      while (queue.length) {
        const id = queue.shift();
        try { await processMeeting(id); } catch (e) {
          try { meetingStore.finalizeIndex(id, { status: 'failed', analysisError: describeError(e) }); } catch { /* egal */ }
          _emitUpdated(id, 'failed');
        }
      }
    } finally {
      running = false;
      const rs = idleResolvers; idleResolvers = [];
      rs.forEach((r) => r());
    }
  }

  async function processMeeting(id) {
    const full = meetingStore.get(id);
    if (!full) return; // gelöscht, während es in der Warteschlange stand
    const entry = full.index;
    const attempts = (entry.analysisAttempts || 0) + 1;
    meetingStore.finalizeIndex(id, { status: 'processing', analysisAttempts: attempts, analysisError: null, progress: 'Auswertung startet …' });
    _emitUpdated(id, 'processing');

    let micPath = meetingStore.audioPath(id, 'mic');
    if (!micPath) { try { micPath = _concatChannel(id, 'mic'); } catch { /* egal */ } }
    let sysPath = entry.systemRemote ? meetingStore.audioPath(id, 'system') : null;
    if (entry.systemRemote && !sysPath) { try { sysPath = _concatChannel(id, 'system'); } catch { /* egal */ } }
    if (!micPath && !sysPath) {
      meetingStore.finalizeIndex(id, { status: 'failed', analysisError: 'Keine Aufnahme gefunden (Audio fehlt oder wurde bereits gelöscht)', progress: null });
      _emitUpdated(id, 'failed');
      return;
    }
    if (!micPath) { micPath = sysPath; sysPath = null; } // nur System-Spur vorhanden → als Hauptspur
    const boundaries = Array.isArray(entry.chunkBoundariesSec) && entry.chunkBoundariesSec.length ? entry.chunkBoundariesSec : _chunkBoundariesFromFiles(id);
    const language = (full.transcript && full.transcript.language) || store.get('language') || 'de';

    let result = null; let analysis = null; let analysisError = null;
    const geminiKey = store.get('geminiApiKey');
    if (geminiKey) {
      try {
        result = await analyzeAudio({
          micWavPath: micPath, systemWavPath: sysPath, chunkBoundariesSec: boundaries, apiKey: geminiKey, fetchImpl, sleep, language,
          maxWindowSeconds: analysisWindowSeconds,
          onProgress: (p) => {
            const txt = p.stage === 'retry' ? `Warte auf Gemini (Abschnitt ${p.windowIndex + 1}/${p.windowCount}) …` : `Auswertung Abschnitt ${p.windowIndex + 1} von ${p.windowCount} …`;
            try { meetingStore.finalizeIndex(id, { progress: txt }); } catch { /* egal */ }
            _emitUpdated(id, 'processing', { progress: txt });
          },
        });
        analysis = 'gemini';
      } catch (e) { analysisError = 'Gemini: ' + describeError(e); }
    } else {
      analysisError = 'Kein Gemini-Key hinterlegt';
    }
    if (!result) {
      const groqKey = store.get('groqApiKey');
      if (groqKey) {
        try {
          try { meetingStore.finalizeIndex(id, { progress: 'Fallback: Groq Whisper (ohne Sprechertrennung) …' }); } catch { /* egal */ }
          result = await fallbackAnalyze({ micWavPath: micPath, systemWavPath: sysPath, apiKey: groqKey, language, fetchImpl, sampleRate });
          analysis = 'groq-fallback';
        } catch (e2) { analysisError = `${analysisError} · Groq: ${describeError(e2)}`; }
      } else {
        analysisError = `${analysisError} · kein Groq-Key für den Fallback`;
      }
    }
    if (!result) {
      meetingStore.finalizeIndex(id, { status: 'failed', analysisError, progress: null });
      _emitUpdated(id, 'failed');
      return;
    }

    const segments = result.segments || [];
    meetingStore.saveTranscript(id, { segments, language, speakers: result.speakers || [] });
    const speakerNames = [...new Set(segments.map((s) => s.speaker))];
    const preview = (segments[0] && segments[0].text ? segments[0].text : '').slice(0, 120);
    const firstSentence = (segments.find((s) => (s.text || '').trim().length > 8)?.text || '').trim().slice(0, 70);
    const title = firstSentence || entry.title;
    meetingStore.finalizeIndex(id, {
      status: 'ready', analysis, analysisError, progress: segments.length ? 'Bericht wird erstellt …' : null,
      speakerCount: speakerNames.length || 1, speakerNames, preview, title, analysisModel: result.model || null,
    });
    _emitUpdated(id, 'ready');

    // Bericht (best effort; Kontingent-Fehler verständlich merken)
    const text = transcriptToText(segments);
    if (text.trim()) {
      try {
        const summary = await summarize(text, { ...llmConfig(), language });
        meetingStore.saveSummary(id, summary);
        const sumTitle = (summary.titel || summary.kurzfassung || '').slice(0, 60);
        meetingStore.finalizeIndex(id, { hasSummary: true, title: sumTitle || title, summaryError: null, progress: null });
      } catch (e) {
        try { meetingStore.finalizeIndex(id, { summaryError: e && e.code === 'rate_limit' ? 'rate_limit' : 'error', progress: null }); } catch { /* egal */ }
      }
    } else {
      meetingStore.finalizeIndex(id, { progress: null });
    }
    _emitUpdated(id, 'ready');

    // Chunk-Dateien (Absturzsicherung) sind nach erfolgreicher Auswertung redundant
    try { fs.rmSync(path.join(meetingStore.meetingDir(id), 'chunks'), { recursive: true, force: true }); } catch { /* egal */ }
    try { cleanRetention(meetingStore, { now: now() }); } catch { /* egal */ }
  }

  /** Beim App-Start: unterbrochene Aufnahmen/Auswertungen wieder aufnehmen. */
  function resumePending() {
    const resumed = [];
    for (const entry of meetingStore.list()) {
      if (!entry || (entry.status !== 'recording' && entry.status !== 'processing')) continue;
      if ((entry.analysisAttempts || 0) >= MAX_ANALYSIS_ATTEMPTS) {
        try { meetingStore.finalizeIndex(entry.id, { status: 'failed', analysisError: entry.analysisError || 'Auswertung mehrfach abgebrochen', progress: null }); } catch { /* egal */ }
        continue;
      }
      if (entry.status === 'recording') {
        // Absturz während der Aufnahme: aus den Chunks retten
        let mic = null; let sys = null;
        try { mic = _concatChannel(entry.id, 'mic'); sys = _concatChannel(entry.id, 'system'); } catch { /* egal */ }
        if (!mic && !sys) {
          try { meetingStore.finalizeIndex(entry.id, { status: 'failed', analysisError: 'Aufnahme abgebrochen, keine Audiodaten gefunden' }); } catch { /* egal */ }
          continue;
        }
        const durationMs = Math.round(Math.max(mic ? wavDurationSec(mic, sampleRate) : 0, sys ? wavDurationSec(sys, sampleRate) : 0) * 1000);
        const mode = store.get('systemAudioMode') || 'auto';
        try {
          meetingStore.finalizeIndex(entry.id, {
            status: 'processing', durationMs,
            audioExpiresAt: entry.audioExpiresAt || new Date(now() + RETENTION_MS).toISOString(),
            systemRemote: mode === 'always' ? true : mode === 'never' ? false : !!entry.systemRemote,
            chunkBoundariesSec: _chunkBoundariesFromFiles(entry.id),
            analysisError: 'Aufnahme wurde unterbrochen (App beendet) — Audio bis dahin gerettet',
          });
        } catch { /* egal */ }
      }
      enqueue(entry.id);
      resumed.push(entry.id);
    }
    return resumed;
  }

  /** „Neu auswerten“ (Gemini erneut, Fallback Groq) — braucht vorhandenes Audio. */
  function reanalyze(id) {
    const full = meetingStore.get(id);
    if (!full) return { error: 'not_found' };
    if (!full.audio.mic && !full.audio.system) return { error: 'no_audio' };
    try { meetingStore.finalizeIndex(id, { status: 'processing', analysisAttempts: 0, analysisError: null, summaryError: null }); } catch { /* egal */ }
    _emitUpdated(id, 'processing');
    enqueue(id);
    return { ok: true };
  }

  async function regenerateSummary(id) {
    const full = meetingStore.get(id);
    if (!full) return null;
    const text = transcriptToText(full.transcript.segments || []);
    if (!text.trim()) return null;
    let summary;
    try {
      summary = await summarize(text, { ...llmConfig(), language: (full.transcript.language) || store.get('language') });
    } catch (e) {
      if (e && e.code === 'rate_limit') return { error: 'rate_limit' };
      throw e;
    }
    meetingStore.saveSummary(id, summary);
    const sumTitle = (summary.titel || summary.kurzfassung || '').slice(0, 60);
    meetingStore.finalizeIndex(id, sumTitle ? { hasSummary: true, title: sumTitle, summaryError: null } : { hasSummary: true, summaryError: null });
    _emitUpdated(id, 'ready');
    return summary;
  }

  function runRetention() {
    try { return cleanRetention(meetingStore, { now: now() }); } catch { return []; }
  }

  function isActive() { return active && !stopping; }

  function getStatus() {
    return { active, id: sessionId, callActive, micReady };
  }

  function onCallState(activeFlag) {
    callActive = !!activeFlag;
    if (callActive) callDetectedEver = true;
    if (active) _emit('meeting:call-state', { active: callActive });
    return callActive;
  }

  return {
    start, stop, isActive, getStatus, onCallState,
    onMicPcm, onMicLevel, onMicCaptureStarted, onSystemPcm, onCaptureFlushed,
    processMeeting, enqueue, whenIdle, resumePending, reanalyze, regenerateSummary, runRetention,
  };
}

module.exports = { createMeetingController, transcriptToText, speakerLabel };
