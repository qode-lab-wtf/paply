from fetch import ROOT
from bench import words,score
import json,soundfile as sf
for p in sorted((ROOT/'results').glob('*.json')):
 if not p.name.startswith(('ES2004','IS1009')) or 'metrics' in p.name:continue
 r=json.loads(p.read_text())
 if 'segments' not in r:continue
 meeting=p.name.split('-')[0];ws=words(meeting);duration=sf.info(ROOT/f'data/{meeting}.wav').duration
 for smooth in [False,True]:
  m=score(ws,r['segments'],duration,smooth);m.update(meeting=meeting,engine=p.stem,smooth=smooth,seconds=r['seconds'],rtf=r['seconds']/duration,duration=duration,peak_rss_bytes=r.get('peak_rss_bytes'))
  dest=p.with_name(p.stem+f'-smooth{smooth}-metrics.json');dest.write_text(json.dumps(m,indent=2))
 print(p.stem,flush=True)
