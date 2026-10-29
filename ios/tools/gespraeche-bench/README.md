# Gespräche: reproduzierbarer Pilotbenchmark

Keine App-Integration. Stand und Grenzen: `../../docs/gespraeche/MESSUNG.md`.
Alle Modelle, Audiodaten, venv und Buildprodukte liegen in `~/paply-gsp-bench/`.
Vor Downloads `df -h /System/Volumes/Data`; Gesamtbudget 4 GB. `fetch.py` prüft
vor und während Downloads. Swift-Modelldownloads separat mit `du -sh` überwachen.

```sh
mkdir -p ~/paply-gsp-bench/{data,models,results,cache}
python3 -m venv ~/paply-gsp-bench/venv
~/paply-gsp-bench/venv/bin/pip --no-cache-dir install -r requirements.txt
git clone https://github.com/FluidInference/FluidAudio.git ~/paply-gsp-bench/FluidAudio
git -C ~/paply-gsp-bench/FluidAudio checkout e15287985625dbf544a343df679436789ffb03fb
swift build --package-path FluidBench --scratch-path ~/paply-gsp-bench/swift-build --cache-path ~/paply-gsp-bench/cache/swift -c release -j 2
~/paply-gsp-bench/venv/bin/python fetch.py
(cd ~/paply-gsp-bench/models && tar -xjf segmentation.tar.bz2)
~/paply-gsp-bench/venv/bin/python test_metrics.py
~/paply-gsp-bench/venv/bin/python run_ami.py
~/paply-gsp-bench/venv/bin/python german.py
# Sendet bis zu 50 min deutsche Simulationen an Groq, explizit nur large-v3:
~/paply-gsp-bench/venv/bin/python run_german.py
~/paply-gsp-bench/venv/bin/python owner.py
~/paply-gsp-bench/venv/bin/python ami_owner.py
```

Aufrufe aus diesem Verzeichnis. ffmpeg muss im PATH sein. Für Zeitmessungen alle
Inferenzläufe **seriell** und ohne andere rechenintensive Prozesse ausführen.
Das vorliegende Pilotprotokoll enthält auch Läufe unter Konkurrenzlast.

Einzelmessung sherpa:

```sh
~/paply-gsp-bench/venv/bin/python bench.py ES2004a --model ~/paply-gsp-bench/models/wespeaker_en_voxceleb_resnet34_LM.onnx --speakers 4
```

`--speakers -1 --threshold 0.7` ist nur die problematische Kontrollvariante.
Vier bekannte Sprecher auf AMI sind eine Oracle-Ablation, keine Meeting-Automatik.
`refine.py hypothesis.json audio.wav embedding.onnx [K]` testet eine experimentelle
spektrale Nachgruppierung. Nicht für die App empfohlen ohne unabhängige Kalibrierung.

Swift-CLI: `FluidBench AUDIO OUTPUT MODELS [N] [STEP]` für Community-1;
`FluidBench AUDIO OUTPUT MODELS nemotron [PRESET]` für Nemotron-3, Standard
`c128-split-w8a8`; FP16-Vergleich `fast128`. Ein frischer Prozess je Peak-RAM-Messung:
`/usr/bin/time -l ...`. Zeiten in JSON trennen Laden und eigentliche Verarbeitung.

`groq.py FILE.flac`: SHA256-Cache, Dateigröße ≤25 MB, 16 kHz mono,
Gesamtreservierung ≤5400 s. Prozesssperre und dauerhafte Reservierung verhindern
Doppelsendungen auch nach Absturz. 429 stoppt die Batch ohne Retry-Schleife;
`Retry-After` steht im Ledger. Bei unklarem Netzwerkfehler nicht erneut senden.
Schlüssel wird nur im Prozess aus der erlaubten lokalen Konfiguration gelesen.
Keine Schlüssel im Repo oder Ergebnisdateien. Cache und Ledger behalten!

## Messdefinitionen

- AMI: echte Array1-01-WAVs; manuelle Wörter v1.6.2, keine Whisper-Aufrufe.
- DER/JER: pyannote.metrics, Collar 0,25 s, Overlap eingeschlossen, ganze Datei.
- WDER: falsche oder unbekannte Sprecher / Referenzwörter, optimale globale
  Eins-zu-eins-Zuordnung per Hungarian-Verfahren. Keine ASR-WER.
- Satzfehler: mindestens ein falsch/unbekannt zugeordnetes Wort im Referenzsegment;
  zusätzlich Mehrheitsfehler. AMI-Segmente aus Sprecher, Satzzeichen und >0,8 s Pause.
  Das sind **Satz-Proxys**, keine manuell geprüften grammatischen Sätze.
- Glättung sieht nur Wörter, Zeiten und Satzzeichen, niemals Referenzsprecher oder
  Referenzsatz-IDs. Dominanz ≥70 %, nur Wortentscheidungen mit Evidenz <0,6 ändern.
- Deutsch: zehn 5-min-Mischungen aus MLS-Testclips; erster Dreierblock je Person
  für Enrollment reserviert. Wiederverwendete Lesesprachclips sind keine unabhängigen
  Gespräche. DER/JER verwenden hier **ASR-Zeitproxies**, keine echte Wortzeit-Wahrheit.
  Mehrdeutige Überlappungswörter werden gezählt und aus dem deutschen WDER ausgeschlossen.
  ASR-Auslassungen/-Substitutionen werden nicht lexikalisch gegen den Quelltext aligniert.
  Deshalb deutsche WDER nicht direkt mit AMI vergleichen.
- Keine behauptete Kalibrierung: Ownerscores werden über mehrere Schwellen ausgewertet;
  dieselben wenigen Personen dürfen keine Produktionsschwelle begründen.

Modelle sind durch Dateihashes im Ergebnismanifest dokumentiert. Upstream kann
Modelle unter denselben Namen ändern; bei abweichenden Hashes separat auswerten.
Nach Abschluss nur selbst angelegte Daten, Build, venv, Checkout und Caches unter
`~/paply-gsp-bench/` löschen; kleine Ergebnisse/Cache-Ledger und Modelle behalten.

Zusatzprüfungen: `run_fp16.py`, `enrollment_outliers.py`, `short_turns.py`.
`owner.py MODEL.onnx ENGINE` erlaubt CAM++-Profile auf `nemotron-fp16`-Clustern;
`ami_owner.py --cam` ist der AMI-Vergleich mit CAM++.
`FluidBench AUDIO OUTPUT MODELS nemotron fast128 all --stream` verarbeitet die
16-kHz-Monodatei in 10-s-Leseblöcken; `cpu` statt `all` erzwingt CPU.
`--short-turns` setzt die experimentelle minimale Ausgabedauer auf 50 statt 200 ms.
Für den finalen Scorer v4 `rescore_ami.py` und `score_german_existing.py` ausführen,
dann `summarize.py`. V4 vereinigt angrenzende Referenzwörter vor dem DER-Collar;
gegen offizielle AMI-RTTMs auf allen drei Meetings mit 0 Referenz-DER geprüft.

V4 vereinigt außerdem überlappende Hypothesen desselben Sprechers und enthält sich
bei Gleichstand mehrerer Sprecher. Sechs Scorer-Regressionsprüfungen bestanden.
`run_fp16.py --short-turns` erzeugt die 50-ms-Ablation; `refine_german.py` die
CAM++-Nachgruppierung. Fehlende geeignete Embeddings erhalten explizit das Original.
