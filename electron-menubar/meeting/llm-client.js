'use strict';
// Gemeinsamer LLM-Client für Meeting-Aufgaben (Bericht). Unterstützt ZWEI Anbieter — Google Gemini
// (großzügiges Free-Tier, auch für die Audio-Auswertung genutzt) und Groq (schnell) — mit
// Auto-Fallback. 'auto' (Default) probiert in der übergebenen Reihenfolge (`order`, Default
// Gemini → Groq, damit das Groq-Tageskontingent fürs Diktat frei bleibt) und fällt bei
// Limit/Fehler/fehlendem Key auf den nächsten Anbieter zurück. 'groq'/'gemini' erzwingen einen
// Anbieter. Gibt { text, model } zurück. Bei 429 hat der Fehler code='rate_limit'.

const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';
const DEFAULT_GEMINI_MODEL = 'gemini-flash-latest';
// Ausweich-Reihenfolge bei nicht verfügbar/überlastet/Kontingent. Kein -lite: lehnt thinkingBudget 0 mit 400 ab.
const GEMINI_FALLBACK_MODELS = ['gemini-3.6-flash', 'gemini-3.5-flash'];
const GEMINI_RETRY_MS = 4000;                    // eine Wiederholung je Modell bei 5xx, bevor gewechselt wird
const DEFAULT_GROQ_MODEL = 'llama-3.3-70b-versatile';

async function callGroq({ system, user, jsonMode, maxTokens, temperature, apiKey, model, fetchImpl }) {
  const fetch = fetchImpl || globalThis.fetch;
  const res = await fetch(GROQ_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      temperature,
      max_tokens: maxTokens,
      ...(jsonMode ? { response_format: { type: 'json_object' } } : {}),
      messages: [
        ...(system ? [{ role: 'system', content: system }] : []),
        { role: 'user', content: user },
      ],
    }),
  });
  if (!res.ok) {
    const e = new Error(`Groq HTTP ${res.status}`);
    e.status = res.status;
    if (res.status === 429) e.code = 'rate_limit';
    throw e;
  }
  const data = await res.json();
  return { text: (data && data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content) || '', model };
}

async function callGemini({ system, user, jsonMode, responseSchema, thinkingBudget, maxTokens, temperature, apiKey, model, fetchImpl }) {
  const fetch = fetchImpl || globalThis.fetch;
  const url = `${GEMINI_BASE}/${model}:generateContent`;
  const body = {
    contents: [{ role: 'user', parts: [{ text: user }] }],
    generationConfig: {
      temperature,
      maxOutputTokens: maxTokens,
      ...(jsonMode ? { responseMimeType: 'application/json' } : {}),
      ...(jsonMode && responseSchema ? { responseSchema } : {}),
      ...(typeof thinkingBudget === 'number' ? { thinkingConfig: { thinkingBudget } } : {}),
    },
    ...(system ? { systemInstruction: { parts: [{ text: system }] } } : {}),
  };
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const e = new Error(`Gemini HTTP ${res.status}`);
    e.status = res.status;
    if (res.status === 429) e.code = 'rate_limit';
    throw e;
  }
  const data = await res.json();
  const parts = (data && data.candidates && data.candidates[0] && data.candidates[0].content && data.candidates[0].content.parts) || [];
  return { text: parts.map((p) => (p && p.text) || '').join(''), model };
}

/**
 * Führt eine Chat-Completion aus — provider-agnostisch, mit Fallback.
 * @param {{
 *   system?:string, user:string, jsonMode?:boolean, responseSchema?:object, thinkingBudget?:number,
 *   maxTokens?:number, temperature?:number,
 *   provider?:'auto'|'groq'|'gemini', order?:('groq'|'gemini')[],
 *   groqApiKey?:string, groqModel?:string, geminiApiKey?:string, geminiModel?:string,
 *   fetchImpl?:Function
 * }} opts
 * @returns {Promise<{text:string, model:string}>}
 */
async function chatComplete({
  system, user, jsonMode = false, responseSchema, thinkingBudget, maxTokens = 2048, temperature = 0,
  provider = 'auto', order = ['gemini', 'groq'],
  groqApiKey, groqModel = DEFAULT_GROQ_MODEL,
  geminiApiKey, geminiModel = DEFAULT_GEMINI_MODEL,
  fetchImpl, sleep = (ms) => new Promise((r) => setTimeout(r, ms)),
} = {}) {
  const seq = provider === 'groq' ? ['groq'] : provider === 'gemini' ? ['gemini'] : order;
  let lastErr = null;
  for (const p of seq) {
    if (p === 'groq' && !groqApiKey) continue;
    if (p === 'gemini' && !geminiApiKey) continue;
    if (p === 'groq') {
      try { return await callGroq({ system, user, jsonMode, maxTokens, temperature, apiKey: groqApiKey, model: groqModel, fetchImpl }); } catch (e) { lastErr = e; }
      continue;
    }
    // Gemini: Modell-Fallback bei 404/400 (Modell nicht verfügbar) und 500/503 (überlastet); sonst nächster Anbieter
    const models = [geminiModel, ...GEMINI_FALLBACK_MODELS.filter((m) => m !== geminiModel)];
    let stop = false;
    for (const m of models) {
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          return await callGemini({ system, user, jsonMode, responseSchema, thinkingBudget, maxTokens, temperature, apiKey: geminiApiKey, model: m, fetchImpl });
        } catch (e) {
          lastErr = e;
          const overloaded = [500, 502, 503].includes(e.status);
          if (overloaded && attempt === 0) { await sleep(GEMINI_RETRY_MS); continue; }
          if (![400, 404, 429].includes(e.status) && !overloaded) stop = true;
          break;
        }
      }
      if (stop) break;
    }
  }
  throw lastErr || new Error('Kein LLM-Anbieter verfügbar (kein Groq- oder Gemini-Key gesetzt)');
}

module.exports = { chatComplete, callGroq, callGemini, GROQ_URL, GEMINI_BASE, DEFAULT_GEMINI_MODEL, DEFAULT_GROQ_MODEL, GEMINI_FALLBACK_MODELS };
