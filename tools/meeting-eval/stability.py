"""Agreement of two acoustic predictions, never an accuracy/reference score."""
from metrics import validate_segments


def agreement(first, second, duration):
    import numpy as np
    from scipy.optimize import linear_sum_assignment
    validate_segments(first, duration)
    validate_segments(second, duration)
    left = sorted({s['speaker'] for s in first})
    right = sorted({s['speaker'] for s in second})
    weights = np.zeros((len(left), len(right)))
    points = sorted({0., duration, *(t for s in first + second for t in (s['start'], s['end']))})
    spans = []
    comparable = presence_difference = single_first = 0.
    for start, end in zip(points, points[1:]):
        mid = (start + end) / 2
        a = {s['speaker'] for s in first if s['start'] <= mid < s['end']}
        b = {s['speaker'] for s in second if s['start'] <= mid < s['end']}
        seconds = end - start
        if len(a) == 1: single_first += seconds
        if bool(a) != bool(b): presence_difference += seconds
        if len(a) == len(b) == 1:
            aa, bb = next(iter(a)), next(iter(b))
            weights[left.index(aa), right.index(bb)] += seconds
            comparable += seconds
            spans.append((start, end, aa, bb))
    rows, cols = linear_sum_assignment(-weights)
    mapping = {right[c]: left[r] for r, c in zip(rows, cols)}
    disagreements = []
    for start, end, a, b in spans:
        if mapping.get(b) == a: continue
        if disagreements and abs(disagreements[-1]['end'] - start) < 1e-9:
            disagreements[-1]['end'] = end
        else: disagreements.append({'start': start, 'end': end})
    return {'comparableSeconds': comparable,
            'mappedAgreement': float(weights[rows, cols].sum()) / comparable if comparable else None,
            'singleVoiceFirstSeconds': single_first,
            'speechPresenceDisagreementSeconds': presence_difference,
            'disagreementIntervals': disagreements,
            'isAccuracy': False, 'qualityApproved': False}
