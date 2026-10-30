from bench import words,assign
from fetch import ROOT
from collections import Counter
from scipy.optimize import linear_sum_assignment
import json,numpy as np
rows=[]
for meeting in ['ES2004a','ES2004b','IS1009a']:
 ws=words(meeting);counts=Counter(w['sentence'] for w in ws)
 for engine in ['fluid','nemotron-fp16','nemotron-short']:
  r=json.loads((ROOT/f'results/{meeting}-{engine}.json').read_text())
  for smooth in [False,True]:
   labels=assign(ws,r['segments'],smooth);truth=sorted(set(w['speaker'] for w in ws));clusters=sorted(set(labels)-{'?'});mat=np.zeros((len(clusters),len(truth)),int)
   for w,l in zip(ws,labels):
    if l!='?':mat[clusters.index(l),truth.index(w['speaker'])]+=1
   ii,jj=linear_sum_assignment(-mat);mapping={clusters[i]:truth[j] for i,j in zip(ii,jj)}
   for subset in ['short','backchannel']:
    chosen=[i for i,w in enumerate(ws) if (counts[w['sentence']]<=2 if subset=='short' else w['text'].lower().strip('.,?!') in {'yeah','yes','right','okay','ok','mhm','mm','uh-huh','mm-hmm'})]
    rows.append(dict(meeting=meeting,engine=engine,smooth=smooth,subset=subset,words=len(chosen),errors=sum(mapping.get(labels[i])!=ws[i]['speaker'] for i in chosen)))
(ROOT/'results/short-turns.json').write_text(json.dumps(rows,indent=2))
print('short-turn scoring complete')
