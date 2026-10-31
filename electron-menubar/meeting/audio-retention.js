'use strict';
// Ton nach gespeicherter Auswertung sofort löschen, sonst spätestens 30 Tage ab Stopp.
const fs = require('node:fs');
const path = require('node:path');

const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const AUDIO_FILES = ['audio_mic.wav', 'audio_system.wav', 'audio_mic.opus', 'audio_system.opus'];

/** Ablaufzeitpunkt eines Index-Eintrags (ms) — reine Funktion. */
function expiresAtMs(entry) {
  const start = Date.parse(entry?.startTime);
  const stop = Date.parse(entry?.stoppedAt);
  // Alte audioExpiresAt-Werte enthielten die frühere 7-Tage-Frist: neu berechnen.
  const base = Number.isFinite(stop) ? stop : start + (Number(entry?.durationMs) || 0);
  return Number.isFinite(base) ? base + RETENTION_MS : Infinity;
}

/** Löscht Audio-Dateien + chunks/ eines Meeting-Ordners. Liefert true, wenn etwas gelöscht wurde. */
function deleteAudioFiles(meetingDir) {
  let any = false;
  for (const f of AUDIO_FILES) {
    const p = path.join(meetingDir, f);
    try { if (fs.existsSync(p)) { fs.rmSync(p); any = true; } } catch { /* best effort */ }
  }
  const chunks = path.join(meetingDir, 'chunks');
  try { if (fs.existsSync(chunks)) { fs.rmSync(chunks, { recursive: true, force: true }); any = true; } } catch { /* best effort */ }
  return any;
}

/**
 * Räumt abgelaufene Audio-Dateien auf.
 * @param {{ list:Function, meetingDir:Function, finalizeIndex:Function }} meetingStore
 * @param {{ now?:number }} opts
 * @returns {string[]} IDs, deren Audio gelöscht wurde
 */
function cleanExpiredAudio(meetingStore, { now = Date.now() } = {}) {
  const deleted = [];
  for (const entry of meetingStore.list()) {
    if (!entry || entry.audioDeleted) continue;
    if (entry.status === 'recording') continue;
    const expires = expiresAtMs(entry);
    const segments = meetingStore.loadTranscript(entry.id)?.segments;
    const complete = (entry.status === 'ready' || !entry.status) && Array.isArray(segments) && segments.some(s => typeof s.text === 'string' && s.text.trim());
    if (!complete && expires > now) {
      if (Number.isFinite(expires)) meetingStore.finalizeIndex(entry.id, { audioExpiresAt: new Date(expires).toISOString() });
      continue;
    }
    const dir = meetingStore.meetingDir(entry.id);
    const had = deleteAudioFiles(dir);
    const stillThere = [...AUDIO_FILES, 'chunks'].some((f) => fs.existsSync(path.join(dir, f)));
    if (!stillThere) {
      try { meetingStore.finalizeIndex(entry.id, { audioDeleted: true, ...(entry.status === 'processing' ? { status: 'failed', progress: null, analysisError: 'Auswertung abgelaufen · Ton nach 30 Tagen gelöscht' } : {}) }); } catch { /* best effort */ }
      if (had) deleted.push(entry.id);
    }
  }
  return deleted;
}

module.exports = { cleanExpiredAudio, expiresAtMs, deleteAudioFiles, RETENTION_MS };
