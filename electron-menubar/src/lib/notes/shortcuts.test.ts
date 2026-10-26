import { describe, it, expect } from 'vitest';
import { keyEventToAccelerator } from '@/lib/shortcut';
import { formatNotesShortcut } from './shortcuts';
describe('Notes shortcut labels', () => {
  const german = { platform: 'darwin', keyLabels: { Y: 'Z', Z: 'Y', K: 'K' } };
  it('shows the German default and a typed Option combination using the printed key', () => {
    const accelerator = keyEventToAccelerator({ code: 'KeyZ', key: '¥', metaKey: true, ctrlKey: false, altKey: true, shiftKey: false }, true)!;
    expect(accelerator).toBe('Command+Alt+Z');
    expect(formatNotesShortcut(accelerator, german)).toBe('⌘ ⌥ Y');
    expect(formatNotesShortcut('Command+Z', german)).toBe('⌘ Y');
    expect(formatNotesShortcut('Command+Y', german)).toBe('⌘ Z');
  });
  it('leaves function keys, missing labels and Windows accelerators intact', () => {
    expect(formatNotesShortcut('F18', german)).toBe('F18');
    expect(formatNotesShortcut('Ctrl+Alt+Y', { platform: 'win32', keyLabels: german.keyLabels })).toBe('Ctrl + Alt + Y');
    expect(formatNotesShortcut('Command+Shift+K', german)).toBe('⌘ ⇧ K');
  });
});
