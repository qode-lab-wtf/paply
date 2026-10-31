// Führt den echten Main-Code mit vollständig ersetztem Electron aus.
// Keine App, globalen Hotkeys, Mikrofone, Helferprozesse oder Nutzerdaten.
import { describe, it, expect, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { EventEmitter } from 'node:events';

const root = path.resolve(__dirname, '..');
const realRequire = createRequire(path.join(root, 'electron-main.js'));

function harness({ platform = 'win32', persisted = {}, polishFactory, logPath = '/test-only/logs/paply.log' } = {}) {
  let ready;
  const handlers = new Map();
  const data = { ...persisted };
  const helpers = [];
  class Helper extends EventEmitter {
    constructor() { super(); this.start = vi.fn(); this.stop = vi.fn(); helpers.push(this); }
  }
  class Store {
    constructor({ defaults }) { this.defaults = defaults; }
    get(key, fallback) { return key in data ? data[key] : key in this.defaults ? this.defaults[key] : fallback; }
    set(key, value) { data[key] = value; }
  }
  const controller = {
    start: vi.fn(), stop: vi.fn(), isActive: vi.fn(() => false), getStatus: vi.fn(() => ({ active: false })),
    resumePending: vi.fn(), runRetention: vi.fn(),
  };
  const electron = {
    protocol: { registerSchemesAsPrivileged: vi.fn() },
    app: { getPreferredSystemLanguages: () => ['de-DE'], whenReady: () => ({ then: cb => { ready = cb; } }), on: vi.fn(), getPath: () => '/test-only', requestSingleInstanceLock: () => true, quit: vi.fn() },
    systemPreferences: { isTrustedAccessibilityClient: () => true },
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler), on: vi.fn() },
    globalShortcut: { register: vi.fn(() => true), unregister: vi.fn() },
    shell: { openExternal: vi.fn(async () => {}), showItemInFolder: vi.fn(), openPath: vi.fn(async () => '') },
    dialog: { showErrorBox: vi.fn() },
    session: { defaultSession: { setDisplayMediaRequestHandler: vi.fn() } },
    Menu: { buildFromTemplate: vi.fn(template => ({ template })) },
  };
  const spies = { overlay: vi.fn(), dictation: vi.fn(), show: vi.fn(), logFile: vi.fn(() => ({ path: logPath })) };
  const notes = { start: vi.fn(), shutdown: vi.fn(), flush: vi.fn(async () => {}), bridge: { dictationState: vi.fn(), meetingStarted: vi.fn() } };
  const context = {
    require: name => {
      if (name === 'electron') return electron;
      if (name === 'electron-store') return Store;
      if (name === './dictation/polish-client' && polishFactory) return { createPolishClient: polishFactory };
      if (['./globe-key-manager', './audio-tee-manager', './windows-audio-manager', './call-detector-manager'].includes(name)) return Helper;
      if (name === './meeting/meeting-store') return { createMeetingStore: () => ({}) };
      if (name === './meeting/meeting-controller') return { createMeetingController: () => controller };
      if (name === './notes') return { createNotes: () => notes };
      if (name === './diagnostics/log-file') return { installLogFile: spies.logFile };
      return realRequire(name);
    },
    process: { platform, env: {}, arch: 'x64', versions: { electron: '0.0.0-test' } }, __dirname: root,
    console: { log: vi.fn(), error: vi.fn() },
    setTimeout: vi.fn(() => ({ unref() {} })), setInterval: vi.fn(() => ({ unref() {} })), setImmediate: vi.fn(), clearTimeout: vi.fn(), clearInterval: vi.fn(), spies,
  };
  vm.createContext(context);
  // Main-Code liegt im Block der Single-Instance-Sperre: Ersetzungen müssen in
  // denselben Block, sonst treffen sie nur die äußere (Annex-B-)Bindung.
  const source = fs.readFileSync(path.join(root, 'electron-main.js'), 'utf8')
    .replace(/\n\}\s*\/\/ primary instance only\s*$/, `
    setupAutoUpdater = setupTray = createRecordingWindow = updateAutoLaunch = resetStatsIfNeeded = () => {};
    registerHotkey = spies.dictation;
    ensureMeetingOverlayWindow = spies.overlay;
    showMainWindow = spies.show;
    globalThis.fixture = { getStore, setupIpcHandlers, setDashboard: win => { mainWindow = win; }, updateTrayMenu, setTray: value => { tray = value; } };
  }`);
  vm.runInContext(source, context);
  return { ready: () => ready(), handlers, data, controller, electron, spies, helpers, context, notes };
}

