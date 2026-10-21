import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { PaplyMark } from '@/components/brand/PaplyMark';
import './recording-pill.css';

export type PillStatus = 'recording' | 'processing' | 'polishing' | 'done' | 'empty' | 'error' | 'leaving';

export interface RecordingPillProps {
  status: PillStatus;
  /** Live-Mikrofonpegel 0..1 (geglättet). Abonnement, damit die Pille mit 60 fps ohne React-Re-Render animieren kann. */
  subscribeLevel: (cb: (level: number) => void) => () => void;
  errorText?: string | null; // kurze, verständliche Fehlermeldung
  infoText?: string | null; // z. B. „In Zwischenablage kopiert“
  retryHotkey: string; // '⌥⇧⌘R' bzw. 'Ctrl+Alt+Shift+R'
  agentBadge?: string | null; // kurz eingeblendeter Agent-Name
  platform: 'mac' | 'win' | 'linux';
}

// Maße der Pille „Echo“ (Fenster: 272 × 64, siehe createRecordingWindow in electron-main.js)
const ORB = 32;
const GAP = 8;
const PAD_RIGHT = 12;

/** Feder (Steifigkeit k, Dämpfung c) als CSS-`linear()`-Easing + Dauer in ms. */
function spring(k: number, c: number) {
  let x = 0;
  let v = 0;
  let t = 0;
  const dt = 1 / 2000;
  const samples: number[] = [];
  while (t < 2) {
    v += (-k * (x - 1) - c * v) * dt;
    x += v * dt;
    t += dt;
    samples.push(x);
    if (t > 0.08 && Math.abs(x - 1) < 0.002 && Math.abs(v) < 0.03) break;
  }
  const n = 32;
  const pts = Array.from({ length: n + 1 }, (_, i) => +samples[Math.round((i / n) * (samples.length - 1))].toFixed(3));
  pts[0] = 0;
  pts[n] = 1;
  return { easing: `linear(${pts.join(', ')})`, duration: Math.round(t * 1000) };
}
const BOUNCY = spring(520, 24);
const SMOOTH = spring(420, 30);

// Unregelmäßige Klangwolke (statisch) – bewegt wird sie nur per transform (rotate/scale)
function blobPath(seed: number) {
  const pts: string[] = [];
  for (let i = 0; i < 48; i++) {
    const a = (i / 48) * Math.PI * 2;
    const r = 16 * (1 + 0.09 * Math.sin(3 * a + seed) + 0.05 * Math.sin(5 * a + seed * 2.1) + 0.03 * Math.sin(7 * a));
    pts.push(`${(Math.cos(a) * r).toFixed(2)} ${(Math.sin(a) * r).toFixed(2)}`);
  }
  return `M${pts.join('L')}Z`;
}
const BLOB_A = blobPath(0.4);
const BLOB_B = blobPath(2.2);

const prefersReducedMotion = () =>
  typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;

const formatTime = (ms: number) => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

/** Nur Anzeige: unter Windows heißt Ctrl auf deutschen Tastaturen „Strg“. */
export const displayHotkey = (hotkey: string, platform: RecordingPillProps['platform']) =>
  platform === 'win' ? hotkey.replace(/\bCtrl\b/g, 'Strg') : hotkey;

type Visual = Exclude<PillStatus, 'leaving'> | 'agent';

