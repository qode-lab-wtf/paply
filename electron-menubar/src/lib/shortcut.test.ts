import { describe, it, expect, vi } from 'vitest';
import { captureShortcut, formatShortcut, keyEventToAccelerator } from './shortcut';

describe('Plattformgerechte Kürzel', () => {
  it('zeigt Mac-Symbole und Windows-Modifikatoren', () => {
    expect(formatShortcut('Command+Alt+Shift+X', true)).toBe('⌘ ⌥ ⇧ X');
    expect(formatShortcut('Ctrl+Alt+K', false)).toBe('Ctrl + Alt + K');
    expect(formatShortcut('CommandOrControl+Shift+X', false)).toBe('Ctrl + Shift + X');
    expect(formatShortcut('GLOBE', true)).toBe('🌐 Fn');
  });
});

describe('Shortcut-Erfassung', () => {
  function setup() {
    const listeners = new Set<(e: KeyboardEvent) => void>();
    const target = {
      addEventListener: vi.fn((_type, cb) => listeners.add(cb)),
      removeEventListener: vi.fn((_type, cb) => listeners.delete(cb)),
    };
    const press = (key: string, ctrlKey = false) => {
      const code = key.length === 1 ? `Key${key.toUpperCase()}` : `${key}Left`;
      const event = { key, code, ctrlKey, preventDefault: vi.fn(), stopPropagation: vi.fn() } as unknown as KeyboardEvent;
      [...listeners].forEach(cb => cb(event));
      return event;
    };
    return { listeners, target, press };
  }
  it('entfernt den Listener nach der ersten Kombination und lässt weitere Tasten in Ruhe', () => {
    const { target, listeners, press } = setup();
    const onCaptured = vi.fn();
    captureShortcut(target as unknown as Window, onCaptured);
    press('Control', true);
    expect(listeners.size).toBe(1);
    expect(onCaptured).not.toHaveBeenCalled();
    press('k', true);
    expect(onCaptured).toHaveBeenCalledWith('Ctrl+K');
    expect(listeners.size).toBe(0);
    const next = press('z');
    expect(next.preventDefault).not.toHaveBeenCalled();
    expect(onCaptured).toHaveBeenCalledTimes(1);
  });
  it('räumt auch ohne Erfassung auf (Unmount/Tabwechsel/Abbrechen)', () => {
    const { target, listeners, press } = setup();
    const onCaptured = vi.fn();
    const cleanup = captureShortcut(target as unknown as Window, onCaptured);
    cleanup(); cleanup();
    expect(listeners.size).toBe(0);
    press('x');
    expect(onCaptured).not.toHaveBeenCalled();
  });
});

describe('Physische Tastencodes mit macOS-Option', () => {
  it.each([
    ['˚', 'KeyK', 'Command+Alt+K'], ['∑', 'KeyW', 'Command+Alt+W'],
    ['Dead', 'KeyE', 'Command+Alt+E'], ['¡', 'Digit1', 'Command+Alt+1'],
    [' ', 'Space', 'Command+Alt+Space'], ['F1', 'F1', 'Command+Alt+F1'],
    ['F24', 'F24', 'Command+Alt+F24'], ['–', 'Minus', 'Command+Alt+-'],
    ['≠', 'Equal', 'Command+Alt+='], ['“', 'BracketLeft', 'Command+Alt+['],
    ['‘', 'BracketRight', 'Command+Alt+]'], ['«', 'Backslash', 'Command+Alt+\\'],
    ['…', 'Semicolon', 'Command+Alt+;'], ['æ', 'Quote', "Command+Alt+'"],
    ['≤', 'Comma', 'Command+Alt+,'], ['≥', 'Period', 'Command+Alt+.'],
    ['÷', 'Slash', 'Command+Alt+/'], ['Dead', 'Backquote', 'Command+Alt+`'],
    ['ArrowLeft', 'ArrowLeft', 'Command+Alt+Left'], ['End', 'End', 'Command+Alt+End'],
  ])('nutzt %s / %s für %s', (key, code, expected) => {
    expect(keyEventToAccelerator({ key, code, metaKey: true, altKey: true } as KeyboardEvent)).toBe(expected);
  });
  it.each(['AltLeft', 'ShiftRight', 'MetaLeft', 'ControlRight', 'AudioVolumeUp', 'Unidentified', ''])('ignoriert Modifier oder nicht unterstützten Code %s', code => {
    expect(keyEventToAccelerator({ code } as KeyboardEvent)).toBeNull();
  });
  it('behält Windows-Ctrl und Shift unabhängig vom erzeugten Zeichen', () => {
    expect(keyEventToAccelerator({ key: '!', code: 'Digit1', ctrlKey: true, shiftKey: true } as KeyboardEvent)).toBe('Ctrl+Shift+1');
  });
});
