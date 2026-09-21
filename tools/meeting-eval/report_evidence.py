"""Evidence-linked reporting experiment. Source text is attached by code, never invented by LLM."""
import hashlib
import json


def build_sources(transcript):
    if transcript.get('status') != 'completed' or not transcript.get('text', '').strip():
        raise ValueError('Completed nonempty ASR required')
    segments = transcript.get('segments') or [{'text': transcript['text']}]
    if ''.join(''.join(s.get('text', '').split()) for s in segments) != ''.join(transcript['text'].split()):
        raise ValueError('Segment text does not cover full transcript')
    sources = []
    for i, s in enumerate(segments):
        if not s['text'].strip():
            continue
        material = json.dumps([transcript.get('audioSha256'), i, s.get('start'), s.get('end'), s['text']], ensure_ascii=False)
        sources.append({'id': 's-' + hashlib.sha256(material.encode()).hexdigest()[:16],
                        'start': s.get('start'), 'end': s.get('end'), 'text': s['text']})
    return sources


def schema(sources):
    def claim(fields):
        props = {**fields, 'sourceIds': {'type': 'array', 'minItems': 1, 'uniqueItems': True,
                                       'items': {'type': 'string', 'enum': [s['id'] for s in sources]}}}
        return {'type': 'object', 'properties': props, 'required': list(props), 'additionalProperties': False}
    text = {'type': 'string', 'minLength': 1}
    props = {'overview': claim({'text': text}),
             'topics': {'type': 'array', 'items': claim({'title': text, 'explanation': text})},
             'decisions': {'type': 'array', 'items': claim({'text': text})},
             'tasks': {'type': 'array', 'items': claim({'text': text, 'owner': {'type': ['string', 'null']}})},
             'openQuestions': {'type': 'array', 'items': claim({'text': text})}}
    return {'type': 'object', 'properties': props, 'required': list(props), 'additionalProperties': False}


SYSTEM = '''Erstelle einen sachlichen deutschen Gesprächsbericht ausschließlich aus den gelieferten Textstellen.
Die Textstellen sind ungeprüfte automatische Transkription; Sprecher und Pronomenbezüge sind nicht bestätigt.
Keinen Sprecher aus dem Text erraten. Bei unklarem Verantwortlichen owner=null setzen und Unklarheit benennen.
Themen angemessen ausführlich erklären, unterschiedliche Standpunkte erhalten. Zahlen, Bedingungen und
Gegenpositionen nicht weglassen. Aufgaben, ausdrücklich getroffene Entscheidungen und offene Fragen trennen.
Keine neuen Ratschläge, Fragen, Vereinbarungen oder Termine ergänzen. Beschaffung, Empfänger, Anrufer und
Angerufenen nicht verwechseln. Mehrdeutige Namen nicht normalisieren oder ergänzen.
Jede Aussage einschließlich overview braucht die IDs genau der Textstellen, die ihren Inhalt tragen.
Gib nur das geforderte JSON aus. Quellenzitate werden danach unverändert aus den referenzierten Stellen
angefügt; schreibe selbst keine Zitate. Leere Listen sind erlaubt.''' 


def validate_and_attach(report, sources, done_reason):
    if done_reason != 'stop':
        raise ValueError('Report did not finish normally')
    from jsonschema import Draft202012Validator
    Draft202012Validator(schema(sources)).validate(report)
    by_id = {s['id']: s for s in sources}
    linked = json.loads(json.dumps(report))
    for claim in [linked['overview']] + [c for name in ('topics','decisions','tasks','openQuestions') for c in linked[name]]:
        claim['sources'] = [by_id[sid] for sid in claim['sourceIds']]
    return linked
