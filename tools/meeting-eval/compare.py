"""Private, self-contained listening comparison; never labels a model as correct."""
import argparse
import base64
import hashlib
import html
import json
from pathlib import Path


def render(manifest, results):
    audio = Path(manifest['audio'])
    data = audio.read_bytes()
    if hashlib.sha256(data).hexdigest() != manifest['audioSha256']:
        raise ValueError('Audio hash mismatch')
    cards = []
    for result in results:
        if result.get('audioSha256') != manifest['audioSha256']:
            raise ValueError('Result belongs to different audio')
        name = html.escape(result['candidate'])
        if result.get('status') != 'completed':
            body = '<p>Verarbeitung fehlgeschlagen.</p>'
        elif result.get('task') == 'diarization':
            rows = []
            for s in result.get('segments', []):
                rows.append('<tr><td>%.2f–%.2f s</td><td>%s</td></tr>' %
                            (s['start'], s['end'], html.escape(s['speaker'])))
            body = '<table><tr><th>Zeit</th><th>Modell-Zuordnung</th></tr>' + ''.join(rows) + '</table>'
        else:
            body = '<p class="transcript">' + html.escape(result.get('text', '')) + '</p>'
        cards.append('<article><h2>' + name + '</h2>' + body + '</article>')
    return '''<!doctype html><html lang="de"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; media-src data:; style-src 'unsafe-inline'">
<title>Paply – lokaler Modellvergleich</title>
<style>body{font:17px/1.6 system-ui;margin:32px auto;padding:0 20px;max-width:1050px;color:#202b35;background:#f5f6f8}article{background:white;padding:24px;margin:20px 0;border-radius:12px}h1{line-height:1.2}h2{font-size:21px}audio{width:100%}table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:6px;border-bottom:1px solid #ddd}.transcript{white-space:pre-wrap}.notice{border-left:4px solid #bd7700;padding:12px;background:#fff5de}</style>
<h1>Paply · vorhandene Aufnahme im Vergleich</h1>
<p class="notice">Ungeprüfte Modellergebnisse, kein fertiges Transkript. Unterschiedliche Sprecher-IDs sind je Modell unabhängig. Die tatsächliche Zahl der Beteiligten und mögliche Hintergrundstimmen sind nicht bestätigt. Dieser Vergleich erteilt keine Qualitätsfreigabe.</p>
<p>Aufnahme: ''' + html.escape(manifest['id']) + ''' · ''' + str(manifest['durationSeconds']) + ''' Sekunden</p>
<audio controls preload="metadata" src="data:audio/wav;base64,''' + base64.b64encode(data).decode() + '''"></audio>
''' + ''.join(cards) + '</html>'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('results', nargs='+', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    if output.is_relative_to(root) and not output.is_relative_to(root/'work'):
        raise ValueError('Private comparison must not be written into tracked project')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render(json.loads(args.manifest.read_text()),
                             [json.loads(p.read_text()) for p in args.results]))


if __name__ == '__main__':
    main()
