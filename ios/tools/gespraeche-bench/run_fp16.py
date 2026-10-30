import subprocess,sys
from fetch import ROOT
from pathlib import Path
HERE=Path(__file__).parent
short='--short-turns' in sys.argv
engine='nemotron-short' if short else 'nemotron-fp16'
for audio in list((ROOT/'data').glob('ES*.wav'))+list((ROOT/'data').glob('IS*.wav'))+sorted((ROOT/'data').glob('T*.flac')):
 out=ROOT/f'results/{audio.stem}-{engine}.json'
 if not out.exists():subprocess.run([str(ROOT/'swift-build/release/FluidBench'),str(audio),str(out),str(ROOT/'models/fluid'),'nemotron','fast128']+(['all','--stream','--short-turns'] if short else []),check=True)
 if audio.suffix=='.wav':subprocess.run([sys.executable,str(HERE/'bench.py'),audio.stem,'--hyp',str(out)],check=True)
