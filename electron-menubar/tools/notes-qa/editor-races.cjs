// Independent GUI acceptance cases for Opus N1/N2. Run only on a ready test bundle.
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const planRequests=c=>c.requests.filter(r=>r.url.endsWith('/chat/completions'));
const sttRequests=c=>c.requests.filter(r=>r.url.endsWith('/audio/transcriptions'));
const raw=s=>Object.values(s.nodes).find(n=>n.id.startsWith('raw_'));
const terminal=e=>['complete','kept_user','fallback','needs_attention','empty'].includes(e.state);
async function paste(c,text){await c.app.evaluate(({clipboard},value)=>clipboard.writeText(value),text);await c.board.keyboard.press('Meta+v');}
async function edit(c,id){await c.board.getByRole('button',{name:'Alles zeigen (⇧1)',exact:true}).click();await wait(350);await c.board.locator(`[data-note-body="${id}"]`).dblclick();const input=c.board.getByRole('textbox',{name:'Notiz bearbeiten'});await input.waitFor();return input;}
async function sourceText(c,id){const result=await c.board.evaluate(id=>window.paplyNotes.source(id),id);return result.text;}
function release(list){assert.equal(list.length,1,'exactly one delayed reply');list.shift()();}

exports.planDuringEditor=async(c,{unchanged=false}={})=>{
  const start=planRequests(c).length,text='Ein ruhiger Garten ist mein Wunsch. Ein kleiner Tisch passt dazu. Warmes Licht fehlt noch.',draft='Mein offener Entwurf bleibt vollständig erhalten.';
  c.setMode('delay');await paste(c,text);await c.waitUntil(()=>c.pending.length===1);
  const initial=await c.state(),note=raw(initial);assert(note,'a raw note is visible before the plan');
  const input=await edit(c,note.id),originalDraft=await input.inputValue();
  if(!unchanged)await input.fill(draft);
  release(c.pending);
  await c.waitUntil(()=>fs.existsSync(path.join(c.profile,'notes','sources',note.sourceId,'plan-0.json')));
  await wait(2400); // Cross the editor retry interval while keeping the actual textarea open.
  assert.equal(await input.inputValue(),unchanged?originalDraft:draft,'incoming plan cannot destroy or replace the open draft');
  assert((await c.state()).nodes[note.id],'raw object remains while the editor holds it');
  assert.equal(planRequests(c).length-start,1,'no second paid request while editing');
  const screenshot=await c.shot(unchanged?'n1-a2-plan-held-unchanged':'n1-a-plan-held-draft');
  await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();
  await c.waitUntil(async()=>{const s=await c.state();return s.entries.length&&s.entries.every(terminal);},16000);
  const final=await c.state();
  if(unchanged){
    assert(!final.nodes[note.id],'cached plan replaces untouched raw note after editor closes');
    for(const sentence of ['Ein ruhiger Garten ist mein Wunsch.','Ein kleiner Tisch passt dazu.','Warmes Licht fehlt noch.'])assert(Object.values(final.nodes).some(n=>n.text.includes(sentence)),'all original sentences represented');
  }else assert.equal(final.nodes[note.id]?.text,draft,'saving the draft remains durable after plan completion');
  assert.equal(await sourceText(c,note.sourceId),text,'original is preserved');await wait(1200);
  assert.equal(planRequests(c).length-start,1,'held result reused or discarded locally without another request');
  const result={id:unchanged?'N1-A2-unchanged-editor':'N1-A-open-draft',pass:true,requests:planRequests(c).length-start,entry:final.entries[0],screenshot};c.results.push(result);return result;
};

