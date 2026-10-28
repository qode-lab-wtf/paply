#!/usr/bin/env python3
"""Small adb helper for this emulator's repeatable phase-0 UI checks."""
import argparse
import re
import subprocess
import xml.etree.ElementTree as ET
adb = ['adb', '-s', 'emulator-5580']
p = argparse.ArgumentParser()
p.add_argument('--tap', help='Exact UI text or accessibility label')
a = p.parse_args()
subprocess.run(adb + ['shell', 'rm', '-f', '/sdcard/paply-window.xml'], check=True)
try:
    dump = subprocess.run(adb + ['shell', 'uiautomator', 'dump', '/sdcard/paply-window.xml'],
                          check=True, capture_output=True, text=True, timeout=15)
except subprocess.TimeoutExpired:
    raise SystemExit('UI did not become idle; inspect a screenshot instead.')
if 'UI hierchary dumped to:' not in dump.stdout:
    raise SystemExit('No fresh UI hierarchy (animation/chronometer); inspect a screenshot instead.')
r = ET.fromstring(subprocess.check_output(adb + ['exec-out', 'cat', '/sdcard/paply-window.xml']))
if a.tap:
    nodes = [n for n in r.iter('node') if n.get('text') == a.tap or n.get('content-desc') == a.tap]
    if not nodes:
        raise SystemExit('UI target not found: ' + a.tap)
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', nodes[0].get('bounds')))
    subprocess.run(adb + ['shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2)], check=True)
else:
    for n in r.iter('node'):
        if n.get('text') or n.get('content-desc'):
            print(n.get('class'), n.get('text') or n.get('content-desc'), n.get('bounds'))
