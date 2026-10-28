#!/bin/bash
# MacBook only. Everything installed/generated lives in work/ or venv/.
set -euo pipefail
source "$HOME/Android/env.sh"
export TMPDIR="$HOME/Android/work/tmp"
mkdir -p "$TMPDIR" "$HOME/Android/work/audio-test/proto"
if [[ ! -x "$HOME/Android/venv/bin/python" ]]; then
  /usr/bin/python3 -m venv "$HOME/Android/venv"
fi
"$HOME/Android/venv/bin/python" -m pip install --no-cache-dir grpcio==1.80.0 grpcio-tools==1.80.0 protobuf==6.33.6
"$HOME/Android/venv/bin/python" -m grpc_tools.protoc -I "$ANDROID_HOME/emulator/lib" --python_out="$HOME/Android/work/audio-test/proto" --grpc_python_out="$HOME/Android/work/audio-test/proto" "$ANDROID_HOME/emulator/lib/emulator_controller.proto"
say -v Anna -o "$HOME/Android/work/audio-test/de.wav" --file-format=WAVE --data-format=LEI16@16000 --channels=1 'Hallo Testname, ich komme heute etwas später, so gegen halb acht.'
say -v Samantha -o "$HOME/Android/work/audio-test/en.wav" --file-format=WAVE --data-format=LEI16@16000 --channels=1 'Please remind me to bring the green notebook tomorrow morning.'
