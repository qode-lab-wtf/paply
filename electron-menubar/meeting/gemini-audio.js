'use strict';
// Gesprächs-Auswertung per Gemini-Audio-Verständnis: Wortlaut + Sprecher + Zeitmarken in EINEM
// Schritt, aus der Mikrofon-Spur (Raum) und optional der System-Spur (Gegenstelle am Telefon/in
// der Konferenz-App). Ersetzt Groq-Whisper-Chunks + Tonhöhen-Clustering. Kostenlos (Free-Tier),
// keine lokalen Modelle. Lange Aufnahmen werden in Fenster (≤ 25 min) zerlegt, die nacheinander
// verarbeitet werden; die Sprecher-Legende wird von Fenster zu Fenster weitergegeben.
//
// Alle Netzfunktionen nehmen ein injizierbares fetchImpl/sleep (Tests ohne Netz).

const fs = require('node:fs');
const { encodeWav, readWavSlice, wavDurationSec } = require('../audio/wav-encoder');
const { rms } = require('../audio/pcm-utils');
const { uploadFile, deleteFile, GEMINI_BASE } = require('./gemini-files');

const DEFAULT_MODEL = 'gemini-flash-latest';
// Reihenfolge beim Ausweichen: nicht verfügbar (404/400), überlastet (5xx nach Retry) oder Kontingent (429)
// → nächstes Modell. Feste Versionen als Zwischenstufen, weil die -latest-Aliase gemeinsam überlastet sein können.
const FALLBACK_MODELS = ['gemini-3.6-flash', 'gemini-3.5-flash'];
const SWITCH_MODEL_STATUS = new Set([400, 404, 429, 500, 502, 503]);
const INLINE_LIMIT_BYTES = 9 * 1024 * 1024;      // pro Spur inline (Base64), sonst Files API
const RETRY_DELAYS_MS = [5000, 15000];           // 429/5xx-Backoff je Modell, danach nächstes Modell
const MIN_SPLIT_SECONDS = 120;                   // kleiner wird ein Fenster bei MAX_TOKENS nicht mehr geteilt

// ----------------------------- Fensterplanung -----------------------------

/**
 * Zerlegt eine Aufnahme in Fenster ≤ maxSeconds, geschnitten an bereits bekannten Chunk-Grenzen
 * (= Sprechpausen aus dem ChunkAccumulator). Reine Funktion.
 * @param {number[]} boundariesSec  Sekunden-Positionen möglicher Schnitte (Chunk-Enden)
 * @param {number} totalSec         Gesamtlänge
 * @returns {{startSec:number,endSec:number}[]}
 */
function planWindows(boundariesSec, totalSec, { maxSeconds = 1500, minTailSeconds = 20 } = {}) {
  const total = Math.max(0, Number(totalSec) || 0);
  if (total === 0) return [];
  const bounds = [...new Set((boundariesSec || []).map(Number).filter((b) => Number.isFinite(b) && b > 0 && b < total))].sort((a, b) => a - b);
  const windows = [];
  let start = 0;
  while (start < total) {
    const limit = start + maxSeconds;
    let end;
    if (total <= limit) end = total;
    else {
      const cands = bounds.filter((b) => b > start + 1 && b <= limit);
      end = cands.length ? cands[cands.length - 1] : limit;
    }
    windows.push({ startSec: start, endSec: end });
    start = end;
  }
  // Winziger Rest ans vorherige Fenster hängen (spart einen Aufruf)
  if (windows.length > 1) {
    const last = windows[windows.length - 1];
    const prev = windows[windows.length - 2];
    if (last.endSec - last.startSec < minTailSeconds) { prev.endSec = last.endSec; windows.pop(); }
  }
  return windows;
}

