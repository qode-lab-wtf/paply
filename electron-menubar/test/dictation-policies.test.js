import { afterEach, describe, expect, it, vi } from 'vitest';
import { createDictationJobs } from '../dictation/jobs.js';
import { completePolish, polishTokenBudget, readResponse, replaceShortcut, friendlyError, explainDictationStatus, ensureGlobeReady, sameShortcut, retryAfterMs, transcriptionTimeoutMs } from '../dictation/policies.js';
import { deferred, tick } from './helpers/dictation-main.js';
afterEach(() => vi.useRealTimers());

it('gibt bei Längen-Abbruch immer das Original frei, auch bei scheinbar langer Antwort', () => {
  expect(completePolish({ choices: [{ finish_reason: 'length', message: { content: 'Zu kurz' } }] })).toBeNull();
  expect(completePolish({ choices: [{ finish_reason: 'stop', message: { content: ' Ganzer Text ' } }] })).toBe('Ganzer Text');
  expect(polishTokenBudget('a'.repeat(30000))).toBe(20000);
  expect(polishTokenBudget('a'.repeat(1000000))).toBe(32768);
  expect(polishTokenBudget('kurz')).toBe(4096);
});

it.each([true, false])('Timeout bleibt auch während langsamem Antwort-Body aktiv (HTTP ok=%s)', async ok => {
  vi.useFakeTimers();
  let signal;
  const fetch = vi.fn(async (_url, options) => {
    signal = options.signal;
    return { ok, status: ok ? 200 : 500, text: () => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' })));
    }) };
  });
  const request = readResponse('example', {}, 100, fetch);
  const rejected = expect(request).rejects.toMatchObject({ name: 'AbortError' });
  await tick(); expect(signal.aborted).toBe(false);
  await vi.advanceTimersByTimeAsync(100); await rejected;
  expect(signal.aborted).toBe(true); expect(vi.getTimerCount()).toBe(0);
});

it.each(['success', 'fetch error', 'body error'])('räumt den HTTP-Timer bei %s auf', async outcome => {
  vi.useFakeTimers();
  const fetch = vi.fn(async () => {
    if (outcome === 'fetch error') throw Error('network');
    return { ok: true, status: 200, text: async () => { if (outcome === 'body error') throw Error('body'); return 'ok'; } };
  });
  await readResponse('example', {}, 100, fetch).catch(() => {});
  expect(vi.getTimerCount()).toBe(0);
});

it('überspringt fehlgeschlagene/abgebrochene Aufträge ohne vorherige Aufträge zu überholen', async () => {
  const jobs = createDictationJobs();
  const first = jobs.create('A'); const second = jobs.create('B'); const third = jobs.create('C');
  let thirdReady = false; third.turn.then(() => { thirdReady = true; });
  second.finish(); await tick(); expect(thirdReady).toBe(false);
  first.finish(); await tick(); expect(thirdReady).toBe(true);
  expect(jobs.isCurrent(first)).toBe(false); expect(jobs.isCurrent(third)).toBe(true);
});

it.each(['false', 'throw'])('altes Kürzel bleibt bei Registrierungsergebnis %s aktiv', failure => {
  const active = new Set(['old']);
  const unregister = vi.fn(key => active.delete(key));
  const success = replaceShortcut('old', 'new', {
    register: () => { if (failure === 'throw') throw Error('invalid accelerator'); return false; },
    unregister, activate: vi.fn(),
  });
  expect(success).toBe(false); expect(active.has('old')).toBe(true);
});
it('registriert zuerst das neue Kürzel und entfernt erst danach das alte', () => {
  const calls = [];
  expect(replaceShortcut('old', 'new', { register: key => { calls.push('register ' + key); return true; },
    activate: key => calls.push('activate ' + key), unregister: key => calls.push('unregister ' + key) })).toBe(true);
  expect(calls).toEqual(['register new', 'activate new', 'unregister old']);
});
for (const platform of ['darwin', 'win32']) describe(`Fehlertexte ${platform}`, () => {
  it.each([['401', 'Groq-Schlüssel'], ['429', 'Limit'], ['fetch failed', 'Verbindung'], ['ENOTFOUND', 'Verbindung'], ['NotAllowedError', 'Mikrofon']])('%s ist verständlich', (error, text) => {
    expect(friendlyError(error, platform)).toContain(text);
  });
  it('benennt das plattformgerechte Einstellungsfenster', () => {
    expect(explainDictationStatus(friendlyError('microphone'), platform)).toContain(platform === 'darwin' ? 'Systemeinstellungen → Datenschutz & Sicherheit' : 'Windows-Einstellungen');
  });
});

it.each(['spawn', 'error', 'exit', 'timeout'])('Globe-Wechsel wartet auf Helferstart (%s), bevor altes Kürzel entfernt wird', async event => {
  vi.useFakeTimers();
  const { EventEmitter } = await import('node:events');
  const child = new EventEmitter();
  const manager = { isRunning: false, _resolveBinary: () => 'binary', process: child, start: vi.fn(), stop: vi.fn() };
  const result = ensureGlobeReady(manager, 100);
  if (event === 'timeout') await vi.advanceTimersByTimeAsync(100);
  else child.emit(event);
  expect(await result).toBe(event === 'spawn');
  expect(manager.stop).toHaveBeenCalledTimes(event === 'spawn' ? 0 : 1);
  expect(vi.getTimerCount()).toBe(0);
});

it('liest Retry-After nur als Sekundenangabe und reicht sie durch', async () => {
  expect(retryAfterMs('7')).toBe(7000); expect(retryAfterMs('0.5')).toBe(500);
  expect([null, undefined, '', 'bald', '-1'].map(retryAfterMs)).toEqual([null, null, null, null, null]);
  const headers = { get: name => name === 'retry-after' ? '42' : null };
  expect(await readResponse('example', {}, 100, async () => ({ ok: false, status: 429, headers, text: async () => '' })))
    .toMatchObject({ status: 429, retryAfter: '42' });
  expect((await readResponse('example', {}, 100, async () => ({ ok: true, status: 200, text: async () => '' }))).retryAfter).toBeNull();
});

it('gibt langen Uploads mehr Zeit, kurzen praktisch die bisherigen 60 s', () => {
  expect(transcriptionTimeoutMs(0)).toBe(60000);
  expect(transcriptionTimeoutMs(256000)).toBe(64000);
  expect(transcriptionTimeoutMs(25 * 1024 * 1024)).toBeGreaterThan(450000);
});

it('erklärt zu große Aufnahmen (413) statt „Diktat fehlgeschlagen“', () => {
  expect(friendlyError('413')).toBe('Aufnahme zu lang');
  expect(friendlyError('Request Entity Too Large')).toBe('Aufnahme zu lang');
  expect(explainDictationStatus('Aufnahme zu lang')).toContain('25 MB');
});

it.each(['microphone', '401', '413', '429', 'fetch failed', 'Unknown failure'])('hält Pillenfehler kurz: %s', error => {
  expect(friendlyError(error).length).toBeLessThanOrEqual(28);
  expect(friendlyError(error)).not.toContain('Einstellungen');
});

it.each([
  ['darwin', 'Alt+Command+K', 'Command+Alt+K'],
  ['darwin', 'Option+Cmd+K', 'Command+Alt+K'],
  ['win32', 'Control+Alt+K', 'Ctrl+Alt+K'],
])('erkennt das bereits aktive Kürzel trotz anderer Modifier-Reihenfolge auf %s', (platform, active, captured) => {
  expect(sameShortcut(active, captured, platform)).toBe(true);
  expect(sameShortcut(active, captured.replace('+K', '+X'), platform)).toBe(false);
});