describe('Main: Notes beim nativen Beenden sichern', () => {
  it.each([false, true])('wartet auf Flush und verlässt den nativen Quit-Dispatch (Flush-Fehler: %s)', async fails => {
    const h = harness({ platform: 'darwin' }); h.ready();
    let finish;
    h.notes.flush.mockImplementation(() => new Promise((resolve, reject) => { finish = () => fails ? reject(new Error('disk unavailable')) : resolve(); }));
    const beforeQuit = h.electron.app.on.mock.calls.find(([event]) => event === 'before-quit')[1];
    const first = { preventDefault: vi.fn() }, duplicate = { preventDefault: vi.fn() };
    beforeQuit(first); beforeQuit(duplicate);
    expect(first.preventDefault).toHaveBeenCalledOnce();
    expect(duplicate.preventDefault).toHaveBeenCalledOnce();
    expect(h.notes.flush).toHaveBeenCalledOnce();
    expect(h.context.setImmediate).not.toHaveBeenCalled();
    finish();
    await new Promise(resolve => setImmediate(resolve));
    expect(h.context.setImmediate).toHaveBeenCalledOnce();
    expect(h.electron.app.quit).not.toHaveBeenCalled();
    h.context.setImmediate.mock.calls[0][0]();
    expect(h.electron.app.quit).toHaveBeenCalledOnce();
    const retry = { preventDefault: vi.fn() };
    beforeQuit(retry);
    expect(retry.preventDefault).not.toHaveBeenCalled();
    expect(h.notes.flush).toHaveBeenCalledOnce();
  });
});

describe('Main: Meeting-Beta und Ersteinrichtung verdrahtet', () => {
  it('startet für Altinstallationen ohne Opt-in weder Meeting-Hotkey noch Overlay/Helfer, behält Retention', () => {
    const h = harness({ persisted: { groqApiKey: 'example-only', meetingHotkey: 'Command+Shift+X' } });
    h.ready();
    expect(h.handlers.get('settings:get')().meetingEnabled).toBe(false);
    expect(h.handlers.get('settings:get')().onboardingCompleted).toBe(true);
    expect(h.data.meetingHotkey).toBe('Control+Shift+X');
    expect(h.spies.dictation).toHaveBeenCalledOnce();
    expect(h.spies.overlay).not.toHaveBeenCalled();
    expect(h.electron.globalShortcut.register).not.toHaveBeenCalled();
    for (const helper of h.helpers) expect(helper.start).not.toHaveBeenCalled();
    expect(h.controller.runRetention).toHaveBeenCalledOnce();
    expect(h.context.setInterval).toHaveBeenCalledWith(expect.any(Function), 86400000);
    expect(h.handlers.get('meeting:start')()).toEqual({ error: 'Meeting-Modus ist ausgeschaltet.' });
    expect(h.controller.start).not.toHaveBeenCalled();
  });
  it('erlaubt Opt-in ohne Neustart und lässt den Diktat-Hotkey in Ruhe', async () => {
    const h = harness(); h.ready();
    const settings = h.handlers.get('settings:set');
    settings(null, { meetingEnabled: true });
    expect(h.data.meetingEnabled).toBe(true);
    expect(h.electron.globalShortcut.register).toHaveBeenCalledWith('Control+Shift+X', expect.any(Function));
    expect(h.spies.overlay).toHaveBeenCalledOnce();
    settings(null, { meetingHotkey: 'Alt+M' });
    expect(h.electron.globalShortcut.unregister).toHaveBeenCalledWith('Control+Shift+X');
    expect(h.spies.dictation).toHaveBeenCalledOnce();
    h.controller.getStatus.mockReturnValue({ active: true });
    await expect(settings(null, { meetingEnabled: false })).rejects.toThrow('Beende zuerst');
    expect(h.data.meetingEnabled).toBe(true);
    h.controller.getStatus.mockReturnValue({ active: false });
    settings(null, { meetingEnabled: false });
    expect(h.data.meetingEnabled).toBe(false);
    expect(h.electron.globalShortcut.unregister).toHaveBeenCalledWith('Alt+M');
  });
  it('behält bei belegtem Hotkey den gespeicherten Opt-out bei', async () => {
    const h = harness(); h.ready();
    h.electron.globalShortcut.register.mockReturnValue(false);
    await expect(h.handlers.get('settings:set')(null, { meetingEnabled: true })).rejects.toThrow('bereits belegt');
    expect(h.handlers.get('settings:get')().meetingEnabled).toBe(false);
    expect(h.spies.overlay).not.toHaveBeenCalled();
  });
  it('zeigt Neulingen den Setup-Status und speichert Abschluss/erneutes Öffnen', () => {
    const h = harness(); h.ready();
    expect(h.handlers.get('settings:get')().onboardingCompleted).toBe(false);
    h.handlers.get('onboarding:complete')();
    expect(h.data.onboardingCompleted).toBe(true);
    h.handlers.get('onboarding:open')();
    expect(h.data.onboardingCompleted).toBe(false);
    expect(h.spies.show).toHaveBeenCalledOnce();
  });
  it('öffnet nur das feste Groq-Ziel und plattformgerechte Mikrofon-Einstellungen', async () => {
    for (const platform of ['darwin', 'win32']) {
      const h = harness({ platform }); h.ready();
      await h.handlers.get('onboarding:openGroqKeys')();
      expect(h.electron.shell.openExternal).toHaveBeenCalledWith('https://console.groq.com/keys');
      await h.handlers.get('permissions:openMicrophone')();
      expect(h.electron.shell.openExternal).toHaveBeenCalledWith(platform === 'win32'
        ? 'ms-settings:privacy-microphone'
        : 'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone');
    }
  });
});


