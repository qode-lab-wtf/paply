import { mkdir, readFile, writeFile, rename, unlink, open } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';

export const hash = value => createHash('sha256').update(typeof value === 'string' || Buffer.isBuffer(value) ? value : JSON.stringify(value)).digest('hex');
export async function readJson(file, fallback) {
  try { return JSON.parse(await readFile(file, 'utf8')); }
  catch (e) { if (e.code === 'ENOENT' && arguments.length > 1) return fallback; throw e; }
}
export async function writeJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const tmp = `${file}.${process.pid}.tmp`;
  await writeFile(tmp, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
  await rename(tmp, file);
}
export async function acquireLock(file) {
  await mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  for (let attempt = 0; attempt < 2; attempt++) {
    try { const fd = await open(file, 'wx', 0o600); await fd.writeFile(String(process.pid)); await fd.close(); return async () => unlink(file).catch(() => {}); }
    catch (e) {
      if (e.code !== 'EEXIST') throw e;
      const pid = Number(await readFile(file, 'utf8'));
      if (!Number.isInteger(pid) || pid <= 0) throw new Error('Benchmark-Lock ungültig; nach Prüfung manuell entfernen.');
      try { process.kill(pid, 0); } catch (err) { if (err.code === 'ESRCH') { await unlink(file); continue; } throw err; }
      throw new Error(`Benchmark läuft bereits (PID ${pid}).`);
    }
  }
  throw new Error('Lock konnte nicht übernommen werden.');
}
export const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function wait(ms, label = 'API-Backoff', sleepImpl = sleep) {
  if (ms >= 1000) console.log(`${label}: ${Math.ceil(ms / 1000)} s warten.`);
  for (let remaining = ms; remaining > 0; remaining -= 30_000) await sleepImpl(Math.min(30_000, remaining));
}
export class ApiError extends Error {
  constructor(provider, status, retryAt = null, cached = false) {
    super(`${provider}: HTTP ${status}${cached ? ' (Fehlercache)' : ''}${retryAt ? `; frühestens ${new Date(retryAt).toISOString()} erneut` : ''}`);
    this.status = status; this.retryAt = retryAt;
  }
}
export function finalText(data) {
  const choice = data.choices?.[0];
  if (!choice || choice.finish_reason !== 'stop') throw new Error('LLM-Ausgabe fehlt oder wurde abgeschnitten; Ergebnis nicht gewertet.');
  let content = choice.message?.content;
  if (typeof content !== 'string') throw new Error('Keine finale Textantwort.');
  content = content.replace(/<think>[\s\S]*?<\/think>/gi, '').trim();
  const final = content.match(/<\|(?:start\|>assistant<\|channel\|>final<\|message|channel\|>final|final)\|>([\s\S]*)/);
  if (final) content = final[1].replace(/<\|[^>]+\|>/g, '').trim();
  if (!content || /<think>|<\|channel\|>analysis/i.test(content)) throw new Error('Keine eindeutig finale Antwort (Reasoning nicht gewertet).');
  return content;
}
function retryDelay(response, data, attempt, now) {
  const h = response.headers.get('retry-after');
  let delay = Number(h) * 1000;
  if (!Number.isFinite(delay) || delay <= 0) delay = Date.parse(h) - now;
  const detail = data?.error?.details?.find(d => d.retryDelay)?.retryDelay;
  if (detail) delay = Math.max(delay || 0, parseFloat(detail) * 1000);
  return Math.max(Number.isFinite(delay) ? delay : 0, 15_000 * 2 ** attempt);
}

