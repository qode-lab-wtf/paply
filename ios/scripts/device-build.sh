#!/usr/bin/env bash
# Paply iOS bauen, aufs iPhone installieren und optional starten (für das MacBook).
# Läuft aus einer Kopie nur des ios/-Ordners (alle Pfade relativ zu diesem Skript).
#
#   TEAM_ID=ABCDE12345 scripts/device-build.sh            # bauen + installieren
#   TEAM_ID=ABCDE12345 scripts/device-build.sh --launch   # danach starten
#
# Optionen / Umgebungsvariablen:
#   --device <udid|name>   bzw. DEVICE_ID   Gerät (Standard: erstes verbundene iPhone)
#   --prefix <bundle-id>   bzw. PAPLY_BUNDLE_PREFIX   z. B. de.allan.paply, falls com.paply.ios vergeben ist
#   --release              Release statt Debug. Für Phase 0 NICHT empfohlen: pull-logs.sh braucht
#                          einen Debug-Build (get-task-allow), sonst lassen sich die Logs nicht holen.
#   --launch               App nach dem Installieren starten
#   DERIVED_DATA           Standard /tmp/paply-ios-dd
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$IOS_DIR"

TEAM_ID="${TEAM_ID:-}"
DEVICE="${DEVICE_ID:-}"
PREFIX="${PAPLY_BUNDLE_PREFIX:-}"
CONFIG="Debug"
LAUNCH=0
DD="${DERIVED_DATA:-/tmp/paply-ios-dd}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --release) CONFIG="Release"; shift ;;
    --launch) LAUNCH=1; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TEAM_ID" ]]; then
  echo "TEAM_ID fehlt (Apple-Team-ID, z. B. aus Xcode → Settings → Accounts)." >&2
  exit 2
fi
if [[ ! -d Paply.xcodeproj ]]; then
  echo "Paply.xcodeproj nicht gefunden in $IOS_DIR – das Skript muss im ios/scripts-Ordner liegen." >&2
  exit 2
fi
if [[ "$CONFIG" == "Release" ]]; then
  echo "Hinweis: Release-Build – pull-logs.sh kann die Diagnose dann nicht holen (kein get-task-allow)."
fi

# Xcode 26 braucht die iOS-Plattform (Xcode → Settings → Components), sonst gibt es kein Ziel.
if xcodebuild -project Paply.xcodeproj -scheme Paply -derivedDataPath "$DD" -showdestinations 2>/dev/null | grep -q "is not installed"; then
  echo "Die iOS-Plattform fehlt in Xcode. Installieren mit:" >&2
  echo "    xcodebuild -downloadPlatform iOS" >&2
  echo "(oder Xcode → Settings → Components → iOS). Danach dieses Skript erneut starten." >&2
  exit 1
fi

# Gerät ermitteln: Name, UDID oder leer (erstes verbundene iPhone) → UDID
JSON="$(mktemp -t paply-devices)"
xcrun devicectl list devices --json-output "$JSON" >/dev/null
UDID="$(python3 -I - "$JSON" "$DEVICE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
wanted = sys.argv[2].strip().lower()
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    props = d.get("deviceProperties", {})
    conn = d.get("connectionProperties", {})
    udid = hw.get("udid", "")
    names = {udid.lower(), d.get("identifier", "").lower(), props.get("name", "").lower()}
    if wanted:
        if wanted in names:
            print(udid)
            break
    elif hw.get("deviceType") == "iPhone" and conn.get("tunnelState") != "unavailable":
        print(udid)
        break
PY
)"
rm -f "$JSON"
if [[ -z "$UDID" ]]; then
  if [[ -n "$DEVICE" ]]; then
    echo "Gerät „$DEVICE“ nicht gefunden. Verfügbar:" >&2
    xcrun devicectl list devices >&2 || true
  else
    echo "Kein iPhone gefunden. Per Kabel verbinden, entsperren und „Vertrauen“ bestätigen." >&2
  fi
  exit 1
fi
echo "Gerät: $UDID · Konfiguration: $CONFIG"

SETTINGS=(DEVELOPMENT_TEAM="$TEAM_ID")
if [[ -n "$PREFIX" ]]; then
  SETTINGS+=(PAPLY_BUNDLE_PREFIX="$PREFIX")
fi

xcodebuild \
  -project Paply.xcodeproj \
  -scheme Paply \
  -configuration "$CONFIG" \
  -destination "id=$UDID" \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  "${SETTINGS[@]}" \
  build

APP="$DD/Build/Products/$CONFIG-iphoneos/Paply.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo "Installiere $BUNDLE_ID …"
xcrun devicectl device install app --device "$UDID" "$APP"

if [[ "$LAUNCH" == 1 ]]; then
  xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID"
fi

echo "Fertig. Logs holen: scripts/pull-logs.sh --device $UDID${PREFIX:+ --prefix $PREFIX}"
