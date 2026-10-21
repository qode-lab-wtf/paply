// Sehr niedrige Schwelle: Auch leise Sprache soll als Aktivität zählen.
export const SPEECH_THRESHOLD_DBFS = -65;
export const MAX_SAMPLE_GAP_MS = 100;

export interface VoiceActivityMeta {
  durationMs: number;
  measuredMs: number;
  speechMs: number;
  peakDbfs: number; // Höchster RMS-Pegel eines Messfensters, kein Gesamtmittel.
  maxGapMs: number;
}

export function createVoiceActivity(): VoiceActivityMeta {
  return { durationMs: 0, measuredMs: 0, speechMs: 0, peakDbfs: -120, maxGapMs: 0 };
}

export function rmsDbfs(samples: Float32Array): number {
  if (!samples.length) return NaN;
  let sum = 0;
  for (const sample of samples) sum += sample * sample;
  return Math.max(-120, 20 * Math.log10(Math.sqrt(sum / samples.length)));
}

// Rein und unabhängig von Web Audio/Timern. Lange Messlücken werden nicht als
// beobachtete Stille gezählt; Main verwirft bei solchen Lücken nichts vorab.
export function measureVoiceActivity(
  previous: VoiceActivityMeta, samples: Float32Array, elapsedMs: number
): VoiceActivityMeta {
  const dbfs = rmsDbfs(samples);
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0 || !Number.isFinite(dbfs)) return previous;
  const measuredMs = Math.min(elapsedMs, 50);
  return {
    durationMs: previous.durationMs + elapsedMs,
    measuredMs: previous.measuredMs + measuredMs,
    speechMs: previous.speechMs + (dbfs > SPEECH_THRESHOLD_DBFS ? measuredMs : 0),
    peakDbfs: Math.max(previous.peakDbfs, dbfs),
    maxGapMs: Math.max(previous.maxGapMs, elapsedMs),
  };
}
