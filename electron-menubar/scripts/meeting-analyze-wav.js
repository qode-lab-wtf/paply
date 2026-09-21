#!/usr/bin/env node
'use strict';
// Spike/Prüfwerkzeug: wertet eine vorhandene Aufnahme (16 kHz, mono, 16 bit WAV) genauso aus wie
// die App nach dem Stop — Gemini-Audio (Sprecher + Wortlaut + Zeitmarken), danach Bericht v2.
//
//   GEMINI_API_KEY=… node scripts/meeting-analyze-wav.js audio_mic.wav [audio_system.wav] [--report] [--out ergebnis.json]
//
// Optional GROQ_API_KEY für den Bericht-Fallback. Keine App, kein Electron nötig.

const fs = require('node:fs');
const path = require('node:path');
const { transcribeWithGemini } = require('../meeting/gemini-audio');
const { generateMeetingSummary } = require('../meeting/summary');
const { wavInfo, wavDurationSec } = require('../audio/wav-encoder');

function fmt(sec) { const s = Math.floor(sec); return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`; }

async function main() {
  const args = process.argv.slice(2);
  const wantReport = args.includes('--report');
  const outIdx = args.indexOf('--out');
  const outPath = outIdx >= 0 ? args[outIdx + 1] : null;
  const files = args.filter((a, i) => !a.startsWith('--') && !(outIdx >= 0 && i === outIdx + 1));
  const apiKey = process.env.GEMINI_API_KEY;
  if (!files.length || !apiKey) {
    console.error('Aufruf: GEMINI_API_KEY=… node scripts/meeting-analyze-wav.js mic.wav [system.wav] [--report] [--out datei.json]');
    process.exit(2);
  }
  for (const f of files) {
    const info = wavInfo(f);
    if (info.format !== 1 || info.channels !== 1 || info.sampleRate !== 16000 || info.bitsPerSample !== 16) {
      console.error(`${path.basename(f)}: erwartet PCM 16 kHz mono 16 bit, gefunden ${JSON.stringify(info)}. Umwandeln z. B. mit: ffmpeg -i in.wav -ac 1 -ar 16000 -sample_fmt s16 out.wav`);
      process.exit(2);
    }
    console.error(`${path.basename(f)}: ${fmt(wavDurationSec(f))} min`);
  }
  const t0 = Date.now();
  const r = await transcribeWithGemini({
    micWavPath: files[0], systemWavPath: files[1] || null, apiKey,
    onProgress: (p) => console.error(`… ${p.stage} Abschnitt ${p.windowIndex + 1}/${p.windowCount}`),
  });
  console.error(`Transkript: ${r.segments.length} Segmente, ${r.speakers.length} Sprecher, Modell ${r.model}, ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  console.log('');
  for (const s of r.speakers) console.log(`# ${s.label} (${s.channel}): ${s.beschreibung}`);
  console.log('');
  for (const s of r.segments) console.log(`[${fmt(s.tStart)}] ${s.speaker}${s.unsicher ? ' (?)' : ''}: ${s.text}`);

  let summary = null;
  if (wantReport) {
    const text = r.segments.map((s) => `[${fmt(s.tStart)}] ${s.speaker}: ${s.text}`).join('\n');
    const t1 = Date.now();
    summary = await generateMeetingSummary(text, { geminiApiKey: apiKey, groqApiKey: process.env.GROQ_API_KEY, language: 'de' });
    console.error(`Bericht: Modell ${summary.model}, ${((Date.now() - t1) / 1000).toFixed(1)} s`);
    console.log('\n==== BERICHT ====');
    console.log(JSON.stringify(summary, null, 2));
  }
  if (outPath) fs.writeFileSync(outPath, JSON.stringify({ transcript: r, summary }, null, 2));
}

main().catch((e) => { console.error('Fehler:', e && e.message ? e.message : e); process.exit(1); });
