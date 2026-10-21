import { describe, it, expect, vi } from 'vitest';
const { createMeetingBetaMode, meetingAccelerator } = require('./beta-mode');

describe('Meeting-Beta-Hotkey', () => {
  function setup(platform = 'win32') {
    const keys = new Map();
    const controller = { getStatus: vi.fn(() => ({ active: false })), isActive: vi.fn(() => false), start: vi.fn(), stop: vi.fn() };
    const globalShortcut = {
      register: vi.fn((key, cb) => { if (keys.has(key)) return false; keys.set(key, cb); return true; }),
      unregister: vi.fn(key => keys.delete(key)),
    };
    const onError = vi.fn();
    return { keys, controller, globalShortcut, onError, beta: createMeetingBetaMode({ globalShortcut, getController: () => controller, platform, onError }) };
  }
  it('registriert im ausgeschalteten Zustand nichts', () => {
    const { beta, globalShortcut } = setup();
    beta.apply(false, 'Command+Shift+X');
    expect(globalShortcut.register).not.toHaveBeenCalled();
  });
  it('migriert Windows-Command-Kürzel gezielt, macOS behält Command', () => {
    expect(meetingAccelerator('Command+Shift+X', 'win32')).toBe('Control+Shift+X');
    expect(meetingAccelerator('Command+Shift+X', 'darwin')).toBe('Command+Shift+X');
    expect(meetingAccelerator(undefined, 'win32')).toBe('Control+Shift+X');
    expect(meetingAccelerator(undefined, 'darwin')).toBe('Command+Shift+X');
    expect(meetingAccelerator('Alt+K', 'win32')).toBe('Alt+K');
  });
  it('ersetzt genau den registrierten Hotkey und meldet ihn beim Ausschalten ab', () => {
    const { beta, keys, globalShortcut } = setup();
    beta.apply(true, 'Command+Shift+X');
    beta.apply(true, 'Alt+M');
    expect([...keys.keys()]).toEqual(['Alt+M']);
    expect(globalShortcut.unregister).toHaveBeenCalledWith('Control+Shift+X');
    beta.apply(false, 'Alt+M');
    expect(keys.size).toBe(0);
  });
  it('behält bei Belegung oder ungültigem neuem Kürzel die bisherige Registrierung', () => {
    const { beta, keys, globalShortcut } = setup();
    beta.apply(true, 'Alt+M');
    globalShortcut.register.mockReturnValueOnce(false);
    expect(() => beta.apply(true, 'Alt+K')).toThrow('bereits belegt');
    expect([...keys.keys()]).toEqual(['Alt+M']);
    globalShortcut.register.mockImplementationOnce(() => { throw new Error('invalid'); });
    expect(() => beta.apply(true, 'invalid')).toThrow('ungültig');
    expect([...keys.keys()]).toEqual(['Alt+M']);
  });
  it('fasst fremde Kürzel beim Deaktivieren nicht an und registriert nicht doppelt', () => {
    const { beta, keys, globalShortcut } = setup();
    keys.set('Ctrl+Alt+K', () => {});
    beta.apply(true, 'Alt+M'); beta.apply(true, 'Alt+M'); beta.apply(false, 'Alt+M');
    expect([...keys.keys()]).toEqual(['Ctrl+Alt+K']);
    expect(globalShortcut.register).toHaveBeenCalledTimes(1);
  });
  it('sperrt Ausschalten während einer Aufnahme einschließlich Flush', () => {
    const { beta, controller, keys } = setup();
    beta.apply(true, 'Alt+M');
    controller.getStatus.mockReturnValue({ active: true });
    controller.isActive.mockReturnValue(false); // Stop/Flush läuft bereits
    expect(() => beta.apply(false, 'Alt+M')).toThrow('laufende Meeting');
    expect(keys.has('Alt+M')).toBe(true);
  });
  it('meldet Startfehler sauber und schaltet laufende Meetings per Hotkey aus', async () => {
    const { beta, controller, keys, onError } = setup();
    beta.apply(true, 'Alt+M');
    controller.start.mockRejectedValueOnce(new Error('failure'));
    keys.get('Alt+M')();
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(onError).toHaveBeenCalled();
    controller.isActive.mockReturnValue(true);
    keys.get('Alt+M')();
    await Promise.resolve();
    expect(controller.stop).toHaveBeenCalled();
  });
});
