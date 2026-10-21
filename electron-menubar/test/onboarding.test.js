import { describe, it, expect, vi } from 'vitest';
const { validateGroqKey, saveGroqKey, microphonePermission } = require('../app-setup');

describe('Ersteinrichtung: Groq-Prüfung', () => {
  it('prüft Modelle im Main mit Bearer-Header, ohne Weiterleitungen', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: true });
    expect(await validateGroqKey(' example-key ', { fetchImpl })).toEqual({ status: 'valid' });
    expect(fetchImpl).toHaveBeenCalledWith('https://api.groq.com/openai/v1/models', expect.objectContaining({
      method: 'GET', headers: { Authorization: 'Bearer example-key' }, redirect: 'error', signal: expect.any(AbortSignal),
    }));
  });
  it.each([401, 403])('erkennt HTTP %s als ungültigen Key', async status => {
    expect(await validateGroqKey('test', { fetchImpl: async () => ({ ok: false, status }) })).toEqual({ status: 'invalid' });
  });
  it.each([429, 500, 503])('unterscheidet HTTP %s von falschen Keys', async status => {
    expect(await validateGroqKey('test', { fetchImpl: async () => ({ ok: false, status }) })).toEqual({ status: 'unavailable' });
  });
  it('meldet Netzwerkfehler ohne Fehlerobjekt/Key zurück', async () => {
    const result = await validateGroqKey('private-example', { fetchImpl: async () => { throw new Error('private-example'); } });
    expect(result).toEqual({ status: 'unavailable' });
  });
  it('bricht nach Timeout ab', async () => {
    const fetchImpl = (_url, { signal }) => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => reject(new Error('Abgebrochen')));
    });
    expect(await validateGroqKey('test', { fetchImpl, timeoutMs: 5 })).toEqual({ status: 'unavailable' });
  });
  it.each(['', null, '\nkey', 'x'.repeat(4097)])('lehnt ungeeignete Eingaben vor dem Request ab', async key => {
    const fetchImpl = vi.fn();
    expect(await validateGroqKey(key, { fetchImpl })).toEqual({ status: 'invalid' });
    expect(fetchImpl).not.toHaveBeenCalled();
  });
  it('speichert ausschließlich gültige oder ausdrücklich bestätigte Keys', async () => {
    const store = { set: vi.fn() };
    const invalid = async () => ({ ok: false, status: 401 });
    expect((await saveGroqKey(store, 'test', { fetchImpl: invalid })).saved).toBe(false);
    expect(store.set).not.toHaveBeenCalled();
    expect((await saveGroqKey(store, 'test', { fetchImpl: invalid, saveAnyway: true })).saved).toBe(true);
    expect(store.set).toHaveBeenCalledWith('groqApiKey', 'test');
    store.set.mockClear();
    expect((await saveGroqKey(store, ' valid ', { fetchImpl: async () => ({ ok: true }) })).saved).toBe(true);
    expect(store.set).toHaveBeenCalledWith('groqApiKey', 'valid');
    store.set.mockClear();
    expect((await saveGroqKey(store, '', { fetchImpl: invalid, saveAnyway: true })).saved).toBe(false);
    expect(store.set).not.toHaveBeenCalled();
  });
});

describe('Mikrofonberechtigungen', () => {
  function preferences(status) {
    let current = status;
    return {
      getMediaAccessStatus: vi.fn(() => current),
      askForMediaAccess: vi.fn(async () => { current = 'granted'; return true; }),
      isTrustedAccessibilityClient: vi.fn(() => false),
    };
  }
  it('fragt auf macOS erst auf ausdrücklichen Wunsch und nur bei unbestimmtem Status', async () => {
    const api = preferences('not-determined');
    expect((await microphonePermission(api, 'darwin')).status).toBe('not-determined');
    expect(api.askForMediaAccess).not.toHaveBeenCalled();
    expect(await microphonePermission(api, 'darwin', true)).toEqual({ status: 'granted', accessibilityRequired: true, accessibilityGranted: false });
    expect(api.askForMediaAccess).toHaveBeenCalledWith('microphone');
    expect(api.isTrustedAccessibilityClient).toHaveBeenCalledWith(false);
  });
  it('fragt bei gesperrtem Mikrofon nicht wiederholt', async () => {
    const api = preferences('denied');
    expect((await microphonePermission(api, 'darwin', true)).status).toBe('denied');
    expect(api.askForMediaAccess).not.toHaveBeenCalled();
  });
  it('verwendet Windows-Status ohne macOS-Berechtigungs-APIs', async () => {
    const api = preferences('denied');
    expect(await microphonePermission(api, 'win32', true)).toEqual({ status: 'denied', accessibilityRequired: false, accessibilityGranted: true });
    expect(api.askForMediaAccess).not.toHaveBeenCalled();
    expect(api.isTrustedAccessibilityClient).not.toHaveBeenCalled();
  });
});
