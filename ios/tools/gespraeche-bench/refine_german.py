from fetch import ROOT
from pathlib import Path
import subprocess,sys
here=Path(__file__).parent
for audio in sorted((ROOT/'data').glob('T*.flac')):
 hyp=ROOT/f'results/{audio.stem}-cam.json'
 if not hyp.exists() or hyp.with_name(hyp.stem+'-spectral-v2.json').exists():continue
 subprocess.run([sys.executable,str(here/'refine.py'),str(hyp),str(audio),str(ROOT/'models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx')]+(['2'] if audio.name.startswith(('T1','T3')) else []),check=True)
