import subprocess,sys
from fetch import ROOT
from pathlib import Path
HERE=Path(__file__).parent
for meeting in ['ES2004a','ES2004b','IS1009a']:
 for engine in ['fluid','nemotron']:
  dest=ROOT/f'results/{meeting}-{engine}.json'
  if not dest.exists():
   subprocess.run([str(ROOT/'swift-build/release/FluidBench'),str(ROOT/f'data/{meeting}.wav'),str(dest),str(ROOT/'models/fluid')]+(['nemotron'] if engine=='nemotron' else []),check=True)
  subprocess.run([sys.executable,str(HERE/'bench.py'),meeting,'--hyp',str(dest)],check=True)
