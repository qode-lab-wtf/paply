#!/usr/bin/env bash
# Holt das Diagnoseprotokoll (JSONL) aus dem App-Group-Container des iPhones,
# führt alle Prozesse zeitlich zusammen und zeigt eine kurze Latenz-Übersicht.
# Diktat-Texte stehen nicht im Protokoll (nur Längen und Zeiten).
# Braucht einen Debug-Build (get-task-allow) – so baut scripts/device-build.sh standardmäßig.
#
#   scripts/pull-logs.sh [--device <udid|name>] [--group group.com.paply.ios] [--out <ordner>]
# Die App Group ist fest (siehe Config/Base.xcconfig), auch bei anderem Bundle-Präfix.
set -euo pipefail

DEVICE="${DEVICE_ID:-}"
GROUP="${PAPLY_APP_GROUP:-group.com.paply.ios}"
OUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --group) GROUP="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done

JSON="$(mktemp -t paply-devices)"
xcrun devicectl list devices --json-output "$JSON" >/dev/null
UDID="$(python3 -I - "$JSON" "$DEVICE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
wanted = sys.argv[2].strip().lower()
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    udid = hw.get("udid", "")
    names = {udid.lower(), d.get("identifier", "").lower(), d.get("deviceProperties", {}).get("name", "").lower()}
    if (wanted and wanted in names) or (not wanted and hw.get("deviceType") == "iPhone"):
        print(udid)
        break
PY
)"
rm -f "$JSON"
[[ -n "$UDID" ]] || { echo "Kein passendes iPhone gefunden${DEVICE:+ („$DEVICE“)}." >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${OUT:-$HOME/paply-logs/$STAMP}"
mkdir -p "$OUT/raw"

echo "Hole Diagnostics aus $GROUP …"
xcrun devicectl device copy from \
  --device "$UDID" \
  --domain-type appGroupDataContainer \
  --domain-identifier "$GROUP" \
  --source Diagnostics \
  --destination "$OUT/raw"

python3 -I - "$OUT" <<'PY'
import json, os, statistics, sys
from collections import defaultdict

out = sys.argv[1]
rows = []
for root, _, files in os.walk(os.path.join(out, "raw")):
    for name in files:
        if not name.endswith(".jsonl"):
            continue
        with open(os.path.join(root, name), encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    pass
rows.sort(key=lambda r: (r.get("ts", ""), r.get("mono", 0)))
merged = os.path.join(out, "merged.jsonl")
with open(merged, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print(f"{len(rows)} Einträge → {merged}")

def stats(values):
    values = [v for v in values if isinstance(v, (int, float))]
    if not values:
        return "–"
    return f"Median {statistics.median(values):.0f} ms · Mittel {statistics.mean(values):.0f} ms · max {max(values):.0f} (n={len(values)})"

DEFAULT_OPTS = {"flac·primer·polish·strict", "flac·primer·polish"}  # aktuell bzw. ältere Builds

def key(r):
    chunked = r.get("chunked")
    chunk_label = "Stücke an" if chunked is True else "Stücke aus" if chunked is False else "Stücke ?"
    # Testvarianten (Format, Beispielsatz, Polieren) nur ausweisen, wenn nicht Standard –
    # so landen Messungen mit „Polieren aus“ nicht im selben Topf.
    opts = r.get("opts") or "flac·primer·polish·strict"
    return (str(r.get("model") or "?"), chunk_label, str(r.get("net") or "?"), "" if opts in DEFAULT_OPTS else f" · [{opts}]")

print("\nTastatur")
print("  Erscheinen → Aufnahme läuft:", stats([r.get("appearToRecordingMs") for r in rows if r.get("ev") == "kb.recording"]))
print("  Prozessstart → erstes Bild:  ", stats([r.get("sinceProcessStartMs") for r in rows if r.get("ev") == "kb.firstFrame"]))

app = defaultdict(list)
for r in rows:
    if r.get("ev") == "dictation.result" and not r.get("deferred"):
        app[key(r)].append(r.get("totalMs"))
kb = defaultdict(list)
for r in rows:
    if r.get("ev") == "kb.inserted" and r.get("source") == "dictation":
        kb[key(r)].append(r.get("tapToInsertMs"))

for title, groups in (("App: Pipeline ab „fertig“ (totalMs)", app), ("Tastatur: Tipp „fertig“ → eingesetzt", kb)):
    if groups:
        print(f"\n{title} – je Modell · Stücke · Netz")
        for k in sorted(groups):
            print(f"  {k[0]} · {k[1]} · {k[2]}{k[3]}: {stats(groups[k])}")

counts = defaultdict(int)
for r in rows:
    ev = r.get("ev", "")
    if ev.startswith(("audio.interruption", "audio.resume", "session.", "kb.open", "kb.disappear.defer", "dictation.deferred")):
        counts[ev] += 1
polish = defaultdict(int)
for r in rows:
    if r.get("ev") == "dictation.result":
        if r.get("polishError"):
            polish[f"unpoliert: {r.get('polishError')}"] += 1
        if r.get("rejected"):
            polish[f"Sicherheitsnetz: {r.get('rejected')}"] += 1
        if r.get("polishModel"):
            polish[f"Modell: {r.get('polishModel')}"] += 1
        if r.get("retries"):
            polish["erneut gesendet"] += 1
        if r.get("noSpeech"):
            polish["nichts verstanden"] += 1
if polish:
    print("\nPolieren / Neuversuche")
    for k, n in sorted(polish.items()):
        print(f"  {k}: {n}")

if counts:
    print("\nSitzung / Unterbrechungen / App öffnen / zurückgestellt")
    for ev, n in sorted(counts.items()):
        print(f"  {ev}: {n}")
PY
