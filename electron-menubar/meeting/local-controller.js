'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { ChunkAccumulator } = require('./chunk-accumulator');
const { encodeWav } = require('../audio/wav-encoder');
const { rms } = require('../audio/pcm-utils');
const { createLocalPipeline } = require('./local-pipeline');
const { cleanExpiredAudio } = require('./local-retention');
function createLocalController({ meetingStore: store, audioTee, getOverlayWindow, getMainWindow, configPath, baseDir, now = Date.now, pipeline: injected }) {
  let active = false, stopping = false, id = null, startMs = 0, overlay, timer, stopResolve;
  let chunkFiles = { mic: [], system: [] };
  let pendingByte = { mic: Buffer.alloc(0), system: Buffer.alloc(0) };
  let micAcc, sysAcc, tracks = {}, micLevel = 0, systemLevel = 0, error = null, listeners;
  const emit = (channel, value) => { for (const win of [overlay, getMainWindow?.()]) if (win && !win.isDestroyed?.()) win.webContents.send(channel, value); };
  const pipeline = injected || createLocalPipeline({ store, configPath, emit, now });
  function chunk(channel, { pcm, seq }) {
    const file = store.chunkPath(id, channel, seq), tmp = file + '.tmp';
    fs.writeFileSync(tmp, encodeWav(pcm), { mode: 0o600 }); fs.renameSync(tmp, file);
    chunkFiles[channel].push(file);
    if (chunkFiles[channel].length % 15 === 0) {
      pipeline.preview?.(id, channel, chunkFiles[channel].slice(-15), (tracks[channel]?.offsetSeconds || 0) + (chunkFiles[channel].length - 15) * 2);
    }
  }
  function ingest(channel, buffer, meta) {
    if (!active || (meta?.sessionId && meta.sessionId !== id)) return;
    try {
      buffer = Buffer.concat([pendingByte[channel], buffer]);
      pendingByte[channel] = buffer.length % 2 ? buffer.subarray(-1) : Buffer.alloc(0);
      if (buffer.length % 2) buffer = buffer.subarray(0, -1);
      if (!buffer.length) return;
      const duration = buffer.length / 32000;
      if (meta?.endAtMs && !Number.isFinite(meta.endAtMs)) throw new Error('Ungültige Aufnahmezeit');
      if (!tracks[channel]) {
        tracks[channel] = { offsetSeconds: Math.max(0, ((meta?.endAtMs || now()) - startMs) / 1000 - duration), timing: meta?.endAtMs ? 'audio-context-clock' : 'first-arrival-estimate' };
        store.writeState(id, { tracks });
      }
      const accumulator = channel === 'mic' ? micAcc : sysAcc;
      if (meta?.endAtMs && tracks[channel].receivedSamples !== undefined) {
        const expectedEnd = startMs / 1000 + tracks[channel].offsetSeconds + tracks[channel].receivedSamples / 16000 + duration;
        const gap = meta.endAtMs / 1000 - expectedEnd;
        if (meta.endAtMs > now() + 5000) throw new Error('Aufnahmezeit liegt in der Zukunft');
        if (gap > .1) {
          let missing = Math.round(gap * 16000);
          tracks[channel].gaps = [...(tracks[channel].gaps || []), { start: expectedEnd - duration - startMs / 1000, seconds: gap }];
          tracks[channel].receivedSamples += missing;
          while (missing > 0) { const count = Math.min(missing, 32000); accumulator.push(Buffer.alloc(count * 2)); missing -= count; }
          store.writeState(id, { tracks, captureWarning: 'Aufnahmelücke erkannt; Zeitachse mit Stille erhalten.' });
        }
      }
      accumulator.push(buffer);
      tracks[channel].receivedSamples = (tracks[channel].receivedSamples || 0) + buffer.length / 2;
      if (channel === 'mic') micLevel = rms(buffer); else systemLevel = rms(buffer);
    } catch (e) { error = e.message; store.writeState(id, { error }); }
  }
  function start() {
    if (active || stopping) return { id };
    // Fail before recording when runtime configuration is missing, never switch to cloud.
    cleanExpiredAudio(baseDir, now());
    startMs = now(); id = store.create(new Date(startMs).toISOString());
    pendingByte = { mic: Buffer.alloc(0), system: Buffer.alloc(0) };
    tracks = {}; chunkFiles = { mic: [], system: [] }; error = null; micLevel = 0; systemLevel = 0;
    store.writeState(id, { schemaVersion: 2, status: 'recording', captureStartedAt: startMs,
      retentionPolicy: 'seven-days-from-capture', audioExpiresAt: startMs + 7 * 86400000, tracks, completed: {}, models: {} });
    micAcc = new ChunkAccumulator({ sampleRate: 16000, windowSeconds: 2, onChunk: c => chunk('mic', c) });
    sysAcc = new ChunkAccumulator({ sampleRate: 16000, windowSeconds: 2, onChunk: c => chunk('system', c) });
    active = true;
    listeners = { pcm: b => ingest('system', b), error: e => { error = e.message; store.writeState(id, { captureWarning: error }); } };
    audioTee.on('pcm', listeners.pcm); audioTee.on('error', listeners.error);
    audioTee.start({ sampleRate: 16000, chunkDurationMs: 200 });
    overlay = getOverlayWindow?.();
    emit('meeting:started', { id, diarization: true, callActive: false, local: true });
    timer = setInterval(() => {
      const warning = !tracks.mic && now() - startMs > 5000 ? 'Noch kein Mikrofonton empfangen – Berechtigung oder Gerät prüfen' : null;
      emit('meeting:status', { color: error ? 'red' : warning ? 'yellow' : 'green', reason: error || warning || 'Lokal gespeichert · Auswertung nach Stop', durationMs: now() - startMs, micLevel, systemLevel });
    }, 1000);
    return { id };
  }
  function acknowledgeStop(sessionId) { if (sessionId === id) stopResolve?.(); }
  async function stop() {
    if (!active || stopping) return { id: null };
    stopping = true; const capturedId = id, stoppedAt = now();
    try {
      // Ask renderer to send the partial final audio block before acknowledging stop.
      const micStopped = new Promise(resolve => {
        const deadline = setTimeout(() => { store.writeState(capturedId, { captureWarning: 'Mikrofon-Ende nicht bestätigt; letzter Teilblock möglicherweise unvollständig.' }); resolve(); }, 2000);
        stopResolve = () => { clearTimeout(deadline); resolve(); };
        emit('meeting:capture-stop', { id: capturedId });
      });
      // Stop both sources immediately, then wait for their final buffered data.
      const systemStopped = new Promise(resolve => {
        let deadline, forceDeadline;
        const done = () => { clearTimeout(deadline); clearTimeout(forceDeadline); audioTee.removeListener('closed', done); resolve(); };
        deadline = setTimeout(() => { audioTee.stop(true); forceDeadline = setTimeout(done, 1000); }, 1000);
        audioTee.once('closed', done); audioTee.stop();
      });
      await Promise.all([micStopped, systemStopped]);
      stopResolve = null;
      active = false; clearInterval(timer);
      audioTee.removeListener('pcm', listeners.pcm); audioTee.removeListener('error', listeners.error);
      micAcc.flush(); sysAcc.flush();
      const durationMs = stoppedAt - startMs;
      let timingWarning = null;
      for (const track of Object.values(tracks)) {
        track.durationSeconds = (track.receivedSamples || 0) / 16000;
        track.timingUncertain = Math.abs(track.offsetSeconds + track.durationSeconds - durationMs / 1000) > 2;
        if (track.timingUncertain) timingWarning = 'Tonspur und Aufnahmeuhr weichen voneinander ab; zeitliche Zuordnung bitte prüfen.';
      }
      if (timingWarning) store.writeState(capturedId, { captureWarning: timingWarning });
      store.finalizeIndex(capturedId, { durationMs, title: 'Gespräch ' + new Date(startMs).toLocaleString('de-DE') });
      store.writeState(capturedId, { status: 'queued', captureStoppedAt: stoppedAt, tracks });
      pipeline.enqueue(capturedId);
      emit('meeting:stopped', { id: capturedId }); overlay?.hide?.();
      return { id: capturedId };
    } catch (e) {
      store.writeState(capturedId, { status: 'failed', error: e.message }); throw e;
    } finally { clearInterval(timer); stopResolve = null; audioTee.removeListener("pcm", listeners.pcm); audioTee.removeListener("error", listeners.error); active = false; stopping = false; id = null; }
  }
  return { start, stop, acknowledgeStop, isActive: () => active,
    getStatus: () => ({ active, id, diarization: true, callActive: false, local: true }),
    onCaptureError: message => { error = message; if (id) store.writeState(id, { captureWarning: message }); },
    onMicPcm: (buffer, meta) => ingest('mic', buffer, meta), onMicLevel: level => { micLevel = level; },
    setSessionDiarization: () => true,
    retranscribe: sessionId => pipeline.enqueue(sessionId, { force: true }),
    regenerateSummary: async sessionId => { await pipeline.enqueue(sessionId, { reportOnly: true }); return store.get(sessionId)?.summary; },
    resume: () => pipeline.resume(), shutdown: () => pipeline.shutdown(), pipeline,
  };
}
module.exports = { createLocalController };
