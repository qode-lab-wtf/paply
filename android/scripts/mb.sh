#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
host=${PAPLY_MACBOOK:-macbook}
work=${PAPLY_WORK:-paply-android}
[[ "$work" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'PAPLY_WORK: nur Buchstaben, Ziffern, - und _' >&2; exit 2; }
remote="~/Android/work/$work"
avd=${PAPLY_AVD:-paply}
port=${PAPLY_PORT:-5580}
[[ "$avd" =~ ^[a-zA-Z0-9_-]+$ && "$port" =~ ^[0-9]+$ ]] || { echo "PAPLY_AVD/PAPLY_PORT ungültig" >&2; exit 2; }
serial="emulator-$port"
case "${1:-}" in
  sync)
    ssh "$host" 'set -e; source ~/Android/env.sh; mkdir -p ~/Android/work/'"$work"
    rsync -az --exclude build/ --exclude .gradle/ --exclude .kotlin/ --exclude .local/ --exclude local.properties --exclude "*.jks" --exclude "*.keystore" --exclude paply-release.properties "$root/" "$host:$remote/" ;;
  build)
    ssh "$host" 'set -e; source ~/Android/env.sh; export GRADLE_USER_HOME="$HOME/Android/work/gradle-home"; export TMPDIR="$HOME/Android/work/tmp"; mkdir -p "$TMPDIR"; export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$TMPDIR -Djava.util.prefs.userRoot=$HOME/Android/work/java-prefs"; cd ~/Android/work/'"$work"'; mkdir -p .local; if [ ! -f .local/debug.keystore ]; then keytool -genkeypair -keystore .local/debug.keystore -storepass android -alias androiddebugkey -keypass android -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 10000; fi; ./gradlew '"${GRADLE_TASKS:-:core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:lintRelease}"' --console=plain' ;;
  release)
    evidence=/tmp/paply-android-release
    mkdir -p "$evidence"
    ssh "$host" /bin/bash -s -- "$work" <<'REMOTE_RELEASE'
set -euo pipefail
source "$HOME/Android/env.sh"
export GRADLE_USER_HOME="$HOME/Android/work/gradle-home"
export TMPDIR="$HOME/Android/work/tmp"
mkdir -p "$TMPDIR"
export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$TMPDIR -Djava.util.prefs.userRoot=$HOME/Android/work/java-prefs"
cd "$HOME/Android/work/$1"
./gradlew :core:animalsnifferMain :thoughts:animalsnifferMain :app:lintRelease :app:assembleRelease --console=plain
# Read this build's metadata, so an old signed APK cannot mask an unsigned build.
apk=$(/usr/bin/python3 -c 'import json; print(json.load(open("app/build/outputs/apk/release/output-metadata.json"))["elements"][0]["outputFile"])')
if [[ "$apk" != app-release.apk ]]; then
  echo 'Paply: Keine signierte Release-APK. ~/Android/keys/paply-release.properties einrichten; unsignierte APK nicht weitergeben.' >&2
  exit 1
fi
"$ANDROID_HOME/build-tools/37.0.0/apksigner" verify --print-certs "app/build/outputs/apk/release/$apk"
mkdir -p build/reports
python3 scripts/audit-release-api.py "app/build/outputs/apk/release/$apk" > build/reports/release-api29.txt
echo "Merged-DEX API-29 report: build/reports/release-api29.txt (SDK guards require review)"
REMOTE_RELEASE
    version=$(ssh "$host" "cd $remote; /usr/bin/python3 -c 'import json; print(json.load(open(\"app/build/outputs/apk/release/output-metadata.json\"))[\"elements\"][0][\"versionName\"])'")
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Paply: Ungültige Release-Version' >&2; exit 1; }
    # Transfer to a temporary name; publish only the complete verified APK locally.
    scp "$host:$remote/app/build/outputs/apk/release/app-release.apk" "$evidence/.Paply-$version.apk.tmp"
    mv "$evidence/.Paply-$version.apk.tmp" "$evidence/Paply-$version.apk"
    (cd "$evidence" && shasum -a 256 "Paply-$version.apk" > "Paply-$version.apk.sha256")
    echo "Paply: Signierte APK und SHA-256 unter $evidence/Paply-$version.apk" ;;
  install)
    ssh "$host" 'set -e; source ~/Android/env.sh; PAPLY_AVD='"$avd"' PAPLY_PORT='"$port"' ~/Android/emu-start.sh; adb -s '"$serial"' install -r ~/Android/work/'"$work"'/app/build/outputs/apk/debug/app-debug.apk' ;;
  shot)
    name=${2:?shot requires a name}
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 2
    evidence=${PAPLY_EVIDENCE_DIR:-/tmp/paply-android-p0}
    mkdir -p "$evidence"
    ssh "$host" 'set -e; source ~/Android/env.sh; adb -s '"$serial"' exec-out screencap -p' > "$evidence/$name.png" ;;
  logs)
    ssh "$host" 'set -e; source ~/Android/env.sh; adb -s '"$serial"' logcat -d -v threadtime Paply:D AndroidRuntime:E "*:S"' ;;
  *) echo 'Usage: [PAPLY_WORK=name] [GRADLE_TASKS="…"] mb.sh sync|build|release|install|shot <name>|logs' >&2; exit 2 ;;
esac
