import { describe, it, expect, vi } from 'vitest';
import { primer, looksLikeEcho, cutEchoes, echoCheck } from '../dictation/whisper-prompt';
import { makeMain, speech } from './helpers/dictation-main';

const example = primer(['de', 'en']);
const spoken = 'Bei der Rechnung für die Miete gab es eine Unstimmigkeit, die Nebenkosten sind doppelt aufgeführt. Ich habe die Hausverwaltung angeschrieben, aber noch keine Antwort bekommen.';
const echoed = 'Bei der Rechnung für die Miete gab es eine Unstimmigkeit, die Nebenkosten sind doppelt aufgeführt. Ich habe die Hausver Ich schreibe dir später, see you tomorrow.';
const long = { ...speech, durationMs: 70000, measuredMs: 70000, speechMs: 60000 };
const reply = (text, extra = {}) => ({ ok: true, text: async () => JSON.stringify({ language: 'German', text, segments: [{ text, start: 0, end: 60, avg_logprob: -0.1 }], ...extra }) });

describe('Echo-Erkennung', () => {
  it('erkennt drei Wörter am Stück aus dem Beispielsatz, egal wo und wie geschrieben', () => {
    expect(looksLikeEcho({ text: echoed }, { example })).toBe(true);
    expect(looksLikeEcho({ text: 'Okay, ICH SCHREIBE DIR noch was.' }, { example })).toBe(true);
    expect(looksLikeEcho({ text: spoken }, { example })).toBe(false);
    expect(looksLikeEcho({ text: 'Ich schreibe dir.' }, { example: '' })).toBe(false);
  });
  it('erkennt Begriffslisten-Echo am Ende, aber keinen einzelnen gesprochenen Begriff', () => {
    const vocabulary = 'Paply, Tailscale, Supabase, Kubernetes, Vitest, Groq';
    expect(looksLikeEcho({ text: 'Das Angebot geht raus. Paply, Tailscale, Supabase, Kubernetes, Vitest, Groq, Groq.' }, { vocabulary })).toBe(true);
    expect(looksLikeEcho({ text: 'Ich rufe Paply morgen an.' }, { vocabulary })).toBe(false);
    expect(looksLikeEcho({ text: 'Groq.' }, { vocabulary })).toBe(false);
  });
  it('erkennt bei Gedanken ein Segment, das nur das Ende des Vorstücks wiederholt', () => {
    const previousText = 'Wir sollten das Dach im Frühjahr neu decken lassen.';
    expect(looksLikeEcho({ text: 'neu decken lassen. Und dann', segments: [{ text: 'neu decken lassen.' }, { text: 'Und dann' }] }, { previousText })).toBe(true);
    expect(looksLikeEcho({ text: 'Das Dach ist alt.', segments: [{ text: 'Das Dach ist alt.' }] }, { previousText })).toBe(false);
  });
  it('Rückfall streicht nur die Echo-Wörter, nicht das ganze lange Segment', () => {
    const out = cutEchoes({ text: echoed, segments: [{ text: echoed, start: 30, end: 64 }] }, { example });
    expect(out.text).toBe('Bei der Rechnung für die Miete gab es eine Unstimmigkeit, die Nebenkosten sind doppelt aufgeführt. Ich habe die Hausver');
    expect(out.segments).toHaveLength(1);
    const list = cutEchoes({ text: 'Das Angebot geht raus. Paply, Tailscale, Supabase, Groq.' }, { vocabulary: 'Paply, Tailscale, Supabase, Groq' });
    expect(list.text).toBe('Das Angebot geht raus.');
  });
});

