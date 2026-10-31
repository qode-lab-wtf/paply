import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
const { near, acc, termCheck } = require('../dictation/term-guard');
const cases = JSON.parse(fs.readFileSync(new URL('../../shared/begriffe/faelle.json', import.meta.url)));
describe('Gemeinsame Begriffe',()=>{
 for(const c of cases.klang) it(c.name,()=>expect(near(c.term,c.text)).toBe(c.near));
 for(const c of cases.annahme) it(c.name,()=>expect(acc(c)).toBe(c.accept));
});
const response = (text,lp=-0.3)=>({text,language:'de',segments:[{text,start:0,end:3,avg_logprob:lp}]});
for(const mode of ['accept','reject','empty','fail']) it('Begriffsablauf '+mode,async()=>{
 let calls=1;
 const first=response('Hallo Lavi Min, wie geht es dir?');
 const result=await termCheck(first,mode==='empty'?'':'Law Min',async(language,prompt)=>{
  calls++; expect(language).toBe('de'); expect(prompt).toBe('Law Min, Law Min.');
  if(mode==='fail') throw Error('failed');
  return response('Hallo Law Min, wie geht es dir?',mode==='reject'?-0.9:-0.1);
 },10);
 expect(calls).toBe(mode==='empty'?1:2);
 expect(result.text).toBe(mode==='accept'?'Hallo Law Min, wie geht es dir?':first.text);
});
it('accepted term survives polish safety net',()=>{
 const { polishRejection } = require('../dictation/polish');
 expect(polishRejection('hallo Law Min wie geht es dir','Hallo Law Min, wie geht es dir?',{vocabulary:'Law Min'})).toBeNull();
});
it('request timeout AbortError keeps first; caller cancellation propagates',async()=>{
 const first=response('Hallo Lavi Min, wie geht es dir?');
 const timeout=()=>{throw Object.assign(new Error('timeout'),{name:'AbortError'})};
 expect(await termCheck(first,'Law Min',timeout,1)).toBe(first);
 const controller=new AbortController();controller.abort();
 await expect(termCheck(first,'Law Min',timeout,1,controller.signal)).rejects.toThrow();
});
for(const [text,lp,second,calls] of [
 ['Lamin danke.',-.3,'Law Min, Law Min.',1],
 ['Vielen Dank.',-.9,'Law Min.',0],
 ['Das Wetter ist heute schön.',-.3,'Law Min.',0],
 ['Das Wetter ist heute schön.',-.9,'Law Min.',0],
]) it('only sound triggers; echo rejected: '+text+lp,async()=>{
 let requests=0;const first=response(text,lp);
 const result=await termCheck(first,'Law Min',async()=>{requests++;return response(second,-.1)},1);
 expect(requests).toBe(calls);expect(result).toBe(first);
});
it('at most three repeated candidates without greeting',()=>{
 const {candidates}=require('../dictation/term-guard');
 const c=candidates('Law Min;Law Min;Law Min;Law Min',response('Lamin'));
 expect(c.terms).toHaveLength(3);expect(c.prompt).toBe('Law Min, Law Min. Law Min, Law Min. Law Min, Law Min.');
});
