// Modellnamen für App und Benchmark. Keine Netzwerk- oder Store-Abhängigkeit.
const POLISH_MODEL = 'qwen/qwen3.8-27b';
const POLISH_FALLBACK_MODEL = 'openai/gpt-oss-120b';
const MEETING_MODEL = POLISH_FALLBACK_MODEL;
const RETIRED_GROQ_MODEL = 'llama-3.3-70b-versatile';
const GROQ_MODELS_URL = 'https://api.groq.com/openai/v1/models';
const GROQ_CHAT_URL = 'https://api.groq.com/openai/v1/chat/completions';

function selectPolishModel(models) {
  const ids = new Set(models.map(model => typeof model === 'string' ? model : model?.id));
  return [POLISH_MODEL, POLISH_FALLBACK_MODEL].find(model => ids.has(model)) || null;
}

function groqReasoningOptions(model) {
  return model.startsWith('openai/gpt-oss-') ? { reasoning_format: 'hidden', reasoning_effort: 'low' } : {};
}

function migrateMeetingModel(store) {
  if (store.get('meetingSummaryModel') === RETIRED_GROQ_MODEL) {
    store.set('meetingSummaryModel', MEETING_MODEL);
  }
}

module.exports = { POLISH_MODEL, POLISH_FALLBACK_MODEL, MEETING_MODEL, RETIRED_GROQ_MODEL,
  GROQ_MODELS_URL, GROQ_CHAT_URL, selectPolishModel, migrateMeetingModel, groqReasoningOptions };
