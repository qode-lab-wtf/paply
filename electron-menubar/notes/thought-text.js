'use strict';
const { negationCount } = require('./safety');
const fold = s => s.toLowerCase().normalize('NFD').replace(/\p{M}/gu, '');
const tokens = s => [...s.matchAll(/[\p{L}\p{N}]+/gu)].map(m => ({ word: fold(m[0]), start: m.index, end: m.index + m[0].length }));
const normalized = s => tokens(s).map(t => t.word).join(' ');
const plainHyphens = s => s.replace(/[‐‑]|\\u201[01]/g, '-');
function matches(word, forms) {
  return forms.some(f => { if (word === f) return true;
    if (/[\p{Script=Han}\p{Script=Thai}\p{Script=Hiragana}\p{Script=Katakana}]/u.test(word)) return [...word].some((_, i, a) => i && f.includes(a[i-1]+a[i]));
    let i=0; while(i < Math.min(word.length,f.length) && word[i]===f[i]) i++;
    return i >= 4 && i >= Math.min(word.length,f.length)-3;
  });
}
const fillers = new Set(['äh','ähm','öhm','ähem','hm','hmm','mhm','uh','uhm','uhmm','um','umm','er','erm','eh','ehm','ehh','eeh','euh','euhm','eee','eem','yyy','ııı','hum','mmm']);
function fallbackTitle(text) {
  const w=text.replace(/• /g,' ').trim().split(/\s+/).filter(w=>!fillers.has(w.toLowerCase().replace(/\p{P}/gu,'')));
  const head = w.slice(0,6).join(' ').replace(/[,;:.]+$/,'');
  return w.length ? [...head].slice(0,58).join('') + (w.length>6 || [...head].length>58 ? ' …' : '') : '…';
}
function locateQuote(quote, raw) {
  const q=tokens(quote).map(t=>t.word), t=tokens(raw), w=t.map(t=>t.word);
  if(!q.length) return null;
  const span=(a,b)=>raw.slice(t[a].start,t[b-1].end);
  const find=(piece,start)=>{for(let i=start;i<=w.length-piece.length;i++) if(piece.every((v,j)=>v===w[i+j])) return i;return -1;};
  const exact=find(q,0); if(exact>=0) return span(exact,exact+q.length);
  let best=null;
  for(let len=Math.max(1,q.length-2);len<=q.length+2 && len<=w.length;len++) for(let start=0;start<=w.length-len;start++) {
    let prev=Array(q.length+1).fill(0);
    for(const v of w.slice(start,start+len)) {const row=[0];for(let j=0;j<q.length;j++) row.push(v===q[j]?prev[j]+1:Math.max(prev[j+1],row[j]));prev=row;}
    const score=prev[q.length]/Math.max(len,q.length);if(score>=.9 && (!best || score>best.score)) best={score,start,len};
  }
  if(best) return span(best.start,best.start+best.len);
  const pieces=quote.replace(/\.\.\./g,'…').split('…').map(p=>tokens(p).map(t=>t.word)).filter(p=>p.length);
  if(pieces.length<2) return null;
  for(let start=find(pieces[0],0);start>=0;start=find(pieces[0],start+1)) {let end=start+pieces[0].length;for(const p of pieces.slice(1)){const i=find(p,end);if(i<0){end=-1;break;}end=i+p.length;}if(end>start && end-start<=30) return span(start,end);}
  return null;
}
const reminders = ["nicht vergessen","vergiss nicht","vergessen sie nicht","nicht zu vergessen","vergesst nicht","don't forget","do not forget","dont forget","n'oublie pas","n'oubliez pas","no olvides","no olvidar","non dimenticare","não esquecer","não esqueças","niet vergeten","vergeet niet","nie zapomnij","unutma","unutmayın"];
function effectiveNegations(s) {s=s.toLowerCase().replace(/’/g,"'"); for(const phrase of reminders) s=s.split(phrase).join('');return negationCount(s);}
const nameKey=s=>s.toLowerCase().replace(/ä/g,'ae').replace(/ö/g,'oe').replace(/ü/g,'ue').replace(/[^\p{L}\p{N}]/gu,'');
function bases(s) {const b=[s];if(s.endsWith('es')&&s.length-2>=4)b.push(s.slice(0,-2));if(s.endsWith('en')&&s.length-2>=5)b.push(s.slice(0,-2));if(s.endsWith('e')&&s.length-1>=5)b.push(s.slice(0,-1));if(s.endsWith('s')&&s.length-1>=4)b.push(s.slice(0,-1));if(/(?:e|el|er)n$/.test(s)&&s.length-1>=4)b.push(s.slice(0,-1));return b;}
function rank(a,b){const x=nameKey(a),y=nameKey(b);if(x===y&&x)return 0;
 const aw=a.toLowerCase().match(/[\p{L}\p{N}]+/gu)||[],bw=b.toLowerCase().match(/[\p{L}\p{N}]+/gu)||[];
 if(aw.length===bw.length&&aw.every((w,i)=>bases(w).map(nameKey).includes(nameKey(bw[i]))||bases(bw[i]).map(nameKey).includes(nameKey(w))))return 1;
 const tx=a.toLowerCase().replace(/[^\p{L}\p{N}]/gu,''),ty=b.toLowerCase().replace(/[^\p{L}\p{N}]/gu,'');if(Math.min(tx.length,ty.length)<8)return null;
 if(tx.length===ty.length){const d=[...tx].map((c,i)=>c===ty[i]?-1:i).filter(i=>i>=0);if(d.length===2&&d[1]===d[0]+1&&tx[d[0]]===ty[d[1]]&&tx[d[1]]===ty[d[0]]&&/\p{L}/u.test(tx[d[0]])&&/\p{L}/u.test(tx[d[1]]))return 2;}
 const [l,s]=tx.length>ty.length?[tx,ty]:[ty,tx];if(l.length===s.length+1&&!l.startsWith(s)&&!l.endsWith(s)){let i=0;while(l[i]===s[i])i++;if(l.slice(i+1)===s.slice(i)&&/\p{L}/u.test(l[i])&&!(l[i]==='e'&&'aou'.includes(l[i-1])))return 2;}return null;
}
function sameNamed(name,topics){let best=Infinity,result=[];for(const t of topics){const r=rank(name,t.title);if(r===null||r>best)continue;if(r<best){best=r;result=[];}result.push(t);}return result;}
const extraNegations = new Set(["ohne", "without", "no", "nein", "nee", "non", "nope", "dont", "doesnt", "didnt", "cant", "wont", "isnt", "arent", "wasnt", "shouldnt", "mustnt", "neednt", "havent", "hasnt"].map(normalized));
const blockedNeighbors = new Set(["und", "oder", "bzw", "aber", "sondern", "statt", "anstatt", "erst", "nur", "bis", "ab", "seit", "f\u00fcr", "wegen", "am", "an", "zum", "zur", "vor", "nach", "and", "or", "but", "instead", "until", "by", "for", "before", "after", "beziehungsweise", "sowie", "als", "au\u00dfer", "sonst", "anstelle", "zwischen", "von", "vom", "sp\u00e4testens", "fr\u00fchestens", "schon", "bereits", "wenn", "falls", "sobald", "bevor", "nachdem", "ob", "dass", "than", "rather", "except", "nor", "only", "already", "if", "when", "once", "unless", "between", "from", "since", "till", "til", "latest", "earliest", "heute", "morgen", "\u00fcbermorgen", "gestern", "fr\u00fch", "morgens", "vormittag", "vormittags", "mittag", "mittags", "nachmittag", "nachmittags", "abend", "abends", "nacht", "nachts", "uhr", "um", "halb", "viertel", "woche", "wochenende", "monat", "jahr", "today", "tomorrow", "tonight", "morning", "afternoon", "evening", "night", "noon", "midnight", "week", "weekend", "month", "year", "pm", "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag", "sonnabend", "sonntag", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].map(normalized));
const prepositions = new Set(["wegen", "f\u00fcr", "\u00fcber", "von", "vom", "vor", "nach", "bis", "ab", "an", "am", "ans", "auf", "zu", "zum", "zur", "seit", "ohne", "mit", "um", "in", "im", "ins", "bei", "beim", "gegen", "aus", "unter", "zwischen", "w\u00e4hrend", "innerhalb", "binnen", "bez\u00fcglich", "for", "about", "of", "to", "at", "on", "by", "until", "before", "after", "from", "since", "with", "into", "regarding", "during", "within", "between"].map(normalized));
const governingDeterminers = new Set(["der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "eines", "n\u00e4chste", "n\u00e4chsten", "n\u00e4chster", "n\u00e4chstes", "\u00fcbern\u00e4chste", "\u00fcbern\u00e4chsten", "kommende", "kommenden", "kommender", "kommendes", "diese", "diesen", "dieser", "dieses", "diesem", "jede", "jeden", "jeder", "jedes", "jedem", "letzte", "letzten", "letzter", "letztes", "vorige", "vorigen", "the", "a", "an", "next", "this", "every", "each", "last", "coming", "following"].map(normalized));
const spanWords = new Set(["bis", "ab", "seit", "von", "vom", "w\u00e4hrend", "\u00fcber", "until", "till", "til", "from", "since", "through", "thru", "during", "throughout"].map(normalized));
const deadlineWords = new Set(["sp\u00e4testens"].map(normalized));
const edgeFillers = new Set(["noch", "mal", "eben"].map(normalized));
const definiteArticles = new Set(["der", "die", "das", "den", "dem", "des"].map(normalized));
function tidyTask(raw,hint) {
 let w=raw.trim().split(/\s+/); const key=normalized;
 const neg=s=>negationCount(s)>0||tokens(s).some(t=>extraNegations.has(t.word));
 const blocked=s=>blockedNeighbors.has(key(s))||/\d/.test(s)||require('./numbers').isNumberWord(key(s));
 if(hint&&!neg(raw)&&!neg(hint)&&(!tokens(hint).some(t=>spanWords.has(t.word))||tokens(hint).some(t=>deadlineWords.has(t.word)))){
  for(let k=1;k<w.length;k++){
   if(key(w.slice(0,k).join(' '))===key(hint)){const rest=w.slice(k);if(rest.length>=2&&!blocked(rest[0]))w=rest;break;}
   if(key(w.slice(-k).join(' '))===key(hint)){const rest=w.slice(0,-k);if(rest.length>=2&&!blocked(rest.at(-1))&&!governingDeterminers.has(key(rest.at(-1)))&&!rest.some(v=>prepositions.has(key(v))))w=rest;break;}
  }
 }
 const bare=s=>s.replace(/^[\p{P}\p{S}]+|[\p{P}\p{S}]+$/gu,'');
 if(w.length>=2&&edgeFillers.has(key(w[0]))&&(/^[\p{Lu}]/u.test(bare(w[1]))||definiteArticles.has(key(w[1])))&&!neg(w.slice(1).join(' ').split(/[,;:–—]/)[0]))w.shift();
 if(w.length>=2&&edgeFillers.has(key(w.at(-1)))&&/^[\p{Ll}]{2,}(en|rn|ln)$/u.test(bare(w.at(-2)))&&!neg(w.slice(0,-1).join(' ').split(/[,;:–—]/).at(-1)))w.pop();
 let text=w.join(' ').replace(/^[,;:–—\- ]+|[,;:–—\- ]+$/g,'');
 return text.replace(/[\p{L}\p{N}]+/u,word=>/[\p{Lu}]/u.test(word.slice(1))?word:word[0].toUpperCase()+word.slice(1));
}
module.exports={plainHyphens,matches,locateQuote,fallbackTitle,sameNamed,tidyTask,effectiveNegations};
