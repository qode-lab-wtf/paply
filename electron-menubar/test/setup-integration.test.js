// Führt den echten Main-Code mit vollständig ersetztem Electron aus.
// Keine App, globalen Hotkeys, Mikrofone, Helferprozesse oder Nutzerdaten.
import { describe, it, expect, vi } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { EventEmitter } from 'node:events';

const root = path.resolve(__dirname, '..');
const realRequire = createRequire(path.join(root, 'electron-main.js'));

function harness({ platform = 'win32', persisted = {}, polishFactory } = {}) {
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
    app: { whenReady: () => ({ then: cb => { ready = cb; } }), on: vi.fn(), getPath: () => '/test-only', requestSingleInstanceLock: () => true, quit: vi.fn() },
    systemPreferences: { isTrustedAccessibilityClient: () => true },
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler), on: vi.fn() },
    globalShortcut: { register: vi.fn(() => true), unregister: vi.fn() },
    shell: { openExternal: vi.fn(async () => {}) },
    dialog: { showErrorBox: vi.fn() },
    session: { defaultSession: { setDisplayMediaRequestHandler: vi.fn() } },
  };
  const spies = { overlay: vi.fn(), dictation: vi.fn(), show: vi.fn() };
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
      return realRequire(name);
    },
    process: { platform, env: {}, arch: 'x64' }, __dirname: root,
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
    globalThis.fixture = { getStore, setupIpcHandlers, setDashboard: win => { mainWindow = win; } };
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
