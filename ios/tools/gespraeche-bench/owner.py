"""Held-out clip enrollment, open-set decisions; exploratory thresholds, not calibration."""
import json,subprocess,time,sys
from collections import defaultdict,Counter
import numpy as np,soundfile as sf,sherpa_onnx as sh
from fetch import ROOT
from pathlib import Path
engine=sys.argv[2] if len(sys.argv)>2 else 'fluid'
model=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'models/wespeaker_en_voxceleb_resnet34_LM.onnx'
e=sh.SpeakerEmbeddingExtractor(sh.SpeakerEmbeddingExtractorConfig(model=str(model),num_threads=2))
def embed(x):
 stream=e.create_stream();stream.accept_waveform(16000,x);stream.input_finished()
 if not e.is_ready(stream):return None
 v=np.array(e.compute(stream));return v/np.linalg.norm(v)
def profile(vs):
 x=np.stack(vs);sim=x@x.T;med=np.argmax(np.median(sim,axis=1));keep=sim[med]>=.6
 v=x[keep].mean(axis=0);return v/np.linalg.norm(v),int((~keep).sum())
clips=json.loads((ROOT/'data/german-clips.json').read_text());profiles={};rejections={}
for s,cs in clips.items():
 vs=[]
 for c in cs[:3]:
  raw=subprocess.check_output(['ffmpeg','-v','error','-i',c['path'],'-ar','16000','-ac','1','-f','f32le','-']);vs.append(embed(np.frombuffer(raw,dtype=np.float32)))
 profiles[s],rejections[s]=profile(vs)
rows=[]
for audio in sorted((ROOT/'data').glob('T*.flac')):
 hyp=ROOT/f'results/{audio.stem}-{engine}.json'
 if not hyp.exists():continue
 x,sr=sf.read(audio,dtype='float32');truth=json.loads((ROOT/f'data/{audio.stem}-truth.json').read_text());groups=defaultdict(list)
 for s in json.loads(hyp.read_text())['segments']:groups[s['speaker']].append(s)
 centroids={};actual={}
 for k,segs in groups.items():
  selected=sorted(segs,key=lambda r:r['end']-r['start'],reverse=True)[:5]
  vs=[embed(x[int(s['start']*sr):int(min(s['end'],s['start']+10)*sr)]) for s in selected if s['end']-s['start']>2]
  vs=[v for v in vs if v is not None]
  if not vs:continue
  v=np.mean(vs,axis=0);centroids[k]=v/np.linalg.norm(v)
  votes=Counter()
  for s in segs:
   for t in truth:votes[t['speaker']]+=max(0,min(s['end'],t['end'])-max(s['start'],t['start']))
  actual[k]=votes.most_common(1)[0][0]
 for owner,p in profiles.items():
  scores=sorted([(float(p@v),k) for k,v in centroids.items()],reverse=True)
  if not scores:continue
  best,k=scores[0];margin=best-(scores[1][0] if len(scores)>1 else -1)
  present=owner in {t['speaker'] for t in truth}
  for threshold in [.5,.6,.7,.8,.9]:
   accept=best>=threshold and margin>=.1
   rows.append(dict(condition=audio.stem,owner=owner,present=present,threshold=threshold,margin_min=.1,score=best,margin=margin,accepted=accept,correct=accept and actual[k]==owner,false_owner=accept and actual[k]!=owner))
(ROOT/(f'results/owner-{engine}-cam.json' if 'campplus' in str(model) else f'results/owner-{engine}.json')).write_text(json.dumps(dict(trials=rows,enrollment_rejections=rejections),indent=2));print('owner trials',len(rows))
