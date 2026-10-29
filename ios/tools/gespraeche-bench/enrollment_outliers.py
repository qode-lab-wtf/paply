from fetch import ROOT
import json,subprocess,numpy as np,sherpa_onnx as sh
clips=json.loads((ROOT/'data/german-clips.json').read_text());e=sh.SpeakerEmbeddingExtractor(sh.SpeakerEmbeddingExtractorConfig(model=str(ROOT/'models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx'),num_threads=2));vectors={}
for speaker,cs in clips.items():
 vs=[]
 for c in cs[:3]:
  raw=subprocess.check_output(['ffmpeg','-v','error','-i',c['path'],'-ar','16000','-ac','1','-f','f32le','-']);x=np.frombuffer(raw,dtype=np.float32)
  stream=e.create_stream();stream.accept_waveform(16000,x);stream.input_finished();v=np.array(e.compute(stream));vs.append(v/np.linalg.norm(v))
 vectors[speaker]=vs
keys=list(vectors);results=[]
for i,speaker in enumerate(keys):
 outsider=keys[(i+1)%len(keys)];x=np.stack(vectors[speaker][:2]+[vectors[outsider][0]])
 sim=x@x.T;med=np.argmax(np.median(sim,axis=1));keep=sim[med]>=.6
 results.append(dict(speaker=speaker,outsider=outsider,rejected_outlier=not bool(keep[2]),rejected_correct=int((~keep[:2]).sum()),medoid_is_outlier=bool(med==2)))
(ROOT/'results/enrollment-outliers.json').write_text(json.dumps(results,indent=2));print('rejected impostor',sum(r['rejected_outlier'] for r in results),'/',len(results),'rejected correct',sum(r['rejected_correct'] for r in results))
