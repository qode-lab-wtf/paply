import React,{createContext,useContext,useState,useRef,useEffect,useLayoutEffect} from 'react';
import {createRoot} from 'react-dom/client';
import {defineComponent,createLibrary,Renderer} from '@openuidev/react-lang';
import {z} from 'zod';
import {ArrowUpRight,ArrowRight,ArrowLeft,Camera,Check,ChevronDown,Copy,Expand,FileText,Footprints,Hand,House,LampCeiling,MapPin,Mic,Minus,MousePointer2,Pencil,Plus,Quote,Route,Shapes,StickyNote,Sun,Table2,Trash2,Undo2,Waves,Wind,X,Workflow,ZoomIn} from 'lucide-react';

// Prepared demo data, no LLM or network calls. Canonical text lives outside OpenUI.
const SOURCES={
 t1:{time:'09:12',text:'Ich brauche im Frühjahr ein paar Tage Pause. Vielleicht Portugal, irgendwo am Meer, eher ein kleines Haus als ein Hotel. Hauptsache ruhig.'},
 t2:{time:'13:40',text:'Zum Urlaub: Die kleine Kamera würde ich mitnehmen. Ich will eigentlich wenig planen, einfach laufen, fotografieren, gut essen.'},
 t3:{time:'18:06',text:'Im Urlaub will ich nicht jeden Moment fotografieren. Lieber ein paar bewusste Bilder am Tag und den Rest einfach angucken.'},
 h1:{time:'10:23',text:'Die Lampe über dem Esstisch ist zu kalt und zu hell. Ich möchte warmes, dimmbares Licht. Bei der Größe bin ich noch unsicher.'},
 h2:{time:'16:10',text:'Ich habe zwei Ideen für die Lampe: A ist aus Papier, 45 Zentimeter, dimmbar. B ist aus Opalglas, 35 Zentimeter. Ob B dimmbar ist, muss ich noch nachschauen. Preise habe ich noch keine.'},
 p1:{time:'08:35',text:'Zu Paply: Ich will morgens Gedanken loswerden können, ohne gleich zu entscheiden, wohin sie gehören. Einfach Kürzel drücken, reden, weiterarbeiten. Abends soll da eine Ordnung sein, die ich nachvollziehen kann.'},
 p2:{time:'14:52',text:'Das Board soll sich sofort bewegen und zoomen, wie Figma. Ich möchte ganze Gedanken sehen und sie bearbeiten können. Keine Aufgaben-App, keine Fälligkeiten, kein Pflegen.'}
};
const INITIAL={
 t_place:{text:'Vielleicht Portugal.\nIrgendwo am Meer.',source:'t1',label:'Wohin?',icon:'place'},
 t_house:{text:'Ein kleines Haus,\nlieber als ein Hotel.',source:'t1',label:'Wohnen',icon:'home'},
 t_pace:{text:'Wenig planen. Laufen,\nfotografieren, gut essen.',source:'t2',label:'Die Tage',icon:'walk'},
 t_photo:{text:'Ein paar bewusste Bilder.\nDen Rest einfach angucken.',source:'t3',label:'Mit der kleinen Kamera',icon:'camera'},
 t_core:{text:'Ein paar Tage\nraus.',source:'t1',label:'Im Frühjahr',icon:'sun'},
 h_wish:{text:'Warmes, dimmbares Licht.\nAbends soll es gemütlich sein.',source:'h1',label:'Was ich suche',icon:'sun'},
 h_material_a:{text:'Papier',source:'h2',label:'Material · A'}, h_material_b:{text:'Opalglas',source:'h2',label:'Material · B'},
 h_size_a:{text:'45 cm',source:'h2',label:'Durchmesser · A'}, h_size_b:{text:'35 cm',source:'h2',label:'Durchmesser · B'},
 h_dim_a:{text:'Dimmbar',source:'h2',label:'Licht · A'}, h_dim_b:{text:'Noch nachschauen',source:'h2',label:'Licht · B'},
 h_question:{text:'Welche Größe passt\nüber den Tisch?',source:'h1',label:'Noch offen',icon:'lamp'},
 p_start:{text:'Kürzel drücken.',source:'p1',label:'Ein Gedanke kommt',icon:'hotkey'},
 p_speak:{text:'Frei sprechen.\nAuch über mehrere Themen.',source:'p1',label:'Loswerden',icon:'mic'},
 p_continue:{text:'Weiterarbeiten.\nOhne vorher zu sortieren.',source:'p1',label:'Kopf wieder frei',icon:'wind'},
 p_evening:{text:'Abends nachvollziehen,\nwas mich beschäftigt hat.',source:'p1',label:'Wiederfinden',icon:'map'},
 p_boundary:{text:'Eine Gedankenablage.\nKeine Aufgaben-App. Kein Pflegen.',source:'p2',label:'Das soll es bleiben',icon:'sticky'},
 p_native:{text:'Sofort bewegen und zoomen.\nGanze Gedanken bearbeiten.',source:'p2',label:'Wie es sich anfühlt',icon:'hand'}
};
const TOPICS={trip:{title:'Auszeit',subtitle:'Ein Wunsch, der über den Tag klarer wird.',type:'Mindmap',root:'MindMap',icon:Sun,ids:Object.keys(INITIAL).filter(x=>x.startsWith('t_'))},home:{title:'Zuhause',subtitle:'Zwei Ideen für die Lampe am Esstisch.',type:'Vergleich',root:'Comparison',icon:House,ids:Object.keys(INITIAL).filter(x=>x.startsWith('h_'))},paply:{title:'Paply',subtitle:'Gedanken loswerden. Später wiederfinden.',type:'Ablauf',root:'Flow',icon:Workflow,ids:Object.keys(INITIAL).filter(x=>x.startsWith('p_'))}};
const icons={place:MapPin,home:House,walk:Footprints,camera:Camera,sun:Sun,lamp:LampCeiling,hotkey:Shapes,mic:Mic,wind:Wind,map:Workflow,sticky:StickyNote,hand:Hand};
const Store=createContext(null);
function Icon({name,...props}){const C=icons[name]||FileText;return <C aria-hidden="true" {...props}/>}
function IconButton({icon:C,label,onClick,active,disabled,...rest}){return <button className={'icon-btn'+(active?' active':'')} aria-label={label} title={label} onClick={onClick} disabled={disabled} {...rest}><C size={18} strokeWidth={1.65}/></button>}
function Thought({id,style,kind='',label=true}){const s=useContext(Store),n=s.notes[id];if(!n)return <div className="removed" style={style}>Entfernt</div>;return <button data-note={id} className={'thought '+kind+(s.selected===id?' selected':'')} style={style} onClick={()=>s.select(id)} onDoubleClick={()=>s.select(id,true)}><span className="thought-label">{n.icon&&<Icon name={n.icon} size={23}/>} {label&&n.label}</span><span className="thought-text">{n.text}</span></button>}
function MindMap(){return <div className="composition mindmap" data-layout="mindmap">
 <svg className="connections desktop-lines" viewBox="0 0 900 550" aria-label="Gedanken zu Reiseziel, Unterkunft, Tagesgestaltung und Fotografie"><path d="M370 230 C305 230 318 147 268 147"/><path d="M370 273 C308 273 319 390 270 390"/><path d="M534 230 C594 230 568 139 627 139"/><path d="M534 273 C599 273 576 390 625 390"/><path className="inferred" d="M217 215 C213 268 198 298 217 331"/><path className="inferred" d="M702 208 C746 254 744 282 714 331"/><path className="underline" d="M366 296 Q443 311 535 295"/></svg>
 <svg className="mobile-lines" viewBox="0 0 450 610" aria-hidden="true"><path d="M180 125 C180 165 110 150 110 184 M280 125 C280 165 345 150 345 184 M110 302 L110 364 M345 302 L345 364"/></svg><Thought id="t_core" kind="center-note" style={{left:352,top:192,width:200}}/>
 <Thought id="t_place" style={{left:35,top:100,width:240}}/><Thought id="t_house" style={{left:35,top:335,width:250}}/>
 <Thought id="t_pace" style={{left:623,top:94,width:257}}/><Thought id="t_photo" style={{left:623,top:332,width:257}}/>
 <span className="pen annotation" style={{left:340,top:355,transform:'rotate(-4deg)'}}>Hauptsache ruhig.</span>
 <Waves className="scene-waves" size={65} strokeWidth={1}/>
 <span className="source-stamp"><Mic size={13}/> 3 Momente · heute</span>
 </div>}
