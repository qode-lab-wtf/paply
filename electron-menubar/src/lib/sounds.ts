/**
 * Start-/Stopp-Töne des Diktats: je zwei weiche, kurze Töne – Quinte aufwärts beim Start,
 * abwärts beim Stopp.
 *
 * Standard ist „warm“ (seit v1.14.1): eine Oktave tiefer als zuvor, weicher Anstieg (18 ms),
 * Tiefpass bei 1,8 kHz und längeres Ausklingen – rund statt „blitzartig“.
 * „holz“ ist die Vergleichsvariante (Marimba-artig), „hell“ der Klang von v1.14.0.
 *
 * - EIN AudioContext wird wiederverwendet (kein Aufbau pro Ton → minimale Latenz).
 * - Hüllkurve startet bei ~0 und steigt linear an → kein Klicken.
 * Optional `warmUpSounds()` früh aufrufen (z. B. beim Laden des Fensters).
 */

type AudioContextCtor = typeof AudioContext;

export type SoundVariant = 'warm' | 'holz' | 'hell';

interface Voice {
  start: number[];
  stop: number[];
  gap: number; // s zwischen den beiden Tönen
  attack: number; // s, linearer Anstieg
  decay: number; // s bis zur Stille (exponentiell)
  peak: number;
  lowpass: number; // Hz
  overtone: { type: OscillatorType; ratio: number; gain: number };
}

export const SOUND_VARIANTS: Record<SoundVariant, Voice> = {
  // E4 → H4 / G4 → C4; Dreieck im Grundton gibt Wärme ohne Schärfe
  warm: {
    start: [329.63, 493.88],
    stop: [392.0, 261.63],
    gap: 0.085,
    attack: 0.018,
    decay: 0.34,
    peak: 0.22,
    lowpass: 1800,
    overtone: { type: 'triangle', ratio: 1, gain: 0.22 },
  },
  // D4 → A4 / A4 → D4; leiser 4. Teilton wie bei Holz-Klangstäben
  holz: {
    start: [293.66, 440.0],
    stop: [440.0, 293.66],
    gap: 0.08,
    attack: 0.015,
    decay: 0.28,
    peak: 0.2,
    lowpass: 2000,
    overtone: { type: 'sine', ratio: 4, gain: 0.05 },
  },
  // v1.14.0: E5 → H5 / G5 → C5
  hell: {
    start: [659.25, 987.77],
    stop: [783.99, 523.25],
    gap: 0.075,
    attack: 0.008,
    decay: 0.2,
    peak: 0.16,
    lowpass: 3200,
    overtone: { type: 'triangle', ratio: 2, gain: 0.12 },
  },
};

export const DEFAULT_SOUND_VARIANT: SoundVariant = 'warm';
const SILENT = 0.0001;

let ctx: AudioContext | null = null;
let output: BiquadFilterNode | null = null;
let suspendTimer: ReturnType<typeof setTimeout> | null = null;

// Nach dem Ton den Audio-Ausgang wieder schlafen legen: kein dauerhaft offener
// Ausgabe-Stream (Akku, Bluetooth-Kopfhörer). play() weckt ihn bei Bedarf.
function scheduleSuspend(context: AudioContext, afterMs: number) {
  if (suspendTimer) clearTimeout(suspendTimer);
  suspendTimer = setTimeout(() => {
    suspendTimer = null;
    if (context.state === 'running') void context.suspend().catch(() => {});
  }, afterMs);
}

function getContext(): AudioContext | null {
  if (ctx && ctx.state !== 'closed') return ctx;
  const Ctor: AudioContextCtor | undefined =
    (globalThis as { AudioContext?: AudioContextCtor }).AudioContext ??
    (globalThis as { webkitAudioContext?: AudioContextCtor }).webkitAudioContext;
  if (!Ctor) return null;
  ctx = new Ctor({ latencyHint: 'interactive' });
  const lowpass = ctx.createBiquadFilter();
  lowpass.type = 'lowpass';
  lowpass.frequency.value = SOUND_VARIANTS[DEFAULT_SOUND_VARIANT].lowpass;
  lowpass.Q.value = 0.6;
  lowpass.connect(ctx.destination);
  output = lowpass;
  return ctx;
}

function schedule(context: AudioContext, voice: Voice, freqs: number[]) {
  const t = context.currentTime + 0.005;
  output!.frequency.setValueAtTime(voice.lowpass, t);
  freqs.forEach((freq, i) => {
    const t0 = t + i * voice.gap;
    const env = context.createGain();
    env.gain.setValueAtTime(SILENT, t0);
    env.gain.linearRampToValueAtTime(voice.peak, t0 + voice.attack);
    env.gain.exponentialRampToValueAtTime(SILENT, t0 + voice.decay);
    env.connect(output!);

    const tone = context.createOscillator();
    tone.type = 'sine';
    tone.frequency.value = freq;
    tone.connect(env);

    const overtoneGain = context.createGain();
    overtoneGain.gain.value = voice.overtone.gain;
    overtoneGain.connect(env);
    const overtone = context.createOscillator();
    overtone.type = voice.overtone.type;
    overtone.frequency.value = freq * voice.overtone.ratio;
    overtone.connect(overtoneGain);

    for (const osc of [tone, overtone]) {
      osc.start(t0);
      osc.stop(t0 + voice.decay + 0.02);
    }
    tone.onended = () => {
      env.disconnect();
      overtoneGain.disconnect();
    };
  });
}

function play(variant: SoundVariant, which: 'start' | 'stop') {
  try {
    const context = getContext();
    if (!context) return;
    const voice = SOUND_VARIANTS[variant];
    const freqs = voice[which];
    if (context.state === 'suspended') {
      void context.resume().then(() => schedule(context, voice, freqs)).catch(() => {});
    } else {
      schedule(context, voice, freqs);
    }
    scheduleSuspend(context, (freqs.length * voice.gap + voice.decay) * 1000 + 400);
  } catch (err) {
    console.error('[paply] Ton fehlgeschlagen', err);
  }
}

/** Ton beim Start der Aufnahme. */
export function playStartSound(variant: SoundVariant = DEFAULT_SOUND_VARIANT): void {
  play(variant, 'start');
}

/** Ton beim Stopp der Aufnahme. */
export function playStopSound(variant: SoundVariant = DEFAULT_SOUND_VARIANT): void {
  play(variant, 'stop');
}

/** Legt den AudioContext vorab an, damit der erste Ton ohne Verzögerung kommt. */
export function warmUpSounds(): void {
  try {
    // Nur anlegen (teure Initialisierung vorziehen); bleibt bis zum ersten Ton schlafend.
    const context = getContext();
    if (context?.state === 'running') scheduleSuspend(context, 300);
  } catch {
    /* ohne Audio-Ausgabe einfach still bleiben */
  }
}

/** Nur für Tests: internen Zustand zurücksetzen. */
export function __resetSoundsForTests(): void {
  if (suspendTimer) clearTimeout(suspendTimer);
  suspendTimer = null;
  ctx = null;
  output = null;
}
