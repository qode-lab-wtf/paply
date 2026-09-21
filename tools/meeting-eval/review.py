"""Create a private, self-contained audio/reference review page. No external requests."""
import argparse
import base64
import copy
import html
import json
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('manifest', type=Path)
    p.add_argument('--asr', type=Path, required=True)
    p.add_argument('--diarization', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    manifest = json.loads(args.manifest.read_text())
    asr = json.loads(args.asr.read_text())
    diar = json.loads(args.diarization.read_text())
    if any(x.get('audioSha256') != manifest['audioSha256'] or x.get('status') != 'completed' for x in (asr, diar)):
        raise ValueError('Successful results for the identical audio are required')
    m = copy.deepcopy(manifest)
    m['reference'] = {'reviewed': False, 'reviewer': None, 'text': asr['text'],
                      'segments': diar['segments'], 'draftSources': [asr['candidate'], diar['candidate']]}
    data = json.dumps(m, ensure_ascii=False).replace('<', '\\u003c')
    sound = base64.b64encode(Path(m['audio']).read_bytes()).decode()
    page = '''<!doctype html><html lang="de"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; media-src data:; connect-src 'none'">
<title>Paply – Hörprobe und Referenz</title>
<style>body{font:17px/1.5 system-ui;max-width:1000px;margin:32px auto;padding:0 20px;color:#17212b;background:#fafafa}h1{font-size:27px}section{background:white;border:1px solid #ddd;padding:20px;margin:20px 0;border-radius:8px}audio,textarea{width:100%}textarea{min-height:200px;box-sizing:border-box;font:inherit}input,select,button{font:inherit;padding:7px}button{cursor:pointer}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:6px;border-bottom:1px solid #ddd}td input{width:110px}.notice{background:#fff4cc;padding:15px}.muted{color:#56616d}</style>
<h1>Paply – eine echte Aufnahme zum Nachprüfen</h1>
<p class="notice"><strong>Modellvorschläge, noch keine bestätigte Referenz.</strong> Diese Seite funktioniert vollständig lokal. Nichts wird hochgeladen.</p>
<section><h2>1. Hören</h2><audio id="audio" controls src="data:audio/wav;base64,__PAPLY_AUDIO__"></audio>
<p>Die Bezeichnungen A/B/C oder Sprecher 1/2/3 genügen. Namen sind nicht nötig.</p></section>
<section><h2>2. Wortlaut prüfen</h2><p>Fehlende oder falsche Wörter korrigieren, keine sprachliche Politur.</p><textarea id="text" aria-label="Referenztranskript"></textarea></section>
<section><h2>3. Sprecherwechsel prüfen</h2><p>Jede Zeile ist ein vorgeschlagener Abschnitt. Überlappungen dürfen mehrere Zeilen zur selben Zeit haben.</p>
<table><thead><tr><th>Abspielen</th><th>Start (s)</th><th>Ende (s)</th><th>Sprecher</th><th>Aktion</th></tr></thead><tbody id="rows"></tbody></table><button id="add">Abschnitt hinzufügen</button></section>
<section><h2>4. Referenz speichern</h2><label>Gesprächsart <select id="scenario"><option value="unclassified">Noch unbekannt</option value="room">Gemeinsam im Raum</option><option value="call">Telefonat</option><option value="hybrid">Telefonat und Personen im Raum</option></select></label>
<p><label>Geprüft von <input id="reviewer" placeholder="z. B. Allan"></label></p>
<p><label><input type="checkbox" id="confirmed"> Ich habe Wortlaut und Sprecherwechsel am Audio geprüft.</label></p>
<button id="save">Referenzdatei herunterladen</button><p id="status" role="status"></p>
<p class="muted">Das Speichern ändert die installierte App nicht. Die heruntergeladene Datei enthält Gesprächsinhalte und gehört nicht auf GitHub.</p></section>
<script>
const manifest=__PAPLY_REFERENCE__, segments=manifest.reference.segments;
const $=id=>document.getElementById(id); $('text').value=manifest.reference.text;
function render(){ $('rows').replaceChildren(); segments.forEach((s,i)=>{
 const row=document.createElement('tr'), play=document.createElement('button');play.textContent='Anhören';play.onclick=()=>{$('audio').currentTime=s.start;$('audio').play()};const td=document.createElement('td');td.append(play);row.append(td);
 for(const key of ['start','end','speaker']){const cell=document.createElement('td'),input=document.createElement('input');input.value=s[key];input.setAttribute('aria-label',key+' Abschnitt '+(i+1));if(key!=='speaker'){input.type='number';input.step='0.01';input.min=0}input.onchange=()=>{s[key]=key==='speaker'?input.value:Number(input.value)};cell.append(input);row.append(cell)}
 const cell=document.createElement('td'),del=document.createElement('button');del.textContent='Entfernen';del.onclick=()=>{segments.splice(i,1);render()};cell.append(del);row.append(cell);$('rows').append(row);
 });}render();
$('add').onclick=()=>{segments.push({start:$('audio').currentTime,end:Math.min(manifest.durationSeconds,$('audio').currentTime+1),speaker:'neu'});render()};
$('save').onclick=()=>{if(!$('confirmed').checked||!$('reviewer').value.trim()){ $('status').textContent='Bitte erst prüfen und den Prüfernamen eintragen.';return }
 if(segments.some(s=>!Number.isFinite(s.start)||!Number.isFinite(s.end)||s.start<0||s.end<=s.start||s.end>manifest.durationSeconds||!s.speaker.trim())){$('status').textContent='Bitte ungültige Zeitangaben oder leere Sprecher korrigieren.';return}
 manifest.scenario=$('scenario').value;manifest.reference={reviewed:true,reviewer:$('reviewer').value.trim(),reviewedAt:new Date().toISOString(),text:$('text').value,segments:[...segments].sort((a,b)=>a.start-b.start)};
 const u=URL.createObjectURL(new Blob([JSON.stringify(manifest,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=u;a.download=manifest.id+'-reviewed.json';a.click();setTimeout(()=>URL.revokeObjectURL(u),1000);$('status').textContent='Referenzdatei erstellt. Noch keine Freigabe der App.';};
</script></html>'''
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(page.replace('__PAPLY_REFERENCE__', data, 1).replace('__PAPLY_AUDIO__', sound, 1))
    print(str(args.output))


if __name__ == '__main__':
    main()
