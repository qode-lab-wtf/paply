// Absolute Untergrenze; der tatsächliche Schwellwert folgt dem Grundrauschen.
export const SPEECH_THRESHOLD_DBFS = -65;
export const MAX_SAMPLE_GAP_MS = 100;

export interface VoiceActivityMeta {
  durationMs: number;
  measuredMs: number;
  speechMs: number;
  peakDbfs: number; // Höchster RMS-Pegel eines Messfensters, kein Gesamtmittel.
  floorDbfs: number; // 15. Perzentil der RMS-Fensterpegel dieser Aufnahme.
  maxGapMs: number;
}

export interface VoiceActivityWindow {
  dbfs: number;
  elapsedMs: number;
}

export function rmsDbfs(samples: Float32Array): number {
  if (!samples.length) return NaN;
  let sum = 0;
  for (const sample of samples) sum += sample * sample;
  return Math.max(-120, 20 * Math.log10(Math.sqrt(sum / samples.length)));
}

// Reine Einzelmessung. Der Adapter sammelt die Fenster nur im Renderer.
export function measureVoiceActivity(samples: Float32Array, elapsedMs: number): VoiceActivityWindow | undefined {
  const dbfs = rmsDbfs(samples);
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0 || !Number.isFinite(dbfs)) return undefined;
  return { dbfs, elapsedMs };
}

// Erst beim Stop auswerten: Auch frühe Silben werden relativ zum Grundrauschen
// der gesamten Aufnahme beurteilt. Die Rohdaten verlassen den Renderer nicht.
export function summarizeVoiceActivity(windows: readonly VoiceActivityWindow[]): VoiceActivityMeta {
  const levels = windows.map(window => window.dbfs).sort((a, b) => a - b);
  // Nearest-rank-Perzentil: mindestens 15 % der Fenster liegen bei/unter floor.
  const floorDbfs = levels[Math.max(0, Math.ceil(levels.length * 0.15) - 1)] ?? -120;
  const thresholdDbfs = Math.max(SPEECH_THRESHOLD_DBFS, floorDbfs + 15);
  let durationMs = 0, measuredMs = 0, speechMs = 0, maxGapMs = 0;
  for (const window of windows) {
    const observedMs = Math.min(window.elapsedMs, 50);
    durationMs += window.elapsedMs;
    measuredMs += observedMs;
    if (window.dbfs > thresholdDbfs) speechMs += observedMs;
    maxGapMs = Math.max(maxGapMs, window.elapsedMs);
  }
  return {
    durationMs, measuredMs, speechMs, maxGapMs, floorDbfs,
    peakDbfs: levels[levels.length - 1] ?? -120,
  };
}
