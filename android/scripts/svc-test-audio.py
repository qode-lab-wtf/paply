#!/usr/bin/env python3
"""MacBook-only E2 S fixtures: local speech synthesis, no API calls or credentials."""
from pathlib import Path
import subprocess
import wave

out = Path.home() / 'Android/work/svc/.local/audio'
out.mkdir(parents=True, exist_ok=True)
texts = {
    'first': 'Für den Garten möchte ich Tomaten auf dem Balkon pflanzen. Morgen muss ich dafür große Töpfe kaufen.',
    'related': 'Noch etwas zu den Tomaten auf dem Balkon. Statt kleiner Töpfe nehme ich zwei große Kübel. Morgen muss ich auch die passende Erde kaufen.',
    'interrupted-first': 'Für den Urlaub in Portugal möchte ich nach Porto fahren.',
    'interrupted-last': 'Außerdem muss ich morgen ein Hotel in Porto buchen.',
    'offline': 'Am Wochenende möchte ich das Fahrrad reparieren. Ich muss dafür morgen einen neuen Schlauch kaufen.',
}
for name, text in texts.items():
    path = out / (name + '.wav')
    subprocess.run(['say', '-v', 'Anna', '-r', '165', '-o', str(path), '--file-format=WAVE',
                    '--data-format=LEI16@16000', '--channels=1', text], check=True)
    with wave.open(str(path), 'rb') as audio:
        print(name, round(audio.getnframes() / 16000, 2), 's')