exports.transcriptDuringEditor=async(c,{reopen=false}={})=>{
  const flags=await c.app.evaluate(({app})=>({fakeDevice:app.commandLine.hasSwitch('use-fake-device-for-media-stream'),fakeUi:app.commandLine.hasSwitch('use-fake-ui-for-media-stream'),noSandbox:app.commandLine.hasSwitch('no-sandbox')}));
  assert(flags.fakeDevice&&flags.fakeUi&&!flags.noSandbox,'synthetic Chromium microphone in normal sandbox required');
  const startStt=sttRequests(c).length,startPlan=planRequests(c).length,transcript='Das synthetische Transkript bleibt vollständig auf der Fläche.',firstDraft='Mein erster bereits gespeicherter Zusatz.',draft=reopen?'Meine überarbeitete Ergänzung aus dem zweiten Editor.':'Meine Ergänzung während der Aufnahme.';
  c.setMode('delay-stt');c.setTranscript(transcript);
  await c.board.getByRole('button',{name:'Gedanke aufnehmen',exact:true}).click();
  await c.waitUntil(async()=>{const s=await c.state();return s.capture.active&&s.capture.elapsedMs>=1500;},16000);
  const note=raw(await c.state());assert(note?.pending,'live recording placeholder exists');
  let input=await edit(c,note.id),reopenedBase=null;
  const pendingMaxLength=await input.getAttribute('maxlength');assert.equal(pendingMaxLength,'16998','pending editor reserves room for its later transcript');
  if(reopen){
    await input.fill(firstDraft);await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();
    await c.waitUntil(async()=>await input.count()===0);
    reopenedBase=(await c.state()).nodes[note.id];assert.equal(reopenedBase.text,firstDraft);assert.equal(reopenedBase.owner,'user');assert.equal(reopenedBase.pending,true);
    input=await edit(c,note.id);assert.equal(await input.inputValue(),firstDraft,'second editor starts with previously saved user text');
  }
  await input.fill(draft);
  // The existing capture preload stop path models a global hotkey without moving
  // focus from the textarea. No PCM is injected and no main state is seeded.
  await c.pill.evaluate(()=>window.paplyNotesCapture.stop());
  await c.waitUntil(()=>c.pendingStt.length===1,16000);assert.equal(await input.inputValue(),draft);
  release(c.pendingStt);
  await c.waitUntil(async()=>{const s=await c.state();return s.nodes[note.id]?.text.includes(transcript);},16000);
  // Main commits before its debounced renderer broadcast. Anchor this STT-arrival
  // case to the visible pending indicator, not merely to a newer main snapshot.
  await c.waitUntil(async()=>await c.board.locator(`[data-note-body="${note.id}"] .spin`).count()===0);
  assert.equal(await input.getAttribute('maxlength'),'16998','open pending draft keeps its transcript reserve after STT');
  if(reopen)assert.equal((await c.state()).nodes[note.id].text,`${firstDraft}\n\n${transcript}`,'STT reached already-owned pending card while second draft stayed open');
  assert.equal(await input.inputValue(),draft,'STT arriving while editor is open does not reset draft');
  const screenshot=await c.shot(reopen?'n1-b2-stt-with-second-draft':'n1-b-stt-with-open-draft');
  await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();
  await c.waitUntil(async()=>await input.count()===0,16000);
  await c.waitUntil(async()=>{const s=await c.state();return s.entries.length&&s.entries.every(terminal);},16000);
  const final=await c.state(),saved=final.nodes[note.id];
  assert.equal(saved.text,`${draft}\n\n${transcript}`,'only latest draft and one complete transcript survive save');
  if(reopen)assert(!saved.text.includes(firstDraft),'old user prefix is replaced, not duplicated');
  assert.equal(saved.pending,false);assert.equal(await sourceText(c,note.sourceId),transcript);
  assert.equal(sttRequests(c).length-startStt,1);assert.equal(planRequests(c).length-startPlan,0,'edited placeholder needs no extra plan request');
  const upload=sttRequests(c).at(-1);assert(upload.wavBytes>32000);assert.equal(upload.sampleRate,16000);
  const displayed=await c.board.locator(`[data-note-body="${note.id}"] .note-text`).textContent();assert(displayed.includes(draft)&&displayed.includes(transcript),'saved merged text is rendered after editor closes');
  const result={id:reopen?'N1-B2-reopened-placeholder-STT':'N1-B-placeholder-STT',pass:true,flags,pendingMaxLength,sttRequests:1,planRequests:0,wavBytes:upload.wavBytes,reopenedBase:reopenedBase?{owner:reopenedBase.owner,pending:reopenedBase.pending,rev:reopenedBase.rev,text:reopenedBase.text}:null,text:saved.text,entry:final.entries[0],screenshot,savedScreenshot:await c.shot(reopen?'n1-b2-second-draft-merged':'n1-b-draft-merged')};c.results.push(result);return result;
};

