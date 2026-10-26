import { formatShortcut } from '@/lib/shortcut';
type Labels = { platform: string; keyLabels?: Record<string, string> };
// Stored macOS accelerators describe physical US positions. Only Notes labels
// translate them back to the selected keyboard; existing custom keys stay put.
export function formatNotesShortcut(shortcut: string, preferences: Labels): string {
  const parts = shortcut.split('+');
  const key = parts.pop() || '';
  const mac = preferences.platform === 'darwin';
  const label = mac ? preferences.keyLabels?.[key.toUpperCase()] || key : key;
  const modifiers = formatShortcut(parts.join('+'), mac);
  return modifiers ? `${modifiers}${mac ? ' ' : ' + '}${label}` : label;
}
