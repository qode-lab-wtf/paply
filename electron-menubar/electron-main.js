const {
  app,
  BrowserWindow,
  globalShortcut,
  ipcMain,
  Menu,
  Tray,
  clipboard,
  nativeImage,
  shell,
  dialog,
} = require('electron');
const path = require('node:path');
const fs = require('node:fs');
const { spawn, exec } = require('node:child_process');

// ============================================================================
// PLATFORM HELPERS
// ============================================================================
const isMac = process.platform === 'darwin';
const isWin = process.platform === 'win32';

function getDefaultShortcut() {
  return isMac ? 'Alt+Command+K' : 'Ctrl+Alt+K';
}

function getQuitAccelerator() {
  return isMac ? 'Command+Q' : 'Ctrl+Q';
}

// ============================================================================
// LAZY LOADED MODULES
// ============================================================================
let store = null;
let autoLauncher = null;

function getStore() {
  if (!store) {
    const Store = require('electron-store');
    store = new Store({
      defaults: {
        groqApiKey: '',
        haikuApiKey: '',
        enablePolish: false,
        shortcut: getDefaultShortcut(),
        autoStart: false,
        language: 'de',
        autopaste: true,
        beepEnabled: true,
        hideDock: false,
        history: [],
        // Profile/Rollen
        activeProfile: 'coding',
        profiles: {
          coding: { name: 'Coding', language: 'de', polishFlavor: 'code', autopaste: true },
          meeting: { name: 'Meeting', language: 'de', polishFlavor: 'meeting', autopaste: false },
          dictation: { name: 'Diktat', language: 'de', polishFlavor: 'plain', autopaste: true },
        },
        // Stats (öffentlich)
        stats: {
          wordsTotal: 0,
          wordsToday: 0,
          wordsWeek: 0,
          minutesTotal: 0,
          minutesToday: 0,
          minutesWeek: 0,
          sessionsCount: 0,
          errorsCount: 0,
          lastResetDay: null,
          lastResetWeek: null,
        },
        // Owner Analytics (hidden)
        ownerMode: false,
        ownerStats: {
          tokensGroq: 0,
          tokensAnthropic: 0,
          estimatedCost: 0,
        },
        // Snippets
        snippets: [
          { id: 'ticket', name: 'Ticket-Entwurf', template: '## Ticket\n\n{{text}}\n\n### Action Items\n- [ ] ' },
          { id: 'meeting', name: 'Meeting-Notizen', template: '# Meeting Notes\n\n{{text}}\n\n## Next Steps\n' },
          { id: 'code-comment', name: 'Code-Kommentar', template: '// {{text}}' },
        ],
        // Favorites
        favorites: [],
      },
    });
  }
  return store;
}

function getAutoLauncher() {
  if (!autoLauncher) {
    const AutoLaunch = require('auto-launch');
    autoLauncher = new AutoLaunch({
      name: 'paply',
      path: app.getPath('exe'),
    });
  }
  return autoLauncher;
}

async function updateAutoLaunch() {
  // In Dev/unsinged runs the login item often does not exist; skip there
  if (!app.isPackaged) return;

  try {
    const enabled = getStore().get('autoStart');
    const launcher = getAutoLauncher();
    if (enabled) {
      await launcher.enable();
    } else {
      await launcher.disable();
    }
  } catch (e) {
    console.error('AutoLaunch error:', e);
  }
}

// ============================================================================
// STATS MANAGEMENT
// ============================================================================
function countWords(text) {
  if (!text) return 0;
  return text.trim().split(/\s+/).filter(w => w.length > 0).length;
}

function detectRole(text) {
  if (!text) return 'dictation';
  const lower = text.toLowerCase();
  
  // Coding keywords
  const codeKeywords = ['function', 'const', 'let', 'var', 'import', 'export', 'class', 'return',
    'usestate', 'useeffect', 'component', 'react', 'typescript', 'javascript', 'python',
    'api', 'endpoint', 'database', 'query', 'async', 'await', 'promise', 'callback',
    'git', 'commit', 'push', 'pull', 'merge', 'branch', 'npm', 'yarn', 'package'];
  
  // Meeting keywords
  const meetingKeywords = ['meeting', 'action item', 'action items', 'agenda', 'discussion',
    'teilnehmer', 'besprechung', 'termin', 'next steps', 'follow up', 'deadline',
    'projekt', 'project', 'team', 'status update', 'blocker'];
  
  const codeScore = codeKeywords.filter(kw => lower.includes(kw)).length;
  const meetingScore = meetingKeywords.filter(kw => lower.includes(kw)).length;
  
  if (codeScore >= 2) return 'coding';
  if (meetingScore >= 2) return 'meeting';
  return 'dictation';
}

function calculateDelta(transcript, polished) {
  if (!transcript || !polished) return null;
  
  const transcriptWords = countWords(transcript);
  const polishedWords = countWords(polished);
  
  // Simple filler word detection (German + English)
  const fillerWords = ['ähm', 'äh', 'also', 'sozusagen', 'quasi', 'halt', 'ne', 'oder so',
    'um', 'uh', 'like', 'you know', 'basically', 'actually', 'literally'];
  
  const transcriptLower = transcript.toLowerCase();
  const polishedLower = polished.toLowerCase();
  
  const fillersRemoved = fillerWords.filter(fw => 
    transcriptLower.includes(fw) && !polishedLower.includes(fw)
  );
  
  return {
    wordsBefore: transcriptWords,
    wordsAfter: polishedWords,
    wordsDiff: transcriptWords - polishedWords,
    fillersRemoved: fillersRemoved.length,
    fillersList: fillersRemoved.slice(0, 5),
  };
}

