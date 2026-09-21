"""Isolated local model worker. Outputs go to ignored work/, never cloud STT.

Usage: python run_model.py CANDIDATE MANIFEST OUTPUT
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
FLUID = ROOT / 'work/FluidAudio/.build/release/fluidaudiocli'


def normalize_turns(segments, duration):
    """CoreML final windows can extend beyond the recording; retain raw output separately."""
    result = []
    for s in segments:
        start, end = float(s['startTimeSeconds']), float(s['endTimeSeconds'])
        if not math.isfinite(start) or not math.isfinite(end) or end <= start:
            raise ValueError('Invalid model timestamps')
        start, end = max(0.0, start), min(duration, end)
        if end > start:
            result.append({'start': start, 'end': end, 'speaker': s['speakerId']})
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('candidate', choices=['qwen-asr', 'whisper', 'parakeet', 'fluid-diarization', 'pyannote'])
    p.add_argument('manifest', type=Path)
    p.add_argument('output', type=Path)
    args = p.parse_args()
    # Outputs contain private conversation content. Never permit tracked destinations.
    args.output = args.output.resolve()
    args.output.relative_to(ROOT / 'work')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    m = json.loads(args.manifest.read_text())
    audio = Path(m['audio'])
    digest = hashlib.sha256(audio.read_bytes()).hexdigest()
    if digest != m['audioSha256']:
        raise ValueError('Audio hash mismatch')
    raw = args.output.with_suffix('.raw.json')
    result = {'schemaVersion': 1, 'candidate': args.candidate, 'audioSha256': digest,
              'sampleId': m['id'], 'status': 'running', 'task': 'asr'}
    started = time.monotonic()
    try:
        if args.candidate == 'qwen-asr':
            from mlx_audio.stt.utils import load_model
            model = load_model(str(ROOT / 'work/models/qwen3-asr'))
            out = model.generate(str(audio), language='German', max_tokens=8192)
            result['text'] = out.text
            result['model'] = 'mlx-community/Qwen3-ASR-1.7B-4bit@78a389c776a5483b2d0d4ea5494e11012e0d6159'
        elif args.candidate == 'whisper':
            import mlx_whisper
            out = mlx_whisper.transcribe(str(audio), path_or_hf_repo=str(ROOT / 'work/models/whisper'),
                                        language='de', word_timestamps=True, verbose=False)
            result.update(text=out['text'], segments=out['segments'])
            result['model'] = 'mlx-community/whisper-large-v3-mlx@49e6aa286ad60c14352c404340ded53710378a11'
        elif args.candidate in ('parakeet', 'fluid-diarization'):
            if args.candidate == 'parakeet':
                cmd = [str(FLUID), 'transcribe', str(audio), '--model-version', 'v3', '--word-timestamps', '--output-json', str(raw)]
            else:
                cmd = [str(FLUID), 'process', str(audio), '--mode', 'offline', '--overlapping-segments', '--output', str(raw)]
                result['task'] = 'diarization'
            with args.output.with_suffix('.worker.log').open('w') as log:
                subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1200)
            out = json.loads(raw.read_text())
            if args.candidate == 'parakeet':
                result.update(text=out['text'], words=out.get('wordTimings', []))
            else:
                result['segments'] = normalize_turns(out['segments'], m['durationSeconds'])
            result['runtimeRevision'] = subprocess.check_output(['git', '-C', str(ROOT/'work/FluidAudio'), 'rev-parse', 'HEAD'], text=True).strip()
        else:
            from pyannote.audio import Pipeline
            pipe = Pipeline.from_pretrained('pyannote/speaker-diarization-community-1', token=os.environ.get('HF_TOKEN'))
            out = pipe(str(audio))
            result['task'] = 'diarization'
            result['segments'] = [{'start': t.start, 'end': t.end, 'speaker': speaker}
                                  for t, speaker in out.speaker_diarization]
        result['status'] = 'completed'
    except Exception as e:
        result.update(status='failed', errorType=type(e).__name__, error=str(e))
    result['wallSeconds'] = time.monotonic() - started
    result['peakRssBytes'] = max(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
                                 resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)
    # macOS ru_maxrss is bytes. GPU allocations are reported separately.
    try:
        import mlx.core as mx
        result['mlxPeakBytes'] = mx.get_peak_memory()
    except ImportError:
        pass
    tmp = args.output.with_suffix('.tmp')
    tmp.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    tmp.replace(args.output)
    print(json.dumps({k: result[k] for k in ['candidate', 'status', 'wallSeconds', 'peakRssBytes']}))
    return 0 if result['status'] == 'completed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
