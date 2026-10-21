import { useEffect, useRef } from 'react';
import { Mic, Check, X } from 'lucide-react';
import { cn } from '@/lib/utils';

export type PillStatus = 'recording' | 'processing' | 'polishing' | 'done' | 'empty' | 'error' | 'leaving';
export interface RecordingPillProps {
  status: PillStatus;
  /** Live-Mikrofonpegel 0..1 (geglättet), ohne React-Re-Render. */
  subscribeLevel: (cb: (level: number) => void) => () => void;
  errorText?: string | null;
  infoText?: string | null;
  retryHotkey: string;
  agentBadge?: string | null;
  platform: 'mac' | 'win' | 'linux';
}

export function RecordingPill({ status, subscribeLevel, errorText, infoText, retryHotkey, agentBadge }: RecordingPillProps) {
  const barsRef = useRef<(HTMLDivElement | null)[]>([]);
  useEffect(() => subscribeLevel(level => {
    barsRef.current.forEach(bar => { if (bar) bar.style.height = `${Math.max(4, level * 24)}px`; });
  }), [subscribeLevel]);
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
          'flex items-center gap-2 px-3 py-2 rounded-2xl backdrop-blur-xl border shadow-lg transition-opacity duration-200',
          status === 'leaving' && 'opacity-0',
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
            status === 'empty' && 'opacity-40',
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

        {infoText && <span className="text-xs text-muted-foreground">{infoText}</span>}

        {/* Error with retry hint */}
        {status === 'error' && (
          <div className="flex items-center gap-2">
            <span className="text-xs text-destructive">{errorText || 'Diktat fehlgeschlagen'}</span>
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

