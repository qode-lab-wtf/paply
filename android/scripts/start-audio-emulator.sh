#!/bin/bash
# Test launcher only; never edits the shared emu-start.sh or AVD configuration.
set -euo pipefail
source "$HOME/Android/env.sh"
"$HOME/Android/emu-stop.sh"
mkdir -p "$HOME/Android/work/audio-test"
nohup emulator -avd paply -port 5580 -no-window -no-boot-anim -no-snapshot-save -gpu swiftshader \
  -grpc 8554 -grpc-use-token > "$HOME/Android/work/audio-test/emulator.log" 2>&1 < /dev/null &
for ((i=0;i<90;i++)); do
  if [[ "$(adb -s emulator-5580 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; then exit 0; fi
  sleep 2
done
exit 1
