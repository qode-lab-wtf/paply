import { describe, it, expect } from 'vitest';
import { placeNotes, overlaps, heightFor } from './layout';
import type { Note } from '@/types/notes';
const note = (id: string, extra: Partial<Note> = {}): Note => ({ id, kind: 'note', text: 'Ein ganzer Gedanke.', label: 'Idee', icon: 'lightbulb', position: null, width: 320, height: null, topicId: 't1', sourceId: null, sentenceIds: [], attachments: [], owner: 'ai', rev: 1, createdAt: 0, ...extra });
describe('stable canvas placement', () => {
  it('is deterministic and never repositions existing elements', () => { const list = [note('a'),note('b'),note('c')]; expect(placeNotes(list,['t1'])).toEqual(placeNotes(list,['t1'])); const positions = placeNotes(list,['t1']); const placed = list.map(n => ({ ...n, position: positions[n.id] })); expect(placeNotes(placed,['t1'])).toEqual({}); });
  it('fits measured long text around a user-positioned obstacle', () => { const old = note('fixed',{position:{x:80,y:80},height:700}); const list = [old,note('next')]; const result = placeNotes(list,['t1'],{ next:{height:850} }); expect(overlaps({ ...old.position!,width:320,height:700 },{ ...result.next,width:320,height:850 })).toBe(false); });
  it('arranges actual mindmap branches with measured heights and no overlap', () => { const list = [note('hub',{kind:'hub',structureId:'g',structureKind:'mindmap',order:-1}),...Array.from({length:5},(_,i)=>note(`n${i}`,{structureId:'g',structureKind:'mindmap',order:i,height:300+i*50}))]; const positions = placeNotes(list,['t1']); for(let a=0;a<list.length;a++)for(let b=a+1;b<list.length;b++)expect(overlaps({ ...positions[list[a].id],width:list[a].width,height:heightFor(list[a]) },{ ...positions[list[b].id],width:list[b].width,height:heightFor(list[b]) },0)).toBe(false); });
});
