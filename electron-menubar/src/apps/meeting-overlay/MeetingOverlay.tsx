import { useEffect, useRef, useState } from 'react';
import { Mic, Phone } from 'lucide-react';
import { cn } from '@/lib/utils';

type HealthColor = 'green' | 'yellow' | 'red';

interface MeetingStatus {
  color: HealthColor;
  reason: string;
  durationMs: number;
  micLevel: number;
  systemLevel: number;
}

// Resampling auf die Zielrate (16 kHz). Läuft auf einem Default-AudioContext
// (Geräterate) — ein erzwungener 16-kHz-Context lieferte in Electron/Chromium mit
// MediaStreamSource teils STILLE (Capture-Regression).
// - fromRate > toRate: Downsampling per MITTELUNG (Box-Filter) = leichtes Anti-Aliasing.
// - fromRate < toRate: Upsampling per linearer Interpolation (Sub-16k-Geräte, z.B. Bluetooth-SCO 8 kHz).
function downsample(f32: Float32Array, fromRate: number, toRate: number): Float32Array {
  if (fromRate === toRate) return f32;
  const ratio = fromRate / toRate;
  const outLen = Math.max(1, Math.floor(f32.length / ratio));
  const out = new Float32Array(outLen);
  if (fromRate < toRate) {
    for (let i = 0; i < outLen; i++) {
      const pos = i * ratio;
      const i0 = Math.floor(pos);
      const frac = pos - i0;
      const a = f32[i0] ?? 0;
      const b = f32[i0 + 1] ?? a;
      out[i] = a + (b - a) * frac;
    }
    return out;
  }
  for (let i = 0; i < outLen; i++) {
    const start = Math.floor(i * ratio);
    const end = Math.min(f32.length, Math.floor((i + 1) * ratio));
    let s = 0;
    for (let j = start; j < end; j++) s += f32[j];
    out[i] = s / Math.max(1, end - start);
  }
  return out;
}

function floatToInt16(f32: Float32Array): Int16Array {
  const out = new Int16Array(f32.length);
  for (let i = 0; i < f32.length; i++) {
    const clamped = Math.max(-1, Math.min(1, f32[i]));
    out[i] = clamped < 0 ? clamped * 32768 : clamped * 32767;
  }
  return out;
}

function rms(int16: Int16Array): number {
  if (int16.length === 0) return 0;
  let sum = 0;
  for (let i = 0; i < int16.length; i++) {
    const s = int16[i] / 32768;
    sum += s * s;
  }
  return Math.sqrt(sum / int16.length);
}

// Mikrofon-Constraints — IDENTISCH zum normalen Diktat-Modus (Command+X), der bei Allan auch in
// lauter Umgebung zuverlässig funktioniert: EchoCancellation + NoiseSuppression + AutoGainControl AN.
// AGC hebt leise/entfernte Sprecher an, NS entfernt Raumlärm; die Sprechertrennung übernimmt
// Gemini aus Klang UND Gesprächslogik, daher kein Konflikt mit AGC.
function micConstraints(): MediaTrackConstraints {
  return {
    channelCount: 1,
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
  };
}

