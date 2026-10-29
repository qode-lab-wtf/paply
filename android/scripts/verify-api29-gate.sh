#!/bin/bash
# Run in the synced Android checkout on MacBook, with env.sh sourced.
# Negative control: test must reject incompatible production bytecode.
set -euo pipefail
cd "$(dirname "$0")/.."
probe=core/src/main/kotlin/AndroidApi29NegativeProbe.kt
[[ ! -e "$probe" ]] || { echo 'Probe path already exists' >&2; exit 1; }
log=$(mktemp)
trap 'rm -f "$probe" "$log"' EXIT
cat > "$probe" <<'EOF'
package com.paply.compatibilityprobe
import java.nio.file.Files
import java.nio.file.Path
import java.util.Optional
import java.util.stream.Collectors
import java.util.stream.Stream
fun stream(s: Stream<String>) = s.toList()
fun bytes(i: java.io.InputStream) = i.readNBytes(44)
fun optional(o: Optional<String>) = o.isEmpty
fun file(p: Path) = Files.readString(p)
fun collector(s: Stream<String>) = s.collect(Collectors.toUnmodifiableList())
fun first(l: java.util.ArrayList<String>) = l.removeFirst()
EOF
if ./gradlew :core:test --console=plain > "$log" 2>&1; then
    cat "$log"
    echo 'ERROR: incompatible bytecode passed :core:test' >&2
    exit 1
fi
for method in 'Stream.toList' 'InputStream.readNBytes' 'Optional.isEmpty' 'Files.readString' 'Collectors.toUnmodifiableList' 'ArrayList.removeFirst'; do
    grep -F "$method" "$log" >/dev/null || { cat "$log"; echo "Missing rejection: $method" >&2; exit 1; }
done
cat "$log"
echo 'PASS: all six incompatible calls rejected through :core:test'
