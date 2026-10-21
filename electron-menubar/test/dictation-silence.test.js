import { afterEach, describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createDictationJobs } from '../dictation/jobs.js';
import { readResponse, friendlyError } from '../dictation/policies.js';
import { filterTranscription, shouldSkipTranscription, validateVoiceActivity } from '../audio/silence-filter.js';

// Die echten Main-Funktionen mit isoliertem Store/Fenster/Netzwerk ausführen.
// Electron wird weder geladen noch gestartet, es werden keine Hotkeys registriert.
const source = fs.readFileSync(path.join(__dirname, '../electron-main.js'), 'utf8');
const transcribe = source.slice(source.indexOf('async function transcribeAudio('), source.indexOf('// AUTO UPDATER ('));
const audio = source.slice(source.indexOf('let lastAudioBackup ='), source.indexOf('// HOTKEY\n'));
const directories = [];
const silence = { durationMs: 4000, measuredMs: 4000, speechMs: 0, peakDbfs: -120, floorDbfs: -120, maxGapMs: 40 };
const speech = { ...silence, speechMs: 800, peakDbfs: -40 };

function main(response = { text: 'Vielen Dank.' }, settings = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-silence-'));
  directories.push(directory);
  const values = { language: 'de', groqApiKey: 'test-placeholder', enablePolish: true, autopaste: true, ...settings };
  const window = { webContents: { send: vi.fn() }, hide: vi.fn(), showInactive: vi.fn() };
  const context = vm.createContext({
    process: { env: {} }, dictationJobs: createDictationJobs(), friendlyError,
    readResponse: (url, options, ms) => readResponse(url, options, ms, context.fetch),
    savePreviousApp: async () => null, resizeRecordingWindow: vi.fn(), mainWindow: null, isRecording: false,
    Buffer, ArrayBuffer, Uint8Array, Blob, FormData, AbortController, Date,
    fs, path, app: { getPath: () => directory },
    filterTranscription, shouldSkipTranscription, validateVoiceActivity,
    GROQ_API_URL: 'https://example.invalid/transcribe',
    getStore: () => ({ get: key => values[key] }),
    fetch: vi.fn(async () => ({ ok: true, text: async () => JSON.stringify(response) })),
    setTimeout: vi.fn(), clearTimeout: vi.fn(), console: { log: vi.fn(), error: vi.fn() },
    recordingWindow: window, createRecordingWindow: () => window,
    dialog: { showMessageBox: vi.fn() }, isMac: true,
    polishText: vi.fn(async text => text), addToHistory: vi.fn(),
    autopasteText: vi.fn(), clipboard: { writeText: vi.fn() },
  });
  const status = source.slice(source.indexOf('function sendJobStatus('), source.indexOf('async function beginRecording('));
  vm.runInContext(status + '\n' + transcribe + '\n' + audio, context);
  return { context, directory, window };
}

afterEach(() => {
  for (const directory of directories.splice(0)) fs.rmSync(directory, { recursive: true, force: true });
});

