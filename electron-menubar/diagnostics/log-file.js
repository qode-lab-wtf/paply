// ============================================================================
// DIAGNOSE-PROTOKOLL
// Spiegelt console.log/warn/error des Main-Prozesses nach <userData>/logs/paply.log,
// damit sich Probleme auch auf fremden Rechnern (z. B. Windows) nachvollziehen lassen.
// - Die Konsole bleibt unverändert; die Datei ist nur eine Kopie.
// - Wirft nie in den Aufrufer: Bei Schreibfehlern schaltet sich das Protokoll still ab.
// - Größe begrenzt: ab ~2 MB wird nach paply.old.log rotiert (genau eine alte Datei).
// - Diktat-, Notiz- und Meeting-Text gehört nicht hinein; das regeln die Aufrufer
//   (Text nur mit PAPLY_DEBUG_TEXT=1). API-Schlüssel werden hier zusätzlich geschwärzt.
// ============================================================================
const fs = require('node:fs');
const path = require('node:path');
const util = require('node:util');

const MAX_BYTES = 2 * 1024 * 1024;
const MAX_LINE = 8000;           // Zeichen je Eintrag; schützt vor riesigen Objekten
const MAX_PENDING = 1024 * 1024; // ungeschriebene Bytes, ab denen Einträge verworfen werden
const LEVELS = { log: 'INFO', warn: 'WARN', error: 'ERROR' };

// Zweite Verteidigungslinie: Schlüssel dürfen nie im Protokoll landen.
const SECRETS = [
  [/\bBearer\s+[A-Za-z0-9._~+/=-]+/g, 'Bearer ***'],
  [/\bgsk_[A-Za-z0-9]{8,}/g, 'gsk_***'],
  [/\bAIza[0-9A-Za-z_-]{16,}/g, 'AIza***'],
  [/(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{16,}/g, 'sk-***'],
  [/(api[_-]?key["']?\s*[:=]\s*["']?)[^\s"',;}&]{6,}/gi, '$1***'],
];

function redact(text) {
  return SECRETS.reduce((result, [pattern, replacement]) => result.replace(pattern, replacement), text);
}

function formatEntry(args) {
  let text;
  try { text = util.format(...args); } catch {
    try { text = args.map(String).join(' '); } catch { text = '[nicht darstellbar]'; }
  }
  text = redact(text);
  return text.length > MAX_LINE ? `${text.slice(0, MAX_LINE)} … [gekürzt, ${text.length} Zeichen]` : text;
}

/**
 * Hängt das Protokoll an `target` (Standard: globale Konsole).
 * @param {{ directory: string, console?: Console, maxBytes?: number, process?: NodeJS.Process, now?: () => Date, fs?: typeof fs }} options
 */
function installLogFile({ directory, console: target = console, maxBytes = MAX_BYTES, process: proc = null, now = () => new Date(), fs: files = fs }) {
  const file = path.join(directory, 'paply.log');
  const oldFile = path.join(directory, 'paply.old.log');
  const originals = {};
  let stream = null;
  let size = 0;
  let disabled = false;

  function disable() {
    disabled = true;
    const current = stream;
    stream = null;
    try { current?.destroy(); } catch { /* egal */ }
  }

  function open(flags) {
    // Datei synchron öffnen (nur beim Start/Rotieren), damit Umbenennen immer die Datei
    // trifft, in die der Stream schreibt. Die Einträge selbst laufen asynchron.
    const next = files.createWriteStream(file, { fd: files.openSync(file, flags) });
    // Fehler eines bereits abgelösten Streams (nach Rotation) ignorieren.
    next.on('error', () => { if (stream === next) disable(); });
    stream = next;
  }

  // Liefert die Öffnungsart für die neue Datei: anhängen nach erfolgreichem Umbenennen,
  // sonst (z. B. Datei von Virenscanner gesperrt) neu beginnen, damit die Grenze hält.
  function moveToOld() {
    try { files.renameSync(file, oldFile); return 'a'; } catch { return 'w'; }
  }

  function rotate() {
    const previous = stream;
    stream = null;
    try { previous?.end(); } catch { /* egal */ }
    size = 0;
    open(moveToOld());
  }

  function line(level, args) {
    return `${now().toISOString()} [${LEVELS[level] || 'INFO'}] ${formatEntry(args)}\n`;
  }

  function write(level, args) {
    if (disabled || !stream) return;
    try {
      const entry = line(level, args);
      const bytes = Buffer.byteLength(entry);
      if (size > 0 && size + bytes > maxBytes) rotate();
      // Platte hängt oder Endlosschleife loggt: lieber Einträge verlieren als Speicher.
      if (!stream || stream.writableLength > MAX_PENDING) return;
      stream.write(entry);
      size += bytes;
    } catch { disable(); }
  }

  // Bei Abstürzen synchron schreiben: Der Prozess endet evtl., bevor der Stream leert.
  function onCrash(error, origin) {
    if (disabled) return;
    try { files.appendFileSync(file, line('error', [`[Absturz] ${origin}:`, error])); } catch { /* egal */ }
  }

  try {
    files.mkdirSync(directory, { recursive: true });
    try { size = files.statSync(file).size; } catch { size = 0; }
    let flags = 'a';
    if (size > maxBytes) { flags = moveToOld(); size = 0; }
    open(flags);
  } catch {
    disable();
  }

  if (!disabled) {
    for (const level of Object.keys(LEVELS)) {
      const original = target[level];
      if (typeof original !== 'function') continue;
      originals[level] = original;
      // Erst die Datei (wirft nie), dann unverändert die Original-Konsole.
      target[level] = (...args) => { write(level, args); return original.apply(target, args); };
    }
    // Nur beobachten: ändert Electrons Verhalten bei unbehandelten Fehlern nicht.
    proc?.on?.('uncaughtExceptionMonitor', onCrash);
  }

  return {
    path: file,
    oldPath: oldFile,
    get enabled() { return !disabled; },
    restore() {
      Object.assign(target, originals);
      proc?.off?.('uncaughtExceptionMonitor', onCrash);
      const current = stream;
      stream = null;
      disabled = true;
      return new Promise(resolve => {
        if (!current) return resolve();
        try { current.end(resolve); } catch { resolve(); }
      });
    },
  };
}

module.exports = { installLogFile, redact, MAX_BYTES };
