const assert=require('node:assert/strict');
const pause=ms=>new Promise(r=>setTimeout(r,ms));
exports.run=async({board,state,app,dashboard,shot})=>{
 // Volume fixture only: explicit user commands into a separate empty QA profile.
 for(let start=0;start<300;start+=100){const ops=Array.from({length:100},(_,i)=>{const n=start+i;return {type:'create',node:{kind:n%3===0?'sticky':n%3===1?'text':'note',text:`Synthetischer Leistungstest ${n}. Ein kurzer vollständiger Gedanke.`,label:`Notiz ${n}`,position:{x:(n%20)*360,y:Math.floor(n/20)*250}}}});await board.evaluate(ops=>window.paplyNotes.command(ops),ops);}
 await board.getByRole('button',{name:'Alles zeigen (⇧1)',exact:true}).click();await pause(800);
 const count=await board.locator('.react-flow__node').count();assert.equal(count,300,'300 nodes rendered at start');
 const sampling=board.evaluate(()=>new Promise(resolve=>{const ts=[];let start,last;function next(t){if(!start){start=t;last=t;}else{ts.push(t-last);last=t;}if(t-start<3100)requestAnimationFrame(next);else resolve(ts);}requestAnimationFrame(next);}));
 await board.mouse.move(600,450);const at=Date.now();let steps=0;while(Date.now()-at<3000){await board.mouse.wheel(steps%60<30?5:-5,0);steps++;await pause(18);}
 const frames=await sampling;frames.sort((a,b)=>a-b);const p95=frames[Math.floor(frames.length*.95)],max=frames.at(-1);
 const before=Date.now();await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.webContents.getURL().endsWith('/notes.html')).close());await dashboard.evaluate(()=>window.electronAPI.openNotes());await board.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>r(true))));const openMs=Date.now()-before;
 return {renderedNodes:count,frames:frames.length,p95Ms:p95,maxMs:max,warmOpenMs:openMs,passesFrameGate:p95<=20,passesOpenGate:openMs<=200,screenshot:await shot('performance-300')};
};
