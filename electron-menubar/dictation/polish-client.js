const { readResponse, completePolish, polishTokenBudget } = require('./policies');
const { GROQ_CHAT_URL, GROQ_MODELS_URL, POLISH_MODEL, POLISH_FALLBACK_MODEL, selectPolishModel, groqReasoningOptions } = require('./groq-models');
const { finalPolishText, polishRejection } = require('./polish');

function modelMissing(response) {
  if (response.status === 404) return true;
  if (response.status !== 400) return false;
  try { return ['model_decommissioned', 'model_not_found'].includes(JSON.parse(response.body)?.error?.code); }
  catch { return false; }
}

// Ein Client je App-Sitzung; parallele Diktate teilen sich die Modellabfrage.
function createPolishClient({ request = readResponse, onUnavailable = () => {}, log = () => {}, now = Date.now } = {}) {
  let session;
  let warned = false;
  function unavailable() {
    if (!warned) { warned = true; onUnavailable(); }
  }
  async function modelsFor(state, timeout) {
    if (state.ids && now() - state.checkedAt < 5 * 60 * 1000) return state.ids;
    if (!state.pending) {
      state.pending = (async () => {
        const res = await request(GROQ_MODELS_URL, {
          method: 'GET', headers: { Authorization: `Bearer ${state.apiKey}` },
        }, Math.min(10000, timeout));
        if (!res.ok) {
          if (modelMissing(res)) unavailable();
          throw new Error('models-unavailable');
        }
        const data = JSON.parse(res.body).data;
        if (!Array.isArray(data)) throw new Error('models-invalid');
        state.ids = data.filter(model => model?.active !== false).map(model => model?.id).filter(Boolean);
        state.checkedAt = now();
        return state.ids;
      })().finally(() => { state.pending = null; });
    }
    return state.pending;
  }
  async function polish({ text, apiKey, messages, custom = false, vocabulary = '' }) {
    if (!apiKey) return null;
    const deadline = now() + 30000;
    if (!session || session.apiKey !== apiKey) session = { apiKey };
    const state = session;
    try {
      let model = selectPolishModel(await modelsFor(state, deadline - now()));
      if (!model) { unavailable(); log('model-unavailable'); return null; }
      const timeout = deadline - now();
      if (timeout <= 0) { log('timeout'); return null; }
      const send = (id, ms) => request(GROQ_CHAT_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
        body: JSON.stringify({ model: id, max_tokens: polishTokenBudget(text), messages, ...groqReasoningOptions(id),
          ...(!custom ? { temperature: 0 } : {}) }),
      }, ms);
      let res = await send(model, timeout);
      // Limit erreicht (429, z. B. Tageskontingent im Free-Tier): einmal das andere Modell mit
      // eigenem Kontingent versuchen (wie Paply iOS), statt sofort den Rohtext einzusetzen.
      const alternative = res.status === 429
        && [POLISH_MODEL, POLISH_FALLBACK_MODEL].find(id => id !== model && state.ids.includes(id));
      if (alternative && deadline - now() > 0) {
        model = alternative;
        res = await send(model, deadline - now());
      }
      if (!res.ok) {
        if (modelMissing(res)) {
          // Dieses Diktat bleibt roh. Das nächste nutzt ggf. das noch verfügbare Ausweichmodell.
          state.ids = state.ids.filter(id => id !== model);
          unavailable();
        }
        log(`http-${res.status}`);
        return null;
      }
      const result = finalPolishText(completePolish(JSON.parse(res.body)));
      // Eigene Agenten dürfen absichtlich umformen/erweitern; ihr Vertrag bleibt erhalten.
      const reason = custom ? (!result ? 'empty' : null) : polishRejection(text, result, { vocabulary });
      if (reason) { log(reason); return null; }
      return result;
    } catch {
      log('request-failed');
      return null;
    }
  }
  // Modellliste schon während der Aufnahme laden (wie Paply iOS): Nach dem Stopp entfällt
  // dann die serielle Abfrage (~0,2 s), wenn die letzte Prüfung über fünf Minuten her ist.
  // Fehler bleiben still; das Polieren fragt in dem Fall wie bisher selbst.
  polish.prefetch = apiKey => {
    if (!apiKey) return;
    if (!session || session.apiKey !== apiKey) session = { apiKey };
    modelsFor(session, 10000).catch(() => {});
  };
  return polish;
}

module.exports = { createPolishClient, modelMissing };
