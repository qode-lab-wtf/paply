import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { __resetSoundsForTests, playStartSound, playStopSound, SOUND_VARIANTS, warmUpSounds } from './sounds';

type Call = [string, number, number];

class FakeParam {
  value = 0;
  calls: Call[] = [];
  setValueAtTime(v: number, t: number) { this.calls.push(['set', v, t]); }
  exponentialRampToValueAtTime(v: number, t: number) { this.calls.push(['exp', v, t]); }
  linearRampToValueAtTime(v: number, t: number) { this.calls.push(['lin', v, t]); }
}
class FakeNode { connect() {} disconnect() {} }
class FakeGain extends FakeNode { gain = new FakeParam(); }
class FakeOsc extends FakeNode {
  type = 'sine';
  frequency = new FakeParam();
  starts: number[] = [];
  onended: (() => void) | null = null;
  start(t: number) { this.starts.push(t); }
  stop() {}
}

let contexts: FakeContext[] = [];
class FakeContext {
  state: 'running' | 'suspended' | 'closed' = 'running';
  currentTime = 1;
  destination = new FakeNode();
  gains: FakeGain[] = [];
  oscs: FakeOsc[] = [];
  constructor() { contexts.push(this); }
  createGain() { const g = new FakeGain(); this.gains.push(g); return g; }
  createOscillator() { const o = new FakeOsc(); this.oscs.push(o); return o; }
  filters: { frequency: FakeParam }[] = [];
  createBiquadFilter() { const f = Object.assign(new FakeNode(), { type: '', frequency: new FakeParam(), Q: new FakeParam() }); this.filters.push(f); return f; }
  resume() { this.state = 'running'; return Promise.resolve(); }
  suspend() { this.state = 'suspended'; return Promise.resolve(); }
}

describe('sounds', () => {
  beforeEach(() => {
    contexts = [];
    __resetSoundsForTests();
    vi.stubGlobal('AudioContext', FakeContext);
  });
  afterEach(() => vi.unstubAllGlobals());

  it('nutzt einen einzigen AudioContext für alle Töne', () => {
    warmUpSounds();
    playStartSound();
    playStopSound();
    playStartSound();
    expect(contexts).toHaveLength(1);
  });

  it('spielt beim Start zwei aufsteigende Töne', () => {
    playStartSound();
    const freqs = contexts[0].oscs.filter((o) => o.type === 'sine').map((o) => o.frequency.value);
    expect(freqs).toHaveLength(2);
    expect(freqs[1]).toBeGreaterThan(freqs[0]);
  });

  it('spielt beim Stopp zwei absteigende Töne', () => {
    playStopSound();
    const freqs = contexts[0].oscs.filter((o) => o.type === 'sine').map((o) => o.frequency.value);
    expect(freqs[1]).toBeLessThan(freqs[0]);
  });

  it('beginnt jede Hüllkurve still und mit weichem Anstieg (kein Klicken)', () => {
    playStartSound();
    const envelopes = contexts[0].gains.filter((g) => g.gain.calls.length > 0);
    expect(envelopes).toHaveLength(2);
    for (const g of envelopes) {
      const [first, attack] = g.gain.calls;
      expect(first[0]).toBe('set');
      expect(first[1]).toBeLessThan(0.001);
      expect(attack[0]).toBe('lin');
      expect(attack[2] - first[2]).toBeGreaterThanOrEqual(0.015);
    }
  });

  it('wartet bei pausiertem Context auf resume()', async () => {
    warmUpSounds();
    contexts[0].state = 'suspended';
    playStartSound();
    expect(contexts[0].oscs).toHaveLength(0);
    await Promise.resolve();
    await Promise.resolve();
    expect(contexts[0].oscs.length).toBeGreaterThan(0);
  });

  it('bleibt ohne Web Audio still statt zu werfen', () => {
    vi.stubGlobal('AudioContext', undefined);
    expect(() => playStartSound()).not.toThrow();
  });

  it('klingt standardmäßig warm: tiefe Grundtöne, Tiefpass ≤ 2 kHz, langes Ausklingen', () => {
    playStartSound();
    const ctx = contexts[0];
    const sines = ctx.oscs.filter((o) => o.type === 'sine').map((o) => o.frequency.value);
    expect(Math.max(...sines)).toBeLessThan(520);
    const lp = ctx.filters[0].frequency.calls.at(-1)!;
    expect(lp[1]).toBeLessThanOrEqual(2000);
    expect(SOUND_VARIANTS.warm.decay).toBeGreaterThan(SOUND_VARIANTS.hell.decay);
  });

  it('spielt auf Wunsch eine andere Variante', () => {
    playStartSound('hell');
    const sines = contexts[0].oscs.filter((o) => o.type === 'sine').map((o) => o.frequency.value);
    expect(sines).toContain(SOUND_VARIANTS.hell.start[0]);
  });
});
