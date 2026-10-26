import { useState, useEffect, useCallback, useRef, useMemo, memo } from 'react';
import { ReactFlow, ReactFlowProvider, ViewportPortal, Background, BackgroundVariant, Handle, Position, NodeResizer, NodeToolbar, BaseEdge, EdgeLabelRenderer, getBezierPath, getStraightPath, MarkerType, ConnectionMode, applyNodeChanges, applyEdgeChanges, useReactFlow, useNodesInitialized, type Node, type Edge, type NodeProps, type EdgeProps, type Connection, type Viewport, type NodeChange } from '@xyflow/react';
import { MousePointer2, Hand, StickyNote, Type, ArrowUpRight, Minus, Plus, Mic, Square, Undo2, Redo2, Maximize, Search, Inbox, Settings2, Copy, Pencil, Trash2, Quote, X, Check, Camera, LoaderCircle, ChevronDown, ArrowLeft, ArrowRight, LayoutGrid, Share2, Table2, ArrowRightLeft, Shapes, CircleHelp } from 'lucide-react';
import { PaplyMark } from '@/components/brand/PaplyMark';
import { formatNotesShortcut } from '@/lib/notes/shortcuts';
import { placeNotes, bounds, heightFor } from '@/lib/notes/layout';
import type { NotesBoard, Note, XY, NotesSource } from '@/types/notes';
import { BoardContext, useBoard } from './context';
import { GenerativeBody } from './bodies';
import { NoteIcon } from './icons';
import '@xyflow/react/dist/style.css';
import './notes.css';

type FlowNode = Node<{ noteId: string; kind: Note['kind']; direct?: boolean }, 'thought'|'point'>;
type FlowEdge = Edge<{ inferred: boolean; free: boolean }, 'thought'>;
const api = () => window.paplyNotes;
const editable = (target: EventTarget|null) => target instanceof Element && !!target.closest('input,textarea,[contenteditable=true]');
function IconButton({ title, active, onClick, disabled, children, className = '' }: { title: string; active?: boolean; onClick?: () => void; disabled?: boolean; children: React.ReactNode; className?: string }) { return <button className={`icon-button ${active ? 'is-active' : ''} ${className}`} title={title} aria-label={title} aria-pressed={active === undefined ? undefined : active} onClick={onClick} disabled={disabled}>{children}</button>; }

