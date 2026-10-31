'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { uid, node, assert } = require('./contracts');
const { encodeWav } = require('../audio/wav-encoder');
const { filterTranscription, shouldSkipTranscription } = require('../audio/silence-filter');
const { splitSentences, chunks, context, validatePlan, applyPlan } = require('./plan');

function hasTranscript(transcript) { return !!(transcript?.text?.trim() || transcript?.silenceProven === true); }

function levels(pcm) {
  const windows = [];
  for (let offset = 0; offset + 1 < pcm.length; offset += 1600) {
    const end = Math.min(offset + 1600, pcm.length); let sum = 0;
    for (let i = offset; i + 1 < end; i += 2) sum += (pcm.readInt16LE(i) / 32768) ** 2;
    windows.push({ db: Math.max(-120, 20 * Math.log10(Math.sqrt(sum / ((end - offset) / 2)))), ms: (end - offset) / 32 });
  }
  const sorted = windows.map(w => w.db).sort((a, b) => a - b), floor = sorted[Math.max(0, Math.ceil(sorted.length * .15) - 1)] ?? -120;
  return { durationMs: pcm.length / 32, measuredMs: pcm.length / 32, speechMs: windows.filter(w => w.db > Math.max(-65, floor + 15)).reduce((v, w) => v + w.ms, 0), floorDbfs: floor, peakDbfs: sorted.at(-1) ?? -120, maxGapMs: 50 };
}
function audioChunks(pcm) {
  const result = []; let offset = 0;
  while (offset < pcm.length) {
    let end = Math.min(offset + 9 * 60 * 32000, pcm.length);
    if (end < pcm.length) {
      let quiet = Infinity, best = end;
      for (let at = end - 2 * 32000; at <= end - 1600; at += 1600) {
        let sum = 0; for (let i = at; i < at + 1600; i += 2) sum += pcm.readInt16LE(i) ** 2;
        if (sum < quiet) { quiet = sum; best = at + 800; }
      }
      end = best;
    }
    result.push(pcm.subarray(offset, end)); offset = end;
  }
  return result;
}
function createQueue({ repo, commands, groq, assets, getSettings, getKey, vocabulary = () => '', isBusy = () => false, isEditing = () => false, isOnline = () => true, onChange = () => {} }) {
  let running = false, stopped = false, controller = null, timer = null, currentId = null, authKey = null, retentionTimer = null;
  function save(entry) { repo.saveEntry(entry); onChange(); }
  function prepare(entry, transcript) {
    const parts = chunks(transcript.sentences), firstId = `raw_${entry.id}`;
    const first = repo.current().nodes[firstId];
    if (repo.current().tombstones[firstId] || first?.owner === 'user' && !first.pending) {
      if (first?.pending) commands.commit(b => { if (b.nodes[firstId]) b.nodes[firstId].pending = false; }, false);
      entry.state = 'kept_user'; save(entry); return;
    }
    commands.commit(b => {
      parts.forEach((sentences, index) => {
        const rid = index ? `${firstId}_${index}` : firstId;
        if (b.tombstones[rid]) return;
        const existing = b.nodes[rid];
        if (existing && !existing.pending && (existing.owner === 'user' || existing.sourceId)) return;
        const n = existing || node({ kind: 'note' });
        const content = sentences.map(s => s.text).join(' '), userText = existing?.pending && existing.owner === 'user' ? existing.text.trim() : '';
        Object.assign(n, { id: rid, text: userText ? `${userText}\n\n${content}` : content, label: 'Gedanke', icon: entry.kind === 'voice' ? 'message-circle' : 'pencil', sourceId: entry.id, sentenceIds: sentences.map(s => s.id), owner: existing?.owner === 'user' ? 'user' : 'system', pending: false, attachments: [...new Set([...(n.attachments || []), ...(index === 0 ? entry.attachments || [] : [])])], rev: (existing?.rev || 0) + 1 });
        b.nodes[rid] = n; sentences.forEach(s => { if (!b.claims[s.id]) b.claims[s.id] = rid; });
      });
    }, false);
    entry.parts = parts.length;
    entry.state = parts.length ? 'transcribed' : 'empty';
    if (!parts.length) commands.commit(b => { const n = b.nodes[firstId]; if (n) { n.pending = false; if (n.owner !== 'user') n.label = 'Keine Sprache erkannt'; n.attachments = [...new Set([...n.attachments, ...(entry.attachments || [])])]; } }, false);
    save(entry);
  }
  async function transcribe(entry, signal) {
    const pcm = fs.readFileSync(path.join(repo.sourcePath(entry.id), 'rec.pcm'));
    const pieces = audioChunks(pcm), done = [];
    for (const part of repo.readLocal(`sources/${entry.id}/stt.json`, [])) {
      if (!hasTranscript(part)) break;
      done.push(part);
    }
    save({ ...entry, state: 'transcribing' });
    for (let i = done.length; i < pieces.length; i++) {
      if (signal.aborted) throw new Error('Abgebrochen');
      if (isBusy()) { const e = new Error('Diktat hat Vorrang'); e.kind = 'busy'; throw e; }
      const meta = levels(pieces[i]);
      let text = '', language = done.at(-1)?.language, model = null;
      const silenceProven = shouldSkipTranscription(meta);
      if (!silenceProven) {
        const response = await groq.transcribe(encodeWav(pieces[i]), pieces[i].length / 32000, signal, vocabulary(), { previousLanguage: language, previousText: done.at(-1)?.text, voiceActivity: meta });
        language = response.language || language;
        model = response.model;
        if (signal.aborted || repo.entry(entry.id)?.state === 'discarded') return;
        text = filterTranscription(response, meta).text;
      }
      if (!text.trim() && !silenceProven) throw new Error('Keine Sprache erkannt · Erneut versuchen');
      done.push({ text, language, model, silenceProven, durationMs: meta.durationMs }); repo.writeLocal(`sources/${entry.id}/stt.json`, done);
    }
    const original = done.map(d => d.text).filter(Boolean).join(' ');
    if (signal.aborted || repo.entry(entry.id)?.state === 'discarded') return;
    const match = /^(?:(?:bitte\s+)?screenshot\s+(?:machen|speichern)|bildschirm\s+merken)[\s,.!:;-]*/i.exec(original);
    const temporary = path.join(repo.root, 'tmp', `${entry.id}.png`);
    const hasScreen = !!match && fs.existsSync(temporary);
    if (hasScreen) { const hash = assets.put(fs.readFileSync(temporary)); entry.attachments = [...new Set([...(entry.attachments || []), hash])]; }
    if (match && !hasScreen) entry.message = 'Kein Startbild vorhanden · Bildschirmkontext in den Notes-Einstellungen aktivieren';
    try { fs.rmSync(temporary, { force: true }); } catch { /* later housekeeping */ }
    const transcript = repo.saveTranscript(entry.id, { text: original, command: hasScreen ? match[0] : null, sentences: splitSentences(hasScreen ? original.slice(match[0].length) : original, entry.id), model: done.find(d => d.model)?.model || null, silenceProven: done.every(d => d.silenceProven === true), createdAt: Date.now() });
    if (transcript.text.trim() || transcript.silenceProven) deleteAudio(entry);
    prepare(entry, transcript);
  }
  async function structure(entry, signal) {
    const transcript = repo.transcript(entry.id); assert(transcript, 'Originaltext fehlt');
    const parts = chunks(transcript.sentences), index = entry.partsDone || 0;
    if (index >= parts.length) { entry.state = entry.fallback ? 'fallback' : entry.keptUser ? 'kept_user' : 'complete'; entry.finishedAt = Date.now(); save(entry); return; }
    const rawId = `raw_${entry.id}${index ? `_${index}` : ''}`, raw = repo.current().nodes[rawId];
    if (!raw || raw.owner === 'user' || raw.pinned) {
      const alreadyApplied = !raw && parts[index].every(s => typeof repo.current().claims[s.id] === 'string' && repo.current().nodes[repo.current().claims[s.id]]?.sourceId === entry.id);
      entry.partsDone = index + 1; entry.state = 'transcribed'; if (!alreadyApplied) entry.keptUser = true; save(entry); return;
    }
    const waitForEditor = () => { if (isEditing(rawId)) { const error = new Error('Bearbeitung hat Vorrang'); error.kind = 'busy'; throw error; } };
    waitForEditor();
    const ctx = context(repo.current(), parts[index], entry.id); const rawRev = raw.rev;
    const useLarge = !!entry.largeFallback || parts[index].length >= 3 || parts[index].map(s => s.text).join(' ').length > 550;
    entry.state = 'structuring'; save(entry);
    const planPath = `sources/${entry.id}/plan-${index}.json`;
    const cached = repo.readLocal(planPath, null);
    const reuse = cached?.rawRev === rawRev && cached.context;
    const validationContext = reuse ? { ...ctx, ...cached.context, sentences: parts[index] } : ctx;
    let plan;
    try {
      const result = reuse ? cached.plan : await groq.plan(ctx, useLarge, signal);
      try { plan = validatePlan(result, validationContext); } catch (e) { e.kind = 'plan'; throw e; }
    } catch (e) {
      if (['plan', 'invalid', 'model'].includes(e.kind) && !useLarge) { entry.largeFallback = true; entry.state = 'transcribed'; entry.retryAt = Date.now() + 1500; save(entry); return; }
      if (['plan', 'invalid', 'model', 'too_large'].includes(e.kind)) { entry.partsDone = index + 1; entry.largeFallback = false; entry.state = 'transcribed'; entry.fallback = true; entry.message = 'Original erhalten · Einordnung nicht eindeutig'; save(entry); return; }
      throw e;
    }
    if (signal.aborted || repo.entry(entry.id)?.state === 'discarded') return;
    // A completed request is durable before waiting for an open editor or saving
    // the projection. Retrying a local write never buys the same plan again.
    repo.writeLocal(planPath, { plan, rawRev, context: { topics: validationContext.topics.map(t => ({ id: t.id })), existing: validationContext.existing.map(n => ({ id: n.id })) }, at: Date.now() });
    waitForEditor();
    let applied = false;
    try { commands.commit(b => { applied = applyPlan(b, plan, { entryId: entry.id, sentences: parts[index], rawId, rawRev }); }, false); }
    catch (error) {
      if (error.message !== 'Ungültige Notes-Daten') throw error;
      entry.fallback = true; entry.message = 'Original erhalten · Darstellung nicht verwendbar';
    }
    if (!applied && !entry.fallback) entry.keptUser = true;
    entry.partsDone = index + 1; entry.largeFallback = false; entry.state = 'transcribed'; entry.attempts = 0; entry.retryAt = 0; save(entry);
  }
  async function tick() {
    if (stopped || running || isBusy()) return;
    running = true;
    try {
      const entry = repo.entries().filter(e => ['captured', 'transcribed', 'waiting_key', 'waiting_network', 'waiting_limit', 'waiting_budget'].includes(e.state) && (!e.retryAt || e.retryAt <= Date.now())).sort((a, b) => (a.resumeStep === 'plan' || a.state === 'transcribed' ? 1 : 0) - (b.resumeStep === 'plan' || b.state === 'transcribed' ? 1 : 0) || a.createdAt - b.createdAt)[0];
      if (!entry) { await vision(); return; }
      currentId = entry.id; controller = new AbortController();
      entry.resumeStep = entry.state === 'transcribed' || hasTranscript(repo.transcript(entry.id)) ? 'plan' : 'stt';
      if (!getKey() || authKey === getKey()) { entry.state = 'waiting_key'; entry.message = authKey ? 'Groq-Schlüssel prüfen' : 'Groq-Schlüssel in den Einstellungen ergänzen'; entry.retryAt = Date.now() + 60000; save(entry); return; }
      authKey = null;
      if (!isOnline()) { entry.state = 'waiting_network'; entry.message = 'Lokal gesichert · wartet auf Verbindung'; entry.retryAt = Date.now() + 30000; save(entry); return; }
      try {
        if (entry.resumeStep === 'stt') await transcribe(entry, controller.signal);
        else {
          if (!entry.parts) prepare(entry, repo.transcript(entry.id));
          if (!['kept_user', 'empty'].includes(entry.state)) await structure(entry, controller.signal);
        }
      } catch (error) {
        if (controller.signal.aborted || repo.entry(entry.id)?.state === 'discarded') return;
        if (error.kind === 'auth') authKey = getKey();
        const waits = { key: 'waiting_key', auth: 'waiting_key', network: 'waiting_network', rate: 'waiting_limit', budget: 'waiting_budget', busy: entry.resumeStep === 'stt' ? 'captured' : 'transcribed' };
        entry.attempts = (entry.attempts || 0) + (Object.hasOwn(waits, error.kind) ? 0 : 1);
        entry.state = error.kind === 'budget_small' ? 'needs_attention' : waits[error.kind] || (entry.attempts >= 5 ? 'needs_attention' : entry.resumeStep === 'stt' ? 'captured' : 'transcribed');
        entry.message = ['network', 'timeout'].includes(error.kind) ? 'Lokal gesichert · Verbindung unterbrochen' : error.message;
        entry.retryAt = Date.now() + (Number.isFinite(error.retryMs) && error.retryMs > 0 ? error.retryMs : error.kind === 'busy' ? 2000 : Math.min(600000, 30000 * 2 ** entry.attempts));
        if (Date.now() - entry.createdAt > 86400000 && !['waiting_key', 'waiting_budget'].includes(entry.state)) entry.state = 'needs_attention';
        save(entry);
      }
    } finally { running = false; currentId = null; controller = null; }
  }
  async function vision() {
    if (!getKey() || !isOnline() || authKey === getKey()) return;
    const item = assets.pending()[0]; if (!item) return;
    const days = repo.readLocal('vision-usage.json', []).filter(at => at > Date.now() - 86400000); if (days.length >= 10) return;
    days.push(Date.now()); repo.writeLocal('vision-usage.json', days); item.attempts++;
    repo.writeLocal(`assets/${item.id}.json`, item);
    controller = new AbortController();
    try { item.analysis = { ...await groq.describe(assets.describeInput(item.id), controller.signal), version: 1 }; }
    catch (e) { if (e.kind === 'auth') authKey = getKey(); item.retryAt = Date.now() + Math.max(60000, e.retryMs || 600000); }
    repo.writeLocal(`assets/${item.id}.json`, item); onChange();
  }
  function deleteAudio(entry) {
    try { fs.rmSync(path.join(repo.sourcePath(entry.id), 'rec.pcm'), { force: true }); } catch { /* retry at next cleanup */ }
  }
  function cleanAudio(now = Date.now()) {
    for (const entry of repo.entries()) {
      if (entry.state === 'recording' || entry.id === currentId) continue;
      if (repo.transcript(entry.id)?.text?.trim() || repo.transcript(entry.id)?.silenceProven === true || now - (entry.stoppedAt ?? (entry.createdAt + (entry.durationMs || 0))) >= 30 * 86400000) deleteAudio(entry);
    }
  }
  function recover() {
    for (const entry of repo.entries()) {
      if (entry.state === 'transcribing') { entry.state = 'captured'; save(entry); }
      else if (entry.state === 'structuring') { entry.state = 'transcribed'; save(entry); }
    }
  }
  return { tick, recover, cleanAudio,
    start() { recover(); cleanAudio(); retentionTimer = setInterval(() => { try { cleanAudio(); } catch { /* retry next hour */ } }, 3600000); retentionTimer.unref(); timer = setInterval(() => { tick().catch(() => {}); }, 1500); timer.unref(); tick().catch(() => {}); },
    stop() { stopped = true; clearInterval(timer); clearInterval(retentionTimer); controller?.abort(); },
    retry(id) {
      const e = repo.entry(id); assert(e && !['recording', 'discarded'].includes(e.state));
      if (e.fallback) {
        // Explicit retry requests a fresh plan. Automatic retries only reuse it.
        for (let i = 0; i < (e.parts || 0); i++) repo.writeLocal(`sources/${id}/plan-${i}.json`, null);
        e.partsDone = 0; e.fallback = false; e.largeFallback = false; e.keptUser = false;
      }
      e.state = hasTranscript(repo.transcript(id)) ? 'transcribed' : 'captured'; e.retryAt = 0; e.attempts = 0; e.message = ''; authKey = null; save(e); tick().catch(() => {});
    },
    discard(id) { const e = repo.entry(id); assert(e && e.state !== 'recording'); if (currentId === id) controller?.abort(); e.state = 'discarded'; e.discardedAt = Date.now(); save(e); commands.commit(b => { for (const [nid, n] of Object.entries(b.nodes)) if (n.sourceId === id) { n.sentenceIds.forEach(s => { b.claims[s] = { tomb: true }; }); b.tombstones[nid] = Date.now(); delete b.nodes[nid]; } for (const [eid, edge] of Object.entries(b.edges)) if (!b.nodes[edge.source] || !b.nodes[edge.target]) delete b.edges[eid]; }); },
    reconcileUndo() {
      const live = new Set(Object.values(repo.current().nodes).map(n => n.sourceId));
      for (const e of repo.entries()) if (e.discardedAt) {
        if (live.has(e.id) && e.state === 'discarded') { e.state = repo.transcript(e.id) ? 'kept_user' : 'needs_attention'; e.message = ''; save(e); }
        else if (!live.has(e.id) && e.state !== 'discarded') { e.state = 'discarded'; save(e); }
      }
    },
    addText(text, position) {
      assert(typeof text === 'string' && text.trim() && text.length <= 20000);
      const e = { id: uid('s'), kind: 'text', createdAt: Date.now(), state: 'transcribed', attachments: [], partsDone: 0, attempts: 0 };
      const transcript = { text, sentences: splitSentences(text, e.id), model: null, createdAt: Date.now() };
      repo.saveEntry(e); repo.saveTranscript(e.id, transcript); prepare(e, transcript);
      if (position) commands.place([{ id: `raw_${e.id}`, position }]); tick().catch(() => {}); return e.id;
    },
  };
}
module.exports = { createQueue, levels, audioChunks };
