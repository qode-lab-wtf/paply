"""Hash downloaded artifacts without publishing model files or private recordings."""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('directory', type=Path)
    p.add_argument('output', type=Path)
    a = p.parse_args()
    root = Path(__file__).resolve().parents[2]
    a.output.resolve().relative_to(root/'work')
    entries = []
    for f in sorted(a.directory.rglob('*')):
        if not f.is_file() or '.cache' in f.parts:
            continue
        h = hashlib.sha256()
        with f.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024*1024), b''):
                h.update(chunk)
        entries.append({'file': str(f.relative_to(a.directory)), 'size': f.stat().st_size, 'sha256': h.hexdigest()})
    a.output.write_text(json.dumps({'files': entries}, indent=2))
    print('Hashed', len(entries), 'artifacts')


if __name__ == '__main__':
    main()
