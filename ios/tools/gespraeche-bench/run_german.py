import json,hashlib,subprocess,sys
from pathlib import Path
import soundfile as sf
from fetch import ROOT
from bench import sherpa,score
HERE=Path(__file__).parent
for audio in sorted((ROOT/'data').glob('T*.flac')):
 name=audio.stem
 subprocess.run([sys.executable,str(HERE/'groq.py'),str(audio)],check=True)
 response=json.loads((ROOT/f'results/groq-{hashlib.sha256(audio.read_bytes()).hexdigest()}.json').read_text())
 truth=json.loads((ROOT/f'data/{name}-truth.json').read_text())
 ws=[];ambiguous=0
 for w in response['words']:
  if w['end']<=w['start']:continue
  candidates=[s for s in truth if s['start']<w['end'] and s['end']>w['start']]
  if len(candidates)!=1:ambiguous+=1;continue
  s=candidates[0];ws.append(dict(start=w['start'],end=w['end'],text=w['word'],speaker=s['speaker'],sentence=s['sentence']))
 # DER/JER below use ASR word intervals as proxy reference, explicitly not gold DER.
 x,sr=sf.read(audio,dtype='float32');n=2 if name.startswith(('T1','T3')) else -1
 for engine in ['fluid','cam','wespeaker']:
  dest=ROOT/f'results/{name}-{engine}.json'
  if not dest.exists():
   if engine=='fluid':subprocess.run([str(ROOT/'swift-build/release/FluidBench'),str(audio),str(dest),str(ROOT/'models/fluid'),str(n)],check=True)
   else:
    model=ROOT/('models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx' if engine=='cam' else 'models/wespeaker_en_voxceleb_resnet34_LM.onnx')
    dest.write_text(json.dumps(sherpa(x,model,n,.7)))
  r=json.loads(dest.read_text())
  for smooth in [False,True]:
   m=score(ws,r['segments'],len(x)/sr,smooth);m.update(condition=name,engine=engine,smooth=smooth,ambiguous_words_excluded=ambiguous,asr_words=len(response['words']),rtf=r['seconds']/(len(x)/sr),seconds=r['seconds'],reference='ASR-word time proxy; speaker from source clip; no lexical alignment')
   (ROOT/f'results/{name}-{engine}-smooth{smooth}-metrics.json').write_text(json.dumps(m,indent=2));print(json.dumps(m),flush=True)