describe('Main: Polieren-Einstellungen und Migration', () => {
  it('setzt das neue Meeting-Modell als Default und migriert gespeicherte Altwerte', () => {
    for (const persisted of [{}, { meetingSummaryModel: 'llama-3.3-70b-versatile' }]) {
      const h = harness({ persisted }); h.ready();
      expect(h.context.fixture.getStore().get('meetingSummaryModel')).toBe('openai/gpt-oss-120b');
    }
    const h = harness({ persisted: { meetingSummaryModel: 'bewusst-eigenes-modell' } }); h.ready();
    expect(h.context.fixture.getStore().get('meetingSummaryModel')).toBe('bewusst-eigenes-modell');
  });
  it('liest, speichert und leert die optionale Wortliste über die echten Settings-Handler', async () => {
    const h = harness(); h.ready();
    expect(h.handlers.get('settings:get')().customVocabulary).toBe('');
    await h.handlers.get('settings:set')(null, { customVocabulary: 'Paply, Müller' });
    expect(h.handlers.get('settings:get')().customVocabulary).toBe('Paply, Müller');
    await h.handlers.get('settings:set')(null, { customVocabulary: '' });
    expect(h.data.customVocabulary).toBe('');
  });
  it('meldet Modell-Ausfall ans Dashboard und hält den Hinweis für später geöffnete Fenster vor', () => {
    let unavailable;
    const h = harness({ polishFactory: options => { unavailable = options.onUnavailable; return vi.fn(); } });
    h.ready();
    const send = vi.fn();
    h.context.fixture.setDashboard({ isDestroyed: () => false, webContents: { send } });
    expect(h.handlers.get('settings:get')().polishUnavailable).toBe(false);
    unavailable();
    expect(send).toHaveBeenCalledExactlyOnceWith('settings:changed');
    expect(h.handlers.get('settings:get')().polishUnavailable).toBe(true);
    expect(h.data).not.toHaveProperty('polishUnavailable');
  });
});

describe('Main: Diagnose-Protokoll', () => {
  it('hängt das Protokoll vor allen Modulen an userData/logs und schreibt eine Startzeile', () => {
    const h = harness();
    expect(h.spies.logFile).toHaveBeenCalledOnce();
    const [options] = h.spies.logFile.mock.calls[0];
    expect(options.directory).toBe(path.join('/test-only', 'logs'));
    expect(options.console).toBe(h.context.console);
    expect(options.process).toBe(h.context.process);
    const start = h.context.console.log.mock.calls.find(([first]) => first === '[Start] paply');
    expect(start.join(' ')).toMatch(/^\[Start\] paply \d+\.\d+\.\d+ win32\/x64 OS \S+ Electron 0\.0\.0-test$/);
    expect(h.electron.app.on).toHaveBeenCalledWith('render-process-gone', expect.any(Function));
    expect(h.electron.app.on).toHaveBeenCalledWith('child-process-gone', expect.any(Function));
  });
  it('„Protokoll anzeigen“ im Tray markiert die Datei, ohne Datei öffnet es den Ordner', () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-log-menu-'));
    const logPath = path.join(directory, 'paply.log');
    try {
      for (const platform of ['darwin', 'win32']) {
        fs.rmSync(logPath, { force: true });
        const h = harness({ platform, logPath }); h.ready();
        h.context.fixture.setTray({ setContextMenu: vi.fn() });
        h.context.fixture.updateTrayMenu();
        const template = h.electron.Menu.buildFromTemplate.mock.calls.at(-1)[0];
        const labels = template.map(item => item.label).filter(Boolean);
        expect(labels.slice(labels.indexOf('Einstellungen...'))).toEqual(
          ['Einstellungen...', 'Nach Updates suchen...', 'Protokoll anzeigen', 'Über paply', 'Beenden']);
        const entry = template.find(item => item.label === 'Protokoll anzeigen');
        entry.click();
        expect(h.electron.shell.openPath).toHaveBeenCalledWith(directory);
        fs.writeFileSync(logPath, '');
        entry.click();
        expect(h.electron.shell.showItemInFolder).toHaveBeenCalledExactlyOnceWith(logPath);
      }
    } finally {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  });
});

it('neue Nutzer polieren standardmäßig; gespeichertes Aus bleibt und Entwicklerwerte sind dauerhaft', () => {
 const fresh = harness(); fresh.ready();
 expect(fresh.handlers.get('settings:get')().enablePolish).toBe(true);
 expect(fresh.handlers.get('settings:get')().whisperModel).toBe('whisper-large-v3');
 const saved = harness({persisted:{enablePolish:false,developerMode:true,whisperModel:'whisper-large-v3-turbo'}}); saved.ready();
 const settings=saved.handlers.get('settings:get')();
 expect(settings.enablePolish).toBe(false); expect(settings.developerMode).toBe(true);
 expect(settings.whisperModel).toBe('whisper-large-v3-turbo');
});
