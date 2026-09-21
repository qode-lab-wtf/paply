import { describe, it, expect } from 'vitest';
const { uploadFile, deleteFile } = require('./gemini-files.js');

function makeFetch(log, { startStatus = 200, uploadStatus = 200, states = ['ACTIVE'] } = {}) {
  let polls = 0;
  return async (url, opts = {}) => {
    const u = String(url);
    log.push({ url: u, method: opts.method || 'GET', headers: opts.headers || {}, bodyLen: opts.body ? opts.body.length : 0 });
    if (u.endsWith('/upload/v1beta/files')) {
      return { ok: startStatus === 200, status: startStatus, headers: { get: (h) => (h.toLowerCase() === 'x-goog-upload-url' ? 'https://upload.example/session-1' : null) }, text: async () => 'err' };
    }
    if (u === 'https://upload.example/session-1') {
      return { ok: uploadStatus === 200, status: uploadStatus, json: async () => ({ file: { name: 'files/abc', uri: 'https://generativelanguage.googleapis.com/v1beta/files/abc', state: states[0] } }), text: async () => 'err' };
    }
    if (u.endsWith('/v1beta/files/abc') && (opts.method || 'GET') === 'GET') {
      polls++;
      return { ok: true, status: 200, json: async () => ({ name: 'files/abc', uri: 'uri-abc', state: states[Math.min(polls, states.length - 1)] }) };
    }
    if (u.endsWith('/v1beta/files/abc') && opts.method === 'DELETE') return { ok: true, status: 200 };
    return { ok: false, status: 404, text: async () => 'nf' };
  };
}

describe('gemini-files uploadFile', () => {
  it('führt den resumable Handshake aus (start → upload/finalize) und liefert uri', async () => {
    const log = [];
    const buf = Buffer.alloc(1000, 1);
    const f = await uploadFile({ apiKey: 'k', buffer: buf, displayName: 'mic-0', fetchImpl: makeFetch(log) });
    expect(f.uri).toContain('files/abc');
    expect(f.state).toBe('ACTIVE');
    expect(log[0].headers['X-Goog-Upload-Protocol']).toBe('resumable');
    expect(log[0].headers['X-Goog-Upload-Command']).toBe('start');
    expect(log[0].headers['X-Goog-Upload-Header-Content-Length']).toBe('1000');
    expect(log[0].headers['x-goog-api-key']).toBe('k');
    expect(log[1].url).toBe('https://upload.example/session-1');
    expect(log[1].headers['X-Goog-Upload-Command']).toBe('upload, finalize');
    expect(log[1].headers['X-Goog-Upload-Offset']).toBe('0');
    expect(log[1].bodyLen).toBe(1000);
  });

  it('pollt bis ACTIVE, wenn die Datei zunächst PROCESSING ist', async () => {
    const log = [];
    const f = await uploadFile({ apiKey: 'k', buffer: Buffer.alloc(10), fetchImpl: makeFetch(log, { states: ['PROCESSING', 'PROCESSING', 'ACTIVE'] }), sleep: async () => {} });
    expect(f.state).toBe('ACTIVE');
    expect(log.filter((l) => l.method === 'GET').length).toBe(2);
  });

  it('429 beim Start → Fehler mit code rate_limit', async () => {
    await expect(uploadFile({ apiKey: 'k', buffer: Buffer.alloc(10), fetchImpl: makeFetch([], { startStatus: 429 }) })).rejects.toMatchObject({ code: 'rate_limit' });
  });

  it('deleteFile ruft DELETE und wirft nie', async () => {
    const log = [];
    expect(await deleteFile({ apiKey: 'k', name: 'files/abc', fetchImpl: makeFetch(log) })).toBe(true);
    expect(log[0].method).toBe('DELETE');
    expect(await deleteFile({ apiKey: 'k', name: 'files/abc', fetchImpl: async () => { throw new Error('net'); } })).toBe(false);
  });
});
