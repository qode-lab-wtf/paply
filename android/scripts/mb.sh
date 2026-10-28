#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
host=${PAPLY_MACBOOK:-macbook}
work=${PAPLY_WORK:-paply-android}
[[ "$work" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'PAPLY_WORK: nur Buchstaben, Ziffern, - und _' >&2; exit 2; }
remote="~/Android/work/$work"
case "${1:-}" in
  sync)
    ssh "$host" 'set -e; source ~/Android/env.sh; mkdir -p ~/Android/work/'"$work"
    rsync -az --exclude build/ --exclude .gradle/ --exclude .kotlin/ --exclude .local/ --exclude local.properties "$root/" "$host:$remote/" ;;
  build)
    ssh "$host" 'set -e; source ~/Android/env.sh; export GRADLE_USER_HOME="$HOME/Android/work/gradle-home"; export TMPDIR="$HOME/Android/work/tmp"; mkdir -p "$TMPDIR"; export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$TMPDIR -Djava.util.prefs.userRoot=$HOME/Android/work/java-prefs"; cd ~/Android/work/'"$work"'; mkdir -p .local; ./gradlew '"${GRADLE_TASKS:-:core:test :app:assembleDebug}"' --console=plain' ;;
  install)
    ssh "$host" 'set -e; source ~/Android/env.sh; ~/Android/emu-start.sh; adb -s emulator-5580 install -r ~/Android/work/'"$work"'/app/build/outputs/apk/debug/app-debug.apk' ;;
  shot)
    name=${2:?shot requires a name}
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 2
    mkdir -p /tmp/paply-android-p0
    ssh "$host" 'set -e; source ~/Android/env.sh; adb -s emulator-5580 exec-out screencap -p' > "/tmp/paply-android-p0/$name.png" ;;
  logs)
    ssh "$host" 'set -e; source ~/Android/env.sh; adb -s emulator-5580 logcat -d -v threadtime Paply:D AndroidRuntime:E "*:S"' ;;
  *) echo 'Usage: [PAPLY_WORK=name] [GRADLE_TASKS="…"] mb.sh sync|build|install|shot <name>|logs' >&2; exit 2 ;;
esac
