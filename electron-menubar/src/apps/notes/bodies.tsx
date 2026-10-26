import { memo, useEffect, useRef, useState } from 'react';
import { Renderer, createLibrary, defineComponent } from '@openuidev/react-lang';
import { z } from 'zod';
import { Mic, Image as ImageIcon, LoaderCircle, Plus, Check } from 'lucide-react';
import { useBoard } from './context';
import { NoteIcon } from './icons';
import { textEdit } from '@/lib/notes/editor';
import type { Note } from '@/types/notes';

export function NoteBody({ id }: { id: string }) {
  const { board, editing, setEditing, finishEditing, registerEditor, command, notify, zoom } = useBoard(), n = board.nodes[id];
  const [draft, setDraft] = useState(n?.text || ''), [table, setTable] = useState(n?.table), [expanded, setExpanded] = useState(false);
  const edit = editing === id;
  const base = useRef<Note|null>(null), saving = useRef<Promise<boolean>|null>(null), conflict = useRef(false);
  useEffect(() => { if (edit && n) { conflict.current = false; base.current = structuredClone(n); setDraft(n.text); setTable(n.table ? structuredClone(n.table) : undefined); } }, [edit]);
  const save = (confirmed = false): Promise<boolean> => {
    if (saving.current) return saving.current;
    const operation = async () => {
      const original = base.current;
      if (!n || !original) return false;
      const unchanged = original.kind === 'table' ? JSON.stringify(table) === JSON.stringify(original.table) : draft === original.text;
      if (!unchanged && conflict.current && !confirmed) return false;
      try {
        if (!unchanged) {
          // A transcript may fill a pending card while its editor is open. Keep
          // both texts; every other concurrent change must pass the base revision.
          const next = textEdit(original, n, draft);
          await command([{ type: 'update', id, rev: original.kind === 'table' ? original.rev : next.rev, patch: original.kind === 'table' ? { table } : { text: next.text } }]);
        }
        await finishEditing(id); return true;
      } catch (error) {
        if (error instanceof Error && error.message.includes('Die Notiz hat sich geändert')) {
          base.current = structuredClone(n); conflict.current = true;
          notify('Notiz inzwischen geändert. Dein Entwurf bleibt offen. Erneut Übernehmen bestätigt deinen Text.');
        }
        return false;
      }
    };
    saving.current = operation().finally(() => { saving.current = null; }); return saving.current;
  };
  useEffect(() => {
    if (!edit) return;
    registerEditor(id, save);
    const blur = () => { void save(); }; window.addEventListener('blur', blur);
    return () => { registerEditor(id, null); window.removeEventListener('blur', blur); };
  });
  if (!n) return null;
  const key = (e: React.KeyboardEvent) => { if (e.nativeEvent.isComposing) return; if (e.key === 'Escape' || (e.key === 'Enter' && (e.metaKey || e.ctrlKey))) { e.preventDefault(); e.stopPropagation(); void save(e.key === 'Enter'); } };
  const stamp = new Date(n.createdAt).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
  return <div className={`note-body kind-${n.kind} ${n.owner === 'ai' ? 'derived' : ''} ${zoom < .3 ? 'lod-tiny' : zoom < .6 ? 'lod-small' : ''}`} data-note-body={id} onBlur={e => { if (edit && !e.currentTarget.contains(e.relatedTarget as globalThis.Node|null)) void save(); }} onDoubleClick={e => { if (!['image', 'point'].includes(n.kind)) { e.stopPropagation(); setEditing(id); } }}>
    {n.kind !== 'hub' && n.kind !== 'point' && <div className="note-heading"><NoteIcon name={n.icon}/><span>{n.label || (n.kind === 'sticky' ? 'Merken' : n.kind === 'image' ? 'Fundstück' : '')}</span>{n.pending && <LoaderCircle className="spin" size={14}/>}</div>}
    {n.kind === 'hub' && !edit ? <div className="hub-label"><NoteIcon name={n.icon} size={28}/><span>{n.text}</span><i/></div> : n.kind === 'table' ? <div className="table-wrap"><table><thead><tr><th/>{(edit ? table : n.table)?.columns.map((column, i) => <th key={i}>{edit ? <input maxLength={100} className="nodrag nowheel" aria-label={`Spalte ${i + 1}`} value={column} onChange={e => setTable(t => ({ ...t!, columns: t!.columns.map((c, index) => index === i ? e.target.value : c) }))} onKeyDown={key}/> : column}</th>)}</tr></thead><tbody>{(edit ? table : n.table)?.rows.map((row, r) => <tr key={r}><th>{edit ? <input maxLength={100} className="nodrag nowheel" aria-label={`Kriterium ${r + 1}`} value={row.label} onChange={e => setTable(t => ({ ...t!, rows: t!.rows.map((v, i) => i === r ? { ...v, label: e.target.value } : v) }))} onKeyDown={key}/> : row.label}</th>{row.cells.map((cell, c) => <td key={c}>{edit ? <textarea maxLength={2000} className="nodrag nowheel" aria-label={`Zeile ${r + 1}, Spalte ${c + 1}`} value={cell} onChange={e => setTable(t => ({ ...t!, rows: t!.rows.map((v, i) => i === r ? { ...v, cells: v.cells.map((v, j) => j === c ? e.target.value : v) } : v) }))} onKeyDown={key}/> : cell || <span className="not-mentioned">Nicht genannt</span>}</td>)}</tr>)}</tbody></table></div> : n.kind !== 'image' && (edit ? <textarea autoFocus maxLength={base.current?.pending || n.pending ? 16998 : 20000} className="note-edit nodrag nowheel" aria-label="Notiz bearbeiten" value={draft} onChange={e => setDraft(e.target.value)} onKeyDown={key} style={{ minHeight: Math.max(100, (n.height || 180) - 80) }}/> : <p className={`note-text ${!expanded && n.text.length > 1200 ? 'clamped' : ''}`}>{n.text || (n.pending ? 'Dein Gedanke wird gesichert …' : 'Ein Gedanke beginnt hier.')}</p>)}
    {!edit && n.text.length > 1200 && n.kind !== 'table' && <button className="more nodrag" onClick={() => setExpanded(!expanded)}>{expanded ? 'Weniger' : 'Weiterlesen'}</button>}
    {n.attachments.length > 0 && <div className={`attachments ${n.kind === 'image' ? 'standalone' : ''}`}>{n.attachments.map(hash => <button className="attachment nodrag" key={hash} title="Bild öffnen" onClick={() => window.dispatchEvent(new CustomEvent('notes:image', { detail: hash }))}><img src={`paply-notes://thumb/${hash}`} alt="Gespeichertes Bild" loading="lazy"/>{n.kind !== 'image' && <ImageIcon size={14}/>}</button>)}</div>}
    {n.attachments.map(hash => board.assets[hash]?.analysis?.caption ? <p key={hash} className="image-caption">{board.assets[hash].analysis!.caption}</p> : null)}
    {edit && <button className="save-note nodrag" onClick={() => void save(true)}><Check size={14}/>Übernehmen</button>}
    {n.sourceId && n.kind !== 'hub' && <div className="note-stamp"><Mic size={11}/><span>{stamp}</span></div>}
  </div>;
}
const names = ['NoteBody', 'StickyBody', 'TextBody', 'HubLabel', 'ComparisonTable', 'ImageBody'] as const;
const components = names.map(name => defineComponent({ name, description: 'Paply presentation backed by a canonical note ID.', props: z.object({ id: z.string() }), component: ({ props }) => <NoteBody id={props.id}/> }));
export const library = createLibrary({ components, root: 'NoteBody' });
const bodyName: Record<Note['kind'], string> = { note: 'NoteBody', sticky: 'StickyBody', text: 'TextBody', hub: 'HubLabel', table: 'ComparisonTable', image: 'ImageBody', point: 'NoteBody' };
export const compileBody = (kind: Note['kind'], id: string) => { if (!/^[\w-]+$/.test(id) || !bodyName[kind]) throw new Error('Unzulässiger Baustein'); return `root = ${bodyName[kind]}(${JSON.stringify(id)})`; };
// Programs contain only trusted component names and IDs; neither model nor user
// text is ever executable UI. The canonical store remains outside OpenUI.
export const GenerativeBody = memo(function GenerativeBody({ id, kind, direct = false }: { id: string; kind: Note['kind']; direct?: boolean }) {
  return <div className="body-renderer">{direct ? <NoteBody id={id}/> : <Renderer library={library} response={compileBody(kind, id)} isStreaming={false} publishObservability={false}/>}</div>;
});
