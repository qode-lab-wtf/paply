import { useCallback, useEffect, useRef, useState } from 'react';
import { startVoiceActivityMeasurement } from '@/lib/voice-activity-recorder';
import { createRecordingGeneration } from '@/lib/recording-generation';
import type { RecordingPillProps, PillStatus } from './RecordingPill';

const MIC_ERROR = 'Kein Mikrofonzugriff';

function playBeep(frequency: number, duration: number) {
  try {
    const ctx = new AudioContext();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.frequency.value = frequency;
    osc.type = 'sine';
    gain.gain.setValueAtTime(0.3, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + duration);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + duration);
    osc.onended = () => { void ctx.close(); };
  } catch { /* Audio feedback must not prevent recording. */ }
}

export function useDictationRecorder(): RecordingPillProps {
  const [status, setStatus] = useState<PillStatus>('empty');
  const [errorText, setErrorText] = useState<string | null>(null);
  const [infoText, setInfoText] = useState<string | null>(null);
  const [retryHotkey, setRetryHotkey] = useState('⌥⇧⌘R');
  const [platform, setPlatform] = useState<'mac' | 'win' | 'linux'>('mac');
  const [agentBadge, setAgentBadge] = useState<string | null>(null);
  const listeners = useRef(new Set<(level: number) => void>());
  const subscribeLevel = useCallback((cb: (level: number) => void) => {
    listeners.current.add(cb);
    return () => { listeners.current.delete(cb); };
  }, []);

  useEffect(() => {
    const api = window.electronAPI;
    const generation = createRecordingGeneration();
    let mounted = true;
    let micError = MIC_ERROR;
    let jobId: string | null = null;
    let badgeTimer: ReturnType<typeof setTimeout>;
    let session: { id: string; recorder: MediaRecorder; release: () => void; beep: boolean; discard: () => void } | null = null;
    const emitLevel = (level: number) => listeners.current.forEach(cb => cb(level));

    const cancel = (discard: boolean) => {
      generation.cancel();
      const active = session;
      session = null;
      if (!active) return false;
      if (discard) active.discard();
      // Freeze voice measurement before stopping tracks; onstop is asynchronous.
      active.release();
      if (active.recorder.state !== 'inactive') active.recorder.stop();
      if (!discard && active.beep) playBeep(400, 0.12);
      return true;
    };

    void api.getPlatform().then(value => {
      if (!mounted) return;
      setPlatform(value.isMac ? 'mac' : value.isWin ? 'win' : 'linux');
      micError = value.isMac
        ? 'Kein Mikrofonzugriff — Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon'
        : value.isWin
          ? 'Kein Mikrofonzugriff — Windows-Einstellungen → Datenschutz & Sicherheit → Mikrofon'
          : 'Kein Mikrofonzugriff — Mikrofon und Zugriffsrechte prüfen';
      setRetryHotkey(value.isMac ? '⌥⇧⌘R' : 'Ctrl+Alt+Shift+R');
    });

    const offStart = api.onRecordingStart(async ({ jobId: id }) => {
      cancel(true);
      jobId = id;
      const token = generation.begin();
      let beep = true;
      try { beep = (await api.getSettings()).beepEnabled !== false; } catch { /* default */ }
      if (!generation.isCurrent(token)) return;
      setErrorText(null);
      setInfoText(null);
      if (beep) playBeep(800, 0.12);
      setStatus('recording');
      let stream: MediaStream | null = null;
      let context: AudioContext | null = null;
      let frame: number | null = null;
      let measure: ReturnType<typeof startVoiceActivityMeasurement> | null = null;
      let voiceActivity: ReturnType<ReturnType<typeof startVoiceActivityMeasurement>> | undefined;
      let released = false;
      let discarded = false;
      let localRecorder: MediaRecorder | null = null;
      const release = () => {
        if (released) return;
        released = true;
        voiceActivity = measure?.();
        measure = null;
        stream?.getTracks().forEach(track => track.stop());
        if (frame !== null) cancelAnimationFrame(frame);
        if (context) void context.close().catch(() => {});
        emitLevel(0);
      };
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        if (!generation.acceptStream(token, stream)) return;
        context = new AudioContext();
        const analyser = context.createAnalyser();
        context.createMediaStreamSource(stream).connect(analyser);
        analyser.fftSize = 32;
        const levels = new Uint8Array(analyser.frequencyBinCount);
        let smoothed = 0;
        const draw = () => {
          analyser.getByteFrequencyData(levels);
          const level = levels.slice(2, 7).reduce((sum, value) => sum + value, 0) / (5 * 255);
          smoothed += (level - smoothed) * 0.4;
          emitLevel(smoothed);
          frame = requestAnimationFrame(draw);
        };
        draw();
        const preferred = 'audio/webm;codecs=opus';
        const mimeType = MediaRecorder.isTypeSupported(preferred) ? preferred : undefined;
        const recorder = new MediaRecorder(stream, mimeType ? { mimeType, audioBitsPerSecond: 128000 } : undefined);
        localRecorder = recorder;
        // Chunks and measurement belong to this session, never to a shared ref.
        const chunks: Blob[] = [];
        recorder.ondataavailable = event => { if (event.data.size) chunks.push(event.data); };
        recorder.onstop = async () => {
          release();
          if (discarded || !mounted) return;
          try {
            const audio = await new Blob(chunks, { type: recorder.mimeType || 'audio/webm' }).arrayBuffer();
            if (mounted) api.sendAudio(audio, voiceActivity, id);
          } catch {
            api.recordingFailed(id, 'Aufnahme konnte nicht gelesen werden');
          }
        };
        recorder.onerror = () => {
          discarded = true;
          release();
          if (generation.isCurrent(token)) {
            cancel(true);
            setStatus('error');
            setErrorText(micError);
            api.recordingFailed(id, micError);
          }
        };
        recorder.start(1000);
        measure = startVoiceActivityMeasurement(analyser);
        session = { id, recorder, release, beep, discard: () => { discarded = true; } };
        api.recordingStarted(id);
      } catch {
        discarded = true;
        release();
        if (localRecorder && localRecorder.state !== 'inactive') localRecorder.stop();
        if (!generation.isCurrent(token)) return;
        cancel(true);
        setStatus('error');
        setErrorText(micError);
        api.recordingFailed(id, micError);
      }
    });

    const offStop = api.onRecordingStop(({ jobId: id }) => {
      if (id !== jobId) return;
      setStatus(cancel(false) ? 'processing' : 'empty');
    });
    const offStatus = api.onStatusUpdate(update => {
      // Main only publishes the current job; a retry may establish a new ID.
      if (update.jobId) jobId = update.jobId;
      setStatus(update.status === 'transcribing' ? 'processing' : update.status);
      setErrorText(update.status === 'error' ? update.detail || 'Diktat fehlgeschlagen' : null);
      setInfoText(update.status === 'done' ? update.detail || null : null);
    });
    const offRetry = api.onErrorRetry(data => {
      if (data.jobId && data.jobId !== jobId) return;
      setStatus('error');
      setErrorText(data.message);
      setRetryHotkey(data.hotkey);
    });
    const offBadge = api.onAgentSwitched(({ name }) => {
      clearTimeout(badgeTimer);
      setAgentBadge(name);
      badgeTimer = setTimeout(() => setAgentBadge(null), 1200);
    });
    return () => {
      mounted = false;
      cancel(true);
      clearTimeout(badgeTimer);
      offStart(); offStop(); offStatus(); offRetry(); offBadge();
    };
  }, []);

  return { status, subscribeLevel, errorText, infoText, retryHotkey, agentBadge, platform };
}
