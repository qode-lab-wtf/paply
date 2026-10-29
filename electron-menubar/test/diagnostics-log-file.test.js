// Diagnose-Protokoll: echte Dateien in einem Temp-Ordner, Konsole ist ein Double.
import { afterEach, describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { installLogFile, redact } from '../diagnostics/log-file.js';

const cleanups = [];
afterEach(async () => { while (cleanups.length) await cleanups.pop()(); });

function setup(options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-log-'));
  const directory = path.join(root, 'logs');
  const target = { log: vi.fn(), warn: vi.fn(), error: vi.fn() };
  const originals = { ...target };
  const log = installLogFile({ directory, console: target, now: () => new Date('2026-10-28T09:15:00.000Z'), ...options });
  cleanups.push(async () => { await log.restore(); fs.rmSync(root, { recursive: true, force: true }); });
  return { root, directory, target, originals, log, read: file => fs.readFileSync(file || log.path, 'utf8') };
}

describe('Diagnose-Protokoll', () => {
  it('schreibt Zeilen mit Zeitstempel und Stufe und behält die Konsolenausgabe', async () => {
    const { target, originals, log, read, directory } = setup();
    expect(log.path).toBe(path.join(directory, 'paply.log'));
    target.log('Version:', '1.15.1', { ok: true });
    target.warn('[PTT] Achtung %d', 3);
    target.error('Fehler:', new Error('kaputt'));
    expect(originals.log).toHaveBeenCalledWith('Version:', '1.15.1', { ok: true });
    expect(originals.warn).toHaveBeenCalledWith('[PTT] Achtung %d', 3);
    expect(originals.error).toHaveBeenCalledWith('Fehler:', expect.any(Error));
    await log.restore();
    const lines = read().split('\n');
    expect(lines[0]).toBe("2026-10-28T09:15:00.000Z [INFO] Version: 1.15.1 { ok: true }");
    expect(lines[1]).toBe('2026-10-28T09:15:00.000Z [WARN] [PTT] Achtung 3');
    expect(lines[2]).toBe('2026-10-28T09:15:00.000Z [ERROR] Fehler: Error: kaputt');
    expect(read()).toContain('at '); // Stacktrace bleibt erhalten
    expect(target.log).toBe(originals.log); // restore() hängt die Konsole wieder ab
  });

  it('hängt an eine bestehende Datei an', async () => {
    const first = setup();
    first.target.log('erste Sitzung');
    await first.log.restore();
    const target = { log: vi.fn() };
    const second = installLogFile({ directory: first.directory, console: target });
    target.log('zweite Sitzung');
    await second.restore();
    expect(first.read()).toMatch(/erste Sitzung\n.*zweite Sitzung\n$/);
  });

  it('rotiert beim Start, wenn die Datei zu groß ist', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-log-'));
    cleanups.push(() => fs.rmSync(root, { recursive: true, force: true }));
    fs.writeFileSync(path.join(root, 'paply.log'), 'x'.repeat(2000));
    fs.writeFileSync(path.join(root, 'paply.old.log'), 'ganz alt');
    const target = { log: vi.fn() };
    const log = installLogFile({ directory: root, console: target, maxBytes: 1000 });
    target.log('neu');
    await log.restore();
    expect(fs.readFileSync(log.oldPath, 'utf8')).toBe('x'.repeat(2000));
    expect(fs.readFileSync(log.path, 'utf8')).toMatch(/\[INFO\] neu\n$/);
    expect(fs.readdirSync(root).sort()).toEqual(['paply.log', 'paply.old.log']);
  });

  it('rotiert während des Laufs an der Grenze und behält genau eine alte Datei', async () => {
    const { target, log, read } = setup({ maxBytes: 400 });
    // 64 Byte je Zeile → 6 Zeilen je Datei: 0–5, 6–11, 12–17, 18–23, 24–29.
    for (let i = 0; i < 30; i++) target.log(`Eintrag ${String(i).padStart(2, '0')} ${'-'.repeat(20)}`);
    await log.restore();
    await vi.waitFor(() => expect(read(log.oldPath)).toContain('Eintrag 23'));
    const current = read(), old = read(log.oldPath);
    expect(Buffer.byteLength(current)).toBeLessThanOrEqual(400);
    expect(Buffer.byteLength(old)).toBeLessThanOrEqual(400);
    expect(current.match(/Eintrag \d+/g)).toEqual(['24', '25', '26', '27', '28', '29'].map(n => `Eintrag ${n}`));
    expect(old.match(/Eintrag \d+/g)).toEqual(['18', '19', '20', '21', '22', '23'].map(n => `Eintrag ${n}`));
    expect(fs.readdirSync(path.dirname(log.path)).sort()).toEqual(['paply.log', 'paply.old.log']);
  });

  it('schwärzt Groq-, Gemini- und OpenAI-Schlüssel sowie Bearer-Token', async () => {
    const { target, originals, log, read } = setup();
    const groq = `gsk_${'A1b2'.repeat(13)}`;
    const gemini = `AIza${'Sy_x-9'.repeat(6)}`;
    const openai = `sk-proj-${'Zz9_'.repeat(8)}`;
    target.error('Antwort', { headers: { Authorization: `Bearer ${groq}` }, url: `https://x.invalid/v1?key=${gemini}` });
    target.log(`Schlüssel ${openai} und`, { groqApiKey: 'nur-ein-platzhalter', geminiApiKey: gemini });
    await log.restore();
    const text = read();
    for (const secret of [groq, gemini, openai, 'nur-ein-platzhalter', groq.slice(4, 20), gemini.slice(4, 20)]) expect(text).not.toContain(secret);
    expect(text).toContain('Bearer ***');
    expect(text).toContain('key=AIza***');
    expect(text).toContain('Schlüssel sk-*** und');
    expect(text).toContain("groqApiKey: '***'");
    // Die Konsole selbst bleibt unverändert (nur die Datei wird geschwärzt).
    expect(originals.log.mock.calls[0][0]).toContain(openai);
  });

  it('lässt normale Wörter mit ähnlichen Mustern stehen', () => {
    expect(redact('task-1234567890abcdefgh disk-sk-x Groq Key: Set API Key fehlt')).toBe('task-1234567890abcdefgh disk-sk-x Groq Key: Set API Key fehlt');
  });

  it('kürzt riesige Einträge und übersteht nicht darstellbare Werte', async () => {
    const { target, log, read } = setup();
    target.log('a'.repeat(20000));
    const hostile = new Proxy({}, { get() { throw new Error('nein'); }, ownKeys() { throw new Error('nein'); } });
    expect(() => target.log('feindlich', hostile)).not.toThrow();
    await log.restore();
    const [huge] = read().split('\n');
    expect(huge.length).toBeLessThan(8200);
    expect(huge).toContain('[gekürzt, 20000 Zeichen]');
  });

  it('wirft nie, wenn der Ordner nicht beschreibbar ist, und lässt die Konsole unangetastet', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-log-'));
    cleanups.push(() => fs.rmSync(root, { recursive: true, force: true }));
    const blocker = path.join(root, 'datei');
    fs.writeFileSync(blocker, ''); // eine Datei, wo der Ordner hin soll → mkdir scheitert
    const target = { log: vi.fn(), error: vi.fn() };
    const original = target.log;
    let log;
    expect(() => { log = installLogFile({ directory: path.join(blocker, 'logs'), console: target }); }).not.toThrow();
    expect(log.enabled).toBe(false);
    expect(target.log).toBe(original);
    expect(() => target.log('läuft weiter')).not.toThrow();
    expect(original).toHaveBeenCalledWith('läuft weiter');
  });

  it('schaltet sich bei Schreibfehlern still ab, die Konsole läuft weiter', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-log-'));
    cleanups.push(() => fs.rmSync(root, { recursive: true, force: true }));
    // Platte voll o. Ä.: Der Stream meldet den Fehler asynchron.
    const failing = { ...fs, createWriteStream: (file, options) => {
      const stream = fs.createWriteStream(file, options);
      setImmediate(() => stream.destroy(new Error('ENOSPC')));
      return stream;
    } };
    const target = { log: vi.fn() };
    const original = target.log;
    const log = installLogFile({ directory: root, console: target, fs: failing });
    expect(log.enabled).toBe(true);
    await vi.waitFor(() => expect(log.enabled).toBe(false));
    expect(() => target.log('noch da')).not.toThrow();
    expect(original).toHaveBeenCalledWith('noch da');
    await log.restore();
  });

  it('bleibt aus, wenn die Datei selbst nicht zu öffnen ist', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-log-'));
    cleanups.push(() => fs.rmSync(root, { recursive: true, force: true }));
    fs.mkdirSync(path.join(root, 'paply.log')); // Ordner statt Datei
    const target = { log: vi.fn() };
    const original = target.log;
    const log = installLogFile({ directory: root, console: target });
    expect(log.enabled).toBe(false);
    expect(target.log).toBe(original);
  });

  it('schreibt unbehandelte Fehler sofort mit, ohne Electrons Verhalten zu ändern', async () => {
    const proc = new EventEmitter();
    const { log, read } = setup({ process: proc });
    expect(proc.listenerCount('uncaughtException')).toBe(0);
    proc.emit('uncaughtExceptionMonitor', new Error(`weg mit gsk_${'q'.repeat(52)}`), 'uncaughtException');
    expect(read()).toMatch(/\[ERROR\] \[Absturz\] uncaughtException: Error: weg mit gsk_\*\*\*/);
    await log.restore();
    expect(proc.listenerCount('uncaughtExceptionMonitor')).toBe(0);
  });
});
