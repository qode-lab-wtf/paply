# Paply: lokaler Diktat-Benchmark

Node **22**, keine neuen Abhängigkeiten, kein Electron-Start, keine Änderungen am Diktat der App.
Alle folgenden Befehle ab `electron-menubar/` ausführen. Die App-Einstellungen werden nur gelesen.

## Eingaben und Start

Aufnahmen und gleichnamige Metadaten in einen Ordner **außerhalb des Repositorys** kopieren:

```text
/tmp/paply-bench/
  123.webm                # alternativ 123.wav
  123.json
  references.json         # optional, menschlich bestätigte Referenzen
  scripts.json            # optional, vorgelesene Texte
  vocab.txt               # wird im Benchmark ignoriert
```

Metadaten: `{ "id": "123", "createdAt": "...", "language": "de", "enablePolish": true,
"activeProfile": "coding", "skipped": false, "voiceActivity": null, "transcript": "...",
"polished": "...", "finalText": "..." }`. Die gespeicherten App-Texte werden nicht als
Benchmark-Ergebnisse ausgegeben: jede Variante kommt aus ihrem eigenen API-Aufruf/Cache.
Auch `skipped`-Aufnahmen werden bewusst gemessen und im Bericht gekennzeichnet.

`references.json`: `{ "123": { "text": "Der richtige Wortlaut.", "ideal": "Die gewünschte Politur.", "kind": "vorgelesen", "note": "..." } }`.
Für freie Rede `kind: "frei"`. **Vorhandene Einträge gelten als menschlich bestätigt** und haben
immer Vorrang. Ein freier Eintrag ohne `text` (`{ "kind": "frei" }`) ist nur eine Klassifikation und erhält Konsens statt einer bestätigten Referenz. Leere/ungültige Text-Einträge werden nicht durch Konsens ersetzt, sondern beanstandet.

`scripts.json`: `[{ "nr": 1, "text": "Der vorgelesene Text." }]`.

```sh
node tools/benchmark/bench.mjs models --data /tmp/paply-bench
node tools/benchmark/bench.mjs transcribe --data /tmp/paply-bench
node tools/benchmark/bench.mjs match --data /tmp/paply-bench
```

`match` benutzt Transkript a (Transkriptionen aus Cache), sortiert Vorlesetexte nach
`1 − Wort-Editdistanz / max(Wortanzahl)` und schlägt ab **0,6** einen Vorlesetext vor.
Darunter gilt die Aufnahme vorläufig als frei. `references.suggested.json` und `matches.json`
enthalten Vorschläge/Top-3-Kandidaten; **references.json wird nie überschrieben**.
Mehrere Aufnahmen dürfen denselben Vorlesetext erhalten. Vorhandene bestätigte Einträge bleiben erhalten.
Vorschläge anhören, korrigieren und gewünschte Einträge manuell in `references.json` übernehmen.
Nicht bestätigte freie Aufnahmen ohne Eintrag erhalten im nächsten Schritt eine Konsens-Referenz.

```sh
node tools/benchmark/bench.mjs reference --data /tmp/paply-bench
node tools/benchmark/bench.mjs polish --data /tmp/paply-bench
node tools/benchmark/bench.mjs score --data /tmp/paply-bench
node tools/benchmark/bench.mjs report --data /tmp/paply-bench
open /tmp/paply-bench/bericht.html
```

Oder nach Bereitstellung der Referenzen:

```sh
node tools/benchmark/bench.mjs all --data /tmp/paply-bench
# Optionales LLM-Urteil kostet zusätzliche Free-Tier-Anfragen:
node tools/benchmark/bench.mjs score --data /tmp/paply-bench --judge
node tools/benchmark/bench.mjs report --data /tmp/paply-bench
# Vollständige Wiederholung ohne Netz, nur aus API-Cache:
node tools/benchmark/bench.mjs all --data /tmp/paply-bench --offline
```

