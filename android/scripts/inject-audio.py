#!/usr/bin/env python3
"""Authenticated, local emulator gRPC audio; generated proto lives outside the repo.
Based on the official AOSP inject_audio.py flow linked in PLATTFORM.md D9.
"""
import argparse
from pathlib import Path
import sys
import subprocess
import time
import wave
import grpc

sys.path.insert(0, str(Path.home() / 'Android/work/audio-test/proto'))
from emulator_controller_pb2 import AudioFormat, AudioPacket
from emulator_controller_pb2_grpc import EmulatorControllerStub

parser = argparse.ArgumentParser()
parser.add_argument('wav')
parser.add_argument('--wait', type=float, default=0, help='Wait up to this many seconds for an active recorder')
parser.add_argument('--serial', default='emulator-5580')
parser.add_argument('--grpc-port', default='8554')
args = parser.parse_args()
discovery = Path.home() / 'Library/Caches/TemporaryItems/avd/running'
configs = []
for file in discovery.glob('pid_*.ini'):
    values = dict(line.split('=', 1) for line in file.read_text().splitlines() if '=' in line)
    if values.get('grpc.port') == args.grpc_port:
        configs.append(values)
if len(configs) != 1:
    raise SystemExit('Expected one authenticated Paply emulator on port 8554.')
# Emulator 37.2 can crash in audio_forwarder_enable if no input stream is active.
# Do not begin injection until Android confirms Paply owns an active recorder.
deadline = time.monotonic() + min(max(args.wait, 0), 15)
while True:
    audio_state = subprocess.check_output(['adb', '-s', args.serial, 'shell', 'dumpsys', 'audio'], text=True)
    monitor = audio_state.split('## RecordActivityMonitor', 1)[-1].split('### Recording Activity', 1)[0]
    if 'active? true' in monitor and 'pack:com.paply.android' in monitor:
        break
    if time.monotonic() >= deadline:
        raise SystemExit('Paply recorder is not active; refusing injection (emulator audio-forwarder crash guard).')
    time.sleep(.2)
config = configs[0]
token = config.get('grpc.token')
if not token:
    raise SystemExit('Missing gRPC token; use start-audio-emulator.sh.')

def packets():
    with wave.open(args.wav, 'rb') as wav:
        assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, 16000)
        fmt = AudioFormat(samplingRate=16000, channels=AudioFormat.Mono, format=AudioFormat.AUD_FMT_S16, mode=AudioFormat.MODE_REAL_TIME)
        start = time.monotonic()
        frames = 0
        while True:
            data = wav.readframes(1600)
            if not data:
                break
            yield AudioPacket(format=fmt, audio=data)
            frames += len(data) // 2
            time.sleep(max(0, start + frames / 16000 - time.monotonic()))
        print(f'Injected {frames} frames ({frames / 16000:.2f}s), PCM16 mono 16kHz.')

with wave.open(args.wav, 'rb') as source:
    timeout = max(45, source.getnframes() / source.getframerate() + 30)

with grpc.insecure_channel('127.0.0.1:' + args.grpc_port) as channel:
    # Loopback transport with emulator-generated bearer token; never printed or persisted here.
    EmulatorControllerStub(channel).injectAudio(packets(), metadata=(('authorization', 'Bearer ' + token),), timeout=timeout)
