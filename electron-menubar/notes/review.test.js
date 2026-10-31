import { it, expect } from 'vitest';
import { validate, applyThought } from './thought';
import { fallbackTitle, locateQuote, sameNamed, tidyTask, effectiveNegations } from './thought-text';
import { blankBoard, node } from './contracts';
import { context } from './context';
import { createGroq } from './groq';
import { createLedger } from './ledger';
import { buildPrompt, estimateTokens } from '../dictation/whisper-prompt';
const ctx = text => ({sentences:[{text}],topics:[],existing:[]});
const answer = text => ({title:'Milch kaufen',clean_text:text,topic:{choice:'none'},tasks:[],related:[]});
it('1: medium uses the lexical scale; high trusts model confidence',()=>{
 const a='Die Wohnung in Berlin braucht neue Fenster.',b='Neue Fenster für unsere Wohnung in Berlin bestellen.';
 const board=blankBoard(),n=node({kind:'note',text:b});n.label='Fenster bestellen';board.nodes[n.id]=n;
 const c=context(board,[{text:a}]);expect(c.existing[0].score).toBeGreaterThanOrEqual(.2);expect(c.existing[0].score).toBeLessThan(.75);
 for(const confidence of ['high','medium']) expect(validate({...answer(a),related:[{ref:n.id,confidence,kind:'same_matter',reason:'Fenster der Wohnung'}]},c).related).toHaveLength(1);
 expect(validate({...answer(a),related:[{ref:n.id,confidence:'medium',kind:'same_matter',reason:'Fenster'}]},{...c,existing:[{...c.existing[0],score:.05}]}).related).toHaveLength(0);
});
it('2: retains long, fuzzy and elided quotes, normalizes model hyphens and inflections',()=>{
 const text='Ich muss morgen die ausführlichen Unterlagen für die neue Wohnung in Berlin mit Anna gemeinsam durchsehen und anschließend abschicken.';
 const r=validate({...answer(text),tasks:[{text:'Unterlagen durchsehen und abschicken',quote:text,due_hint:'morgen'}]},ctx(text));expect(r.tasks).toHaveLength(1);
 expect(locateQuote('ICH muss morgen die ausführlichen Unterlagen',text)).toBe('Ich muss morgen die ausführlichen Unterlagen');
 expect(locateQuote('Ich muss morgen die ausführlichen Dokumente für die neue Wohnung in Berlin',text)).toContain('Unterlagen');
 expect(locateQuote('Unterlagen … anschließend abschicken',text)).toContain('gemeinsam');
 const t='Ich muss das Kita-Dashboard öffnen.';expect(validate({...answer(t),clean_text:t.replace('-','‑')},ctx(t)).text).toBe(t);
 expect(effectiveNegations('Don’t forget milk')).toBe(0);expect(effectiveNegations('Vergessen Sie nicht Milch kaufen')).toBe(0);
 expect(tidyTask('morgen Anna anrufen', 'morgen')).toBe('Anna anrufen');expect(tidyTask('nicht morgen Anna anrufen','morgen')).toBe('Nicht morgen Anna anrufen');
});
it('3: real ledger can send the medium retry after a consumed invalid response',async()=>{
 const records={};const ledger=createLedger({readLocal:(_,d)=>d,writeLocal:(k,v)=>records[k]=v},()=>({dailyTokens:100000}));let calls=0;const efforts=[];
 const groq=createGroq({getKey:()=> 'test',ledger,fetchImpl:async(_,r)=>{efforts.push(JSON.parse(r.body).reasoning_effort);calls++;return new Response(JSON.stringify({usage:{total_tokens:500},choices:[{finish_reason:'stop',message:{content:JSON.stringify(calls===1?{}:answer('Milch kaufen'))}}]}));}});
 await groq.plan(ctx('Milch kaufen'));expect(efforts).toEqual(['low','medium']);
});
it('4,10: five tasks per part, ten per source, pinned geometry survives',()=>{
 const b=blankBoard();for(let i=0;i<3;i++){const n=node({kind:'note',text:'Milch kaufen'});n.owner='ai';n.sourceId='same';n.pinned=true;n.position={x:12,y:23};n.width=456;n.height=234;b.nodes[n.id]=n;applyThought(b,{title:'Milch',text:'Milch kaufen',tasks:Array.from({length:5},(_,j)=>({text:`Teil ${i} Aufgabe ${j}`,quote:`${i}-${j}`})),related:[]},{rawId:n.id,rawRev:n.rev});expect(n).toMatchObject({pinned:true,position:{x:12,y:23},width:456,height:234});}expect(Object.values(b.tasks)).toHaveLength(10);
});
it('6: fallback filters fillers and indicates truncation; CJK and inflections survive',()=>{
 expect(fallbackTitle('Ähm, eins zwei drei vier fünf sechs sieben')).toBe('eins zwei drei vier fünf sechs …');
 for(const [text,title] of [['Ich kaufe die größeren Töpfe.','Größere Töpfe kaufen'],['明日東京で友達と会います','東京で友達']])expect(validate({...answer(text),title},ctx(text)).title).toBe(title);
});
it('7: topics match plural, umlaut spelling, typo; preserve distinct names',()=>{
 for(const [name,title] of [['Wohnungen','Wohnung'],['Kuechenplan','Küchenplan'],['Wohnugnsplan','Wohnungsplan']])expect(sameNamed(name,[{id:'t',title}])).toHaveLength(1);
 for(const [name,title] of [['Küchen','Kuchen'],['Fischer','Fisch'],['Busse','Buße']])expect(sameNamed(name,[{id:'t',title}])).toHaveLength(0);
});
it('8: input aliases, normalized terms, optional topic data and short excerpts',async()=>{
 let input;const groq=createGroq({getKey:()=> 'test',ledger:{reserve:()=>1,settle:()=>{}},getTranscriptionSettings:()=>({systemLanguages:['de-DE']}),fetchImpl:async(_,r)=>{input=JSON.parse(JSON.parse(r.body).messages[1].content);return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify({...answer('Milch kaufen'),topic:{choice:'existing',id:'t1'}})}}]}));}});
 const r=await groq.plan({...ctx('Milch kaufen'),custom_terms:'Alpha;Beta\nGamma',topics:[{id:'secret-real-id',title:'Einkauf',about:'Die Liste',mentioned:true}],existing:[{id:'n',text:'x'.repeat(400),topic:'secret-real-id',createdAt:Date.now()}]});
 expect(r.topic.id).toBe('secret-real-id');expect(input.topics[0]).toMatchObject({id:'t1',about:'Die Liste',mentioned:true});expect(input.candidates[0].excerpt).toHaveLength(160);expect(input.candidates[0].when).toContain('heute');expect(input.custom_terms).toBe('Alpha, Beta, Gamma');expect(input.now).toMatch(/Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag/);
});
it('13: dense vocabulary retains whole leading terms across separators',()=>{
 for(const separator of [',',';','\n']){const prompt=buildPrompt(Array(40).fill('漢字漢字').join(separator));expect(prompt).not.toBe('');expect(prompt).toMatch(/^漢字漢字/);expect(estimateTokens(prompt)).toBeLessThanOrEqual(92);}
});
