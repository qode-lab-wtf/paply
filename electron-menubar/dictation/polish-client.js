const { readResponse, completePolish, polishTokenBudget } = require('./policies');
const { GROQ_CHAT_URL, GROQ_MODELS_URL, selectPolishModel, groqReasoningOptions } = require('./groq-models');
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
  return async function polish({ text, apiKey, messages, custom = false }) {
    if (!apiKey) return null;
    const deadline = now() + 30000;
    if (!session || session.apiKey !== apiKey) session = { apiKey };
    const state = session;
    try {
      const model = selectPolishModel(await modelsFor(state, deadline - now()));
      if (!model) { unavailable(); log('model-unavailable'); return null; }
      const timeout = deadline - now();
      if (timeout <= 0) { log('timeout'); return null; }
      const res = await request(GROQ_CHAT_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
        body: JSON.stringify({ model, max_tokens: polishTokenBudget(text), messages, ...groqReasoningOptions(model),
          ...(!custom ? { temperature: 0 } : {}) }),
      }, timeout);
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
      const reason = custom ? (!result ? 'empty' : null) : polishRejection(text, result);
      if (reason) { log(reason); return null; }
      return result;
    } catch {
      log('request-failed');
      return null;
    }
  };
}

module.exports = { createPolishClient, modelMissing };
