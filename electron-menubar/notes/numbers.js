'use strict';
// Gedanken: Werte statt Schreibweise; Port der mobilen SpokenNumbers-Prüfung.
const map = (list, start=0) => Object.fromEntries(list.split(' ').map((w,i)=>[w,i+start]));
const units=map('eins zwei drei vier fünf sechs sieben acht neun',1), teens=map('zehn elf zwölf dreizehn vierzehn fünfzehn sechzehn siebzehn achtzehn neunzehn',10);
const tens=Object.fromEntries('zwanzig dreißig vierzig fünfzig sechzig siebzig achtzig neunzig'.split(' ').map((w,i)=>[w,(i+2)*10]));
const english={...map('zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'),...map('_ first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth')};
for(const [i,w] of 'twenty thirty forty fifty sixty seventy eighty ninety'.split(' ').entries()) { english[w]=(i+2)*10;english[w.slice(0,-1)+'ieth']=(i+2)*10; }
const articles=new Set('ein eine einen einem einer eines a an'.split(' '));
const months={...map('januar februar märz april mai juni juli august september oktober november dezember',1),...map('january february march april may june july august september october november december',1),jänner:1};
const enumerators=map('erstens zweitens drittens viertens fünftens sechstens siebtens achtens neuntens zehntens',1);
function cardinal(w) {
 for(const [term,factor] of [['tausend',1000],['hundert',100]]) if(w.includes(term)) {const [a,b,...rest]=w.split(term);if(rest.length)return null;const high=!a||a==='ein'?1:cardinal(a),low=!b?0:cardinal(b.replace(/^und/,''));return high!==null&&low!==null?high*factor+low:null;}
 if(units[w]!==undefined||teens[w]!==undefined||tens[w]!==undefined)return units[w]??teens[w]??tens[w];
 const [a,b]=w.split('und');return (a==='ein'||units[a])&&tens[b]?(a==='ein'?1:units[a])+tens[b]:null;
}
function german(w) {
 let v=cardinal(w);if(v!==null)return v;
 if(w.endsWith('mal'))return cardinal(w.slice(0,-3));
 for(const [stem,value] of Object.entries({erst:1,dritt:3,siebt:7,acht:8}))if(['e','en','er','es','em'].some(e=>w===stem+e))return value;
 for(const end of ['sten','ster','stes','stem','ste','ten','ter','tes','tem','te'])if(w.endsWith(end)){v=cardinal(w.slice(0,-end.length));if(v>1)return v;}
 return null;
}
const words=s=>s.toLowerCase().match(/\d+(?:[. ’'\u202f\u00a0]\d{3}(?!\d))*|[\p{L}\p{M}]+/gu)||[];
function tokens(s) {
 const ws=words(s),out=[];
 for(let i=0;i<ws.length;i++) {const w=ws[i];if(/^\d/.test(w)){out.push({value:Number(w.replace(/\D/g,'')),kind:'digits',word:i});continue;}
 let k=i,total=0,current=0,last='none';
 while(k<ws.length){const x=ws[k],v=english[x];if(v!==undefined){if(last==='none')current=v;else if(last==='tens'&&v>0&&v<10||['hundred','thousand'].includes(last))current+=v;else break;last=v>=20&&v%10===0?'tens':'unit';}
 else if(x==='hundred'&&['none','unit','tens'].includes(last)){current=Math.max(1,current)*100;last='hundred';}
 else if(x==='thousand'&&last!=='thousand'){total+=Math.max(1,current)*1000;current=0;last='thousand';}
 else if(x==='and'&&['hundred','thousand'].includes(last)&&english[ws[k+1]]!==undefined){k++;continue;}else break;k++;}
 if(k>i){out.push({value:total+current,kind:k===i+1&&['one','first','second'].includes(w)?'optional':'word',word:i});i=k-1;continue;}
 const optional=articles.has(w)||months[w]!==undefined||enumerators[w]!==undefined||/^erst/.test(w);
 const value=articles.has(w)?1:months[w]??enumerators[w]??german(w);if(value!==null&&value!==undefined)out.push({value,kind:optional?'optional':'word',word:i});
 }
 return out;
}
function preserved(raw,result) {
 const source=tokens(raw),dest=tokens(result),ws=words(raw),corrected=new Set();
 for(let i=0;i<ws.length;i++) {
 let end=null;
 if(['nee','nein','ne','nö','no','nope','non'].includes(ws[i])) {if(['warte','moment','quatsch','falsch','sorry','stopp','wait','scratch'].includes(ws[i+1]))end=i+2;else if(source.some(t=>t.word===i+1&&t.kind!=='optional'))end=i+1;}
 else for(const m of [['ich','meine'],['ich','mein'],['i','mean'],['scratch','that'],['korrektur']])if(m.every((w,k)=>ws[i+k]===w))end=i+m.length;
 if(end!==null&&source.some(t=>t.word>=end&&t.word<=end+3&&t.kind!=='optional')) {const previous=source.filter(t=>t.word<i&&t.word>=i-6&&t.kind!=='optional').at(-1);if(previous)corrected.add(previous.word);}
 }
 return source.every(t=>t.kind==='optional'||corrected.has(t.word)||dest.some(d=>d.value===t.value))&&dest.every(t=>t.kind!=='digits'||source.some(s=>s.value===t.value));
}
const digitsContained=(text,source)=>tokens(text).every(t=>t.kind!=='digits'||tokens(source).some(s=>s.value===t.value));
const isNumberWord=w=>english[w]!==undefined||['hundred','thousand'].includes(w)||enumerators[w]!==undefined||!articles.has(w)&&months[w]===undefined&&german(w)!==null;
module.exports={preserved,digitsContained,isNumberWord};
