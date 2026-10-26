'use strict';
const { sameShortcut } = require('../dictation/policies');
const { assert } = require('./contracts');
const { readKeyLabels, physicalKey } = require('./keymap');
function defaults(platform = process.platform, keyLabels = {}) { const key = physicalKey('Y', keyLabels); return { enabled: true, captureHotkey: platform === 'darwin' ? `Command+${key}` : 'Control+Alt+Y', openHotkey: platform === 'darwin' ? `Command+Alt+${key}` : 'Control+Alt+Shift+Y', screenContext: false, imageUnderstanding: false, dailyTokens: 100000, dailyAudioMinutes: 60 }; }
function createSettings({ store, globalShortcut, otherShortcuts, capture, open, interceptShortcut = () => false, platform = process.platform, loadKeyLabels = () => readKeyLabels({ platform }), changed = () => {} }) {
  let keyLabels = loadKeyLabels();
  let value = { ...defaults(platform, keyLabels), ...store.get('notesSettings', {}) }, registered = [], warning = '';
  function validate(v) {
    assert(typeof v.enabled === 'boolean' && typeof v.screenContext === 'boolean' && typeof v.imageUnderstanding === 'boolean');
    for (const key of ['captureHotkey', 'openHotkey']) assert(typeof v[key] === 'string' && v[key].length > 0 && v[key].length <= 100 && !/[\r\n]/.test(v[key]), 'Bitte ein gültiges Tastenkürzel wählen.');
    assert(!sameShortcut(v.captureHotkey, v.openHotkey, platform), 'Aufnehmen und Öffnen brauchen unterschiedliche Kürzel.');
    assert(Number.isInteger(v.dailyTokens) && v.dailyTokens >= 5000 && v.dailyTokens <= 180000 && Number.isInteger(v.dailyAudioMinutes) && v.dailyAudioMinutes >= 1 && v.dailyAudioMinutes <= 120, 'Ungültiges Notes-Budget.');
    if (v.enabled) for (const hk of [v.captureHotkey, v.openHotkey]) assert(!otherShortcuts().filter(Boolean).some(x => sameShortcut(x, hk, platform)), 'Dieses Kürzel verwendet Paply bereits.');
  }
  function register(next, persist) {
    validate(next); const wanted = next.enabled ? [next.captureHotkey, next.openHotkey] : [], added = [];
    try {
      for (const key of wanted) {
        if (registered.some(x => sameShortcut(x, key, platform))) continue;
        const ok = globalShortcut.register(key, () => { if (interceptShortcut(key)) return; if (sameShortcut(key, value.captureHotkey, platform)) capture(); else open(); });
        assert(ok, 'Dieses Tastenkürzel ist bereits belegt. Bitte ein anderes wählen.'); added.push(key);
      }
      if (persist) store.set('notesSettings', next);
    } catch (e) { added.forEach(key => globalShortcut.unregister(key)); throw e; }
    const retained = registered.filter(x => wanted.some(key => sameShortcut(x, key, platform)));
    registered.filter(x => !retained.includes(x)).forEach(key => globalShortcut.unregister(key));
    registered = [...retained, ...added]; value = next; warning = ''; changed(); return get();
  }
  function get() { return { ...value, warning, hasGroqKey: !!store.get('groqApiKey'), platform, keyLabels }; }
  return { get, start() { try { register(value, false); } catch (e) { warning = e.message; } },
    refreshKeyLabels() { keyLabels = loadKeyLabels(); },
    set(patch) { assert(patch && Object.keys(patch).every(k => Object.hasOwn(defaults(platform), k))); return register({ ...value, ...patch }, true); },
    shutdown() { registered.forEach(k => globalShortcut.unregister(k)); registered = []; },
  };
}
module.exports = { createSettings, defaults };
