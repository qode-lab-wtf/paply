"""Experimental local enhancement. Never replaces the source recording.

Derived audio is stored inside an enrolled session so its original expiry applies.
This is a comparison tool, not an enabled product preprocessing stage.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time

os.environ.update(HF_HUB_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1',
                  PYTORCH_ENABLE_MPS_FALLBACK='1')
ROOT = Path(__file__).resolve().parents[2]


def output_path(audio):
    directory = audio.resolve().parent
    state = json.loads((directory / 'local-state.json').read_text())
    if state.get('retentionPolicy') != 'seven-days-from-capture' or state.get('schemaVersion') != 2:
        raise ValueError('Source must belong to a session enrolled in audio retention')
    if state.get('audioExpiresAt', 0) <= time.time() * 1000:
        raise ValueError('Source has expired; do not create new audio derivatives')
    return directory / 'processing' / 'experiments' / 'mossformer.wav'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest', type=Path)
    p.add_argument('output_manifest', type=Path)
    args = p.parse_args()
    args.output_manifest.resolve().relative_to(ROOT / 'work')
    manifest = json.loads(args.manifest.read_text())
    source = Path(manifest['audio'])
    if hashlib.sha256(source.read_bytes()).hexdigest() != manifest['audioSha256']:
        raise ValueError('Source hash mismatch')
    destination = output_path(source)
    if destination.exists():
        raise FileExistsError('Keep existing experiment evidence; do not overwrite')
    import importlib.util
    spec = importlib.util.spec_from_file_location('paply_enhancer', ROOT / 'electron-menubar/meeting/local/enhancer.py')
    enhancer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(enhancer)
    state = json.loads((source.parent / 'local-state.json').read_text())
    started = time.monotonic()
    destination.parent.mkdir(parents=True, exist_ok=True)
    enhancer.enhance(source, destination, {'enhancementModel': str(ROOT / 'work/models/mossformer-gan')}, state)
    result = {**manifest, 'id': manifest['id'] + '-enhanced', 'audio': str(destination),
              'audioSha256': hashlib.sha256(destination.read_bytes()).hexdigest(),
              'sourceAudioSha256': manifest['audioSha256'],
              'enhancement': 'alibabasglab/MossFormerGAN_SE_16K@dcb1b20e1e44d435090072ab9b223c792ea1f624',
              'enhancementSeconds': time.monotonic() - started, 'qualityApproved': False}
    args.output_manifest.write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
