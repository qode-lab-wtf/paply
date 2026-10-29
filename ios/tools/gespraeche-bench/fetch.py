"""Bounded, resumable benchmark downloads. No global caches."""
from pathlib import Path
import requests, shutil, hashlib, json
ROOT=Path.home()/'paply-gsp-bench'
def fetch(url, relative):
    dst=ROOT/relative
    dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists(): return dst
    used=sum(p.stat().st_size for p in ROOT.rglob('*') if p.is_file())
    with requests.get(url,stream=True,timeout=90) as r:
        r.raise_for_status()
        size=int(r.headers.get('Content-Length',0))
        assert used+size<4_000_000_000 and shutil.disk_usage(ROOT).free>size+2_000_000_000
        part=dst.with_suffix(dst.suffix+'.part')
        count=0
        with part.open('wb') as f:
            for chunk in r.iter_content(1024*1024):
                count+=len(chunk)
                if used+count>=4_000_000_000: raise RuntimeError('4 GB budget')
                f.write(chunk)
        part.rename(dst)
    print(relative, dst.stat().st_size, flush=True)
    return dst
if __name__=='__main__':
    base='https://github.com/k2-fsa/sherpa-onnx/releases/download/'
    fetch(base+'speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2','models/segmentation.tar.bz2')
    for name in ['3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx','wespeaker_en_voxceleb_resnet34_LM.onnx']:
        fetch(base+'speaker-recongition-models/'+name,'models/'+name)
    fetch('https://groups.inf.ed.ac.uk/ami/AMICorpusAnnotations/ami_public_manual_1.6.2.zip','data/annotations.zip')
    for meeting in ['ES2004a','ES2004b','IS1009a']:
        fetch(f'https://groups.inf.ed.ac.uk/ami/AMICorpusMirror/amicorpus/{meeting}/audio/{meeting}.Array1-01.wav',f'data/{meeting}.wav')