// ----------------------------- Prompt + Schema -----------------------------

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    sprecher: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          id: { type: 'STRING' },
          spur: { type: 'STRING', enum: ['A', 'B'] },
          beschreibung: { type: 'STRING' },
        },
        required: ['id', 'spur', 'beschreibung'],
      },
    },
    segmente: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          start: { type: 'NUMBER' },
          ende: { type: 'NUMBER' },
          sprecher: { type: 'STRING' },
          spur: { type: 'STRING', enum: ['A', 'B'] },
          text: { type: 'STRING' },
          unsicher: { type: 'BOOLEAN' },
        },
        required: ['start', 'ende', 'sprecher', 'spur', 'text'],
      },
    },
  },
  required: ['sprecher', 'segmente'],
};

/**
 * Baut den deutschen Transkriptions-Prompt für ein Fenster. Reine Funktion (testbar).
 * @param {{ hasSystem:boolean, windowStartSec:number, windowIndex:number, windowCount:number,
 *           legend:{id:string,spur:string,beschreibung:string}[], language?:string }} p
 */
function buildTranscribePrompt({ hasSystem, windowStartSec = 0, windowIndex = 0, windowCount = 1, legend = [], language = 'de' }) {
  const lines = [];
  lines.push('Du bekommst die Tonaufnahme eines echten Gesprächs (Hauptsprache: ' + (language === 'de' ? 'Deutsch' : language) + ').');
  lines.push('Spur A = Mikrofon des Aufnahmegeräts: die Personen im Raum (Gerätebesitzer und Anwesende, unterschiedlich nah am Mikrofon).');
  if (hasSystem) {
    lines.push('Spur B = Systemaudio des Computers: Gesprächspartner am Telefon bzw. in einer Konferenz-App.');
    lines.push('Beide Spuren beginnen exakt zum selben Zeitpunkt (Sekunde 0) und laufen synchron. Spur A kann leise das Lautsprecher-Echo der Stimmen aus Spur B enthalten.');
  }
  lines.push('');
  lines.push('Aufgabe: vollständiges, wortgetreues Transkript mit Sprecherzuordnung und Zeitmarken als JSON.');
  lines.push('Regeln:');
  lines.push('- Wortgetreu: genau das, was gesagt wurde. Nichts zusammenfassen, nichts umformulieren, nichts auslassen. Nur reine Fülllaute (ähm, äh) und Stottern weglassen. Dialekt in normaler Schreibweise.');
  lines.push('- Jede Äußerung ist ein Segment mit start/ende in Sekunden ab Beginn dieses Abschnitts (Dezimalzahl, z. B. 12.4). Höchstens ca. 20 Sekunden pro Segment; bei jedem Sprecherwechsel ein neues Segment. Chronologisch sortiert.');
  lines.push('- Sprecher: Unterscheide Stimmen nach Klang UND Gesprächslogik (wer antwortet wem, Anrede, Rollen). Neutrale IDs S1, S2, S3 … in Reihenfolge des ersten Auftretens. Keine Namen erfinden. Dieselbe Stimme behält dieselbe ID, auch wenn sie leiser, weiter weg oder undeutlich ist. Lieber wenige echte Sprecher als viele Schein-Sprecher.');
  if (hasSystem) {
    lines.push('- spur: "A", wenn die Äußerung auf Spur A (Mikrofon) gesprochen wurde; "B", wenn auf Spur B. Ist dieselbe Äußerung als Echo auf beiden Spuren zu hören, nur EINMAL mit spur "B" ausgeben. Ein Sprecher gehört immer zu genau einer Spur.');
  } else {
    lines.push('- spur ist immer "A".');
  }
  lines.push('- unsicher: true, wenn Sprecherzuordnung oder Wortlaut unklar sind; sonst false.');
  lines.push('- In "sprecher" jede Stimme kurz charakterisieren (z. B. "männlich, tief, nah am Mikrofon").');
  lines.push('- Enthält der Abschnitt keine Sprache, gib leere Listen zurück. Erfinde keinen Text.');
  if (legend.length) {
    lines.push('');
    lines.push(`Bereits bekannte Stimmen aus früheren Abschnitten derselben Aufnahme (Abschnitt ${windowIndex + 1} von ${windowCount}, beginnt bei ${formatMinSec(windowStartSec)} der Gesamtaufnahme):`);
    for (const s of legend) lines.push(`- ${s.id} (Spur ${s.spur}): ${s.beschreibung}`);
    const next = legend.reduce((m, s) => Math.max(m, parseInt(String(s.id).replace(/\D/g, ''), 10) || 0), 0) + 1;
    lines.push(`Verwende für dieselbe Stimme exakt dieselbe ID. Neue Stimmen bekommen die nächste freie Nummer (ab S${next}). Zeitmarken trotzdem ab 0 für diesen Abschnitt.`);
  } else if (windowCount > 1) {
    lines.push('');
    lines.push(`Dies ist Abschnitt ${windowIndex + 1} von ${windowCount} der Gesamtaufnahme.`);
  }
  return lines.join('\n');
}

