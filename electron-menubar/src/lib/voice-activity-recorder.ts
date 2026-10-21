import { measureVoiceActivity, summarizeVoiceActivity, MAX_SAMPLE_GAP_MS } from './voice-activity';
import type { VoiceActivityMeta, VoiceActivityWindow } from './voice-activity';

// Eigener Zeitbereich-Puffer am vorhandenen Analyser: Die FFT-Auflösung und
// Pegelbalken des Widgets bleiben unverändert. Keine Verbindung zum Lautsprecher.
export function startVoiceActivityMeasurement(source: AnalyserNode): () => VoiceActivityMeta | undefined {
  const analyser = source.context.createAnalyser();
  // Mindestens 50 ms auch bei 96/192 kHz, damit zwischen Messungen keine
  // regulären Lücken entstehen.
  analyser.fftSize = Math.min(32768, 2 ** Math.ceil(Math.log2(source.context.sampleRate * 0.05)));
  const maxGapMs = Math.min(MAX_SAMPLE_GAP_MS, analyser.fftSize / source.context.sampleRate * 1000);
  source.connect(analyser);
  const samples = new Float32Array(analyser.fftSize);
  const windows: VoiceActivityWindow[] = [];
  const startedAt = performance.now();
  let lastSampleAt = startedAt;
  let valid = source.context.state === 'running';
  let finished = false;
  let result: VoiceActivityMeta | undefined;
  const sample = () => {
    const now = performance.now();
    if (now === lastSampleAt) return;
    // Ein suspendierter Kontext liefert Nullen, aber keinen Stille-Nachweis.
    if (source.context.state !== 'running' || now - lastSampleAt > maxGapMs) valid = false;
    analyser.getFloatTimeDomainData(samples);
    const window = measureVoiceActivity(samples, now - lastSampleAt);
    if (window) windows.push(window);
    else valid = false;
    lastSampleAt = now;
  };
  const timer = setInterval(sample, 40);

  return () => {
    if (finished) return result;
    finished = true;
    clearInterval(timer);
    sample(); // Auch Sprache unmittelbar vor dem Stop erfassen.
    source.disconnect(analyser);
    const now = performance.now();
    if (!valid || source.context.state !== 'running') return undefined;
    const meta = summarizeVoiceActivity(windows);
    result = {
      ...meta,
      durationMs: now - startedAt,
      maxGapMs: Math.max(meta.maxGapMs, now - lastSampleAt),
    };
    return result;
  };
}
