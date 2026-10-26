// Independent QA harness. No production data/keys; launched only by QA.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const readline = require('node:readline');
const { _electron } = require(process.env.PAPLY_QA_PLAYWRIGHT || '/Users/allan/.npm/_npx/e41f203b7505f1fb/node_modules/playwright');
const appDir = path.resolve(__dirname, '../..');
const artifact = fs.mkdtempSync(path.join(os.tmpdir(), 'paply-notes-qa-'));
let profile = path.join(artifact, 'profile'); fs.mkdirSync(profile);
const config = {groqApiKey:'paply-notes-test-key', shortcut:'F20', meetingEnabled:false, onboardingCompleted:true, autopaste:false, autoStart:false, enablePolish:false, beepEnabled:false, notesSettings:{enabled:true,captureHotkey:'F18',openHotkey:'F19',screenContext:false,imageUnderstanding:false,dailyTokens:100000,dailyAudioMinutes:60}};
fs.writeFileSync(path.join(profile,'config.json'), JSON.stringify(config));
const wav = path.join(artifact, 'synthetic.wav');
cp.execFileSync('/usr/bin/say', ['-o',path.join(artifact,'speech.aiff'),'This is a synthetic test. We are planning a quiet holiday. We need warm light for the table. First press the button, then speak, and finally return to work. This is a synthetic test recording.']);
cp.execFileSync('/usr/bin/afconvert', ['-f','WAVE','-d','LEI16@16000','-c','1',path.join(artifact,'speech.aiff'),wav]);
const transcript = 'Ich möchte im Frühjahr ans Meer. Ein kleines Haus wäre schön. Ruhe ist mir wichtig. Zuerst drücke ich das Kürzel. Dann spreche ich meinen Gedanken. Danach arbeite ich weiter. Lampe A besteht aus Papier. Lampe B besteht aus Opalglas. Die Preise kenne ich noch nicht. Welche Größe passt zum Tisch?';
let requests=[], pending=[], mode='normal', app, board, dashboard, pill, logs=[], results=[];
function plan(ctx) {
 const topics=[{key:'trip',title:'Auszeit',icon:'sun'},{key:'app',title:'Paply',icon:'code'},{key:'home',title:'Zuhause',icon:'home'}];
 const items=ctx.sentences.map((s,i)=>({key:'i'+i,sentenceIds:[s.id],label:['Meer','Wohnen','Ruhe','Kürzel','Sprechen','Weiterarbeiten','Lampe A','Lampe B','Preis offen','Größe'][i]||'Gedanke',icon:i<3?'sun':i<6?'code':'home',topic:i<3?'trip':i<6?'app':'home',appearance:i===8?'sticky':i===9?'text':'note'}));
 const structures=[];
 if(items.length>=3)structures.push({kind:'mindmap',title:'Auszeit',members:['i0','i1','i2'],columns:[],rows:[]});
 if(items.length>=6)structures.push({kind:'flow',title:'Gedanken ablegen',members:['i3','i4','i5'],columns:[],rows:[]});
 if(items.length>=8)structures.push({kind:'table',title:'Zwei Lampen',members:['i6','i7'],columns:['Lampe A','Lampe B'],rows:[{label:'Material',cells:[{sentenceId:ctx.sentences[6].id,quote:'Papier'},{sentenceId:ctx.sentences[7].id,quote:'Opalglas'}]}]});
 return {topics,items,structures,relations:[]};
}
const server=http.createServer(async(req,res)=>{
 const chunks=[];for await(const b of req)chunks.push(b);const body=Buffer.concat(chunks);
 if(req.headers.authorization!=='Bearer paply-notes-test-key'){res.writeHead(403);res.end('{}');return;}
 const record={url:req.url,bytes:body.length,at:Date.now(),mode}; requests.push(record);
 const send=(status,data)=>{res.writeHead(status,{'content-type':'application/json','retry-after':'2'});res.end(JSON.stringify(data));};
 if(mode==='auth')return send(401,{}); if(mode==='rate')return send(429,{});
 if(req.url.endsWith('/audio/transcriptions')){
   const at=body.indexOf(Buffer.from('RIFF')); assert(at>=0,'Real multipart WAV required'); assert.equal(body.toString('ascii',at+8,at+12),'WAVE');
   record.wavBytes=body.readUInt32LE(at+4)+8;record.sampleRate=body.readUInt32LE(at+24);fs.writeFileSync(path.join(artifact,'last-upload.wav'),body.subarray(at,at+record.wavBytes));
   return send(200,{text:transcript,duration:(record.wavBytes-44)/32000,segments:[{text:transcript,no_speech_prob:0,avg_logprob:-0.05}]});
 }
 if(req.url.endsWith('/chat/completions')){
   const data=JSON.parse(body);record.model=data.model;const ctx=JSON.parse(data.messages.at(-1).content);record.sentenceCount=ctx.sentences.length;
   const reply=()=>send(200,{choices:[{finish_reason:'stop',message:{content:mode==='invalid'?'{}':JSON.stringify(plan(ctx))}}],usage:{total_tokens:400}});
   if(mode==='delay'){pending.push(reply);return;} return reply();
 }
 send(404,{});
});
async function waitUntil(fn,ms=15000){const t=Date.now();while(Date.now()-t<ms){const v=await fn();if(v)return v;await new Promise(r=>setTimeout(r,100));}throw Error('waitUntil timeout');}
async function launch({audioWorkaround=false,nativeBackground=false}={}){
 const env=Object.fromEntries(['PATH','HOME','TMPDIR','LANG','SHELL','USER','LOGNAME'].filter(k=>process.env[k]).map(k=>[k,process.env[k]]));
 app=await _electron.launch({executablePath:require(path.join(appDir,'node_modules/electron')),args:[nativeBackground?path.join(__dirname,'background-bootstrap.cjs'):appDir,...(audioWorkaround?['--no-sandbox']:[]),'--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream',`--use-file-for-fake-audio-capture=${wav}`],cwd:appDir,env:{...env,PAPLY_USER_DATA:profile,PAPLY_NOTES_TEST_ENDPOINT:`http://127.0.0.1:${server.address().port}/openai/v1`},timeout:25000});
 app.process().stdout.on('data',b=>{logs.push(b.toString());fs.appendFileSync(path.join(artifact,'main.log'),b);});
 app.process().stderr.on('data',b=>{logs.push(b.toString());fs.appendFileSync(path.join(artifact,'main.log'),b);});
 app.on('window',p=>{p.on('pageerror',e=>logs.push('PAGEERROR '+p.url()+' '+e.stack));p.on('console',m=>{if(m.type()==='error')logs.push('CONSOLE '+p.url()+' '+m.text());});});
 dashboard=await waitUntil(()=>app.windows().find(p=>p.url().endsWith('/dashboard.html')));
 pill=await waitUntil(()=>app.windows().find(p=>p.url().endsWith('/notes-pill.html')));
 await dashboard.waitForLoadState();
 return {windows:app.windows().map(p=>p.url()),artifact,profile};
}
async function openBoard(){await dashboard.evaluate(()=>window.electronAPI.openNotes());board=await waitUntil(()=>app.windows().find(p=>p.url().endsWith('/notes.html')));await board.locator('.notes-app').waitFor();return await state();}
async function state(){return board.evaluate(()=>window.paplyNotes.get());}
async function shot(name){await board.screenshot({path:path.join(artifact,name+'.png')});return path.join(artifact,name+'.png');}
async function native(keycode){cp.execFileSync('/usr/bin/osascript',['-e',`tell application "System Events" to key code ${keycode}`],{timeout:3000});}
async function capture(sec=5){await native(79);await waitUntil(()=>pill.evaluate(()=>window.paplyNotesCapture.ready()).then(v=>v.phase==='recording'));await new Promise(r=>setTimeout(r,sec*1000));await native(79);return await waitUntil(async()=>{const files=fs.readdirSync(path.join(profile,'notes/sources'));const es=files.map(n=>JSON.parse(fs.readFileSync(path.join(profile,'notes/sources',n,'entry.json'))));return es.length&&es.every(e=>e.state==='complete')?es:null;},20000);}
server.listen(0,'127.0.0.1',async()=>{
 console.log(JSON.stringify({ready:true,artifact,profile,port:server.address().port}));
 const rl=readline.createInterface({input:process.stdin});
 for await(const line of rl){try{const out=await eval(`(async()=>{${line}})()`);console.log('RESULT '+JSON.stringify(out));}catch(e){console.log('ERROR '+e.stack);}}
 fs.writeFileSync(path.join(artifact,'results.json'),JSON.stringify({requests,results,logs},null,2));
 if(app)await app.close().catch(()=>{});server.close();
});
