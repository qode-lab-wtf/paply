/**
 * Start-/Stopp-Töne des Diktats („veredelt“): je zwei weiche, kurze Töne –
 * Quinte aufwärts beim Start (E5 → H5), abwärts beim Stopp (G5 → C5).
 *
 * - EIN AudioContext wird wiederverwendet (kein Aufbau pro Ton → minimale Latenz).
 * - Hüllkurve startet bei ~0 mit 8 ms Anstieg und klingt exponentiell aus → kein Klicken.
 * - Sinus + leise Oktave (Dreieck) durch einen Tiefpass: warm, nicht piepsig.
 * Optional `warmUpSounds()` früh aufrufen (z. B. beim Laden des Fensters).
 */

type AudioContextCtor = typeof AudioContext;

const START_NOTES = [659.25, 987.77]; // E5, H5
const STOP_NOTES = [783.99, 523.25]; // G5, C5
const NOTE_GAP = 0.075; // s zwischen den beiden Tönen
const ATTACK = 0.008;
const DECAY = 0.2;
const PEAK = 0.16;
const SILENT = 0.0001;

let ctx: AudioContext | null = null;
let output: AudioNode | null = null;

function getContext(): AudioContext | null {
  if (ctx && ctx.state !== 'closed') return ctx;
  const Ctor: AudioContextCtor | undefined =
    (globalThis as { AudioContext?: AudioContextCtor }).AudioContext ??
    (globalThis as { webkitAudioContext?: AudioContextCtor }).webkitAudioContext;
  if (!Ctor) return null;
  ctx = new Ctor({ latencyHint: 'interactive' });
  const lowpass = ctx.createBiquadFilter();
  lowpass.type = 'lowpass';
  lowpass.frequency.value = 3200;
  lowpass.connect(ctx.destination);
  output = lowpass;
  return ctx;
}

function schedule(context: AudioContext, freqs: number[]) {
  const t = context.currentTime + 0.005;
  freqs.forEach((freq, i) => {
    const t0 = t + i * NOTE_GAP;
    const env = context.createGain();
    env.gain.setValueAtTime(SILENT, t0);
    env.gain.exponentialRampToValueAtTime(PEAK, t0 + ATTACK);
    env.gain.exponentialRampToValueAtTime(SILENT, t0 + DECAY);
    env.connect(output!);

    const tone = context.createOscillator();
    tone.type = 'sine';
    tone.frequency.value = freq;
    tone.connect(env);

    const overtoneGain = context.createGain();
    overtoneGain.gain.value = 0.12;
    overtoneGain.connect(env);
    const overtone = context.createOscillator();
    overtone.type = 'triangle';
    overtone.frequency.value = freq * 2;
    overtone.connect(overtoneGain);

    for (const osc of [tone, overtone]) {
      osc.start(t0);
      osc.stop(t0 + DECAY + 0.02);
    }
    tone.onended = () => {
      env.disconnect();
      overtoneGain.disconnect();
    };
  });
}

function play(freqs: number[]) {
  try {
    const context = getContext();
    if (!context) return;
    if (context.state === 'suspended') {
      void context.resume().then(() => schedule(context, freqs)).catch(() => {});
    } else {
      schedule(context, freqs);
    }
  } catch (err) {
    console.error('[paply] Ton fehlgeschlagen', err);
  }
}

/** Ton beim Start der Aufnahme. */
export function playStartSound(): void {
  play(START_NOTES);
}

/** Ton beim Stopp der Aufnahme. */
export function playStopSound(): void {
  play(STOP_NOTES);
}

/** Legt den AudioContext vorab an, damit der erste Ton ohne Verzögerung kommt. */
export function warmUpSounds(): void {
  try {
    const context = getContext();
    if (context?.state === 'suspended') void context.resume().catch(() => {});
  } catch {
    /* ohne Audio-Ausgabe einfach still bleiben */
  }
}

/** Nur für Tests: internen Zustand zurücksetzen. */
export function __resetSoundsForTests(): void {
  ctx = null;
  output = null;
}
