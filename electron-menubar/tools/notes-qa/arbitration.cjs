const fs=require('node:fs');const path=require('node:path');const assert=require('node:assert/strict');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
exports.run=async({board,dashboard,app,pill,waitUntil,profile})=>{
 // Only legacy dictation's dynamic transport is replaced here. Notes captured
 // its loopback fetch earlier. No real endpoint receives this synthetic audio.
 await app.evaluate(()=>{globalThis.qaFetchCalls=[];globalThis.fetch=async url=>{globalThis.qaFetchCalls.push(String(url));if(String(url)!=='https://api.groq.com/openai/v1/audio/transcriptions')throw Error('QA blocks external transport');return new Response(JSON.stringify({text:'Diktat QA synthetisch',segments:[{text:'Diktat QA synthetisch',no_speech_prob:0,avg_logprob:-.1}]}),{status:200,headers:{'content-type':'application/json'}});};});
 await board.getByRole('button',{name:'Gedanke aufnehmen',exact:true}).click();
 await waitUntil(()=>pill.evaluate(()=>window.paplyNotesCapture.ready()).then(s=>s.phase==='recording'));
 await sleep(1500);await dashboard.evaluate(()=>window.electronAPI.startTranscription());await sleep(1000);
 const paused=await pill.evaluate(()=>window.paplyNotesCapture.ready());assert.equal(paused.phase,'paused');
 const file=path.join(profile,'notes/sources',paused.entryId,'rec.pcm'),bytes=fs.statSync(file).size;
 await sleep(2000);const unchanged=fs.statSync(file).size===bytes;assert(unchanged);
 await dashboard.evaluate(()=>window.electronAPI.stopTranscription());
 await waitUntil(()=>pill.evaluate(()=>window.paplyNotesCapture.ready()).then(s=>s.phase==='recording'||s.phase==='resume'),8000);
 const resumed=await pill.evaluate(()=>window.paplyNotesCapture.ready());assert(resumed.epoch>paused.epoch);
 await sleep(1000);assert(fs.statSync(file).size>bytes,'Notes audio grows again after dictation');await pill.getByRole('button',{name:'Gedanke sichern',exact:true}).click();
 return {paused,resumed,pcmDidNotGrowDuringDictation:unchanged,dictationFetch:await app.evaluate(()=>globalThis.qaFetchCalls),history:await dashboard.evaluate(()=>window.electronAPI.getHistory())};
};
