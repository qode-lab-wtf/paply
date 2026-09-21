# Lokaler Meeting-Vergleich

Dieses Werkzeug prüft Modelle isoliert. Es verändert weder Paplys installierte App
noch deren Aufnahmen/Einstellungen und ruft keine Cloud-Transkriptions-API auf.
Modell-Downloads brauchen Internet; Inferenz und Prüfmaterial bleiben lokal.

## Laufzeit

Apple Silicon / Python 3.12.13. Installation im Repository:

```sh
uv venv work/venv --python 3.12.13
uv pip sync --python work/venv/bin/python tools/meeting-eval/requirements-macos.lock
git clone https://github.com/FluidInference/FluidAudio.git work/FluidAudio
git -C work/FluidAudio checkout 5343241cd8a7576890e50925dec666bafc89d324
cd work/FluidAudio
swift build -c release --product fluidaudiocli
```

Modelle vom Repository-Root laden (kein Audio wird übertragen):

```sh
work/venv/bin/hf download mlx-community/Qwen3-ASR-1.7B-4bit --revision 78a389c776a5483b2d0d4ea5494e11012e0d6159 --local-dir work/models/qwen3-asr
work/venv/bin/hf download mlx-community/whisper-large-v3-mlx --revision 49e6aa286ad60c14352c404340ded53710378a11 --local-dir work/models/whisper
```

FluidAudio lädt seine CoreML-Modelle beim ersten Lauf in den eigenen macOS-Cache.
Für spätere Produktionsintegration müssen auch diese Artefakte per Hash festgeschrieben
werden; ein beweglicher Download-Branch reicht nicht als Produktiv-Pin.
`inventory_models.py` erzeugt dafür ein lokales Hashinventar.

Originales pyannote Community-1 braucht eine persönliche Hugging-Face-Freigabe.
Kein Zugang: als blockiert ausweisen, nicht heimlich einen anderen Kandidaten so nennen.
Seine separate Python-Laufzeit ist absichtlich nicht Teil der MLX-Lockdatei:

```sh
uv venv work/pyannote-venv --python 3.12.13
uv pip sync --python work/pyannote-venv/bin/python tools/meeting-eval/requirements-pyannote.lock
```

Nach genehmigtem Download das vollständige Modell (config.yaml, embedding/,
segmentation/, plda/) unter `work/models/pyannote` ablegen. Der Worker lädt
ausschließlich diesen lokalen Ordner, deaktiviert pyannote-Telemetrie und decodiert
Audio mit soundfile. Keine Zugangsdaten in Argumente oder Git-Dateien schreiben.

## Private Referenz

Alles unter ignoriertem `work/`. Ein Manifest enthält:

```json
{
  "schemaVersion": 1,
  "id": "sample-a",
  "audio": "/absolute/path/to/work/sample.wav",
  "audioSha256": "sha256-of-file",
  "durationSeconds": 90,
  "scenario": "unclassified",
  "channel": "mic",
  "reference": {
    "reviewed": false,
    "reviewer": null,
    "text": null,
    "segments": []
  }
}
```

Referenzsegmente: `{ "start": 0, "end": 1.2, "speaker": "A" }`.
Sprecher-IDs sind pro Aufnahme konsistent; bei Überlappungen mehrere Segmente.
Unverständliche Spannen optional mit `unintelligible: true` kennzeichnen.
Die geprüfte Referenz muss die gesamte Datei abdecken, nicht nur ausgewählte Treffer.
Gesprächsart erst nach Prüfung als `room`, `call` oder `hybrid` setzen.
Ein generiertes Transkript oder bisheriges Paply-Ergebnis ist KEINE Referenz.

## Ausführen

Jeden Kandidaten nacheinander in frischem Prozess starten:

```sh
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 work/venv/bin/python tools/meeting-eval/run_model.py qwen-asr work/samples/conversation-a-mic.json work/results/qwen-a-mic.json
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 work/venv/bin/python tools/meeting-eval/run_model.py whisper work/samples/conversation-a-mic.json work/results/whisper-a-mic.json
work/venv/bin/python tools/meeting-eval/run_model.py parakeet work/samples/conversation-a-mic.json work/results/parakeet-a-mic.json
work/venv/bin/python tools/meeting-eval/run_model.py fluid-diarization work/samples/conversation-a-mic.json work/results/fluid-a-mic.json
work/venv/bin/python tools/meeting-eval/evaluate.py work/samples/conversation-a-mic.json work/results/qwen-a-mic.json
work/venv/bin/python -m unittest discover -s tools/meeting-eval -p 'test_*.py'
```

Zeitmessung umfasst Laden und ggf. Erstdownload, nicht nur Modell-Inferenz.
`peakRssBytes` ist der größte Einzelprozess-RSS-Wert, nicht gesamte Systemlast.
MLX-GPU-Speicher wird separat berichtet. Kalte und warme Läufe getrennt auswerten.
Qwen-ASR liefert hier zunächst nur Text: Wortausrichtung ist noch kein nachgewiesener
Teil dieser Variante. Keine erfundenen Wortzeitmarken daraus ableiten.

Für einen echten Offline-Nachweis unter macOS kann nach dem Download der Befehl
mit `/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)'` laufen.
Nur ein erfolgreicher netzgesperrter Lauf zählt als Offline-Beleg.

## Nachhören / Referenz bestätigen

```sh
work/venv/bin/python tools/meeting-eval/review.py work/samples/conversation-a-mic.json --asr work/results/whisper-a-mic.json --diarization work/results/fluid-a-mic.json --output work/review.html
```

