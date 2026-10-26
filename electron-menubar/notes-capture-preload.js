const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('paplyNotesCapture', {
  ready: () => ipcRenderer.invoke('notes:capture:ready'),
  pcm: payload => ipcRenderer.invoke('notes:pcm', payload),
  flushed: payload => ipcRenderer.invoke('notes:capture:flushed', payload),
  failed: payload => ipcRenderer.invoke('notes:capture:failed', payload),
  stop: () => ipcRenderer.invoke('notes:capture:stop'),
  camera: () => ipcRenderer.invoke('notes:capture:camera'),
  onState: cb => { const listener = (_e, value) => cb(value); ipcRenderer.on('notes:capture:state', listener); return () => ipcRenderer.removeListener('notes:capture:state', listener); },
});