exports.longTable=async c=>{
  const start=planRequests(c).length,first=('Ein langer Gedanke über Licht und Ruhe ').repeat(60).trim()+'.',second='Der zweite Gedanke bleibt ebenfalls vollständig.',text=first+' '+second;
  assert(first.length>2000);c.setMode('normal');
  c.setPlan(ctx=>({topics:[],items:ctx.sentences.map((s,i)=>({key:'i'+i,sentenceIds:[s.id],label:i?'Zweiter Gedanke':'Langer Gedanke',icon:'pencil',topic:null,appearance:'note'})),structures:[{kind:'table',title:'Überlange Zelle',members:ctx.sentences.map((_,i)=>'i'+i),columns:['Erster','Zweiter'],rows:[{label:'Original',cells:[{sentenceId:ctx.sentences[0].id,quote:'Unbelegter Kurztext'},{sentenceId:ctx.sentences[1].id,quote:ctx.sentences[1].text}]}]}],relations:[]}));
  await paste(c,text);await c.waitUntil(async()=>{const s=await c.state();return s.entries.length&&s.entries.every(terminal);},20000);
  const final=await c.state(),nodes=Object.values(final.nodes);
  assert.equal(final.entries[0].state,'complete');assert.equal(nodes.length,2);assert(nodes.every(n=>n.kind==='note'),'oversized table becomes ordinary notes');
  assert(nodes.some(n=>n.text===first));assert(nodes.some(n=>n.text===second));
  assert.equal(await sourceText(c,final.entries[0].id),text);await wait(2400);
  assert.equal(planRequests(c).length-start,1,'one plan request only; no paid retry loop');
  await c.board.getByRole('button',{name:'Alles zeigen (⇧1)',exact:true}).click();await wait(350);
  const result={id:'N2-oversized-table',pass:true,originalLength:text.length,longSentenceLength:first.length,notes:nodes.length,requests:planRequests(c).length-start,entry:final.entries[0],screenshot:await c.shot('n2-long-table-as-notes')};c.results.push(result);return result;
};

exports.switchAndBlur=async(c,{nativeBlur=true}={})=>{
  const start=planRequests(c).length,notes=Object.values((await c.state()).nodes).filter(n=>n.kind==='note');assert(notes.length>=2);
  const [a,b]=notes;const first=await edit(c,a.id);await first.fill('Erster Entwurf vor dem direkten Editorwechsel.');
  await c.board.locator(`[data-note-body="${b.id}"]`).dblclick();
  const second=c.board.locator(`[data-note-body="${b.id}"]`).getByRole('textbox',{name:'Notiz bearbeiten'});await second.waitFor();
  await c.waitUntil(async()=>(await c.state()).nodes[a.id].text==='Erster Entwurf vor dem direkten Editorwechsel.');
  assert.equal(await c.board.getByRole('textbox',{name:'Notiz bearbeiten'}).count(),1);
  await second.fill('Zweiter Entwurf wird beim Fensterwechsel gesichert.');
  if(!nativeBlur){
    await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();
    assert.equal((await c.state()).nodes[b.id].text,'Zweiter Entwurf wird beim Fensterwechsel gesichert.');
    assert.equal(planRequests(c).length,start);
    const result={id:'N1-editor-switch-save',pass:true,extraRequests:0,screenshot:await c.shot('n1-editor-switch-saved')};c.results.push(result);return result;
  }
  const focus=await c.app.evaluate(({BrowserWindow})=>{const dashboard=BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/dashboard.html')),board=BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/notes.html'));dashboard.show();dashboard.focus();return {dashboardId:dashboard.id,boardId:board.id};});
  await c.waitUntil(()=>c.app.evaluate(({BrowserWindow},ids)=>BrowserWindow.fromId(ids.dashboardId).isFocused()&&!BrowserWindow.fromId(ids.boardId).isFocused(),focus));
  await c.waitUntil(async()=>(await c.state()).nodes[b.id].text==='Zweiter Entwurf wird beim Fensterwechsel gesichert.');
  await c.app.evaluate(({BrowserWindow},id)=>{const w=BrowserWindow.fromId(id);w.show();w.focus();},focus.boardId);
  assert.equal(await c.board.getByRole('textbox',{name:'Notiz bearbeiten'}).count(),0,'native window blur saved and finished editor');
  assert.equal(planRequests(c).length,start);
  const result={id:'N1-editor-switch-native-blur',pass:true,extraRequests:0,screenshot:await c.shot('n1-editor-switch-blur-saved')};c.results.push(result);return result;
};

