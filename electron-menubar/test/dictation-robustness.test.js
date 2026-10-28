import { createPolishClient } from '../dictation/polish-client.js';
import { afterEach, describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { EventEmitter } from 'node:events';
import { makeMain, speech, deferred, tick, source } from './helpers/dictation-main.js';
const fixtures = [];
function main(...args) { const fixture = makeMain(...args); fixtures.push(fixture); return fixture; }
afterEach(() => fixtures.splice(0).forEach(fixture => fixture.dispose()));

for (const platform of ['darwin', 'win32']) describe(`Diktat auf ${platform}`, () => {
  it('startet ohne auf die Ziel-Ermittlung zu warten; Stop bricht den ersten Auftrag ab, neuer Start bleibt gültig', async () => {
    const { context: c, win, state } = main(platform);
    const target = deferred();
    c.savePreviousApp.mockReturnValueOnce(target.promise);
    const first = c.beginRecording();
    const firstId = c.dictationJobs.current.id;
    // Aufnahme-Start geht sofort raus, obwohl die Ziel-App noch ermittelt wird.
    expect(win.webContents.send).toHaveBeenCalledWith('recording:start', { jobId: firstId });
    c.stopRecording();
    await c.beginRecording();
    const current = c.dictationJobs.current;
    target.resolve('Old target'); await first;
    expect(state()).toBe(true);
    expect(current.id).not.toBe(firstId);
    const calls = win.webContents.send.mock.calls.filter(([name]) => name === 'recording:start' || name === 'recording:stop');
    expect(calls).toEqual([
      ['recording:start', { jobId: firstId }],
      ['recording:stop', { jobId: firstId }],
      ['recording:start', { jobId: current.id }],
    ]);
  });

  it('lädt die Polier-Modellliste erst nach dem Aufnahmestart vor, nur mit Polieren', async () => {
    const { context: c, win, values } = main(platform);
    c.runPolish.prefetch.mockImplementationOnce(() => {
      expect(win.webContents.send).toHaveBeenCalledWith('recording:start', expect.anything());
    });
    await c.beginRecording();
    expect(c.runPolish.prefetch).toHaveBeenCalledExactlyOnceWith('test-placeholder');
    c.stopRecording(); values.enablePolish = false;
    await c.beginRecording();
    expect(c.runPolish.prefetch).toHaveBeenCalledOnce();
  });

  it('startet die Aufnahme auch, wenn das Vorladen scheitert', async () => {
    const { context: c, state } = main(platform);
    c.runPolish.prefetch.mockImplementationOnce(() => { throw new Error('kaputt'); });
    await c.beginRecording();
    expect(state()).toBe(true); expect(c.dictationJobs.current.phase).toBe('requested');
  });

  it('setzt fehlgeschlagenen Mikrofonstart zurück, nächster Hotkey startet direkt', async () => {
    const { context: c, ipc, event, state, win } = main(platform);
    await c.beginRecording(); const id = c.dictationJobs.current.id;
    ipc['recording:failed'](event, { jobId: id, message: 'NotAllowedError: microphone' });
    expect(state()).toBe(false);
    expect(c.dictationJobs.get(id)).toBeUndefined();
    const errors = win.webContents.send.mock.calls.filter(([, data]) => data?.status === 'error').map(([, data]) => data.detail);
    expect(errors).toContain('Mikrofon gesperrt');
    expect(errors.some(error => error.includes(platform === 'darwin' ? 'Systemeinstellungen' : 'Windows-Einstellungen'))).toBe(true);
    c.handleHotkeyDown(); await tick();
    expect(state()).toBe(true);
    expect(c.dictationJobs.current.id).not.toBe(id);
  });

  it('ignoriert verspätete Bestätigung und Audio eines abgebrochenen Starts', async () => {
    const { context: c, ipc, event, state } = main(platform);
    await c.beginRecording(); const id = c.dictationJobs.current.id;
    c.stopRecording();
    ipc['recording:started'](event, { jobId: id });
    await ipc['recording:audio'](event, Buffer.from('late'), speech, id);
    expect(state()).toBe(false);
    expect(c.fetch).not.toHaveBeenCalled();
    expect(c.dictationJobs.get(id)).toBeUndefined();
  });

  it('ordnet spätes altes Ergebnis vor schnellem neuen ein und behält Ziel + Backup getrennt', async () => {
    const { context: c, ipc, event, win, directory } = main(platform);
    const firstResponse = deferred();
    c.fetch.mockReturnValueOnce(firstResponse.promise);
    c.savePreviousApp.mockResolvedValueOnce('First target').mockResolvedValueOnce('Second target');
    await c.beginRecording(); const first = c.dictationJobs.current;
    ipc['recording:started'](event, { jobId: first.id }); c.stopRecording();
    const firstWork = ipc['recording:audio'](event, Buffer.from('first'), speech, first.id);
    // Wait for actual disk persistence before starting second HTTP response.
    for (let i = 0; !c.fetch.mock.calls.length && i < 100; i++) await new Promise(resolve => setTimeout(resolve, 1));
    expect(c.fetch).toHaveBeenCalledTimes(1);
    await c.beginRecording(); const second = c.dictationJobs.current;
    ipc['recording:started'](event, { jobId: second.id }); c.stopRecording();
    const secondWork = ipc['recording:audio'](event, Buffer.from('second'), speech, second.id);
    for (let i = 0; c.fetch.mock.calls.length < 2 && i < 100; i++) await new Promise(resolve => setTimeout(resolve, 1));
    expect(c.fetch).toHaveBeenCalledTimes(2);
    await tick();
    expect(c.autopasteText).not.toHaveBeenCalled();
    // Keep newer backup even when older successful paste clears its own backup.
    const pastedFirst = deferred();
    c.autopasteText.mockImplementationOnce(() => pastedFirst.promise);
    firstResponse.resolve({ ok: true, text: async () => JSON.stringify({ text: 'Erstes Diktat' }) });
    await tick();
    expect(c.autopasteText).toHaveBeenCalledWith('Erstes Diktat', 'First target');
    expect(c.getAudioBackup()).toEqual(Buffer.from('second'));
    win.webContents.send.mockClear();
    pastedFirst.resolve(true); await firstWork;
    expect(fs.readdirSync(path.join(directory, 'audio-backups')).some(name => name.includes(second.id))).toBe(true);
    await secondWork;
    expect(c.autopasteText.mock.calls).toEqual([['Erstes Diktat', 'First target'], ['Gesprochener Text', 'Second target']]);
    expect(win.webContents.send.mock.calls.every(([, data]) => !data?.jobId || data.jobId === second.id)).toBe(true);
  });

  it('lässt nach Einfügefehler Text kopiert und zeigt den passenden Tastaturhinweis', async () => {
    const { context: c, win } = main(platform);
    c.autopasteText.mockResolvedValueOnce(false);
    await c.processAudioData(Buffer.from('audio'), false, speech);
    const done = win.webContents.send.mock.calls.filter(([, data]) => data?.status === 'done').at(-1)[1];
    expect(done.detail).toContain(platform === 'darwin' ? 'Cmd+V' : 'Ctrl+V');
    const details = win.webContents.send.mock.calls.filter(([, data]) => data?.status === 'done').map(([, data]) => data.detail);
    expect(details).toContain(platform === 'darwin' ? 'Kopiert – ⌘V drücken' : 'Kopiert – Strg+V drücken');
  });

  it('ignoriert normales Key-up nach kurzem Hotkey-Tippen', async () => {
    const { context: c, state } = main(platform);
    c.handleHotkeyDown(); await tick(); c.handleHotkeyUp();
    c.handleHotkeyUp();
    expect(state()).toBe(true);
    c.handleHotkeyDown();
    expect(state()).toBe(false);
  });

  it('älterer Ausblendtimer kann ein neueres Widget nicht verstecken', async () => {
    const { context: c, timers, win } = main(platform);
    await c.processAudioData(Buffer.from('audio'), false, speech);
    const hide = timers.find(timer => timer.ms === 300);
    await c.beginRecording(); hide.fn();
    expect(win.hide).not.toHaveBeenCalled();
    expect(timers.filter(timer => timer.ms === 200)).toHaveLength(0);
  });

  it('sendet leaving und versteckt erst 200 ms später', async () => {
    const { context: c, timers, win } = main(platform);
    await c.processAudioData(Buffer.from('audio'), false, speech);
    timers.find(timer => timer.ms === 300).fn();
    expect(win.hide).not.toHaveBeenCalled();
    expect(win.webContents.send).toHaveBeenCalledWith('status:update', expect.objectContaining({ status: 'leaving' }));
    timers.find(timer => timer.ms === 200).fn();
    expect(win.hide).toHaveBeenCalledOnce();
  });
});

it('wiederholt bei langem Groq-Limit (429, Retry-After > 10 s) nicht stur', async () => {
  const { context: c, timers } = main();
  c.fetch.mockResolvedValue({ ok: false, status: 429, headers: { get: () => '600' }, text: async () => '{}' });
  await expect(c.transcribeAudio(Buffer.from('audio'), 'de', 3, speech)).rejects.toMatchObject({ status: 429 });
  expect(c.fetch).toHaveBeenCalledOnce(); expect(timers).toHaveLength(0);
});

it('wartet bei kurzem Groq-Limit die genannte Zeit und versucht es erneut', async () => {
  const { context: c, timers } = main();
  c.fetch.mockResolvedValueOnce({ ok: false, status: 429, headers: { get: () => '4' }, text: async () => '{}' });
  const work = c.transcribeAudio(Buffer.from('audio'), 'de', 3, speech);
  await tick(); await tick();
  expect(timers.map(timer => timer.ms)).toEqual([4000]);
  timers[0].fn();
  expect(await work).toBe('Gesprochener Text'); expect(c.fetch).toHaveBeenCalledTimes(2);
});

it('wiederholt hängende Uploads nur, solange das bisherige Gesamtbudget reicht', async () => {
  const { context: c, timers } = main();
  let now = 0;
  c.Date = class extends Date { static now() { return now; } };
  const aborted = () => Object.assign(new Error('This operation was aborted'), { name: 'AbortError' });
  c.fetch.mockImplementation(async () => { now += 239000; throw aborted(); });
  await expect(c.transcribeAudio(Buffer.from('audio'), 'de', 3, speech)).rejects.toMatchObject({ name: 'AbortError' });
  expect(c.fetch).toHaveBeenCalledOnce(); expect(timers).toHaveLength(0);
  now = 0; c.fetch.mockReset();
  c.fetch.mockImplementationOnce(async () => { now += 60000; throw aborted(); });
  const work = c.transcribeAudio(Buffer.from('audio'), 'de', 3, speech);
  await tick(); await tick();
  expect(timers.map(timer => timer.ms)).toEqual([1000]);
  c.fetch.mockResolvedValueOnce({ ok: true, text: async () => JSON.stringify({ text: 'Gesprochener Text' }) });
  timers[0].fn();
  expect(await work).toBe('Gesprochener Text');
});

it('zählt einen Fehler genau einmal je Aufnahme, nicht beim Wiederholen', async () => {
  const { context: c } = main();
  c.fetch.mockResolvedValue({ ok: false, status: 401, text: async () => '{}' });
  await c.processAudioData(Buffer.from('audio'), false, speech);
  expect(c.updateStats).toHaveBeenCalledExactlyOnceWith(0, 0, true);
  await c.processAudioData(Buffer.from('audio'), true, speech);
  expect(c.updateStats).toHaveBeenCalledOnce();
});

it('gibt dem Verlauf die gemessene Aufnahmedauer für die Minuten-Statistik mit', async () => {
  const { context: c } = main();
  await c.processAudioData(Buffer.from('audio'), false, speech);
  expect(c.addToHistory).toHaveBeenCalledWith(expect.objectContaining({ durationMinutes: speech.durationMs / 60000 }));
});

it('gibt dem Upload je nach Dateigröße mehr Zeit', async () => {
  const { context: c } = main();
  const original = c.readResponse; c.readResponse = vi.fn(original);
  await c.transcribeAudio(Buffer.alloc(640000), 'de', 0, speech);
  expect(c.readResponse.mock.calls[0][2]).toBe(70000);
});

it('speichert bei ungültigem neuen Kürzel gar keine Einstellungen und liefert strukturierten Fehler', async () => {
  const { context: c, ipc, values } = main();
  c.changeDictationShortcut.mockReturnValueOnce(false);
  const result = await ipc['settings:set']({}, { shortcut: 'Invalid+Key', language: 'en' });
  expect(result).toEqual({ success: false, error: { code: 'HOTKEY_REGISTRATION_FAILED', field: 'shortcut', message: expect.any(String) } });
  expect(values.shortcut).toBe('Alt+Command+K'); expect(values.language).toBe('de');
});

it('bereinigt abgelaufene Backups beim Speichern und löscht nur das eigene Backup', async () => {
  const { context: c, directory } = main();
  const dir = path.join(directory, 'audio-backups'); fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, `backup_${Date.now() - 25 * 3600000}.webm`), 'old');
  await c.saveAudioBackup(Buffer.from('first'), speech, 'first');
  await c.saveAudioBackup(Buffer.from('second'), speech, 'second');
  expect(fs.readdirSync(dir)).toHaveLength(4);
  c.clearAudioBackup('first');
  expect(fs.readdirSync(dir)).toHaveLength(2);
  expect(c.getAudioBackup()).toEqual(Buffer.from('second'));
});