function resetStatsIfNeeded() {
  const s = getStore();
  const stats = s.get('stats') || {};
  const now = new Date();
  const today = now.toISOString().split('T')[0];
  const weekStart = getWeekStart(now).toISOString().split('T')[0];
  
  if (stats.lastResetDay !== today) {
    stats.wordsToday = 0;
    stats.minutesToday = 0;
    stats.lastResetDay = today;
  }
  
  if (stats.lastResetWeek !== weekStart) {
    stats.wordsWeek = 0;
    stats.minutesWeek = 0;
    stats.lastResetWeek = weekStart;
  }
  
  s.set('stats', stats);
}

function getWeekStart(date) {
  const d = new Date(date);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.setDate(diff));
}

function updateStats(wordCount, durationMinutes = 0, isError = false) {
  const s = getStore();
  resetStatsIfNeeded();
  
  const stats = s.get('stats') || {};
  
  if (isError) {
    stats.errorsCount = (stats.errorsCount || 0) + 1;
  } else {
    stats.wordsTotal = (stats.wordsTotal || 0) + wordCount;
    stats.wordsToday = (stats.wordsToday || 0) + wordCount;
    stats.wordsWeek = (stats.wordsWeek || 0) + wordCount;
    stats.minutesTotal = (stats.minutesTotal || 0) + durationMinutes;
    stats.minutesToday = (stats.minutesToday || 0) + durationMinutes;
    stats.minutesWeek = (stats.minutesWeek || 0) + durationMinutes;
    stats.sessionsCount = (stats.sessionsCount || 0) + 1;
  }
  
  s.set('stats', stats);
  
  // Update owner stats (token estimation)
  if (s.get('ownerMode')) {
    const ownerStats = s.get('ownerStats') || {};
    // Rough estimation: ~1 token per 4 characters for text, ~100 tokens per minute for audio
    ownerStats.tokensGroq = (ownerStats.tokensGroq || 0) + Math.round(durationMinutes * 100);
    ownerStats.tokensAnthropic = (ownerStats.tokensAnthropic || 0) + Math.round(wordCount * 1.5);
    // Cost estimation: Groq ~$0.0001/min, Anthropic ~$0.00025/1k tokens
    ownerStats.estimatedCost = (ownerStats.estimatedCost || 0) + 
      (durationMinutes * 0.0001) + (wordCount * 1.5 * 0.00025 / 1000);
    s.set('ownerStats', ownerStats);
  }
  
  // Notify main window of stats update
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('stats:updated', stats);
  }
}

// ============================================================================
// HISTORY MANAGEMENT
// ============================================================================
const MAX_HISTORY = 100;

function addToHistory(entry) {
  const s = getStore();
  const history = s.get('history') || [];
  
  const wordCount = countWords(entry.polished || entry.transcript);
  const role = detectRole(entry.transcript);
  const delta = entry.polished ? calculateDelta(entry.transcript, entry.polished) : null;
  
  const newEntry = {
    id: Date.now(),
    timestamp: new Date().toISOString(),
    transcript: entry.transcript,
    polished: entry.polished || null,
    language: entry.language,
    role: role,
    wordCount: wordCount,
    delta: delta,
    polishUsed: !!entry.polished,
    favorite: false,
  };
  
  history.unshift(newEntry);
  if (history.length > MAX_HISTORY) {
    history.length = MAX_HISTORY;
  }
  s.set('history', history);
  
  // Update stats
  updateStats(wordCount, entry.durationMinutes || 0);
  
  updateTrayMenu();
  
  // Notify main window
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('history:updated', history);
  }
  
  return newEntry;
}

function getHistory() {
  return getStore().get('history') || [];
}

function clearHistory() {
  getStore().set('history', []);
  updateTrayMenu();
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('history:updated', []);
  }
}

function toggleFavorite(id) {
  const s = getStore();
  const history = s.get('history') || [];
  const item = history.find(h => h.id === id);
  if (item) {
    item.favorite = !item.favorite;
    s.set('history', history);
    return item.favorite;
  }
  return false;
}

function deleteHistoryItem(id) {
  const s = getStore();
  const history = s.get('history') || [];
  const index = history.findIndex(h => h.id === id);
  if (index !== -1) {
    history.splice(index, 1);
    s.set('history', history);
    updateTrayMenu();
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('history:updated', history);
    }
    return true;
  }
  return false;
}

// ============================================================================
// API CALLS
// ============================================================================
const GROQ_API_URL = 'https://api.groq.com/openai/v1/audio/transcriptions';
const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const GITHUB_REPO = 'allanhamduws-alt/paply';
const CURRENT_VERSION = require('./package.json').version;

