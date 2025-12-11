const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // Settings
  getSettings: () => ipcRenderer.invoke('settings:get'),
  setSettings: (settings) => ipcRenderer.invoke('settings:set', settings),

  // History
  getHistory: () => ipcRenderer.invoke('history:get'),
  clearHistory: () => ipcRenderer.invoke('history:clear'),
  copyHistoryItem: (id) => ipcRenderer.invoke('history:copy', id),
  deleteHistoryItem: (id) => ipcRenderer.invoke('history:delete', id),
  toggleFavorite: (id) => ipcRenderer.invoke('history:toggleFavorite', id),
  onHistoryUpdated: (cb) => ipcRenderer.on('history:updated', (_e, history) => cb(history)),

  // Recording
  onRecordingStart: (cb) => ipcRenderer.on('recording:start', cb),
  onRecordingStop: (cb) => ipcRenderer.on('recording:stop', cb),
  onStatusUpdate: (cb) => ipcRenderer.on('status:update', (_e, status) => cb(status)),
  sendAudio: (audioData) => ipcRenderer.send('recording:audio', audioData),

  // Transcription control (from dashboard)
  startTranscription: () => ipcRenderer.invoke('transcription:start'),
  stopTranscription: () => ipcRenderer.invoke('transcription:stop'),
  getTranscriptionStatus: () => ipcRenderer.invoke('transcription:status'),

  // Stats
  getStats: () => ipcRenderer.invoke('stats:get'),
  getOwnerStats: () => ipcRenderer.invoke('stats:owner'),
  onStatsUpdated: (cb) => ipcRenderer.on('stats:updated', (_e, stats) => cb(stats)),

  // Owner Mode
  checkOwnerMode: () => ipcRenderer.invoke('owner:check'),
  toggleOwnerMode: (password) => ipcRenderer.invoke('owner:toggle', password),

  // Profiles
  getProfiles: () => ipcRenderer.invoke('profiles:get'),
  setActiveProfile: (profileId) => ipcRenderer.invoke('profiles:setActive', profileId),
  updateProfile: (profileId, updates) => ipcRenderer.invoke('profiles:update', profileId, updates),

  // Snippets
  getSnippets: () => ipcRenderer.invoke('snippets:get'),
  addSnippet: (snippet) => ipcRenderer.invoke('snippets:add', snippet),
  deleteSnippet: (id) => ipcRenderer.invoke('snippets:delete', id),
  applySnippet: (snippetId, text) => ipcRenderer.invoke('snippets:apply', snippetId, text),

  // Accessibility
  openAccessibilitySettings: () => ipcRenderer.send('open:accessibility'),

  // Platform
  getPlatform: () => ipcRenderer.invoke('platform:get'),
});
