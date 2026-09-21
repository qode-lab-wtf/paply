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
  onErrorRetry: (cb) => ipcRenderer.on('error:retry', (_e, data) => cb(data)),
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

  // Profiles / Agents
  getProfiles: () => ipcRenderer.invoke('profiles:get'),
  setActiveProfile: (profileId) => ipcRenderer.invoke('profiles:setActive', profileId),
  updateProfile: (profileId, updates) => ipcRenderer.invoke('profiles:update', profileId, updates),
  onAgentSwitched: (cb) => ipcRenderer.on('agent:switched', (_e, data) => cb(data)),
  
  // Custom Agents CRUD
  getCustomAgents: () => ipcRenderer.invoke('agents:getAll'),
  createAgent: (agent) => ipcRenderer.invoke('agents:create', agent),
  updateAgent: (agentId, updates) => ipcRenderer.invoke('agents:update', agentId, updates),
  deleteAgent: (agentId) => ipcRenderer.invoke('agents:delete', agentId),
  reorderAgents: (orderedIds) => ipcRenderer.invoke('agents:reorder', orderedIds),
  updateAgentHotkey: (agentId, hotkey) => ipcRenderer.invoke('agents:updateHotkey', agentId, hotkey),
  
  // Snippets
  getSnippets: () => ipcRenderer.invoke('snippets:get'),
  addSnippet: (snippet) => ipcRenderer.invoke('snippets:add', snippet),
  deleteSnippet: (id) => ipcRenderer.invoke('snippets:delete', id),
  applySnippet: (snippetId, text) => ipcRenderer.invoke('snippets:apply', snippetId, text),

  // Accessibility
  openAccessibilitySettings: () => ipcRenderer.send('open:accessibility'),

  // Meeting-Recorder
  startMeeting: () => ipcRenderer.invoke('meeting:start'),
  stopMeeting: () => ipcRenderer.invoke('meeting:stop'),
  getMeetingStatus: () => ipcRenderer.invoke('meeting:get-status'),
  sendMicPcm: (buf, meta) => ipcRenderer.send('meeting:mic-pcm', buf, meta),
  reportMeetingCaptureError: (error) => ipcRenderer.send('meeting:capture-error', error),
  acknowledgeMeetingCaptureStop: (id) => ipcRenderer.send('meeting:capture-stopped', id),
  onMeetingCaptureStop: (cb) => { const listener = (_e, value) => cb(value); ipcRenderer.on('meeting:capture-stop', listener); return () => ipcRenderer.removeListener('meeting:capture-stop', listener); },
  correctMeetingSegment: (id, segmentId, patch) => ipcRenderer.invoke('meetings:correct-segment', id, segmentId, patch),
  exportMeeting: (id, format) => ipcRenderer.invoke('meetings:export', id, format),
  onMeetingsUpdated: (cb) => { const listener = (_e, data) => cb(data); ipcRenderer.on('meetings:updated', listener); return () => ipcRenderer.removeListener('meetings:updated', listener); },
  sendMicLevel: (lvl) => ipcRenderer.send('meeting:mic-level', lvl),
  sendSystemPcm: (buf) => ipcRenderer.send('meeting:system-pcm', buf),
  setMeetingDiarization: (enabled) => ipcRenderer.invoke('meeting:set-diarization', enabled),
  setOverlayExpanded: (expanded) => ipcRenderer.send('meeting:overlay-expand', expanded),
  listMeetings: () => ipcRenderer.invoke('meetings:list'),
  getMeeting: (id) => ipcRenderer.invoke('meetings:get', id),
  deleteMeeting: (id) => ipcRenderer.invoke('meetings:delete', id),
  retranscribeMeeting: (id) => ipcRenderer.invoke('meetings:retranscribe', id),
  regenerateSummary: (id) => ipcRenderer.invoke('meetings:regenerateSummary', id),
  updateSpeakerName: (id, channel, name) => ipcRenderer.invoke('meetings:updateSpeakerName', id, channel, name),
  renameSpeaker: (id, fromSpeaker, toName) => ipcRenderer.invoke('meetings:renameSpeaker', id, fromSpeaker, toName),
  toggleMeetingTodo: (id, idx) => ipcRenderer.invoke('meetings:toggleTodo', id, idx),
  onMeetingStatus: (cb) => { const listener = (_e, value) => cb(value); ipcRenderer.on('meeting:status', listener); return () => ipcRenderer.removeListener('meeting:status', listener); },
  onMeetingTranscriptChunk: (cb) => { const listener = (_e, value) => cb(value); ipcRenderer.on('meeting:transcript-chunk', listener); return () => ipcRenderer.removeListener('meeting:transcript-chunk', listener); },
  onMeetingStarted: (cb) => { const listener = (_e, value) => cb(value); ipcRenderer.on('meeting:started', listener); return () => ipcRenderer.removeListener('meeting:started', listener); },
  onMeetingStopped: (cb) => { const listener = (_e, value) => cb(value); ipcRenderer.on('meeting:stopped', listener); return () => ipcRenderer.removeListener('meeting:stopped', listener); },
  onMeetingCallState: (cb) => { const listener = (_e, value) => cb(value); ipcRenderer.on('meeting:call-state', listener); return () => ipcRenderer.removeListener('meeting:call-state', listener); },

  // Platform
  getPlatform: () => ipcRenderer.invoke('platform:get'),
});
