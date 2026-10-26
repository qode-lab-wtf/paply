import type { Note, XY } from '@/types/notes';
export type Rect = XY & { width: number; height: number };
export function heightFor(n: Note) {
  if (n.height) return n.height;
  if (n.kind === 'point') return 12;
  if (n.kind === 'hub') return 150;
  if (n.kind === 'table') return 130 + (n.table?.rows.length || 1) * 115;
  if (n.kind === 'image') return 260;
  return 100 + Math.min(12, Math.ceil(n.text.length / Math.max(16, n.width / 10))) * 29 + (n.attachments.length ? 90 : 0);
}
export const overlaps = (a: Rect, b: Rect, gap = 38) => a.x < b.x + b.width + gap && a.x + a.width + gap > b.x && a.y < b.y + b.height + gap && a.y + a.height + gap > b.y;
export function placeNotes(notes: Note[], topicIds: string[], measured: Record<string, { width?: number; height?: number }> = {}): Record<string, XY> {
  const result: Record<string, XY> = {};
  const size = (n: Note) => ({ width: measured[n.id]?.width || n.width, height: measured[n.id]?.height || heightFor(n) });
  const occupied: Rect[] = notes.filter(n => n.position && n.kind !== 'point').map(n => ({ ...n.position!, ...size(n) }));
  const batches = new Map<string, Note[]>();
  for (const n of notes.filter(n => !n.position)) { const k = n.structureId || n.id; batches.set(k, [...(batches.get(k) || []), n]); }
  for (const members of batches.values()) {
    const first = members[0], topic = topicIds.indexOf(first.topicId || ''), origin = topic < 0 ? { x: -650, y: 80 } : { x: (topic % 3) * 1500 + 80, y: Math.floor(topic / 3) * 1500 + 80 };
    const local: Record<string, XY> = {};
    if (first.structureKind === 'mindmap') {
      const hub = members.find(n => n.kind === 'hub'), branches = members.filter(n => n !== hub).sort((a, b) => (a.order || 0) - (b.order || 0));
      const step = Math.max(250, ...branches.map(n => size(n).height + 65));
      if (hub) local[hub.id] = { x: 450, y: Math.max(100, (Math.ceil(branches.length / 2) * step) / 2 - 80) };
      branches.forEach((n, i) => { local[n.id] = { x: i % 2 ? 900 : 0, y: Math.floor(i / 2) * step }; });
    } else if (first.structureKind === 'flow') {
      let x = 0; members.sort((a, b) => (a.order || 0) - (b.order || 0)).forEach(n => { local[n.id] = { x, y: 0 }; x += size(n).width + 110; });
    } else members.forEach((n, i) => { local[n.id] = { x: i * 390, y: 0 }; });
    let y = origin.y, attempts = 0;
    const rectangles = () => members.map(n => ({ x: origin.x + local[n.id].x, y: y + local[n.id].y, ...size(n) }));
    while (rectangles().some(r => occupied.some(o => overlaps(r, o))) && attempts++ < 2000) y += 90;
    members.forEach(n => { result[n.id] = { x: origin.x + local[n.id].x, y: y + local[n.id].y }; occupied.push({ ...result[n.id], ...size(n) }); });
  }
  return result;
}
export function bounds(notes: Note[]): Rect|null {
  const list = notes.filter(n => n.position && n.kind !== 'point'); if (!list.length) return null;
  const x = Math.min(...list.map(n => n.position!.x)), y = Math.min(...list.map(n => n.position!.y));
  return { x, y, width: Math.max(...list.map(n => n.position!.x + n.width)) - x, height: Math.max(...list.map(n => n.position!.y + heightFor(n))) - y };
}
