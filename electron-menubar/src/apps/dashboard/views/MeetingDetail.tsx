import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, RefreshCw, Play, Copy, Download, Phone, AlertTriangle, Users, Sparkles } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import { normalizeSummary, summaryToMarkdown, formatTime } from '@/lib/meeting-summary';
import type { MeetingFull, MeetingTodo } from '@/types/meeting';

interface MeetingDetailProps {
  id: string;
  onBack: () => void;
}

function formatDuration(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  return h > 0 ? `${h} h ${m} min` : `${m} min`;
}

export function MeetingDetail({ id, onBack }: MeetingDetailProps) {
  const [meeting, setMeeting] = useState<MeetingFull | null>(null);
  const [loading, setLoading] = useState(true);
  const [regenerating, setRegenerating] = useState(false);
  const [speakerNames, setSpeakerNames] = useState<Record<string, string>>({});
  const [todos, setTodos] = useState<MeetingTodo[]>([]);
  const [msg, setMsg] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const micAudioRef = useRef<HTMLAudioElement | null>(null);
  const sysAudioRef = useRef<HTMLAudioElement | null>(null);

  const load = async (silent = false) => {
    if (!silent) setLoading(true);
    try {
      const data = await window.electronAPI.getMeeting(id);
      setMeeting(data);
      setTodos(normalizeSummary(data?.summary)?.todos ?? []);
      setSpeakerNames({});
    } finally {
      if (!silent) setLoading(false);
    }
  };

  useEffect(() => {
    load();
    const unsub = window.electronAPI.onMeetingsUpdated((d) => { if (d && d.id === id) load(true); });
    return () => { try { unsub(); } catch { /* egal */ } };
  }, [id]);

  const handleToggleTodo = async (idx: number) => {
    setTodos((prev) => prev.map((t, i) => (i === idx ? { ...t, erledigt: !t.erledigt } : t)));
    await window.electronAPI.toggleMeetingTodo(id, idx);
  };

  const handleRegenerateSummary = async () => {
    setRegenerating(true);
    setMsg(null);
    try {
      const res = await window.electronAPI.regenerateSummary(id);
      if (res && (res as { error?: string }).error === 'rate_limit') {
        setMsg('Kontingent des KI-Anbieters erschöpft — der Bericht lässt sich gerade nicht erzeugen. Später erneut versuchen.');
      } else {
        await load(true);
      }
    } catch {
      setMsg('Bericht konnte nicht erzeugt werden. Bitte später erneut versuchen.');
    } finally {
      setRegenerating(false);
    }
  };

  const handleReanalyze = async () => {
    setMsg(null);
    const r = await window.electronAPI.reanalyzeMeeting(id);
    if (r && r.error === 'no_audio') setMsg('Kein Audio mehr vorhanden (nach 7 Tagen gelöscht) — eine neue Auswertung ist nicht möglich.');
    else if (r && r.error) setMsg('Neu auswerten nicht möglich: ' + r.error);
    else await load(true);
  };

  const handleRenameSpeaker = async (from: string, to: string) => {
    if (!to) return;
    await window.electronAPI.renameSpeaker(id, from, to);
    await load(true);
  };

  const speakerLabel = (speaker: string): string => {
    if (speaker === 'me') return 'Ich';
    if (speaker === 'other') return 'Gegenstelle';
    return speaker;
  };

  const playAt = (channel: 'mic' | 'system', t: number) => {
    const el = channel === 'system' && sysAudioRef.current ? sysAudioRef.current : micAudioRef.current;
    const other = el === micAudioRef.current ? sysAudioRef.current : micAudioRef.current;
    if (!el) return;
    try { other?.pause(); } catch { /* egal */ }
    try { el.currentTime = Math.max(0, t); el.play().catch(() => {}); } catch { /* egal */ }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64 text-muted-foreground">
        <RefreshCw className="w-5 h-5 animate-spin mr-2" />
        Lade Meeting...
      </div>
    );
  }

  if (!meeting) {
    return (
      <div className="text-center py-16 text-muted-foreground">
        <p>Meeting nicht gefunden.</p>
        <Button variant="outline" className="mt-4" onClick={onBack}>
          <ArrowLeft className="w-4 h-4 mr-2" />
          Zurück
        </Button>
      </div>
    );
  }

  const { index, transcript, audio } = meeting;
  const summary = normalizeSummary(meeting.summary);
  const hasAudio = !!(audio.mic || audio.system);
  const status = index.status || (transcript.segments.length ? 'ready' : 'failed');
  const segments = transcript.segments;

  // Sprecher-Farben: bleibende Farbe je Sprecher. „Ich“ ist immer GRÜN.
  const isMe = (sp: string): boolean => sp === 'me' || /^(ich|me|i)$/i.test(sp.trim());
  const SPEAKER_PALETTE = ['text-blue-600', 'text-amber-600', 'text-purple-600', 'text-pink-600', 'text-teal-600', 'text-orange-600'];
  const uniqSpeakers = Array.from(new Set(segments.map((s) => s.speaker)));
  const nonMeSpeakers = uniqSpeakers.filter((sp) => !isMe(sp));
  const speakerClass = (speaker: string): string => {
    if (isMe(speaker)) return 'text-green-600';
    const idx = nonMeSpeakers.indexOf(speaker);
    return SPEAKER_PALETTE[idx % SPEAKER_PALETTE.length] ?? 'text-muted-foreground';
  };
  const channelOf = (speaker: string): 'mic' | 'system' => (segments.find((s) => s.speaker === speaker)?.channel === 'system' ? 'system' : 'mic');

  const markdown = () => summaryToMarkdown(index.title, summary, segments, speakerLabel);
  const handleCopy = async () => {
    try { await navigator.clipboard.writeText(markdown()); setCopied(true); setTimeout(() => setCopied(false), 1500); } catch { /* egal */ }
  };
  const handleExport = async () => { await window.electronAPI.exportMeeting({ title: index.title, markdown: markdown() }); };

  const expires = index.audioExpiresAt ? new Date(index.audioExpiresAt) : null;

  return (
    <div className="space-y-5">
      {/* Kopf */}
      <div className="flex items-start gap-3">
        <Button variant="ghost" size="icon" onClick={onBack} className="mt-0.5">
          <ArrowLeft className="w-4 h-4" />
        </Button>
        <div className="flex-1 min-w-0">
          <h2 className="font-semibold text-lg leading-tight">{summary?.titel || index.title}</h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            {new Date(index.startTime).toLocaleString('de-DE', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
            {' · '}{formatDuration(index.durationMs)}
          </p>
          <div className="flex flex-wrap items-center gap-1.5 mt-2">
            {uniqSpeakers.length > 0 && (
              <Badge variant="secondary" className="gap-1 font-normal"><Users className="w-3 h-3" />{uniqSpeakers.length} {uniqSpeakers.length === 1 ? 'Sprecher' : 'Sprecher'}</Badge>
            )}
            {index.callDetected && <Badge variant="secondary" className="gap-1 font-normal"><Phone className="w-3 h-3" />Anruf</Badge>}
            {index.analysis === 'groq-fallback' && (
              <Badge variant="outline" className="gap-1 font-normal text-amber-700 border-amber-300"><AlertTriangle className="w-3 h-3" />ohne Sprechertrennung</Badge>
            )}
            {status === 'processing' && <Badge variant="outline" className="gap-1 font-normal"><RefreshCw className="w-3 h-3 animate-spin" />wird ausgewertet …</Badge>}
            {status === 'failed' && <Badge variant="destructive" className="gap-1 font-normal">Auswertung fehlgeschlagen</Badge>}
          </div>
        </div>
      </div>

      {/* Status-Hinweise */}
      {status === 'processing' && (
        <div className="text-sm rounded-md border bg-muted/40 px-3 py-2 flex items-center gap-2">
          <RefreshCw className="w-4 h-4 animate-spin text-muted-foreground" />
          <span>{index.progress || 'Aufnahme wird ausgewertet (Wortlaut, Sprecher, Bericht) …'} Du kannst das Fenster schließen; das Ergebnis erscheint automatisch.</span>
        </div>
      )}
      {status === 'failed' && (
        <div className="text-sm rounded-md border border-red-200 bg-red-50 text-red-700 px-3 py-2 space-y-2">
          <p><b>Die Auswertung ist fehlgeschlagen.</b> {index.analysisError || ''}</p>
          <p className="text-xs">Die Aufnahme ist gespeichert{expires ? ` (bis ${expires.toLocaleDateString('de-DE')})` : ''}. Prüfe die API-Keys in den Einstellungen und starte die Auswertung erneut.</p>
          <Button size="sm" variant="outline" onClick={handleReanalyze} disabled={!hasAudio}><RefreshCw className="w-3 h-3 mr-1" />Neu auswerten</Button>
        </div>
      )}
      {status === 'ready' && index.analysis === 'groq-fallback' && (
        <div className="text-sm rounded-md border border-amber-200 bg-amber-50 text-amber-800 px-3 py-2 flex items-center justify-between gap-3">
          <span>Ohne Sprechertrennung ausgewertet (Gemini nicht verfügbar{index.analysisError ? `: ${index.analysisError}` : ''}). Gemini-Key in den Einstellungen hinterlegen und neu auswerten.</span>
          <Button size="sm" variant="outline" onClick={handleReanalyze} disabled={!hasAudio}><Sparkles className="w-3 h-3 mr-1" />Neu auswerten</Button>
        </div>
      )}
      {index.captureStartGapMs && index.captureStartGapMs.mic > 1500 && (
        <p className="text-xs text-muted-foreground">Hinweis: Das Mikrofon startete {(index.captureStartGapMs.mic / 1000).toFixed(1)} s nach dem Shortcut — die ersten Worte fehlen evtl.</p>
      )}
      {msg && <p className="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-3 py-2">{msg}</p>}

      {/* Bericht */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between gap-2">
            <CardTitle className="text-base">Bericht</CardTitle>
            <div className="flex items-center gap-1">
              <Button size="sm" variant="ghost" onClick={handleCopy} title="Bericht + Konversation als Text kopieren">
                <Copy className="w-3 h-3 mr-1" />{copied ? 'Kopiert' : 'Kopieren'}
              </Button>
              <Button size="sm" variant="ghost" onClick={handleExport} title="Als Markdown-Datei speichern">
                <Download className="w-3 h-3 mr-1" />Export
              </Button>
              <Button size="sm" variant="outline" onClick={handleRegenerateSummary} disabled={regenerating || segments.length === 0}>
                <RefreshCw className={cn('w-3 h-3 mr-1', regenerating && 'animate-spin')} />Neu erzeugen
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-5">
          {!summary ? (
            index.summaryError === 'rate_limit' ? (
              <p className="text-sm text-amber-600 italic">Bericht noch nicht erzeugt — Kontingent des KI-Anbieters erschöpft. Später „Neu erzeugen“.</p>
            ) : status === 'processing' ? (
              <p className="text-sm text-muted-foreground italic">Der Bericht wird erstellt, sobald die Auswertung fertig ist.</p>
            ) : (
              <p className="text-sm text-muted-foreground italic">Noch kein Bericht vorhanden.</p>
            )
          ) : (
            <>
              {summary.kurzfassung && <p className="text-sm leading-relaxed">{summary.kurzfassung}</p>}

              {summary.themen.map((t, i) => (
                <div key={i}>
                  <h3 className="text-sm font-semibold mb-1">{t.ueberschrift || `Thema ${i + 1}`}</h3>
                  <div className="text-sm leading-relaxed space-y-2">
                    {t.inhalt.split(/\n\s*\n|\n(?=• )/).map((para, j) => <p key={j} className="whitespace-pre-line">{para.trim()}</p>)}
                  </div>
                </div>
              ))}

              {summary.entscheidungen.length > 0 && (
                <div>
                  <h3 className="text-sm font-semibold mb-1">Entscheidungen</h3>
                  <ul className="list-disc list-outside pl-5 space-y-1">
                    {summary.entscheidungen.map((e, i) => (
                      <li key={i} className="text-sm">{e.text}{e.begruendung && <span className="text-muted-foreground"> — {e.begruendung}</span>}</li>
                    ))}
                  </ul>
                </div>
              )}

              {summary.offeneFragen.length > 0 && (
                <div>
                  <h3 className="text-sm font-semibold mb-1">Offene Fragen</h3>
                  <ul className="list-disc list-outside pl-5 space-y-1">
                    {summary.offeneFragen.map((q, i) => <li key={i} className="text-sm">{q}</li>)}
                  </ul>
                </div>
              )}

              {todos.length > 0 && (
                <div>
                  <h3 className="text-sm font-semibold mb-1">To-dos</h3>
                  <ul className="space-y-1.5">
                    {todos.map((todo, i) => (
                      <li key={i} className="flex items-start gap-2 text-sm">
                        <input type="checkbox" checked={todo.erledigt} onChange={() => handleToggleTodo(i)} className="mt-0.5 accent-primary cursor-pointer" />
                        <span className={cn(todo.erledigt && 'line-through text-muted-foreground')}>
                          {todo.text}
                          {(todo.verantwortlich || todo.frist) && (
                            <span className="text-xs text-muted-foreground ml-1">
                              ({[todo.verantwortlich, todo.frist ? `bis ${todo.frist}` : null].filter(Boolean).join(', ')})
                            </span>
                          )}
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              <p className="text-[11px] text-muted-foreground">Automatisch erstellt ({summary.model || 'KI'}). Kann Fehler enthalten — Konversation unten ist der Wortlaut.</p>
            </>
          )}
        </CardContent>
      </Card>

      {/* Konversation */}
      <Card>
        <CardHeader className="pb-3">
          <div className="flex items-center justify-between gap-2">
            <CardTitle className="text-base">Konversation</CardTitle>
            <span className="text-xs text-muted-foreground">
              {hasAudio ? (expires ? `Audio bis ${expires.toLocaleDateString('de-DE')} verfügbar` : 'Audio verfügbar') : (index.audioDeleted ? 'Audio nach 7 Tagen gelöscht' : 'kein Audio')}
            </span>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Sprecher umbenennen (gleicher Name = zusammenführen) */}
          {uniqSpeakers.length > 0 && (
            <div className="p-3 bg-muted/40 rounded-lg">
              <p className="text-xs text-muted-foreground mb-2">Sprecher benennen — gleicher Name führt zwei zusammen; nenne dich „Ich“, dann bleibst du grün.</p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                {uniqSpeakers.map((sp) => (
                  <div key={sp} className="flex items-center gap-2">
                    <span className={cn('text-xs w-28 shrink-0 truncate font-semibold', speakerClass(sp))}>
                      {speakerLabel(sp)}{channelOf(sp) === 'system' && <Phone className="w-3 h-3 inline ml-1 opacity-60" />}
                    </span>
                    <Input
                      placeholder="Name…"
                      value={speakerNames[sp] ?? ''}
                      onChange={(e) => setSpeakerNames((p) => ({ ...p, [sp]: e.target.value }))}
                      onKeyDown={(e) => { if (e.key === 'Enter') handleRenameSpeaker(sp, speakerNames[sp] ?? ''); }}
                      className="h-8 text-sm"
                    />
                    <Button size="sm" variant="outline" onClick={() => handleRenameSpeaker(sp, speakerNames[sp] ?? '')} disabled={!speakerNames[sp]}>OK</Button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {segments.length === 0 ? (
            <p className="text-sm text-muted-foreground italic">{status === 'processing' ? 'Wortlaut folgt nach der Auswertung …' : 'Kein Text erkannt.'}</p>
          ) : (
            <div className="space-y-2.5">
              {segments.map((seg, i) => (
                <div key={i} className="flex gap-2 text-sm group">
                  <button
                    className={cn('shrink-0 w-14 text-[11px] font-mono tabular-nums text-muted-foreground text-left flex items-center gap-1 mt-0.5', hasAudio && 'hover:text-primary')}
                    onClick={() => hasAudio && playAt(seg.channel, seg.tStart)}
                    title={hasAudio ? 'Ab hier anhören' : 'Audio nicht mehr vorhanden'}
                    disabled={!hasAudio}
                  >
                    <Play className={cn('w-3 h-3', hasAudio ? 'opacity-40 group-hover:opacity-100' : 'opacity-0')} />
                    {formatTime(seg.tStart)}
                  </button>
                  <span className={cn('shrink-0 w-24 text-xs font-semibold mt-0.5 truncate', speakerClass(seg.speaker))} title={speakerLabel(seg.speaker)}>
                    {speakerLabel(seg.speaker)}
                  </span>
                  <p className={cn('flex-1 leading-relaxed', seg.unsicher && 'text-muted-foreground')} title={seg.unsicher ? 'Zuordnung/Wortlaut laut KI unsicher' : undefined}>
                    {seg.text}{seg.unsicher && <span className="text-[10px] ml-1 opacity-60">(?)</span>}
                  </p>
                </div>
              ))}
            </div>
          )}

          {/* Audio-Player (Seek-Ziele für ▶) */}
          {hasAudio && (
            <div className="pt-2 border-t space-y-2">
              {audio.mic && (
                <div className="flex items-center gap-2">
                  <span className="text-[11px] text-muted-foreground w-16 shrink-0">Mikrofon</span>
                  <audio ref={micAudioRef} controls preload="metadata" src={`file://${encodeURI(audio.mic)}`} className="w-full h-8" />
                </div>
              )}
              {audio.system && (
                <div className="flex items-center gap-2">
                  <span className="text-[11px] text-muted-foreground w-16 shrink-0">Gegenstelle</span>
                  <audio ref={sysAudioRef} controls preload="metadata" src={`file://${encodeURI(audio.system)}`} className="w-full h-8" />
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
