#!/usr/bin/env python3
"""Conservative merged-DEX invocation audit, on MacBook with Android SDK.

Reports newer platform calls including guarded dependency code. This is a review
report, not a control-flow proof. Animal Sniffer is the strict JVM source gate;
Android Lint checks SDK guards in app sources. No third-party Python packages.
"""
import argparse
import functools
import os
import pathlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('apk', type=pathlib.Path)
p.add_argument('--sdk', type=pathlib.Path, default=os.environ.get('ANDROID_HOME'))
p.add_argument('--api', type=int, default=29)
p.add_argument('--api-xml', type=pathlib.Path)
p.add_argument('--dexdump', type=pathlib.Path)
a = p.parse_args()
if a.sdk is None:
    p.error('ANDROID_HOME or --sdk required')
xml = a.api_xml or sorted(a.sdk.glob('platforms/*/data/api-versions.xml'))[-1]
dexdump = a.dexdump or sorted(a.sdk.glob('build-tools/*/dexdump'))[-1]
classes = {c.attrib['name']: c for c in ET.parse(xml).getroot().findall('class')}

@functools.lru_cache(None)
def method_api(owner, member):
    c = classes.get(owner)
    if c is None:
        return None
    floor = float(c.get('since', '1'))
    for m in c.findall('method'):
        if m.get('name') == member:
            return max(floor, float(m.get('since', str(floor))))
    for parent in list(c.findall('extends')) + list(c.findall('implements')):
        level = method_api(parent.get('name'), member)
        if level is not None:
            return max(floor, level, float(parent.get('since', '1')))
    return None

# dexdump disassembles actual instructions, including invoke-*/range.
invoke = re.compile(r'\binvoke-[\w/-]+\s+.*?, L([^;]+);\.([^:]+):(\S+)')
refs = {}
with zipfile.ZipFile(a.apk) as apk, tempfile.TemporaryDirectory() as tmp:
    dexes = sorted(n for n in apk.namelist() if re.fullmatch(r'classes\d*\.dex', n))
    if not dexes:
        raise SystemExit('No merged DEX in APK')
    for name in dexes:
        path = pathlib.Path(tmp) / name
        path.write_bytes(apk.read(name))
        proc = subprocess.Popen([str(dexdump), '-d', str(path)], stdout=subprocess.PIPE, text=True)
        for line in proc.stdout:
            match = invoke.search(line)
            if match:
                owner, method, descriptor = match.groups()
                if owner.startswith(('java/', 'javax/', 'android/', 'dalvik/', 'org/xml/', 'org/w3c/')):
                    key = (owner, method + descriptor)
                    refs[key] = refs.get(key, 0) + 1
        if proc.wait():
            raise SystemExit('dexdump failed')
newer, unknown = [], []
for (owner, member), count in sorted(refs.items()):
    level = method_api(owner, member)
    if level is None:
        unknown.append((owner, member, count))
    elif level > a.api:
        newer.append((owner, member, level, count))
print(f'APK: {a.apk.name}; DEX: {len(dexes)}; distinct platform invocations: {len(refs)}')
print(f'Baseline API {a.api}; database: {xml}')
print(f'Newer references (review SDK guards/dependency fallbacks): {len(newer)}')
for owner, member, level, count in newer:
    print(f'  API {level}: {owner}.{member} [{count} instructions]')
print(f'Unresolved references (not proof of incompatibility): {len(unknown)}')
for owner, member, count in unknown:
    print(f'  UNKNOWN: {owner}.{member} [{count} instructions]')
