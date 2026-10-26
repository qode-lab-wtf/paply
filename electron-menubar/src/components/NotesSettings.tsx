import { useEffect, useState } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { keyEventToAccelerator } from '@/lib/shortcut';
import { formatNotesShortcut } from '@/lib/notes/shortcuts';
import { Sparkles, ArrowUpRight } from 'lucide-react';
import type { NotesPreferences } from '@/types/notes';
export function NotesSettings() {
  const [value, setValue] = useState<NotesPreferences|null>(null), [error, setError] = useState(''), [busy, setBusy] = useState(false);
  const [keys, setKeys] = useState({ captureHotkey: '', openHotkey: '' });
  useEffect(() => {
    const load = () => window.electronAPI.getNotesSettings().then(v => { setValue(v); setKeys({ captureHotkey: v.captureHotkey, openHotkey: v.openHotkey }); }).catch(() => setError('Notes-Einstellungen konnten nicht geladen werden.'));
    void load(); const off = window.electronAPI.onNotesSettingsChanged(load); const offGeneral = window.electronAPI.onSettingsChanged(load);
    const offKeys = window.electronAPI.onNotesShortcut(({ field, key }) => setKeys(k => ({ ...k, [field]: key })));
    return () => { off(); offGeneral(); offKeys(); void window.electronAPI.captureNotesShortcut(null).catch(() => {}); };
  }, []);
  async function save(patch: Partial<NotesPreferences>) {
    setBusy(true); setError('');
    try { setValue(await window.electronAPI.setNotesSettings(patch)); } catch (e) { setError(e instanceof Error ? e.message.replace(/^Error invoking remote method '[^']+': Error: /, '') : 'Speichern nicht möglich.'); } finally { setBusy(false); }
  }
  return <Card><CardContent className="pt-6 space-y-4">
    <div className="flex items-center justify-between gap-4"><div><Label className="flex items-center gap-2"><Sparkles size={16}/> Notes</Label><p className="text-sm text-muted-foreground mt-1">Ein Kürzel. Ein Gedanke. Deine eigene Fläche.</p></div>{value && <Switch aria-label="Notes aktivieren" checked={value.enabled} disabled={busy} onCheckedChange={enabled => void save({ enabled })}/>}</div>
    {value && <><div className="grid grid-cols-2 gap-3">{(['captureHotkey', 'openHotkey'] as const).map(key => <div className="space-y-2" key={key}><Label htmlFor={`notes-${key}`}>{key === 'captureHotkey' ? 'Gedanke aufnehmen' : 'Notes öffnen'}</Label><Input id={`notes-${key}`} value={formatNotesShortcut(keys[key], value)} readOnly aria-label={key === 'captureHotkey' ? 'Notes Aufnahme-Kürzel' : 'Notes Öffnen-Kürzel'} onFocus={() => void window.electronAPI.captureNotesShortcut(key).catch(() => {})} onBlur={() => void window.electronAPI.captureNotesShortcut(null).catch(() => {})} onKeyDown={e => { if (e.key === 'Tab') return; e.preventDefault(); if (e.key === 'Escape') { e.currentTarget.blur(); return; } const next = keyEventToAccelerator(e.nativeEvent, value.platform === 'darwin'); if (next && (e.metaKey || e.ctrlKey || e.altKey || /^F\d+$/.test(e.code))) setKeys(k => ({ ...k, [key]: next })); }}/></div>)}</div>
    <div className="flex items-center justify-between"><Button variant="outline" size="sm" disabled={busy || (keys.captureHotkey === value.captureHotkey && keys.openHotkey === value.openHotkey)} onClick={() => void save(keys)}>Kürzel übernehmen</Button><Button variant="ghost" size="sm" onClick={() => window.electronAPI.openNotes()}>Notes öffnen <ArrowUpRight size={15}/></Button></div>
    <label className="flex justify-between gap-4 items-center"><span><span className="text-sm">Bildschirmkontext beim Start</span><p className="text-xs text-muted-foreground mt-1">Ein lokales Bild. Nur mit „Bildschirm merken“ am Anfang deiner Aufnahme wird es behalten.</p></span><Switch aria-label="Bildschirmkontext beim Start" checked={value.screenContext} disabled={busy} onCheckedChange={screenContext => void save({ screenContext })}/></label>
    <label className="flex justify-between gap-4 items-center"><span><span className="text-sm">Bilder verstehen</span><p className="text-xs text-muted-foreground mt-1">Eine kurze Beschreibung je Bild, höchstens zehn am Tag.</p></span><Switch aria-label="Bilder verstehen" checked={value.imageUnderstanding} disabled={busy} onCheckedChange={imageUnderstanding => void save({ imageUnderstanding })}/></label>
    <details><summary className="text-xs text-muted-foreground cursor-pointer">Verarbeitung & Budget</summary><div className="space-y-3 pt-3"><p className="text-xs text-muted-foreground">Ton und neue Gedanken werden mit deinem Groq-Schlüssel verarbeitet. Dazu kommt ein kleiner Ausschnitt passender vorhandener Notizen. Bilder gehen nur bei aktivierter Bildbeschreibung an Groq. Bei Limits bleibt alles lokal gesichert.</p><label className="block text-xs">Notes-Tokenbudget für 24 Stunden<Input type="number" min={5000} max={180000} step={5000} defaultValue={value.dailyTokens} onBlur={e => { const n = Number(e.target.value); if (n !== value.dailyTokens) void save({ dailyTokens: n }); }}/></label><label className="block text-xs">Audiominuten für 24 Stunden<Input type="number" min={1} max={120} defaultValue={value.dailyAudioMinutes} onBlur={e => { const n = Number(e.target.value); if (n !== value.dailyAudioMinutes) void save({ dailyAudioMinutes: n }); }}/></label><p className="text-xs text-muted-foreground">Die Grenzen gelten für Notes auf diesem Gerät. Das tatsächliche Groq-Kontingent wird mit Diktat und anderen Geräten geteilt.</p></div></details>
    {!value.hasGroqKey && <p className="text-xs text-muted-foreground">Ergänze deinen Groq-Schlüssel oben, damit Aufnahmen verschriftet werden.</p>}
    {value.warning && <p className="text-sm text-destructive" role="alert">{value.warning}</p>}</>}
    {error && <p className="text-sm text-destructive" role="alert">{error}</p>}
  </CardContent></Card>;
}
