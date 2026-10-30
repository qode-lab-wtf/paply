#!/usr/bin/env python3
"""Reconstruct the E2 long-pause case from its retained injection WAVs, never claim original capture.
No network. Output is PCM16/16kHz mono plus a provenance JSON with source hashes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import wave

p = argparse.ArgumentParser()
p.add_argument('--first', type=Path, required=True)
p.add_argument('--last', type=Path, required=True)
p.add_argument('--seconds', type=float, default=286.488)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()

def read(path):
    with wave.open(str(path), 'rb') as audio:
        assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (1, 2, 16000)
        return audio.readframes(audio.getnframes())

first, last = read(a.first), read(a.last)
frames = round(a.seconds * 16000)
pause = frames - (len(first) + len(last)) // 2
assert pause >= 2 * 16000
pcm = first + bytes(pause * 2) + last
a.output.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(a.output), 'wb') as audio:
    audio.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
    audio.writeframes(pcm)
manifest = {
    'kind': 'reconstruction-not-original-capture',
    'reference': 'svc-timed-call-source.json',
    'audioSeconds': frames / 16000,
    'silenceSeconds': pause / 16000,
    'sources': [{'name': f.name, 'sha256': hashlib.sha256(f.read_bytes()).hexdigest()} for f in [a.first, a.last]],
    'sha256': hashlib.sha256(a.output.read_bytes()).hexdigest(),
}
a.output.with_suffix('.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest))
