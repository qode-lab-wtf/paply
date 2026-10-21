// Großzügiges Ausgabebudget; abgeschnittene Antworten werden vollständig verworfen.
function polishTokenBudget(text) {
  return Math.min(32768, Math.max(4096, Math.ceil(text.length / 3) * 2));
}
function completePolish(json) {
  const choice = json?.choices?.[0];
  if (choice?.finish_reason === 'length') return null;
  return choice?.message?.content?.trim() || null;
}
function friendlyError(error) {
  const message = String(error?.message || error || '');
  if (/mikro|micro|permission|notallowederror|notfounderror|notreadableerror/i.test(message)) return 'Mikrofon gesperrt';
  if (/401|403|api.?key|invalid.*key|nicht konfiguriert/i.test(message)) return 'Groq-Schlüssel ungültig';
  if (/429|rate.?limit|quota|limit reached/i.test(message)) return 'Groq-Limit erreicht';
  if (/fetch|network|netz|ECONN|ENOTFOUND|ETIMEDOUT|abort|timeout/i.test(message)) return 'Keine Verbindung';
  return 'Diktat fehlgeschlagen';
}
function explainDictationStatus(message, platform = process.platform) {
  if (message === 'Mikrofon gesperrt') {
    if (platform === 'darwin') return 'Kein Mikrofonzugriff — Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon';
    if (platform === 'win32') return 'Kein Mikrofonzugriff — Windows-Einstellungen → Datenschutz & Sicherheit → Mikrofon';
    return 'Kein Mikrofonzugriff — Mikrofon und Zugriffsrechte prüfen';
  }
  const explanations = {
    'Kein Mikrofonsignal': 'Kein Mikrofonsignal — Mikrofon und Eingabegerät prüfen',
    'Groq-Schlüssel ungültig': 'Ungültiger Groq-Schlüssel — bitte in den Einstellungen prüfen',
    'Keine Verbindung': 'Keine Verbindung — Netzwerk prüfen und erneut versuchen',
    'Groq-Limit erreicht': 'Groq-Limit erreicht — bitte später erneut versuchen',
    'Aufnahme neu gestartet': 'Aufnahmefenster neu gestartet — bitte erneut versuchen',
    'Kopiert – ⌘V drücken': 'In Zwischenablage kopiert — mit Cmd+V einfügen; ggf. Bedienungshilfen für Paply erlauben',
    'Kopiert – Strg+V drücken': 'In Zwischenablage kopiert — mit Ctrl+V im gewünschten Fenster einfügen',
  };
  return explanations[message] || message;
}
async function readResponse(url, options, timeoutMs, fetchImpl = fetch) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(url, { ...options, signal: controller.signal });
    const body = await response.text();
    return { ok: response.ok, status: response.status, body };
  } finally { clearTimeout(timer); }
}
function sameShortcut(first, second, platform = process.platform) {
  if (!first || !second) return false;
  const normalize = shortcut => {
    const parts = shortcut.toUpperCase().split('+');
    const key = parts.pop();
    const aliases = { CMD: 'COMMAND', META: 'COMMAND', OPTION: 'ALT', CONTROL: 'CTRL',
      COMMANDORCONTROL: platform === 'darwin' ? 'COMMAND' : 'CTRL',
      CMDORCTRL: platform === 'darwin' ? 'COMMAND' : 'CTRL' };
    return [...parts.map(part => aliases[part] || part).sort(), key].join('+');
  };
  return normalize(first) === normalize(second);
}

// Keep the old registration live until the replacement is known to work.
function replaceShortcut(old, next, { register, unregister, activate }) {
  if (old === next) return true;
  try {
    if (!register(next)) return false;
    activate(next);
  } catch {
    try { unregister(next); } catch { /* best effort */ }
    try { if (old) activate(old); } catch { /* old registration is still live */ }
    return false;
  }
  try { if (old) unregister(old); }
  catch {
    try { unregister(next); if (old) activate(old); } catch { /* best effort */ }
    return false;
  }
  return true;
}
async function ensureGlobeReady(manager, timeoutMs = 2000) {
  if (manager.isRunning) return true;
  try {
    if (!manager._resolveBinary()) return false;
    manager.start();
    const child = manager.process;
    if (!child) return false;
    return await new Promise(resolve => {
      const finish = ok => {
        clearTimeout(timer);
        child.removeListener('spawn', ready);
        child.removeListener('error', failed);
        child.removeListener('exit', failed);
        if (!ok) manager.stop();
        resolve(ok);
      };
      const ready = () => finish(true);
      const failed = () => finish(false);
      const timer = setTimeout(failed, timeoutMs);
      child.once('spawn', ready); child.once('error', failed); child.once('exit', failed);
    });
  } catch { manager.stop(); return false; }
}
module.exports = { polishTokenBudget, completePolish, friendlyError, explainDictationStatus, readResponse, replaceShortcut, ensureGlobeReady, sameShortcut };