it('protokolliert Text nur mit PAPLY_DEBUG_TEXT=1', async () => {
  const { context: c } = main();
  await c.processAudioData(Buffer.from('audio'), false, speech);
  expect(JSON.stringify(c.console.log.mock.calls)).not.toContain('Gesprochener Text');
  c.process.env.PAPLY_DEBUG_TEXT = '1';
  await c.processAudioData(Buffer.from('audio'), false, speech);
  expect(JSON.stringify(c.console.log.mock.calls)).toContain('Gesprochener Text');
});

it('Hintergrund-Prüfung: still bei „kein Update“ und Prüffehler, meldet aber neue Versionen', async () => {
  const { EventEmitter } = await import('node:events');
  const updater = new EventEmitter(); updater.checkForUpdates = vi.fn(async () => {});
  const context = vm.createContext({ getAutoUpdater: () => updater, console, CURRENT_VERSION: '1', process: { env: {} },
    dialog: { showMessageBox: vi.fn(async () => ({ response: 1 })) },
    shell: { openExternal: vi.fn() }, GITHUB_REPO: 'test/repo', checkForUpdatesManual: vi.fn() });
  const code = source.slice(source.indexOf('function setupAutoUpdater('), source.indexOf('// Fallback manual update check'));
  vm.runInContext(`let updateCheckSilent = true; let updateCheckInProgress = false; let downloadInProgress = false;\n${code}`, context);
  context.setupAutoUpdater();
  for (const event of ['update-not-available', 'error']) {
    await context.checkForUpdates(true); updater.emit(event, { version: '1', message: 'Failure' });
  }
  expect(context.dialog.showMessageBox).not.toHaveBeenCalled();
  await context.checkForUpdates(true); updater.emit('update-available', { version: '2' });
  expect(context.dialog.showMessageBox).toHaveBeenCalledOnce();
  expect(context.dialog.showMessageBox.mock.calls[0][0].title).toBe('Update verfügbar!');
  await context.checkForUpdates(false); updater.emit('update-not-available', { version: '1' });
  expect(context.dialog.showMessageBox).toHaveBeenCalledTimes(2);
});

