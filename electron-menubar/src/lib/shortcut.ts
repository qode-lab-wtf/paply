export function formatShortcut(shortcut: string, isMac: boolean): string {
  if (shortcut === 'GLOBE') return '🌐 Fn';
  return shortcut
    .split('+')
    .map((part) => {
      if (/^(CommandOrControl|CmdOrCtrl)$/i.test(part)) return isMac ? '⌘' : 'Ctrl';
      if (/^(Command|Cmd|Meta)$/i.test(part)) return isMac ? '⌘' : 'Ctrl';
      if (/^(Control|Ctrl)$/i.test(part)) return isMac ? '⌃' : 'Ctrl';
      if (/^(Alt|Option)$/i.test(part)) return isMac ? '⌥' : 'Alt';
      if (/^Shift$/i.test(part)) return isMac ? '⇧' : 'Shift';
      return part;
    })
    .join(isMac ? ' ' : ' + ');
}

export function keyEventToAccelerator(event: KeyboardEvent): string | null {
  if (['Meta', 'Control', 'Alt', 'Shift', 'Fn'].includes(event.key)) return null;
  const parts: string[] = [];
  if (event.metaKey) parts.push('Command');
  if (event.ctrlKey) parts.push('Ctrl');
  if (event.altKey) parts.push('Alt');
  if (event.shiftKey) parts.push('Shift');
  const keys: Record<string, string> = {
    ' ': 'Space',
    ArrowUp: 'Up',
    ArrowDown: 'Down',
    ArrowLeft: 'Left',
    ArrowRight: 'Right',
  };
  parts.push(keys[event.key] || (event.key.length === 1 ? event.key.toUpperCase() : event.key));
  return parts.join('+');
}

export function captureShortcut(
  target: Pick<Window, 'addEventListener' | 'removeEventListener'>,
  onCaptured: (shortcut: string) => void
): () => void {
  const cleanup = () => target.removeEventListener('keydown', listener, true);
  const listener = (event: KeyboardEvent) => {
    event.preventDefault();
    event.stopPropagation();
    const shortcut = keyEventToAccelerator(event);
    if (shortcut) {
      cleanup(); // Sofort entfernen, noch bevor React den neuen State rendert.
      onCaptured(shortcut);
    }
  };
  target.addEventListener('keydown', listener, true);
  return cleanup;
}
