import { WHISPER_MODEL, userLanguages, guardedTranscription } from '../../dictation/language-guard.js';
import { primer, buildPrompt, removeEchoes } from '../../dictation/whisper-prompt.js';
import { vocabularyPrompt, uncertainSegments, buildPolishMessages, recentRawDictations, isVocabularyEcho } from '../../dictation/polish-prompt.js';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { isBackupAtOrBefore, compareBackups } from '../../dictation/backup-order.js';
import { vi } from 'vitest';
import { createDictationJobs } from '../../dictation/jobs.js';
import { readResponse, friendlyError, explainDictationStatus, replaceShortcut, polishTokenBudget, completePolish, retryAfterMs, transcriptionTimeoutMs, transcriptionBudgetMs } from '../../dictation/policies.js';
import { filterTranscription, shouldSkipTranscription, validateVoiceActivity, isSilentSegment } from '../../audio/silence-filter.js';

export const source = fs.readFileSync(path.join(__dirname, '../../electron-main.js'), 'utf8');
export const speech = { durationMs: 4000, measuredMs: 4000, speechMs: 800, peakDbfs: -40, floorDbfs: -62, maxGapMs: 40 };
export const tick = async () => { for (let i = 0; i < 15; i++) await Promise.resolve(); };
export function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
export function makeMain(platform = 'darwin', settings = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-dictation-'));
  const values = { language: 'de', groqApiKey: 'test-placeholder', enablePolish: true, autopaste: true, shortcut: 'Alt+Command+K', ...settings };
  const win = { webContents: { send: vi.fn(), isLoading: () => false }, hide: vi.fn(), showInactive: vi.fn(), isDestroyed: () => false, destroy: vi.fn(), setBounds: vi.fn() };
  const timers = [];
  const ipc = {};
  const context = vm.createContext({
    WHISPER_MODEL, userLanguages, guardedTranscription, primer, buildPrompt, removeEchoes,
    Buffer, ArrayBuffer, Uint8Array, Blob, FormData, AbortController, Date, fs, path,
    notesBridge: { dictationState: vi.fn(), meetingStarted: vi.fn() },
    process: { env: {}, platform },
    app: { getPreferredSystemLanguages: () => ['de-DE'], getPath: () => directory }, screen: { getPrimaryDisplay: () => ({ workAreaSize: { width: 1440, height: 900 } }) }, isMac: platform === 'darwin', isWin: platform === 'win32',
    dictationJobs: createDictationJobs(), friendlyError, explainDictationStatus, replaceShortcut, polishTokenBudget, completePolish, retryAfterMs, transcriptionTimeoutMs, transcriptionBudgetMs,
    readResponse: (url, options, ms) => readResponse(url, options, ms, context.fetch),
    vocabularyPrompt, uncertainSegments, buildPolishMessages, recentRawDictations, isVocabularyEcho,
    filterTranscription, shouldSkipTranscription, validateVoiceActivity, isSilentSegment, isBackupAtOrBefore, compareBackups,
    GROQ_API_URL: 'https://example.invalid/transcribe', GROQ_CHAT_URL: 'https://example.invalid/polish',
    getStore: () => ({ get: (key, fallback) => values[key] ?? fallback, set: vi.fn((key, value) => { values[key] = value; }), store: values }),
    fetch: vi.fn(async () => ({ ok: true, text: async () => JSON.stringify({ text: 'Gesprochener Text' }) })),
    setTimeout: vi.fn((fn, ms) => { const timer = { fn, ms }; timers.push(timer); return timer; }),
    clearTimeout: vi.fn(timer => { if (timer) timer.cancelled = true; }),
    console: { log: vi.fn(), error: vi.fn() },
    positionRecordingWindow: vi.fn(), recordingWindow: win, mainWindow: win, createRecordingWindow: () => win,
    dialog: { showMessageBox: vi.fn() },
    savePreviousApp: vi.fn(async () => platform === 'darwin' ? 'Editor' : '123'),
    polishText: vi.fn(async text => text), runPolish: { prefetch: vi.fn() }, addToHistory: vi.fn(), updateStats: vi.fn(),
    autopasteText: vi.fn(async () => true), clipboard: { writeText: vi.fn() },
    ipcMain: { on: (name, fn) => { ipc[name] = fn; }, handle: (name, fn) => { ipc[name] = fn; } },
    changeDictationShortcut: vi.fn(() => true), updateTrayMenu: vi.fn(),
  });
  const lifecycle = source.slice(source.indexOf('function publishRecordingState('), source.indexOf('// PUSH-TO-TALK LOGIC'));
  const recovery = source.slice(source.indexOf('function restartRecordingWindow('), source.indexOf('// Overlay-Fenster wird'));
  const ptt = source.slice(source.indexOf('function handleHotkeyDown('), source.indexOf('// AUDIO BACKUP SYSTEM'));
  const transcribe = source.slice(source.indexOf('async function transcribeAudio('), source.indexOf('// AUTO UPDATER ('));
  const audio = source.slice(source.indexOf('let lastAudioBackup ='), source.indexOf('// HOTKEY\n'));
  const recordingIpc = source.slice(source.indexOf('  const fromRecorder ='), source.indexOf("  ipcMain.on('open:accessibility'"));
  const settingsIpc = source.slice(source.indexOf("  ipcMain.handle('settings:set'"), source.indexOf('  // History\n', source.indexOf("  ipcMain.handle('settings:set'")));
  vm.runInContext(`let isRecording = false; let pttKeyDownTime = null; let pttIsHolding = false; let pttHoldTimer = null;\n${lifecycle}\n${recovery}\n${ptt}\n${transcribe}\n${audio}\n${recordingIpc}\n${settingsIpc}`, context);
  return { context, win, timers, ipc, values, directory, event: { sender: win.webContents },
    state: () => vm.runInContext('isRecording', context),
    dispose: () => fs.rmSync(directory, { recursive: true, force: true }) };
}