it('zweite Instanz initialisiert weder Manager noch Hotkeys', () => {
  const app = { requestSingleInstanceLock: () => false, quit: vi.fn() };
  const requireMock = vi.fn(name => { if (name === 'electron') return { app }; throw Error('Unexpected initialization: ' + name); });
  vm.runInNewContext(source, { require: requireMock, process: { env: {} }, console });
  expect(app.quit).toHaveBeenCalledOnce(); expect(requireMock).toHaveBeenCalledOnce();
});

it('später Mac-Einfügefehler ersetzt den bereits geplanten Erfolg-Ausblendtimer', async () => {
  const { context: c, timers, win } = main('darwin');
  c.autopasteText.mockResolvedValueOnce(false);
  await c.processAudioData(Buffer.from('audio'), false, speech);
  timers.find(timer => timer.ms === 300).fn();
  expect(timers.filter(timer => timer.ms === 200)).toHaveLength(0);
  expect(win.hide).not.toHaveBeenCalled();
  timers.find(timer => timer.ms === 5000).fn();
  expect(timers.filter(timer => timer.ms === 200)).toHaveLength(1);
});

for (const platform of ['darwin', 'win32']) it(`nutzt bei abgeschnittenem Polish auf ${platform} das vollständige Original`, async () => {
  const { context: c } = main(platform);
  const original = 'Sehr langes Diktat. '.repeat(2000);
  c.runPolish = createPolishClient({ request: c.readResponse });
  const polish = source.slice(source.indexOf('async function polishText('), source.indexOf('// WINDOWS\n'));
  vm.runInContext(polish, c);
  c.fetch.mockResolvedValueOnce({ ok: true, text: async () => JSON.stringify({ text: original }) })
    .mockResolvedValueOnce({ ok: true, text: async () => JSON.stringify({ data: [{ id: 'qwen/qwen3.8-27b' }] }) })
    .mockResolvedValueOnce({ ok: true, text: async () => JSON.stringify({ choices: [{ finish_reason: 'length', message: { content: 'Abgeschnitten.' } }] }) });
  const result = await c.processAudioData(Buffer.from('audio'), false, speech);
  expect(result.polished).toBeNull();
  expect(c.autopasteText).toHaveBeenCalledWith(original.trim(), null);
  const payload = JSON.parse(c.fetch.mock.calls[2][1].body);
  expect(payload.max_tokens).toBeGreaterThan(1024);
  expect(payload.max_tokens).toBeLessThanOrEqual(32768);
});

