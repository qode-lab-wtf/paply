import { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Camera, Check, Square, Pause, AlertCircle } from 'lucide-react';
import { PaplyMark } from '@/components/brand/PaplyMark';
import type { CaptureState } from '@/types/notes';
import workletUrl from './pcm-worklet.js?url&no-inline';
import './pill.css';

type Run = { entryId: string; epoch: number; seq: number; stream?: MediaStream; context?: AudioContext; node?: AudioWorkletNode; chain: Promise<unknown>; pending: number; stop: boolean };
function NotesPill() {
  const [state, setState] = useState<CaptureState>({ phase: 'idle', entryId: null, epoch: 0 });
  const [time, setTime] = useState(0), [level, setLevel] = useState(0), [error, setError] = useState('');
  useEffect(() => {
    const api = window.paplyNotesCapture; let current: Run|null = null, base = 0, started = 0;
    const close = (r: Run) => { r.stream?.getTracks().forEach(t => t.stop()); r.node?.disconnect(); r.context?.close().catch(() => {}); };
    const cancel = () => { if (current) close(current); current = null; };
    async function begin(s: CaptureState) {
      cancel(); if (!s.entryId) return;
      const run: Run = { entryId: s.entryId, epoch: s.epoch, seq: 0, chain: Promise.resolve(), pending: 0, stop: false }; current = run;
      base = s.elapsedMs || 0; started = performance.now(); setError('');
      try {
        run.stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: false });
        if (current !== run) { close(run); return; }
        // Device-rate context avoids Chromium's silent-input regression with
        // forced 16 kHz. The worklet resamples continuously across render quanta.
        run.context = new AudioContext();
        await run.context.audioWorklet.addModule(workletUrl);
        if (current !== run) { close(run); return; }
        run.node = new AudioWorkletNode(run.context, 'paply-notes-pcm');
        run.node.port.onmessage = e => {
          if (current !== run) return;
          if (e.data.type === 'pcm') {
            setLevel(e.data.level); run.pending++;
            if (run.pending > 8) { cancel(); api.failed({ entryId: run.entryId }).catch(() => {}); return; }
            const seq = ++run.seq;
            run.chain = run.chain.then(() => api.pcm({ entryId: run.entryId, epoch: run.epoch, seq, bytes: e.data.bytes })).then(() => { run.pending--; }).catch(() => { if (current === run) { cancel(); api.failed({ entryId: run.entryId }).catch(() => {}); } });
          } else if (e.data.type === 'flushed') {
            close(run); run.chain.then(() => { if (current === run) { current = null; api.flushed({ entryId: run.entryId, epoch: run.epoch }).catch(() => {}); } });
          }
        };
        const mic = run.context.createMediaStreamSource(run.stream), mute = run.context.createGain(); mute.gain.value = 0;
        mic.connect(run.node); run.node.connect(mute); mute.connect(run.context.destination); await run.context.resume();
        if (run.stop) run.node.port.postMessage('flush');
      } catch { close(run); if (current === run) { current = null; api.failed({ entryId: run.entryId }).catch(() => {}); } }
    }
    function receive(s: CaptureState) {
      setState(s);
      if (s.phase === 'start' || s.phase === 'resume') void begin(s);
      else if (s.phase === 'stop') { if (current) { current.stop = true; current.node?.port.postMessage('flush'); } else if (s.entryId) api.flushed({ entryId: s.entryId, epoch: s.epoch }).catch(() => {}); }
      else if (['paused', 'abort', 'error', 'saved', 'refused'].includes(s.phase)) { cancel(); started = 0; base = s.elapsedMs || base; setTime(base); }
    }
    const unsubscribe = api.onState(receive); api.ready().then(receive).catch(() => {});
    const timer = setInterval(() => { if (started && current) setTime(base + performance.now() - started); }, 200);
    return () => { unsubscribe(); clearInterval(timer); cancel(); };
  }, []);
  const active = ['start', 'recording', 'resume', 'paused', 'stop'].includes(state.phase);
  const label = error || state.detail || (state.phase === 'saved' ? 'Gedanke gesichert' : state.phase === 'paused' ? 'Pausiert · Diktat' : state.phase === 'stop' ? 'Sichern …' : 'Gedanke');
  return <div className={`notes-pill ${active ? 'active' : ''} ${state.phase === 'paused' ? 'paused' : ''}`} style={{ '--voice': Math.min(1, level * 4) } as React.CSSProperties}>
    <div className="notes-aura"/><div className="notes-shell"><div className="notes-orb"><PaplyMark size={29}/></div>
    <div className="notes-pill-label"><span>{label}</span>{active && <small>{String(Math.floor(time / 60000)).padStart(2, '0')}:{String(Math.floor(time / 1000) % 60).padStart(2, '0')}</small>}</div>
    {active ? <><button title="Bildschirm jetzt merken" aria-label="Bildschirm jetzt merken" className={state.hasImage ? 'captured' : ''} onClick={() => window.paplyNotesCapture.camera().catch(() => setError('Bildschirmzugriff fehlt'))}><Camera size={17}/></button><button title="Gedanke sichern" aria-label="Gedanke sichern" onClick={() => window.paplyNotesCapture.stop()}>{state.phase === 'paused' ? <Pause size={15}/> : <Square size={13} fill="currentColor"/>}</button></> : state.phase === 'error' || state.phase === 'refused' ? <AlertCircle size={17}/> : <Check size={18}/>}
    </div></div>;
}
createRoot(document.getElementById('root')!).render(<NotesPill/>);
