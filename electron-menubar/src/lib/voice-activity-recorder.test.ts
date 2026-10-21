import { afterEach, describe, expect, it, vi } from 'vitest';
import { startVoiceActivityMeasurement } from './voice-activity-recorder';

function audioSource(sampleRate = 48000) {
  let level = 0;
  const analyser = { fftSize: 0, getFloatTimeDomainData: (data: Float32Array) => data.fill(level) };
  const context = { state: 'running', sampleRate, createAnalyser: () => analyser };
  const source = { context, fftSize: 32, connect: vi.fn(), disconnect: vi.fn() };
  return { source, context, analyser, setLevel: (value: number) => { level = value; } };
}

afterEach(() => vi.useRealTimers());

describe('Sprachmessung am vorhandenen Audio-Analyser', () => {
  it.each([44100, 48000, 96000, 192000])('erfasst bei %i Hz überlappende Zeitfenster, ohne die Balken-FFT zu ändern', sampleRate => {
    vi.useFakeTimers();
    const { source, analyser } = audioSource(sampleRate);
    const stop = startVoiceActivityMeasurement(source as unknown as AnalyserNode);
    vi.advanceTimersByTime(2000);
    expect(stop()).toMatchObject({ durationMs: 2000, measuredMs: 2000, speechMs: 0, peakDbfs: -120 });
    expect(analyser.fftSize / sampleRate * 1000).toBeGreaterThanOrEqual(50);
    expect(source.fftSize).toBe(32);
    expect(source.disconnect).toHaveBeenCalledWith(analyser);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('erfasst Sprache direkt vor dem Stop und beendet die Messung vor dem Stop-Signalton', () => {
    vi.useFakeTimers();
    const { source, setLevel } = audioSource();
    const stop = startVoiceActivityMeasurement(source as unknown as AnalyserNode);
    vi.advanceTimersByTime(2000);
    vi.advanceTimersByTime(15);
    setLevel(0.001); // -60 dBFS, sehr leise Sprache in den letzten 15 ms
    const result = stop();
    expect(result?.speechMs).toBe(15);
    setLevel(0.5); // Ein danach abgespielter Signalton darf das Ergebnis nicht ändern.
    vi.advanceTimersByTime(100);
    expect(stop()).toBe(result);
    expect(result?.peakDbfs).toBeCloseTo(-60);
  });

  it('liefert nach einem suspendierten Kontext keinen Stille-Nachweis', () => {
    vi.useFakeTimers();
    const { source, context } = audioSource();
    const stop = startVoiceActivityMeasurement(source as unknown as AnalyserNode);
    vi.advanceTimersByTime(1000);
    context.state = 'suspended';
    vi.advanceTimersByTime(40);
    context.state = 'running';
    vi.advanceTimersByTime(1000);
    expect(stop()).toBeUndefined();
  });

  it('liefert bei gedrosselten Timern keinen Stille-Nachweis', () => {
    let now = 0;
    vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] });
    const clock = vi.spyOn(performance, 'now').mockImplementation(() => now);
    try {
      const { source } = audioSource();
      const stop = startVoiceActivityMeasurement(source as unknown as AnalyserNode);
      now = 2000; // Der nächste Timer kam 2 Sekunden zu spät.
      vi.advanceTimersByTime(40);
      expect(stop()).toBeUndefined();
    } finally {
      clock.mockRestore();
    }
  });
});