it('zeigt Mac-Fallback erneut, wenn osascript erst nach dem Ausblenden scheitert', async () => {
  const { context: c, timers, win } = main('darwin');
  const paste = deferred(); c.autopasteText.mockReturnValueOnce(paste.promise);
  const work = c.processAudioData(Buffer.from('audio'), false, speech);
  await tick();
  timers.find(timer => timer.ms === 300).fn(); timers.find(timer => timer.ms === 200).fn();
  expect(win.hide).toHaveBeenCalledOnce();
  paste.resolve(false); await work;
  expect(win.showInactive).toHaveBeenCalledOnce();
});

for (const platform of ['darwin', 'win32']) it(`übernimmt Agent-Wechsel während der Aufnahme auf ${platform}, hält Einstellungen danach fest`, async () => {
  const { context: c, values, ipc, event } = main(platform);
  values.profiles = { dictation: { polishFlavor: 'plain' } };
  await c.beginRecording(); const job = c.dictationJobs.current;
  expect(job.settings).toBeNull();
  ipc['recording:started'](event, { jobId: job.id });
  values.activeProfile = 'dictation'; values.language = 'en'; values.autopaste = false; values.copyToClipboard = true;
  c.stopRecording();
  values.activeProfile = 'coding'; values.language = 'de'; values.autopaste = true;
  await ipc['recording:audio'](event, Buffer.from('audio'), speech, job.id);
  expect(c.polishText).toHaveBeenCalledWith('Gesprochener Text', 'en', 'plain', null, []);
  expect(c.autopasteText).not.toHaveBeenCalled();
  expect(c.clipboard.writeText).toHaveBeenCalledWith('Gesprochener Text');
});

