import { describe, it, expect, vi } from 'vitest';
import { readKeyLabels } from './keymap';
import { createSettings } from './settings';

const german = { Y: 'Z', Z: 'Y', X: 'X' };
function setup(saved = {}, labels = german) {
  const registrations = new Map();
  const capture = vi.fn(), open = vi.fn();
  const s = createSettings({ platform: 'darwin', loadKeyLabels: () => labels,
    store: { get: (key, fallback) => key === 'notesSettings' ? saved : fallback, set: vi.fn() },
    globalShortcut: { register: (key, action) => { registrations.set(key, action); return true; }, unregister: key => registrations.delete(key) },
    otherShortcuts: () => ['Command+X'], capture, open });
  s.start(); return { s, registrations, capture, open };
}
describe('Notes macOS key positions', () => {
  it('registers the printed German Y for both default actions', () => {
    const { s, registrations, capture, open } = setup();
    expect([...registrations.keys()]).toEqual(['Command+Z', 'Command+Alt+Z']);
    registrations.get('Command+Z')(); registrations.get('Command+Alt+Z')();
    expect(capture).toHaveBeenCalledOnce(); expect(open).toHaveBeenCalledOnce();
    expect(s.get()).toMatchObject({ warning: '', keyLabels: german });
    expect(() => s.set({ captureHotkey: 'Command+X' })).toThrow('bereits');
  });
  it('keeps US defaults and never changes a saved physical binding', () => {
    expect(setup({}, { Y: 'Y', Z: 'Z' }).s.get().captureHotkey).toBe('Command+Y');
    expect(setup({ captureHotkey: 'Command+Y', openHotkey: 'Command+Alt+Y' }).s.get().captureHotkey).toBe('Command+Y');
  });
  it('refreshes labels without moving or registering a custom shortcut', () => {
    const labels = { ...german }; const { s, registrations } = setup({}, labels);
    labels.Y = 'Y'; labels.Z = 'Z'; s.refreshKeyLabels();
    expect([...registrations.keys()]).toEqual(['Command+Z', 'Command+Alt+Z']);
    expect(s.get().keyLabels.Z).toBe('Z');
  });
  it('reads the packaged helper, validates its result, and falls back safely', () => {
    const run = vi.fn(() => JSON.stringify({ ...german, wrong: 'bad', Q: null }));
    expect(readKeyLabels({ platform: 'darwin', resourcesPath: '/Applications/paply.app/Contents/Resources', run })).toEqual(german);
    expect(run.mock.calls[0][0]).toBe('/Applications/paply.app/Contents/Resources/bin/macos-notes-keymap');
    expect(readKeyLabels({ platform: 'darwin', run: () => { throw Error('missing'); } })).toEqual({});
    run.mockClear(); expect(readKeyLabels({ platform: 'win32', run })).toEqual({}); expect(run).not.toHaveBeenCalled();
  });
});