const ThoughtNode = memo(function ThoughtNode({ id, selected, data }: NodeProps<FlowNode>) {
  const { board, setEditing, command, source, notify } = useBoard(), n = board.nodes[id];
  if (!n) return null;
  return <div className={`thought-node ${n.kind} ${selected ? 'selected' : ''}`} data-note-id={id}>
    <NodeResizer isVisible={selected && n.kind !== 'hub'} minWidth={n.kind === 'table' ? 400 : 170} minHeight={90} onResizeEnd={(_e, p) => { void command([{ type: 'update', id, patch: { width: p.width, height: p.height, position: { x: p.x, y: p.y } } }]); }}/>
    <Handle type="source" position={Position.Left} id="left"/><Handle type="source" position={Position.Right} id="right"/>
    <NodeToolbar isVisible={selected} position={Position.Top} offset={13}><div className="context-tools nodrag">
      <IconButton title="Bearbeiten" onClick={() => setEditing(id)}><Pencil size={16}/></IconButton>
      {n.sourceId && <IconButton title="Original ansehen" onClick={() => source(id)}><Quote size={16}/></IconButton>}
      <IconButton title="Text kopieren" onClick={() => { void api().copy(n.kind === 'table' && n.table ? [n.table.columns.join('\t'), ...n.table.rows.map(r => [r.label, ...r.cells].join('\t'))].join('\n') : n.text).then(() => notify('Kopiert')); }}><Copy size={16}/></IconButton>
      <IconButton title="Duplizieren" onClick={() => void command([{ type: 'duplicate', id }])}><Plus size={16}/></IconButton>
      {['note', 'sticky', 'text'].includes(n.kind) && <select aria-label="Darstellung" title="Darstellung" value={n.kind} onChange={e => void command([{ type: 'update', id, patch: { kind: e.target.value } }])}><option value="note">Karte</option><option value="sticky">Haftnotiz</option><option value="text">Freier Text</option></select>}
      <select aria-label="Thema zuordnen" title="Thema zuordnen" value={n.topicId || ''} onChange={e => void command([{ type: 'update', id, patch: { topicId: e.target.value || null } }])}><option value="">Ohne Thema</option>{Object.values(board.topics).map(t => <option value={t.id} key={t.id}>{t.title}</option>)}</select>
      <IconButton title="Entfernen" onClick={() => void command([{ type: 'delete', id }])}><Trash2 size={16}/></IconButton>
    </div></NodeToolbar>
    <GenerativeBody id={id} kind={n.kind} direct={data.direct}/>
  </div>;
});
const PointNode = memo(function PointNode({ id, selected }: NodeProps<FlowNode>) {
  const { board, selectedEdges } = useBoard();
  const show = selected || [...selectedEdges].some(eid => { const e = board.edges[eid]; return e && (e.source === id || e.target === id); });
  return <div className={`line-point ${show ? 'visible' : ''}`} data-endpoint={id}><Handle type="source" position={Position.Left} id="left"/><Handle type="source" position={Position.Right} id="right"/></div>;
});
function ThoughtEdge(props: EdgeProps<FlowEdge>) {
  const { board, command } = useBoard(), rf = useReactFlow<FlowNode, FlowEdge>();
  const free = props.data?.free;
  const [path, x, y] = free ? getStraightPath(props) : getBezierPath({ ...props, curvature: .25 });
  function drag(e: React.PointerEvent<SVGPathElement>) {
    if (!free || e.button !== 0) return;
    e.stopPropagation(); e.preventDefault();
    const a = rf.getNode(props.source), z = rf.getNode(props.target); if (!a || !z) return;
    const start = rf.screenToFlowPosition({ x: e.clientX, y: e.clientY });
    const origin = { a: { ...a.position }, z: { ...z.position } }; let delta = { x: 0, y: 0 };
    const move = (event: PointerEvent) => { const p = rf.screenToFlowPosition({ x: event.clientX, y: event.clientY }); delta = { x: p.x - start.x, y: p.y - start.y }; rf.setNodes(ns => ns.map(n => n.id === a.id || n.id === z.id ? { ...n, position: { x: (n.id === a.id ? origin.a.x : origin.z.x) + delta.x, y: (n.id === a.id ? origin.a.y : origin.z.y) + delta.y } } : n)); };
    const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); if (delta.x || delta.y) void command([{ type: 'update', id: a.id, patch: { position: { x: origin.a.x + delta.x, y: origin.a.y + delta.y } } }, { type: 'update', id: z.id, patch: { position: { x: origin.z.x + delta.x, y: origin.z.y + delta.y } } }]); };
    window.addEventListener('pointermove', move); window.addEventListener('pointerup', up, { once: true });
  }
  return <><BaseEdge path={path} markerEnd={props.markerEnd} style={{ stroke: props.selected ? 'var(--green)' : props.data?.inferred ? 'var(--ink-soft)' : 'var(--ink)', strokeWidth: props.selected ? 2.3 : 1.6, strokeDasharray: props.data?.inferred ? '6 5' : undefined }}/><path d={path} fill="none" stroke="transparent" strokeWidth={22} className="edge-grab" onPointerDown={drag}/>{props.label && <EdgeLabelRenderer><span className="edge-label" style={{ transform: `translate(-50%,-50%) translate(${x}px,${y}px)` }}>{String(props.label)}</span></EdgeLabelRenderer>}</>;
}
const nodeTypes = { thought: ThoughtNode, point: PointNode }, edgeTypes = { thought: ThoughtEdge };
function Board() {
  const rf = useReactFlow<FlowNode, FlowEdge>(), initialized = useNodesInitialized();
  const [board, setBoard] = useState<NotesBoard|null>(null), [nodes, setNodes] = useState<FlowNode[]>([]), [edges, setEdges] = useState<FlowEdge[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set()), [selectedEdges, setSelectedEdges] = useState<Set<string>>(new Set()), [editing, setEditingState] = useState<string|null>(null);
  const [tool, setTool] = useState('select'), [space, setSpace] = useState(false), [zoom, setZoom] = useState(1), [toast, setToast] = useState(''), [inbox, setInbox] = useState(false), [help, setHelp] = useState(false), [query, setQuery] = useState(''), [search, setSearch] = useState(false), [source, setSource] = useState<NotesSource|null>(null), [image, setImage] = useState<string|null>(null), [drawing, setDrawing] = useState<{ a: XY; z: XY }|null>(null);
  const boardRef = useRef<NotesBoard|null>(null), dragIds = useRef(new Set<string>()), mounted = useRef(true), loaded = useRef(false), placing = useRef(false), toastTimer = useRef<ReturnType<typeof setTimeout>|null>(null), viewportTimer = useRef<ReturnType<typeof setTimeout>|null>(null), surface = useRef<HTMLDivElement>(null), searchInput = useRef<HTMLInputElement>(null), drawingRef = useRef<{ a: XY; z: XY }|null>(null);
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const notify = useCallback((message: string) => { setToast(message.replace(/^Error invoking remote method '[^']+': Error: /, '')); if (toastTimer.current) clearTimeout(toastTimer.current); toastTimer.current = setTimeout(() => setToast(''), 4200); }, []);
  const receive = useCallback((b: NotesBoard) => {
    if (!mounted.current || (boardRef.current && b.rev < boardRef.current.rev)) return;
    boardRef.current = b; setBoard(b);
    const values = Object.values(b.nodes), provisional = placeNotes(values, Object.keys(b.topics));
    setNodes(old => values.map(n => {
      const before = old.find(x => x.id === n.id), dragging = dragIds.current.has(n.id);
      return { id: n.id, type: n.kind === 'point' ? 'point' : 'thought', position: dragging && before ? before.position : n.position || provisional[n.id] || { x: 0, y: 0 }, data: { noteId: n.id, kind: n.kind }, selected: before?.selected || false, width: n.width, style: { width: n.width, ...(n.height ? { height: n.height } : {}) }, measured: before?.measured, zIndex: n.kind === 'point' ? 8 : 2 } as FlowNode;
    }));
    setEdges(old => Object.values(b.edges).map(e => {
      const a = b.nodes[e.source], z = b.nodes[e.target], free = a?.kind === 'point' && z?.kind === 'point';
      const left = a && z && (z.position?.x ?? provisional[z.id]?.x ?? 0) < (a.position?.x ?? provisional[a.id]?.x ?? 0);
      return { ...e, ...(e.inferred ? { sourceHandle: left ? 'left' : 'right', targetHandle: left ? 'right' : 'left' } : {}), type: 'thought', data: { inferred: e.inferred, free }, selected: old.find(x => x.id === e.id)?.selected || false, markerEnd: e.arrow ? { type: MarkerType.ArrowClosed, width: 15, height: 15, color: 'var(--ink-soft)' } : undefined, label: e.label || undefined };
    }));
    if (!loaded.current) { loaded.current = true; void rf.setViewport(b.viewport); setZoom(b.viewport.zoom); }
  }, [rf]);
  const run = useCallback(async (fn: () => Promise<NotesBoard>) => { try { receive(await fn()); } catch (e) { notify(e instanceof Error ? e.message : 'Änderung konnte nicht gespeichert werden'); try { receive(await api().get()); } catch { /* Keep the last durable snapshot if IPC itself is unavailable. */ } throw e; } }, [receive, notify]);
  const command = useCallback(async (ops: unknown[]) => { await run(() => api().command(ops)); }, [run]);
  const editingRef = useRef<string|null>(null), editorSave = useRef<{ id: string; save: () => Promise<boolean> }|null>(null), editTransitions = useRef(Promise.resolve());
  const registerEditor = useCallback((id: string, save: (() => Promise<boolean>)|null) => {
    if (save) editorSave.current = { id, save }; else if (editorSave.current?.id === id) editorSave.current = null;
  }, []);
  const finishEditing = useCallback(async (id: string) => {
    receive(await api().editing({ id, active: false }));
    if (editingRef.current === id) { editingRef.current = null; setEditingState(null); }
    if (editorSave.current?.id === id) editorSave.current = null;
  }, [receive]);
  const setEditing = useCallback((id: string|null) => {
    editTransitions.current = editTransitions.current.then(async () => {
      if (id === editingRef.current) return;
      if (editorSave.current && !await editorSave.current.save()) return;
      if (editingRef.current) await finishEditing(editingRef.current);
      if (id) { const next = await api().editing({ id, active: true }); receive(next); editingRef.current = id; setEditingState(id); }
    }).catch(e => notify(e instanceof Error ? e.message : String(e)));
  }, [finishEditing, receive, notify]);
  const selectionChanged = useCallback(({ nodes: ns, edges: es }: { nodes: FlowNode[]; edges: FlowEdge[] }) => {
    const update = (previous: Set<string>, ids: string[]) => previous.size === ids.length && ids.every(id => previous.has(id)) ? previous : new Set(ids);
    setSelected(previous => update(previous, ns.map(n => n.id)));
    setSelectedEdges(previous => update(previous, es.map(e => e.id)));
  }, []);
  useEffect(() => {
    mounted.current = true; api().get().then(receive).catch(e => notify(String(e))); const unsubscribe = api().onChange(receive);
    const offKeys = api().onKey(k => { if (editable(document.activeElement)) return; if (k === '0') void rf.zoomTo(1, { duration: 0 }); else void rf.zoomTo(Math.min(2.5, Math.max(.1, rf.getZoom() * (k === '-' ? 1/1.15 : 1.15))), { duration: 100 }); });
    const showImage = (e: Event) => setImage((e as CustomEvent<string>).detail); window.addEventListener('notes:image', showImage);
    return () => { mounted.current = false; unsubscribe(); offKeys(); window.removeEventListener('notes:image', showImage); };
  }, [receive, rf, notify]);
  useEffect(() => {
    if (!initialized || !board || placing.current) return;
    const missing = Object.values(board.nodes).filter(n => !n.position); if (!missing.length) return;
    const measured = Object.fromEntries(rf.getNodes().map(n => [n.id, n.measured || {}]));
    const positions = placeNotes(Object.values(board.nodes), Object.keys(board.topics), measured);
    placing.current = true;
    api().place(Object.entries(positions).map(([id, position]) => ({ id, position }))).then(receive).catch(e => notify(String(e))).finally(() => { placing.current = false; });
  }, [initialized, board?.rev, rf, receive, notify]);
  const openSource = useCallback((id: string) => { api().source(id).then(setSource).catch(() => notify('Original ist noch nicht verfügbar')); }, [notify]);
  const remove = useCallback(() => { void command([...selected].map(id => ({ type: 'delete', id })).concat([...selectedEdges].map(id => ({ type: 'deleteEdge', id })))).catch(() => {}); }, [command, selected, selectedEdges]);
  const center = () => { const rect = surface.current!.getBoundingClientRect(); return rf.screenToFlowPosition({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }); };
  async function create(kind: Note['kind'], position = center()) {
    const previous = new Set(Object.keys(boardRef.current?.nodes || {}));
    try { const next = await api().command([{ type: 'create', node: { kind, position, text: '' } }]); receive(next); const id = Object.keys(next.nodes).find(k => !previous.has(k)); if (id) { setSelected(new Set([id])); setNodes(ns => ns.map(n => ({ ...n, selected: n.id === id }))); setEditing(id); } } catch (e) { notify(String(e)); }
    setTool('select');
  }
  const fit = (ids?: string[]) => { void rf.fitView({ duration: reduced ? 0 : 240, padding: .18, maxZoom: 1.2, ...(ids?.length ? { nodes: ids.map(id => ({ id })) } : {}) }); };
  function jump(topicId: string|null) { const ids = Object.values(boardRef.current?.nodes || {}).filter(n => n.topicId === topicId && n.kind !== 'point').map(n => n.id); fit(ids); }
  useEffect(() => {
    function key(e: KeyboardEvent) {
      if (e.isComposing || editable(e.target)) return;
      if ((source || image || help) && e.key !== 'Escape') return;
      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === 'c' && window.getSelection()?.toString()) return;
      if (mod && e.key.toLowerCase() === 'f') { e.preventDefault(); setSearch(true); setTimeout(() => searchInput.current?.focus(), 0); }
      else if (mod && e.key.toLowerCase() === 'z') { e.preventDefault(); void run(() => e.shiftKey ? api().redo() : api().undo()).catch(() => {}); }
      else if (mod && e.key.toLowerCase() === 'c') { e.preventDefault(); const text = [...selected].map(id => boardRef.current?.nodes[id]?.text || '').join('\n\n'); if (text) void api().copy(text).then(() => notify('Kopiert')); }
      else if (mod && e.key.toLowerCase() === 'd' && selected.size) { e.preventDefault(); void command([...selected].map(id => ({ type: 'duplicate', id }))).catch(() => {}); }
      else if (e.key === 'Delete' || e.key === 'Backspace') { if (selected.size || selectedEdges.size) { e.preventDefault(); remove(); } }
      else if (e.key === 'Escape') { setEditing(null); setSource(null); setImage(null); setHelp(false); setInbox(false); setSearch(false); setTool('select'); }
      else if (e.key === 'Enter' && selected.size === 1) setEditing([...selected][0]);
      else if (e.code === 'Space') { e.preventDefault(); setSpace(true); }
      else if (!mod && !e.altKey) { if (e.key.toLowerCase() === 'v') setTool('select'); if (e.key.toLowerCase() === 'h') setTool('hand'); if (e.key.toLowerCase() === 'n') setTool('sticky'); if (e.key.toLowerCase() === 't') setTool('text'); if (e.key.toLowerCase() === 'l') setTool(e.shiftKey ? 'line' : 'arrow'); if (e.shiftKey && e.code === 'Digit1') fit(); if (e.shiftKey && e.code === 'Digit2') fit([...selected]); }
    }
    const up = (e: KeyboardEvent) => { if (e.code === 'Space') setSpace(false); };
    const blur = () => setSpace(false);
    window.addEventListener('keydown', key); window.addEventListener('keyup', up); window.addEventListener('blur', blur);
    return () => { window.removeEventListener('keydown', key); window.removeEventListener('keyup', up); window.removeEventListener('blur', blur); };
  }, [selected, selectedEdges, command, remove, run, notify, source, image, help]);
  useEffect(() => {
    async function paste(e: ClipboardEvent) {
      if (editable(e.target)) return;
      const file = [...(e.clipboardData?.items || [])].find(i => i.type.startsWith('image/'))?.getAsFile();
      const text = e.clipboardData?.getData('text/plain'); if (!file && !text) return; e.preventDefault();
      try { if (file) await run(async () => api().attach({ bytes: await file.arrayBuffer(), target: selected.size === 1 ? [...selected][0] : null, position: center() })); else if (text) await run(() => api().addText({ text, position: center() })); } catch { /* shown by run */ }
    }
    window.addEventListener('paste', paste); return () => window.removeEventListener('paste', paste);
  }, [selected, run]);
  function pointerDown(e: React.PointerEvent) {
    if (!['line', 'arrow'].includes(tool) || e.button !== 0 || (e.target as Element).closest('.notes-ui')) return;
    e.preventDefault(); e.stopPropagation(); const a = { x: e.clientX, y: e.clientY }; drawingRef.current = { a, z: a }; setDrawing({ a, z: a });
    const move = (event: PointerEvent) => { let z = { x: event.clientX, y: event.clientY }; if (event.shiftKey) { const dx = z.x-a.x, dy = z.y-a.y, angle = Math.round(Math.atan2(dy, dx)/(Math.PI/12))*(Math.PI/12), distance = Math.hypot(dx, dy); z = { x: a.x+Math.cos(angle)*distance, y: a.y+Math.sin(angle)*distance }; } drawingRef.current = { a, z }; setDrawing({ a, z }); };
    const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); const d = drawingRef.current; drawingRef.current = null; setDrawing(null); if (d && Math.hypot(d.z.x-d.a.x, d.z.y-d.a.y) > 8) void command([{ type: 'line', from: rf.screenToFlowPosition(d.a), to: rf.screenToFlowPosition(d.z), arrow: tool === 'arrow' }]).catch(() => {}); setTool('select'); };
    window.addEventListener('pointermove', move); window.addEventListener('pointerup', up, { once: true });
  }
  function dragStop(_e: MouseEvent|TouchEvent, n: FlowNode, dragged: FlowNode[]) {
    dragIds.current.clear(); const list = dragged.length ? dragged : [n];
    const ops: unknown[] = list.map(item => ({ type: 'update', id: item.id, patch: { position: item.position } }));
    if (n.type === 'point' && boardRef.current) {
      const hit = rf.getNodes().find(other => other.id !== n.id && other.type !== 'point' && n.position.x >= other.position.x - 12 && n.position.y >= other.position.y - 12 && n.position.x <= other.position.x + (other.measured?.width || other.width || 320) + 12 && n.position.y <= other.position.y + (other.measured?.height || 200) + 12);
      if (hit) { for (const edge of Object.values(boardRef.current.edges)) if (edge.source === n.id || edge.target === n.id) ops.push({ type: 'edge', ...edge, source: edge.source === n.id ? hit.id : edge.source, target: edge.target === n.id ? hit.id : edge.target }); ops.push({ type: 'delete', id: n.id }); }
    }
    void command(ops).catch(() => {});
  }
  const detailZoom = zoom < .3 ? .2 : zoom < .6 ? .4 : 1;
  const ctx = useMemo(() => ({ board: board!, selected, selectedEdges, editing, setEditing, finishEditing, registerEditor, command, source: openSource, notify, zoom: detailZoom }), [board, selected, selectedEdges, editing, setEditing, finishEditing, registerEditor, command, openSource, notify, detailZoom]);
  if (!board) return <div className="notes-loading"><PaplyMark size={42}/>{toast || 'Deine Gedanken …'}</div>;
  const topicList = Object.values(board.topics), pending = board.entries.filter(e => ['recording', 'captured', 'transcribing', 'transcribed', 'structuring', 'waiting_key', 'waiting_network', 'waiting_limit', 'waiting_budget'].includes(e.state));
  const topicFrames = topicList.map(t => { const members = nodes.filter(n => board.nodes[n.id]?.topicId === t.id && n.type !== 'point'); if (!members.length) return null; const x = Math.min(...members.map(n => n.position.x)), y = Math.min(...members.map(n => n.position.y)), right = Math.max(...members.map(n => n.position.x + (n.measured?.width || n.width || 320))), bottom = Math.max(...members.map(n => n.position.y + (n.measured?.height || heightFor(board.nodes[n.id])))); return { topic: t, x: x-45, y: y-80, width: right-x+90, height: bottom-y+125, count: new Set(members.map(n => board.nodes[n.id]?.sourceId).filter(Boolean)).size }; });
  const results = query ? Object.values(board.nodes).filter(n => n.kind !== 'point' && `${n.text} ${n.label} ${n.table ? JSON.stringify(n.table) : ''}`.toLocaleLowerCase('de').includes(query.toLocaleLowerCase('de'))).slice(0, 15) : [];
  return <BoardContext.Provider value={ctx}><main className={`notes-app tool-${tool} ${space ? 'holding-space' : ''}`}>
    <header className={`notes-header notes-ui ${board.preferences.platform === 'darwin' ? 'mac' : ''}`}><div className="notes-brand"><PaplyMark size={30}/><span>notes</span></div><nav className="topic-nav" aria-label="Themen auf dieser Fläche"><button onClick={() => fit()} className="overview-chip"><LayoutGrid size={14}/>Alles</button>{topicList.map(t => <button key={t.id} onClick={() => jump(t.id)}><NoteIcon name={t.icon} size={15}/>{t.title}</button>)}</nav><div className="header-tools"><IconButton title="Gedanken suchen (⌘F)" active={search} onClick={() => { setSearch(!search); setTimeout(() => searchInput.current?.focus(), 0); }}><Search size={18}/></IconButton><button className={`inbox-button ${inbox ? 'is-active' : ''}`} title="Aufnahmen & Verarbeitung" aria-label="Aufnahmen & Verarbeitung" onClick={() => setInbox(!inbox)}><Inbox size={18}/>{pending.length > 0 && <span>{pending.length}</span>}</button><IconButton title="Notes-Einstellungen" onClick={() => void api().settings()}><Settings2 size={18}/></IconButton></div></header>
    <div className="board-surface" ref={surface} onPointerDownCapture={pointerDown}>
    <ReactFlow<FlowNode, FlowEdge> connectionMode={ConnectionMode.Loose} nodes={nodes} edges={edges} nodeTypes={nodeTypes} edgeTypes={edgeTypes} onNodesChange={changes => setNodes(ns => applyNodeChanges(changes, ns))} onEdgesChange={changes => setEdges(es => applyEdgeChanges(changes, es))} onSelectionChange={selectionChanged} onNodeDragStart={(_e, _n, ns) => { dragIds.current = new Set(ns.map(n => n.id)); setEditing(null); }} onNodeDragStop={dragStop} onConnect={(c: Connection) => void command([{ type: 'edge', ...c }]).catch(() => {})} onReconnect={(edge, c) => void command([{ type: 'edge', id: edge.id, ...c }]).catch(() => {})} onPaneClick={e => { if (tool === 'sticky' || tool === 'text') void create(tool, rf.screenToFlowPosition({ x: e.clientX, y: e.clientY })); else setEditing(null); }} onMove={(_e, v) => setZoom(v.zoom)} onMoveEnd={(_e, v) => { if (viewportTimer.current) clearTimeout(viewportTimer.current); viewportTimer.current = setTimeout(() => api().viewport(v).catch(() => notify('Ansicht konnte nicht gespeichert werden')), 180); }}
      panOnScroll panOnScrollSpeed={1} zoomOnPinch zoomOnScroll={false} zoomOnDoubleClick={false} panOnDrag={tool === 'hand' || space ? true : tool === 'select' ? [1,2] : false} selectionOnDrag={tool === 'select' && !space} selectionKeyCode="Shift" multiSelectionKeyCode="Shift" nodesDraggable={tool === 'select' && !space} nodesConnectable={tool === 'select'} elementsSelectable={tool === 'select'} deleteKeyCode={null} minZoom={.1} maxZoom={2.5} nodeDragThreshold={3} edgesReconnectable onlyRenderVisibleElements={nodes.length > 150 && !editing} proOptions={{ hideAttribution: true }}>
      <Background variant={BackgroundVariant.Dots} gap={24} size={1} color={zoom < .5 ? 'transparent' : 'var(--dot)'}/>
      <ViewportPortal><div className="topic-layer">{topicFrames.map(f => f && <div key={f.topic.id} className="topic-frame" style={{ left: f.x, top: f.y, width: f.width, height: f.height }}><div className="topic-title" style={zoom < .5 ? { fontSize: 14/zoom, top: -32/zoom, gap: 7/zoom } : undefined}><NoteIcon name={f.topic.icon} size={zoom < .5 ? 16/zoom : 20}/><span>{f.topic.title}</span><small style={zoom < .5 ? { fontSize: 10/zoom } : undefined}>{f.count ? `${f.count} ${f.count === 1 ? 'Moment' : 'Momente'}` : ''}</small></div></div>)}</div></ViewportPortal>
    </ReactFlow>
    {!nodes.length && <div className="empty-board"><div className="empty-orbit"><PaplyMark size={64}/><span>✦</span></div><h1>Platz für das, was dir einfällt.</h1><p>Ein Gedanke oder fünf verschiedene.<br/>Sprich los. Hier finden sie zusammen.</p><button className="capture-empty" onClick={() => void run(() => api().capture()).catch(() => {})}><Mic size={18}/>Gedanke aufnehmen <kbd>{formatNotesShortcut(board.preferences.captureHotkey, board.preferences)}</kbd></button><span className="empty-hint">Oder Text und Bilder einfügen · ⌘V</span></div>}
    {drawing && <svg className="drawing-preview"><line x1={drawing.a.x-(surface.current?.getBoundingClientRect().left || 0)} y1={drawing.a.y-(surface.current?.getBoundingClientRect().top || 0)} x2={drawing.z.x-(surface.current?.getBoundingClientRect().left || 0)} y2={drawing.z.y-(surface.current?.getBoundingClientRect().top || 0)}/></svg>}
    <div className="board-tools notes-ui"><div className="tool-section">{[['select',MousePointer2,'Auswählen (V)'],['hand',Hand,'Verschieben (H)'],['sticky',StickyNote,'Haftnotiz (N)'],['text',Type,'Freier Text (T)'],['arrow',ArrowUpRight,'Pfeil (L)'],['line',Minus,'Linie (⇧L)']].map(([id, Icon, title]) => { const Component = Icon as typeof MousePointer2; return <IconButton key={id as string} title={title as string} active={tool === id} onClick={() => { setTool(id as string); setEditing(null); }}><Component size={19}/></IconButton>; })}<IconButton title="Tabelle einfügen" onClick={() => void create('table')}><Table2 size={19}/></IconButton><IconButton title="Bildschirm jetzt merken" onClick={() => void run(() => api().camera({ target: selected.size === 1 ? [...selected][0] : null, position: center() })).catch(() => {})}><Camera size={19}/></IconButton></div><div className="tool-section"><IconButton title={board.capture.active ? 'Gedanke sichern' : 'Gedanke aufnehmen'} className={`capture-button ${board.capture.active ? 'recording' : ''}`} onClick={() => void run(() => api().capture()).catch(() => {})}>{board.capture.active ? <Square size={16} fill="currentColor"/> : <Mic size={19}/>}</IconButton></div><div className="tool-section"><IconButton title="Rückgängig (⌘Z)" disabled={!board.canUndo} onClick={() => void run(() => api().undo()).catch(() => {})}><Undo2 size={18}/></IconButton><IconButton title="Wiederholen (⇧⌘Z)" disabled={!board.canRedo} onClick={() => void run(() => api().redo()).catch(() => {})}><Redo2 size={18}/></IconButton></div><div className="tool-section zoom-tools"><IconButton title="Verkleinern" onClick={() => void rf.zoomTo(Math.max(.1, zoom/1.15), { duration: 100 })}><Minus size={16}/></IconButton><button className="zoom-number" title="100 %" onClick={() => void rf.zoomTo(1, { duration: 100 })}>{Math.round(zoom*100)}<small>%</small></button><IconButton title="Vergrößern" onClick={() => void rf.zoomTo(Math.min(2.5, zoom*1.15), { duration: 100 })}><Plus size={16}/></IconButton><IconButton title="Alles zeigen (⇧1)" onClick={() => fit()}><Maximize size={17}/></IconButton></div></div>
    <div className="board-status notes-ui"><span className={pending.length ? 'waiting-dot' : 'saved-dot'}/>{board.capture.active ? 'Gedanke wird aufgenommen' : pending.length ? `${pending.length} ${pending.length === 1 ? 'Moment' : 'Momente'} im Eingang` : 'Lokal gesichert'}</div><div className="help-button notes-ui"><IconButton title="Bedienung" onClick={() => setHelp(!help)}><CircleHelp size={17}/></IconButton></div>
    {search && <div className="search-panel notes-ui"><div><Search size={18}/><input ref={searchInput} placeholder="Deine Gedanken durchsuchen …" aria-label="Gedanken durchsuchen" value={query} onChange={e => setQuery(e.target.value)}/><IconButton title="Suche schließen" onClick={() => setSearch(false)}><X size={17}/></IconButton></div>{results.map(n => <button key={n.id} onClick={() => { fit([n.id]); setSearch(false); setNodes(ns => ns.map(x => ({ ...x, selected: x.id === n.id }))); }}><NoteIcon name={n.icon}/><span><strong>{n.label}</strong><small>{n.text.slice(0, 120)}</small></span></button>)}{query && !results.length && <p>Kein Gedanke gefunden.</p>}</div>}
    {inbox && <aside className="inbox-panel notes-ui"><header><div><span className="eyebrow">DEINE MOMENTE</span><h2>Eingang</h2></div><IconButton title="Eingang schließen" onClick={() => setInbox(false)}><X size={18}/></IconButton></header>{!board.entries.length && <p className="muted">Deine Aufnahmen erscheinen hier.</p>}{[...board.entries].reverse().map(e => <div className="entry" key={e.id}><button onClick={() => openSource(e.id)}><Mic size={17}/><span><strong>{new Date(e.createdAt).toLocaleString('de-DE', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</strong><small>{({ complete: 'Eingeordnet', fallback: 'Original erhalten · Einordnung offen', captured: 'Ton gesichert', transcribing: 'Wird verschriftet', transcribed: 'Wartet auf Einordnung', structuring: 'Findet zusammen', kept_user: 'Deine Bearbeitung bleibt', empty: 'Keine Sprache erkannt', recording: 'Aufnahme läuft' } as Record<string,string>)[e.state] || e.message || 'Lokal gesichert'}</small></span></button>{e.state !== 'recording' && <div className="entry-actions"><button onClick={() => void run(() => api().retry(e.id)).catch(() => {})}>Erneut</button><IconButton title="Moment entfernen" onClick={() => void run(() => api().discard(e.id)).catch(() => {})}><Trash2 size={14}/></IconButton></div>}</div>)}<p className="budget-label">Notes heute: {Math.round(board.budget.tokens/1000)}k / {Math.round(board.preferences.dailyTokens/1000)}k Token · {Math.ceil(board.budget.audioSeconds/60)} Min.</p></aside>}
    {help && <aside className="help-panel notes-ui"><h3>Ein bisschen Platz zum Denken.</h3><p>Mit zwei Fingern verschieben, mit Pinch zoomen. Leertaste halten und ziehen bewegt die Fläche.</p><p>Doppelklick bearbeitet eine Notiz. Ziehe an den kleinen seitlichen Punkten, um Gedanken zu verbinden.</p><p>Linien auswählen und ihre Enden ziehen. ⇧ beim Zeichnen hält den Winkel.</p><p>⌘V fügt Text oder Bilder ein. ⌘Z nimmt deine letzte Änderung zurück.</p></aside>}
    {source && <div className="modal-backdrop notes-ui" onClick={() => setSource(null)}><section className="source-modal" onClick={e => e.stopPropagation()}><header><span><Quote size={19}/>Der ursprüngliche Gedanke</span><IconButton title="Original schließen" onClick={() => setSource(null)}><X size={19}/></IconButton></header><small>{new Date(source.entry.createdAt).toLocaleString('de-DE')}</small><p>{source.text || 'Der Ton ist gesichert. Der Text folgt nach der Verschriftung.'}</p>{source.audioUrl && <audio controls src={source.audioUrl}/>}<button className="copy-source" onClick={() => { if (source.text) void api().copy(source.text).then(() => notify('Original kopiert')); }}><Copy size={15}/>Kopieren</button></section></div>}
    {image && <div className="modal-backdrop notes-ui" onClick={() => setImage(null)}><section className="image-modal" onClick={e => e.stopPropagation()}><IconButton title="Bild schließen" onClick={() => setImage(null)}><X size={20}/></IconButton><img src={`paply-notes://asset/${image}`} alt="Gespeichertes Bild"/>{board.assets[image]?.analysis && <p>{board.assets[image].analysis!.caption}</p>}</section></div>}
    {toast && <div className="notes-toast notes-ui" role="status">{toast}</div>}
    </div></main></BoardContext.Provider>;
}
export function NotesApp() { return <ReactFlowProvider><Board/></ReactFlowProvider>; }
