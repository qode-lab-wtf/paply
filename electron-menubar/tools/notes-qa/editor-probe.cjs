// Passive diagnostics for an observed first-click save race; test process only.
exports.install=async c=>{
  await c.app.evaluate(({ipcMain})=>{
    global.__qaEditorIpc=[];
    for(const channel of ['notes:command','notes:editing']){
      const original=ipcMain._invokeHandlers.get(channel);
      ipcMain._invokeHandlers.set(channel,async(...args)=>{
        const event={channel,payload:args[1],at:Date.now()};global.__qaEditorIpc.push(event);
        try {const result=await original(...args);event.resultRev=result?.rev;return result;}
        catch(error){event.error=String(error);throw error;}
      });
    }
  });
  await c.board.evaluate(()=>{
    window.__qaEditorEvents=[];
    function hooks(element){
      let fiber=element?.[Object.keys(element).find(k=>k.startsWith('__reactFiber'))];const result=[];
      for(let i=0;fiber&&i<20;i++,fiber=fiber.return){
        if(typeof fiber.type!=='function')continue;
        let hook=fiber.memoizedState,values=[];
        for(let j=0;hook&&j<12;j++,hook=hook.next){
          const value=hook.memoizedState;
          if(typeof value==='string'||typeof value==='boolean')values.push({j,value});
          else if(value&&typeof value==='object'&&'current' in value){
            const current=value.current;
            values.push({j,ref:current instanceof Promise?'Promise':current&&typeof current==='object'&&current.id?{id:current.id,text:current.text,pending:current.pending,rev:current.rev,owner:current.owner,sentenceIds:current.sentenceIds}:typeof current==='boolean'||current===null?current:typeof current});
          }
        }
        if(values.length)result.push({name:fiber.type.name,values});
      }
      return result;
    }
    for(const type of ['pointerdown','pointerup','click','blur'])document.addEventListener(type,e=>{
      const body=e.target.closest?.('[data-note-body]');if(!body)return;
      window.__qaEditorEvents.push({at:Date.now(),type,target:e.target.tagName,text:e.target.tagName==='BUTTON'?e.target.textContent:undefined,related:e.relatedTarget?.tagName,pending:!!body.querySelector('.spin'),hooks:hooks(e.target)});
    },true);
    const observer=new MutationObserver(()=>{const toast=document.querySelector('.notes-toast')?.textContent;if(toast&&toast!==window.__qaLastToast){window.__qaEditorEvents.push({at:Date.now(),toast});window.__qaLastToast=toast;}});
    observer.observe(document.body,{childList:true,subtree:true,characterData:true});
  });
};
exports.report=async c=>({ipc:await c.app.evaluate(()=>global.__qaEditorIpc),ui:await c.board.evaluate(()=>window.__qaEditorEvents)});
