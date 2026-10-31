import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRepo } from './repo.js';
import { createCommands } from './commands.js';
import { createQueue } from './queue.js';
import { createCapture } from './capture.js';

function fixture() {
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'paply-independent-'));
 const repo=createRepo(directory),commands=createCommands(repo);let request,release;
 const gate=new Promise(r=>{release=r});
 const queue=createQueue({repo,commands,getSettings:()=>({}),getKey:()=> 'paply-notes-test-key',assets:{pending:()=>[]},groq:{async plan(ctx){request=ctx;await gate;return{title:'Gedanke',clean_text:ctx.sentences.map(s=>s.text).join(' '),topic:{choice:'none'},tasks:[],related:[]}}}});
 return {repo,commands,queue,request:()=>request,release,async finish(){release();for(let i=0;i<8;i++){await Promise.resolve();await queue.tick();}},close(){queue.stop();fs.rmSync(directory,{recursive:true,force:true})}};
}
describe('Independent Notes acceptance regressions',()=>{
 it('stop during a slow recorder-window load cannot restart the microphone',async()=>{
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'paply-capture-race-'));
  const repo=createRepo(directory),commands=createCommands(repo),events=[];let ready;
  const loading=new Promise(r=>{ready=r});
  const capture=createCapture({repo,commands,getSettings:()=>({enabled:true}),isDictating:()=>false,isMeetingActive:()=>false,show:()=>loading,send:s=>events.push(s.phase),hide:()=>{},screenshot:()=>Promise.resolve(Buffer.alloc(0))});
  try{const started=capture.start();capture.stop();ready();await started;const stoppedAt=events.indexOf('stop');expect(stoppedAt).toBeGreaterThanOrEqual(0);expect(events.slice(stoppedAt+1)).not.toContain('start');}
  finally{capture.shutdown();fs.rmSync(directory,{recursive:true,force:true})}
 });
 it('pasted text is immediately visible and can become a sourced note',async()=>{
  const f=fixture();try{
   const id=f.queue.addText('Die Preise kenne ich noch nicht. Eine Frage bleibt offen.',{x:50,y:60});
   expect(Object.values(f.repo.snapshot().nodes).map(n=>n.text).join(' ')).toContain('Die Preise kenne ich noch nicht.');
   expect(f.repo.transcript(id).text).toBe('Die Preise kenne ich noch nicht. Eine Frage bleibt offen.');
   await f.finish();expect(f.repo.entry(id).state).toBe('complete');expect(Object.values(f.repo.snapshot().nodes).map(n=>n.text).join(' ')).toBe('Die Preise kenne ich noch nicht. Eine Frage bleibt offen.');
  }finally{f.close()}
 });
 it('a delayed plan cannot overwrite a manual edit of its raw note',async()=>{
  const f=fixture();try{
   const id=f.queue.addText('Ursprünglicher Gedanke.');const raw=Object.values(f.repo.snapshot().nodes)[0];expect(raw).toBeDefined();expect(f.request()).toBeDefined();
   f.commands.apply([{type:'update',id:raw.id,patch:{text:'Meine bewusste Änderung.'}}]);await f.finish();
   expect(Object.values(f.repo.snapshot().nodes).map(n=>n.text)).toEqual(['Meine bewusste Änderung.']);expect(f.repo.transcript(id).text).toBe('Ursprünglicher Gedanke.');
  }finally{f.close()}
 });
 it('a delayed plan cannot restore a deleted raw note',async()=>{
  const f=fixture();try{
   const id=f.queue.addText('Diesen Gedanken entferne ich.');const raw=Object.values(f.repo.snapshot().nodes)[0];expect(raw).toBeDefined();
   f.commands.apply([{type:'delete',id:raw.id}]);await f.finish();expect(Object.keys(f.repo.snapshot().nodes)).toHaveLength(0);expect(f.repo.transcript(id).text).toBe('Diesen Gedanken entferne ich.');
  }finally{f.close()}
 });
});