it('Erfolg löscht auch ältere Fehler aus vorherigen App-Läufen, Retry holt sie nicht zurück', async () => {
  const { context: c, directory } = main();
  const dir = path.join(directory, 'audio-backups'); fs.mkdirSync(dir);
  const old = `backup_${Date.now() - 10000}.webm`;
  fs.writeFileSync(path.join(dir, old), 'old failure'); fs.writeFileSync(path.join(dir, old + '.json'), '{}');
  const job = c.dictationJobs.create(); job.backupId = job.id;
  await c.saveAudioBackup(Buffer.from('success'), speech, job.id);
  await c.processAudioData(Buffer.from('success'), false, speech, job);
  expect(fs.readdirSync(dir)).toEqual([]); expect(c.getAudioBackup()).toBeNull();
  const fetchCount = c.fetch.mock.calls.length;
  await c.retryLastRecording(); expect(c.fetch).toHaveBeenCalledTimes(fetchCount);
  expect(c.dialog.showMessageBox).toHaveBeenCalledOnce();
});

it('Erfolg bereinigt nach Aufnahmestart statt verspätetem Audio-Eingang und schützt neuere Backups', async () => {
  const { context: c } = main(); const time = Date.now();
  const olderId = `${time}-1`; const newerId = `${time}-2`;
  await c.saveAudioBackup(Buffer.from('new'), speech, newerId);
  await c.saveAudioBackup(Buffer.from('old'), speech, olderId);
  expect(c.getAudioBackup()).toEqual(Buffer.from('new'));
  c.clearSuccessfulBackups(olderId);
  expect(c.getAudioBackup()).toEqual(Buffer.from('new'));
  c.clearSuccessfulBackups(newerId);
  expect(c.getAudioBackup()).toBeNull();
});