function Cell({id}){const s=useContext(Store);return <button className={'table-cell'+(s.selected===id?' selected':'')} data-note={id} onClick={()=>s.select(id)} onDoubleClick={()=>s.select(id,true)}>{s.notes[id]?.text||'—'}</button>}
function Comparison(){return <div className="composition comparison" data-layout="comparison">
 <Thought id="h_wish" kind="loose-note" style={{left:25,top:25,width:340}}/>
 <div className="comparison-sheet"><table><thead><tr><th>Meine zwei Ideen</th><th><span className="lamp-a"><LampCeiling size={52} strokeWidth={1.2}/></span><span>Idee A</span></th><th><span className="lamp-b"><LampCeiling size={43} strokeWidth={1.2}/></span><span>Idee B</span></th></tr></thead><tbody>
 <tr><th>Material</th><td><Cell id="h_material_a"/></td><td><Cell id="h_material_b"/></td></tr><tr><th>Durchmesser</th><td><Cell id="h_size_a"/></td><td><Cell id="h_size_b"/></td></tr><tr><th>Licht</th><td><Cell id="h_dim_a"/></td><td><Cell id="h_dim_b"/></td></tr><tr className="unknown"><th>Preis</th><td>Nicht genannt</td><td>Nicht genannt</td></tr>
 </tbody></table></div>
 <Thought id="h_question" kind="yellow-note" style={{left:647,top:275,width:227,transform:'rotate(3deg)'}}/>
 <svg className="connections" viewBox="0 0 900 550" aria-hidden="true"><path className="inferred" d="M651 334 Q625 315 598 337"/><path d="M598 337 l14 4 m-14 -4 l5 -12"/></svg>
 <span className="source-stamp"><Mic size={13}/> 2 Momente · heute</span>
 </div>}
