import { describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import ts from 'typescript';
import { saveSettings } from './settings-save';
import { keyEventToAccelerator } from './shortcut';
const message = 'Kürzel nicht verfügbar — bitte ein anderes wählen';
const rejected = { success: false as const, error: { code: 'HOTKEY_REGISTRATION_FAILED' as const, field: 'shortcut' as const, message } };
const settingsSource = fs.readFileSync(path.join(__dirname, '../apps/settings/SettingsApp.tsx'), 'utf8');
const dashboardSource = fs.readFileSync(path.join(__dirname, '../apps/dashboard/Dashboard.tsx'), 'utf8');
function handler(source: string, name: string, context: Record<string, unknown>) {
  const start = source.indexOf(`  const ${name} =`);
  const end = source.indexOf('\n  };', start) + 6;
  if (start < 0 || end < start) throw Error('Handler not found: ' + name);
  const { outputText } = ts.transpileModule(`${source.slice(start, end)}; globalThis.run = ${name};`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  });
  const fixture = { Error, ...context };
  vm.runInNewContext(outputText, fixture);
  return (fixture as any).run;
}
it('übersetzt aufgelösten Main-Fehler in einen Fehler mit Originalmeldung', async () => {
  const setSettings = vi.fn(async () => rejected);
  await expect(saveSettings({ setSettings }, { shortcut: 'Alt+Command+K' })).rejects.toThrow(message);
});
it('akzeptiert Erfolg und reicht IPC-Ausnahmen durch', async () => {
  await expect(saveSettings({ setSettings: async () => true }, {})).resolves.toBeUndefined();
  await expect(saveSettings({ setSettings: async () => { throw Error('offline'); } }, {})).rejects.toThrow('offline');
});
describe('Echte Settings-Handler', () => {
  it.each(['resolved', 'rejected'])('SettingsApp zeigt %s-Fehler und setzt das sichtbare Kürzel zurück', async failure => {
    const setShortcut = vi.fn(); const setSaveError = vi.fn(); const setSettings = vi.fn(); const setIsSaving = vi.fn();
    const run = handler(settingsSource, 'handleSave', {
      settings: { shortcut: 'Command+K' }, setShortcut, setSaveError, setSettings, setIsSaving,
      saveSettings, window: { electronAPI: { setSettings: async () => { if (failure === 'rejected') throw Error(message); return rejected; } } },
    });
    await run('shortcut', 'Command+Alt+K');
    expect(setShortcut).toHaveBeenCalledWith('Command+K');
    expect(setSaveError).toHaveBeenLastCalledWith(message);
    expect(setSettings).not.toHaveBeenCalled(); expect(setIsSaving).toHaveBeenLastCalledWith(false);
  });
  function dashboard() {
    const setSettingsError = vi.fn(); const setSettings = vi.fn();
    const onSettingChange = handler(dashboardSource, 'handleSettingChange', {
      saveSettings, setSettingsError, setSettings,
      window: { electronAPI: { setSettings: async () => rejected, getSettings: vi.fn() } },
    });
    const context = { onSettingChange, settings: { shortcut: 'Command+K' },
      groqKey: '••••', geminiKey: '••••', shortcutInput: 'Command+Alt+K',
      setShortcutInput: vi.fn(), setSaved: vi.fn(), setIsRecording: vi.fn() };
    return { context, setSettingsError, setSettings };
  }
  it('Dashboard zeigt den Main-Fehler, rollt die Eingabe zurück und meldet nicht Gespeichert', async () => {
    const { context, setSettingsError, setSettings } = dashboard();
    await handler(dashboardSource.slice(dashboardSource.indexOf('function SettingsView(')), 'handleSave', context)();
    expect(setSettingsError).toHaveBeenLastCalledWith(message);
    expect(context.setShortcutInput).toHaveBeenCalledWith('Command+K');
    expect(context.setSaved).not.toHaveBeenCalled(); expect(setSettings).not.toHaveBeenCalled();
  });
  it('Dashboard rollt auch einen abgelehnten Globe-Wechsel zurück', async () => {
    const { context, setSettingsError } = dashboard();
    await handler(dashboardSource, 'handleUseGlobe', context)();
    expect(context.setShortcutInput.mock.calls).toEqual([['GLOBE'], ['Command+K']]);
    expect(setSettingsError).toHaveBeenLastCalledWith(message);
  });
  it('Dashboard verwendet für ⌥⌘K denselben physischen Mapper wie SettingsApp', () => {
    const setShortcutInput = vi.fn(); const event = { key: '˚', code: 'KeyK', metaKey: true, altKey: true, preventDefault: vi.fn() };
    handler(dashboardSource.slice(dashboardSource.indexOf('function SettingsView(')), 'handleHotkeyRecord', { isRecording: true, keyEventToAccelerator, setShortcutInput, setIsRecording: vi.fn() })(event);
    expect(setShortcutInput).toHaveBeenCalledWith('Command+Alt+K');
  });
});

it('Agenten-Dialog erfasst ⌥⌘K ebenfalls über event.code', () => {
  const setHotkeyInput = vi.fn(); const setIsRecordingHotkey = vi.fn();
  handler(dashboardSource.slice(dashboardSource.indexOf('function AgentsView(')), 'handleHotkeyRecord', {
    isRecordingHotkey: true, keyEventToAccelerator, setHotkeyInput, setIsRecordingHotkey,
  })({ key: '˚', code: 'KeyK', metaKey: true, altKey: true, preventDefault: vi.fn() });
  expect(setHotkeyInput).toHaveBeenCalledWith('Command+Alt+K');
  expect(setIsRecordingHotkey).toHaveBeenCalledWith(false);
});
