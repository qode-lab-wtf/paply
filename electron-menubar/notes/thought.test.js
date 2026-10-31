import { it, expect, vi, afterEach } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { PROMPT } from './prompt';
import { SCHEMA, validate, applyThought } from './thought';
import { polishRejection } from './safety';
import { createGroq } from './groq';
import { createRepo } from './repo';
import { createCommands } from './commands';
import { createCapture } from './capture';
import { blankBoard, node, validBoard } from './contracts';
import { context } from './context';
const raw = 'Ich muss morgen Milch kaufen.';
const ctx = { sentences: [{ id: 's1', text: raw }], topics: [], existing: [] };
const answer = () => ({ title: 'Milch kaufen', clean_text: raw, topic: { choice: 'none', id: null, new_name: null, symbol: 'sparkles' }, tasks: [{ text: 'Milch kaufen', quote: raw, due_hint: 'morgen' }], related: [] });
afterEach(() => vi.useRealTimers());
it('embeds the canonical prompt byte for byte and uses the mobile strict schema', () => {
 expect(PROMPT).toBe(fs.readFileSync('../shared/gedanken/system-prompt-v6.txt', 'utf8'));
 expect(PROMPT).toBe(fs.readFileSync('../android/thoughts/src/test/resources/thought-system-v6.txt', 'utf8'));
 expect(SCHEMA.required).toEqual(['clean_text','related','tasks','title','topic']);
 const check = s => { if(s.type==='object') { expect(s.additionalProperties).toBe(false); expect(s.required).toEqual(Object.keys(s.properties).sort()); Object.values(s.properties).forEach(check); } if(s.items) check(s.items); }; check(SCHEMA);
 expect(SCHEMA.properties.topic.properties.symbol.enum).toHaveLength(24);
});
it.each(JSON.parse(fs.readFileSync('../shared/polish/safety-cases.json')).filter(c => c.profile === 'thought'))('thought safety profile $raw', c => expect(polishRejection(c.raw, c.result, { profile: 'thought', vocabulary: c.vocabulary })).toBe(c.expected));
it.each([null, {}, { ...answer(), title: '', clean_text: '' }])('rejects unreadable or wholly empty output %j', a => expect(() => validate(a,ctx)).toThrow());
it.each(['', 'x'.repeat(61), 'Milch 2029'])('falls back only the title %s', title => { const r=validate({...answer(),title},ctx); expect(r.title).toBe(raw); expect(r.tasks).toHaveLength(1); });
it.each(['', 'I must buy milk tomorrow.', raw+' Es gibt viele neue Dinge zu erledigen.'])('retains raw text for unsafe cleanup %s', clean_text => { const r=validate({...answer(),clean_text},ctx); expect(r.text).toBe(raw); expect(r.tasks).toHaveLength(1); });
it.each([{quote:'erfunden'}, {quote:'x'.repeat(81)}, {text:'x'}, {text:'x'.repeat(81)}, {text:'Milch 42 kaufen'}, {text:'Milch nicht kaufen'}, {text:'Raketen weltweit entsorgen'}])('drops only an invalid task %j', patch => { const a=answer(); Object.assign(a.tasks[0],patch); expect(validate(a,ctx).tasks).toEqual([]); expect(validate(a,ctx).text).toBe(raw); });
it('drops invented due hints, duplicates and tasks over five', () => { const a=answer(); a.tasks[0].due_hint='Freitag'; a.tasks.push(a.tasks[0]); const r=validate(a,ctx); expect(r.tasks).toHaveLength(1); expect(r.tasks[0].due_hint).toBeNull(); });
it.each([{choice:'existing',id:'missing'}, {choice:'new',new_name:'Ideen'}, {choice:'new',new_name:'x'.repeat(25)}, {choice:'new',new_name:'Garten 2027'}, {choice:'unknown'}])('drops invalid topic %j', topic => expect(validate({...answer(),topic},ctx).topic).toBeNull());
it('reuses a known topic, creates a bounded new topic and respects full topics', () => {
 const topic={choice:'new',new_name:'Garten',symbol:'leaf'};
 expect(validate({...answer(),topic},ctx).topic.name).toBe('Garten');
 expect(validate({...answer(),topic},{...ctx,topics:[{id:'t',title:'Garten'}]}).topic).toEqual({id:'t'});
 expect(validate({...answer(),topic},{...ctx,topics_full:true}).topic).toBeNull();
});
it.each(['high','medium','low'])('requires local evidence for %s links', confidence => {
 const a={...answer(),related:[{ref:'n',kind:'continues',reason:'Milch kaufen',confidence}]};
 const candidate={id:'n',score:.75,label:'Milch',text:raw};
 expect(validate(a,{...ctx,existing:[candidate]}).related).toHaveLength(confidence==='low'?0:1);
 expect(validate(a,{...ctx,existing:[{...candidate,score:.74}]}).related).toHaveLength(0);
 expect(validate({...a,related:[{...a.related[0],reason:'x'.repeat(61)}]},{...ctx,existing:[candidate]}).related).toHaveLength(0);
});
it('preserves old forms and user-owned/completed tasks through AI retries', () => {
 const b=blankBoard(), n=node({kind:'table',text:raw}); n.owner='ai';n.sourceId='s';b.nodes[n.id]=n;
 const r=validate(answer(),ctx); applyThought(b,r,{rawId:n.id,rawRev:n.rev}); const task=Object.values(b.tasks)[0]; task.done=true;task.owner='user';task.text='Eigene Änderung';
 applyThought(b,r,{rawId:n.id,rawRev:n.rev}); expect(Object.values(b.tasks)).toHaveLength(1);expect(task.text).toBe('Eigene Änderung'); expect(n.kind).toBe('table');expect(validBoard(b)).toBe(true);
 n.owner='user';expect(applyThought(b,r,{rawId:n.id,rawRev:n.rev})).toBe(false);
});
it('loads a legacy board without tasks unchanged and bounds retrieval', () => {
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'thought-legacy-'));try { const b=blankBoard();delete b.tasks;fs.writeFileSync(path.join(dir,'board.json'),JSON.stringify(b));const repo=createRepo(dir);expect(repo.current().tasks).toEqual({});expect(repo.entries()).toEqual([]);
 for(let i=0;i<40;i++){b.topics['t'+i]={id:'t'+i,title:'Thema',icon:'leaf'};const n=node({kind:'note',text:raw});b.nodes[n.id]=n;}
 const c=context(b,ctx.sentences);expect(c.topics).toHaveLength(32);expect(c.existing).toHaveLength(8);
 } finally {fs.rmSync(dir,{recursive:true,force:true});}
});
const ok = () => new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify(answer())}}]}));
function transport(responses) { const bodies=[];const groq=createGroq({getKey:()=> 'fake',ledger:{reserve:()=> 'r',settle:()=>{}},fetchImpl:async(_,r)=>{bodies.push(JSON.parse(r.body));return responses.shift()();}});return {groq,bodies}; }
it.each([404,429])('switches from 120b to 20b on %s', async status=>{const t=transport([()=>new Response('{}',{status,headers:{'retry-after':'21'}}),ok]);await t.groq.plan(ctx,false);expect(t.bodies.map(b=>b.model)).toEqual(['openai/gpt-oss-120b','openai/gpt-oss-20b']);expect(t.bodies[0].response_format.json_schema.schema).toEqual(SCHEMA);});
it('retries invalid output once with medium reasoning', async()=>{const t=transport([()=>new Response(JSON.stringify({choices:[{finish_reason:'length'}]})),ok]);await t.groq.plan(ctx,false);expect(t.bodies.map(b=>b.reasoning_effort)).toEqual(['low','medium']);});
it('waits after both models hit the limit', async()=>{const rate=()=>new Response('{}',{status:429,headers:{'retry-after':'21'}});const t=transport([rate,rate]);await expect(t.groq.plan(ctx,false)).rejects.toMatchObject({kind:'rate',retryMs:900000});});
it('waits once for a short limit before retrying the same model', async()=>{vi.useFakeTimers();const t=transport([()=>new Response('{}',{status:429,headers:{'retry-after':'0.001'}}),ok]);const pending=t.groq.plan(ctx,false);await vi.waitFor(()=>expect(t.bodies).toHaveLength(1));await vi.advanceTimersByTimeAsync(1100);await pending;expect(t.bodies.map(b=>b.model)).toEqual(['openai/gpt-oss-120b','openai/gpt-oss-120b']);});
it('warns at 29 minutes and saves normally at 30 minutes', async()=>{
 vi.useFakeTimers();const dir=fs.mkdtempSync(path.join(os.tmpdir(),'thought-limit-'));const repo=createRepo(dir), commands=createCommands(repo),send=vi.fn();
 const capture=createCapture({repo,commands,getSettings:()=>({enabled:true}),isDictating:()=>false,isMeetingActive:()=>false,show:async()=>{},send,hide:()=>{},screenshot:()=>{}});
 try {await capture.start();const id=capture.status().entryId;capture.accept({entryId:id,epoch:1,seq:1,bytes:new Int16Array(8000).buffer});await vi.advanceTimersByTimeAsync(29*60000);expect(send.mock.calls.at(-1)[0].detail).toContain('Noch 1 Min.');await vi.advanceTimersByTimeAsync(60000);capture.flushed({entryId:id,epoch:1});expect(repo.entry(id).message).toBe('Nach 30 Min. gespeichert');expect(send.mock.calls.at(-1)[0].phase).toBe('saved');}finally{capture.shutdown();fs.rmSync(dir,{recursive:true,force:true});}
});
it('task edits and completion persist and undo without touching the source', () => {
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'thought-owner-'));try {const repo=createRepo(dir),commands=createCommands(repo);commands.commit(b=>{const n=node({kind:'note',text:raw});n.owner='ai';n.sourceId='s';b.nodes[n.id]=n;applyThought(b,validate(answer(),ctx),{rawId:n.id,rawRev:n.rev});},false);const task=Object.values(repo.current().tasks)[0];commands.apply([{type:'task',id:task.id,text:'Mein Text',due_hint:'Freitag',done:true}]);expect(createRepo(dir).current().tasks[task.id]).toMatchObject({text:'Mein Text',done:true,owner:'user'});commands.undo();expect(repo.current().tasks[task.id].done).toBe(false);}finally{fs.rmSync(dir,{recursive:true,force:true});}
});
it('rejects malformed links and deduplicates accepted references',()=>{const c={...ctx,existing:[{id:'n',score:1,label:'Milch',text:raw}]};const link={ref:'n',kind:'continues',reason:'Milch',confidence:'high'};for(const patch of [{ref:'unknown'},{kind:'invented'},{reason:''},{reason:'Milch 999'}])expect(validate({...answer(),related:[{...link,...patch}]},c).related).toEqual([]);expect(validate({...answer(),related:[link,link,link,link]},c).related).toHaveLength(1);});
it('caps tasks at five and does not accept a reversed due expression',()=>{const text='Ich muss morgen früh Milch kaufen.';const a={...answer(),tasks:Array.from({length:7},(_,i)=>({text:'Milch kaufen '+i,quote:text,due_hint:'früh morgen'}))};expect(validate(a,{...ctx,sentences:[{id:'s',text}]}).tasks).toEqual([]);a.tasks=[{text:'Milch kaufen',quote:text,due_hint:'früh morgen'}];expect(validate(a,{...ctx,sentences:[{id:'s',text}]}).tasks[0].due_hint).toBeNull();});
it('rejects a translated title even when proper names overlap',()=>{const transcript='Demain je vais retrouver Sophie au café. Nous parlerons de notre voyage à Lyon.';const r=validate({...answer(),title:'Treffen mit Sophie in Lyon',clean_text:transcript,tasks:[]},{...ctx,spoken_languages:['fr'],ui_language:'de',sentences:[{id:'s',text:transcript}]});expect(r.title).toBe('Demain je vais retrouver Sophie au');expect(r.text).toBe(transcript);});
it('retains only the first five grounded tasks',()=>{const tasks=Array.from({length:7},(_,i)=>({text:`Milch ${i} kaufen`,quote:`Ich muss Milch ${i} kaufen.`,due_hint:null}));const text=tasks.map(t=>t.quote).join(' ');expect(validate({...answer(),clean_text:text,tasks},{...ctx,sentences:[{id:'s',text}]}).tasks).toHaveLength(5);});
it('all-invalid model responses receive exactly one reasoning retry',async()=>{const bad=()=>new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:'{}'}}]}));const t=transport([bad,bad]);await expect(t.groq.plan(ctx,false)).rejects.toMatchObject({kind:'plan'});expect(t.bodies).toHaveLength(2);});
it('recognizes a missing-model provider code even with HTTP 400',async()=>{const t=transport([()=>new Response(JSON.stringify({error:{code:'model_decommissioned'}}),{status:400}),ok]);await t.groq.plan(ctx,false);expect(t.bodies[1].model).toBe('openai/gpt-oss-20b');});
