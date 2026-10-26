const assert = require('node:assert/strict');
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

exports.mindmap = async ({board,state,shot,results}) => {
  await board.getByRole('button',{name:'Auszeit',exact:true}).click(); await wait(400);
  const s=await state(), hub=Object.values(s.nodes).find(n=>n.kind==='hub');
  const edges=Object.values(s.edges).filter(e=>e.source===hub.id && s.nodes[e.target].position.x<hub.position.x);
  assert.equal(edges.length,2,'fixture has two left-facing mindmap edges');
  const measured=[];
  for(const edge of edges){
    const path=board.locator(`.react-flow__edge[data-id="${edge.id}"] .react-flow__edge-path`);
    const points=await path.evaluate(p=>{const m=p.getScreenCTM(),a=p.getPointAtLength(0),z=p.getPointAtLength(p.getTotalLength()); const start=new DOMPoint(a.x,a.y).matrixTransform(m),end=new DOMPoint(z.x,z.y).matrixTransform(m);return {start:{x:start.x,y:start.y},end:{x:end.x,y:end.y}};});
    const a=await board.locator(`[data-note-id="${hub.id}"] .react-flow__handle[data-handleid="left"]`).boundingBox();
    const z=await board.locator(`[data-note-id="${edge.target}"] .react-flow__handle[data-handleid="right"]`).boundingBox();
    assert(Math.hypot(points.start.x-a.x,points.start.y-a.y-a.height/2)<3,'edge begins at outer edge of hub LEFT handle');
    assert(Math.hypot(points.end.x-z.x-z.width,points.end.y-z.y-z.height/2)<3,'edge ends at outer edge of branch RIGHT handle');
    measured.push({edge:edge.id,...points,sourceHandle:a,targetHandle:z});
  }
  results.push({id:'packaged-left-mindmap',pass:true,measured});
  await board.locator(`[data-note-body="${hub.id}"]`).dblclick();
  await board.getByRole('textbox',{name:'Notiz bearbeiten'}).fill('Meine ruhige Auszeit');
  await board.getByRole('button',{name:'Übernehmen',exact:true}).click();
  await wait(150); assert.equal((await state()).nodes[hub.id].text,'Meine ruhige Auszeit');
  results.push({id:'packaged-hub-edit',pass:true});
  return {measured,screenshot:await shot('02-packaged-mindmap')};
};

exports.original = async({board,state,app,shot,results})=>{
  const s=await state(),note=Object.values(s.nodes).find(n=>n.label==='Meer');
  await board.locator(`[data-note-id="${note.id}"]`).click();
  await board.getByRole('button',{name:'Original ansehen',exact:true}).click();
  const p=board.locator('.source-modal p'); await p.waitFor();
  await p.click({clickCount:3,position:{x:36,y:15}});
  let selection=await board.evaluate(()=>window.getSelection().toString());
  assert(selection.includes('Meer'),'real pointer text selection selects source paragraph');
  await app.evaluate(({clipboard})=>clipboard.writeText('QA sentinel'));
  await board.keyboard.press('Meta+c'); await wait(100);
  const copied=await app.evaluate(({clipboard})=>clipboard.readText());
  assert.equal(copied,selection,'Cmd+C preserves native selected-text copy');
  assert.notEqual(copied,note.text,'selected original is distinct from edited note');
  await board.keyboard.press('Delete'); await board.keyboard.press('Backspace'); await wait(150);
  assert.deepEqual((await state()).nodes,s.nodes,'Delete/Backspace inside original dialog do not delete board notes');
  results.push({id:'packaged-original-copy-delete',pass:true,selected:selection,copied});
  const screenshot=await shot('03-packaged-original');
  await board.getByRole('button',{name:'Original schließen',exact:true}).click();
  return {copied,screenshot};
};

