import { afterEach, describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { makeMain, speech, deferred, tick, source } from './helpers/dictation-main.js';
const fixtures = [];
function main(...args) { const fixture = makeMain(...args); fixtures.push(fixture); return fixture; }
afterEach(() => fixtures.splice(0).forEach(fixture => fixture.dispose()));

for (const platform of ['darwin', 'win32']) describe(`Diktat auf ${platform}`, () => {
  it('verwirft Start nach Stop während der Ziel-Ermittlung, neuer Start bleibt gültig', async () => {
    const { context: c, win, state } = main(platform);
    const target = deferred();
    c.savePreviousApp.mockReturnValueOnce(target.promise);
    const first = c.beginRecording();
    c.stopRecording();
    await c.beginRecording();
    const current = c.dictationJobs.current;
    target.resolve('Old target'); await first;
    expect(state()).toBe(true);
    expect(win.webContents.send.mock.calls.filter(([name]) => name === 'recording:start')).toEqual([['recording:start', { jobId: current.id }]]);
  });

  it('setzt fehlgeschlagenen Mikrofonstart zurück, nächster Hotkey startet direkt', async () => {
    const { context: c, ipc, event, state, win } = main(platform);
    await c.beginRecording(); const id = c.dictationJobs.current.id;
    ipc['recording:failed'](event, { jobId: id, message: 'NotAllowedError: microphone' });
    expect(state()).toBe(false);
    expect(c.dictationJobs.get(id)).toBeUndefined();
    const error = win.webContents.send.mock.calls.find(([, data]) => data?.status === 'error')[1].detail;
    expect(error).toContain(platform === 'darwin' ? 'Systemeinstellungen' : 'Windows-Einstellungen');
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
    expect(done.detail).toContain('In Zwischenablage kopiert');
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

it('unterdrückt bei Hintergrund-Updates sämtliche Dialoge, manuelle Prüfung zeigt sie', async () => {
  const { EventEmitter } = await import('node:events');
  const updater = new EventEmitter(); updater.checkForUpdates = vi.fn(async () => {});
  const context = vm.createContext({ getAutoUpdater: () => updater, console, CURRENT_VERSION: '1',
    dialog: { showMessageBox: vi.fn(async () => ({ response: 1 })) },
    shell: { openExternal: vi.fn() }, GITHUB_REPO: 'test/repo', checkForUpdatesManual: vi.fn() });
  const code = source.slice(source.indexOf('function setupAutoUpdater('), source.indexOf('// Fallback manual update check'));
  vm.runInContext(`let updateCheckSilent = true; let updateCheckInProgress = false; let downloadInProgress = false;\n${code}`, context);
  context.setupAutoUpdater();
  for (const event of ['update-not-available', 'update-available', 'error']) {
    await context.checkForUpdates(true); updater.emit(event, { version: '1', message: 'Failure' });
  }
  expect(context.dialog.showMessageBox).not.toHaveBeenCalled();
  await context.checkForUpdates(false); updater.emit('update-not-available', { version: '1' });
  expect(context.dialog.showMessageBox).toHaveBeenCalledOnce();
});

it('zweite Instanz initialisiert weder Manager noch Hotkeys', () => {
  const app = { requestSingleInstanceLock: () => false, quit: vi.fn() };
  const requireMock = vi.fn(name => { if (name === 'electron') return { app }; throw Error('Unexpected initialization: ' + name); });
  vm.runInNewContext(source, { require: requireMock });
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
  c.getPolishPrompt = text => text;
  const polish = source.slice(source.indexOf('async function polishText('), source.indexOf('// WINDOWS\n'));
  vm.runInContext(polish, c);
  c.fetch.mockResolvedValueOnce({ ok: true, text: async () => JSON.stringify({ text: original }) })
    .mockResolvedValueOnce({ ok: true, text: async () => JSON.stringify({ choices: [{ finish_reason: 'length', message: { content: 'Abgeschnitten.' } }] }) });
  const result = await c.processAudioData(Buffer.from('audio'), false, speech);
  expect(result.polished).toBeNull();
  expect(c.autopasteText).toHaveBeenCalledWith(original.trim(), null);
  const payload = JSON.parse(c.fetch.mock.calls[1][1].body);
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
