import { describe, it, expect } from 'vitest';
import { createVoiceActivity, measureVoiceActivity, rmsDbfs, SPEECH_THRESHOLD_DBFS } from './voice-activity';

const samplesAt = (dbfs: number) => new Float32Array(2048).fill(10 ** (dbfs / 20));

describe('Sprachaktivitätsmessung', () => {
  it('misst RMS in dBFS und begrenzt digitale Stille auf einen serialisierbaren Wert', () => {
    expect(rmsDbfs(new Float32Array([1, -1]))).toBe(0);
    expect(rmsDbfs(samplesAt(-60))).toBeCloseTo(-60);
    expect(rmsDbfs(new Float32Array(2048))).toBe(-120);
    expect(JSON.parse(JSON.stringify(createVoiceActivity())).peakDbfs).toBe(-120);
  });

  it('zählt mehrere Sekunden Stille vollständig, ohne Sprachaktivität zu erfinden', () => {
    let meta = createVoiceActivity();
    for (let i = 0; i < 100; i++) meta = measureVoiceActivity(meta, samplesAt(-90), 40);
    expect(meta).toEqual({ durationMs: 4000, measuredMs: 4000, speechMs: 0, peakDbfs: expect.closeTo(-90), maxGapMs: 40 });
  });

  it('erkennt auch sehr leise Sprache oberhalb von -65 dBFS', () => {
    const meta = measureVoiceActivity(createVoiceActivity(), samplesAt(SPEECH_THRESHOLD_DBFS + 1), 40);
    expect(meta.speechMs).toBe(40);
  });

  it('behält kurze Sprachaktivität und ihren Spitzenpegel auch nach langer Stille', () => {
    let meta = measureVoiceActivity(createVoiceActivity(), samplesAt(-40), 40);
    for (let i = 0; i < 1000; i++) meta = measureVoiceActivity(meta, samplesAt(-100), 40);
    expect(meta.speechMs).toBe(40);
    expect(meta.peakDbfs).toBeCloseTo(-40);
  });

  it('zählt eine Messlücke nicht als beobachtete Stille', () => {
    const meta = measureVoiceActivity(createVoiceActivity(), samplesAt(-90), 1000);
    expect(meta.durationMs).toBe(1000);
    expect(meta.measuredMs).toBe(50);
    expect(meta.maxGapMs).toBe(1000);
  });

  it('ändert den bisherigen Messstand nicht und ignoriert unbrauchbare Messwerte', () => {
    const initial = createVoiceActivity();
    const next = measureVoiceActivity(initial, samplesAt(-30), 40);
    expect(initial.speechMs).toBe(0);
    expect(next.speechMs).toBe(40);
    for (const elapsed of [0, -40, NaN, Infinity]) {
      expect(measureVoiceActivity(next, samplesAt(-90), elapsed)).toBe(next);
    }
    expect(measureVoiceActivity(next, new Float32Array([NaN]), 40)).toBe(next);
    expect(measureVoiceActivity(next, new Float32Array(), 40)).toBe(next);
  });
});
