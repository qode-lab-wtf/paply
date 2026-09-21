'use strict';
// Gemini Files API (kostenlos): resumable Upload für Audio-Dateien > 20 MB, die nicht inline in
// generateContent passen. Reine fetch-Funktionen, injizierbares fetchImpl (Tests ohne Netz).
// Hochgeladene Dateien laufen serverseitig nach 48 h automatisch ab; wir löschen sie zusätzlich
// nach der Auswertung (best effort).

const GEMINI_BASE = 'https://generativelanguage.googleapis.com';

function _sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function _readError(res) {
  try { const t = await res.text(); return t.slice(0, 300); } catch { return String(res.status); }
}

/**
 * Lädt einen Buffer als Datei zu Gemini hoch (resumable, 2 Requests) und wartet, bis die Datei ACTIVE ist.
 * @param {{ apiKey:string, buffer:Buffer, mimeType?:string, displayName?:string, fetchImpl?:Function,
 *           waitActiveMs?:number, sleep?:Function }} opts
 * @returns {Promise<{ name:string, uri:string, state:string }>}
 */
async function uploadFile({ apiKey, buffer, mimeType = 'audio/wav', displayName = 'audio', fetchImpl, waitActiveMs = 30000, sleep = _sleep }) {
  const fetch = fetchImpl || globalThis.fetch;
  if (!apiKey) throw new Error('Gemini-Key fehlt');
  // 1) Upload-Sitzung starten → Upload-URL im Header
  const startRes = await fetch(`${GEMINI_BASE}/upload/v1beta/files`, {
    method: 'POST',
    headers: {
      'x-goog-api-key': apiKey,
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Header-Content-Length': String(buffer.length),
      'X-Goog-Upload-Header-Content-Type': mimeType,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ file: { display_name: displayName } }),
  });
  if (!startRes.ok) {
    const e = new Error(`Gemini Upload-Start HTTP ${startRes.status}: ${await _readError(startRes)}`);
    e.status = startRes.status; if (startRes.status === 429) e.code = 'rate_limit';
    throw e;
  }
  const uploadUrl = startRes.headers && typeof startRes.headers.get === 'function' ? startRes.headers.get('x-goog-upload-url') : null;
  if (!uploadUrl) throw new Error('Gemini Upload: keine Upload-URL erhalten');

  // 2) Bytes hochladen + finalisieren
  const upRes = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      'X-Goog-Upload-Offset': '0',
      'X-Goog-Upload-Command': 'upload, finalize',
    },
    body: buffer,
  });
  if (!upRes.ok) {
    const e = new Error(`Gemini Upload HTTP ${upRes.status}: ${await _readError(upRes)}`);
    e.status = upRes.status; if (upRes.status === 429) e.code = 'rate_limit';
    throw e;
  }
  const data = await upRes.json();
  let file = (data && data.file) || {};
  if (!file.uri || !file.name) throw new Error('Gemini Upload: Antwort ohne file.uri');

  // 3) Auf Verarbeitung warten (Audio ist meist sofort ACTIVE)
  const deadline = Date.now() + waitActiveMs;
  while (file.state && file.state !== 'ACTIVE') {
    if (file.state === 'FAILED') throw new Error('Gemini Upload: Datei-Verarbeitung fehlgeschlagen');
    if (Date.now() > deadline) throw new Error('Gemini Upload: Datei wurde nicht rechtzeitig aktiv');
    await sleep(1000);
    const r = await fetch(`${GEMINI_BASE}/v1beta/${file.name}`, { headers: { 'x-goog-api-key': apiKey } });
    if (!r.ok) throw new Error(`Gemini Datei-Status HTTP ${r.status}`);
    file = await r.json();
  }
  return { name: file.name, uri: file.uri, state: file.state || 'ACTIVE' };
}

/** Löscht eine hochgeladene Datei (best effort, wirft nie). */
async function deleteFile({ apiKey, name, fetchImpl }) {
  const fetch = fetchImpl || globalThis.fetch;
  if (!apiKey || !name) return false;
  try {
    const r = await fetch(`${GEMINI_BASE}/v1beta/${name}`, { method: 'DELETE', headers: { 'x-goog-api-key': apiKey } });
    return !!r.ok;
  } catch { return false; }
}

module.exports = { uploadFile, deleteFile, GEMINI_BASE };
