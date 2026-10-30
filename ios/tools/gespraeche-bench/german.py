"""MLS German (CC BY 4.0), deterministic semi-synthetic pilot; source IDs retained."""
import json,io,subprocess
from collections import defaultdict
import requests,numpy as np,soundfile as sf
from scipy.signal import butter,sosfilt,fftconvolve
from fetch import ROOT,fetch
rng=np.random.default_rng(20261029)
manifest=ROOT/'data/german-clips.json'
if not manifest.exists():
    import pyarrow.parquet as pq
    path=fetch('https://huggingface.co/datasets/facebook/multilingual_librispeech/resolve/refs%2Fconvert%2Fparquet/german/test/0000.parquet','data/mls.parquet')
    clips=defaultdict(list)
    for batch in pq.ParquetFile(path).iter_batches(batch_size=100):
        for row in batch.to_pylist():
            sp=row['speaker_id']
            if len(clips[sp])>=25: continue
            out=ROOT/f'data/mls/{row["id"]}.opus';out.parent.mkdir(exist_ok=True)
            out.write_bytes(row['audio']['bytes'])
            clips[sp].append(dict(path=str(out),text=row['transcript'],id=row['id']))
    manifest.write_text(json.dumps(clips))
clips=json.loads(manifest.read_text());speakers=[s for s in clips if len(clips[s])>=10];assert len(speakers)>=5
loaded={}
for s in speakers:
    loaded[s]=[]
    for c in clips[s]:
        raw=subprocess.check_output(['ffmpeg','-v','error','-i',c['path'],'-ar','16000','-ac','1','-f','f32le','-'])
        x=np.frombuffer(raw,dtype=np.float32).copy();x=x/(np.sqrt(np.mean(x*x))+1e-6)*.08
        loaded[s].append((x,c))
for condition,n in [('T1',2),('T2-3',3),('T2-4',4),('T2-5',5),('T3',2)]:
 for trial in range(2):
    chosen=speakers[trial:trial+n] if len(speakers)>=trial+n else speakers[:n]
    name=f'{condition}-{trial}';duration=300;mix=np.zeros(16000*duration,dtype=np.float32);segments=[];t=.5;turn=0
    while t<duration-16:
        s=chosen[turn%n];x,c=loaded[s][3+(turn//n)%(len(loaded[s])-3)];x=x.copy()
        if condition=='T1' and s==chosen[1]:
            x=sosfilt(butter(4,[300,3400],fs=16000,btype='bandpass',output='sos'),x);x=np.tanh(x*3)/3
            # 8-bit mu-law quantization approximates narrowband companding, not a GSM codec.
            x=np.sign(x)*np.log1p(255*np.abs(x))/np.log(256);x=np.round(x*127)/127;x=np.sign(x)*np.expm1(abs(x)*np.log(256))/255
        rt=.35 if condition.startswith('T2') else .12
        ir=np.zeros(int(rt*16000));ir[0]=1
        for delay,gain in [(0.021,.4),(.047,.22),(.091,.13)]:
            ir[int(delay*16000)]=gain
        x=fftconvolve(x,ir)[:len(x)].astype(np.float32)
        a=int(t*16000);b=min(a+len(x),len(mix));mix[a:b]+=x[:b-a]
        segments.append(dict(start=a/16000,end=b/16000,speaker=s,text=c['text'],sentence=f'{name}-{turn}',source=c['id']))
        t=b/16000+float(rng.uniform(-.25,.65));turn+=1
    mix+=rng.normal(0,.0015,len(mix));mix=np.clip(mix,-.99,.99)
    sf.write(ROOT/f'data/{name}.flac',mix,16000)
    (ROOT/f'data/{name}-truth.json').write_text(json.dumps(segments))
# First three source clips are reserved for enrollment, never mixed.
print('Generated ten 5-minute pilots; repeated source clips: NOT independent conversations.',flush=True)
