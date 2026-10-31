'use strict';
const path = require('node:path');
const fs = require('node:fs');
const { createRepo } = require('./repo');
const { createCommands } = require('./commands');
const { createSettings } = require('./settings');
const { createCapture } = require('./capture');
const { createAssets } = require('./assets');
const { createLedger } = require('./ledger');
const { createGroq } = require('./groq');
const { createQueue } = require('./queue');
const C = require('./contracts');
function createNotes(deps) {
  const { app, BrowserWindow, ipcMain, globalShortcut, screen, nativeImage, desktopCapturer, session, clipboard, getStore, isDictating, isMeetingActive, otherShortcuts, getSettingsWindows, openSettings } = deps;
  const store = getStore(), root = path.join(app.getPath('userData'), 'notes'), repo = createRepo(root);
  let boardWindow = null, captureWindow = null, settings, capture, queue, hideTimer, closing = false, lastCaptureState = { phase: 'idle' }, broadcastTimer, shortcutCapture = null, editingId = null;
  const notesSession = session.fromPartition('persist:paply-notes');
  notesSession.setPermissionRequestHandler((wc, permission, callback) => callback(wc === captureWindow?.webContents && permission === 'media'));
  notesSession.setPermissionCheckHandler((wc, permission) => wc === captureWindow?.webContents && permission === 'media');
  const getSettings = () => settings.get();
  function snapshot() {
    const b = repo.snapshot();
    const hashes = [...new Set(Object.values(b.nodes).flatMap(n => n.attachments))];
    return { ...b, entries: repo.entries().filter(e => e.state !== 'discarded').map(e => ({ id: e.id, kind: e.kind, createdAt: e.createdAt, state: e.state, message: e.message || '', durationMs: e.durationMs || 0 })), assets: Object.fromEntries(hashes.map(h => [h, repo.readLocal(`assets/${h}.json`, null)])), preferences: getSettings(), capture: capture.status(), budget: ledger.summary(), canUndo: commands.canUndo(), canRedo: commands.canRedo() };
  }
  function changed() {
    clearTimeout(broadcastTimer); broadcastTimer = setTimeout(() => {
      if (boardWindow && !boardWindow.isDestroyed()) boardWindow.webContents.send('notes:changed', snapshot());
    }, 25);
  }
  const commands = createCommands(repo, changed);
  settings = createSettings({ store, globalShortcut, otherShortcuts, capture: () => { Promise.resolve(capture.toggle()).catch(() => {}); }, open: () => openBoard(), interceptShortcut(key) {
    if (!shortcutCapture || shortcutCapture.sender.isDestroyed() || !shortcutCapture.sender.isFocused()) return false;
    shortcutCapture.sender.send('notes:settings:key', { field: shortcutCapture.field, key }); return true;
  }, changed() { changed(); for (const w of getSettingsWindows()) if (w && !w.isDestroyed()) w.webContents.send('notes:settings:changed'); } });
  const assets = createAssets({ repo, nativeImage, desktopCapturer, screen, commands, getSettings });
  const ledger = createLedger(repo, getSettings);
  // Test transport is loopback-only, explicitly isolated, and cannot receive a real key.
  let endpoint;
  if (process.env.PAPLY_USER_DATA && process.env.PAPLY_NOTES_TEST_ENDPOINT && store.get('groqApiKey') === 'paply-notes-test-key') {
    const url = new URL(process.env.PAPLY_NOTES_TEST_ENDPOINT);
    if (url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)) endpoint = url.href.replace(/\/$/, '');
  }
  const groq = createGroq({ getTranscriptionSettings: () => ({ language: store.get('language'), whisperModel: store.get('whisperModel'), systemLanguages: app.getPreferredSystemLanguages() }), getKey: () => store.get('groqApiKey'), ledger, ...(endpoint ? { endpoint } : {}) });
  function secureWindow(win) {
    win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    win.webContents.on('will-navigate', e => e.preventDefault());
    win.webContents.on('will-attach-webview', e => e.preventDefault());
    win.webContents.setVisualZoomLevelLimits(1, 1); win.webContents.setZoomFactor(1);
  }
  function sendCapture(state) { lastCaptureState = state; if (captureWindow && !captureWindow.isDestroyed()) captureWindow.webContents.send('notes:capture:state', state); }
  async function showCapture(reveal = true) {
    clearTimeout(hideTimer);
    if (!captureWindow || captureWindow.isDestroyed()) {
      captureWindow = new BrowserWindow({ width: 340, height: 90, frame: false, transparent: true, hasShadow: false, resizable: false, focusable: false, skipTaskbar: true, show: false, alwaysOnTop: true, webPreferences: { preload: path.join(__dirname, '..', 'notes-capture-preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true, backgroundThrottling: false, session: notesSession } });
      secureWindow(captureWindow); captureWindow.setAlwaysOnTop(true, 'screen-saver'); captureWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true }); captureWindow.setContentProtection(true);
      captureWindow.webContents.on('render-process-gone', () => { capture.fail('Aufnahmefenster neu gestartet · Ton gesichert'); captureWindow?.destroy(); captureWindow = null; });
      await captureWindow.loadFile(path.join(__dirname, '..', 'renderer', 'notes-pill.html'));
    } else if (captureWindow.webContents.isLoading()) await new Promise(resolve => captureWindow.webContents.once('did-finish-load', resolve));
    if (!reveal) return;
    const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
    captureWindow.setPosition(Math.round(area.x + (area.width - 340) / 2), area.y + area.height - 160); captureWindow.showInactive();
  }
  capture = createCapture({ repo, commands, getSettings, isDictating, isMeetingActive, show: showCapture, send: sendCapture, screenshot: assets.screenshot, hide(ms) { clearTimeout(hideTimer); hideTimer = setTimeout(() => captureWindow?.hide(), ms); }, onChange: changed });
  queue = createQueue({ repo, commands, groq, assets, getSettings, getKey: () => store.get('groqApiKey'), vocabulary: () => store.get('customVocabulary', ''), isBusy: () => isDictating() || isMeetingActive() || capture.status().active, isEditing: id => editingId === id, isOnline: () => deps.net.isOnline(), onChange: changed });
  async function openBoard() {
    settings.refreshKeyLabels();
    if (boardWindow && !boardWindow.isDestroyed()) { boardWindow.webContents.send('notes:changed', snapshot()); boardWindow.show(); boardWindow.focus(); return true; }
    boardWindow = new BrowserWindow({ width: 1280, height: 860, minWidth: 760, minHeight: 560, title: 'paply · Notes', backgroundColor: '#f5f5ee', titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default', show: false, webPreferences: { preload: path.join(__dirname, '..', 'notes-preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: true, session: notesSession } });
    secureWindow(boardWindow);
    boardWindow.webContents.on('render-process-gone', () => { editingId = null; boardWindow?.destroy(); boardWindow = null; });
    boardWindow.webContents.on('did-start-navigation', (_e, _url, inPlace, mainFrame) => { if (mainFrame && !inPlace) editingId = null; });
    boardWindow.on('closed', () => { editingId = null; });
    boardWindow.on('close', e => { if (!closing) { e.preventDefault(); boardWindow.hide(); } });
    boardWindow.webContents.on('before-input-event', (e, input) => {
      if ((input.meta || input.control) && input.key.toLowerCase() === 'r') e.preventDefault();
      if ((input.meta || input.control) && ['+', '=', '-', '0'].includes(input.key)) { e.preventDefault(); if (input.type === 'keyDown') boardWindow.webContents.send('notes:key', input.key); }
    });
    await boardWindow.loadFile(path.join(__dirname, '..', 'renderer', 'notes.html')); boardWindow.show(); boardWindow.focus(); return true;
  }
  function allowed(event, role) {
    const windows = role === 'board' ? [boardWindow] : role === 'capture' ? [captureWindow] : getSettingsWindows();
    return windows.some(w => w && !w.isDestroyed() && event.sender === w.webContents && event.senderFrame === w.webContents.mainFrame);
  }
  const channels = [];
  function handle(name, role, fn) { channels.push(name); ipcMain.handle(name, (event, payload) => { C.assert(allowed(event, role), 'Unzulässiger Notes-Absender'); return fn(payload, event); }); }
  handle('notes:board:get', 'board', snapshot);
  handle('notes:editing', 'board', p => {
    const id = C.id(p?.id); C.assert(typeof p.active === 'boolean');
    if (p.active) { C.assert(repo.current().nodes[id], 'Diese Notiz wurde bereits eingeordnet.'); editingId = id; }
    else if (editingId === id) editingId = null;
    return snapshot();
  });
  handle('notes:command', 'board', p => { commands.apply(p); return snapshot(); });
  handle('notes:place', 'board', p => { commands.place(p); return snapshot(); });
  handle('notes:viewport', 'board', p => { commands.viewport(p); return true; });
  handle('notes:undo', 'board', () => { commands.undo(); queue.reconcileUndo(); return snapshot(); });
  handle('notes:redo', 'board', () => { commands.redo(); queue.reconcileUndo(); return snapshot(); });
  handle('notes:text', 'board', p => { C.assert(p); queue.addText(C.text(p.text), p.position ? C.point(p.position) : undefined); return snapshot(); });
  handle('notes:copy', 'board', text => { clipboard.writeText(C.text(text, 100000)); return true; });
  handle('notes:attach', 'board', p => { C.assert(p); assets.attach(assets.put(p.bytes), p.target || null, p.position ? C.point(p.position) : undefined); return snapshot(); });
  handle('notes:camera', 'board', async p => {
    const window = boardWindow, visible = window?.isVisible(); window?.hide();
    try { await new Promise(resolve => setTimeout(resolve, 200)); await assets.camera(p?.target || null, p?.position ? C.point(p.position) : undefined); return snapshot(); }
    finally { if (visible && window && !window.isDestroyed() && !closing) { window.show(); window.focus(); } }
  });
  handle('notes:source', 'board', value => { const nid = C.id(value), sourceId = repo.current().nodes[nid]?.sourceId || nid; const entry = repo.entry(sourceId); C.assert(entry && entry.state !== 'discarded'); return { ...repo.transcript(sourceId), entry, audioUrl: fs.existsSync(path.join(repo.sourcePath(sourceId), 'rec.pcm')) ? `paply-notes://audio/${sourceId}` : null }; });
  handle('notes:retry', 'board', value => { queue.retry(C.id(value)); return snapshot(); });
  handle('notes:discard', 'board', value => { queue.discard(C.id(value)); return snapshot(); });
  handle('notes:capture:toggle', 'board', async () => { await capture.toggle(); return snapshot(); });
  handle('notes:settings:open', 'board', () => { openSettings(); return true; });
  handle('notes:open', 'settings', openBoard);
  handle('notes:settings:get', 'settings', () => { settings.refreshKeyLabels(); return getSettings(); });
  handle('notes:settings:listen', 'settings', (field, event) => {
    C.assert(field === null || ['captureHotkey', 'openHotkey'].includes(field));
    if (field) shortcutCapture = { field, sender: event.sender };
    else if (shortcutCapture?.sender === event.sender) shortcutCapture = null;
    return true;
  });
  handle('notes:settings:set', 'settings', p => { C.assert(!capture.status().active, 'Beende zuerst die Notes-Aufnahme.'); return settings.set(p); });
  handle('notes:capture:ready', 'capture', () => lastCaptureState);
  handle('notes:pcm', 'capture', p => capture.accept(p));
  handle('notes:capture:flushed', 'capture', p => { capture.flushed(p); return true; });
  handle('notes:capture:failed', 'capture', p => { if (capture.status().entryId === p?.entryId) capture.fail('Mikrofonzugriff fehlt oder Aufnahme unterbrochen'); return true; });
  handle('notes:capture:stop', 'capture', () => { capture.stop(); return true; });
  handle('notes:capture:camera', 'capture', async () => { const before = capture.status().entryId; C.assert(before); const hash = assets.put(await assets.screenshot()); C.assert(capture.status().entryId === before, 'Aufnahme schon beendet'); capture.attach(hash); return true; });
  return {
    openBoard, toggle: () => capture.toggle(),
    prepareQuit() { closing = true; queue.stop(); capture.shutdown(); },
    bridge: { dictationState(value) { try { capture.dictationState(value); } catch { /* Notes must never block dictation. */ } }, meetingStarted() { try { capture.meetingStarted(); } catch { /* Meeting keeps priority. */ } } },
    start() { notesSession.protocol.handle('paply-notes', assets.serve); capture.recover(); settings.start(); queue.start(); showCapture(false).catch(() => {}); },
    async flush() {
      closing = true; queue.stop(); capture.stop();
      const deadline = Date.now() + 3000;
      while (capture.status().active && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 40));
      if (capture.status().active) capture.shutdown();
    },
    shutdown() { closing = true; queue.stop(); capture.shutdown(); settings.shutdown(); clearTimeout(hideTimer); clearTimeout(broadcastTimer); channels.forEach(c => ipcMain.removeHandler(c)); },
  };
}
module.exports = { createNotes };