function Flow(){return <div className="composition flow" data-layout="flow">
 <svg className="connections" viewBox="0 0 900 550" aria-label="Vom Einsprechen bis zum Wiederfinden"><defs><marker id="flow-arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path className="arrow-tip" d="M1 1 L7 4 L1 7"/></marker></defs><path markerEnd="url(#flow-arrow)" d="M206 160 Q226 150 249 160"/><path markerEnd="url(#flow-arrow)" d="M431 160 Q451 150 477 160"/><path markerEnd="url(#flow-arrow)" d="M657 160 Q679 150 704 160"/><path className="inferred" d="M800 310 C800 344 624 329 624 357"/></svg>
 <Thought id="p_start" kind="flow-step" style={{left:18,top:90,width:194}}/><Thought id="p_speak" kind="flow-step" style={{left:245,top:90,width:194}}/><Thought id="p_continue" kind="flow-step" style={{left:470,top:90,width:200}}/><Thought id="p_evening" kind="flow-step final-step" style={{left:699,top:90,width:194}}/>
 <Thought id="p_boundary" kind="yellow-note" style={{left:84,top:345,width:360,transform:'rotate(-2deg)'}}/><Thought id="p_native" kind="loose-note" style={{left:520,top:357,width:355}}/>
 <span className="pen annotation" style={{left:56,top:30}}>Ein Gedanke darf einfach anfangen.</span><span className="source-stamp"><Mic size={13}/> 2 Momente · heute</span>
 </div>}
function FreeNotes({topic}){return <div className="composition free-notes" data-layout="notes">{TOPICS[topic].ids.map((id,i)=><Thought key={id} id={id} kind="paper-note" style={{left:20+(i%3)*295,top:20+Math.floor(i/3)*170,width:275,"--mobile-x":(10+(i%2)*225)+"px","--mobile-y":(20+Math.floor(i/2)*195)+"px"}}/>)}</div>}
const comps=[['MindMap',MindMap],['Comparison',Comparison],['Flow',Flow],['FreeNotes',FreeNotes]].map(([name,C])=>defineComponent({name,description:'Read-only layout backed by editable canonical note IDs; no invented facts.',props:z.object({topic:z.enum(['trip','home','paply'])}),component:({props})=><C topic={props.topic}/>}));
const library=createLibrary({components:comps,root:'MindMap'});
const INITIAL_STATE={notes:INITIAL,annotations:{trip:[],home:[],paply:[]}};
function App(){
 const [data,setData]=useState(()=>{const p=window.openai?.widgetState?.privateContent;return p?.v===1?p.data:INITIAL_STATE});
 const [topic,setTopic]=useState('trip'),[plain,setPlain]=useState(false),[selected,setSelected]=useState(null),[editing,setEditing]=useState(false),[draft,setDraft]=useState(''),[source,setSource]=useState(false),[history,setHistory]=useState([]),[tool,setTool]=useState('select'),[toast,setToast]=useState(''),[cam,setCam]=useState({x:0,y:0,z:1});
 const viewport=useRef(null),gesture=useRef(null),suppressClick=useRef(false),toastTimer=useRef(null),[dim,setDim]=useState({w:728,h:525}),[stroke,setStroke]=useState(null);
 const notes=data.notes, current=TOPICS[topic],selectedNote=notes[selected];
 const persist=next=>window.openai?.setWidgetState?.({modelContent:{topic,view:plain?'notes':current.type},privateContent:{v:1,data:next}})?.catch(()=>{});
 function commit(next){setHistory(h=>[...h.slice(-29),data]);setData(next);persist(next)}
 function undo(){if(!history.length)return;const prev=history.at(-1);setData(prev);setHistory(history.slice(0,-1));setSelected(null);setEditing(false);persist(prev)}
 function notify(t){setToast(t);clearTimeout(toastTimer.current);toastTimer.current=setTimeout(()=>setToast(''),2000)}
 function select(id,edit=false){if(tool!=='select')return;setSelected(id);setSource(false);setDraft(notes[id]?.text||'');setEditing(edit)}
 function save(){if(!selectedNote)return;commit({...data,notes:{...notes,[selected]:{...selectedNote,text:draft}}});setEditing(false)}
 function fit(){const d=viewport.current?.getBoundingClientRect();if(!d)return;const mobile=d.width<480;const wide=mobile?450:900;const tall=mobile?(plain?Math.ceil(current.ids.length/2)*195+50:topic==='trip'?610:topic==='home'?760:950):(plain?Math.max(550,Math.ceil(current.ids.length/3)*170+40):550);const z=Math.min(1.1,(d.width-(mobile?8:32))/wide,(d.height-64)/tall);setCam({x:(d.width-wide*z)/2,y:mobile?15:(d.height-tall*z)/2,z});}
 useLayoutEffect(()=>{const ro=new ResizeObserver(e=>{setDim({w:e[0].contentRect.width,h:e[0].contentRect.height})});ro.observe(viewport.current);return()=>ro.disconnect()},[]);
 useLayoutEffect(fit,[topic,plain,dim.w,dim.h]);
 useEffect(()=>{const vp=viewport.current;const wheel=e=>{e.preventDefault();setCam(c=>{if(e.ctrlKey||e.metaKey){const r=vp.getBoundingClientRect(),px=e.clientX-r.left,py=e.clientY-r.top,z=Math.max(.35,Math.min(2.2,c.z*Math.exp(-Math.max(-100,Math.min(100,e.deltaY))*.003)));return {x:px-(px-c.x)*z/c.z,y:py-(py-c.y)*z/c.z,z}}return {...c,x:c.x-e.deltaX,y:c.y-e.deltaY}})};vp.addEventListener('wheel',wheel,{passive:false});return()=>vp.removeEventListener('wheel',wheel)},[]);
 useEffect(()=>{function key(e){if(/TEXTAREA|INPUT/.test(e.target.tagName))return;if((e.metaKey||e.ctrlKey)&&e.key==='z'){e.preventDefault();undo()}if(e.key==='Escape'){setSelected(null);setTool('select');setEditing(false)}if((e.key==='Backspace'||e.key==='Delete')&&selected){e.preventDefault();remove()}}window.addEventListener('keydown',key);return()=>window.removeEventListener('keydown',key)},[data,history,selected]);
 function remove(){const next={...notes};delete next[selected];commit({...data,notes:next});setSelected(null);setEditing(false)}
 function zoom(factor){setCam(c=>{const z=Math.max(.35,Math.min(2.2,c.z*factor)),px=dim.w/2,py=dim.h/2;return {z,x:px-(px-c.x)*z/c.z,y:py-(py-c.y)*z/c.z}})}
 function point(e){const r=viewport.current.getBoundingClientRect();return {x:(e.clientX-r.left-cam.x)/cam.z,y:(e.clientY-r.top-cam.y)/cam.z}}
 function down(e){if(e.button!==0||e.target.closest('.icon-btn')||(tool==='select'&&e.target.closest('.thought,.table-cell')))return;const p=point(e);if(tool==='sticky'){suppressClick.current=true;const id='user_'+Date.now();commit({notes:{...notes,[id]:{text:'Mein Gedanke …',label:'Eigene Notiz',source:null,icon:'sticky'}},annotations:{...data.annotations,[topic]:[...data.annotations[topic],{type:'sticky',id,...p}]}});setTool('select');setSelected(id);setDraft('Mein Gedanke …');setEditing(true);return}if(tool==='arrow'||tool==='line'){setStroke({...p,x2:p.x,y2:p.y,type:tool});gesture.current={mode:'draw',...p};}else{setSelected(null);gesture.current={mode:'pan',x:e.clientX,y:e.clientY,c:cam}}e.currentTarget.setPointerCapture(e.pointerId)}
 function move(e){const g=gesture.current;if(!g)return;if(g.mode==='draw'){const p=point(e);setStroke({x:g.x,y:g.y,x2:p.x,y2:p.y,type:tool})}else setCam({...g.c,x:g.c.x+e.clientX-g.x,y:g.c.y+e.clientY-g.y})}
 function up(){if(gesture.current?.mode==='draw'&&stroke&&Math.hypot(stroke.x2-stroke.x,stroke.y2-stroke.y)>8)commit({...data,annotations:{...data.annotations,[topic]:[...data.annotations[topic],stroke]}});gesture.current=null;setStroke(null)}
 const response=`root = ${plain?'FreeNotes':current.root}("${topic}")`;
 useEffect(()=>{window.paplyGenerative={getState:()=>({topic,plain,data,history:history.length,cam,selected,render:response}),selectTopic:t=>{if(TOPICS[t])setTopic(t)},setPlain,select,undo,fit,errors:window.paplyGenerative?.errors||[],version:'openui-1'}},[topic,plain,data,history,cam,selected]);
 useEffect(()=>{if(!globalThis.Tweak)return;const el=document.getElementById('paply-generative'),opts={lines:1.5,paper:true};const t=new Tweak({container:el,onChange:()=>{el.style.setProperty('--sketch-width',opts.lines+'px');el.classList.toggle('no-paper',!opts.paper)}});t.addSlider(opts,'lines',{min:1,max:3,step:.25,label:'Linienstärke'});t.addToggle(opts,'paper',{label:'Papiertextur'});return()=>t.dispose()},[]);
 return <Store.Provider value={{notes,selected,select}}><main className="paply-app" aria-label="Paply Notes – interaktiver Entwurf">
 <header className="app-header"><div className="brand"><img src="__PAPLY_LOGO__" alt=""/><span>paply<span className="brand-divider">/</span><span className="brand-notes">notes</span></span></div><span className="prototype-badge">Entwurf</span><IconButton icon={Undo2} label="Rückgängig" onClick={undo} disabled={!history.length}/></header>
 <nav className="topic-nav" aria-label="Gedankenbereiche">{Object.entries(TOPICS).map(([id,t])=><button key={id} className={topic===id?'active':''} aria-current={topic===id?'page':undefined} onClick={()=>{setTopic(id);setSelected(null);setPlain(false)}}><t.icon size={16} strokeWidth={1.6}/>{t.title}</button>)}</nav>
 <div className="area-heading"><div><h1>{current.title}</h1><p>{current.subtitle}</p></div><button className="view-button" onClick={()=>{setPlain(!plain);setSelected(null)}} title="Zwischen visueller Ansicht und einzelnen Notizen wechseln">{plain?<FileText size={15}/>:topic==='home'?<Table2 size={15}/>:<Workflow size={15}/>}<span>{plain?'Notizen':current.type}</span><ArrowLeft size={13}/></button></div>
 <div className={'viewport tool-'+tool+(dim.w<480?' mobile':'')} style={dim.w<480?{height:plain?Math.min(1000,Math.ceil(current.ids.length/2)*153+90):topic==='trip'?550:topic==='home'?670:800}:undefined} ref={viewport} onClickCapture={e=>{if(suppressClick.current){e.stopPropagation();suppressClick.current=false}}} onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={()=>{gesture.current=null;setStroke(null)}}>
 <div className="world" style={{transform:`translate(${cam.x}px,${cam.y}px) scale(${cam.z})`}}><Renderer response={response} library={library} isStreaming={false} publishObservability={false} onError={e=>{if(e.length){window.paplyGenerative.errors=e;console.error('OpenUI',e)}}}/>
 <svg className="user-lines" viewBox="0 0 900 550" aria-hidden="true"><defs><marker id="user-arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M1 1 L7 4 L1 7"/></marker></defs>{[...data.annotations[topic],...(stroke?[stroke]:[])].filter(a=>a.type!=='sticky').map((a,i)=><line key={i} x1={a.x} y1={a.y} x2={a.x2} y2={a.y2} markerEnd={a.type==='arrow'?'url(#user-arrow)':undefined}/>)}</svg>
 {data.annotations[topic].filter(a=>a.type==='sticky').map(a=><Thought key={a.id} id={a.id} kind="yellow-note" style={{left:a.x,top:a.y,width:230}}/>)}
 </div>
 {selectedNote&&<aside className="inspector" aria-label="Ausgewählte Notiz" onPointerDown={e=>e.stopPropagation()}><div className="inspector-toolbar"><span>{selectedNote.label}</span><IconButton icon={Pencil} label="Bearbeiten" active={editing} onClick={()=>{setDraft(selectedNote.text);setEditing(!editing);setSource(false)}}/><IconButton icon={Copy} label="Text kopieren" onClick={async()=>{try{await navigator.clipboard.writeText(selectedNote.text);notify('Kopiert')}catch{setDraft(selectedNote.text);setEditing(true);notify('Text markieren und kopieren')}}}/>{selectedNote.source&&<IconButton icon={Quote} label="Original ansehen" active={source} onClick={()=>{setSource(!source);setEditing(false)}}/>}<IconButton icon={Trash2} label="Notiz entfernen" onClick={remove}/><IconButton icon={X} label="Auswahl schließen" onClick={()=>setSelected(null)}/></div>
 {editing&&<div className="editor"><textarea aria-label="Notiztext" value={draft} onChange={e=>setDraft(e.target.value)} autoFocus/><button className="save-button" onClick={save}><Check size={15}/>Übernehmen</button></div>}
 {source&&<div className="original"><span><Mic size={13}/>{SOURCES[selectedNote.source].time} · Original</span><p>{SOURCES[selectedNote.source].text}</p></div>}
 </aside>}
 {toast&&<div className="toast" role="status">{toast}</div>}
 <div className="board-tools" onPointerDown={e=>e.stopPropagation()}><div className="tool-group">{[['select',MousePointer2,'Auswählen'],['hand',Hand,'Verschieben'],['sticky',StickyNote,'Notiz platzieren'],['arrow',ArrowUpRight,'Pfeil zeichnen'],['line',Minus,'Linie zeichnen']].map(([id,C,l])=><IconButton key={id} icon={C} label={l} active={tool===id} onClick={()=>{setTool(id);setSelected(null)}}/>)}</div><div className="tool-group zoom-tools"><IconButton icon={Minus} label="Verkleinern" onClick={()=>zoom(1/1.2)}/><span>{Math.round(cam.z*100)}%</span><IconButton icon={Plus} label="Vergrößern" onClick={()=>zoom(1.2)}/><IconButton icon={Expand} label="Alles zeigen" onClick={fit}/></div></div>
 </div>
 <footer><span><span className="status-dot"/>OpenUI · vorbereitete Ansichten</span><span>Beispielnotizen · keine Live-KI</span></footer>
 </main></Store.Provider>
}
createRoot(document.getElementById('paply-generative')).render(<App/>);