async function transcribeAudio(audioBuffer, language = 'de') {
  const apiKey = getStore().get('groqApiKey');
  if (!apiKey) {
    throw new Error('Groq API Key nicht konfiguriert');
  }

  const formData = new FormData();
  const blob = new Blob([audioBuffer], { type: 'audio/webm' });
  formData.append('file', blob, 'audio.webm');
  formData.append('model', 'whisper-large-v3-turbo');
  formData.append('language', language);
  formData.append('response_format', 'json');

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);

  try {
    const res = await fetch(GROQ_API_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}` },
      body: formData,
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (!res.ok) {
      const errText = await res.text();
      console.error('Groq error:', res.status, errText);
      throw new Error(`Transkription fehlgeschlagen (${res.status})`);
    }

    const json = await res.json();
    return json?.text?.trim() ?? '';
  } catch (error) {
    clearTimeout(timeout);
    if (error.name === 'AbortError') throw new Error('Timeout nach 30s');
    throw error;
  }
}

// ============================================================================
// AUTO UPDATER (electron-updater)
// ============================================================================
let autoUpdater = null;
let updateCheckInProgress = false;
let downloadInProgress = false;

function getAutoUpdater() {
  if (!autoUpdater) {
    autoUpdater = require('electron-updater').autoUpdater;
    autoUpdater.autoDownload = false;
    autoUpdater.autoInstallOnAppQuit = true;
  }
  return autoUpdater;
}

function setupAutoUpdater() {
  const updater = getAutoUpdater();
  updater.on('checking-for-update', () => {
    console.log('Checking for updates...');
  });

  updater.on('update-available', (info) => {
    console.log('Update available:', info.version);
    updateCheckInProgress = false;
    
    dialog.showMessageBox({
      type: 'info',
      title: 'Update verfügbar!',
      message: `Neue Version ${info.version} verfügbar`,
      detail: `Du hast Version ${CURRENT_VERSION}.\n\n${info.releaseNotes || 'Neue Verbesserungen und Bugfixes.'}\n\nMöchtest du das Update jetzt herunterladen und installieren?`,
      buttons: ['Herunterladen', 'Später'],
      defaultId: 0,
    }).then((result) => {
      if (result.response === 0) {
        downloadInProgress = true;
        updater.downloadUpdate();
      }
    });
  });

  updater.on('update-not-available', (info) => {
    console.log('No update available, current version:', info.version);
    updateCheckInProgress = false;
    
    if (!updateCheckInProgress) {
      dialog.showMessageBox({
        type: 'info',
        title: 'Kein Update verfügbar',
        message: 'Du hast die neueste Version!',
        detail: `Aktuelle Version: ${CURRENT_VERSION}`,
        buttons: ['OK'],
      });
    }
  });

  updater.on('error', (error) => {
    console.error('Auto-updater error:', error);
    updateCheckInProgress = false;
    downloadInProgress = false;
    
    // Fallback: Open GitHub releases page
    dialog.showMessageBox({
      type: 'error',
      title: 'Update-Fehler',
      message: 'Auto-Update fehlgeschlagen',
      detail: `${error.message}\n\nMöchtest du die Releases-Seite öffnen?`,
      buttons: ['GitHub öffnen', 'Abbrechen'],
      defaultId: 0,
    }).then((result) => {
      if (result.response === 0) {
        shell.openExternal(`https://github.com/${GITHUB_REPO}/releases/latest`);
      }
    });
  });

  updater.on('download-progress', (progress) => {
    console.log(`Download progress: ${Math.round(progress.percent)}%`);
  });

  updater.on('update-downloaded', (info) => {
    console.log('Update downloaded:', info.version);
    downloadInProgress = false;
    
    dialog.showMessageBox({
      type: 'info',
      title: 'Update bereit',
      message: 'Update heruntergeladen!',
      detail: `Version ${info.version} wurde heruntergeladen.\n\nDie App wird jetzt neu gestartet, um das Update zu installieren.`,
      buttons: ['Jetzt neu starten', 'Später'],
      defaultId: 0,
    }).then((result) => {
      if (result.response === 0) {
        updater.quitAndInstall(false, true);
      }
    });
  });
}

async function checkForUpdates(silent = false) {
  if (updateCheckInProgress || downloadInProgress) {
    console.log('Update check already in progress');
    return;
  }
  
  updateCheckInProgress = true;
  const updater = getAutoUpdater();
  
  try {
    // Remove the dialog for silent checks
    if (silent) {
      updater.once('update-not-available', () => {
        updateCheckInProgress = false;
      });
    }
    
    await updater.checkForUpdates();
  } catch (error) {
    console.error('Update check failed:', error);
    updateCheckInProgress = false;
    
    if (!silent) {
      // Fallback to manual GitHub check
      await checkForUpdatesManual();
    }
  }
}

