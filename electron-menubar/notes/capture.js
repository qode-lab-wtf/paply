'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { assert, uid, node } = require('./contracts');
function createCapture({ repo, commands, getSettings, isDictating, isMeetingActive, show, send, hide, screenshot, onChange = () => {} }) {
  let active = null, timer = null, warningTimer = null, finishTimer = null, resumeTimer = null, quitting = false;
  function state(phase, detail = '') { detail ||= active?.limitWarning ? 'Noch 1 Min. · dann wird gesichert' : ''; send({ phase, detail, entryId: active?.id || null, epoch: active?.epoch || 0, elapsedMs: active ? active.bytes / 32 : 0, hasImage: !!active?.attachments.length }); onChange(); }
  function emptyPlaceholder(entryId) {
    commands.commit(b => { const n = b.nodes[`raw_${entryId}`]; if (n?.pending) { n.pending = false; n.label = 'Kein Ton aufgenommen'; } }, false);
  }
  function recover() {
    for (const e of repo.entries()) if (e.state === 'recording') {
      const file = path.join(repo.sourcePath(e.id), 'rec.pcm');
      if (fs.existsSync(file)) { const bytes = fs.statSync(file).size; if (bytes % 2) fs.truncateSync(file, bytes - 1); e.durationMs = (bytes - bytes % 2) / 32; }
      e.state = e.durationMs > 0 ? 'captured' : 'needs_attention'; e.message = 'Unterbrochene Aufnahme gesichert'; repo.saveEntry(e);
      if (!e.durationMs) emptyPlaceholder(e.id);
    }
    // Keep the opted-in start image while transcription is pending, at most 7 days.
    for (const name of fs.readdirSync(path.join(repo.root, 'tmp'))) if (/^[\w-]+\.png$/.test(name)) {
      const file = path.join(repo.root, 'tmp', name), entryId = name.slice(0, -4), e = repo.entry(entryId);
      if (!e || e.state === 'discarded' || repo.transcript(entryId) || fs.statSync(file).mtimeMs < Date.now() - 7 * 86400000) fs.rmSync(file, { force: true });
    }
  }
  async function start() {
    if (active) return stop();
    if (!getSettings().enabled) return;
    if (isDictating() || isMeetingActive()) { await show(); state('refused', isMeetingActive() ? 'Meeting läuft' : 'Diktat läuft'); hide(1600); return; }
    // Reserve synchronously, before window/microphone/screenshot awaits.
    const entry = { id: uid('s'), kind: 'voice', createdAt: Date.now(), state: 'recording', durationMs: 0, attachments: [], partsDone: 0, attempts: 0 };
    try {
      repo.saveEntry(entry);
      const fd = fs.openSync(path.join(repo.sourcePath(entry.id), 'rec.pcm'), 'a', 0o600);
      active = { ...entry, fd, epoch: 1, seq: 0, bytes: 0, paused: false, stopping: false, started: false, droppedPackets: 0 };
      const generation = active;
      commands.commit(b => { const n = node({ kind: 'note', label: 'Neuer Gedanke', text: '' }); Object.assign(n, { id: `raw_${entry.id}`, owner: 'system', sourceId: entry.id, pending: true }); b.nodes[n.id] = n; }, false);
      warningTimer = setTimeout(() => { if (active === generation && !active.stopping) { active.limitWarning = true; state(active.paused ? 'paused' : 'recording'); } }, 29 * 60000);
      timer = setTimeout(() => { if (active) active.limitReached = true; stop(); }, 30 * 60000);
      await show(); if (active !== generation) return;
      if (active.stopping) { finish(); return; }
      state(active.paused ? 'paused' : 'start');
      finishTimer = setTimeout(() => { if (active === generation && !active.started) fail('Mikrofon antwortet nicht'); }, 15000);
      if (getSettings().screenContext) {
        screenshot().then(bytes => { if (active === generation && !active.stopping) fs.writeFileSync(path.join(repo.root, 'tmp', `${entry.id}.png`), bytes, { mode: 0o600 }); }).catch(() => { if (active === generation) state(active.paused ? 'paused' : 'recording', 'Bildschirmzugriff fehlt'); });
      }
    } catch {
      if (active) fail('Notes-Aufnahme konnte nicht starten');
      else { try { await show(); state('error', 'Notes-Aufnahme konnte nicht gespeichert werden'); hide(3000); } catch { /* The recorder window itself may have failed. */ } }
    }
  }
  function accept(payload) {
    assert(payload && typeof payload.entryId === 'string' && Number.isInteger(payload.epoch) && Number.isInteger(payload.seq));
    const a = active;
    if (!a || payload.entryId !== a.id || payload.epoch !== a.epoch || a.paused) { if (a) a.droppedPackets++; return { accepted: false }; }
    assert(payload.bytes instanceof ArrayBuffer || ArrayBuffer.isView(payload.bytes));
    const bytes = Buffer.from(payload.bytes instanceof ArrayBuffer ? payload.bytes : new Uint8Array(payload.bytes.buffer, payload.bytes.byteOffset, payload.bytes.byteLength));
    assert(bytes.length > 0 && bytes.length <= 64000 && bytes.length % 2 === 0);
    if (payload.seq <= a.seq) return { accepted: true, seq: a.seq };
    assert(payload.seq === a.seq + 1, 'Eine Audioportion fehlt');
    try {
      let offset = 0;
      while (offset < bytes.length) { const written = fs.writeSync(a.fd, bytes, offset, bytes.length - offset); assert(written > 0, 'Audio konnte nicht gespeichert werden'); offset += written; }
      fs.fsyncSync(a.fd); a.bytes += bytes.length; a.seq = payload.seq;
      if (!a.started) { a.started = true; if (!a.stopping) { clearTimeout(finishTimer); state('recording'); } }
      if (a.bytes >= 30 * 60 * 32000) { a.limitReached = true; stop(); }
      return { accepted: true, seq: a.seq };
    } catch { fail('Speichern fehlgeschlagen · bisheriger Ton bleibt erhalten'); return { accepted: false }; }
  }
  function finish(message = '') {
    const a = active; if (!a) return;
    clearTimeout(timer); clearTimeout(warningTimer); clearTimeout(finishTimer); clearTimeout(resumeTimer);
    // A full disk must never leave a live microphone or a stuck capture lease.
    // entry.json remains 'recording' if its final write fails; recover() repairs it.
    try { const length = fs.fstatSync(a.fd).size; a.bytes = length - length % 2; if (length % 2) fs.ftruncateSync(a.fd, a.bytes); fs.fsyncSync(a.fd); } catch { message ||= 'Speichern unterbrochen · vorhandener Ton bleibt erhalten'; }
    try { fs.closeSync(a.fd); } catch { message ||= 'Aufnahme beendet · Speicher prüfen'; }
    active = null;
    const entry = repo.entry(a.id) || { id: a.id, kind: 'voice', createdAt: a.createdAt, partsDone: 0, attempts: 0 };
    Object.assign(entry, { stoppedAt: Date.now(), state: a.bytes ? 'captured' : 'needs_attention', durationMs: a.bytes / 32, attachments: a.attachments, message: message || (a.limitReached ? 'Nach 30 Min. gespeichert' : a.bytes ? '' : 'Kein Ton aufgenommen'), droppedPackets: a.droppedPackets });
    try { repo.saveEntry(entry); } catch { message = 'Speicher voll oder nicht erreichbar · vorhandenen Ton beim Neustart wiederherstellen'; }
    if (!a.bytes) { try { emptyPlaceholder(a.id); } catch { /* Keep the last durable board on disk failure. */ } }
    state(message ? 'error' : 'saved', message || (a.limitReached ? 'Nach 30 Min. gespeichert' : getSettings().hasGroqKey ? 'Gedanke gesichert' : 'Gesichert · Schlüssel ergänzen')); if (!quitting) hide(message ? 3000 : 1400);
  }
  function stop() {
    if (!active || active.stopping) return;
    active.stopping = true; clearTimeout(finishTimer);
    if (active.paused) { finish(); return; }
    state('stop'); finishTimer = setTimeout(() => finish('Aufnahme gesichert · Mikrofon neu starten'), 2500);
  }
  function flushed(p) { if (active && p.entryId === active.id && p.epoch === active.epoch && active.stopping) finish(); }
  function fail(message) { if (active) { send({ phase: 'abort', entryId: active.id, epoch: active.epoch }); finish(message); } }
  function dictationState(recording) {
    if (!active || active.stopping) return;
    clearTimeout(resumeTimer);
    if (recording) { active.paused = true; active.epoch++; active.seq = 0; state('paused', 'Pausiert · Diktat'); }
    else if (active.paused) {
      const generation = active;
      const resume = () => {
        if (active !== generation || active.stopping) return;
        if (isDictating()) { resumeTimer = setTimeout(resume, 200); return; }
        active.paused = false; active.epoch++; active.seq = 0; state('resume');
      };
      resumeTimer = setTimeout(resume, 350);
    }
  }
  function meetingStarted() { if (active) { active.paused = true; active.epoch++; send({ phase: 'abort', entryId: active.id }); finish('Gesichert · Meeting hat Vorrang'); } }
  return { start, stop, toggle: () => active ? stop() : start(), accept, flushed, fail, recover, dictationState, meetingStarted,
    status: () => ({ active: !!active, paused: !!active?.paused, entryId: active?.id || null, elapsedMs: active ? active.bytes / 32 : 0 }),
    attach(hash) { if (!active) return false; if (!active.attachments.includes(hash)) active.attachments.push(hash); const e = repo.entry(active.id); e.attachments = active.attachments; repo.saveEntry(e); state(active.paused ? 'paused' : 'recording'); return true; },
    shutdown() { quitting = true; if (active) { send({ phase: 'abort', entryId: active.id }); finish(); } },
  };
}
module.exports = { createCapture };
