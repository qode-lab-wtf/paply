const GROQ_KEYS_URL = 'https://console.groq.com/keys';

async function validateGroqKey(key, { fetchImpl = globalThis.fetch, timeoutMs = 8000 } = {}) {
  if (typeof key !== 'string' || !key.trim() || key.length > 4096 || /[\r\n]/.test(key)) {
    return { status: 'invalid' };
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl('https://api.groq.com/openai/v1/models', {
      method: 'GET',
      headers: { Authorization: `Bearer ${key.trim()}` },
      signal: controller.signal,
      redirect: 'error',
    });
    return {
      status: response.ok
        ? 'valid'
        : [401, 403].includes(response.status)
          ? 'invalid'
          : 'unavailable',
    };
  } catch {
    // Keine Fehlerobjekte ausgeben: Sie können Request-Header mit dem Key enthalten.
    return { status: 'unavailable' };
  } finally {
    clearTimeout(timeout);
  }
}

async function saveGroqKey(store, key, options = {}) {
  const result = await validateGroqKey(key, options);
  const usable =
    typeof key === 'string' && !!key.trim() && key.length <= 4096 && !/[\r\n]/.test(key);
  const saved = usable && (result.status === 'valid' || options.saveAnyway === true);
  if (saved) store.set('groqApiKey', key.trim());
  return { ...result, saved };
}

async function microphonePermission(systemPreferences, platform, request = false) {
  let status = systemPreferences.getMediaAccessStatus('microphone');
  if (platform === 'darwin' && request && status === 'not-determined') {
    await systemPreferences.askForMediaAccess('microphone');
    status = systemPreferences.getMediaAccessStatus('microphone');
  }
  return {
    status,
    accessibilityRequired: platform === 'darwin',
    accessibilityGranted:
      platform !== 'darwin' || systemPreferences.isTrustedAccessibilityClient(false),
  };
}

module.exports = { GROQ_KEYS_URL, validateGroqKey, saveGroqKey, microphonePermission };
