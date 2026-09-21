"""Compare local report models on the SAME saved transcript, no cloud fallback.

The response is an unverified candidate, not a factuality score.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import urllib.request
from jsonschema import ValidationError

ROOT = Path(__file__).resolve().parents[2]
def claim_schema(properties):
    fields = {**properties, 'sourceIds': {'type': 'array', 'items': {'type': 'string', 'enum': ['segment-1']}, 'minItems': 1},
              'sourceQuote': {'type': 'string', 'minLength': 1}}
    return {'type': 'object', 'properties': fields, 'required': list(fields), 'additionalProperties': False}


REPORT_SCHEMA = {'type': 'object', 'properties': {
    'overview': {'type': 'string'},
    'topics': {'type': 'array', 'items': claim_schema({'title': {'type': 'string'}, 'explanation': {'type': 'string'}})},
    'decisions': {'type': 'array', 'items': claim_schema({'text': {'type': 'string'}})},
    'tasks': {'type': 'array', 'items': claim_schema({'text': {'type': 'string'}, 'owner': {'type': ['string', 'null']}})},
    'openQuestions': {'type': 'array', 'items': claim_schema({'text': {'type': 'string'}})},
}, 'required': ['overview', 'topics', 'decisions', 'tasks', 'openQuestions'], 'additionalProperties': False}
SYSTEM = '''Du protokollierst ein deutsches Gespräch. Verwende ausschließlich den gelieferten Inhalt.
Erfinde keine Namen, Zahlen, Verantwortlichen, Beschlüsse oder Zusammenhänge.
Unterscheide Aussagen, Vorschläge, Entscheidungen und offene Fragen.
Schreibe verständlich und dem Informationsgehalt angemessen ausführlich.
Jede inhaltliche Aussage muss sourceIds der gelieferten Textstellen nennen.
Jeder Eintrag braucht zusätzlich sourceQuote: einen wortwörtlich kopierten zusammenhängenden
Beleg aus dem Transkript. Der Beleg muss gerade diese Aussage unterstützen.
Unterscheide sorgfältig: Wer soll jemanden anrufen und wer soll angerufen werden?
Wer beschafft etwas für jemanden und wer erhält es? Namen nicht aus mehrdeutigen Pronomen ableiten.
Bei unklarem Bezug schreibe ausdrücklich "Zuordnung unklar" statt einen Namen einzusetzen.
Antworte als JSON mit overview (string), topics (Array aus title, explanation, sourceIds),
decisions (Array aus text, sourceIds), tasks (Array aus text, owner oder null, sourceIds),
openQuestions (Array aus text, sourceIds). Keine Entscheidung oder Aufgabe erfinden,
wenn nur eine Möglichkeit besprochen wurde. Leere Listen sind erlaubt.'''


def validate_report(report, text, done_reason):
    if done_reason == 'length':
        raise ValueError('Truncated report')
    if not isinstance(report, dict) or not isinstance(report.get('overview'), str):
        raise ValueError('Missing overview')
    for section, fields in [('topics', ['title', 'explanation']), ('decisions', ['text']),
                            ('tasks', ['text']), ('openQuestions', ['text'])]:
        if not isinstance(report.get(section), list):
            raise ValueError('Missing report section: '+section)
        for claim in report[section]:
            if not isinstance(claim, dict) or claim.get('sourceIds') != ['segment-1']:
                raise ValueError('Missing or invalid source reference')
            if any(not isinstance(claim.get(f), str) for f in fields):
                raise ValueError('Invalid claim text')
            if section == 'tasks' and ('owner' not in claim or not isinstance(claim['owner'], (str, type(None)))):
                raise ValueError('Invalid task owner')
            quote = claim.get('sourceQuote')
            if not isinstance(quote, str) or not quote.strip() or quote not in text:
                raise ValueError('Source quotation is not an exact substring')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('model', choices=['gemma3:4b', 'qwen3:8b'])
    p.add_argument('transcript', type=Path)
    p.add_argument('output', type=Path)
    p.add_argument('--thinking', action='store_true')
    p.add_argument('--evidence-v2', action='store_true')
    a = p.parse_args()
    a.output.resolve().relative_to(ROOT/'work')
    t = json.loads(a.transcript.read_text())
    # This benchmark uses short samples. Production long-form chunking is gated.
    text = t['text']
    if len(text) > 20000:
        raise ValueError('Benchmark sample too long; do not silently truncate')
    sources = None
    report_schema, system, user_text = REPORT_SCHEMA, SYSTEM, '[segment-1]\n' + text
    if a.evidence_v2:
        import report_evidence as evidence
        sources = evidence.build_sources(t)
        report_schema, system, user_text = evidence.schema(sources), evidence.SYSTEM, json.dumps(sources, ensure_ascii=False)
    request = {'model': a.model, 'stream': False, 'think': a.thinking, 'format': report_schema,
               'keep_alive': 0, 'options': {'temperature': 0, 'num_ctx': 16384, 'num_predict': 8192 if a.thinking else 4096},
               'messages': [{'role': 'system', 'content': system},
                            {'role': 'user', 'content': user_text}]}
    start = time.monotonic()
    req = urllib.request.Request('http://127.0.0.1:11435/api/chat', data=json.dumps(request).encode(),
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=600) as response:
        data = json.load(response)
    output = {'model': a.model, 'inputSha256': hashlib.sha256(text.encode()).hexdigest(),
              'wallSeconds': time.monotonic()-start, 'humanReviewed': False, 'thinking': a.thinking,
              'evidenceVersion': 2 if a.evidence_v2 else 1, 'sources': sources, 'doneReason': data.get('done_reason'), 'raw': data['message']['content']}
    try:
        report = json.loads(output['raw'])
        if a.evidence_v2:
            report = evidence.validate_and_attach(report, sources, data.get('done_reason'))
        else:
            validate_report(report, text, data.get('done_reason'))
        output.update(status='schema-valid-unreviewed', report=report)
    except (ValueError, TypeError, ValidationError) as e:
        output.update(status='invalid', error=str(e))
    a.output.write_text(json.dumps(output, ensure_ascii=False, indent=2))
    print(json.dumps({k: output[k] for k in ['model', 'status', 'wallSeconds']}))


if __name__ == '__main__':
    main()
