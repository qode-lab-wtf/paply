const key=t=>{let s=t.toLowerCase().normalize('NFD').replace(/\p{M}/gu,'').replace(/ß/g,'ss').replace(/sch/g,'s').replace(/ch/g,'k').replace(/ph/g,'f').replace(/ck/g,'k').replace(/qu/g,'k').replace(/th/g,'t').replace(/dt/g,'t').replace(/x/g,'ks');
 s=s.replace(/[vfw]/g,'w').replace(/[cqg]/g,'k').replace(/[zs]/g,'s').replace(/b/g,'p').replace(/d/g,'t').replace(/[^a-z]/g,'').replace(/[aeiouyhj]/g,'');return s.replace(/(.)\1+/g,'$1')};
const lev=(a,b)=>{const m=[...Array(a.length+1)].map((_,i)=>[i,...Array(b.length).fill(0)]);for(let j=1;j<=b.length;j++)m[0][j]=j;for(let i=1;i<=a.length;i++)for(let j=1;j<=b.length;j++)m[i][j]=Math.min(m[i-1][j]+1,m[i][j-1]+1,m[i-1][j-1]+(a[i-1]!==b[j-1]));return m[a.length][b.length]};
const norm=t=>t.toLowerCase().replace(/[^\p{L}\p{N} ]/gu,' ').replace(/\s+/g,' ').trim();
const plain=t=>t.normalize('NFD').replace(/\p{M}/gu,'').replace(/ /g,'');
const window_=(term,text,RATIO=SPELLING_RATIO, cache=new Windows(text))=>{const T=norm(term),w=norm(text).split(' ');if((' '+norm(text)+' ').includes(' '+T+' '))return null;const k=key(term);if(k.length<3)return null;const n=T.split(' ').length+1,tol=k.length>=4?1:0;const lim=Math.ceil(plain(T).length*RATIO);
 for(let i=0;i<w.length;i++)for(let l=1;l<=n&&i+l<=w.length;l++){const {cand,x,p}=cache.get(i,l);if(x.length>=3&&lev(x,k)<=tol&&lev(p,plain(T))<=lim)return {i,l}}return null};
const acc=(c,RATIO=SPELLING_RATIO)=>{if(c.lpFirst==null||c.lpSecond==null)return false;if(c.lpSecond<c.lpFirst-TERM_GAP)return false;const f=norm(c.first).split(' '),s=norm(c.second),T=norm(c.term);if((' '+f.join(' ')+' ').includes(' '+T+' ')||!(' '+s+' ').includes(' '+T+' '))return false;const win=window_(c.term,c.first,RATIO);if(!win)return false;
 const F=[...f.slice(0,win.i),...f.slice(win.i+win.l)];const parts=(' '+s+' ').split(' '+T+' ');const hits=parts.length-1;if(hits>1&&F.length<3)return false;const S=parts.join(' ').trim().split(' ').filter(Boolean);
 const left=[...S];const gone=[];for(const w of F){const p=left.indexOf(w);if(p<0)gone.push(w);else left.splice(p,1)}const allow=Math.floor(F.length/10);
 if(gone.length<=allow&&left.length<=allow)return true;
 const before=f[win.i-1],after=f[win.i+win.l];return gone.length===allow+1&&left.length<=allow&&F.length>=4&&(gone.includes(before)||gone.includes(after))};

const TERM_GAP = 0.05;
const SPELLING_RATIO = 0.6;
class Windows {
 constructor(text) { this.words=norm(text).split(' '); this.cache=new Map(); }
 get(i,l) { const id=i+':'+l; if(!this.cache.has(id)) { const cand=this.words.slice(i,i+l).join(' '); this.cache.set(id,{cand,x:key(cand),p:plain(cand)}); } return this.cache.get(id); }
}
const near=(term,text)=>!!window_(term,text);
const { confidence } = require('./language-guard');
function candidates(vocabulary, response) {
 const text=response.text || '', cache=new Windows(text);
 const selected=vocabulary.split(/[,;\n\r]/).map(t=>t.trim()).filter(Boolean).filter(t=>window_(t,text,SPELLING_RATIO,cache)).slice(0,3);
 return {terms:selected,prompt:selected.map(t=>t+', '+t+'.').join(' ')};
}
async function termCheck(first, vocabulary, request, firstMs, signal, diagnose = (requested,accepted)=>console.log('[Begriffe]', requested, accepted)) {
 const c = candidates(vocabulary, first);
 if (!c.terms.length) { diagnose(0,0); return first; }
 let timer, accepted = false;
 try {
  signal?.throwIfAborted();
  const second = await Promise.race([request(first.language,c.prompt),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('timeout')),Math.min(60000,2*firstMs+5000));})]);
  signal?.throwIfAborted();
  accepted = c.terms.some(term=>acc({term,first:first.text || '',second:second.text || '',lpFirst:confidence(first),lpSecond:confidence(second)}));
  return accepted ? {...second,language:first.language} : first;
 } catch(error) { if (signal?.aborted) throw error; return first; }
 finally { clearTimeout(timer); diagnose(1,Number(accepted)); }
}
module.exports = { key, near, acc, candidates, termCheck, TERM_GAP, SPELLING_RATIO };