function formatMinSec(sec) {
  const s = Math.max(0, Math.floor(sec));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

// ----------------------------- Antwort-Verarbeitung -----------------------------

/** Tolerantes JSON-Parsing (```-Fences, Text drumherum). Wirft bei Unbrauchbarem. */
function parseJsonLoose(text) {
  const t = String(text || '').trim();
  try { return JSON.parse(t); } catch { /* weiter */ }
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (fence) { try { return JSON.parse(fence[1]); } catch { /* weiter */ } }
  const a = t.indexOf('{'); const b = t.lastIndexOf('}');
  if (a >= 0 && b > a) return JSON.parse(t.slice(a, b + 1));
  throw new Error('Gemini-Antwort ist kein JSON');
}

/**
 * Wandelt die Gemini-Antwort eines Fensters in Segmente (absolute Zeiten) um. Reine Funktion.
 * @returns {{ segments:{tStart:number,tEnd:number,speakerId:string,track:'A'|'B',text:string,unsicher:boolean}[],
 *             speakers:{id:string,spur:'A'|'B',beschreibung:string}[] }}
 */
function parseTranscriptResponse(json, { windowStartSec = 0, windowEndSec = Infinity, hasSystem = false } = {}) {
  const obj = typeof json === 'string' ? parseJsonLoose(json) : (json || {});
  const speakers = Array.isArray(obj.sprecher) ? obj.sprecher : [];
  const raw = Array.isArray(obj.segmente) ? obj.segmente : [];
  const winLen = windowEndSec - windowStartSec;
  const segments = [];
  for (const s of raw) {
    if (!s || typeof s !== 'object') continue;
    const text = String(s.text || '').trim();
    if (!text) continue;
    let start = Number(s.start); let end = Number(s.ende != null ? s.ende : s.end);
    if (!Number.isFinite(start)) start = 0;
    if (!Number.isFinite(end) || end < start) end = start + 1;
    if (Number.isFinite(winLen)) { start = Math.min(start, winLen); end = Math.min(end, winLen + 1); }
    const track = hasSystem && s.spur === 'B' ? 'B' : 'A';
    segments.push({
      tStart: round1(windowStartSec + start),
      tEnd: round1(windowStartSec + end),
      speakerId: String(s.sprecher || 'S1').trim() || 'S1',
      track,
      text,
      unsicher: !!s.unsicher,
    });
  }
  segments.sort((x, y) => (x.tStart - y.tStart) || (x.tEnd - y.tEnd));
  return {
    segments,
    speakers: speakers
      .filter((p) => p && p.id)
      .map((p) => ({ id: String(p.id).trim(), spur: hasSystem && p.spur === 'B' ? 'B' : 'A', beschreibung: String(p.beschreibung || '').slice(0, 200) })),
  };
}

function round1(x) { return Math.round(x * 10) / 10; }

/**
 * Spurzuordnung lokal absichern: Gemini weiß nicht sicher, welche Datei ein Segment war. Hat die
 * gewählte Spur im Segmentzeitraum praktisch keine Energie, die andere aber deutlich, wird die Spur
 * korrigiert. Reine Funktion über PCM-Puffer eines Fensters (Zeiten relativ zum Fensterstart).
 */
function correctTracksByEnergy(segments, { micPcm, sysPcm, windowStartSec = 0, sampleRate = 16000, silent = 0.002, loud = 0.01 } = {}) {
  if (!micPcm || !sysPcm) return segments;
  const energy = (pcm, a, b) => {
    const from = Math.max(0, Math.floor((a - windowStartSec) * sampleRate) * 2);
    const to = Math.min(pcm.length, Math.max(from, Math.floor((b - windowStartSec) * sampleRate) * 2));
    return to > from ? rms(pcm.subarray(from, to)) : 0;
  };
  return segments.map((s) => {
    const eMic = energy(micPcm, s.tStart, s.tEnd);
    const eSys = energy(sysPcm, s.tStart, s.tEnd);
    if (s.track === 'A' && eMic < silent && eSys > loud) return { ...s, track: 'B' };
    if (s.track === 'B' && eSys < silent && eMic > loud) return { ...s, track: 'A' };
    return s;
  });
}

function _tokens(text) {
  return String(text).toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter((w) => w.length > 1);
}

/**
 * Lautsprecher-Echo entfernen: ein Mikro-Segment, das zeitgleich (±2 s) mit nahezu gleichem Text
 * auch auf der System-Spur steht, ist die Gegenstelle über den Lautsprecher → nur System behalten.
 */
function dedupeEcho(segments, { windowSec = 2.5, minSimilarity = 0.7 } = {}) {
  const sys = segments.filter((s) => s.track === 'B');
  if (!sys.length) return segments;
  return segments.filter((m) => {
    if (m.track !== 'A') return true;
    const mt = new Set(_tokens(m.text));
    if (mt.size < 3) return true;
    for (const s of sys) {
      if (Math.abs(s.tStart - m.tStart) > windowSec) continue;
      const st = new Set(_tokens(s.text));
      let inter = 0; for (const w of mt) if (st.has(w)) inter++;
      const sim = inter / Math.max(1, Math.min(mt.size, st.size));
      if (sim >= minSimilarity) return false;
    }
    return true;
  });
}

/**
 * Vergibt die endgültigen, neutralen Anzeige-Labels: Mikro-Stimmen „Sprecher 1..N“ (nach erstem
 * Auftreten), System-Stimmen „Gegenstelle“, „Gegenstelle 2“… Kanal je Sprecher = Mehrheit seiner
 * Segmente. Reine Funktion. Gibt MeetingSegment-kompatible Objekte zurück.
 */
function assignLabels(segments, legend = []) {
  const byId = new Map(); // speakerId → { first, a, b }
  segments.forEach((s, i) => {
    const e = byId.get(s.speakerId) || { first: i, a: 0, b: 0 };
    if (s.track === 'B') e.b++; else e.a++;
    byId.set(s.speakerId, e);
  });
  const ids = [...byId.keys()].sort((x, y) => byId.get(x).first - byId.get(y).first);
  const label = new Map();
  let mic = 0; let sys = 0;
  for (const id of ids) {
    const e = byId.get(id);
    const isSys = e.b > e.a;
    if (isSys) { sys++; label.set(id, sys === 1 ? 'Gegenstelle' : `Gegenstelle ${sys}`); }
    else { mic++; label.set(id, `Sprecher ${mic}`); }
  }
  const out = segments.map((s) => {
    const e = byId.get(s.speakerId);
    const channel = e.b > e.a ? 'system' : 'mic';
    const o = { tStart: s.tStart, tEnd: s.tEnd, speaker: label.get(s.speakerId), channel, text: s.text };
    if (s.unsicher) o.unsicher = true;
    return o;
  });
  const speakers = ids.map((id) => {
    const l = legend.find((x) => x.id === id);
    return { id, label: label.get(id), channel: byId.get(id).b > byId.get(id).a ? 'system' : 'mic', beschreibung: l ? l.beschreibung : '' };
  });
  return { segments: out, speakers };
}

// ----------------------------- Gemini-Aufruf -----------------------------

function _sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function _generate({ apiKey, model, parts, fetchImpl }) {
  const fetch = fetchImpl || globalThis.fetch;
  const res = await fetch(`${GEMINI_BASE}/v1beta/models/${model}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
    body: JSON.stringify({
      contents: [{ role: 'user', parts }],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: 65536,
        responseMimeType: 'application/json',
        responseSchema: RESPONSE_SCHEMA,
        thinkingConfig: { thinkingBudget: 0 },
      },
    }),
  });
  if (!res.ok) {
    let detail = '';
    try { detail = (await res.text()).slice(0, 300); } catch { /* egal */ }
    const e = new Error(`Gemini HTTP ${res.status}${detail ? ': ' + detail : ''}`);
    e.status = res.status;
    if (res.status === 429) e.code = 'rate_limit';
    throw e;
  }
  const data = await res.json();
  const cand = data && data.candidates && data.candidates[0];
  const text = ((cand && cand.content && cand.content.parts) || []).map((p) => (p && p.text) || '').join('');
  const blocked = data && data.promptFeedback && data.promptFeedback.blockReason;
  if (blocked) { const e = new Error(`Gemini hat die Anfrage blockiert (${blocked})`); e.code = 'blocked'; throw e; }
  return { text, finishReason: cand ? cand.finishReason : undefined };
}

/** Wiederholt fn bei 429/5xx/Netzfehlern mit Backoff. */
async function withRetry(fn, { delays = RETRY_DELAYS_MS, sleep = _sleep, onRetry } = {}) {
  let last;
  for (let attempt = 0; attempt <= delays.length; attempt++) {
    try { return await fn(attempt); } catch (e) {
      last = e;
      const status = e && e.status;
      const retryable = status === 429 || status === 500 || status === 503 || status === 502 || status === undefined;
      if (!retryable || attempt === delays.length) throw e;
      if (onRetry) onRetry(e, attempt);
      await sleep(delays[attempt]);
    }
  }
  throw last;
}

/** Baut die Audio-Parts eines Fensters (inline für kleine, Files API für große Spuren). */
async function _audioPart({ apiKey, pcm, name, fetchImpl, sleep, uploaded }) {
  const wav = encodeWav(pcm, { sampleRate: 16000, channels: 1 });
  if (wav.length <= INLINE_LIMIT_BYTES) {
    return { inlineData: { mimeType: 'audio/wav', data: wav.toString('base64') } };
  }
  const f = await uploadFile({ apiKey, buffer: wav, mimeType: 'audio/wav', displayName: name, fetchImpl, sleep });
  uploaded.push(f.name);
  return { fileData: { mimeType: 'audio/wav', fileUri: f.uri } };
}

/**
 * Transkribiert eine Aufnahme (Mikro + optional System) mit Gemini.
 * @param {{
 *   micWavPath:string, systemWavPath?:string|null, chunkBoundariesSec?:number[],
 *   apiKey:string, model?:string, models?:string[], fetchImpl?:Function, sleep?:Function,
 *   sampleRate?:number, maxWindowSeconds?:number, language?:string,
 *   onProgress?:(p:{windowIndex:number,windowCount:number,stage:string})=>void
 * }} opts
 * @returns {Promise<{ segments:object[], speakers:object[], model:string, windows:number }>}
 */
async function transcribeWithGemini(opts) {
  const {
    micWavPath, systemWavPath = null, chunkBoundariesSec = [], apiKey, fetchImpl, sleep = _sleep,
    sampleRate = 16000, maxWindowSeconds = 1500, language = 'de', onProgress,
  } = opts;
  const models = opts.models || [opts.model || DEFAULT_MODEL, ...FALLBACK_MODELS.filter((m) => m !== (opts.model || DEFAULT_MODEL))];
  if (!apiKey) { const e = new Error('Gemini-Key fehlt'); e.code = 'no_key'; throw e; }
  const micLen = wavDurationSec(micWavPath, sampleRate);
  const sysLen = systemWavPath ? wavDurationSec(systemWavPath, sampleRate) : 0;
  const total = Math.max(micLen, sysLen);
  const hasSystem = !!systemWavPath && sysLen > 0;
  const windows = planWindows(chunkBoundariesSec, total, { maxSeconds: maxWindowSeconds });
  if (!windows.length) return { segments: [], speakers: [], model: models[0], windows: 0 };

  let modelIdx = 0;
  const legend = [];      // globale Sprecher-Legende {id, spur, beschreibung}
  const all = [];
  const uploaded = [];

  const processWindow = async (win, idx) => {
    const micPcm = readWavSlice(micWavPath, win.startSec, win.endSec, sampleRate);
    const sysPcm = hasSystem ? readWavSlice(systemWavPath, win.startSec, win.endSec, sampleRate) : null;
    const prompt = buildTranscribePrompt({ hasSystem, windowStartSec: win.startSec, windowIndex: idx, windowCount: windows.length, legend, language });
    const parts = [{ text: prompt }, { text: 'Spur A (Mikrofon):' }, await _audioPart({ apiKey, pcm: micPcm, name: `mic-${idx}`, fetchImpl, sleep, uploaded })];
    if (hasSystem) { parts.push({ text: 'Spur B (Systemaudio):' }); parts.push(await _audioPart({ apiKey, pcm: sysPcm, name: `system-${idx}`, fetchImpl, sleep, uploaded })); }

    let result;
    // Retry-Backoff je Modell; danach bei 404/400/429/5xx nächstes Modell, sonst Fehler
    for (;;) {
      try {
        result = await withRetry(() => _generate({ apiKey, model: models[modelIdx], parts, fetchImpl }), { sleep, onRetry: () => onProgress && onProgress({ windowIndex: idx, windowCount: windows.length, stage: 'retry' }) });
        break;
      } catch (e) {
        if (SWITCH_MODEL_STATUS.has(e.status) && modelIdx < models.length - 1) { modelIdx++; continue; }
        throw e;
      }
    }
    let parsed = null;
    try { parsed = parseTranscriptResponse(result.text, { windowStartSec: win.startSec, windowEndSec: win.endSec, hasSystem }); } catch { parsed = null; }
    if ((!parsed || result.finishReason === 'MAX_TOKENS') && (win.endSec - win.startSec) > MIN_SPLIT_SECONDS) {
      // Ausgabe abgeschnitten/unbrauchbar → Fenster halbieren (an einer Chunk-Grenze, wenn möglich)
      const mid = win.startSec + (win.endSec - win.startSec) / 2;
      const near = chunkBoundariesSec.filter((b) => b > win.startSec + 30 && b < win.endSec - 30).sort((a, b) => Math.abs(a - mid) - Math.abs(b - mid))[0];
      const cut = near != null ? near : mid;
      await processWindow({ startSec: win.startSec, endSec: cut }, idx);
      await processWindow({ startSec: cut, endSec: win.endSec }, idx);
      return;
    }
    if (!parsed) throw new Error('Gemini-Antwort unbrauchbar (kein JSON)');
    let segs = parsed.segments;
    if (hasSystem) { segs = correctTracksByEnergy(segs, { micPcm, sysPcm, windowStartSec: win.startSec, sampleRate }); segs = dedupeEcho(segs); }
    all.push(...segs);
    for (const sp of parsed.speakers) if (!legend.some((l) => l.id === sp.id)) legend.push(sp);
  };

  try {
    for (let i = 0; i < windows.length; i++) {
      if (onProgress) onProgress({ windowIndex: i, windowCount: windows.length, stage: 'transcribe' });
      await processWindow(windows[i], i);
    }
  } finally {
    for (const name of uploaded) await deleteFile({ apiKey, name, fetchImpl });
  }
  all.sort((x, y) => (x.tStart - y.tStart) || (x.tEnd - y.tEnd));
  const labeled = assignLabels(all, legend);
  return { segments: labeled.segments, speakers: labeled.speakers, model: models[modelIdx], windows: windows.length };
}

module.exports = {
  transcribeWithGemini, planWindows, readWavSlice, wavDurationSec, buildTranscribePrompt,
  parseTranscriptResponse, correctTracksByEnergy, dedupeEcho, assignLabels, withRetry, parseJsonLoose,
  RESPONSE_SCHEMA, DEFAULT_MODEL, FALLBACK_MODELS, INLINE_LIMIT_BYTES,
};
