'use strict';
const C = require('./contracts');
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const TABLES = ['tasks', 'nodes', 'edges', 'topics', 'claims', 'tombstones'];
function changes(before, after) {
  const result = [];
  for (const table of TABLES) for (const key of new Set([...Object.keys(before[table]), ...Object.keys(after[table])])) {
    if (!same(before[table][key], after[table][key])) result.push({ table, key, before: before[table][key], after: after[table][key] });
  }
  return result;
}
function createCommands(repo, onChange = () => {}) {
  const undo = [], redo = [];
  function commit(fn, user = true) {
    const before = repo.snapshot(), next = C.clone(before); fn(next);
    const delta = changes(before, next);
    if (!delta.length && same(before.viewport, next.viewport)) return before;
    const saved = repo.save(next);
    if (user && delta.length) { undo.push(delta); if (undo.length > 200) undo.shift(); redo.length = 0; }
    onChange(); return saved;
  }
  function apply(ops) {
    C.assert(Array.isArray(ops) && ops.length > 0 && ops.length <= 200);
    return commit(b => {
      for (const op of ops) {
        C.assert(op && typeof op.type === 'string');
        if (op.type === 'task') {
          const t = b.tasks[C.id(op.id)]; C.assert(t);
          if (op.text !== undefined) t.text = C.text(op.text, 200);
          if (op.due_hint !== undefined) t.due_hint = op.due_hint === null ? null : C.text(op.due_hint, 200);
          if (op.done !== undefined) { C.assert(typeof op.done === 'boolean'); t.done = op.done; }
          t.owner = 'user';
        } else if (op.type === 'create') { const n = C.node(op.node); if (n.topicId) C.assert(b.topics[n.topicId]); b.nodes[n.id] = n; }
        else if (op.type === 'update') {
          const n = b.nodes[C.id(op.id)]; C.assert(n, 'Diese Notiz wurde bereits entfernt.');
          if (op.rev !== undefined) C.assert(op.rev === n.rev, 'Die Notiz hat sich geändert. Bitte erneut bearbeiten.');
          const p = C.patch(op.patch); if (p.topicId) C.assert(b.topics[p.topicId]);
          const contentChanged = Object.keys(p).some(k => !['position', 'width', 'height'].includes(k));
          Object.assign(n, p, { ...(contentChanged ? { owner: 'user' } : { pinned: true }), rev: n.rev + 1 });
          if (p.table) n.text = [['', ...p.table.columns].join('\t'), ...p.table.rows.map(r => [r.label, ...r.cells].join('\t'))].join('\n');
        } else if (op.type === 'delete') {
          const n = b.nodes[C.id(op.id)]; if (!n) continue;
          for (const sid of n.sentenceIds) b.claims[sid] = { tomb: true };
          b.tombstones[n.id] = Date.now(); delete b.nodes[n.id]; for (const [tid, task] of Object.entries(b.tasks || {})) if (task.nodeId === n.id && task.owner !== 'user') delete b.tasks[tid];
          for (const [eid, e] of Object.entries(b.edges)) if (e.source === n.id || e.target === n.id) { b.tombstones[eid] = Date.now(); delete b.edges[eid]; }
        } else if (op.type === 'duplicate') {
          const n = b.nodes[C.id(op.id)]; C.assert(n); const copy = C.clone(n);
          Object.assign(copy, { id: C.uid(), sourceId: null, sentenceIds: [], owner: 'user', rev: 1, position: { x: (n.position?.x || 0) + 36, y: (n.position?.y || 0) + 36 } }); b.nodes[copy.id] = copy;
        } else if (op.type === 'edge') {
          const source = C.id(op.source), target = C.id(op.target); C.assert(b.nodes[source] && b.nodes[target] && source !== target);
          const eid = op.id ? C.id(op.id) : C.uid('e'); if (op.id) C.assert(b.edges[eid]);
          b.edges[eid] = { id: eid, source, target, sourceHandle: op.sourceHandle === 'left' ? 'left' : 'right', targetHandle: op.targetHandle === 'right' ? 'right' : 'left', arrow: op.arrow !== false, inferred: false, label: '', rev: (b.edges[eid]?.rev || 0) + 1 };
          for (const nid of [source, target]) { b.nodes[nid].pinned = true; b.nodes[nid].rev++; }
        } else if (op.type === 'deleteEdge') { const eid = C.id(op.id); delete b.edges[eid]; b.tombstones[eid] = Date.now(); }
        else if (op.type === 'line') {
          const a = C.node({ kind: 'point', position: C.point(op.from) }), z = C.node({ kind: 'point', position: C.point(op.to) });
          b.nodes[a.id] = a; b.nodes[z.id] = z; const eid = C.uid('e');
          b.edges[eid] = { id: eid, source: a.id, target: z.id, sourceHandle: 'right', targetHandle: 'left', arrow: op.arrow !== false, inferred: false, label: '', rev: 1 };
        } else if (op.type === 'topic') { const tid = C.uid('t'); b.topics[tid] = { id: tid, title: C.text(op.title, 60), icon: 'lightbulb', owner: 'user', createdAt: Date.now() }; }
        else throw new Error('Unbekannter Notes-Befehl');
      }
      const connected = new Set(Object.values(b.edges).flatMap(e => [e.source, e.target]));
      for (const [nid, n] of Object.entries(b.nodes)) if (n.kind === 'point' && !connected.has(nid)) delete b.nodes[nid];
    });
  }
  function travel(from, to) {
    const delta = from.at(-1); if (!delta) return repo.snapshot();
    const b = repo.snapshot(); const reversed = [];
    // Conditional inverses do not erase later AI/user commits on the same object.
    for (const d of [...delta].reverse()) if (same(b[d.table][d.key], d.after)) {
      if (d.before === undefined) delete b[d.table][d.key]; else b[d.table][d.key] = C.clone(d.before);
      reversed.push({ ...d, before: d.after, after: d.before });
    }
    // No dangling edges can survive a partial undo.
    for (const [eid, e] of Object.entries(b.edges)) if (!b.nodes[e.source] || !b.nodes[e.target]) delete b.edges[eid];
    const saved = repo.save(b); from.pop(); if (reversed.length) to.push(reversed); onChange(); return saved;
  }
  return { apply, commit, undo: () => travel(undo, redo), redo: () => travel(redo, undo), canUndo: () => !!undo.length, canRedo: () => !!redo.length,
    place(positions) { C.assert(Array.isArray(positions) && positions.length <= 500); return commit(b => { positions.forEach(p => { const n = b.nodes[C.id(p.id)]; if (n && n.position === null) n.position = C.point(p.position); }); }, false); },
    viewport(v) { return repo.saveViewport(v); },
  };
}
module.exports = { createCommands, changes };
