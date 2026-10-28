#!/usr/bin/env python3
"""MacBook only: reproducible say fixtures for E1 D, no network or credentials."""
from pathlib import Path
import subprocess
import wave

out = Path.home() / 'Android/work/ime/.local/audio'
out.mkdir(parents=True, exist_ok=True)
def speak(name, text, voice='Anna', rate=155):
    file = out / (name + '.wav')
    subprocess.run(['say', '-v', voice, '-r', str(rate), '-o', str(file), '--file-format=WAVE',
                    '--data-format=LEI16@16000', '--channels=1', text], check=True)
    with wave.open(str(file)) as wav:
        data = wav.readframes(wav.getnframes())
    print(name, round(len(data)/32000, 2), 's')
    return data

def write(name, data):
    with wave.open(str(out / (name + '.wav')), 'wb') as wav:
        wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
        wav.writeframes(data)
    print(name, round(len(data)/32000, 2), 's')

speak('testname', 'Hallo Testname, ich komme heute etwas später, so gegen halb acht.')
speak('short', "Hi, wie geht's?")
speak('english', 'Tomorrow morning I will bring the green notebook to our meeting, and afterwards we can discuss the plans for the new garden together.', 'Samantha', 145)
first = speak('long-first', 'Morgen treffen wir uns am frühen Nachmittag im großen Garten hinter dem Haus, um gemeinsam die nächsten Schritte für unser neues Projekt zu besprechen.', rate=150)
second = speak('long-second', 'Bitte bring das grüne Notizbuch und die alten Unterlagen mit, damit wir alle wichtigen Fragen in Ruhe durchgehen und die Aufgaben sinnvoll verteilen können.', rate=150)
last = speak('long-last', 'Danach trinken wir zusammen einen Kaffee und gehen nach Hause.', rate=160)
write('long', first + bytes(25600) + second + bytes(25600) + last + bytes(16000))
write('silence', bytes(32000 * 3))
