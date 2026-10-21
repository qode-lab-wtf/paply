import { describe, it, expect } from 'vitest';
import { measureVoiceActivity, summarizeVoiceActivity, rmsDbfs, SPEECH_THRESHOLD_DBFS } from './voice-activity';

const samplesAt = (dbfs: number) => new Float32Array(2048).fill(10 ** (dbfs / 20));
const windowAt = (dbfs: number, elapsedMs = 40) => measureVoiceActivity(samplesAt(dbfs), elapsedMs)!;

describe('Sprachaktivitätsmessung', () => {
  it('misst RMS in dBFS und begrenzt digitale Stille auf einen serialisierbaren Wert', () => {
    expect(rmsDbfs(new Float32Array([1, -1]))).toBe(0);
    expect(rmsDbfs(samplesAt(-60))).toBeCloseTo(-60);
    expect(rmsDbfs(new Float32Array(2048))).toBe(-120);
    expect(JSON.parse(JSON.stringify(summarizeVoiceActivity([]))).peakDbfs).toBe(-120);
  });

  it('zählt mehrere Sekunden Stille vollständig, ohne Sprachaktivität zu erfinden', () => {
    const meta = summarizeVoiceActivity(Array.from({ length: 100 }, () => windowAt(-90)));
    expect(meta).toEqual({ durationMs: 4000, measuredMs: 4000, speechMs: 0, peakDbfs: expect.closeTo(-90), floorDbfs: expect.closeTo(-90), maxGapMs: 40 });
  });

  it('erkennt auch sehr leise Sprache oberhalb von -65 dBFS', () => {
    const meta = summarizeVoiceActivity([
      ...Array.from({ length: 50 }, () => windowAt(-100)), windowAt(SPEECH_THRESHOLD_DBFS + 1),
    ]);
    expect(meta.speechMs).toBe(40);
  });

  it('behält kurze Sprachaktivität und ihren Spitzenpegel auch nach langer Stille', () => {
    const meta = summarizeVoiceActivity([windowAt(-40), ...Array.from({ length: 1000 }, () => windowAt(-100))]);
    expect(meta.speechMs).toBe(40);
    expect(meta.peakDbfs).toBeCloseTo(-40);
  });

  it('zählt eine Messlücke nicht als beobachtete Stille', () => {
    const meta = summarizeVoiceActivity([windowAt(-90, 1000)]);
    expect(meta.durationMs).toBe(1000);
    expect(meta.measuredMs).toBe(50);
    expect(meta.maxGapMs).toBe(1000);
  });

  it('ignoriert unbrauchbare Messwerte', () => {
    for (const elapsed of [0, -40, NaN, Infinity]) {
      expect(measureVoiceActivity(samplesAt(-90), elapsed)).toBeUndefined();
    }
    expect(measureVoiceActivity(new Float32Array([NaN]), 40)).toBeUndefined();
    expect(measureVoiceActivity(new Float32Array(), 40)).toBeUndefined();
  });

  it('verwendet das 15. Perzentil der gesamten Aufnahme und ändert die Fenster nicht', () => {
    const windows = Array.from({ length: 100 }, (_, i) => Object.freeze({ dbfs: -100 + i, elapsedMs: 40 }));
    Object.freeze(windows);
    const meta = summarizeVoiceActivity(windows);
    expect(meta.floorDbfs).toBe(-86);
    expect(meta.peakDbfs).toBe(-1);
    expect(meta.speechMs).toBe(64 * 40); // Absolute Untergrenze -65, strikt darüber.
    expect(windows[0].dbfs).toBe(-100);
  });

  it('wertet frühe Silben rückwirkend relativ zum später erfassten Grundrauschen aus', () => {
    const meta = summarizeVoiceActivity([
      ...Array.from({ length: 15 }, () => windowAt(-25)),
      ...Array.from({ length: 110 }, () => windowAt(-50)),
    ]);
    expect(meta.floorDbfs).toBeCloseTo(-50);
    expect(meta.speechMs).toBe(600);
  });

  it('zählt ausschließlich Fenster strikt oberhalb von Grundrauschen plus 15 dB', () => {
    const meta = summarizeVoiceActivity([
      ...Array.from({ length: 100 }, () => ({ dbfs: -50, elapsedMs: 40 })),
      { dbfs: -35, elapsedMs: 40 }, { dbfs: -34, elapsedMs: 40 },
    ]);
    expect(meta.floorDbfs).toBe(-50);
    expect(meta.speechMs).toBe(40);
  });
});
