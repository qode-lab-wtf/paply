import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { it, expect } from 'vitest';
import { TaskRows } from '../src/apps/notes/TaskRows';
it('11: completed tasks and orphaned own tasks are visible with honest source label',()=>{
 const task={id:'t',nodeId:'n',sourceId:'s',text:'Milch kaufen',done:true,due_hint:null,owner:'ai'};
 const render=board=>renderToStaticMarkup(React.createElement(TaskRows,{board,command:async()=>{},openSource:()=>{}}));
 expect(render({tasks:{t:task},nodes:{n:{label:'Einkauf'}}})).toContain('checked');
 const html=render({tasks:{t:{...task,owner:'user'}},nodes:{}});expect(html).toContain('Milch kaufen');expect(html).toContain('Gedanke entfernt');
 expect(render({tasks:{t:task},nodes:{}})).not.toContain('Milch kaufen');
});