it('Retry ist schon während der Ziel-Ermittlung processing und wird von failRecording nicht doppelt beendet', async () => {
  const { context: c } = main(); await c.saveAudioBackup(Buffer.from('audio'), speech);
  const target = deferred(); c.savePreviousApp.mockReturnValueOnce(target.promise);
  const retry = c.retryLastRecording(); const job = c.dictationJobs.current;
  const finish = vi.fn(job.finish); job.finish = finish;
  expect(job.phase).toBe('processing');
  c.failRecording(job, 'Aufnahme neu gestartet');
  expect(c.dictationJobs.get(job.id)).toBe(job); expect(finish).not.toHaveBeenCalled();
  target.resolve('Editor'); await retry;
  expect(job.phase).toBe('finished'); expect(finish).toHaveBeenCalledOnce();
});

for (const platform of ['darwin', 'win32']) it(`ersetzt abgestürzten Renderer auf ${platform} und startet nächstes Diktat ohne 30-s-Timeout`, async () => {
  const { context: c, win, ipc, event, state } = main(platform);
  await c.beginRecording(); const failed = c.dictationJobs.current;
  ipc['recording:started'](event, { jobId: failed.id });
  const webContents = new EventEmitter(); webContents.send = vi.fn(); webContents.isLoading = () => false;
  const replacement = { webContents, showInactive: vi.fn() };
  c.createRecordingWindow = vi.fn(() => { c.recordingWindow = replacement; return replacement; });
  c.restartRecordingWindow(win);
  expect(win.destroy).toHaveBeenCalledOnce(); expect(c.createRecordingWindow).toHaveBeenCalledOnce();
  expect(state()).toBe(false); expect(c.dictationJobs.get(failed.id)).toBeUndefined();
  webContents.emit('did-finish-load');
  expect(webContents.send).toHaveBeenCalledWith('status:update', expect.objectContaining({ status: 'error', detail: 'Aufnahme neu gestartet' }));
  await c.beginRecording();
  expect(state()).toBe(true); expect(c.dictationJobs.current.phase).toBe('requested');
  expect(webContents.send).toHaveBeenCalledWith('recording:start', { jobId: c.dictationJobs.current.id });
  // A stale crash notification cannot destroy the fresh renderer.
  c.restartRecordingWindow(win); expect(c.createRecordingWindow).toHaveBeenCalledTimes(2);
});

it('stellt nach Neustart das jüngste Diktat statt den zuletzt geschriebenen älteren Auftrag wieder her', () => {
  const { context: c, directory } = main();
  const dir = path.join(directory, 'audio-backups'); fs.mkdirSync(dir);
  const time = Date.now();
  fs.writeFileSync(path.join(dir, `backup_${time}-${time - 1000}-1.webm`), 'older');
  fs.writeFileSync(path.join(dir, `backup_${time - 100}-${time - 500}-2.webm`), 'newer');
  expect(c.getAudioBackup()).toEqual(Buffer.from('newer'));
});