function formatDuration(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

const TARGET_RATE = 16000;
const CHUNK_SAMPLES = TARGET_RATE; // ~1 Sekunde je IPC-Paket

export function MeetingOverlay() {
  const [active, setActive] = useState(false);
  const [capturing, setCapturing] = useState(false); // erstes Mikro-Paket eingetroffen
  const [health, setHealth] = useState<HealthColor>('green');
  const [reason, setReason] = useState('');
  const [durationMs, setDurationMs] = useState(0);
  const [callActive, setCallActive] = useState(false);

  // Ein AudioContext für die Lebensdauer des (vorgeladenen, versteckten) Fensters: das Worklet-Modul
  // wird EINMAL geladen; pro Aufnahme kommen nur getUserMedia + Nodes dazu → kurze Startlatenz.
  const audioCtxRef = useRef<AudioContext | null>(null);
  const workletReadyRef = useRef<Promise<void> | null>(null);
  const workletNodeRef = useRef<AudioWorkletNode | null>(null);
  const srcNodeRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const pcmBufferRef = useRef<Float32Array>(new Float32Array(0));
  const captureGenRef = useRef(0);      // entwertet verspätete getUserMedia-Ergebnisse nach Stop
  const startingRef = useRef(false);
  const firstSampleSentRef = useRef(false);

  // System-Loopback-Capture (nur Windows; macOS nimmt System-Audio über AudioTee im Main auf)
  const sysWorkletRef = useRef<AudioWorkletNode | null>(null);
  const sysSrcRef = useRef<MediaStreamAudioSourceNode | null>(null);
  const sysStreamRef = useRef<MediaStream | null>(null);
  const sysPcmBufferRef = useRef<Float32Array>(new Float32Array(0));
  const isWindows = typeof navigator !== 'undefined' && /windows/i.test(navigator.userAgent);

  const ensureAudioContext = async (): Promise<AudioContext> => {
    if (!audioCtxRef.current) {
      const ctx = new AudioContext();
      audioCtxRef.current = ctx;
      workletReadyRef.current = ctx.audioWorklet.addModule(new URL('./mic-worklet.js', import.meta.url));
    }
    await workletReadyRef.current;
    const ctx = audioCtxRef.current!;
    if (ctx.state === 'suspended') { try { await ctx.resume(); } catch { /* egal */ } }
    return ctx;
  };

  const sendMicChunk = (f32: Float32Array) => {
    if (!f32.length) return;
    const int16 = floatToInt16(f32);
    window.electronAPI.sendMicPcm(int16.buffer as ArrayBuffer);
    window.electronAPI.sendMicLevel(rms(int16));
  };

  // Restpuffer (< 1 s) senden — beim Stop-Handshake, damit die letzten Worte nicht fehlen.
  const flushMic = () => {
    const rest = pcmBufferRef.current;
    pcmBufferRef.current = new Float32Array(0);
    sendMicChunk(rest);
  };

  const stopCapture = () => {
    captureGenRef.current++;
    startingRef.current = false;
    workletNodeRef.current?.disconnect();
    srcNodeRef.current?.disconnect();
    streamRef.current?.getTracks().forEach((t) => t.stop());
    workletNodeRef.current = null;
    srcNodeRef.current = null;
    streamRef.current = null;
    pcmBufferRef.current = new Float32Array(0);
    firstSampleSentRef.current = false;
    // AudioContext bleibt (Worklet-Modul vorgeladen); nur schlafen legen
    try { audioCtxRef.current?.suspend(); } catch { /* egal */ }
  };

  const startCapture = async () => {
    if (streamRef.current || startingRef.current) return; // Doppelstart (Push+Pull) vermeiden
    startingRef.current = true;
    const gen = captureGenRef.current;
    try {
      const ctx = await ensureAudioContext();
      const stream = await navigator.mediaDevices.getUserMedia({ audio: micConstraints() });
      if (gen !== captureGenRef.current) { stream.getTracks().forEach((t) => t.stop()); return; }
      streamRef.current = stream;

      const srcNode = ctx.createMediaStreamSource(stream);
      srcNodeRef.current = srcNode;
      const node = new AudioWorkletNode(ctx, 'mic-processor');
      workletNodeRef.current = node;
      srcNode.connect(node);

      node.port.onmessage = (e: MessageEvent<Float32Array>) => {
        const f32: Float32Array = e.data;
        if (!firstSampleSentRef.current) {
          // Wandzeit des ersten Samples — VOR dem ersten PCM-Paket (gleiche geordnete IPC-Kette),
          // damit der Main-Prozess die Startlücke exakt mit Stille auffüllen kann.
          firstSampleSentRef.current = true;
          window.electronAPI.sendMicCaptureStarted({ firstSampleAtMs: Date.now() - (f32.length / ctx.sampleRate) * 1000 });
          setCapturing(true);
        }
        const downsampled = downsample(f32, ctx.sampleRate, TARGET_RATE);
        const prev = pcmBufferRef.current;
        const merged = new Float32Array(prev.length + downsampled.length);
        merged.set(prev);
        merged.set(downsampled, prev.length);
        pcmBufferRef.current = merged;
        if (pcmBufferRef.current.length >= CHUNK_SAMPLES) {
          const chunk = pcmBufferRef.current.slice(0, CHUNK_SAMPLES);
          pcmBufferRef.current = pcmBufferRef.current.slice(CHUNK_SAMPLES);
          sendMicChunk(chunk);
        }
      };
    } catch (err) {
      console.error('MeetingOverlay: mic error', err);
    } finally {
      startingRef.current = false;
    }
  };

  const flushSystem = () => {
    const rest = sysPcmBufferRef.current;
    sysPcmBufferRef.current = new Float32Array(0);
    if (rest.length) window.electronAPI.sendSystemPcm(floatToInt16(rest).buffer as ArrayBuffer);
  };

  const stopSystemCapture = () => {
    sysWorkletRef.current?.disconnect();
    sysSrcRef.current?.disconnect();
    sysStreamRef.current?.getTracks().forEach((t) => t.stop());
    sysWorkletRef.current = null;
    sysSrcRef.current = null;
    sysStreamRef.current = null;
    sysPcmBufferRef.current = new Float32Array(0);
  };

  // Windows: System-Mix per Loopback abgreifen (Pendant zu AudioTee auf macOS).
  const startSystemCapture = async () => {
    if (!isWindows || sysStreamRef.current) return;
    try {
      const ctx = await ensureAudioContext();
      const stream = await navigator.mediaDevices.getDisplayMedia({ audio: true, video: true });
      stream.getVideoTracks().forEach((t) => { t.stop(); stream.removeTrack(t); });
      if (stream.getAudioTracks().length === 0) {
        stream.getTracks().forEach((t) => t.stop());
        console.error('MeetingOverlay: kein System-Audio-Track (Loopback)');
        return;
      }
      sysStreamRef.current = stream;
      const srcNode = ctx.createMediaStreamSource(stream);
      sysSrcRef.current = srcNode;
      const node = new AudioWorkletNode(ctx, 'mic-processor');
      sysWorkletRef.current = node;
      srcNode.connect(node);
      node.port.onmessage = (e: MessageEvent<Float32Array>) => {
        const downsampled = downsample(e.data, ctx.sampleRate, TARGET_RATE);
        const prev = sysPcmBufferRef.current;
        const merged = new Float32Array(prev.length + downsampled.length);
        merged.set(prev);
        merged.set(downsampled, prev.length);
        sysPcmBufferRef.current = merged;
        if (sysPcmBufferRef.current.length >= CHUNK_SAMPLES) {
          const chunk = sysPcmBufferRef.current.slice(0, CHUNK_SAMPLES);
          sysPcmBufferRef.current = sysPcmBufferRef.current.slice(CHUNK_SAMPLES);
          window.electronAPI.sendSystemPcm(floatToInt16(chunk).buffer as ArrayBuffer);
        }
      };
    } catch (err) {
      console.error('MeetingOverlay: system loopback error', err);
    }
  };

  useEffect(() => {
    // Worklet sofort vorladen (Fenster ist beim App-Start versteckt erzeugt)
    ensureAudioContext().then((ctx) => { try { ctx.suspend(); } catch { /* egal */ } }).catch(() => {});

    const unsubs: (() => void)[] = [];
    unsubs.push(window.electronAPI.onMeetingStarted((d) => {
      setActive(true);
      setCapturing(false);
      setHealth('green');
      setReason('');
      setDurationMs(0);
      setCallActive(!!(d && d.callActive));
      startCapture();
      startSystemCapture();
    }));

    // Stop-Handshake: Restpuffer senden, Capture beenden, Main bestätigen — erst dann schließt der
    // Main-Prozess die Aufnahme ab.
    unsubs.push(window.electronAPI.onMeetingCaptureStop(() => {
      flushMic();
      flushSystem();
      stopCapture();
      stopSystemCapture();
      window.electronAPI.captureFlushed().catch(() => {});
    }));

    unsubs.push(window.electronAPI.onMeetingStopped(() => {
      stopCapture();
      stopSystemCapture();
      setActive(false);
      setCapturing(false);
      setCallActive(false);
    }));

    unsubs.push(window.electronAPI.onMeetingCallState((d) => setCallActive(!!(d && d.active))));

    unsubs.push(window.electronAPI.onMeetingStatus((s: MeetingStatus) => {
      setHealth(s.color);
      setReason(s.reason);
      setDurationMs(s.durationMs);
    }));

    // Pull-Modell gegen die Start-Race: falls das 'meeting:started'-Push-Event verloren ging.
    window.electronAPI.getMeetingStatus().then((st) => {
      if (st && st.active) {
        setActive(true);
        setCallActive(!!st.callActive);
        startCapture();
        startSystemCapture();
      }
    });

    return () => {
      unsubs.forEach((u) => { try { u(); } catch { /* egal */ } });
      stopCapture();
      stopSystemCapture();
    };
  }, []);

  if (!active) return null;

  const dotClass = !capturing
    ? 'bg-gray-400 animate-pulse'
    : health === 'green' ? 'bg-green-500' : health === 'yellow' ? 'bg-yellow-500' : 'bg-red-500';
  const dotTitle = !capturing ? 'Mikrofon startet …' : health === 'green' ? 'Aufnahme läuft' : (reason || 'Hinweis');

  return (
    <div className="flex flex-col items-end justify-start h-screen p-1 gap-1">
      {/* Einziges kleines Pill: Mic · Status · Anruf-Indikator · Dauer · Stop */}
      <div
        className="flex items-center gap-2 px-2.5 py-1 rounded-full border shadow-md select-none"
        style={{ WebkitAppRegion: 'no-drag', backgroundColor: '#ffffff', borderColor: health === 'red' ? '#ef4444' : '#e2e8f0' } as React.CSSProperties}
      >
        <Mic className="w-4 h-4 text-muted-foreground flex-shrink-0" />
        <div className={cn('w-2 h-2 rounded-full flex-shrink-0', dotClass)} title={dotTitle} />
        {!capturing && <span className="text-[10px] text-muted-foreground">startet …</span>}
        {callActive && (
          <span className="flex items-center gap-0.5 text-[10px] font-medium text-green-600 flex-shrink-0" title="Anruf erkannt — die Gegenstelle wird mitgenommen">
            <Phone className="w-3 h-3" />
            Anruf
          </span>
        )}
        <span className="text-xs text-muted-foreground font-mono tabular-nums">{formatDuration(durationMs)}</span>
        <button
          className={cn('flex items-center justify-center w-4 h-4 rounded-sm', 'bg-destructive/80 hover:bg-destructive transition-colors', 'text-destructive-foreground')}
          style={{ WebkitAppRegion: 'no-drag' } as React.CSSProperties}
          onClick={(e) => { e.stopPropagation(); window.electronAPI.stopMeeting(); }}
          title="Meeting stoppen"
        >
          <span className="text-[8px] leading-none font-bold">■</span>
        </button>
      </div>

      {/* Gelb/Rot: Klartext-Grund (z.B. Mikro verspätet, fehlende Berechtigung) */}
      {capturing && health !== 'green' && reason && (
        <div
          className={cn('px-2 py-1 rounded-lg border text-[10px] max-w-[340px]', health === 'red' ? 'border-red-500/50 text-red-500' : 'border-yellow-500/50 text-yellow-700')}
          style={{ WebkitAppRegion: 'no-drag', backgroundColor: '#ffffff' } as React.CSSProperties}
        >
          {reason}
        </div>
      )}
    </div>
  );
}
