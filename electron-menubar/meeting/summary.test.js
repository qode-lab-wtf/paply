import { describe, it, expect } from 'vitest';
const { getMeetingSummaryPrompt, parseSummaryJson, generateMeetingSummary, SUMMARY_RESPONSE_SCHEMA } = require('./summary.js');

describe('summary v2', () => {
  it('Prompt enthält alle Rubriken, die Regeln und das Transkript', () => {
    const p = getMeetingSummaryPrompt('Sprecher 1: Hallo', 'de');
    for (const k of ['titel', 'kurzfassung', 'themen', 'entscheidungen', 'offeneFragen', 'todos']) expect(p).toContain(`"${k}"`);
    expect(p).toContain('Nichts erfinden');
    expect(p).toContain('Sprecher 1: Hallo');
    expect(SUMMARY_RESPONSE_SCHEMA.required).toContain('todos');
  });

  it('parseSummaryJson liest JSON aus ```json-Fences und füllt Defaults (erledigt:false, null)', () => {
    const raw = '```json\n{"titel":"T","kurzfassung":"X","themen":[{"ueberschrift":"A","inhalt":"B"}],"entscheidungen":[{"text":"E"}],"offeneFragen":["F"],"todos":[{"text":"Aufgabe","verantwortlich":"","frist":"morgen"}]}\n```';
    const s = parseSummaryJson(raw);
    expect(s.schema).toBe(2);
    expect(s.titel).toBe('T');
    expect(s.kurzfassung).toBe('X');
    expect(s.themen).toEqual([{ ueberschrift: 'A', inhalt: 'B' }]);
    expect(s.entscheidungen).toEqual([{ text: 'E', begruendung: '' }]);
    expect(s.todos).toEqual([{ text: 'Aufgabe', verantwortlich: null, frist: 'morgen', erledigt: false }]);
    expect(s.offeneFragen).toEqual(['F']);
  });

  it('parseSummaryJson toleriert kaputtes JSON (leerer Bericht statt Absturz)', () => {
    const s = parseSummaryJson('kein json');
    expect(s.themen).toEqual([]);
    expect(s.kurzfassung).toBe('');
  });

  it('generateMeetingSummary nutzt Gemini zuerst (mit responseSchema), Groq als Fallback', async () => {
    const calls = [];
    const fakeFetch = async (url, opts) => {
      calls.push(String(url));
      if (String(url).includes('generativelanguage')) {
        const body = JSON.parse(opts.body);
        expect(body.generationConfig.responseSchema).toBeTruthy();
        return { ok: true, json: async () => ({ candidates: [{ content: { parts: [{ text: '{"titel":"T","kurzfassung":"Z","themen":[],"entscheidungen":[],"offeneFragen":[],"todos":[]}' }] } }] }) };
      }
      return { ok: true, json: async () => ({ choices: [{ message: { content: '{"kurzfassung":"G","themen":[]}' } }] }) };
    };
    const s = await generateMeetingSummary('T', { groqApiKey: 'k', geminiApiKey: 'g', language: 'de', fetchImpl: fakeFetch });
    expect(s.kurzfassung).toBe('Z');
    expect(s.model).toBe('gemini-flash-latest');
    expect(calls[0]).toContain('generativelanguage');

    // Gemini 429 → Groq
    const fb = async (url) => (String(url).includes('generativelanguage')
      ? { ok: false, status: 429 }
      : { ok: true, json: async () => ({ choices: [{ message: { content: '{"kurzfassung":"G","themen":[],"todos":[]}' } }] }) });
    const s2 = await generateMeetingSummary('T', { groqApiKey: 'k', geminiApiKey: 'g', fetchImpl: fb });
    expect(s2.kurzfassung).toBe('G');
    expect(s2.model).toBe('openai/gpt-oss-120b');
  });

  it('generateMeetingSummary: leere Antwort → Fehler code empty', async () => {
    const fakeFetch = async () => ({ ok: true, json: async () => ({ choices: [{ message: { content: '{}' } }] }) });
    await expect(generateMeetingSummary('T', { apiKey: 'k', fetchImpl: fakeFetch })).rejects.toMatchObject({ code: 'empty' });
  });
});

describe('Berichtssprache nach Regel 6', () => {
  const { reportLanguage } = require('./summary.js');
  it('wählt ab 80 Prozent Sprechzeit die andere Sprache, darunter die Hauptsprache', () => {
    const segments = n => [{ text: 'Hello', language: 'en', tStart: 0, tEnd: n }, { text: 'Hallo', language: 'de', tStart: n, tEnd: 100 }];
    expect(reportLanguage('', 'de', segments(80))).toBe('en');
    expect(reportLanguage('', 'de', segments(79))).toBe('de');
  });
  it('gewichtet ohne Zeiten die Wörter und akzeptiert Sprachangaben der Auswertung', () => {
    expect(reportLanguage('', 'de', [{ text: 'one two three four', language: 'en' }, { text: 'Hallo', language: 'de' }])).toBe('en');
    expect(reportLanguage('Bonjour', 'de', [], 'fr')).toBe('fr');
    expect(reportLanguage('', 'fr')).toBe('fr');
  });
  it('erkennt durchgehend englische und französische Texte ohne Metadaten', () => {
    expect(reportLanguage('We will discuss the project and the plan for our team today.', 'de')).toBe('en');
    expect(reportLanguage('Nous avons un projet et nous sommes avec vous pour le travail demain.', 'de')).toBe('fr');
  });
  it('bleibt bei gemischtem Text in der Hauptsprache und erhält Zitate im Prompt wörtlich', () => {
    const segments = [{ text: 'We will discuss the project and the plan.', tStart: 0, tEnd: 60 }, { text: 'Wir haben heute eine Frage und werden das mit der Gruppe klären.', tStart: 60, tEnd: 100 }];
    expect(reportLanguage('', 'de', segments)).toBe('de');
    const quote = 'Sprecher 1: “On se voit ce soir.”';
    const prompt = getMeetingSummaryPrompt(quote, 'de');
    expect(prompt).toContain(quote); expect(prompt).toContain('Zitate bleiben immer wörtlich');
  });
});