`--config <pfad>` überschreibt `~/Library/Application Support/paply-menubar/config.json`.
Nur `groqApiKey`, `geminiApiKey` und die Profile werden daraus im Speicher verwendet. Schlüssel
werden nie in Ergebnisse/Logs geschrieben. **Nur Schlüssel von Free-Tier-Konten verwenden**:
die normalen Groq-/Gemini-Endpunkte haben keinen Request-Schalter, der einen kostenpflichtigen
Kontotarif verhindert. Das Werkzeug schaltet kein Billing frei und nutzt keine bezahlten Ausweichdienste.
Kostenfreie Kontingente: [Groq](https://console.groq.com/docs/rate-limits),
[Gemini](https://ai.google.dev/gemini-api/docs/billing).

Weitere Optionen: `--limit 1` (chronologisch erste Aufnahme),
`--models openai/gpt-oss-120b` (Poliermodell-Auswahl), `--scripts <pfad>`,
`--refresh-models` (Modellliste aktualisieren und negative Cache-Einträge erneut versuchen).
`--limit` beschränkt auch Ergebnisdateien/Bericht auf diese Auswahl; die API-Caches aller Aufnahmen bleiben.
Beim nächsten vollständigen `all` werden die übrigen Resultate kostenlos aus dem Cache rekonstruiert.

## Varianten

- **a:** `whisper-large-v3-turbo`, **b:** `whisper-large-v3`, beide Deutsch und `verbose_json`.
- **c:** Gemini inline Audio, passend `audio/webm` oder `audio/wav`; Reihenfolge
  `gemini-3.6-flash` → `gemini-3.5-flash` → `gemini-flash-latest`.
  Wortgetreu mit Füllwörtern/Wiederholungen. Tatsächlich benutztes Modell steht beim Ergebnis.
- `vocab.txt` wird unabhängig vom Inhalt ignoriert; die historische Variante d wird nicht mehr gewertet.
- **P0:** eingefrorene eingebaute Prompts aus v1.14.0 in `legacy-prompts.cjs` (historischer Vergleich). Eigene Agenten nutzen weiterhin das gemeinsame App-Modul.
  Die promptreinen Module werden ohne Electron geladen.
  `activeProfile` wird wie in der App gegen `profiles` / `customAgents` aus den aktuellen
  Einstellungen aufgelöst. Standardprofile: coding→code, dictation→plain, meeting→meeting.
  Optional `polishFlavor`/`customSettings` in der Metadatei als historische Momentaufnahme.
  Ohne historische Momentaufnahme kann ein inzwischen geändertes Profil nicht rekonstruiert werden.
- **P1:** minimales Glätten, strenge Wort-/Sinn-Treue, eindeutige Selbstkorrekturen auflösen,
  Fachbegriffe/Englisch beibehalten, Temperatur 0.
- Poliermodelle: `openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `qwen/qwen3.8-27b`, nach
  `GET /openai/v1/models` (24 h Cache). P0 behält die frühere Temperaturvorgabe (nicht gesetzt).
  GPT-OSS nutzt `reasoning_format: hidden`, 8192 Ausgabetokens; nur finale, nicht abgeschnittene
  Antworten werden gewertet. Verbleibende `<think>`-Blöcke werden entfernt.

## Referenz und Kennzahlen

`reference.auto.json` bildet für alle Aufnahmen eine vorläufige Mehrheit aus **a/b/c**, nicht aus d. Bei vorgelesenen Aufnahmen zeigt der Bericht diesen Konsens zusätzlich neben der Vorlage. Stellen, an denen alle drei Modelle identisch von der Vorlage abweichen (ersetzt, hinzugefügt oder ausgelassen), sind als „vermutlich anders gesprochen“ markiert, mit Sprung zum ungefähren Segmentbeginn. Auch ein gemeinsamer Erkennungsfehler ist möglich. Für Vorlage 5 / Selbstkorrektur gibt es einen hervorgehobenen Hinweis, einschließlich bereits von Turbo oder im gespeicherten App-Rohtext ausgelassener Wörter. Selbstkorrekturen dürfen nur bei eindeutiger Korrekturabsicht entfernt werden; fehlende Rohwörter kann die Politur nicht rekonstruieren.
Wort-Alignment a→b und a→c; Einfügungen von b/c werden untereinander ausgerichtet.
Zwei gleiche Wörter (auch zwei Lücken) gewinnen. Ohne Mehrheit bleibt ein vorläufiges Wort
mit allen Alternativen markiert. Zeitmarken stammen vom Start des zugeordneten Whisper-Segments,
**nicht** von einer genauen Wortposition. Ohne Zeitdaten gibt es keinen erfundenen Sprungzeitpunkt.
Fehlt eines der drei nichtleeren Transkripte, wird keine Konsens-Referenz behauptet.
Zwei Whisper-Modelle sind verwandt: Konsens kann denselben Fehler übernehmen.
Audio-/Transkript-Hashes verhindern die Verwendung veralteter automatischer Referenzen.

Normalisierung: Unicode NFC, Kleinschreibung, Wortgrenzen statt Satzzeichen; keine semantische
Normalisierung. `Next.js` wird `next js`, `15` bleibt anders als `fünfzehn`.
WER = (ersetzt + weggelassen + hinzugefügt) / Referenzwörter; kann über 100 % liegen.
Die Übersicht verwendet **Mikro-WER** (alle Fehler / alle Referenzwörter), getrennt nach bestätigter
und automatischer Referenz. Ohne Referenz wird nicht gewertet.

**Wenn `ideal` vorliegt**, wird jede Polier-Variante zusätzlich per WER gegen diesen menschlich vorgegebenen Zieltext bewertet. Die Übersicht priorisiert diese Mikro-WER für die Politur-Rangfolge; n gibt die Zahl der Ideal-Referenzen an. `text` bleibt die Rohtranskript-Referenz. Beide Referenzen bleiben unverändert, auch wenn beim Lesen abgewichen wurde. Ohne vorgegebenes `ideal` gibt es **keinen automatischen idealen Zieltext**. Erfasst werden wortweise ersetzt/hinzu/weg
für Inhaltswörter (≥4 Zeichen, Großbuchstabe am Anfang oder Ziffer), mit wenigen sicheren
Füllwörtern und unmittelbar wiederholten Wörtern/Phrasen ausgenommen. Selbstkorrekturen werden
nicht pauschal als erlaubt herausgerechnet: die Stellen muss ein Mensch bzw. das optionale LLM prüfen.
„Nicht“ wird dadurch als relevantes Wort erfasst. Zahlen-Treue zählt Ziffern und häufige deutsche
Zahlwörter lexikalisch. Namen-Treue ist ausdrücklich nur eine Großschreibungs-Heuristik,
einschließlich vieler deutscher Substantive und empfindlich auf Satzanfänge. Zahlen und Namen
werden als Multimengen verglichen; die Wortzahl-Längenquote wird ebenfalls angezeigt.

★ markiert niedrigste Roh-WER bzw. niedrigste Ideal-WER für Politur. Nur ohne vorgegebenes Ideal zählt die geringste Inhaltswort-Abweichung **nur bei vollständiger gleicher
Aufnahmeabdeckung**; Gleichstände werden gemeinsam markiert. Dies ist keine Empfehlung,
ungeglätteten Text wegen unveränderter Fehler zu bevorzugen. Die beste Einstellung erst nach
Nachhören, Prüfung der Änderungen und Bewertung sauberer Sätze auswählen. LLM-Urteile
(gpt-oss-120b, Temperatur 0, validiertes JSON) sind ebenfalls keine verlässliche Wahrheit.

## Cache, Fehler und Datenschutz

Alle Dateien entstehen unter `--data`: `cache/`, `results.json`, `scores.json`,
`reference.auto.json`, `models.json` (Befehl models), `last-run.json`, `bericht.html`.
Erfolgreiche API-Anfragen werden nach Eingabe/Audio-Hash + Modell + vollständigem Prompt +
Parametern wiederverwendet. Erfolgreiche Antworten laufen nicht ab; Modelllisten nach 24 h.
`--offline` verhindert jeglichen Netzaufruf. Die Ergebnisse jeder Stufe werden zwischengespeichert;
Fehler einer Aufnahme verhindern andere Ergebnisse nicht. P0/P1 werden aus den aktuellen
exakten Anfragen rekonstruiert, alte Politur bei geändertem Rohtext verworfen. Vor report prüft
das Werkzeug, ob score zu den aktuellen Referenzen und Texten passt.

Anfragen laufen nacheinander mit Mindestabstand. 429/5xx werden maximal zweimal mit mindestens
15/30 s und ggf. längerem Retry-After wiederholt. Cooldowns gelten pro Modell und bleiben über Prozessneustarts erhalten; ein erschöpftes Modell blockiert nicht die getrennten Kontingente der Ausweichmodelle.
Bei Tageskontingent/Nullkontingent oder >120 s Wartezeit wird abgebrochen statt weiter anzufragen.
Negative Antworten sind zeitweise gecacht (400/404/ungültige Ausgabe 24 h, sonst 5 min;
429/5xx gemäß Backoff). Netzwerkfehler werden wegen unbekannter Verarbeitung nicht automatisch
wiederholt. Provider-Fehlertexte werden weder ausgegeben noch gespeichert (könnten Eingaben enthalten).
Exitcode 0 = vollständig, 2 = Ergebnisse mit Fehlern/Hinweisen, 1 = fataler Eingabe-/Ablauffehler.
Ein PID-Lock pro Datenordner verhindert parallele Doppelanfragen; verwaiste Locks werden erkannt.

Der Bericht enthält keine externen Skripte/Schriften/Requests. Audio liegt als relativer Pfad daneben,
HTML wird escaped, CSP sperrt Netzverbindungen. HTML ist eine einzige Datei mit inline CSS/JS;
**zum Weitergeben auch die Audio-Dateien mitnehmen**. Die Aufnahmen werden für die Auswertung an
Groq/Gemini übertragen; der Datenordner enthält vertrauliche Transkripte und ist selbst aufzubewahren.
Audio bis 18 MiB wird unterstützt; längere Dateien teilen. Alignment ist auf 8 Mio. DP-Zellen begrenzt.

## Entwicklung und Prüfung

```sh
node --test tools/benchmark/*.test.mjs
# macOS mit installierter Stimme Anna, /usr/bin/say und /usr/bin/afconvert:
node tools/benchmark/dev-fixtures.mjs /tmp/paply-bench-dev
node tools/benchmark/bench.mjs all --data /tmp/paply-bench-dev
node tools/benchmark/bench.mjs all --data /tmp/paply-bench-dev --offline
```

Der Fixture-Befehl erzeugt drei 16-kHz-Mono-WAVs plus Metadaten, scripts.json und feste Referenzen.
Er überschreibt keine vorhandenen Proben. Die Tests arbeiten ohne Netz und prüfen u. a.
Alignment mit Einfügungen/Lücken, Segmentzeiten, Referenzvorrang, WER, Treue, vollständige
Ranglistenabdeckung, Reasoning/Trunkierung, Caching, 429-Backoff, Tageslimit, Sperren und HTML-Escaping.
Synthetische Stimme und drei kurze Texte erlauben **keine belastbare Modellwahl für Allans Alltag**.


## Echte Aufnahmen vom 21.10.2026

```sh
node tools/benchmark/bench.mjs transcribe --data /tmp/paply-bench/aufnahmen
# Nur falls die vorhandene Zuordnung erneut vorgeschlagen werden soll:
node tools/benchmark/bench.mjs match --data /tmp/paply-bench/aufnahmen --scripts /tmp/paply-bench/scripts.json
node tools/benchmark/bench.mjs reference --data /tmp/paply-bench/aufnahmen
node tools/benchmark/bench.mjs polish --data /tmp/paply-bench/aufnahmen
node tools/benchmark/bench.mjs score --data /tmp/paply-bench/aufnahmen
node tools/benchmark/bench.mjs report --data /tmp/paply-bench/aufnahmen
open /tmp/paply-bench/aufnahmen/bericht.html
```

Die zehn Vorlese-Vorlagen enthalten `text` und `ideal`; sechs freie Aufnahmen haben nur die Klassifikation. Konsens bleibt vorläufig. Der Bericht ändert keine Aufnahme, Vorlage oder App-Einstellung.


## Kontext-Vergleich (P2 und W-ctx+P2)

Modelle bleiben Whisper Turbo und Groq-LLM. `context` verwendet ausschließlich `qwen/qwen3.8-27b` und `openai/gpt-oss-120b` (Temperatur 0), keine fest eingetragenen Korrekturwörter und keine Wortliste. Die historischen P0/P1-Ergebnisse bleiben Vergleichsdaten; P0 wird für diesen Lauf nicht neu angefragt.

```sh
node tools/benchmark/bench.mjs context --data /tmp/paply-bench/aufnahmen
node tools/benchmark/bench.mjs reference --data /tmp/paply-bench/aufnahmen
node tools/benchmark/bench.mjs score --data /tmp/paply-bench/aufnahmen
node tools/benchmark/bench.mjs audit --data /tmp/paply-bench/aufnahmen
node tools/benchmark/bench.mjs report --data /tmp/paply-bench/aufnahmen
# Wiederholung von context kostenlos aus Cache:
node tools/benchmark/bench.mjs context --data /tmp/paply-bench/aufnahmen --offline
```

Sortierung nach `createdAt`; Aufnahmen ohne gültige Zeit folgen danach in ID-Reihenfolge. P2 erhält den aktuellen Rohtext a plus ausschließlich die letzten drei vorherigen a-Rohtranskripte in zeitlicher Reihenfolge als Hintergrund. Es werden keine Referenzen, Ideale, polierten Texte oder Wörterlisten in den Hintergrund übernommen. Bei der ersten Aufnahme ist er leer. Segmente mit `avg_logprob < -0.5` werden mitsamt Text und Zeiten als unsicher gekennzeichnet. Niedrige Sicherheit ist allein kein Korrekturauftrag. `dictation/polish-prompt.js` ist die gemeinsame P2-Prompt-Quelle für App und Benchmark. `context.mjs` verwendet denselben Nachrichtenaufbau. Die App begrenzt ihren Live-Verlauf zusätzlich auf 30 Minuten und verwirft riskante Modellantworten; der historische Kontext-Vergleich misst weiterhin die ungefilterten Modellantworten mit den letzten drei Aufnahmen des Datensatzes.

W-ctx konditioniert Whisper Turbo mit dem letzten Ende dieser Rohtext-Historie (höchstens 200 Unicode-Zeichen, Anfang an Wortgrenze), danach folgt derselbe P2-Prompt auf dem konditionierten Rohtext. Der Verlauf stammt in beiden Varianten immer aus a, nicht rekursiv aus konditionierten oder polierten Ausgaben. Damit bleibt der Kontext kontrolliert vergleichbar. `results.json` speichert die tatsächlich versendeten P2-Nachrichten, Kontext-IDs, Whisper-Konditionierung und Prompt-/Eingabe-Hashes. Änderungen an Verlauf, Eingabe oder Unsicherheitsmarkierung machen alte Resultate ungültig.

`experiment-summary.json` vergleicht P1 (historisch), P2 und W-ctx+P2 für die beiden Modelle. Ideal-WER ist die Mikro-WER über vorgegebene Ideale. Risiko frei ist dieselbe Inhaltswort-Heuristik gegen den vorläufigen a/b/c-Konsens wie zuvor. b/c werden hier nur als bereits vorhandene Referenzdaten verwendet; `context` ruft weder Gemini noch Whisper v3 auf. Automatische Referenzen hängen ausschließlich von a/b/c ab, nicht von W-ctx.

Latenz misst `performance.now()` direkt vor HTTP-Aufruf bis nach Dekodierung der vollständigen erfolgreichen Antwort. Pacing, Backoff und Cache-Lesezeit zählen nicht mit. Erfolgreiche Cache-Einträge behalten die ursprüngliche gemessene Latenz; Cache-Treffer werden nicht als 0 ms ausgegeben. Median/Max werden über diese ursprünglichen Messwerte berechnet. Historische P1-Ergebnisse ohne HTTP-Zeitmessung bleiben **—**, statt Server-Tokenzeiten als Netzlatenz auszugeben.

### Getrennte Hörfehler- und Sinnprüfung

Nur die Auswertung liest optionale Dateien im Datenordner:

- `review-cases.json`: `[{ "id": "fall-1", "nr": 1, "bad": "fehlerhaftes muster", "good": "richtiges muster" }]`. Reguläre Ausdrücke werden auf kleingeschriebene, satzzeichenfreie Wörter mit Leerzeichen angewandt. Ein Fall zählt nur, wenn `bad` im ursprünglichen a-Rohtext vorkommt; als behoben nur, wenn das Ziel im Endtext vorkommt und `bad` verschwunden ist. Bloßes Löschen zählt nicht als Reparatur. Der konkrete Katalog verbleibt außerhalb des Repositories und erreicht nie die Inferenz-Prompts.
- `audit` schreibt `review-inputs.json` mit Baseline, aktueller Eingabe, Ausgabe, Referenz/Ideal sowie Wortänderungen. Dies ist ausschließlich Prüfdatenmaterial.
- `semantic-review.json`: `{ "entries": { "aufnahme-id": { "P2/modell-id": { "inputHash": "...", "baselineHash": "...", "outputHash": "...", "changes": [{ "from": "...", "to": "...", "reason": "..." }] } } } }`. Die Hashes aus `review-inputs.json` übernehmen. Die Prüfung kann als Agenten-Textprüfung erfolgen; sie ist dann kein menschlich bestätigter Audio-Goldstandard und muss so bezeichnet werden. Jede Ausgabe manuell auf neue Sinnänderungen prüfen; ein leeres Array bestätigt nur nach tatsächlicher Prüfung das Fehlen solcher Änderungen. Geerbte Hörfehler sind keine neu entstandenen Sinnänderungen; neue falsche Kontextübernahmen oder Umdeutungen schon. Für W-ctx auch Änderungen des konditionierten Rohtexts gegenüber a prüfen.

Die Zusammenfassung gibt neue Sinnänderungen erst aus, wenn alle Ausgaben der Variante geprüft sind und die Hashes passen; ansonsten **—**, nicht 0. Nach Bearbeitung dieser Auswertungsdateien `score` und `report` erneut ausführen. Veraltete Prüfstände werden erkannt. Keine zusätzlichen LLM-Urteile sind für diese manuelle Zählung nötig.