exports.conflictAndLimits=async c=>{
  const start=planRequests(c).length;
  await c.board.getByRole('button',{name:'Haftnotiz (N)',exact:true}).click();await c.board.mouse.click(520,340);
  let input=c.board.getByRole('textbox',{name:'Notiz bearbeiten'});await input.waitFor();await input.fill('Manueller Ausgangstext.');
  await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();await c.waitUntil(async()=>await input.count()===0);
  const note=Object.values((await c.state()).nodes)[0];assert.equal(note.owner,'user');
  input=await edit(c,note.id);const noteMaxLength=await input.getAttribute('maxlength');assert.equal(noteMaxLength,'20000');
  const oversizedPaste='A'.repeat(20050);
  await c.app.evaluate(({clipboard},text)=>clipboard.writeText(text),oversizedPaste);
  await input.press('Meta+a');await input.press('Meta+v');
  assert.equal(await input.inputValue(),oversizedPaste.slice(0,20000),'real clipboard paste respects the 20,000-character editor limit');
  await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();await c.waitUntil(async()=>await input.count()===0);
  assert.equal((await c.state()).nodes[note.id].text,oversizedPaste.slice(0,20000),'maximum-length pasted note saves successfully');
  input=await edit(c,note.id);
  const draft='Mein ausdrücklich bestätigter Entwurf.',concurrent='Konkurrierende Änderung über das normale Notes-Command.';await input.fill(draft);
  await c.board.evaluate(({id,text})=>window.paplyNotes.command([{type:'update',id,patch:{text}}]),{id:note.id,text:concurrent});
  await c.waitUntil(async()=>(await c.state()).nodes[note.id].text===concurrent);await wait(100);
  assert.equal(await input.inputValue(),draft);
  await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();
  await c.waitUntil(async()=>(await c.board.locator('.notes-toast').allTextContents()).some(t=>t.includes('Notiz inzwischen geändert')));
  assert.equal(await input.inputValue(),draft);assert.equal((await c.state()).nodes[note.id].text,concurrent);
  await input.press('Escape');await wait(150);assert.equal(await input.count(),1);assert.equal((await c.state()).nodes[note.id].text,concurrent,'automatic save remains blocked after conflict');
  const screenshot=await c.shot('editor-conflict-retains-draft');
  await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();await c.waitUntil(async()=>await input.count()===0);
  assert.equal((await c.state()).nodes[note.id].text,draft,'second explicit save confirms draft and closes editor');
  await c.board.getByRole('button',{name:'Tabelle einfügen',exact:true}).click();
  const column=c.board.getByRole('textbox',{name:'Spalte 1',exact:true}),criterion=c.board.getByRole('textbox',{name:'Kriterium 1',exact:true}),cell=c.board.getByRole('textbox',{name:'Zeile 1, Spalte 1',exact:true});await column.waitFor();
  const limits={note:noteMaxLength,column:await column.getAttribute('maxlength'),criterion:await criterion.getAttribute('maxlength'),cell:await cell.getAttribute('maxlength')};
  assert.deepEqual(limits,{note:'20000',column:'100',criterion:'100',cell:'2000'});
  await c.board.getByRole('button',{name:'Übernehmen',exact:true}).click();assert.equal(planRequests(c).length,start);
  const result={id:'editor-conflict-and-DOM-limits',pass:true,limits,pasteInputLength:oversizedPaste.length,pasteSavedLength:20000,extraRequests:0,screenshot};c.results.push(result);return result;
};
