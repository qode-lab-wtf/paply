'use strict';
// Audio-Aufbewahrung: Original-Audio (WAV/Opus) und Chunk-Ordner eines Meetings werden 7 Tage nach
// dem Stop gelöscht; Transkript und Bericht bleiben. Läuft beim App-Start, nach jeder Auswertung und
// täglich. Meetings in Verarbeitung werden übersprungen. Alte Einträge ohne audioExpiresAt gelten
// als „startTime + 7 Tage“. CommonJS.

const fs = require('node:fs');
const path = require('node:path');

const RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
const AUDIO_FILES = ['audio_mic.wav', 'audio_system.wav', 'audio_mic.opus', 'audio_system.opus'];

/** Ablaufzeitpunkt eines Index-Eintrags (ms) — reine Funktion. */
function expiresAtMs(entry) {
  if (entry && entry.audioExpiresAt) { const t = Date.parse(entry.audioExpiresAt); if (Number.isFinite(t)) return t; }
  const st = entry && Date.parse(entry.startTime);
  return Number.isFinite(st) ? st + RETENTION_MS : 0;
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
    if (entry.status === 'processing' || entry.status === 'recording') continue;
    if (expiresAtMs(entry) > now) continue;
    const dir = meetingStore.meetingDir(entry.id);
    const had = deleteAudioFiles(dir);
    const stillThere = AUDIO_FILES.some((f) => fs.existsSync(path.join(dir, f)));
    if (!stillThere) {
      try { meetingStore.finalizeIndex(entry.id, { audioDeleted: true }); } catch { /* best effort */ }
      if (had) deleted.push(entry.id);
    }
  }
  return deleted;
}

module.exports = { cleanExpiredAudio, expiresAtMs, deleteAudioFiles, RETENTION_MS };
