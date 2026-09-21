"""Join candidate word times and speaker intervals without dropping overlapping words."""
import argparse
import base64
import hashlib
import html
import json
from pathlib import Path


def assign_words(asr, diarization):
    labels = list(dict.fromkeys(s['speaker'] for s in sorted(diarization, key=lambda s: s['start'])))
    names = {label: f'Sprecher {i+1}' for i,label in enumerate(labels)}
    result=[]
    for segment in asr['segments']:
        words=segment.get('words', [])
        # Preserve original text even if a model omitted words from its alignment.
        if ''.join(w['word'] for w in words).split() != segment['text'].split():
            result.append({'start':segment['start'],'end':segment['end'],'text':segment['text'],
                           'speaker':'Zuordnung unklar (Wortzeiten unvollständig)'})
            continue
        for w in words:
            start,end=w['start'],w['end']; span=end-start
            candidates={}
            for label in labels:
                # Union, so overlapping intervals from one speaker cannot inflate confidence.
                intervals=sorted((max(start,s['start']),min(end,s['end'])) for s in diarization if s['speaker']==label and s['start']<end and s['end']>start)
                coverage=0; previous=start
                for a,b in intervals:
                    coverage+=max(0,b-max(a,previous));previous=max(previous,b)
                if coverage>0: candidates[label]=coverage/max(span,0.001)
            ranked=sorted(candidates,key=candidates.get,reverse=True)
            if span>0 and ranked and candidates[ranked[0]]>=.6 and (len(ranked)==1 or candidates[ranked[1]]<.2):
                speaker=names[ranked[0]]
            else:
                speaker='Zuordnung unklar' + (' / Überlappung: '+', '.join(names[k] for k in ranked) if len(ranked)>1 else '')
            result.append({'start':start,'end':end,'text':w['word'],'speaker':speaker})
    return result


def render(manifest,asr,candidates):
    data=Path(manifest['audio']).read_bytes()
    if hashlib.sha256(data).hexdigest()!=manifest['audioSha256']: raise ValueError('Audio mismatch')
    blocks=[]
    for d in candidates:
        if d.get('status')!='completed' or d.get('audioSha256')!=manifest['audioSha256'] or asr.get('audioSha256')!=manifest['audioSha256']:
            raise ValueError('Invalid model result or mismatched audio')
        assigned=assign_words(asr,d['segments']); groups=[]
        for w in assigned:
            if groups and groups[-1]['speaker']==w['speaker'] and w['start']-groups[-1]['end']<1.0:
                groups[-1]['text']+=w['text'];groups[-1]['end']=w['end']
            else:groups.append(dict(w))
        rows=[]
        for g in groups:
            rows.append(f'<p><button data-start="{max(0,g["start"]-.25):.3f}">{g["start"]:.1f} s ▶</button> <strong>{html.escape(g["speaker"])}</strong><br>{html.escape(g["text"])}</p>')
        missing=[s for s in d['segments'] if not any(w['start']<s['end'] and w['end']>s['start'] for w in assigned)]
        notes=''.join(f'<li>{s["start"]:.2f}–{s["end"]:.2f} s: Stimme markiert, aber kein zeitlich zugehöriger Text erkannt.</li>' for s in missing)
        blocks.append('<article><h2>'+html.escape(d['candidate'])+'</h2>'+''.join(rows)+'<ul>'+notes+'</ul></article>')
    return '''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; media-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<title>Paply – wer sagt welchen Satz?</title><style>body{font:17px/1.55 system-ui;max-width:1100px;margin:30px auto;padding:0 20px;background:#f5f6f8;color:#25313b}.columns{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:20px}article{background:white;padding:20px;border-radius:12px}button{cursor:pointer}audio{width:100%}.notice{background:#fff0cc;padding:16px}li{margin:10px 0}</style>
<h1>Wer sagt welchen Satz?</h1><p class="notice">Vorläufiger Vergleich: gleicher Whisper-Text, zwei unterschiedliche Sprecheranalysen. Sprecher 1/2 sind je Spalte eigene Kennungen, keine bestätigten Namen. Unsichere Wortgrenzen und Überlappungen bleiben sichtbar. Kein Wort wird als Echo gelöscht. Dies ist noch keine Paply-Testversion.</p>
<audio id="audio" controls src="data:audio/wav;base64,'''+base64.b64encode(data).decode()+'''"></audio><div class="columns">'''+''.join(blocks)+'''</div><script>document.querySelectorAll('button[data-start]').forEach(b=>b.onclick=()=>{const a=document.getElementById('audio');a.currentTime=Number(b.dataset.start);a.play();});</script></html>'''


def main():
    p=argparse.ArgumentParser();p.add_argument('manifest',type=Path);p.add_argument('asr',type=Path);p.add_argument('diarizations',type=Path,nargs='+');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    root=Path(__file__).resolve().parents[2];out=a.output.resolve()
    if out.is_relative_to(root) and not out.is_relative_to(root/'work'):raise ValueError('Private output must not be tracked')
    out.write_text(render(json.loads(a.manifest.read_text()),json.loads(a.asr.read_text()),[json.loads(p.read_text()) for p in a.diarizations]))


if __name__=='__main__':main()
