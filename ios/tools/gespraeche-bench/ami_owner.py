"""Cross-session AMI enrollment pilot: clean non-overlapping words from a, test b + absent IS."""
from bench import words
from fetch import ROOT
import sys,json,numpy as np,soundfile as sf,sherpa_onnx as sh
from collections import defaultdict,Counter
extractor=sh.SpeakerEmbeddingExtractor(sh.SpeakerEmbeddingExtractorConfig(model=str(ROOT/('models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx' if '--cam' in sys.argv else 'models/wespeaker_en_voxceleb_resnet34_LM.onnx')),num_threads=2))
def emb(x):
 s=extractor.create_stream();s.accept_waveform(16000,x);s.input_finished()
 v=np.asarray(extractor.compute(s));return v/np.linalg.norm(v)
x,sr=sf.read(ROOT/'data/ES2004a.wav',dtype='float32');ws=words('ES2004a');profiles={}
for speaker in sorted({w['speaker'] for w in ws}):
 pieces=[]
 for w in ws:
  if w['speaker']!=speaker:continue
  if any(v['speaker']!=speaker and v['start']<w['end'] and v['end']>w['start'] for v in ws):continue
  pieces.append(x[int(w['start']*sr):int(w['end']*sr)])
 clean=np.concatenate(pieces);vs=[emb(clean[i*160000:(i+1)*160000]) for i in range(3)];v=np.mean(vs,axis=0);profiles[speaker]=v/np.linalg.norm(v)
rows=[]
for meeting in ['ES2004b','IS1009a']:
 x,sr=sf.read(ROOT/f'data/{meeting}.wav',dtype='float32');truth=words(meeting)
 r=json.loads((ROOT/f'results/{meeting}-fluid.json').read_text());groups=defaultdict(list)
 for s in r['segments']:groups[s['speaker']].append(s)
 centroids={};identities={}
 for k,segs in groups.items():
  vs=[emb(x[int(s['start']*sr):int(min(s['end'],s['start']+10)*sr)]) for s in sorted(segs,key=lambda s:s['end']-s['start'],reverse=True)[:5] if s['end']-s['start']>2]
  if not vs:continue
  v=np.mean(vs,axis=0);centroids[k]=v/np.linalg.norm(v);votes=Counter()
  for s in segs:
   for w in truth:votes[w['speaker']]+=max(0,min(s['end'],w['end'])-max(s['start'],w['start']))
  identities[k]=votes.most_common(1)[0][0]
 for owner,p in profiles.items():
  scores=sorted([(float(p@v),k) for k,v in centroids.items()],reverse=True);value,k=scores[0];margin=value-scores[1][0]
  for threshold in [.5,.6,.7,.8,.9]:
   accepted=value>=threshold and margin>=.1;correct=meeting=='ES2004b' and identities[k]==owner
   rows.append(dict(meeting=meeting,owner=owner,present=meeting=='ES2004b',threshold=threshold,score=value,margin=margin,accepted=accepted,correct=accepted and correct,false_owner=accepted and not correct))
(ROOT/('results/ami-owner-cam.json' if '--cam' in sys.argv else 'results/ami-owner.json')).write_text(json.dumps(rows,indent=2));print('AMI owner trials',len(rows))
