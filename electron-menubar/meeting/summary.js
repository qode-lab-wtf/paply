// Meeting-Bericht (v2): Prompt, JSON-Schema, Parsing und LLM-Aufruf (Gemini zuerst, Groq als
// Fallback). Der Bericht folgt der Gesprächslänge: Kurzfassung, Themen mit Standpunkten,
// Entscheidungen, offene Fragen, Todos am Ende. Nichts erfinden. CommonJS.

const { chatComplete } = require('./llm-client');
const GROQ_CHAT_URL = 'https://api.groq.com/openai/v1/chat/completions';

const SUMMARY_SCHEMA_VERSION = 2;

/** Gemini-responseSchema für den Bericht (OpenAPI-Teilmenge). Groq bekommt json_object + Prompt. */
const SUMMARY_RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    titel: { type: 'STRING' },
    kurzfassung: { type: 'STRING' },
    themen: { type: 'ARRAY', items: { type: 'OBJECT', properties: { ueberschrift: { type: 'STRING' }, inhalt: { type: 'STRING' } }, required: ['ueberschrift', 'inhalt'] } },
    entscheidungen: { type: 'ARRAY', items: { type: 'OBJECT', properties: { text: { type: 'STRING' }, begruendung: { type: 'STRING' } }, required: ['text'] } },
    offeneFragen: { type: 'ARRAY', items: { type: 'STRING' } },
    todos: { type: 'ARRAY', items: { type: 'OBJECT', properties: { text: { type: 'STRING' }, verantwortlich: { type: 'STRING', nullable: true }, frist: { type: 'STRING', nullable: true } }, required: ['text'] } },
  },
  required: ['titel', 'kurzfassung', 'themen', 'entscheidungen', 'offeneFragen', 'todos'],
};

/**
 * Erzeugt den Prompt für den Bericht.
 * @param {string} transcriptText - Transkript als Text („Sprecher 1: …“ je Zeile, ggf. mit [mm:ss])
 * @param {string} language
 */
function getMeetingSummaryPrompt(transcriptText, language) {
  const lang = language || 'de';
  return `Du bist ein sorgfältiger Protokollant. Unten steht das automatisch erkannte Transkript eines Gesprächs (Sprecher sind neutral nummeriert; der Text kann Erkennungsfehler enthalten). Erstelle daraus einen verständlichen, gut aufgebauten Bericht als JSON.

Antworte NUR mit einem validen JSON-Objekt (kein Markdown, keine Erklärungen) mit exakt diesen Keys:
- "titel": string — kurzer, konkreter Titel des Gesprächs (max. 8 Wörter)
- "kurzfassung": string — 2–4 Sätze: worum ging es, was kam heraus
- "themen": Array von { "ueberschrift": string, "inhalt": string } — die besprochenen Themen in Gesprächsreihenfolge. "inhalt" sind 1–3 Absätze Fließtext (Absätze durch Leerzeile getrennt): Was wurde gesagt, welche Standpunkte gab es (z. B. „Sprecher 2 schlägt vor …, Sprecher 1 hält dagegen …“), welche Zahlen/Namen/Bedingungen wurden genannt. Ausführlichkeit folgt dem Gespräch: kurzes Gespräch → 1–2 Themen mit wenigen Sätzen, langes Gespräch → mehr Themen, mehr Text.
- "entscheidungen": Array von { "text": string, "begruendung": string } — NUR ausdrücklich getroffene Beschlüsse/Vereinbarungen. Ein Vorschlag, eine Frage oder ein Wunsch ist KEINE Entscheidung. Leer lassen, wenn nichts entschieden wurde.
- "offeneFragen": string[] — ungeklärte Fragen und vertagte Punkte
- "todos": Array von { "text": string, "verantwortlich": string|null, "frist": string|null } — konkrete Aufgaben/Folgemaßnahmen, die im Gespräch vereinbart oder angekündigt wurden. "verantwortlich" und "frist" NUR eintragen, wenn sie im Gespräch genannt wurden, sonst null. Sprecherbezeichnungen (z. B. „Sprecher 2“) unverändert übernehmen.

Regeln: Nichts erfinden, keine Zuständigkeiten oder Beschlüsse hinzudichten, Bedingungen („wenn … dann …“) erhalten, Zahlen und Namen exakt übernehmen. Wenn etwas unklar ist, als offene Frage aufführen. Sprache des Berichts: ${lang}.

Transkript:
${transcriptText}`;
}

function _str(v, max = 20000) { return typeof v === 'string' ? v.trim().slice(0, max) : ''; }

