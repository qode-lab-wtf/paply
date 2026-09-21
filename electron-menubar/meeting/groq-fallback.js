'use strict';
// Fallback-Auswertung ohne Sprechertrennung: Groq Whisper über die gespeicherten WAV-Spuren in
// 30-s-Fenstern (positionsweise gelesen, kein Ganzdatei-Read). Wird genutzt, wenn Gemini nicht
// verfügbar ist (kein Key, Kontingent erschöpft, dauerhafter Fehler). Mikro → „Sprecher 1“,
// System (nur wenn als Gegenstelle gewertet) → „Gegenstelle“; Lautsprecher-Echo per Zeitüberlappung
// gefiltert. CommonJS.

const { encodeWav, readWavSlice, wavDurationSec } = require('../audio/wav-encoder');
const { maxFrameRms } = require('../audio/pcm-utils');
const { TranscriptionQueue } = require('./transcription-queue');
const { mergeSegments, suppressBleed } = require('./transcript-merger');

/**
 * @param {{ micWavPath:string, systemWavPath?:string|null, apiKey:string, language?:string,
 *           fetchImpl?:Function, windowSeconds?:number, sampleRate?:number, speechGate?:number,
 *           onProgress?:Function }} opts
 * @returns {Promise<{ segments:object[], model:string }>}
 */
async function transcribeWithGroq(opts) {
  const { micWavPath, systemWavPath = null, apiKey, language = 'de', fetchImpl, windowSeconds = 30, sampleRate = 16000, speechGate = 0.0008, onProgress } = opts;
  if (!apiKey) { const e = new Error('Groq-Key fehlt'); e.code = 'no_key'; throw e; }
  const lastText = { mic: '', system: '' };
  const mic = []; const sys = [];
  let errors = 0;
  const q = new TranscriptionQueue({ apiKey, language, fetchImpl, getPrompt: (ch) => lastText[ch] || '' });
  q.on('segments', ({ channel, segments }) => {
    (channel === 'mic' ? mic : sys).push(...segments);
    const added = segments.map((s) => s.text).join(' ');
    lastText[channel] = ((lastText[channel] || '') + ' ' + added).slice(-800).trimStart();
  });
  q.on('error', () => { errors++; });

  let total = 0;
  for (const [channel, wavPath] of [['mic', micWavPath], ['system', systemWavPath]]) {
    if (!wavPath) continue;
    const dur = wavDurationSec(wavPath, sampleRate);
    for (let off = 0; off < dur; off += windowSeconds) {
      const pcm = readWavSlice(wavPath, off, Math.min(dur, off + windowSeconds), sampleRate);
      if (pcm.length === 0) continue;
      if (maxFrameRms(pcm, { sampleRate }) >= speechGate) {
        q.enqueue({ channel, wavBuffer: encodeWav(pcm, { sampleRate, channels: 1 }), tOffset: off });
        total++;
      }
    }
  }
  if (onProgress) onProgress({ stage: 'groq', windows: total });
  await q.idle();
  if (total > 0 && errors >= total) { const e = new Error('Groq Whisper: alle Fenster fehlgeschlagen'); e.code = 'groq_failed'; throw e; }

  const micS = mic.map((s) => ({ ...s, speaker: 'Sprecher 1' }));
  const sysS = sys.map((s) => ({ ...s, speaker: 'Gegenstelle' }));
  const merged = mergeSegments(sysS.length ? suppressBleed(micS, sysS) : micS, sysS);
  return { segments: merged, model: 'whisper-large-v3 (Groq)' };
}

module.exports = { transcribeWithGroq };