describe('Echo-Gegenprobe', () => {
  it('ohne Echo keine zweite Anfrage', async () => {
    const request = vi.fn(), diagnose = vi.fn();
    const first = { text: spoken, language: 'de' };
    expect(await echoCheck(first, request, { example, firstMs: 100, diagnose })).toBe(first);
    expect(request).not.toHaveBeenCalled(); expect(diagnose).toHaveBeenCalledWith(0, 0);
  });
  it('zweiter Lauf ohne Prompt mit entschiedener Sprache gewinnt', async () => {
    const request = vi.fn(async () => ({ text: spoken, language: 'german' })), diagnose = vi.fn();
    const out = await echoCheck({ text: echoed, language: 'de' }, request, { example, firstMs: 100, diagnose });
    expect(request).toHaveBeenCalledWith('de', '');
    expect(out.text).toBe(spoken); expect(out.language).toBe('de'); expect(diagnose).toHaveBeenCalledWith(1, 1);
  });
  it('wirklich gesprochener Beispielsatz bleibt stehen, weil er auch im zweiten Lauf steht', async () => {
    const said = 'Schreib ihm: Ich schreibe dir später, see you tomorrow.';
    const out = await echoCheck({ text: said, language: 'de' }, async () => ({ text: said }), { example, firstMs: 100, diagnose: () => {} });
    expect(out.text).toBe(said);
  });
  it('scheitert der zweite Lauf, kommt das erste Ergebnis ohne Echo', async () => {
    const diagnose = vi.fn();
    const out = await echoCheck({ text: echoed, language: 'de' }, async () => { throw new Error('500'); }, { example, firstMs: 100, diagnose });
    expect(out.text).toMatch(/Hausver$/); expect(out.echoRemoved).toBe(true); expect(diagnose).toHaveBeenCalledWith(1, 0);
  });
  it('wartet höchstens zweimal die erste Anfrage plus 5 Sekunden', async () => {
    vi.useFakeTimers();
    try {
      const pending = echoCheck({ text: echoed, language: 'de' }, () => new Promise(() => {}), { example, firstMs: 1000, diagnose: () => {} });
      await vi.advanceTimersByTimeAsync(7000);
      expect((await pending).text).toMatch(/Hausver$/);
    } finally { vi.useRealTimers(); }
  });
  it('Abbruch wird weitergereicht', async () => {
    const abort = new AbortController();
    const request = async () => { abort.abort(); throw new Error('abgebrochen'); };
    await expect(echoCheck({ text: echoed, language: 'de' }, request, { example, firstMs: 100, signal: abort.signal, diagnose: () => {} })).rejects.toThrow();
  });
});

describe('Echo-Gegenprobe im Diktat', () => {
  it('langes Diktat mit viel Sprechzeit: zweiter Lauf ohne Prompt liefert den Schluss', async () => {
    const m = makeMain('darwin', { enablePolish: false, autopaste: false });
    m.context.fetch.mockResolvedValueOnce(reply(echoed)).mockResolvedValueOnce(reply(spoken));
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    try {
      await m.context.processAudioData(Buffer.from('audio'), false, long);
      expect(m.context.fetch).toHaveBeenCalledTimes(2);
      const second = m.context.fetch.mock.calls[1][1].body;
      expect(second.has('prompt')).toBe(false); expect(second.get('language')).toBe('de');
      expect(m.context.addToHistory).toHaveBeenCalledWith(expect.objectContaining({ transcript: spoken }));
      expect(log).toHaveBeenCalledWith('[Echo]', 1, 1);
    } finally { log.mockRestore(); m.dispose(); }
  });
  it('Begriffslisten-Echo löst die Gegenprobe aus', async () => {
    const vocabulary = 'Paply, Tailscale, Supabase, Kubernetes, Vitest, Groq';
    const m = makeMain('darwin', { enablePolish: false, autopaste: false, customVocabulary: vocabulary });
    m.context.fetch.mockResolvedValueOnce(reply(spoken + ' Paply, Tailscale, Supabase, Kubernetes, Vitest, Groq, Groq.')).mockResolvedValueOnce(reply(spoken));
    try {
      await m.context.processAudioData(Buffer.from('audio'), false, long);
      expect(m.context.fetch.mock.calls[1][1].body.has('prompt')).toBe(false);
      expect(m.context.addToHistory).toHaveBeenCalledWith(expect.objectContaining({ transcript: spoken }));
    } finally { m.dispose(); }
  });
  it('scheitert der zweite Lauf, kommt das Diktat trotzdem', async () => {
    const m = makeMain('darwin', { enablePolish: false, autopaste: false });
    m.context.fetch.mockResolvedValueOnce(reply(echoed)).mockResolvedValueOnce({ ok: false, status: 400, text: async () => '{}' });
    try {
      await m.context.processAudioData(Buffer.from('audio'), false, long);
      expect(m.context.fetch).toHaveBeenCalledTimes(2);
      expect(m.context.addToHistory).toHaveBeenCalledWith(expect.objectContaining({ transcript: expect.stringMatching(/Hausver$/) }));
    } finally { m.dispose(); }
  });
  it('ohne Echo genau eine Anfrage', async () => {
    const m = makeMain('darwin', { enablePolish: false, autopaste: false });
    m.context.fetch.mockResolvedValue(reply(spoken));
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    try {
      await m.context.processAudioData(Buffer.from('audio'), false, long);
      expect(m.context.fetch).toHaveBeenCalledTimes(1);
      expect(log).toHaveBeenCalledWith('[Echo]', 0, 0);
    } finally { log.mockRestore(); m.dispose(); }
  });
});