export function RecordingPill({ status, subscribeLevel, errorText, infoText, retryHotkey, agentBadge, platform }: RecordingPillProps) {
  // Beim Abgang den letzten Inhalt stehen lassen, damit nichts springt
  const lastVisible = useRef<Exclude<PillStatus, 'leaving'>>('recording');
  if (status !== 'leaving') lastVisible.current = status;
  const visual: Visual = agentBadge ? 'agent' : lastVisible.current;
  const hidden = status === 'leaving' && !agentBadge;

  const shakerRef = useRef<HTMLDivElement>(null);
  const pillRef = useRef<HTMLDivElement>(null);
  const labelRef = useRef<HTMLDivElement>(null);
  const timerRef = useRef<HTMLSpanElement>(null);
  const blobARef = useRef<SVGGElement>(null);
  const blobBRef = useRef<SVGGElement>(null);
  const ripplesRef = useRef<HTMLDivElement>(null);
  const orbRef = useRef<HTMLDivElement>(null);
  const levelRef = useRef(0);
  const recStartRef = useRef(0);
  const prevRef = useRef<{ hidden: boolean; visual: Visual | null }>({ hidden: true, visual: null });
  const [width, setWidth] = useState(ORB);

  // ── Label je Zustand ──
  let label: ReactNode = null;
  let labelKey = visual as string;
  if (visual === 'recording') {
    label = <span ref={timerRef} className="pp-timer">00:00</span>;
  } else if (visual === 'done' && infoText) {
    label = <span className="pp-text" title={infoText}>{infoText}</span>;
    labelKey += infoText;
  } else if (visual === 'empty') {
    const text = infoText || 'Nichts gehört';
    label = <span className="pp-text pp-muted" title={text}>{text}</span>;
    labelKey += text;
  } else if (visual === 'error') {
    const text = errorText || 'Das hat nicht geklappt';
    label = (
      <span className="pp-two">
        <span className="pp-text pp-strong" title={text}>{text}</span>
        <span className="pp-retry">Nochmal: <kbd>{displayHotkey(retryHotkey, platform)}</kbd></span>
      </span>
    );
    labelKey += text + retryHotkey + platform;
  } else if (visual === 'agent') {
    label = (
      <span className="pp-agent">
        <span className="pp-muted pp-small">Agent</span>
        <span className="pp-text pp-strong" title={agentBadge ?? ''}>{agentBadge}</span>
      </span>
    );
    labelKey += agentBadge;
  }

  // ── Breite = Orb + Label (gemessen), federnd per CSS-Transition ──
  useLayoutEffect(() => {
    const w = label && labelRef.current ? ORB + GAP + Math.ceil(labelRef.current.offsetWidth) + PAD_RIGHT : ORB;
    setWidth(hidden ? ORB : w);
  }, [labelKey, hidden]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Ein-/Ausblenden und Zustands-Akzente (Web Animations API, nur transform/opacity) ──
  useEffect(() => {
    const prev = prevRef.current;
    const el = shakerRef.current;
    const reduced = prefersReducedMotion();
    if (el && prev.hidden && !hidden) {
      el.animate(
        reduced
          ? [{ opacity: 0 }, { opacity: 1 }]
          : [
              { opacity: 0, transform: 'translateY(10px) scale(0.62)', filter: 'blur(5px)' },
              { opacity: 1, transform: 'none', filter: 'blur(0)' },
            ],
        reduced ? { duration: 150, easing: 'linear' } : { duration: BOUNCY.duration, easing: BOUNCY.easing },
      );
    }
    if (!hidden && !reduced && el && prev.visual !== visual) {
      if (visual === 'error') {
        el.animate(
          [0, -7, 6, -4, 2, 0].map((x) => ({ transform: `translateX(${x}px)` })),
          { duration: 440, easing: 'cubic-bezier(.3,.7,.4,1)', composite: 'add' },
        );
      } else if (visual === 'done') {
        el.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.06)' }, { transform: 'scale(1)' }], {
          duration: 380,
          easing: 'cubic-bezier(.3,.7,.4,1)',
          composite: 'add',
        });
      } else if (visual === 'agent') {
        orbRef.current?.animate([{ transform: 'rotateY(0)' }, { transform: 'rotateY(360deg)' }], {
          duration: 560,
          easing: 'cubic-bezier(.4,0,.2,1)',
        });
      }
    }
    if (visual === 'recording' && (prev.visual !== 'recording' || prev.hidden)) {
      recStartRef.current = performance.now();
      if (timerRef.current) timerRef.current.textContent = '00:00';
    }
    prevRef.current = { hidden, visual };
  }, [hidden, visual]);

  // ── Pegel abonnieren (kein Re-Render) ──
  useEffect(() => subscribeLevel((l) => { levelRef.current = l; }), [subscribeLevel]);

  // ── 60-fps-Schleife nur während der Aufnahme: Klangwolke, Echo-Ringe, Timer ──
  useEffect(() => {
    if (visual !== 'recording' || hidden) return;
    const reduced = prefersReducedMotion();
    let raf = 0;
    let smooth = 0;
    let lastRipple = 0;
    let lastSecond = -1;
    const tick = (t: number) => {
      raf = requestAnimationFrame(tick);
      const target = Math.min(1, Math.max(0, levelRef.current || 0));
      smooth += (target - smooth) * (target > smooth ? 0.5 : 0.14);
      const a = blobARef.current;
      const b = blobBRef.current;
      if (a && b) {
        if (reduced) {
          a.style.transform = `scale(${1 + smooth * 0.18})`;
          b.style.transform = 'scale(1)';
        } else {
          a.style.transform = `rotate(${(t * 0.045) % 360}deg) scale(${1 + smooth * 0.5})`;
          b.style.transform = `rotate(${(-t * 0.032) % 360}deg) scale(${1 + smooth * 0.36})`;
        }
        a.style.opacity = String(0.22 + smooth * 0.2);
        b.style.opacity = String(0.16 + smooth * 0.16);
      }
      // Echo-Ring bei Silben-Spitzen
      if (!reduced && smooth > 0.58 && t - lastRipple > 420 && ripplesRef.current && ripplesRef.current.childElementCount < 3) {
        lastRipple = t;
        const ring = document.createElement('span');
        ring.className = 'pp-ripple';
        ripplesRef.current.appendChild(ring);
        ring.animate(
          [
            { transform: 'scale(1)', opacity: 0.7 },
            { transform: 'scale(1.62)', opacity: 0 },
          ],
          { duration: 760, easing: 'cubic-bezier(.2,.7,.3,1)' },
        ).onfinish = () => ring.remove();
      }
      const elapsed = performance.now() - recStartRef.current;
      const sec = Math.floor(elapsed / 1000);
      if (sec !== lastSecond && timerRef.current) {
        lastSecond = sec;
        timerRef.current.textContent = formatTime(elapsed);
      }
    };
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      if (blobARef.current) blobARef.current.style.transform = 'scale(1)';
      if (blobBRef.current) blobBRef.current.style.transform = 'scale(1)';
    };
  }, [visual, hidden]);

  return (
    <div className="pp-root" data-platform={platform}>
      <div ref={shakerRef} className="pp-shaker">
        <div
          ref={pillRef}
          className="pp-pill"
          data-status={visual}
          data-hidden={hidden || undefined}
          style={{ width, ['--pp-spring' as string]: SMOOTH.easing, ['--pp-spring-ms' as string]: `${SMOOTH.duration}ms` }}
          role="status"
          aria-live="polite"
        >
          <div className="pp-orb-wrap">
            <svg className="pp-cloud" viewBox="-32 -32 64 64" aria-hidden>
              <g ref={blobBRef} className="pp-blob"><path d={BLOB_B} /></g>
              <g ref={blobARef} className="pp-blob"><path d={BLOB_A} /></g>
            </svg>
            <div ref={ripplesRef} className="pp-ripples" aria-hidden />
            <span className="pp-ring" aria-hidden />
            <div ref={orbRef} className="pp-orb">
              <PaplyMark size={17} className="pp-ico pp-ico-mark" />
              <svg className="pp-ico pp-ico-done" width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden>
                <path d="M3.5 8.4 6.6 11.4 12.6 4.8" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              <span className="pp-ico pp-ico-error" aria-hidden>!</span>
              <span className="pp-ico pp-ico-empty" aria-hidden><i /></span>
            </div>
          </div>
          <div className="pp-label-clip">
            {label ? (
              <div key={labelKey} ref={labelRef} className="pp-label">
                {label}
              </div>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}
