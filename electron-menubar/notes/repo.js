'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { clone, id, point, blankBoard, validBoard, assert } = require('./contracts');

// One main-process writer. No renderer owns a path or writes a file.
function atomic(file, value, previous = false) {
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const tmp = `${file}.tmp`;
  const fd = fs.openSync(tmp, 'w', 0o600);
  try { fs.writeFileSync(fd, JSON.stringify(value)); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  if (previous && fs.existsSync(file)) fs.copyFileSync(file, file.replace(/\.json$/, '.prev.json'));
  // rename is atomic on both supported platforms; on failure the old file survives.
  fs.renameSync(tmp, file);
  try { const dir = fs.openSync(path.dirname(file), 'r'); try { fs.fsyncSync(dir); } finally { fs.closeSync(dir); } } catch { /* Windows does not fsync directories. */ }
}
function read(file, fallback) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; } }
function createRepo(root) {
  for (const dir of ['', 'sources', 'assets', 'thumbs', 'tmp', 'backups']) fs.mkdirSync(path.join(root, dir), { recursive: true, mode: 0o700 });
  const file = path.join(root, 'board.json');
  const backups = fs.readdirSync(path.join(root, 'backups')).filter(n => n.endsWith('.json')).sort().reverse();
  const candidates = [file, path.join(root, 'board.prev.json'), ...backups.map(n => path.join(root, 'backups', n))];
  let board, recovered = false;
  for (const candidate of candidates) { const b = read(candidate); if (validBoard(b)) { board = b; recovered = candidate !== file; break; } }
  if (!board) {
    // Never silently replace a damaged store with an empty board.
    assert(!fs.existsSync(file) && !fs.existsSync(path.join(root, 'board.prev.json')), 'Notes-Speicher beschädigt. Die Originale sind erhalten; bitte den Notes-Ordner sichern.');
    board = blankBoard(); atomic(file, board);
  }
  if (recovered) { if (fs.existsSync(file)) fs.copyFileSync(file, path.join(root, 'backups', `damaged-${Date.now()}.json`)); atomic(file, board); }
  const viewFile = path.join(root, 'viewport.json'), view = read(viewFile);
  try { if (view && view.zoom >= .1 && view.zoom <= 2.5) board.viewport = { ...point(view), zoom: view.zoom }; } catch { /* Last valid board view is still available. */ }
  board.tasks ||= {};
  let lastBackup = 0;
  function save(next) {
    assert(validBoard(next)); next.rev = board.rev + 1;
    atomic(file, next, true); board = next;
    const hour = Math.floor(Date.now() / 3600000);
    if (lastBackup !== hour) {
      try {
        atomic(path.join(root, 'backups', `${String(hour).padStart(12, '0')}.json`), board);
        const names = fs.readdirSync(path.join(root, 'backups')).filter(n => /^\d+\.json$/.test(n)).sort().reverse();
        names.slice(48).forEach(n => fs.unlinkSync(path.join(root, 'backups', n))); lastBackup = hour;
      } catch { /* Canonical write succeeded; backup is best effort. */ }
    }
    return clone(board);
  }
  const sourcePath = entryId => path.join(root, 'sources', id(entryId));
  const entryCache = new Map();
  for (const name of fs.readdirSync(path.join(root, 'sources'))) {
    try { const e = read(path.join(sourcePath(name), 'entry.json')); if (e && e.id === name) entryCache.set(name, e); } catch { /* Ignore unrelated files, never turn them into paths. */ }
  }
  const entry = entryId => clone(entryCache.get(id(entryId)) || null);
  return {
    root, recovered, snapshot: () => clone(board), current: () => board, save,
    saveViewport(view) { const p = point(view); assert(Number.isFinite(view.zoom) && view.zoom >= .1 && view.zoom <= 2.5); const next = { ...p, zoom: view.zoom }; atomic(viewFile, next); board.viewport = next; return clone(board); },
    mutate(fn) { const next = clone(board); const result = fn(next); if (result === false) return clone(board); return save(next); },
    sourcePath, entry,
    entries() { return [...entryCache.values()].map(clone); },
    saveEntry(value) { atomic(path.join(sourcePath(value.id), 'entry.json'), value); entryCache.set(value.id, clone(value)); return value; },
    transcript(entryId) { return read(path.join(sourcePath(entryId), 'transcript.json'), null); },
    saveTranscript(entryId, value) { const p = path.join(sourcePath(entryId), 'transcript.json'); if (fs.existsSync(p)) return read(p); atomic(p, value); return value; },
    readLocal: (name, fallback) => read(path.join(root, name), fallback),
    writeLocal: (name, value) => atomic(path.join(root, name), value),
  };
}
module.exports = { createRepo, atomic, read };