exports.camera = async({app,board,state,results,shot})=>{
  // Replaces getSources before clicking the camera. No screen pixels are read.
  const png=await require('../../node_modules/sharp')({create:{width:160,height:90,channels:4,background:'#799360'}}).png().toBuffer();
  await app.evaluate(({desktopCapturer,nativeImage,screen,BrowserWindow},bytes)=>{
    global.__notesQaCamera={calls:[],original:desktopCapturer.getSources};
    desktopCapturer.getSources=async options=>{
      const w=BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/notes.html'));
      global.__notesQaCamera.calls.push({boardVisible:w.isVisible(),options});
      const display=screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
      return [{id:'screen:synthetic:0',name:'Synthetic QA',display_id:String(display.id),thumbnail:nativeImage.createFromBuffer(Buffer.from(bytes))}];
    };
  },Array.from(png));
  try {
    const before=await state();
    await board.getByRole('button',{name:'Bildschirm jetzt merken',exact:true}).click(); await wait(500);
    const after=await state(),probe=await app.evaluate(({BrowserWindow})=>({calls:global.__notesQaCamera.calls,visible:BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/notes.html')).isVisible()}));
    assert.equal(probe.calls.length,1); assert.equal(probe.calls[0].boardVisible,false); assert.equal(probe.visible,true);
    assert(Object.values(after.nodes).some(n=>n.attachments.length && n.attachments.length>(before.nodes[n.id]?.attachments.length||0)),'synthetic image attached through camera IPC');
    results.push({id:'packaged-camera-hidden',pass:true,...probe});
    return {probe,screenshot:await shot('04-packaged-camera')};
  } finally { await app.evaluate(({desktopCapturer})=>{desktopCapturer.getSources=global.__notesQaCamera.original;}); }
};

exports.settings = async({app,board,dashboard,results,shot,waitUntil})=>{
  await board.getByRole('button',{name:'Notes-Einstellungen',exact:true}).click();
  const settings=await waitUntil(()=>app.windows().find(p=>p.url().endsWith('/settings.html')));
  const input=settings.getByRole('textbox',{name:'Notes Aufnahme-Kürzel',exact:true});
  await input.waitFor(); await input.click(); await input.press('Control+Alt+F12');
  await settings.getByRole('button',{name:'Kürzel übernehmen',exact:true}).click(); await wait(200);
  const prefs=await dashboard.evaluate(()=>window.electronAPI.getNotesSettings());
  assert.equal(prefs.captureHotkey,'Ctrl+Alt+F12');
  const registered=await app.evaluate(({globalShortcut})=>({next:globalShortcut.isRegistered('Control+Alt+F12'),old:globalShortcut.isRegistered('F18')}));
  assert.equal(registered.next,true);assert.equal(registered.old,false);
  results.push({id:'packaged-settings-hotkey',pass:true,prefs,registered});
  await dashboard.evaluate(()=>window.electronAPI.setNotesSettings({captureHotkey:'F18'}));
  await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/settings.html')).close());
  await board.bringToFront();
  return {prefs,registered};
};

exports.performance = async({app,board,state,shot,results,reuseFixture=false})=>{
  // Separate volume fixture in a clearly labelled temporary QA profile. Small cards
  // are deliberate so sixty complete OpenUI bodies fit at actual 100% zoom.
  await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/notes.html')).setBounds({x:10,y:25,width:1900,height:1000}));
  if(!reuseFixture){
  const before=await state();
  await board.evaluate(ids=>window.paplyNotes.command(ids.map(id=>({type:'delete',id}))),Object.keys(before.nodes));
  const ops=Array.from({length:60},(_,i)=>({type:'create',node:{kind:i%3===0?'sticky':i%3===1?'text':'note',text:`QA ${i}: Gedanke.`,label:`Notiz ${i}`,position:{x:(i%10)*180,y:Math.floor(i/10)*120}}}));
  await board.evaluate(ops=>window.paplyNotes.command(ops),ops);
  await board.evaluate(async()=>{const b=await window.paplyNotes.get();return window.paplyNotes.command(Object.keys(b.nodes).map(id=>({type:'update',id,patch:{width:170,height:110}})));});
  await board.waitForFunction(()=>[...document.querySelectorAll('.react-flow__node')].length===60&&[...document.querySelectorAll('.react-flow__node')].every(n=>Math.abs(n.getBoundingClientRect().width/Number(document.querySelector('.zoom-number').textContent.replace('%',''))*100-170)<4));
  await wait(350);
  }
  await board.getByRole('button',{name:'Alles zeigen (⇧1)',exact:true}).click();await wait(350);
  await board.getByTitle('100 %',{exact:true}).click();await wait(350);
  await board.waitForFunction(()=>document.querySelector('.zoom-number').textContent==='100%'&&[...document.querySelectorAll('.react-flow__node')].every(n=>{const r=n.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth&&r.top>=65&&r.bottom<=innerHeight-90}));
  const visible=await board.locator('.react-flow__node').evaluateAll(ns=>ns.filter(n=>{const r=n.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth&&r.top>=65&&r.bottom<=innerHeight-90}).length);
  assert.equal(visible,60,'all 60 cards fully visible at 100%');
  const zoom=await board.locator('.zoom-number').innerText();assert.equal(zoom.replace(/\s/g,''),'100%');
  const domViewport=()=>board.locator('.react-flow__viewport').evaluate(n=>{const m=new DOMMatrix(getComputedStyle(n).transform);return{x:m.m41,y:m.m42,zoom:m.a};});
  const settled=async()=>{for(let i=0;i<50;i++){const d=await domViewport(),s=await state();if(Math.abs(d.x-s.viewport.x)<.1&&Math.abs(d.y-s.viewport.y)<.1&&Math.abs(d.zoom-s.viewport.zoom)<.001)return s;await wait(100);}throw Error('Viewport did not persist its final DOM transform');};
  const initial=await settled(),domBefore=await domViewport();
  assert.equal(domBefore.zoom,1);await shot('05-packaged-performance-start-100pct');
  await board.evaluate(()=>{window.__notesQaBroadcasts=0;window.__notesQaOff=window.paplyNotes.onChange(()=>window.__notesQaBroadcasts++);});
  const sampling=board.evaluate(()=>new Promise(resolve=>{const frames=[];let start,last;function next(t){if(start===undefined){start=t;last=t;}else{frames.push(t-last);last=t;}if(t-start<3100)requestAnimationFrame(next);else resolve(frames);}requestAnimationFrame(next);}));
  await board.mouse.move(1100,500);const at=Date.now();let step=0;while(Date.now()-at<3000){await board.mouse.wheel(step++%40<20?4:-4,0);await wait(18);}
  const frames=await sampling;await board.mouse.wheel(121,0);await wait(600);
  const after=await settled(),domAfter=await domViewport();assert.notDeepEqual(domAfter,domBefore,'real wheel events moved the renderer viewport');
  const broadcasts=await board.evaluate(()=>{window.__notesQaOff();return window.__notesQaBroadcasts;});
  assert.equal(after.rev,initial.rev,'pan must not revise canonical board');assert.equal(broadcasts,0,'pan must not broadcast board snapshots');assert.notDeepEqual(after.viewport,initial.viewport,'pan did persist viewport separately');
  frames.sort((a,b)=>a-b);const p95=frames[Math.floor(frames.length*.95)],max=frames.at(-1);
  const result={id:'packaged-performance-100pct',pass:p95<=20,visible,zoom,frames:frames.length,p95Ms:p95,maxMs:max,boardRevBefore:initial.rev,boardRevAfter:after.rev,broadcasts,domBefore,domAfter,viewportBefore:initial.viewport,viewportAfter:after.viewport,screenshot:await shot('05-packaged-performance-100pct')};
  results.push(result);return result;
};

exports.crash = async({app,board,state,dashboard,waitUntil,results})=>{
  const before=await state();
  const oldId=await app.evaluate(({BrowserWindow})=>{const w=BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/notes.html'));const id=w.id;w.webContents.forcefullyCrashRenderer();return id;});
  await waitUntil(()=>app.evaluate(({BrowserWindow},id)=>!BrowserWindow.fromId(id),oldId));
  await dashboard.evaluate(()=>window.electronAPI.openNotes());
  const reopened=await waitUntil(()=>app.windows().find(p=>p!==board&&p.url().endsWith('/notes.html')));
  await reopened.locator('.notes-app').waitFor();
  const after=await reopened.evaluate(()=>window.paplyNotes.get());
  assert.deepEqual(after.nodes,before.nodes);assert.deepEqual(after.edges,before.edges);
  const newId=await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/notes.html')).id);
  assert.notEqual(newId,oldId); results.push({id:'packaged-renderer-crash-reopen',pass:true,oldWindowId:oldId,newWindowId:newId,nodes:Object.keys(after.nodes).length});
  return reopened;
};

exports.updateQuit = async({app,results,waitUntil})=>{
  // Emit only the native lifecycle event. No update check, download or install.
  const before=await app.evaluate(({BrowserWindow,autoUpdater})=>{
    const w=BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/notes.html'));
    const id=w.id;const listeners=autoUpdater.listenerCount('before-quit-for-update');
    autoUpdater.emit('before-quit-for-update');w.close();return {id,listeners};
  });
  assert(before.listeners>0);await waitUntil(()=>app.evaluate(({BrowserWindow},id)=>!BrowserWindow.fromId(id),before.id));
  const result={id:'packaged-native-update-close',pass:true,windowId:before.id,listeners:before.listeners,destroyed:true};results.push(result);return result;
};