// Fallback manual update check (for unsigned builds)
async function checkForUpdatesManual() {
  try {
    const response = await fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases/latest`);
    if (!response.ok) {
      dialog.showMessageBox({
        type: 'error',
        title: 'Update-Prüfung fehlgeschlagen',
        message: 'Konnte nicht nach Updates suchen.',
        detail: `Status: ${response.status}`,
        buttons: ['OK'],
      });
      return null;
    }

    const release = await response.json();
    const latestVersion = release.tag_name.replace(/^v/, '');
    
    console.log(`Current version: ${CURRENT_VERSION}, Latest: ${latestVersion}`);

    if (compareVersions(latestVersion, CURRENT_VERSION) > 0) {
      const assetName = isMac ? '.dmg' : 'Setup';
      const downloadAsset = release.assets.find(a => 
        a.name.toLowerCase().includes(assetName.toLowerCase())
      );

      const result = await dialog.showMessageBox({
        type: 'info',
        title: 'Update verfügbar!',
        message: `Neue Version ${latestVersion} verfügbar`,
        detail: `Du hast Version ${CURRENT_VERSION}.\n\n${release.body || 'Neue Verbesserungen und Bugfixes.'}\n\nMöchtest du das Update jetzt herunterladen?\n\nHinweis: Nach dem Download bitte manuell installieren.`,
        buttons: ['Herunterladen', 'Später'],
        defaultId: 0,
      });

      if (result.response === 0) {
        const downloadUrl = downloadAsset?.browser_download_url || release.html_url;
        shell.openExternal(downloadUrl);
      }
      return { hasUpdate: true, version: latestVersion };
    } else {
      dialog.showMessageBox({
        type: 'info',
        title: 'Kein Update verfügbar',
        message: 'Du hast die neueste Version!',
        detail: `Aktuelle Version: ${CURRENT_VERSION}`,
        buttons: ['OK'],
      });
      return { hasUpdate: false, version: CURRENT_VERSION };
    }
  } catch (error) {
    console.error('Manual update check failed:', error);
    dialog.showMessageBox({
      type: 'error',
      title: 'Update-Prüfung fehlgeschlagen',
      message: 'Konnte nicht nach Updates suchen.',
      detail: error.message,
      buttons: ['OK'],
    });
    return null;
  }
}

function compareVersions(a, b) {
  const partsA = a.split('.').map(Number);
  const partsB = b.split('.').map(Number);
  
  for (let i = 0; i < Math.max(partsA.length, partsB.length); i++) {
    const numA = partsA[i] || 0;
    const numB = partsB[i] || 0;
    if (numA > numB) return 1;
    if (numA < numB) return -1;
  }
  return 0;
}

function getPolishPrompt(text, language, flavor) {
  const baseRules = `1. ENTFERNE: Füllwörter (ähm, äh, also, sozusagen, quasi, halt, ne, oder so), Wiederholungen, Versprecher
2. KORRIGIERE: Grammatik, Satzbau, Interpunktion - aber behalte den Inhalt exakt bei`;

  const flavorRules = {
    code: `3. TECH-BEGRIFFE: Korrigiere falsch erkannte Tech-Begriffe (use state → useState, shad cn → shadcn, react hook, Next.js, type script → TypeScript)
4. FORMATIERUNG: Behalte technische Begriffe präzise bei, keine Umschreibungen`,
    meeting: `3. STRUKTUR: Formatiere als klare Stichpunkte wenn sinnvoll
4. ACTION ITEMS: Markiere erkannte Aufgaben oder nächste Schritte
5. NAMEN: Behalte Personennamen bei`,
    plain: `3. NATÜRLICHKEIT: Behalte den natürlichen Sprachfluss bei
4. MINIMALISMUS: Nur offensichtliche Fehler korrigieren, Stil beibehalten`,
  };

  const flavorRule = flavorRules[flavor] || flavorRules.code;

  return `Du bist ein Transkriptions-Polierer. Deine EINZIGE Aufgabe: Sprache säubern.

SPRACHE: ${language}
MODUS: ${flavor === 'code' ? 'Technisch/Code' : flavor === 'meeting' ? 'Meeting/Business' : 'Plain/Diktat'}

REGELN:
${baseRules}
${flavorRule}

WICHTIG:
- Gib NUR den korrigierten Text zurück
- KEINE Kommentare, KEINE Erklärungen, KEINE Markdown-Formatierung
- KEINE Interpretation was der User "meinen könnte"

TEXT:
${text}`;
}

async function polishText(text, language = 'de', flavor = 'code') {
  const apiKey = getStore().get('haikuApiKey');
  if (!apiKey) return null;

  const prompt = getPolishPrompt(text, language, flavor);

  const payload = {
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 1024,
    system: 'You polish voice dictations for coding tasks.',
    messages: [{ role: 'user', content: prompt }],
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);

  try {
    const res = await fetch(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (!res.ok) {
      console.error('Anthropic error:', res.status);
      return null;
    }

    const json = await res.json();
    return json?.content?.[0]?.text?.trim() || null;
  } catch (error) {
    clearTimeout(timeout);
    console.error('Polish error:', error);
    return null;
  }
}

// ============================================================================
// WINDOWS
// ============================================================================
let tray = null;
let mainWindow = null;
let settingsWindow = null;
let historyWindow = null;
let recordingWindow = null;

function createMainWindow() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.focus();
    return mainWindow;
  }

  mainWindow = new BrowserWindow({
    width: 1100,
    height: 780,
    minWidth: 960,
    minHeight: 640,
    title: 'paply',
    backgroundColor: '#0f1115',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'dashboard.html'));
  mainWindow.on('closed', () => { mainWindow = null; });
  
  // On macOS, clicking the dock icon should show the window
  app.on('activate', () => {
    if (mainWindow === null) {
      createMainWindow();
    } else {
      mainWindow.show();
    }
  });

  return mainWindow;
}

function showMainWindow() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.show();
    mainWindow.focus();
  } else {
    createMainWindow();
  }
}

function createSettingsWindow() {
  if (settingsWindow && !settingsWindow.isDestroyed()) {
    settingsWindow.focus();
    return;
  }

  settingsWindow = new BrowserWindow({
    width: 500,
    height: 520,
    resizable: false,
    minimizable: false,
    maximizable: false,
    title: 'paply Einstellungen',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  settingsWindow.loadFile(path.join(__dirname, 'settings.html'));
  settingsWindow.on('closed', () => { settingsWindow = null; });
}

function createHistoryWindow() {
  if (historyWindow && !historyWindow.isDestroyed()) {
    historyWindow.focus();
    return;
  }

  historyWindow = new BrowserWindow({
    width: 600,
    height: 500,
    resizable: true,
    minimizable: true,
    title: 'paply History',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  historyWindow.loadFile(path.join(__dirname, 'history.html'));
  historyWindow.on('closed', () => { historyWindow = null; });
}

function createRecordingWindow() {
  if (recordingWindow && !recordingWindow.isDestroyed()) {
    return recordingWindow;
  }

  const { screen } = require('electron');
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width, height } = primaryDisplay.workAreaSize;

  // Compact widget size
  const widgetWidth = 140;
  const widgetHeight = 52;

  const windowOptions = {
    width: widgetWidth,
    height: widgetHeight,
    show: false,
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  };

  if (isMac) {
    windowOptions.frame = false;
    windowOptions.transparent = true;
    windowOptions.focusable = false;
  } else {
    windowOptions.frame = false;
    windowOptions.transparent = false;
    windowOptions.backgroundColor = '#1e1e1e';
    windowOptions.focusable = false;
  }

  recordingWindow = new BrowserWindow(windowOptions);

  recordingWindow.loadFile(path.join(__dirname, 'recording.html'));
  recordingWindow.on('closed', () => { recordingWindow = null; });

  // Position: bottom center, slightly above the Dock
  const x = Math.round((width - widgetWidth) / 2);
  const y = height - widgetHeight - 80; // 80px above bottom edge (above Dock)
  recordingWindow.setPosition(x, y);

  return recordingWindow;
}

function showAboutDialog() {
  const shortcut = getStore().get('shortcut');
  const quitKey = isMac ? '⌘Q' : 'Ctrl+Q';
  dialog.showMessageBox({
    type: 'info',
    title: 'Über paply',
    message: 'paply',
    detail: `Version ${CURRENT_VERSION}

Sprachtranskription mit Groq Whisper Large V3 Turbo
Optionales Polishing mit Claude Haiku 4.5

Shortcuts:
• ${shortcut} - Aufnahme starten/stoppen
• ${quitKey} - Beenden

© 2024 paply`,
    buttons: ['OK'],
  });
}

// ============================================================================
// TRAY MENU
// ============================================================================
function updateTrayMenu() {
  if (!tray) return;

  const s = getStore();
  const history = getHistory();
  const shortcut = s.get('shortcut');
  const enablePolish = s.get('enablePolish');
  const haikuKey = s.get('haikuApiKey');
  const groqKey = s.get('groqApiKey');

  const historySubmenu = history.length > 0
    ? history.slice(0, 10).map((item) => {
        const preview = (item.polished || item.transcript || '').substring(0, 40);
        const date = new Date(item.timestamp).toLocaleString('de-DE', {
          day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
        });
        return {
          label: `${date}: ${preview}${preview.length >= 40 ? '...' : ''}`,
          click: () => { clipboard.writeText(item.polished || item.transcript); },
        };
      })
    : [{ label: 'Keine Einträge', enabled: false }];

  if (history.length > 0) {
    historySubmenu.push({ type: 'separator' });
    historySubmenu.push({ label: 'Alle anzeigen...', click: createHistoryWindow });
    historySubmenu.push({ label: 'History löschen', click: clearHistory });
  }

  const statusLabel = groqKey
    ? (enablePolish && haikuKey ? '✓ Bereit (mit Polish)' : '✓ Bereit')
    : '⚠ API Key fehlt';

  const template = [
    { label: statusLabel, enabled: false },
    { type: 'separator' },
    { label: 'Dashboard öffnen', click: showMainWindow },
    { label: 'Transcribe', accelerator: shortcut, click: startTranscription },
    { type: 'separator' },
    { label: 'History', submenu: historySubmenu },
    { type: 'separator' },
    { label: 'Einstellungen...', click: createSettingsWindow },
    { label: 'Nach Updates suchen...', click: () => checkForUpdates(false) },
    { label: 'Über paply', click: showAboutDialog },
    { type: 'separator' },
    { label: 'Beenden', accelerator: getQuitAccelerator(), click: () => app.quit() },
  ];

  tray.setContextMenu(Menu.buildFromTemplate(template));
}

function setupTray() {
  let icon;

  if (isMac) {
    // macOS: Use template image for proper menubar appearance
    const iconPath = path.join(__dirname, 'iconTemplate.png');
    if (fs.existsSync(iconPath)) {
      icon = nativeImage.createFromPath(iconPath);
      icon.setTemplateImage(true);
    } else {
      icon = nativeImage.createFromDataURL(
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAAbwAAAG8B8aLcQwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAABYSURBVDiNY2CgMmBEF/j//z/DtWvX0IXh4vr6+v/////HKoauwMDAAN4cZAVwzYwQBmaGT58+MTAwMLxmYGBgYGJiYti7dy9cHq4ATQypBlkzVgNGNQADAGVDHxEz5ThqAAAAAElFTkSuQmCC',
      );
      icon.setTemplateImage(true);
    }
  } else {
    // Windows: Use regular colored icon
    const icoPath = path.join(__dirname, 'icon.ico');
    const pngPath = path.join(__dirname, 'icon.png');
    if (fs.existsSync(icoPath)) {
      icon = nativeImage.createFromPath(icoPath);
    } else if (fs.existsSync(pngPath)) {
      icon = nativeImage.createFromPath(pngPath);
    } else {
      icon = nativeImage.createFromDataURL(
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAAbwAAAG8B8aLcQwAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAABYSURBVDiNY2CgMmBEF/j//z/DtWvX0IXh4vr6+v/////HKoauwMDAAN4cZAVwzYwQBmaGT58+MTAwMLxmYGBgYGJiYti7dy9cHq4ATQypBlkzVgNGNQADAGVDHxEz5ThqAAAAAElFTkSuQmCC',
      );
    }
  }

  tray = new Tray(icon);
  tray.setToolTip('paply');
  updateTrayMenu();

  // On Windows, both left and right click should show the context menu
  if (isWin) {
    tray.on('click', () => { tray.popUpContextMenu(); });
    tray.on('right-click', () => { tray.popUpContextMenu(); });
  } else {
    tray.on('click', () => { tray.popUpContextMenu(); });
  }
}

// ============================================================================
// RECORDING & TRANSCRIPTION
// ============================================================================
let isRecording = false;
let previousAppName = null;

function savePreviousApp() {
  return new Promise((resolve) => {
    if (isMac) {
      const proc = spawn('osascript', [
        '-e', 'tell application "System Events" to get name of first application process whose frontmost is true',
      ]);
      let output = '';
      proc.stdout.on('data', (d) => { output += d.toString(); });
      proc.on('close', () => { previousAppName = output.trim(); resolve(previousAppName); });
      proc.on('error', () => resolve(null));
    } else {
      // On Windows, we don't track previous app - just resolve
      resolve(null);
    }
  });
}

// Simple placeholder "..." - animation happens in the widget, not in text
const PLACEHOLDER = '...';

function insertPlaceholder() {
  clipboard.writeText(PLACEHOLDER);

  if (isMac) {
    const script = previousAppName
      ? `tell application "${previousAppName}" to activate
         delay 0.2
         tell application "System Events" to keystroke "v" using command down`
      : `delay 0.15
         tell application "System Events" to keystroke "v" using command down`;

    return new Promise((resolve) => {
      setTimeout(() => {
        const proc = spawn('osascript', ['-e', script]);
        proc.on('close', () => setTimeout(resolve, 100));
        proc.on('error', () => resolve());
      }, 100);
    });
  } else if (isWin) {
    return new Promise((resolve) => {
      setTimeout(() => {
        const psScript = `Add-Type -AssemblyName System.Windows.Forms; Start-Sleep -Milliseconds 50; [System.Windows.Forms.SendKeys]::SendWait('^v')`;
        const tempFile = path.join(app.getPath('temp'), 'paply-placeholder.ps1');
        fs.writeFileSync(tempFile, psScript, 'utf8');
        exec(`powershell -ExecutionPolicy Bypass -File "${tempFile}"`, () => {
          try { fs.unlinkSync(tempFile); } catch (e) { /* ignore */ }
          resolve();
        });
      }, 150);
    });
  }
  return Promise.resolve();
}

function replacePlaceholderWithText(text) {
  // Delete "..." (3 backspaces) then paste text
  if (isMac) {
    const pasteCommand = text ? `keystroke "v" using command down` : '';
    const script = previousAppName
      ? `tell application "${previousAppName}" to activate
         delay 0.2
         tell application "System Events"
           key code 51
           key code 51
           key code 51
           delay 0.05
           ${pasteCommand}
         end tell`
      : `delay 0.15
         tell application "System Events"
           key code 51
           key code 51
           key code 51
           delay 0.05
           ${pasteCommand}
         end tell`;

    if (text) clipboard.writeText(text);
    setTimeout(() => {
      const proc = spawn('osascript', ['-e', script]);
      proc.stderr.on('data', (d) => console.error('AppleScript error:', d.toString()));
    }, 100);
  } else if (isWin) {
    if (text) clipboard.writeText(text);
    setTimeout(() => {
      const pasteCommand = text ? `Start-Sleep -Milliseconds 30; [System.Windows.Forms.SendKeys]::SendWait('^v')` : '';
      const psScript = `
Add-Type -AssemblyName System.Windows.Forms
Start-Sleep -Milliseconds 50
[System.Windows.Forms.SendKeys]::SendWait("{BACKSPACE}{BACKSPACE}{BACKSPACE}")
${pasteCommand}
      `.trim();
      const tempFile = path.join(app.getPath('temp'), 'paply-paste.ps1');
      fs.writeFileSync(tempFile, psScript, 'utf8');
      exec(`powershell -ExecutionPolicy Bypass -File "${tempFile}"`, (err, stdout, stderr) => {
        if (err) console.error('PowerShell paste error:', err);
        if (stderr) console.error('PowerShell stderr:', stderr);
        try { fs.unlinkSync(tempFile); } catch (e) { /* ignore */ }
      });
    }, 100);
  }
}

function autopasteText(text) {
  clipboard.writeText(text);

  if (isMac) {
    const script = previousAppName
      ? `tell application "${previousAppName}" to activate
         delay 0.3
         tell application "System Events" to keystroke "v" using command down`
      : `delay 0.2
         tell application "System Events" to keystroke "v" using command down`;

    setTimeout(() => {
      const proc = spawn('osascript', ['-e', script]);
      proc.stderr.on('data', (d) => console.error('AppleScript error:', d.toString()));
    }, 150);
  } else if (isWin) {
    setTimeout(() => {
      const psScript = `
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait('^v')
      `.trim();
      
      const tempFile = path.join(app.getPath('temp'), 'paply-paste.ps1');
      fs.writeFileSync(tempFile, psScript, 'utf8');
      
      exec(`powershell -ExecutionPolicy Bypass -File "${tempFile}"`, (err, stdout, stderr) => {
        if (err) console.error('PowerShell paste error:', err);
        if (stderr) console.error('PowerShell stderr:', stderr);
        try { fs.unlinkSync(tempFile); } catch (e) { /* ignore */ }
      });
    }, 400);
  }
}

function startTranscription() {
  if (isRecording) {
    isRecording = false;
    recordingWindow?.webContents.send('recording:stop');
    // Window bleibt offen für Spinner - wird in 'recording:audio' Handler versteckt
  } else {
    isRecording = true;
    savePreviousApp();
    const win = createRecordingWindow();
    win.showInactive();
    win.webContents.send('recording:start');
  }
}

// ============================================================================
// HOTKEY
// ============================================================================
let currentShortcut = null;
let smartPasteWindow = null;

function registerHotkey() {
  const shortcut = getStore().get('shortcut');
  if (currentShortcut) globalShortcut.unregister(currentShortcut);

  const ok = globalShortcut.register(shortcut, () => {
    console.log('Hotkey pressed:', shortcut);
    startTranscription();
  });

  if (ok) {
    currentShortcut = shortcut;
    console.log('Hotkey registered:', shortcut);
  } else {
    console.error('Hotkey registration failed:', shortcut);
  }
  
  // Register Smart-Paste hotkey (Cmd/Ctrl+Shift+V)
  const smartPasteKey = isMac ? 'Command+Shift+V' : 'Ctrl+Shift+V';
  globalShortcut.register(smartPasteKey, () => {
    console.log('Smart-Paste hotkey pressed');
    showSmartPasteOverlay();
  });
}

function showSmartPasteOverlay() {
  // Get last transcript from history
  const history = getHistory();
  if (history.length === 0) {
    dialog.showMessageBox({
      type: 'info',
      title: 'Smart-Paste',
      message: 'Keine Transkription vorhanden',
      detail: 'Erstelle zuerst eine Transkription, um Smart-Paste zu nutzen.',
      buttons: ['OK'],
    });
    return;
  }

  const lastText = history[0].polished || history[0].transcript;
  const snippets = getStore().get('snippets') || [];

  // Build menu for snippet selection
  const template = [
    { label: 'Als Plain Text', click: () => { clipboard.writeText(lastText); } },
    { label: 'Als Markdown', click: () => { clipboard.writeText('```\n' + lastText + '\n```'); } },
    { type: 'separator' },
  ];

  snippets.forEach(snippet => {
    template.push({
      label: `Snippet: ${snippet.name}`,
      click: () => {
        const result = snippet.template.replace(/\{\{text\}\}/g, lastText);
        clipboard.writeText(result);
      },
    });
  });

  const menu = Menu.buildFromTemplate(template);
  menu.popup();
}

// ============================================================================
// IPC HANDLERS
// ============================================================================
function setupIpcHandlers() {
  // Settings
  ipcMain.handle('settings:get', () => {
    const s = getStore();
    return {
      groqApiKey: s.get('groqApiKey'),
      haikuApiKey: s.get('haikuApiKey'),
      enablePolish: s.get('enablePolish'),
      shortcut: s.get('shortcut'),
      autoStart: s.get('autoStart'),
      language: s.get('language'),
      autopaste: s.get('autopaste'),
      beepEnabled: s.get('beepEnabled'),
      hideDock: s.get('hideDock'),
      activeProfile: s.get('activeProfile'),
    };
  });

  ipcMain.handle('settings:set', (_event, settings) => {
    const s = getStore();
    if (settings.groqApiKey !== undefined) s.set('groqApiKey', settings.groqApiKey);
    if (settings.haikuApiKey !== undefined) s.set('haikuApiKey', settings.haikuApiKey);
    if (settings.enablePolish !== undefined) s.set('enablePolish', settings.enablePolish);
    if (settings.language !== undefined) s.set('language', settings.language);
    if (settings.autopaste !== undefined) s.set('autopaste', settings.autopaste);
    if (settings.beepEnabled !== undefined) s.set('beepEnabled', settings.beepEnabled);

    if (settings.shortcut !== undefined && settings.shortcut !== s.get('shortcut')) {
      s.set('shortcut', settings.shortcut);
      registerHotkey();
    }

    if (settings.autoStart !== undefined) {
      s.set('autoStart', settings.autoStart);
      updateAutoLaunch();
    }

    if (settings.hideDock !== undefined) {
      s.set('hideDock', settings.hideDock);
      if (app.dock) {
        if (settings.hideDock) {
          app.dock.hide();
        } else {
          app.dock.show();
        }
      }
    }

    if (settings.activeProfile !== undefined) {
      s.set('activeProfile', settings.activeProfile);
    }

    updateTrayMenu();
    return true;
  });

  // History
  ipcMain.handle('history:get', () => getHistory());
  ipcMain.handle('history:clear', () => { clearHistory(); return true; });
  ipcMain.handle('history:copy', (_event, id) => {
    const item = getHistory().find((h) => h.id === id);
    if (item) {
      clipboard.writeText(item.polished || item.transcript);
      return true;
    }
    return false;
  });
  ipcMain.handle('history:delete', (_event, id) => deleteHistoryItem(id));
  ipcMain.handle('history:toggleFavorite', (_event, id) => toggleFavorite(id));
  
  // Stats
  ipcMain.handle('stats:get', () => {
    resetStatsIfNeeded();
    return getStore().get('stats');
  });
  
  ipcMain.handle('stats:owner', () => {
    const s = getStore();
    if (!s.get('ownerMode')) return null;
    return s.get('ownerStats');
  });
  
  // Owner Mode
  ipcMain.handle('owner:check', () => getStore().get('ownerMode'));
  ipcMain.handle('owner:toggle', (_event, password) => {
    // Simple password check for owner mode (can be changed)
    const s = getStore();
    if (password === 'paply-owner-2024') {
      s.set('ownerMode', !s.get('ownerMode'));
      return s.get('ownerMode');
    }
    return false;
  });
  
  // Profiles
  ipcMain.handle('profiles:get', () => {
    const s = getStore();
    return {
      active: s.get('activeProfile'),
      profiles: s.get('profiles'),
    };
  });
  
  ipcMain.handle('profiles:setActive', (_event, profileId) => {
    const s = getStore();
    const profiles = s.get('profiles');
    if (profiles[profileId]) {
      s.set('activeProfile', profileId);
      // Apply profile settings
      const profile = profiles[profileId];
      if (profile.language) s.set('language', profile.language);
      if (profile.autopaste !== undefined) s.set('autopaste', profile.autopaste);
      updateTrayMenu();
      return true;
    }
    return false;
  });
  
  ipcMain.handle('profiles:update', (_event, profileId, updates) => {
    const s = getStore();
    const profiles = s.get('profiles');
    if (profiles[profileId]) {
      profiles[profileId] = { ...profiles[profileId], ...updates };
      s.set('profiles', profiles);
      return true;
    }
    return false;
  });
  
  // Snippets
  ipcMain.handle('snippets:get', () => getStore().get('snippets'));
  
  ipcMain.handle('snippets:add', (_event, snippet) => {
    const s = getStore();
    const snippets = s.get('snippets') || [];
    const newSnippet = {
      id: `custom-${Date.now()}`,
      name: snippet.name,
      template: snippet.template,
    };
    snippets.push(newSnippet);
    s.set('snippets', snippets);
    return newSnippet;
  });
  
  ipcMain.handle('snippets:delete', (_event, id) => {
    const s = getStore();
    const snippets = s.get('snippets') || [];
    const index = snippets.findIndex(sn => sn.id === id);
    if (index !== -1) {
      snippets.splice(index, 1);
      s.set('snippets', snippets);
      return true;
    }
    return false;
  });
  
  ipcMain.handle('snippets:apply', (_event, snippetId, text) => {
    const snippets = getStore().get('snippets') || [];
    const snippet = snippets.find(sn => sn.id === snippetId);
    if (snippet) {
      const result = snippet.template.replace(/\{\{text\}\}/g, text);
      clipboard.writeText(result);
      return result;
    }
    return text;
  });
  
  // Transcription trigger from dashboard
  ipcMain.handle('transcription:start', () => {
    startTranscription();
    return true;
  });
  
  ipcMain.handle('transcription:stop', () => {
    if (isRecording) {
      isRecording = false;
      recordingWindow?.webContents.send('recording:stop');
    }
    return true;
  });
  
  ipcMain.handle('transcription:status', () => ({
    isRecording,
  }));

  ipcMain.on('recording:audio', async (_event, audioData) => {
    console.log('Received audio:', audioData.byteLength, 'bytes');
    isRecording = false;

    // Helper to update status in recording window
    const updateStatus = (status, detail = '') => {
      recordingWindow?.webContents.send('status:update', { status, detail });
    };

    const s = getStore();
    const autopaste = s.get('autopaste');
    let placeholderInserted = false;

    try {
      const language = s.get('language');
      const enablePolish = s.get('enablePolish');
      const haikuKey = s.get('haikuApiKey');

      // Show transcribing status
      updateStatus('transcribing');

      // Insert placeholder at cursor if autopaste is enabled
      if (autopaste) {
        await insertPlaceholder();
        placeholderInserted = true;
      }

      const transcript = await transcribeAudio(Buffer.from(audioData), language);
      console.log('Transcript:', transcript);

      if (!transcript) {
        // Delete placeholder if inserted but no result
        if (placeholderInserted) {
          replacePlaceholderWithText('');
        }
        updateStatus('done');
        setTimeout(() => recordingWindow?.hide(), 300);
        return;
      }

      let polished = null;
      if (enablePolish && haikuKey) {
        // Show polishing status
        updateStatus('polishing');
        // Get polish flavor from active profile
        const activeProfileId = s.get('activeProfile') || 'coding';
        const profiles = s.get('profiles') || {};
        const activeProfile = profiles[activeProfileId] || {};
        const polishFlavor = activeProfile.polishFlavor || 'code';
        polished = await polishText(transcript, language, polishFlavor);
        console.log('Polished:', polished);
      }

      addToHistory({ transcript, polished, language });

      const finalText = polished || transcript;
      if (autopaste) {
        // Replace placeholder with final text
        replacePlaceholderWithText(finalText);
      } else {
        clipboard.writeText(finalText);
      }

      // Show success and hide
      updateStatus('done');
      setTimeout(() => recordingWindow?.hide(), 300);
    } catch (error) {
      console.error('Transcription error:', error);
      // Delete placeholder if error occurred
      if (placeholderInserted) {
        replacePlaceholderWithText('');
      }
      updateStatus('error', error.message || 'Transkription fehlgeschlagen');
      setTimeout(() => {
        recordingWindow?.hide();
        dialog.showErrorBox('Fehler', error.message || 'Transkription fehlgeschlagen');
      }, 1500);
    }
  });

  ipcMain.on('open:accessibility', () => {
    if (isMac) {
      shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility');
    } else if (isWin) {
      // On Windows, open Privacy Settings
      shell.openExternal('ms-settings:privacy-microphone');
    }
  });

  // Expose platform info to renderer
  ipcMain.handle('platform:get', () => ({
    isMac,
    isWin,
    platform: process.platform,
  }));
}

// ============================================================================
// APP LIFECYCLE
// ============================================================================
app.whenReady().then(() => {
  const s = getStore();
  
  // Dock-Icon verstecken wenn gewünscht (Standard: sichtbar)
  if (app.dock && s.get('hideDock')) {
    app.dock.hide();
  }
  
  // Setup auto-updater
  setupAutoUpdater();
  
  setupIpcHandlers();
  setupTray();
  createRecordingWindow();
  registerHotkey();
  updateAutoLaunch();
  
  // Reset daily/weekly stats if needed
  resetStatsIfNeeded();

  console.log('paply started');
  console.log('Version:', CURRENT_VERSION);
  console.log('Shortcut:', s.get('shortcut'));
  console.log('Groq Key:', s.get('groqApiKey') ? 'Set' : 'Not set');
  console.log('Haiku Key:', s.get('haikuApiKey') ? 'Set' : 'Not set');

  // Auto-open dashboard (or settings on first run if no API key)
  if (!s.get('groqApiKey')) {
    setTimeout(() => {
      createMainWindow();
      dialog.showMessageBox({
        type: 'info',
        title: 'Willkommen bei paply!',
        message: 'API Key benötigt',
        detail: 'Bitte konfiguriere deinen Groq API Key in den Einstellungen.\n\nDu kannst einen kostenlosen API Key hier erstellen:\nhttps://console.groq.com/keys',
        buttons: ['OK'],
      });
    }, 500);
  } else {
    // Open main window on startup
    setTimeout(() => createMainWindow(), 300);
  }

  // Check for updates silently on startup (after 5 seconds)
  setTimeout(() => {
    checkForUpdates(true);
  }, 5000);
});

app.on('will-quit', () => { globalShortcut.unregisterAll(); });
app.on('window-all-closed', (e) => { e.preventDefault(); });