/**
 * Parst die rohe LLM-Antwort (v2). Entfernt ```-Fences, füllt fehlende Felder mit Defaults.
 * Todos bekommen `erledigt:false`. Liefert immer ein vollständiges v2-Objekt.
 */
function parseSummaryJson(raw) {
  let text = String(raw || '').trim();
  const fenceMatch = text.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (fenceMatch) text = fenceMatch[1].trim();
  let parsed;
  try { parsed = JSON.parse(text); } catch {
    const a = text.indexOf('{'); const b = text.lastIndexOf('}');
    try { parsed = a >= 0 && b > a ? JSON.parse(text.slice(a, b + 1)) : {}; } catch { parsed = {}; }
  }
  if (!parsed || typeof parsed !== 'object') parsed = {};

  const themen = (Array.isArray(parsed.themen) ? parsed.themen : [])
    .map((t) => (t && typeof t === 'object' ? { ueberschrift: _str(t.ueberschrift, 200), inhalt: _str(t.inhalt) } : { ueberschrift: '', inhalt: _str(t) }))
    .filter((t) => t.inhalt || t.ueberschrift);
  const entscheidungen = (Array.isArray(parsed.entscheidungen) ? parsed.entscheidungen : [])
    .map((e) => (e && typeof e === 'object' ? { text: _str(e.text, 2000), begruendung: _str(e.begruendung, 2000) } : { text: _str(e, 2000), begruendung: '' }))
    .filter((e) => e.text);
  const todos = (Array.isArray(parsed.todos) ? parsed.todos : [])
    .map((t) => (t && typeof t === 'object'
      ? { text: _str(t.text, 2000), verantwortlich: _str(t.verantwortlich, 200) || null, frist: _str(t.frist, 200) || null, erledigt: !!t.erledigt }
      : { text: _str(t, 2000), verantwortlich: null, frist: null, erledigt: false }))
    .filter((t) => t.text);
  const offeneFragen = (Array.isArray(parsed.offeneFragen) ? parsed.offeneFragen : []).map((q) => _str(typeof q === 'object' && q ? q.text : q, 2000)).filter(Boolean);

  return {
    schema: SUMMARY_SCHEMA_VERSION,
    titel: _str(parsed.titel, 120),
    kurzfassung: _str(parsed.kurzfassung || parsed.kurzzusammenfassung),
    themen,
    entscheidungen,
    offeneFragen,
    todos,
    generatedAt: parsed.generatedAt || '',
    model: parsed.model || '',
  };
}

/**
 * Erzeugt den Bericht (Gemini zuerst, dann Groq; Setting llmProvider erzwingt einen Anbieter).
 * Bei erschöpften Kontingenten wirft chatComplete einen Fehler mit code='rate_limit'.
 * @param {string} transcriptText
 * @param {{ apiKey?:string, groqApiKey?:string, geminiApiKey?:string, llmProvider?:string,
 *           model?:string, geminiModel?:string, language?:string, fetchImpl?:Function }} opts
 */
async function generateMeetingSummary(transcriptText, opts = {}) {
  const { apiKey, groqApiKey, geminiApiKey, llmProvider, model, geminiModel, language, fetchImpl } = opts;
  const prompt = getMeetingSummaryPrompt(transcriptText, language || 'de');

  const { text, model: usedModel } = await chatComplete({
    system: 'Du bist ein sorgfältiger Protokollant. Antworte immer mit einem validen JSON-Objekt und erfinde nichts.',
    user: prompt,
    jsonMode: true,
    responseSchema: SUMMARY_RESPONSE_SCHEMA,
    maxTokens: 8192,
    temperature: 0.2,
    provider: llmProvider || 'auto',
    order: ['gemini', 'groq'],
    groqApiKey: groqApiKey != null ? groqApiKey : apiKey, // Abwärtskompatibilität: apiKey = Groq-Key
    groqModel: model || 'llama-3.3-70b-versatile',
    geminiApiKey,
    geminiModel,
    fetchImpl,
  });

  const summary = parseSummaryJson(text || '{}');
  if (!summary.kurzfassung && !summary.themen.length && !summary.todos.length) {
    const e = new Error('Bericht leer/unbrauchbar');
    e.code = 'empty';
    throw e;
  }
  summary.generatedAt = new Date().toISOString();
  summary.model = usedModel || model || '';
  return summary;
}

module.exports = { getMeetingSummaryPrompt, parseSummaryJson, generateMeetingSummary, GROQ_CHAT_URL, SUMMARY_RESPONSE_SCHEMA, SUMMARY_SCHEMA_VERSION };
