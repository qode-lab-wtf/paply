"""Explicit one-file invocation, durable reservation before sending. Never logs credentials."""
from pathlib import Path
import json,hashlib,sys,fcntl
import requests,soundfile as sf
from fetch import ROOT
p=Path(sys.argv[1]);info=sf.info(p)
assert p.suffix=='.flac' and p.stat().st_size<=25_000_000 and info.samplerate==16000 and info.channels==1
sha=hashlib.sha256(p.read_bytes()).hexdigest();dest=ROOT/f'results/groq-{sha}.json'
if dest.exists(): print(dest);sys.exit()
ledger=ROOT/'results/groq-ledger.json'
with (ROOT/'results/groq.lock').open('w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 records=json.loads(ledger.read_text()) if ledger.exists() else {}
 if sha in records: raise SystemExit('Already reserved/sent; refusing duplicate. Inspect ledger manually.')
 assert sum(x['seconds'] for x in records.values())+info.duration<=5400
 # Entire run <= 5400 s, also below the hourly 7200 s budget.
 records[sha]=dict(seconds=info.duration,status='reserved',file=p.name);ledger.write_text(json.dumps(records,indent=2))
 config=Path.home()/'Library/Application Support/paply-menubar/config.json'
 key=json.loads(config.read_text())['groqApiKey']
 with p.open('rb') as f:
  r=requests.post('https://api.groq.com/openai/v1/audio/transcriptions',headers={'Authorization':'Bearer '+key},files={'file':(p.name,f,'audio/flac')},data=[('model','whisper-large-v3'),('response_format','verbose_json'),('timestamp_granularities[]','word'),('timestamp_granularities[]','segment'),('language','de')],timeout=240)
 del key
 if r.status_code==429:
  records[sha]['status']='429';records[sha]['retry_after']=r.headers.get('Retry-After');ledger.write_text(json.dumps(records,indent=2));raise SystemExit('429: stop batch; no immediate retry; reservation retained')
 if r.status_code!=200:
  records[sha]['status']=str(r.status_code);ledger.write_text(json.dumps(records,indent=2));raise SystemExit('Groq HTTP '+str(r.status_code))
 dest.write_text(json.dumps(r.json()));records[sha]['status']='complete';ledger.write_text(json.dumps(records,indent=2))
 print(dest)