Die Seite bettet das Audio ein, macht keine Netzaufrufe und erlaubt korrigierte
Referenzen als JSON herunterzuladen. Sie speichert keine Änderungen am Original.
Die Ausgabe enthält private Inhalte und darf nicht committed werden.

## Berichtsvergleich

`report.py` nutzt ausschließlich einen task-eigenen Ollama auf `127.0.0.1:11435`.
Zunächst dessen `OLLAMA_MODELS` auf ein eigenes Verzeichnis setzen, die Modelle
`gemma3:4b` und `qwen3:8b` bereitstellen und ihre Digests dokumentieren.
Beide Modelle bekommen denselben gespeicherten Text; automatische Bewertung prüft
nur Struktur/Quellen-IDs, NICHT die inhaltliche Richtigkeit.

```sh
work/venv/bin/python tools/meeting-eval/report.py gemma3:4b work/results/qwen-a-mic.json work/results/report-gemma-a.json
work/venv/bin/python tools/meeting-eval/report.py qwen3:8b work/results/qwen-a-mic.json work/results/report-qwen-a.json
```

Die aktuelle Fassung erzwingt zusätzlich wörtliche `sourceQuote`-Belege pro Eintrag;
der Validator verwirft erfundene Zitate, Quellen-IDs, fehlende Felder und abgeschnittene
Antworten. Mit `--thinking` Qwens Analysemodus separat vergleichen. Beide Modelle
müssen für einen Vergleich dieselbe Eingabedatei und Schemafassung bekommen.
Auch ein vorhandenes Zitat beweist nicht, dass die Interpretation korrekt ist.

## Freigabegrenze

`unreviewed` ist kein Erfolg. Leere Referenzen sind kein Erfolg. Dateihashes müssen
übereinstimmen. WER normalisiert Unicode/Großschreibung/Interpunktion, nicht Zahlen
oder Wortwahl. Sprecher-IDs werden optimal eins-zu-eins zugeordnet; fehlende Sprache
und zusätzliche gleichzeitige Sprecher zählen als Fehler. Überlappungen und falsche
Sprachaktivität werden separat ausgewiesen. Keine Zeit-Toleranz am Sprecherwechsel.

Ein bestandener Einzeltest gibt niemals die App frei. Die vollständigen Gates
einschließlich aller Gesprächsarten, Berichtstreue und App-Regression stehen in
`docs/PLAN.md`. Private Modelllogs/Referenzen verbleiben lokal; nur bereinigte
Messwerte und bekannte Lücken dürfen nach `docs/validation/` und GitHub.

## Vergleich ohne neue Aufnahme

`compare.py MANIFEST RESULT... --output work/comparison.html` stellt mehrere
Modelle mit demselben Audiodateihash nebeneinander. Sprecher-IDs gelten nur innerhalb
eines Ergebnisses, nicht modell- oder kanalübergreifend. Keine automatische Freigabe.

`node tools/meeting-eval/legacy_replay.js MIC_WHISPER_JSON SYSTEM_WHISPER_JSON`
misst den Eingriff der bisherigen zeitbasierten Echo-Unterdrückung auf den
Kandidatensegmenten. Unterdrückte Dauer ist keine bestätigte verlorene Gesprächsdauer.

## Verständliches Gespräch / Belegbericht v2

`conversation_preview.py MANIFEST WHISPER_JSON DIARIZATION_JSON... --output work/conversation.html`
erhält alle Wörter, zeigt unklare Zuordnungen und Stimmspannen ohne erkannten Text.
Die 60-Prozent-Abdeckung / 20-Prozent-Zweitstimmen-Grenze ist eine explizite
Darstellungsheuristik, keine validierte Sprecher-Pipeline.

`report.py ... --evidence-v2` verwendet Quellenstellen mit Zeitmarken statt einer
einzigen Gesamtreferenz. Belegzitate werden erst nach Schema-/ID-Prüfung aus
Originaltext eingefügt. Das verhindert erfundene Zitate, nicht falsche Interpretation.
Alte Berichtsfassung bleibt für reproduzierbare Vergleiche verfügbar.

## Raumtest: alternative Auswertung und Sprachaufbereitung

Separater Python-3.12-Vergleich, keine neue Standardauswahl für die produktive App:
`requirements-acoustic.lock` enthält faster-whisper 1.2.1 und ClearVoice 0.1.2.
Modelle und Revisionen stehen unter `acousticCandidates` in `models.lock.json`.
`run_model.py faster-whisper MANIFEST OUTPUT` nutzt CPU/int8, Beam 5, Silero-VAD,
Wortzeitmarken und keinen vorherigen Textkontext. Modellordner:
`work/models/faster-whisper-large-v3`. Kein Modell-Download im Worker.

`enhance_audio.py MANIFEST OUTPUT_MANIFEST` nutzt das lokale
`work/models/mossformer-gan` und denselben Aufbereitungscode wie die Test-App.
Es akzeptiert nur noch nicht abgelaufene neue Sitzungen. Der abgeleitete Ton bleibt
im Sitzungsordner und unterliegt dessen ursprünglicher Sieben-Tage-Frist.

Im Raumtest vom 21.09. verbesserte die Aufbereitung die automatisch gefundene
Sprecherzahl von zwei auf drei, verfälschte aber teils die ASR-Wörter. Deshalb nutzt
nur die **Sprecheranalyse** den aufbereiteten Mikrofonton. ASR und Wiedergabe behalten
den Originalton. Systemton bleibt unbearbeitet. Das ist eine experimentelle
Testkonfiguration; die Identitäts- und Wortfehlerraten sind noch nicht bestätigt.
