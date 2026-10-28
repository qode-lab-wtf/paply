#!/usr/bin/env python3
"""MacBook emulator evidence for the unmodified 9/10 minute capture thresholds.

Start a thought first. This script only observes and opens the notification shade.
Run with ~/Android/env.sh sourced; no key or transcript is read.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--serial', default='emulator-5580')
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
adb = ['adb', '-s', a.serial]

def shell(*args):
    return subprocess.check_output(adb + ['shell', *args])

paths = shell('run-as', 'com.paply.android', 'find', 'files/thoughts', '-name', 'thought.json').decode().splitlines()
active = []
for path in paths:
    meta = json.loads(shell('run-as', 'com.paply.android', 'cat', path))
    if meta['state'] == 'recording':
        active.append(meta)
assert len(active) == 1, 'Exactly one recording must already be running'
started = active[0]['createdAt'] / 1000
for age, label in [(125, 'two-minutes'), (245, 'four-minutes'), (542, 'one-minute-left'), (605, 'ten-minute-stop')]:
    while time.time() - started < age:
        time.sleep(max(0, min(10, age - (time.time() - started))))
    if age == 542:
        shell('cmd', 'statusbar', 'expand-notifications')
        time.sleep(1)
    (a.out / f'svc-{label}.png').write_bytes(subprocess.check_output(adb + ['exec-out', 'screencap', '-p']))
    (a.out / f'svc-{label}-vibrator.txt').write_bytes(shell('dumpsys', 'vibrator_manager'))
    (a.out / f'svc-{label}-notification.txt').write_bytes(shell('dumpsys', 'notification', '--noredact'))
    print(f'Captured {label} at {time.time() - started:.1f}s', flush=True)
(a.out / 'svc-timing-logcat.txt').write_bytes(shell('logcat', '-d', '-s', 'Paply:D', 'AndroidRuntime:E'))
(a.out / 'svc-timing-service.txt').write_bytes(shell('dumpsys', 'activity', 'services', 'com.paply.android/.ThoughtService'))
