"""Evaluate a reference/prediction pair; do not confuse a smoke run with acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
from metrics import score


def main():
    p = argparse.ArgumentParser()
    p.add_argument('manifest', type=Path)
    p.add_argument('prediction', type=Path)
    args = p.parse_args()
    manifest = json.loads(args.manifest.read_text())
    prediction = json.loads(args.prediction.read_text())
    digest = hashlib.sha256(Path(manifest['audio']).read_bytes()).hexdigest()
    if digest != manifest['audioSha256']:
        raise ValueError('Reference audio changed')
    if prediction.get('status') != 'completed':
        result = {'status': 'model-failed', 'passed': False}
    else:
        result = score(manifest, prediction)
    # A single sample result can NEVER qualify a full pipeline.
    result['pipelineApproved'] = False
    result['remainingAcceptance'] = ['room/call/hybrid coverage', 'report factuality',
                                     'overlap review', 'capture/recovery/export/retention/dictation tests']
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
