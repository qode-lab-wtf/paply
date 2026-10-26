'use strict';
const { uid } = require('./contracts');
function createLedger(repo, getSettings, now = Date.now) {
  let records = repo.readLocal('ledger.json', []); if (!Array.isArray(records)) records = [];
  const clean = () => { records = records.filter(r => r.at > now() - 86400000); };
  const save = () => repo.writeLocal('ledger.json', records);
  function reserve(model, amount, unit = 'tokens') {
    clean(); const settings = getSettings();
    const daily = records.filter(r => r.unit === unit).reduce((v, r) => v + r.amount, 0);
    const minute = records.filter(r => r.model === model && r.at > now() - 60000);
    const limit = unit === 'tokens' ? settings.dailyTokens : settings.dailyAudioMinutes * 60;
    const minuteLimit = unit === 'tokens' ? 7600 : 1800;
    if (amount > limit) { const e = new Error(unit === 'tokens' ? 'Notes-Budget zu klein für diesen Gedanken · Budget erhöhen und erneut versuchen' : 'Audio-Budget zu klein für diese Aufnahme · Budget erhöhen und erneut versuchen'); e.kind = 'budget_small'; throw e; }
    if (daily + amount > limit || minute.reduce((v, r) => v + r.amount, 0) + amount > minuteLimit || minute.length >= 15) {
      const error = new Error(daily + amount > limit ? 'Notes-Budget erreicht · Gedanken bleiben gesichert' : 'Kurze Pause für das Groq-Limit');
      error.kind = 'budget'; error.retryMs = daily + amount > limit ? Math.max(60000, Math.min(...records.filter(r => r.unit === unit).map(r => r.at)) + 86400000 - now()) : 61000; throw error;
    }
    const r = { id: uid('q'), at: now(), model, amount, unit, pending: true }; records.push(r); save(); return r.id;
  }
  function settle(id, actual) { const r = records.find(r => r.id === id); if (!r) return; if (Number.isFinite(actual) && actual >= 0) r.amount = actual; r.pending = false; save(); }
  return { reserve, settle, summary() { clean(); return { tokens: records.filter(r => r.unit === 'tokens').reduce((v, r) => v + r.amount, 0), audioSeconds: records.filter(r => r.unit === 'audio').reduce((v, r) => v + r.amount, 0), requests: records.length }; } };
}
module.exports = { createLedger };
