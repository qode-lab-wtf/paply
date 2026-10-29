#!/usr/bin/env python3
"""MacBook-only German say fixtures; never calls Groq or reads credentials."""
from pathlib import Path
import subprocess
import wave

out = Path.home() / 'Android/work/fixg/.local/audio'
out.mkdir(parents=True, exist_ok=True)
texts = {
    'short': 'Morgen möchte ich die Tomaten auf dem Balkon gießen.',
    'beta': 'Für den Garten muss ich morgen zwei große Blumentöpfe kaufen.',
    'long': 'Am Samstag möchte ich mein Fahrrad reparieren und einen neuen Schlauch kaufen.',
}
for name, text in texts.items():
    path = out / (name + '.wav')
    subprocess.run(['say', '-v', 'Anna', '-r', '175', '-o', str(path), '--file-format=WAVE',
                    '--data-format=LEI16@16000', '--channels=1', text], check=True)
    with wave.open(str(path), 'rb') as wav:
        print(name, round(wav.getnframes() / 16000, 2), 's')
# Speech at both ends retains almost ten minutes of PCM through capture edge trimming.
# The ten-minute wall-clock limit is exercised by starting injection immediately after recording.
with wave.open(str(out / 'ten-minutes.wav'), 'wb') as wav:
    wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
    with wave.open(str(out / 'short.wav'), 'rb') as voice:
        wav.writeframesraw(voice.readframes(voice.getnframes()))
        first_frames = voice.getnframes()
    silent_frames = 590 * 16000 - first_frames
    while silent_frames:
        frames = min(16000, silent_frames)
        wav.writeframesraw(bytes(frames * 2))
        silent_frames -= frames
    with wave.open(str(out / 'long.wav'), 'rb') as voice:
        wav.writeframesraw(voice.readframes(voice.getnframes()))
    wav.writeframesraw(bytes(32000))
