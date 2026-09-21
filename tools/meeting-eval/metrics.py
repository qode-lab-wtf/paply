"""Quality metrics. Never use model output as a reviewed reference.

Speaker score: optimal one-to-one label mapping, exact interval integration,
no forgiveness collar. Reference overlap/unintelligible regions are excluded
and reported separately. False positive speech is reported separately.
"""
import math
import re
import unicodedata


def words(text):
    return re.findall(r"\w+", unicodedata.normalize('NFKC', text).casefold())


def word_error_rate(reference, hypothesis):
    ref, hyp = words(reference), words(hypothesis)
    if not ref:
        return {'wer': None, 'referenceWords': 0, 'errors': len(hyp)}
    prev = list(range(len(hyp) + 1))
    for i, a in enumerate(ref, 1):
        row = [i]
        for j, b in enumerate(hyp, 1):
            row.append(min(row[-1] + 1, prev[j] + 1, prev[j-1] + (a != b)))
        prev = row
    return {'wer': prev[-1] / len(ref), 'referenceWords': len(ref), 'errors': prev[-1]}


def validate_segments(segments, duration):
    for s in segments:
        if not (isinstance(s.get('speaker'), str) and s['speaker']):
            raise ValueError('Missing speaker label')
        a, b = s.get('start'), s.get('end')
        if (not isinstance(a, (float, int)) or not isinstance(b, (float, int))
                or not math.isfinite(a) or not math.isfinite(b)
                or not 0 <= a < b <= duration + 0.001):
            raise ValueError('Invalid segment time')


def speaker_accuracy(reference, hypothesis, duration):
    from scipy.optimize import linear_sum_assignment
    import numpy as np
    validate_segments(reference, duration)
    validate_segments(hypothesis, duration)
    refs = sorted({s['speaker'] for s in reference})
    hyps = sorted({s['speaker'] for s in hypothesis})
    weights = np.zeros((len(refs), len(hyps)))
    boundaries = sorted({0.0, duration} | {s[k] for s in reference + hypothesis for k in ('start', 'end')})
    evaluated = overlap = excluded = false_positive = 0.0
    for a, b in zip(boundaries, boundaries[1:]):
        t, dt = (a + b) / 2, b - a
        rr = [s for s in reference if s['start'] <= t < s['end']]
        hh = {s['speaker'] for s in hypothesis if s['start'] <= t < s['end']}
        labels = {s['speaker'] for s in rr}
        if any(s.get('unintelligible', False) for s in rr):
            excluded += dt
        elif len(labels) > 1:
            overlap += dt
        elif len(labels) == 1:
            evaluated += dt
            # Multiple hypothesis speakers during single-speaker reference are wrong.
            if len(hh) == 1:
                weights[refs.index(next(iter(labels))), hyps.index(next(iter(hh)))] += dt
        elif hh:
            false_positive += dt
    rows, cols = linear_sum_assignment(-weights)
    correct = float(weights[rows, cols].sum())
    return {'accuracy': correct / evaluated if evaluated else None,
            'evaluatedSeconds': evaluated, 'correctSeconds': correct,
            'overlapSeconds': overlap, 'unintelligibleSeconds': excluded,
            'falsePositiveSeconds': false_positive,
            'mapping': {hyps[c]: refs[r] for r, c in zip(rows, cols)}}


def score(manifest, prediction):
    ref = manifest.get('reference', {})
    if not ref.get('reviewed') or not ref.get('reviewer'):
        return {'status': 'unreviewed', 'passed': False, 'reason': 'Human reference required'}
    if prediction.get('audioSha256') != manifest.get('audioSha256'):
        raise ValueError('Prediction and reference are not the same audio')
    task = prediction.get('task')
    if task == 'asr':
        if not isinstance(ref.get('text'), str):
            return {'status': 'missing-reference-text', 'passed': False}
        m = word_error_rate(ref['text'], prediction['text'])
        return {'status': 'scored', 'passed': m['wer'] is not None and m['wer'] <= .10, **m}
    if task == 'diarization':
        m = speaker_accuracy(ref.get('segments', []), prediction['segments'], manifest['durationSeconds'])
        return {'status': 'scored', 'passed': m['accuracy'] is not None and m['accuracy'] >= .95, **m}
    raise ValueError('Unsupported task')
