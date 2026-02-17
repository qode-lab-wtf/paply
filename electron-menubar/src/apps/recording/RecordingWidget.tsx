import { useEffect, useRef, useState } from 'react';
import { Mic, Check, X, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';

type Status = 'idle' | 'recording' | 'processing' | 'polishing' | 'done' | 'error';

export function RecordingWidget() {
  const [status, setStatus] = useState<Status>('idle');
  const [retryHotkey, setRetryHotkey] = useState('⌥⇧⌘R');
  const [agentBadge, setAgentBadge] = useState<string | null>(null);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const animationIdRef = useRef<number | null>(null);
  const barsRef = useRef<(HTMLDivElement | null)[]>([]);
  const beepEnabledRef = useRef(true);

  useEffect(() => {
    // Init platform-specific hotkey
    window.electronAPI.getPlatform().then((platform) => {
      setRetryHotkey(platform.isMac ? '⌥⇧⌘R' : 'Ctrl+Alt+Shift+R');
    });

    // Listen for recording events
    window.electronAPI.onRecordingStart(async () => {
      try {
        const settings = await window.electronAPI.getSettings();
        beepEnabledRef.current = settings.beepEnabled !== false;
      } catch {
        beepEnabledRef.current = true;
      }
      if (beepEnabledRef.current) playBeep(800, 0.12);
      setStatus('recording');
      startRecording();
    });

    window.electronAPI.onRecordingStop(() => {
      stopRecording();
    });

    window.electronAPI.onStatusUpdate(({ status: newStatus }) => {
      if (newStatus === 'transcribing') setStatus('processing');
      else if (newStatus === 'polishing') setStatus('polishing');
      else if (newStatus === 'done') setStatus('done');
      else if (newStatus === 'error') setStatus('error');
    });

    window.electronAPI.onAgentSwitched(({ name }) => {
      setAgentBadge(name);
      setTimeout(() => setAgentBadge(null), 1200);
    });
  }, []);

  const playBeep = (frequency: number, duration: number) => {
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
      osc.onended = () => ctx.close();
    } catch (e) {
      console.error('Beep failed', e);
    }
  };

  const startVisualization = (stream: MediaStream) => {
    audioContextRef.current = new AudioContext();
    analyserRef.current = audioContextRef.current.createAnalyser();
    const source = audioContextRef.current.createMediaStreamSource(stream);
    source.connect(analyserRef.current);
    analyserRef.current.fftSize = 32;
    const dataArray = new Uint8Array(analyserRef.current.frequencyBinCount);

    const draw = () => {
      animationIdRef.current = requestAnimationFrame(draw);
      analyserRef.current?.getByteFrequencyData(dataArray);

      barsRef.current.forEach((bar, i) => {
        if (bar) {
          const value = dataArray[i + 2] || 0;
          const height = Math.max(4, (value / 255) * 24);
          bar.style.height = `${height}px`;
        }
      });
    };
    draw();
  };

  const stopVisualization = () => {
    if (animationIdRef.current) {
      cancelAnimationFrame(animationIdRef.current);
      animationIdRef.current = null;
    }
    if (audioContextRef.current) {
      audioContextRef.current.close();
      audioContextRef.current = null;
    }
    barsRef.current.forEach((bar) => {
      if (bar) bar.style.height = '4px';
    });
  };

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      startVisualization(stream);

      const preferredType = 'audio/webm;codecs=opus';
      const mimeType = MediaRecorder.isTypeSupported(preferredType)
        ? preferredType
        : undefined;

      const recorder = new MediaRecorder(
        stream,
        mimeType ? { mimeType, audioBitsPerSecond: 128000 } : undefined
      );
      audioChunksRef.current = [];

      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) {
          audioChunksRef.current.push(e.data);
        }
      };

      recorder.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop());
        stopVisualization();

        if (audioChunksRef.current.length === 0) return;

        const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/webm' });
        const arrayBuffer = await audioBlob.arrayBuffer();
        window.electronAPI.sendAudio(arrayBuffer);
      };

      recorder.start(1000);
      mediaRecorderRef.current = recorder;
    } catch (err) {
      console.error('Mic error:', err);
      setStatus('error');
    }
  };

  const stopRecording = () => {
    if (
      mediaRecorderRef.current &&
      mediaRecorderRef.current.state !== 'inactive'
    ) {
      mediaRecorderRef.current.stop();
      if (beepEnabledRef.current) playBeep(400, 0.12);
      setStatus('processing');
    }
  };

  return (
    <div className="flex items-center justify-center h-screen">
      {/* Agent Badge */}
      {agentBadge && (
        <div className="fixed inset-0 flex items-center justify-center z-50 animate-fade-in">
          <div className="bg-primary text-primary-foreground px-4 py-2 rounded-full text-sm font-medium shadow-lg">
            {agentBadge}
          </div>
        </div>
      )}

      {/* Widget */}
      <div
        className={cn(
          'flex items-center gap-2 px-3 py-2 rounded-2xl backdrop-blur-xl border shadow-lg',
          'bg-card/95 border-border/50',
          status === 'recording' && 'border-primary/50',
          status === 'error' && 'border-destructive/50'
        )}
      >
        {/* Icon */}
        <div
          className={cn(
            'w-8 h-8 rounded-lg flex items-center justify-center',
            'bg-gradient-to-br from-primary to-primary/80',
            status === 'processing' && 'animate-pulse',
            status === 'error' && 'bg-gradient-to-br from-destructive to-destructive/80'
          )}
        >
          {status === 'done' ? (
            <Check className="w-4 h-4 text-primary-foreground" />
          ) : status === 'error' ? (
            <X className="w-4 h-4 text-destructive-foreground" />
          ) : (
            <Mic className="w-4 h-4 text-primary-foreground" />
          )}
        </div>

        {/* Visualizer (recording) */}
        {status === 'recording' && (
          <div className="flex items-center gap-0.5 h-6">
            {[0, 1, 2, 3, 4].map((i) => (
              <div
                key={i}
                ref={(el) => { barsRef.current[i] = el; }}
                className="w-0.5 bg-gradient-to-t from-primary to-primary/60 rounded-full transition-all duration-50"
                style={{ height: '4px' }}
              />
            ))}
          </div>
        )}

        {/* Processing dots */}
        {(status === 'processing' || status === 'polishing') && (
          <div className="flex items-center gap-1">
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                className={cn(
                  'w-1 h-1 rounded-full animate-bounce',
                  status === 'polishing' ? 'bg-purple-400' : 'bg-primary'
                )}
                style={{ animationDelay: `${i * 0.2}s` }}
              />
            ))}
          </div>
        )}

        {/* Done checkmark */}
        {status === 'done' && (
          <Check className="w-5 h-5 text-primary animate-fade-in" />
        )}

        {/* Error with retry hint */}
        {status === 'error' && (
          <div className="flex items-center gap-2">
            <X className="w-4 h-4 text-destructive" />
            <span className="text-xs text-muted-foreground">
              <kbd className="px-1 py-0.5 rounded bg-muted text-xs font-mono">
                {retryHotkey}
              </kbd>
            </span>
          </div>
        )}
      </div>
    </div>
  );
}

