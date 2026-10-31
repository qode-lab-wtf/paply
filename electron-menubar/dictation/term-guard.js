const key=t=>{let s=t.toLowerCase().normalize('NFD').replace(/\p{M}/gu,'').replace(/ß/g,'ss').replace(/sch/g,'s').replace(/ch/g,'k').replace(/ph/g,'f').replace(/ck/g,'k').replace(/qu/g,'k').replace(/th/g,'t').replace(/dt/g,'t').replace(/x/g,'ks');
 s=s.replace(/[vfw]/g,'w').replace(/[cqg]/g,'k').replace(/[zs]/g,'s').replace(/b/g,'p').replace(/d/g,'t').replace(/[^a-z]/g,'').replace(/[aeiouyhj]/g,'');return s.replace(/(.)\1+/g,'$1')};
const lev=(a,b)=>{const m=[...Array(a.length+1)].map((_,i)=>[i,...Array(b.length).fill(0)]);for(let j=1;j<=b.length;j++)m[0][j]=j;for(let i=1;i<=a.length;i++)for(let j=1;j<=b.length;j++)m[i][j]=Math.min(m[i-1][j]+1,m[i][j-1]+1,m[i-1][j-1]+(a[i-1]!==b[j-1]));return m[a.length][b.length]};
const norm=t=>t.toLowerCase().replace(/[^\p{L}\p{N} ]/gu,' ').replace(/\s+/g,' ').trim();
const near=(term,text)=>{if(norm(text).includes(norm(term)))return false;const k=key(term),w=norm(text).split(' '),n=norm(term).split(' ').length+1,tol=k.length>=4?1:0;for(let i=0;i<w.length;i++)for(let l=1;l<=n&&i+l<=w.length;l++){const x=key(w.slice(i,i+l).join(' '));if(x.length>=2&&lev(x,k)<=tol)return true}return false};
const TERM_GAP = 0.05;
const acc=c=>{if(c.lpFirst==null||c.lpSecond==null)return false;const f=norm(c.first),s=norm(c.second),t=norm(c.term);if(f.includes(t)||!s.includes(t))return false;if(c.lpSecond<c.lpFirst-TERM_GAP)return false;const a=new Set(f.split(' ')),b=new Set(s.split(' '));const tw=t.split(' ').length;return [...b].filter(x=>!a.has(x)).length<=tw+1&&[...a].filter(x=>!b.has(x)).length<=tw+2};

const { confidence } = require('./language-guard');
const { estimateTokens } = require('./whisper-prompt');
function candidates(vocabulary, response) {
 const terms = vocabulary.split(/[,;\n\r]/).map(t=>t.trim()).filter(Boolean);
 let selected = terms.filter(t=>near(t,response.text || '')).slice(0,3);
 const uncertain = !selected.length && response.segments?.some(s=>s.avg_logprob != null && s.avg_logprob < -0.5);
 if (uncertain) { for (const term of terms) { if (estimateTokens([...selected,term].join(', ')) > 90) break; selected.push(term); } }
 return { terms:selected, prompt: !selected.length ? '' : uncertain ? selected.join(', ') : selected.map(t=>t+', '+t+'.').join(' ')+' Hallo '+selected[0]+'.' };
}
async function termCheck(first, vocabulary, request, firstMs, signal, diagnose = ()=>{}) {
 const c = candidates(vocabulary, first);
 if (!c.terms.length) { diagnose(0,0); return first; }
 let timer, accepted = false;
 try {
  signal?.throwIfAborted();
  const second = await Promise.race([request(first.language,c.prompt),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('timeout')),Math.min(60000,2*firstMs+5000));})]);
  signal?.throwIfAborted();
  accepted = c.terms.some(term=>acc({term,first:first.text || '',second:second.text || '',lpFirst:confidence(first),lpSecond:confidence(second)}));
  return accepted ? {...second,language:first.language} : first;
 } catch(error) { if (signal?.aborted || error.name === 'AbortError') throw error; return first; }
 finally { clearTimeout(timer); diagnose(1,Number(accepted)); }
}
module.exports = { key, near, acc, candidates, termCheck, TERM_GAP };
