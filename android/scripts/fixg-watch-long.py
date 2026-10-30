#!/usr/bin/env python3
"""Observe the real ten-minute recording on paply only; no API calls or credentials."""
import json, subprocess, time
from pathlib import Path
adb = ['adb', '-s', 'emulator-5580']
out = Path.home() / 'Android/work/fixg/.local/evidence'
out.mkdir(parents=True, exist_ok=True)
def shell(*args): return subprocess.check_output(adb + ['shell', *args], timeout=25)
paths = shell('run-as', 'com.paply.android', 'find', 'files/thoughts/thoughts', '-name', 'thought.json').decode().splitlines()
active = [(path, json.loads(shell('run-as', 'com.paply.android', 'cat', path))) for path in paths]
active = [(path, t) for path, t in active if t['state'] == 'recording']
assert len(active) == 1
path, thought = active[0]
started = thought['createdAt'] / 1000
for age in [30, 120, 240, 360, 480, 542, 580, 605]:
    while time.time() - started < age:
        time.sleep(min(5, age - (time.time() - started)))
    if age == 542:
        shell('cmd', 'statusbar', 'expand-notifications')
        time.sleep(1)
    (out / f'long-{age}-memory.txt').write_bytes(shell('dumpsys', 'meminfo', 'com.paply.android'))
    if age in [30, 542, 605]:
        (out / f'long-{age}.png').write_bytes(subprocess.check_output(adb + ['exec-out', 'screencap', '-p'], timeout=25))
        (out / f'long-{age}-notification.txt').write_bytes(shell('dumpsys', 'notification', '--noredact'))
    if age == 580:
        wav = str(Path(path).with_name('audio.wav'))
        # The live header is unfinished; retain this independent PCM evidence without changing app data.
        data = subprocess.check_output(adb + ['exec-out', 'run-as', 'com.paply.android', 'cat', wav], timeout=25)
        (out / 'long-live-580.wav').write_bytes(data)
        assert len(data) > 18_000_000
    print(f'Observed {age}s; {time.time() - started:.1f}s wall clock', flush=True)
(out / 'long-final-logcat.txt').write_bytes(shell('logcat', '-d', '-s', 'Paply:D', 'AndroidRuntime:E'))
(out / 'long-final-audio.txt').write_bytes(shell('dumpsys', 'audio'))
(out / 'long-final-service.txt').write_bytes(shell('dumpsys', 'activity', 'services', 'com.paply.android/.ThoughtService'))
