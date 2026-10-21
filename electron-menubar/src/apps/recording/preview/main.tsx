// Entwickler-Vorschau aller Pillen-Zustände – nur über `npm run dev:vite` → /pill-preview.html,
// nicht Teil des Produktions-Builds (vite.config.ts listet die Seite nicht).
import React, { useEffect, useMemo, useState } from 'react';
import ReactDOM from 'react-dom/client';
import { RecordingPill, type PillStatus, type RecordingPillProps } from '../RecordingPill';
import { playStartSound, playStopSound } from '@/lib/sounds';

// Simulierter Sprachpegel (Silben ~4 Hz, Phrasen mit Pausen)
function createFakeLevel() {
  const subs = new Set<(l: number) => void>();
  let speaking = true;
  let phraseEnd = 0;
  const loop = (t: number) => {
    if (t > phraseEnd) {
      speaking = !speaking;
      phraseEnd = t + (speaking ? 900 + Math.random() * 1500 : 200 + Math.random() * 400);
    }
    const syl = Math.abs(Math.sin((t / 1000) * Math.PI * 4.2 + Math.sin(t / 770) * 2.2));
    const l = speaking ? 0.22 + 0.78 * syl ** 1.4 * (0.65 + 0.35 * Math.random()) : 0.04 * Math.random();
    subs.forEach((cb) => cb(l));
    requestAnimationFrame(loop);
  };
  requestAnimationFrame(loop);
  return (cb: (l: number) => void) => {
    subs.add(cb);
    return () => subs.delete(cb);
  };
}
const subscribeLevel = createFakeLevel();

type Case = { title: string; props: Partial<RecordingPillProps> & { status: PillStatus } };
const CASES: Case[] = [
  { title: 'recording', props: { status: 'recording' } },
  { title: 'processing', props: { status: 'processing' } },
  { title: 'polishing', props: { status: 'polishing' } },
  { title: 'done', props: { status: 'done' } },
  { title: 'done + infoText', props: { status: 'done', infoText: 'In Zwischenablage kopiert' } },
  { title: 'empty', props: { status: 'empty' } },
  { title: 'error (mac)', props: { status: 'error', errorText: 'Keine Verbindung zu Groq' } },
  { title: 'error lang (win)', props: { status: 'error', platform: 'win', retryHotkey: 'Ctrl+Alt+Shift+R', errorText: 'Groq-Schlüssel ungültig — in den Einstellungen prüfen' } },
  { title: 'agent', props: { status: 'leaving', agentBadge: 'Coding' } },
  { title: 'leaving', props: { status: 'leaving' } },
];

function Frame({ c }: { c: Case }) {
  return (
    <figure style={{ margin: 0 }}>
      <div className="frame">
        <RecordingPill retryHotkey="⌥⇧⌘R" platform="mac" subscribeLevel={subscribeLevel} {...c.props} />
      </div>
      <figcaption>{c.title}</figcaption>
    </figure>
  );
}

const FLOW: [PillStatus, number, (() => void)?][] = [
  ['recording', 3200, playStartSound],
  ['processing', 1300, playStopSound],
  ['polishing', 1300],
  ['done', 900],
  ['leaving', 1200],
  ['recording', 1600, playStartSound],
  ['processing', 800, playStopSound],
  ['empty', 1300],
  ['leaving', 1000],
  ['recording', 1400, playStartSound],
  ['processing', 800, playStopSound],
  ['error', 2600],
  ['leaving', 800],
];

function Live() {
  const [i, setI] = useState(-1);
  useEffect(() => {
    if (i < 0) return;
    if (i >= FLOW.length) return setI(-1);
    FLOW[i][2]?.();
    const t = setTimeout(() => setI(i + 1), FLOW[i][1]);
    return () => clearTimeout(t);
  }, [i]);
  const status = i >= 0 && i < FLOW.length ? FLOW[i][0] : 'leaving';
  return (
    <div style={{ display: 'flex', gap: 16, alignItems: 'center', marginBottom: 24 }}>
      <button onClick={() => setI(0)}>▶ Ablauf (mit Tönen)</button>
      <div className="frame">
        <RecordingPill status={status} retryHotkey="⌥⇧⌘R" platform="mac" errorText="Keine Verbindung zu Groq" subscribeLevel={subscribeLevel} />
      </div>
      <code>{status}</code>
    </div>
  );
}

function App() {
  const cases = useMemo(() => CASES, []);
  return (
    <div className="page">
      <style>{`
        .page { min-height: 100vh; padding: 24px; font: 13px system-ui; background: #d9dee6; color: #222; }
        @media (prefers-color-scheme: dark) { .page { background: #10141a; color: #ddd; } }
        .frame { position: relative; width: 320px; height: 88px; transform: translateZ(0); outline: 1px dashed rgb(128 128 128 / .5); }
        .grid { display: grid; grid-template-columns: repeat(2, 320px); gap: 18px 28px; }
        figcaption { font-size: 11px; opacity: .6; margin-top: 4px; }
      `}</style>
      <Live />
      <div className="grid">{cases.map((c) => <Frame key={c.title} c={c} />)}</div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
