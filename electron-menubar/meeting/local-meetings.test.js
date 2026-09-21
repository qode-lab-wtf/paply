import { describe, it, expect, afterEach } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { EventEmitter } from 'node:events';
import { MeetingResampler } from '../src/lib/meeting-resampler';
const require = createRequire(import.meta.url);
const { createMeetingStore } = require('./meeting-store');
const { createLocalStore } = require('./local-store');
const { atomicJson } = require('./local-files');
const { cleanExpiredAudio } = require('./local-retention');
const { createLocalPipeline, hashFile } = require('./local-pipeline');
const { encodeWav } = require('../audio/wav-encoder');
const { createLocalController } = require('./local-controller');
const { htmlExport } = require('./local-export');
const temp = [];
function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(),'paply-local-')); temp.push(root);
  const values = {}; const index = { get:k => values[k], set:(k,v) => { values[k]=v; } };
  const store = createLocalStore(root, createMeetingStore({ baseDir:root, store:index }));
  const id = store.create(new Date(0).toISOString());
  store.writeState(id, { schemaVersion:2, retentionPolicy:'seven-days-from-capture', audioExpiresAt:604800000, status:'queued', tracks:{mic:{offsetSeconds:0}}, completed:{} });
  return { root, store, id };
}
afterEach(() => { for(const root of temp.splice(0)) fs.rmSync(root,{recursive:true,force:true}); });
describe('Local capture and durable processing', () => {
  it('keeps exact long-term sample count across 128-frame blocks at 48 and 44.1 kHz', () => {
    for(const rate of [48000,44100,8000]) {
      const r = new MeetingResampler(rate); let count=0;
      for(let off=0;off<rate*2;off+=128) count += r.push(new Float32Array(Math.min(128,rate*2-off)).fill(.5)).length;
      count+=r.flush().length; expect(count).toBe(32000);
    }
  });
  it('retains corrections separately across generated transcript replacement', () => {
    const {store,id}=fixture();
    const transcript={segments:[{id:'word-1',speakerId:'mic-1',speaker:'Sprecher 1',text:'alt',channel:'mic',tStart:0,tEnd:1}],language:'de'};
    store.saveTranscript(id,transcript); store.renameSpeaker(id,'Sprecher 1','Anisa');
    store.correctSegment(id,'word-1',{text:'korrigiert'}); store.saveTranscript(id,transcript);
    expect(store.get(id).transcript.segments[0]).toMatchObject({speaker:'Anisa',text:'korrigiert'});
    store.saveTranscript(id,{segments:[],language:'de'});
    expect(store.get(id).transcript.unmatchedCorrections).toEqual(['word-1']);
  });
  it('deletes enrolled expired audio and intermediates, preserving legacy and transcript', () => {
    const {root,store,id}=fixture();const dir=store.dir(id);
    fs.writeFileSync(path.join(dir,'audio_mic.wav'),'audio');fs.writeFileSync(path.join(dir,'chunks','mic_000001.wav.tmp'),'partial');
    store.saveTranscript(id,{segments:[],language:'de'});
    const old=store.create(new Date(1).toISOString());fs.writeFileSync(path.join(store.dir(old),'audio_mic.wav'),'legacy');
    expect(cleanExpiredAudio(root,604799999)).toEqual([]);
    expect(cleanExpiredAudio(root,604800000)).toEqual([id]);
    expect(fs.existsSync(path.join(store.dir(old),'audio_mic.wav'))).toBe(true);
    expect(fs.existsSync(path.join(dir,'transcript.json'))).toBe(true);
    expect(fs.existsSync(path.join(dir,'chunks','mic_000001.wav.tmp'))).toBe(false);
    expect(store.readState(id).audioAvailable).toBe(false);
    expect(store.readState(id).status).toBe('queued');
  });
  it('resumes after a worker failure without repeating successful stages or losing audio', async () => {
    const {root,store,id}=fixture();const file=path.join(store.dir(id),'audio_mic.wav');fs.writeFileSync(file,encodeWav(Buffer.alloc(3200,1)));
    const configPath=path.join(root,'runtime.json');atomicJson(configPath,{asrPython:'unused',diarizationPython:'unused',whisperModel:'local',pyannoteModel:'local',models:{version:1}});
    const calls=[];let fail=true;
    const runner=async(stage,session,channel)=>{
      calls.push(stage);
      if(stage==='diarization' && fail) throw new Error('model interrupted');
      if(stage==='asr'||stage==='diarization') atomicJson(path.join(store.dir(session),'processing',`${channel}-${stage}.json`),{});
      if(stage==='merge') store.saveTranscript(session,{segments:[],language:'de'});
      if(stage==='report') store.saveSummary(session,{});
    };
    const pipeline=createLocalPipeline({store,configPath,runner,now:()=>100});
    expect(await pipeline.enqueue(id)).toBe(false);expect(store.readState(id).status).toBe('failed');
    const hash=await hashFile(file);fail=false;expect(await pipeline.enqueue(id)).toBe(true);
    expect(calls).toEqual(['asr','diarization','diarization','merge','report']);
    expect(await hashFile(file)).toBe(hash);
  });
  it('publishes the final transcript while the report is still running', async () => {
    const {root,store,id}=fixture();fs.writeFileSync(path.join(store.dir(id),'audio_mic.wav'),encodeWav(Buffer.alloc(3200,1)));
    const configPath=path.join(root,'runtime.json');atomicJson(configPath,{asrPython:'x',diarizationPython:'x',whisperModel:'x',pyannoteModel:'x'});
    let release, entered;const started=new Promise(resolve=>{entered=resolve;});const events=[];
    const pipeline=createLocalPipeline({store,configPath,now:()=>100,emit:(event,data)=>events.push({event,data}),runner:async(stage,session,channel)=>{
      if(stage==='asr'||stage==='diarization')atomicJson(path.join(store.dir(session),'processing',`${channel}-${stage}.json`),{});
      if(stage==='merge')store.saveTranscript(session,{provisional:false,language:'de',segments:[{id:'s',text:'final text',speaker:'Sprecher 2',speakerId:'speaker-two',tStart:0,tEnd:1,channel:'mic'}]});
      if(stage==='report'){entered();await new Promise(resolve=>{release=resolve;});store.saveSummary(session,{});}
    }});
    const job=pipeline.enqueue(id);await started;
    expect(events.some(e=>e.data.transcriptReady===true)).toBe(true);
    expect(store.get(id).transcript.segments[0].text).toBe('final text');
    expect(store.get(id).index.processingStage).toBe('report');
    expect(store.list().find(item=>item.id===id).speakerNames).toEqual(['Sprecher 2']);
    release();expect(await job).toBe(true);
  });
  it('resumes microphone enhancement separately and expires its derived audio', async () => {
    const {root,store,id}=fixture();const dir=store.dir(id);
    fs.writeFileSync(path.join(dir,'audio_mic.wav'),encodeWav(Buffer.alloc(3200,1)));
    const configPath=path.join(root,'runtime.json');
    const config={asrPython:'x',diarizationPython:'x',whisperModel:'x',pyannoteModel:'x',enhancementPython:'x',enhancementModel:'x',models:{enhancementRevision:'pinned'}};
    atomicJson(configPath,config);const calls=[];let fail=true;
    const pipeline=createLocalPipeline({store,configPath,now:()=>100,runner:async(stage,session,channel)=>{
      calls.push(stage);
      if(stage==='enhancement' && fail)throw new Error('enhancement interrupted');
      if(['asr','enhancement','diarization'].includes(stage))atomicJson(path.join(dir,'processing',`${channel}-${stage}.json`),{});
      if(stage==='enhancement')fs.writeFileSync(path.join(dir,'processing','mic-enhanced.wav'),encodeWav(Buffer.alloc(3200,2)));
      if(stage==='merge')store.saveTranscript(session,{segments:[],language:'de'});
      if(stage==='report')store.saveSummary(session,{});
    }});
    expect(await pipeline.enqueue(id)).toBe(false);fail=false;
    expect(await pipeline.enqueue(id)).toBe(true);
    expect(calls).toEqual(['asr','enhancement','enhancement','diarization','merge','report']);
    calls.length=0;
    fs.unlinkSync(path.join(dir,'processing','mic-enhanced.wav'));
    expect(await pipeline.enqueue(id)).toBe(true);
    expect(calls).toEqual(['enhancement','merge','report']);
    cleanExpiredAudio(root,604800000);
    expect(fs.existsSync(path.join(dir,'processing','mic-enhanced.wav'))).toBe(false);
    expect(fs.existsSync(path.join(dir,'transcript.json'))).toBe(true);
  });
  it('does not resurrect a deleted meeting after a running stage finishes', async () => {
    const { root, store, id } = fixture();
    fs.writeFileSync(path.join(store.dir(id), 'audio_mic.wav'), encodeWav(Buffer.alloc(3200, 1)));
    const configPath = path.join(root, 'runtime.json');
    atomicJson(configPath, {asrPython:'x',diarizationPython:'x',whisperModel:'x',pyannoteModel:'x'});
    let release, entered;
    const started = new Promise(resolve => { entered = resolve; });
    const pipeline = createLocalPipeline({store,configPath,now:()=>100,runner:async()=>{ entered(); await new Promise(resolve=>{release=resolve;}); }});
    const job = pipeline.enqueue(id); await started;
    pipeline.cancel(id); store.remove(id); release();
    expect(await job).toBe(false);
    expect(fs.existsSync(store.dir(id))).toBe(false);
  });
  it('persists microphone tail and native pipe tail before stopping and removes listeners', async () => {
    const {root,store}=fixture(); const tee = new EventEmitter();
    tee.start=()=>{}; tee.stop=()=>{tee.emit('pcm',Buffer.from([5,6]));tee.emit('stopped');tee.emit('closed');};
    const queued=[];let controller;let clock=100;
    const win={isDestroyed:()=>false,hide:()=>{},webContents:{send:(event,payload)=>{
      if(event==='meeting:capture-stop') { controller.onMicPcm(Buffer.from([3,4]),{sessionId:payload.id});controller.acknowledgeStop(payload.id); }
    }}};
    controller=createLocalController({meetingStore:store,audioTee:tee,baseDir:root,now:()=>clock,getOverlayWindow:()=>win,pipeline:{enqueue:id=>queued.push(id)}});
    const {id}=controller.start();
    controller.onMicPcm(Buffer.from([1]));controller.onMicPcm(Buffer.from([2]));
    tee.emit('pcm',Buffer.from([1,2,3,4]));clock=1100;await controller.stop();
    expect(queued).toEqual([id]);expect(tee.listenerCount('pcm')).toBe(0);expect(tee.listenerCount('closed')).toBe(0);
    const chunks=path.join(store.dir(id),'chunks');
    const files=fs.readdirSync(chunks);
    const mic=fs.readFileSync(path.join(chunks,files.find(f=>f.startsWith('mic'))));
    const system=fs.readFileSync(path.join(chunks,files.find(f=>f.startsWith('system'))));
    expect([...mic.subarray(44)]).toEqual([1,2,3,4]);
    expect([...system.subarray(44)]).toEqual([1,2,3,4,5,6]);
    expect(store.readState(id).status).toBe('queued');
  });
  it('preserves wall-clock alignment across microphone reconnection gaps', async () => {
    const {root,store}=fixture(); const tee=new EventEmitter();
    tee.start=()=>{};tee.stop=()=>tee.emit('closed');let controller;let now=1000;
    const win={isDestroyed:()=>false,webContents:{send:(event,p)=>{if(event==='meeting:capture-stop')controller.acknowledgeStop(p.id);}}};
    controller=createLocalController({meetingStore:store,audioTee:tee,baseDir:root,now:()=>now,getOverlayWindow:()=>win,pipeline:{enqueue:()=>{}}});
    const {id}=controller.start();now=2000;controller.onMicPcm(Buffer.alloc(32000,1),{sessionId:id,endAtMs:2000});
    now=4000;controller.onMicPcm(Buffer.alloc(32000,2),{sessionId:id,endAtMs:4000});await controller.stop();
    const dir=path.join(store.dir(id),'chunks');const pcm=Buffer.concat(fs.readdirSync(dir).sort().map(f=>fs.readFileSync(path.join(dir,f)).subarray(44)));
    expect(pcm.length).toBe(96000);expect([...pcm.subarray(32000,64000)].every(b=>b===0)).toBe(true);
    expect(store.readState(id).tracks.mic.gaps[0].seconds).toBe(1);
  });
  it('flags impossible capture duration without discarding samples', async () => {
    const {root,store}=fixture();const tee=new EventEmitter();tee.start=()=>{};tee.stop=()=>tee.emit('closed');let controller;let clock=1000;
    const win={isDestroyed:()=>false,webContents:{send:(event,p)=>{if(event==='meeting:capture-stop')controller.acknowledgeStop(p.id);}}};
    controller=createLocalController({meetingStore:store,audioTee:tee,baseDir:root,now:()=>clock,getOverlayWindow:()=>win,pipeline:{enqueue:()=>{}}});
    const {id}=controller.start();tee.emit('pcm',Buffer.alloc(128000,1));clock=2000;await controller.stop();
    const state=store.readState(id);expect(state.tracks.system.durationSeconds).toBe(4);expect(state.tracks.system.timingUncertain).toBe(true);expect(state.captureWarning).toContain('Aufnahmeuhr');
  });
  it('rejects path traversal and exports hostile transcript as text', () => {
    const {store}=fixture();expect(()=>store.get('../outside')).toThrow();
    const output=htmlExport({index:{title:'<script>bad()</script>',startTime:''},transcript:{segments:[{tStart:0,speaker:'<img>',text:'<script>run()</script>'}]}});
    expect(output).not.toContain('<script>'); expect(output).toContain('&lt;script&gt;');
  });
});
