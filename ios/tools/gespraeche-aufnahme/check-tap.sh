#!/bin/sh
# Prüft den echten Tap auf dem Mac; nur der nicht verwendete Pegel-Dateikanal ist ersetzt.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d /tmp/paply-tap-check.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
sed '/^import PaplyKit$/d' "$ROOT/App/Session/AudioTapProcessor.swift" > "$TMP/AudioTapProcessor.swift"
cp "$ROOT/tools/gespraeche-aufnahme/main.swift" "$TMP/main.swift"
swiftc -swift-version 6 "$TMP/AudioTapProcessor.swift"     "$ROOT/PaplyKit/Sources/PaplyKit/Audio/MicSilence.swift"     "$ROOT/Shared/Core/MonoClock.swift" "$TMP/main.swift" -o "$TMP/check"
"$TMP/check"
