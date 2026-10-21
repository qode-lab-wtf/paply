import { describe, it, expect, vi } from 'vitest';
import { captureShortcut, formatShortcut } from './shortcut';

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
      const event = { key, ctrlKey, preventDefault: vi.fn(), stopPropagation: vi.fn() } as unknown as KeyboardEvent;
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
