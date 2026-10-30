"""Engine-neutral spectral reclustering of clean turn embeddings. Experimental, untuned."""
import json,sys,time
from pathlib import Path
from collections import defaultdict
import numpy as np,soundfile as sf,sherpa_onnx as sh
from sklearn.cluster import SpectralClustering
from fetch import ROOT
p=Path(sys.argv[1]);audio,sr=sf.read(sys.argv[2],dtype='float32');model=sys.argv[3]
r=json.loads(p.read_text());start=time.perf_counter()
e=sh.SpeakerEmbeddingExtractor(sh.SpeakerEmbeddingExtractorConfig(model=model,num_threads=2))
def embed(x):
 s=e.create_stream();s.accept_waveform(sr,x);s.input_finished()
 if not e.is_ready(s):return None
 v=np.asarray(e.compute(s));return v/max(np.linalg.norm(v),1e-12)
groups=defaultdict(list)
for s in r['segments']:groups[str(s['speaker'])].append(s)
keys=[];vectors=[]
for k,rows in groups.items():
 candidates=sorted(rows,key=lambda x:x['end']-x['start'],reverse=True)[:3]
 vs=[embed(audio[int(s['start']*sr):int(min(s['end'],s['start']+10)*sr)]) for s in candidates if s['end']-s['start']>=1.0]
 vs=[v for v in vs if v is not None]
 if vs:
  v=np.mean(vs,axis=0);vectors.append(v/np.linalg.norm(v));keys.append(k)
if len(keys)<2:
 r['refine']=dict(status='insufficient_embeddings',valid_clusters=len(keys),action='retain_original')
 r['seconds']+=time.perf_counter()-start
 out=p.with_name(p.stem+'-spectral-v2.json');out.write_text(json.dumps(r));print(out);sys.exit(0)
x=np.stack(vectors);sim=x@x.T
# Smooth affinity, eigengap count; no single cosine cut for automatic speaker count.
w=np.exp((sim-1)/.15);np.fill_diagonal(w,0)
d=np.maximum(w.sum(axis=1),1e-12);lap=np.eye(len(w))-w/np.sqrt(d[:,None]*d[None,:]);ev=np.linalg.eigvalsh(lap)
k=int(sys.argv[4]) if len(sys.argv)>4 else int(np.argmax(np.diff(ev)[1:min(8,len(ev)-1)])+2) if len(ev)>2 else 2
labels=np.arange(len(keys)) if k>=len(keys) else SpectralClustering(n_clusters=k,affinity='precomputed',assign_labels='cluster_qr',random_state=0).fit_predict(w) if k>1 else np.zeros(len(w),int)
mapping=dict(zip(keys,map(str,labels)))
# Unembedded tiny clusters abstain, never force genuine short interjections into a neighbour.
r['abstained_seconds']=sum(s['end']-s['start'] for s in r['segments'] if str(s['speaker']) not in mapping)
r['segments']=[dict(s,speaker=mapping[str(s['speaker'])]) for s in r['segments'] if str(s['speaker']) in mapping]
r['seconds']+=time.perf_counter()-start;r['refine']=dict(k=k,eigenvalues=ev.tolist(),temperature=.15)
out=p.with_name(p.stem+'-spectral-v2.json');out.write_text(json.dumps(r));print(out)