describe('Stille im echten Main-Diktat- und Retry-Weg', () => {
  it.each([silence, { ...silence, floorDbfs: -52, peakDbfs: -48 }])('überspringt bei stationärem Signal API, Polishing, Historie und Einfügen und sendet empty (%j)', async meta => {
    const { context, directory, window } = main(undefined, { groqApiKey: '' });
    await context.saveAudioBackup(Buffer.from('audio'), meta);
    const result = await context.processAudioData(Buffer.from('audio'), false, meta);
    expect(result).toEqual({ success: true, empty: true });
    for (const fn of [context.fetch, context.polishText, context.addToHistory, context.autopasteText, context.clipboard.writeText]) {
      expect(fn).not.toHaveBeenCalled();
    }
    expect(window.webContents.send).toHaveBeenCalledWith('status:update', expect.objectContaining({ status: 'empty', detail: '' }));
    expect(context.setTimeout).toHaveBeenCalledWith(expect.any(Function), 900);
    expect(fs.readdirSync(path.join(directory, 'audio-backups'))).toEqual([]);
    expect(context.getAudioBackup()).toBeNull();
  });

  it('behält gesprochene Dankesformeln im kompletten bisherigen Ablauf', async () => {
    const { context, window } = main();
    await context.processAudioData(Buffer.from('audio'), false, speech);
    expect(context.fetch).toHaveBeenCalledTimes(1);
    const body = context.fetch.mock.calls[0][1].body;
    expect(body.get('response_format')).toBe('verbose_json');
    expect(body.get('model')).toBe('whisper-large-v3-turbo');
    expect(body.get('language')).toBe('de');
    expect(context.polishText).toHaveBeenCalledWith('Vielen Dank.', 'de', 'code', null);
    expect(context.addToHistory).toHaveBeenCalledWith({ transcript: 'Vielen Dank.', polished: 'Vielen Dank.', language: 'de' });
    expect(context.autopasteText).toHaveBeenCalledWith('Vielen Dank.', null);
    expect(window.webContents.send).toHaveBeenCalledWith('status:update', expect.objectContaining({ status: 'done', detail: '' }));
  });

  it('sendet auch nach serverseitig verworfenen Segmenten empty und schreibt keine Historie', async () => {
    const { context, window } = main({ text: 'Vielen Dank.', segments: [
      { text: 'Vielen Dank.', no_speech_prob: 0.99, avg_logprob: -1.5 },
    ] });
    await context.processAudioData(Buffer.from('audio'));
    expect(context.fetch).toHaveBeenCalledTimes(1);
    expect(context.addToHistory).not.toHaveBeenCalled();
    expect(context.autopasteText).not.toHaveBeenCalled();
    expect(window.webContents.send).toHaveBeenCalledWith('status:update', expect.objectContaining({ status: 'empty', detail: '' }));
  });

  it('verwirft die real gemessene Groq-Stille-Phrase trotz no_speech_prob=0 bei weniger als 250 ms Aktivität', async () => {
    const { context, window } = main({ text: ' Vielen Dank.', segments: [
      { text: ' Vielen Dank.', no_speech_prob: 0, avg_logprob: -0.28, compression_ratio: 0.62 },
    ] });
    await context.processAudioData(Buffer.from('audio'), false, { ...speech, speechMs: 200 });
    expect(context.fetch).toHaveBeenCalledTimes(1);
    expect(context.addToHistory).not.toHaveBeenCalled();
    expect(context.autopasteText).not.toHaveBeenCalled();
    expect(window.webContents.send).toHaveBeenCalledWith('status:update', expect.objectContaining({ status: 'empty', detail: '' }));
  });

  it('verwirft eindeutige Artefakte auch beim Retry eines alten Backups ohne Metadaten', async () => {
    const { context } = main({ text: 'Untertitel im Auftrag des ZDF, 2017' });
    await context.saveAudioBackup(Buffer.from('audio'));
    vm.runInContext('lastAudioBackup = null; backupTimestamp = null;', context);
    await context.retryLastRecording();
    expect(context.fetch).toHaveBeenCalledTimes(1);
    expect(context.addToHistory).not.toHaveBeenCalled();
    expect(context.autopasteText).not.toHaveBeenCalled();
    expect(context.getAudioBackup()).toBeNull();
  });

  it('behält Audio und Metadaten nach einem API-Fehler für Retry', async () => {
    const { context } = main();
    context.fetch.mockRejectedValueOnce(new Error('Testfehler'));
    await context.saveAudioBackup(Buffer.from('audio'), speech);
    const result = await context.processAudioData(Buffer.from('audio'), false, speech);
    expect(result.success).toBe(false);
    expect(context.getAudioBackup()).toEqual(Buffer.from('audio'));
    await context.retryLastRecording();
    expect(context.fetch).toHaveBeenCalledTimes(2);
    expect(context.autopasteText).toHaveBeenCalledWith('Vielen Dank.', null);
  });

  it.each(['RAM', 'Festplatte'])('nutzt gesicherte Stille-Metadaten beim Retry aus %s', async origin => {
    const { context } = main();
    await context.saveAudioBackup(Buffer.from('audio'), silence);
    if (origin === 'Festplatte') vm.runInContext('lastAudioBackup = null; lastAudioVoiceActivity = undefined; backupTimestamp = null;', context);
    await context.retryLastRecording();
    expect(context.fetch).not.toHaveBeenCalled();
    expect(context.addToHistory).not.toHaveBeenCalled();
    expect(context.getAudioBackup()).toBeNull();
  });

  it.each(['fehlend', 'beschädigt', 'alt'])('verarbeitet alte Backups ohne nutzbare Metadaten (%s) weiter', async metadata => {
    const { context, directory } = main();
    await context.saveAudioBackup(Buffer.from('audio'));
    const backupDir = path.join(directory, 'audio-backups');
    if (metadata !== 'fehlend') {
      const name = fs.readdirSync(backupDir).find(name => name.endsWith('.webm'));
      const { floorDbfs, ...oldMeta } = silence;
      fs.writeFileSync(path.join(backupDir, `${name}.json`), metadata === 'alt' ? JSON.stringify(oldMeta) : '{kaputt');
    }
    vm.runInContext('lastAudioBackup = null; backupTimestamp = null;', context);
    await context.retryLastRecording();
    expect(context.fetch).toHaveBeenCalledTimes(1);
    expect(context.autopasteText).toHaveBeenCalledWith('Vielen Dank.', null);
  });
});
