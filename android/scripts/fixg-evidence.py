#!/usr/bin/env python3
"""Read-only paply:5580 evidence; no credentials or transcript content on stdout."""
import argparse, json, subprocess, time
from pathlib import Path
p = argparse.ArgumentParser()
p.add_argument('label')
p.add_argument('--state', default='done')
p.add_argument('--contains', default='')
p.add_argument('--timeout', type=float, default=30)
p.add_argument('--prior-transcriptions', type=int, default=0)
p.add_argument('--prior-ai', type=int, default=0)
a = p.parse_args()
assert a.label.replace('-', '').isalnum()
out = Path.home() / 'Android/work/fixg/.local/evidence'
out.mkdir(parents=True, exist_ok=True)
adb = ['adb', '-s', 'emulator-5580']
def shell(*args):
    return subprocess.check_output(adb + ['shell', *args])
def thoughts():
    paths = shell('run-as', 'com.paply.android', 'find', 'files/thoughts/thoughts', '-name', 'thought.json').decode().splitlines()
    return [(path, json.loads(shell('run-as', 'com.paply.android', 'cat', path))) for path in paths]
deadline = time.monotonic() + a.timeout
while True:
    path, t = max(thoughts(), key=lambda pair: pair[1]['createdAt'])
    if t['state'] == a.state: break
    if time.monotonic() > deadline: raise SystemExit('Latest thought remains ' + t['state'])
    time.sleep(.5)
(out / (a.label + '-thought.json')).write_text(json.dumps(t, ensure_ascii=False, indent=2))
if a.state == 'done':
    source = json.loads(shell('run-as', 'com.paply.android', 'cat', str(Path(path).with_name('source.json'))))
    assert a.contains.lower() in source['text'].lower(), 'Expected content missing'
    (out / (a.label + '-source.json')).write_text(json.dumps(source, ensure_ascii=False, indent=2))
log = shell('logcat', '-d', '-v', 'threadtime', '-s', 'Paply:D', 'AndroidRuntime:E').decode()
(out / (a.label + '-logcat.txt')).write_text(log)
tx = a.prior_transcriptions + sum('thought.groq count=1' in line for line in log.splitlines())
ai = a.prior_ai + sum('thought.groq ms=' in line for line in log.splitlines())
assert tx <= 4 and ai <= 4, 'Groq budget exceeded'
print(json.dumps({'id': t['id'], 'state': t['state'], 'durationMs': t['durationMs'], 'transcriptions': tx, 'ai': ai}))
