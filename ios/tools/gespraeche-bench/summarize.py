from fetch import ROOT
from pathlib import Path
import json,csv,hashlib,subprocess
from collections import defaultdict
out=Path(__file__).resolve().parent/'results'
out.mkdir(exist_ok=True)
rows=[json.loads(p.read_text()) for p in (ROOT/'results').glob('*-metrics.json')]
keys=sorted(set().union(*(r.keys() for r in rows)))
with (out/'messwerte.csv').open('w') as f:
 writer=csv.DictWriter(f,fieldnames=keys);writer.writeheader();writer.writerows(rows)
groups=defaultdict(list)
for r in rows:
 if not r['smooth']:continue
 if 'condition' in r:condition=r['condition'].rsplit('-',1)[0];engine=r['engine']
 else:condition=r['meeting'];engine=r['engine'].removeprefix(condition+'-')
 groups[condition,engine].append(r)
lines=['| Bedingung | Motor / Variante | n | WDER % | Segmentfehler % | DER % | JER % | ΔK | RTF |','|---|---|---:|---:|---:|---:|---:|---:|---:|']
for (cond,engine),rs in sorted(groups.items()):
 weighted=lambda key,den:sum(r[key]*r[den] for r in rs)/sum(r[den] for r in rs)
 der='Proxy' if 'condition' in rs[0] else f"{100*rs[0]['DER']:.1f}"
 jer='Proxy' if 'condition' in rs[0] else f"{100*rs[0]['JER']:.1f}"
 lines.append(f"| {cond} | {engine} | {len(rs)} | {100*weighted('WDER','words'):.1f} | {100*weighted('sentence_any_error','sentences'):.1f} | {der} | {jer} | {','.join(str(r['count_error']) for r in rs)} | {sum(r['rtf'] for r in rs)/len(rs):.3f} |")
(out/'ERGEBNISSE.md').write_text('# Pilotwerte – geglättete Variante\n\nKeine Produktionsfreigabe. Definitionen und Einschränkungen: [MESSUNG.md](../../../docs/gespraeche/MESSUNG.md).\n\n'+'\n'.join(lines)+'\n\nAlle Roh-/Glättungsvarianten: [messwerte.csv](messwerte.csv).\n')
manifest={}
for p in (ROOT/'models').rglob('*'):
 if p.is_file():manifest[str(p.relative_to(ROOT))]=dict(bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
(ROOT/'results/model-manifest.json').write_text(json.dumps(manifest,indent=2))
print('\n'.join(lines))