it('Gedanken: Echo-Gegenprobe ohne Prompt, Sprache fest', async () => {
  const { createGroq } = await import('../notes/groq');
  const bodies = [];
  const groq = createGroq({ getKey: () => 'test', ledger: { reserve: () => 1, settle: () => {} }, getTranscriptionSettings: () => ({ language: 'de', systemLanguages: ['de-DE'] }),
    fetchImpl: async (_url, { body }) => { bodies.push(body); const text = bodies.length === 1 ? echoed : spoken; return { ok: true, json: async () => ({ text, language: 'German', segments: [{ text, start: 0, end: 60, avg_logprob: -0.1 }] }) }; } });
  const out = await groq.transcribe(Buffer.alloc(64), 70, undefined, '', { previousText: 'Vorher.', voiceActivity: { speechMs: 60000 } });
  expect(bodies).toHaveLength(2);
  expect(bodies[0].get('prompt')).toContain('see you tomorrow');
  expect(bodies[1].has('prompt')).toBe(false); expect(bodies[1].get('language')).toBe('de');
  expect(out.text).toBe(spoken);
});

describe('Kaum Stimme: kein Prompt', () => {
  // Echte Messwerte des Teststücks „Atmen“ (5 s, kein Wort).
  const quiet = { durationMs: 5000, measuredMs: 5000, speechMs: 100, peakDbfs: -38.7, floorDbfs: -54.4, maxGapMs: 50 };
  const english = { ok: true, text: async () => JSON.stringify({ language: 'English', text: "Thank you for watching!", segments: [{ text: "Thank you for watching!", start: 0, end: 4, avg_logprob: -0.3 }] }) };
  it('Diktat: auch die Sprach-Gegenprobe schickt keinen Prompt', async () => {
    const m = makeMain('darwin', { enablePolish: false, autopaste: false, customVocabulary: 'Kubernetes' });
    m.context.fetch.mockResolvedValue(english);
    try {
      await m.context.processAudioData(Buffer.from('audio'), false, quiet);
      expect(m.context.fetch.mock.calls.length).toBeGreaterThanOrEqual(2);
      expect(m.context.fetch.mock.calls[1][1].body.get('language')).toBe('de');
      for (const [, { body }] of m.context.fetch.mock.calls) expect(body.has('prompt')).toBe(false);
    } finally { m.dispose(); }
  });
  it.each([['normale Stimme', long], ['fehlende Messung', undefined]])('Diktat mit %s: Prompt wie bisher', async (_name, meta) => {
    const m = makeMain('darwin', { enablePolish: false, autopaste: false });
    m.context.fetch.mockResolvedValue(reply(spoken));
    try {
      await m.context.processAudioData(Buffer.from('audio'), false, meta);
      expect(m.context.fetch.mock.calls[0][1].body.get('prompt')).toBe(example);
    } finally { m.dispose(); }
  });
  it.each([[quiet, false], [{ ...quiet, speechMs: 4000, peakDbfs: -12 }, true], [undefined, true]])('Gedanken: Messung %j → Prompt %s', async (voiceActivity, withPrompt) => {
    const { createGroq } = await import('../notes/groq');
    const bodies = [];
    const groq = createGroq({ getKey: () => 'test', ledger: { reserve: () => 1, settle: () => {} }, getTranscriptionSettings: () => ({ language: 'de', systemLanguages: ['de-DE'] }),
      fetchImpl: async (_url, { body }) => { bodies.push(body); return { ok: true, json: async () => ({ text: 'Hallo.', language: 'German', segments: [{ text: 'Hallo.', start: 0, end: 1, avg_logprob: -0.1 }] }) }; } });
    await groq.transcribe(Buffer.alloc(64), 5, undefined, 'Kubernetes', { previousText: 'Vorher.', voiceActivity });
    expect(bodies[0].has('prompt')).toBe(withPrompt);
  });
});
