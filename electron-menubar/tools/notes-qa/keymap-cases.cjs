// Targeted notes.2 package checks; no capture or native keyboard event dispatch.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const compact=value=>value.replace(/\s/g,'');
exports.check=async(c,{custom=false}={})=>{
  const expected=custom?['Command+Y','Command+Alt+Y']:['Command+Z','Command+Alt+Z'];
  const labels=custom?['⌘Z','⌘⌥Z']:['⌘Y','⌘⌥Y'];
  const prefs=await c.dashboard.evaluate(()=>window.electronAPI.getNotesSettings());
  assert.deepEqual([prefs.captureHotkey,prefs.openHotkey],expected);
  assert.equal(prefs.warning,'');assert.equal(prefs.keyLabels.Y,'Z');assert.equal(prefs.keyLabels.Z,'Y');
  const native=await c.app.evaluate(({app,globalShortcut},keys)=>({
    version:app.getVersion(),packaged:app.isPackaged,
    registered:keys.map(k=>globalShortcut.isRegistered(k)),
    otherRegistered:keys.map(k=>globalShortcut.isRegistered(k.replace(/([YZ])$/,x=>x==='Y'?'Z':'Y'))),
  }),expected);
  assert.equal(native.version,'1.15.0-notes.2');assert.equal(native.packaged,true);
  assert.deepEqual(native.registered,[true,true]);assert.deepEqual(native.otherRegistered,[false,false]);
  const s=await c.state();assert.equal(Object.keys(s.nodes).length,0);assert.equal(s.capture.active,false);
  assert.deepEqual([s.preferences.keyLabels.Y,s.preferences.keyLabels.Z],['Z','Y']);
  const emptyLabel=await c.board.locator('.empty-board kbd').textContent();assert.equal(compact(emptyLabel),labels[0]);
  const emptyScreenshot=await c.shot(custom?'keymap-custom-empty':'keymap-fresh-empty');
  await c.board.getByRole('button',{name:'Notes-Einstellungen',exact:true}).click();
  const settings=await c.waitUntil(()=>c.app.windows().find(p=>p.url().endsWith('/settings.html')));
  const capture=settings.getByRole('textbox',{name:'Notes Aufnahme-Kürzel',exact:true}),open=settings.getByRole('textbox',{name:'Notes Öffnen-Kürzel',exact:true});await capture.waitFor();
  assert.deepEqual([compact(await capture.inputValue()),compact(await open.inputValue())],labels);
  await capture.scrollIntoViewIfNeeded();
  const settingsScreenshot=path.join(c.artifact,custom?'keymap-custom-settings.png':'keymap-fresh-settings.png');await settings.screenshot({path:settingsScreenshot});
  const stored=JSON.parse(fs.readFileSync(path.join(c.profile,'config.json'),'utf8')).notesSettings;
  if(custom)assert.deepEqual([stored.captureHotkey,stored.openHotkey],expected);
  else assert.equal(stored,undefined,'fresh profile had no stored Notes defaults');
  assert.equal(c.requests.length,0,'hotkey/display checks make no AI or audio requests');
  const result={id:custom?'notes2-custom-physical-preserved':'notes2-German-fresh-defaults',pass:true,native,physicalKeys:expected,labels,emptyLabel,keyLabels:{Y:prefs.keyLabels.Y,Z:prefs.keyLabels.Z},storedKeys:stored?{captureHotkey:stored.captureHotkey,openHotkey:stored.openHotkey}:null,emptyScreenshot,settingsScreenshot};
  c.results.push(result);return result;
};