export class Api {
  constructor({ data, config, offline = false, refreshModels = false, fetchImpl = fetch, sleepImpl = sleep, now = Date.now }) {
    Object.assign(this, { data, config, offline, refreshModels, fetchImpl, sleepImpl, now });
    this.stats = { requests: 0, hits: 0, errorHits: 0, retries: 0 };
    this.blocked = new Map(); this.next = new Map();
  }
  async request(provider, endpoint, payload, { audio = null, validate = x => x, discovery = false, cachedOnly = false } = {}) {
    const digest = hash({ provider, endpoint, payload, audio: audio ? hash(audio.buffer) : null });
    const file = path.join(this.data, 'cache', `${digest}.json`);
    const cached = await readJson(file, null);
    if (cached && cached.ok && (!discovery || this.offline || (!this.refreshModels && this.now() - cached.at < 86_400_000))) {
      this.stats.hits++; return cached.value;
    }
    if (cachedOnly) { const e = new Error('Kein erfolgreiches Cache-Ergebnis.'); e.code = 'CACHE_MISS'; throw e; }
    if (cached && !cached.ok && this.now() < cached.retryAt && !this.refreshModels) {
      this.stats.errorHits++; throw new ApiError(provider, cached.status, cached.retryAt, true);
    }
    if (this.offline) throw new Error(`${provider}: Cache fehlt (--offline).`);
    const key = provider === 'Groq' ? this.config.groqApiKey : this.config.geminiApiKey;
    if (!key) throw new Error(`${provider}: API-Key fehlt in der Konfiguration.`);
    const model = payload?.model || endpoint;
    const bucket = `${provider}:${model}`;
    const blocked = this.blocked.get(bucket);
    if (blocked?.retryAt > this.now()) throw new ApiError(provider, blocked.status, blocked.retryAt);
    const cooldownFile = path.join(this.data, 'cache', 'cooldowns.json');
    const cooldowns = await readJson(cooldownFile, {});
    const cooldown = cooldowns[bucket] || 0;
    if (cooldown - this.now() > 120_000) throw new ApiError(provider, 429, cooldown);
    await wait(Math.max(0, cooldown - this.now(), (this.next.get(provider) || 0) - this.now()), `${provider} Abstand`, this.sleepImpl);
    const base = provider === 'Groq' ? 'https://api.groq.com/openai/v1/' : 'https://generativelanguage.googleapis.com/v1beta/';
    const headers = provider === 'Groq' ? { Authorization: `Bearer ${key}` } : { 'x-goog-api-key': key };
    for (let attempt = 0; attempt < 3; attempt++) {
      let body;
      const requestHeaders = { ...headers };
      if (audio) {
        body = new FormData();
        for (const [k, v] of Object.entries(payload)) body.set(k, String(v));
        body.set('file', new Blob([audio.buffer], { type: audio.mime }), audio.name);
      } else if (payload) { body = JSON.stringify(payload); requestHeaders['Content-Type'] = 'application/json'; }
      let response;
      const started = performance.now();
      this.stats.requests++;
      try {
        response = await this.fetchImpl(base + endpoint, { method: payload ? 'POST' : 'GET', headers: requestHeaders, body, signal: AbortSignal.timeout(180_000) });
      } catch {
        // Unknown delivery: never automatically repeat a potentially processed/costing request.
        throw new Error(`${provider}: Netzwerkfehler/Timeout. Kein automatischer Wiederholungsaufruf.`);
      }
      this.next.set(provider, this.now() + (provider === 'Groq' ? 2200 : 6500));
      let data;
      try { data = await response.json(); } catch { throw new Error(`${provider}: ungültige API-Antwort (HTTP ${response.status}).`); }
      if (response.ok) {
        let value;
        try { value = validate(data, { latencyMs: Math.round(performance.now() - started) }); } catch (error) {
          await writeJson(file, { ok: false, at: this.now(), status: 'invalid-output', retryAt: this.now() + 86_400_000 });
          throw error;
        }
        await writeJson(file, { ok: true, at: this.now(), provider, model, value });
        return value;
      }
      const status = response.status;
      if (status === 429 || status >= 500) {
        const delay = retryDelay(response, data, attempt, this.now());
        const daily = status === 429 && /perday|per_day|daily|per day|limit:\s*0/i.test(JSON.stringify(data));
        const retryAt = this.now() + (daily ? Math.max(delay, 3_600_000) : delay);
        cooldowns[bucket] = retryAt;
        await writeJson(cooldownFile, cooldowns);
        if (attempt < 2 && !daily && delay <= 120_000) {
          this.stats.retries++;
          await wait(delay, `${provider} HTTP ${status}`, this.sleepImpl);
          continue;
        }
        this.blocked.set(bucket, { status, retryAt });
        await writeJson(file, { ok: false, at: this.now(), status, retryAt });
        throw new ApiError(provider, status, retryAt);
      }
      const retryAt = this.now() + (status === 404 || status === 400 ? 86_400_000 : 300_000);
      await writeJson(file, { ok: false, at: this.now(), status, retryAt });
      throw new ApiError(provider, status, retryAt);
    }
  }
  async models() {
    const result = await this.request('Groq', 'models', null, { discovery: true, validate: d => {
      if (!Array.isArray(d.data)) throw new Error('Groq-Modellliste ungültig.');
      return d.data.filter(m => m.active !== false).map(m => m.id).sort();
    } });
    return result;
  }
  async whisper(audio, model, prompt = null) {
    return this.request('Groq', 'audio/transcriptions', { model, language: 'de', response_format: 'verbose_json', ...(prompt ? { prompt } : {}) }, { audio, validate: d => {
      if (typeof d.text !== 'string') throw new Error('Whisper-Text fehlt.');
      return { model, text: d.text.trim(), segments: d.segments || [], duration: d.duration ?? null };
    } });
  }
  async gemini(audio) {
    const models = ['gemini-3.6-flash', 'gemini-3.5-flash', 'gemini-flash-latest'];
    const attempt = (model, cachedOnly) => this.request('Gemini', `models/${model}:generateContent`, {
      contents: [{ role: 'user', parts: [
        { text: 'Transkribiere wortgetreu auf Deutsch, inkl. Füllwörter und Wiederholungen, nichts glätten, nur den Text ausgeben' },
        { inlineData: { mimeType: audio.mime, data: audio.buffer.toString('base64') } },
      ] }], generationConfig: { temperature: 0, maxOutputTokens: 16384 },
    }, { cachedOnly, validate: d => {
      const c = d.candidates?.[0];
      if (!c || c.finishReason !== 'STOP') throw new Error('Gemini-Ausgabe blockiert, fehlt oder abgeschnitten.');
      const text = (c.content?.parts || []).filter(p => !p.thought).map(p => p.text || '').join('').trim();
      if (!text) throw new Error('Gemini-Text fehlt.');
      return { model, text, segments: [] };
    } });
    // Reuse any successful fallback BEFORE retrying a failed primary model, including offline.
    for (const model of models) {
      try { return await attempt(model, true); }
      catch (e) { if (e.code !== 'CACHE_MISS') throw e; }
    }
    if (this.offline) throw new Error('Gemini: Kein erfolgreiches Audio-Ergebnis im Cache (--offline).');
    let last;
    for (const model of models) {
      try { return await attempt(model, false); }
      catch (e) {
        last = e;
        if (![400, 404, 429, 500, 502, 503, 504].includes(e.status)) throw e;
        console.log(`Gemini ${model}: HTTP ${e.status}; nächstes Ausweichmodell.`);
        // A provider cooldown is respected before any fallback request as well.
      }
    }
    throw last;
  }
  async chat(model, messages, { json = false, temperature = undefined } = {}) {
    return this.request('Groq', 'chat/completions', {
      model, messages, max_tokens: 8192,
      ...(temperature === undefined ? {} : { temperature }),
      ...(model.startsWith('openai/gpt-oss-') ? { reasoning_format: 'hidden', reasoning_effort: 'low' } : {}),
      ...(json ? { response_format: { type: 'json_object' } } : {}),
    }, { validate: (d, timing) => ({ text: finalText(d), model, usage: d.usage ?? null, ...timing }) });
  }
}
