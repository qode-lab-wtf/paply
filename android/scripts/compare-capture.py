#!/usr/bin/env python3
"""Offline PCM fidelity evidence: scipy/numpy, no network or voice assets."""
import argparse
import json
import wave
import numpy as np
from scipy.signal import correlate, correlation_lags

def read(path):
    with wave.open(path) as w:
        assert (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 16000)
        return np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(float)

p = argparse.ArgumentParser()
p.add_argument('source')
p.add_argument('capture')
args = p.parse_args()
src, cap = read(args.source), read(args.capture)
corr = correlate(cap, src, mode='full', method='fft')
lag = int(correlation_lags(len(cap), len(src))[np.argmax(corr)])
windows = []
width = 320
energy_prefix = np.r_[0, np.cumsum(cap*cap)]
for start in range(0, len(src) - width + 1, width):
    x = src[start:start + width]
    if np.sqrt(np.mean(x*x)) < 100:
        continue
    # Search each source window independently, allowing loss/drift inside capture.
    lo = max(0, start + lag - 8000)
    hi = min(len(cap), start + lag + 8000 + width)
    c = correlate(cap[lo:hi], x, mode='valid', method='fft')
    energy = energy_prefix[lo+width:hi+1] - energy_prefix[lo:hi-width+1]
    score = c / np.sqrt(np.maximum(energy * np.sum(x*x), 1))
    pos = int(np.argmax(score))
    windows.append(dict(source_ms=start/16, offset_ms=(lo+pos-start)/16,
                        correlation=round(float(score[pos]), 6)))
print(json.dumps(dict(source_ms=len(src)/16, capture_ms=len(cap)/16,
    global_offset_ms=lag/16, windows=windows), indent=2))
