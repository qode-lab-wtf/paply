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

function detectMac(): boolean {
  return typeof navigator !== 'undefined' && /Mac/i.test(navigator.platform || navigator.userAgent || '');
}

export function keyEventToAccelerator(
  event: Pick<KeyboardEvent, 'code' | 'metaKey' | 'ctrlKey' | 'altKey' | 'shiftKey'> & { key?: string },
  isMac: boolean = detectMac(),
): string | null {
  // macOS: Option verändert event.key (⌥K → ˚); event.code behält KeyK, und Electron
  // registriert dort ebenfalls nach Tastenposition.
  // Windows/Linux: globalShortcut arbeitet layoutabhängig (QWERTZ: Z ≠ KeyZ) → für
  // Buchstaben/Ziffern das erzeugte Zeichen nehmen, Satzzeichen ablehnen.
  const code = event.code;
  if (code === 'IntlBackslash') return null; // ISO-Taste </>: kein verlässlicher Accelerator
  if (!isMac && /^(Minus|Equal|BracketLeft|BracketRight|Backslash|Semicolon|Quote|Backquote|Comma|Period|Slash)$/.test(code)) return null;
  const typed = !isMac && typeof event.key === 'string' && /^[a-z0-9]$/i.test(event.key) ? event.key.toUpperCase() : null;
  const keys: Record<string, string> = {
    Space: 'Space', Enter: 'Enter', NumpadEnter: 'Enter', Tab: 'Tab', Escape: 'Escape',
    Backspace: 'Backspace', Delete: 'Delete', Insert: 'Insert', Home: 'Home', End: 'End',
    PageUp: 'PageUp', PageDown: 'PageDown', ArrowUp: 'Up', ArrowDown: 'Down',
    ArrowLeft: 'Left', ArrowRight: 'Right',
    Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\',
    Semicolon: ';', Quote: "'", Backquote: '`',
    Comma: ',', Period: '.', Slash: '/',
  };
  const letter = /^Key([A-Z])$/.exec(code);
  const digit = /^(?:Digit|Numpad)([0-9])$/.exec(code);
  const functionKey = /^F(?:[1-9]|1[0-9]|2[0-4])$/.test(code) ? code : null;
  const key = typed || letter?.[1] || digit?.[1] || functionKey || keys[code];
  if (!key) return null; // modifiers, dead keys, media keys and unknown codes
  const parts: string[] = [];
  if (event.metaKey) parts.push('Command');
  if (event.ctrlKey) parts.push('Ctrl');
  if (event.altKey) parts.push('Alt');
  if (event.shiftKey) parts.push('Shift');
  parts.push(key);
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
