#!/usr/bin/env python3
"""Run ONLY on MacBook after sourcing ~/Android/env.sh. Never print the key."""
import json
from pathlib import Path
import subprocess

config = json.loads((Path.home() / 'Library/Application Support/paply-menubar/config.json').read_text())
# Match the desktop configuration field, without printing config or secret values.
key = config.get('groqApiKey') or config.get('groqKey') or config.get('apiKey')
if not isinstance(key, str) or not key.startswith('gsk_'):
    raise SystemExit('Groq key field not found; inspect desktop schema, never dump config.')
adb = ['adb', '-s', 'emulator-5580']
try:
    subprocess.run(adb + ['shell', 'run-as', 'com.paply.android', 'sh', '-c', "'mkdir -p files && cat > files/debug-groq-key'"], input=key.encode(), check=True, stdout=subprocess.DEVNULL, timeout=20)
    subprocess.run(adb + ['shell', 'am', 'broadcast', '-n', 'com.paply.android/.DebugControlReceiver', '-a', 'com.paply.android.DEBUG', '--es', 'command', 'load-key'], check=True, stdout=subprocess.DEVNULL, timeout=20)
finally:
    key = None
    config.clear()
    subprocess.run(adb + ['shell', 'run-as', 'com.paply.android', 'rm', '-f', 'files/debug-groq-key'], check=True, stdout=subprocess.DEVNULL, timeout=20)
print('Test key installed privately; staging file removed.')
