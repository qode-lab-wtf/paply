const { contextBridge, ipcRenderer } = require('electron');
const on = (channel, cb) => { const listener = (_e, value) => cb(value); ipcRenderer.on(channel, listener); return () => ipcRenderer.removeListener(channel, listener); };
contextBridge.exposeInMainWorld('paplyNotes', {
  get: () => ipcRenderer.invoke('notes:board:get'),
  editing: value => ipcRenderer.invoke('notes:editing', value),
  command: ops => ipcRenderer.invoke('notes:command', ops),
  place: positions => ipcRenderer.invoke('notes:place', positions),
  viewport: value => ipcRenderer.invoke('notes:viewport', value),
  undo: () => ipcRenderer.invoke('notes:undo'), redo: () => ipcRenderer.invoke('notes:redo'),
  addText: value => ipcRenderer.invoke('notes:text', value),
  copy: text => ipcRenderer.invoke('notes:copy', text),
  attach: payload => ipcRenderer.invoke('notes:attach', payload),
  camera: payload => ipcRenderer.invoke('notes:camera', payload),
  source: id => ipcRenderer.invoke('notes:source', id),
  retry: id => ipcRenderer.invoke('notes:retry', id), discard: id => ipcRenderer.invoke('notes:discard', id),
  capture: () => ipcRenderer.invoke('notes:capture:toggle'),
  settings: () => ipcRenderer.invoke('notes:settings:open'),
  onChange: cb => on('notes:changed', cb), onKey: cb => on('notes:key', cb),
});
