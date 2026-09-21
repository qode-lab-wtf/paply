'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawn } = require('node:child_process');
const { atomicJson, readJson } = require('./local-files');
const { concatWavFiles } = require('../audio/wav-encoder');
function stopChild(child, signal = 'SIGTERM') {
  if (!child) return;
  try { if (process.platform !== 'win32') process.kill(-child.pid, signal); else child.kill(signal); } catch (error) { if (error.code !== 'ESRCH') throw error; }
}
function hashFile(file) { return new Promise((resolve, reject) => {
  const hash = crypto.createHash('sha256'), stream = fs.createReadStream(file);
  stream.on('error', reject); stream.on('data', chunk => hash.update(chunk)); stream.on('end', () => resolve(hash.digest('hex')));
}); }
function createLocalPipeline({ store, configPath, emit = () => {}, runner, now = Date.now }) {
  const config = readJson(configPath);
  if (!config?.asrPython || !config?.diarizationPython || !config?.whisperModel || !config?.pyannoteModel) throw new Error('Lokale Modelle noch nicht eingerichtet');
  if (config.enhancementModel && (!config.enhancementPython || !config.models?.enhancementRevision)) throw new Error('Sprachaufbereitung unvollständig eingerichtet');
  if (config.asrBackend === 'faster-whisper' && !config.fasterWhisperModel) throw new Error('Alternative Transkription unvollständig eingerichtet');
  const worker = path.join(__dirname, 'local', 'worker.py').replace('app.asar/', 'app.asar.unpacked/');
  let chain = Promise.resolve(), currentChild = null, currentId = null;
  const scheduled = new Map(), cancelled = new Set();
  const assertPresent = id => { if (cancelled.has(id) || !store.readState(id)) throw new Error('Gespräch wurde gelöscht'); };
  const run = runner || ((stage, id, channel) => new Promise((resolve, reject) => {
    const python = stage === 'enhancement' ? config.enhancementPython : stage === 'asr' ? config.asrPython : config.diarizationPython;
    const args = [python, worker, stage, store.dir(id), configPath, ...(channel ? ['--channel', channel] : [])];
    // Enforcement rather than a convention: final model workers cannot use any network.
    const command = process.platform === 'darwin' ? '/usr/bin/sandbox-exec' : python;
    const profile = '(version 1)(allow default)(deny network*)' + (stage === 'report' && config.reporter ? '(allow network-inbound (local ip "localhost:*"))(allow network-outbound (remote ip "localhost:*"))' : '');
    const argv = process.platform === 'darwin' ? ['-p', profile, ...args] : args.slice(1);
    const child = spawn(command, argv, { detached: process.platform !== 'win32', stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, HF_HUB_OFFLINE: '1', TRANSFORMERS_OFFLINE: '1', PYANNOTE_METRICS_ENABLED: 'false' } });
    currentChild = child;
    let errors = '', killed = false;
    const timeout = setTimeout(() => { killed = true; stopChild(child); }, 6 * 60 * 60 * 1000);
    child.stderr.on('data', data => { errors = (errors + data.toString()).slice(-3000); });
    child.stdout.resume();
    child.once('error', reject);
    child.once('close', code => { clearTimeout(timeout); if (currentChild === child) currentChild = null;
      if (code === 0 && !killed) resolve(); else reject(new Error(killed ? 'Lokale Verarbeitung hat das Zeitlimit erreicht' : errors || `Lokaler Prozess beendet (${code})`)); });
  }));
  async function prepare(id) {
    let state = store.readState(id);
    if (state.audioExpiresAt && now() >= state.audioExpiresAt) throw new Error('Audio-Aufbewahrungszeit abgelaufen');
    const dir = store.dir(id), tracks = {};
    fs.mkdirSync(path.join(dir, 'processing'), { recursive: true });
    for (const channel of ['mic', 'system']) {
      const file = path.join(dir, `audio_${channel}.wav`);
      if (!fs.existsSync(file)) {
        const chunks = path.join(dir, 'chunks');
        const list = fs.existsSync(chunks) ? fs.readdirSync(chunks).filter(f => f.startsWith(channel + '_') && f.endsWith('.wav')).sort().map(f => path.join(chunks, f)) : [];
        if (list.length) { const tmp = file + '.tmp'; concatWavFiles(list, tmp); fs.renameSync(tmp, file); }
      }
      if (fs.existsSync(file)) tracks[channel] = { ...state.tracks?.[channel], sha256: await hashFile(file) };
    }
    if (!Object.keys(tracks).length) throw new Error('Keine gespeicherten Audiospuren vorhanden');
    assertPresent(id);
    store.writeState(id, { tracks, models: { ...config.models, diarizationDevice: config.diarizationDevice || 'cpu' }, status: 'processing', error: null });
    return tracks;
  }
  async function processMeeting(id, { force = false, reportOnly = false } = {}) {
    const dir = store.dir(id);
    currentId = id;
    try {
      assertPresent(id);
      if (!reportOnly) {
        const tracks = await prepare(id);
        for (const channel of Object.keys(tracks)) for (const stage of ['asr', ...(config.enhancementModel && channel === 'mic' ? ['enhancement'] : []), 'diarization']) {
          const key = `${channel}-${stage}`;
          const state = store.readState(id);
          if (state.audioExpiresAt && now() >= state.audioExpiresAt) throw new Error('Audio-Aufbewahrungszeit abgelaufen');
          const checkpoint = state.completed?.[key];
          const signature = crypto.createHash('sha256').update(JSON.stringify([tracks[channel].sha256, config.models, stage, config.asrBackend || 'mlx-whisper', Boolean(config.enhancementModel), ...(stage === 'diarization' ? [config.diarizationDevice || 'cpu'] : [])])).digest('hex');
          if (force || checkpoint !== signature || !fs.existsSync(path.join(dir, 'processing', key + '.json')) || (stage === 'enhancement' && !fs.existsSync(path.join(dir, 'processing', `${channel}-enhanced.wav`)))) {
            store.writeState(id, { stage: key }); emit('meetings:updated', { id, stage: key });
            await run(stage, id, channel);
            assertPresent(id);
            store.writeState(id, { completed: { ...store.readState(id).completed, [key]: signature } });
          }
        }
        store.writeState(id, { stage: 'merge' }); await run('merge', id); assertPresent(id);
      }
      const transcript = store.get(id)?.transcript;
      if (!transcript?.segments) throw new Error('Transkript fehlt');
      // Apply persistent user corrections to the report input; the worker never overwrites corrections.
      atomicJson(path.join(dir, 'report-input.json'), transcript);
      const speakers = [...new Set(transcript.segments.filter(s => s.speakerId && !s.speakerId.endsWith('-unclear')).map(s => s.speaker))];
      store.finalizeIndex(id, { speakerCount: speakers.length, speakerNames: speakers, diarizationUsed: true, diarizationCostUsd: 0 });
      store.writeState(id, { stage: 'report' });
      // Publish the completed transcript before the much slower report stage.
      emit('meetings:updated', { id, stage: 'report', transcriptReady: true });
      await run('report', id); assertPresent(id);
      store.finalizeIndex(id, { hasSummary: true, preview: transcript.segments[0]?.text.slice(0, 120) || '',
        speakerCount: speakers.length, speakerNames: speakers, diarizationUsed: true, diarizationCostUsd: 0 });
      store.writeState(id, { status: 'ready', stage: null, error: null, reportNeedsRefresh: false });
      emit('meetings:updated', { id, status: 'ready' });
      return true;
    } catch (error) {
      if (cancelled.has(id) || !store.readState(id)) return false;
      store.writeState(id, { status: 'failed', error: error.message }); emit('meetings:updated', { id, status: 'failed' });
      return false;
    } finally { if (currentId === id) currentId = null; }
  }
  function enqueue(id, options) {
    if (scheduled.has(id)) return scheduled.get(id);
    store.writeState(id, { status: 'queued', error: null });
    const promise = chain.then(() => processMeeting(id, options));
    chain = promise.catch(() => {}); scheduled.set(id, promise); promise.finally(() => scheduled.delete(id)).catch(() => {});
    return promise;
  }
  function preview(id, channel, files, offsetSeconds) {
    if (!config.fluidBinary) return Promise.resolve();
    const task = chain.then(async () => {
      if (store.readState(id)?.status !== 'recording') return;
      const dir = path.join(store.dir(id), 'processing'); fs.mkdirSync(dir, { recursive: true });
      const base = `${channel}-preview-${path.basename(files[0], '.wav')}`;
      const audio = path.join(dir, base + '.wav'), output = path.join(dir, base + '.json');
      concatWavFiles(files, audio);
      await new Promise((resolve, reject) => {
        const child = spawn('/usr/bin/sandbox-exec', ['-p', '(version 1)(allow default)(deny network*)', config.fluidBinary, 'transcribe', audio, '--model-version', 'v3', '--word-timestamps', '--output-json', output], { detached: true, stdio: 'ignore' });
        currentChild = child; currentId = id;
        const timeout = setTimeout(() => stopChild(child), 120000);
        child.on('error', reject); child.on('close', code => { clearTimeout(timeout); if (currentChild === child) { currentChild = null; currentId = null; } code === 0 ? resolve() : reject(new Error('Vorläufige lokale Transkription fehlgeschlagen')); });
      });
      if (store.readState(id)?.status !== 'recording') return;
      const result = readJson(output), transcript = store.get(id).transcript;
      const segments = transcript.provisional ? transcript.segments : [];
      if (result.text?.trim()) segments.push({ id: base, channel, tStart: offsetSeconds, tEnd: offsetSeconds + 30,
        speaker: channel === 'mic' ? 'Mikrofon · vorläufig' : 'Systemton · vorläufig', text: result.text });
      segments.sort((a,b) => a.tStart-b.tStart);
      store.saveTranscript(id, { schemaVersion: 2, language: 'de', provisional: true, segments });
      emit('meeting:transcript-chunk', segments);
    });
    chain = task.catch(error => { if (!cancelled.has(id) && store.readState(id)) store.writeState(id, { previewError: error.message }); });
    return chain;
  }
  function resume() {
    for (const entry of store.list()) {
      const state = store.readState(entry.id);
      if (state && ['recording','processing','queued'].includes(state.status)) {
        if (state.status === 'recording') store.writeState(entry.id, { interrupted: true, captureWarning: 'Aufnahme beim letzten Lauf unterbrochen; gespeicherte Abschnitte werden wiederhergestellt.' });
        enqueue(entry.id);
      }
    }
  }
  return { enqueue, resume, prepare, preview, cancel(id) { cancelled.add(id); if (currentId === id) stopChild(currentChild, 'SIGKILL'); }, idle: () => chain, shutdown() { if (currentChild) stopChild(currentChild); } };
}
module.exports = { createLocalPipeline, hashFile };
