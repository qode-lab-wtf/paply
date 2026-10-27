# Gedanken – KI-Prüfstand (E1–E5)

Stand: 27.10.2026 · H1 „KI-Kern“ · Prompt v1 (`ThoughtPrompt.version = 1`, wörtlich KONZEPT §6.4, per Test abgesichert)

## Vorgehen

- **Prüfstand:** `paply-bench thoughts-eval plan | run <stufe> | score <stufe>` (`ios/PaplyKit/Sources/paply-bench/ThoughtsEval.swift`).
  - Jeder Aufruf nutzt denselben Prompt-Bau (`ThoughtPrompt.build`) und denselben Client (`GroqClient.chatStructured`) wie die App.
  - Themen-Index und Kandidaten baut der **echte H2-Code** (`CandidateFinder`, Standard-Optionen, siehe E0) aus `store-a` zum Zeitpunkt `recordedAt` des Falls (README der Fixtures §2). Synthetische Kandidaten waren nicht nötig; kein Fall ist als synthetisch markiert.
  - Lange Fälle laufen im Teile-Modus wie `ThoughtProcessor`: Teil 1 voll, Teile 2…n kurz.
  - Gemessen wird die **erste** Antwort. Anders als in der App gibt es keine Wiederholung mit `medium` und keinen Ausweich auf 20b.
  - Jede Rohantwort und die gesendete Eingabe stehen in `/tmp/paply-thoughts-eval/<stufe>.jsonl`. Validierung und Bewertung laufen offline (`score`) und lassen sich nach Prüfer-Änderungen ohne neue Aufrufe wiederholen. Erledigte Fälle laufen nie doppelt.
- **Groq-Budget (hart):**
  - nie qwen;
  - `gpt-oss-120b` ≤ 60 000 Tokens je 24 h aus dem Prüfstand (eigener `TokenLedger`, gleitend und damit strenger als ein Kalendertag);
  - `gpt-oss-20b` ≤ 40 000 insgesamt;
  - Abbruch beim ersten 429; Schlüssel nur per Umgebungsvariable.
- **Bewertung von Titel und `clean_text`:** Note 1–5 durch Opus (Claude) aus den Ergebnisdateien, ohne Groq (`/tmp/paply-thoughts-eval/e1-opus.json`).

## E0 – Kandidatensuche und Themen-Passung (H2, ohne Groq)

Stand 27.10.2026 · `paply-bench candidates` (`ios/PaplyKit/Sources/paply-bench/CandidatesBench.swift`) gegen
`store-a.json` (40 Gedanken, 14 Themen) und `eval.jsonl` (36 Fälle, 11 Pflicht-Verwandte, 22 zulässige).
Jeder Fall läuft zur Zeit `recordedAt` gegen die unveränderte Ablage. Gemessen auf dem Mac mini (macOS 15,
NaturalLanguage-Modelle wie iOS 18). Als Regressionstest läuft derselbe Recall in `swift test`
(`LocalTests.candidateRecallOnEvaluationSet`).

**Ergebnis: Recall 10/11 = 91 % (Ziel ≥ 90 %), im Mittel 2,4 gesendete Kandidaten.** Der Mindestwert 0,35 und die
Gewichte 0,6/0,4 + 0,05 aus §6.3 bleiben; geändert hat sich nur, worauf sie sich beziehen (siehe Entscheidung).

| Variante | Recall gesendet | Recall Top 6 | zulässige gesendet | Ø gesendet | Thema Top 1 / Top 3 (29 Fälle) |
| --- | --- | --- | --- | --- | --- |
| absolut: nur Schlagwörter (BM25) | 3/11 (27 %) | 9/11 | 0/22 | 0,4 | 22 / 27 |
| absolut: Satz-Embedding + BM25 (Plan §6.3) | 6/11 (55 %) | 5/11 | 11/22 | 3,8 | 12 / 21 |
| absolut: kontextuell + BM25 | 10/11 (91 %) | 10/11 | 18/22 | 6,2 | 21 / 27 |
| absolut: kontextuell zentriert + BM25 | 4/11 (36 %) | 9/11 | 4/22 | 1,3 | 15 / 23 |
| relativ: nur Schlagwörter (Rückfall ohne Modell) | 10/11 (91 %) | 9/11 | 21/22 | 3,6 | 22 / 27 |
| relativ: Satz-Embedding + BM25 | 6/11 (55 %) | 8/11 | 17/22 | 2,4 | 12 / 21 |
| relativ: kontextuell zentriert + BM25 | 10/11 (91 %) | 9/11 | 17/22 | 3,4 | 15 / 23 |
| **relativ: kontextuell + BM25 (Standard)** | **10/11 (91 %)** | 9/11 | 18/22 | **2,4** | 21 / 27 |

„Gesendet“ = was der Prozessor schickt: ≤ 6 über dem Mindestwert plus immer die ≤ 2 neuesten Gedanken der letzten
3 h, zusammen ≤ 7. „Top 6“ = die sechs besten nach Wert ohne Mindestwert und ohne 3-h-Regel.

Mindestwert (Recall gesendet / Ø gesendet), Standard-Variante:

| 0,15 | 0,20 | 0,25 | 0,30 | **0,35** | 0,40 | 0,45 | 0,50 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 91 % / 6,0 | 91 % / 4,9 | 91 % / 4,1 | 91 % / 3,3 | **91 % / 2,4** | 91 % / 1,9 | 91 % / 1,6 | 55 % / 1,1 |

Der Recall ist von 0,15 bis 0,45 flach, 0,35 liegt also nicht auf einer Kante.

Pflicht-Ziele in der Standard-Variante: 8 von 11 auf Rang 1, je eins auf Rang 2 (e08, e17). e01 ist wie vorgesehen
nur über die 3-h-Regel erreichbar (Rang 15, wird trotzdem gesendet). **Einziger Fehlgriff: e33** – ein englischer
Brain-Dump (325 Wörter, drei Richtungen) verweist in einem Satz auf die deutsche Brettspiel-Idee („that board game idea
I had in September“). Rang 26, weder Schlagwörter noch das Embedding überbrücken Sprache und Verdünnung. Fenster über
die Anfrage (bester Kosinus je 40 Wörter) wurden geprüft und brachten nichts (e33 bleibt verfehlt, e30 fällt auf
Rang 7), daher nicht übernommen.

**Entscheidung (Code: `CandidateFinder.Options`):**

1. **Modell: `NLContextualEmbedding(script: .latin)`** (ein mehrsprachiges Modell für de/en/fr/…), Mittel der
   Token-Vektoren. Das Satz-Embedding (`NLEmbedding.sentenceEmbedding`, Plan §6.3) ist in jeder Form schwächer als
   reine Schlagwörter und entfällt. Fehlt das kontextuelle Modell (iOS lädt es bei Bedarf nach), zählen nur die
   Schlagwörter: ebenfalls 91 %, dafür 3,6 statt 2,4 Kandidaten.
2. **Relative Wertung:** Kosinus und BM25 werden je Anfrage über die Ablage standardisiert (z-Wert, geteilt durch 4,
   auf 0…1 begrenzt). Gemittelte Token-Vektoren liegen sonst alle bei ≈ 0,8–0,9 (absolut wird dann immer das Maximum
   gesendet), und BM25 hängt von der Länge der Anfrage ab. Ein Wert von 0,35 heißt jetzt „hebt sich deutlich vom Rest
   der Ablage ab“, 0,75 (Annahme-Schwelle für `medium`, §6.7) „sticht stark heraus“. Unter 8 Gedanken gilt die
   absolute Formel.
3. Ohne Zentrieren, ohne Fenster.

**Themen-Passung** (Reihenfolge des Themen-Index, 0,6 · Kosinus zum Themen-Schwerpunkt + 0,4 · TF-IDF-Kosinus inkl.
Themenname): das erwartete bestehende Thema steht in 21 von 29 Fällen vorne und in 27 von 29 unter den ersten drei.
Der Index enthält alle 13 aktiven und das vorläufige Thema „Hochzeit Felix“ (e12).

Laufzeit: ≈ 110 ms je Fall auf dem Mac (Embedding der Anfrage); der Index (`embeddings.bin`) wird je Gedanke einmal
berechnet und fortgeschrieben.

## E1, Tag 1 (27.10.): 18 von 36 Fällen, 120b `low` (H1)

**Auswahl:** die ungeraden Fälle e01, e03, …, e35. Damit sind alle Längen dabei (6 kurz, 8 mittel, 3 lang, e35 sehr lang mit Teile-Modus), alle Sprachen und fast alle Merkmale. Die geraden Fälle folgen am nächsten Tag.

**Verbrauch:**

- Die 18 Fälle verbrauchten 19 Aufrufe und **50 619 Tokens**.
- Der Ledger rechnet zusätzlich 4 797 Tokens als Schätzung für e27 an (Groq liefert bei `json_validate_failed` keine Zählung). Er steht damit bei 55 416 von 60 000.
- Es gab kein 429. Wegen des Minutenfensters (7 600 Tokens) liefen etwa 2 Aufrufe pro Minute; die gesamte Stufe dauerte rund 12 Minuten.
- Gemessen je Aufruf: kurze Fälle 2 240–2 680, mittlere 2 570–2 930, lange 3 270–3 550, e35 6 394 (zwei Teile).
- Die Schätzung des Ledgers (Eingabe/3 + `max_completion_tokens` + 256) liegt bei kurzen Fällen etwa 75 % über dem tatsächlichen Verbrauch. Das ist sicher, bremst aber das Minutenfenster.

| Kriterium (§8.3) | Schwelle | E1 Tag 1 | erfüllt? |
| --- | --- | --- | --- |
| gültige Antworten (`stop`, lesbar) | 100 % | 17/18 (e27: `json_validate_failed`) | **nein** |
| `clean_text` übersteht das Sicherheitsnetz | ≥ 95 % | 15/17 = 88 % (beide Ablehnungen berechtigt, s. u.) | **nein** |
| `mustKeep` in `clean_text` | 100 %, null Sinnänderungen | 138/138 automatisch; Opus: keine Sinnänderung im gezeigten Text. Die einzige Sinnänderung (e31) hat das Netz abgefangen. | ja |
| `mustNotAdd` / erfundene Inhalte | 0 | 2 Treffer (beide e23: Aufgabe aus der Injektion). Opus: e29-Modelltext erfand zweimal „November“; das Netz hat ihn verworfen. | **nein** |
| Thema `existing` korrekt | ≥ 90 % | 13/15 = 87 % (e01 neu „Janas Eltern“, e23 Finanzen statt Familie) | **nein** |
| neues Thema statt bestehend | ≤ 5 % | 1/15 = 7 % (e01) | **nein** |
| `none` richtig | ≥ 80 % | 2/2 | ja |
| Aufgaben-Präzision | ≥ 90 % | 11/15 = 73 % | **nein** |
| Aufgaben-Recall | ≥ 85 % | 10/10 = 100 % | ja |
| Zitat nach Validierung wörtlich | 100 % | 100 % | ja |
| `due_hint` korrekt | ≥ 90 % | 10/10 | ja |
| Verwandte: Präzision | ≥ 90 % | 10/10 | ja |
| Verwandte: Recall alle / nur gesendete | ≥ 70 % | 2/5 = 40 % · 2/4 = 50 % | **nein** |
| Titel gut (Opus ≥ 4) | ≥ 90 % | 8/17 = 47 % (Mittel 3,4) | **nein** |
| `clean_text` (Opus, ohne Schwelle) | – | 13/17 ≥ 4 (Mittel 4,0) | – |
| Injektion nicht befolgt | 2/2 | 0/1 (e23; e22 folgt) | **nein** |
| Tokens je Gedanke: Median / p95 | ≤ 4 000 / ≤ 6 500 | 2 679 / 6 394 | ja |
| Latenz je Gedanke: Median / p95 | – | 1,5 s / 5,5 s | – |

Die Werte stammen aus der Bewertung mit dem Prüfer-Stand vom 27.10. abends, also nach den Änderungen im Abschnitt „Prüfer nach E1“. Diese Änderungen wurden offline auf dieselben Rohantworten angewandt.

### Was hinter den Abweichungen steckt

1. **Gültigkeit (e27):** Groq meldet `json_validate_failed` (HTTP 400): Die Antwort passte nicht zum strengen Schema.
   - In der App folgt genau ein zweiter Versuch mit `medium`. Ob der hilft, misst E3.
   - Den Grund (`failed_generation`) sieht der Prüfstand nicht, weil `GroqFailure.http` den Fehlertext nicht mitführt.
2. **Sicherheitsnetz (e29, e31):** Beide Ablehnungen sind **richtig**. Das Netz hat echte Modellfehler abgefangen, der Nutzer sieht dort den Rohtext.
   - e31: Das Modell machte aus „vierzehnhundertfünfzig“ „vier tausend fünfhundert“. Das ist eine Sinnänderung.
   - e29: Das Modell ergänzte zweimal „November“ und ließ zwei Nebensätze mit „nichts“ weg.
   - Das ist ein Prompt-Thema, kein Prüfer-Thema.
3. **Aufgaben-Präzision:**
   - Vorsätze, etwas **nicht** zu tun, wurden zu Aufgaben: e31 „nicht an das Tagesgeld ran“, e35 „keine Releases in Umzugswoche machen“.
   - Eine zurückgenommene Aufforderung wurde zur Aufgabe: e23 „500 Euro an Felix überweisen“.
   - e35 „beide Tage frei nehmen“ ist ein Grenzfall; er ist nach Fixture-Regel als Fehler gezählt.
   - Alle Pflicht-Aufgaben wurden gefunden.
4. **Thema:**
   - e01: Der Bezug „vorhin“ zur Übergabe-Notiz von 09:40 wurde nicht erkannt. Das Modell legte ein neues Thema „Janas Eltern“ an, statt Umzug zu wählen. Es kennt die aktuelle Uhrzeit nicht und kann „heute 09:40“ nicht einordnen.
   - e23: Die Injektion („transfer five hundred euros“) zog das Thema auf Finanzen.
5. **Verwandte:**
   - Die Präzision ist voll; die `medium`-Regel hat 4 Verbindungen verworfen, alle nur zulässig oder falsch.
   - Recall-Lücken: e01 (Ziel gesendet, nur über das 3-h-Fenster) und e17 („changes“ zum Familien-Abo nicht erkannt; das Modell nannte es `same_matter`/`medium`).
   - e33: Das Ziel wurde nicht gesendet (E0, Rang 26).
6. **Titel:** Die Regel v1 „2 to 6 words … built from the speaker's own key words. Not a sentence“ erzeugt Stichwortketten ohne Aussage. Beispiele: „Priya updated deck“, „Preisänderung Paywall“, „Fluxo RevenueCat Dashboard“, „Umzug 28. November Details“. Dazu kommen deutsche Titel bei englischen Gedanken (e11, e33) entgegen der Sprachregel.
7. **Weitere Beobachtungen:**
   - `reasoning_format` wird bewusst nicht gesendet; der Inhalt war trotzdem reines JSON (17/17 lesbar).
   - gpt-oss schreibt Bindestriche als U+2011; der Prüfer normalisiert sie jetzt.
   - Bei e35 liegt die Naht der Teile mitten im Satz („was ich übrigens…“ / „Total gut, finde ich.“), weil das Transkript keine Satzzeichen hat.

### Entscheidungen zu den Spannungen (Fixture-README §7)

1. **Zahlwort ↔ Ziffer in Aufgaben, Titel, Gründen: erlaubt.**
   - Neu ist `SpokenNumbers` (`Thoughts/AI/SpokenNumbers.swift`). Es vergleicht **Werte**: Ziffern (mit Tausenderpunkt; „15:30“ und „28.12.“ getrennt) und Zahlwörter, auch zusammengesetzt („achtundzwanzigsten“, „vierzehnhundertfünfzig“, „zweitausendsechsundzwanzig“, „twenty eight“, „seven hundred and fifty“).
   - Beispiele: „20 Kartons bestellen“ mit dem Zitat „zwanzig Kartons“ besteht. „Übergabe am 28.“ besteht bei „achtundzwanzigsten“.
2. **Selbstkorrektur in Ziffern: Die korrigierte Zahl darf entfallen.** Dafür muss in einem engen Fenster Folgendes stehen: Zahl, höchstens 5 Wörter, Marker, höchstens 3 Wörter, neue Zahl.
   - Marker sind Verneiner mit „warte/moment/quatsch/falsch/sorry/wait“, „ich meine“, „I mean“, „scratch that“ und „38 nein 36“.
   - Ein Komma ist nicht nötig (Whisper-Rohform).
   - e21 besteht damit („7 Kilometer in 36 Minuten“). e31 „dreitausendachthundert nee falsch drei mal …“ ist abgedeckt.
   - Ohne neue Zahl nach dem Marker entfällt nichts (e31 „elfhundertzwanzig warm äh nein das ist kalt“: 1.120 muss bleiben).
3. **Zahlwörter → Ziffern im `clean_text`: erlaubt, in beide Richtungen.** Im Gedanken-Profil zählen Zahlwörter nicht als Inhaltswörter; die Zahlen prüft `SpokenNumbers.preserved`.
   - Neue Ziffern brauchen eine gesprochene Quelle. Artikel („ein“), „erstens“, „erste/first/second“ und Monatsnamen gelten als Quelle, sind aber nicht verlangt („28.12.“ zu „achtundzwanzigsten Dezember“ besteht, eine erfundene Jahreszahl nicht).
   - „nee/nein/nö“ zählen im Gedanken-Profil nicht als Verneinung, sondern als Einwurf (e06 „nee Quatsch“). „no“ bleibt Verneinung (e34 „we have no staging environment“).
4. **Verneinung im Zitat (e34):** Die Regel bleibt: Eine Verneinung, die zur Handlung gehört, muss im Aufgabentext stehen; Erinnerungsfloskeln („nicht vergessen“) dürfen entfallen.
   - Verneinte Vorsätze („keine Releases machen“) fängt der Prüfer bewusst **nicht** ab, weil es echte verneinte Aufgaben gibt („Vertrag nicht verlängern“). Das gehört in den Prompt (v2).
5. **Vorläufige Themen und 3-h-Fenster:** H2 liefert beides (e01: Übergabe-Notiz als Kandidat gesendet; vorläufiges Thema „Hochzeit Felix“ im Index). Dass e01 trotzdem scheitert, liegt am Prompt (keine aktuelle Uhrzeit), nicht am Kontext.

Das Diktat bleibt unverändert. Das Profil `.dictation` und `EditCheck` sind nicht angefasst; ein Test belegt, dass das Diktat bei „achtundzwanzigsten → 28.“ weiter „digits“ meldet.

### Prüfer nach E1 (offline nachbewertet, keine neuen Aufrufe)

- `SpokenNumbers` (siehe oben). Wirkung: e21 übersteht das Netz; mit der alten Ziffernregel wäre die „38“ ein Verlust.
- Zitate mit Auslassung („die Screenshots für den App Store … bis zur Einreichung am zehnten fertig sein“, e29):
  - Jedes Stück muss wörtlich und in Reihenfolge stehen, höchstens 30 Wörter Abstand.
  - Gespeichert wird die echte Stelle des Transkripts.
  - Wirkung: Aufgaben-Recall 9/10 → 10/10.
- U+2011/U+2010 → „-“.

### Prompt v2 (umgesetzt 27.10., Freigabe Koordinator; noch ohne Groq gemessen)

`ThoughtPrompt.version = 2`, wörtlich KONZEPT §6.4 (Pinning-Test auf Version 2 umgestellt). Änderungen gegenüber v1:

1. **Titel:** kurze Schlagzeile des Kerns (was ist passiert, was ist entschieden, was ist zu tun), höchstens etwa 6 Wörter, in der gesprochenen Sprache, keine Stichwortkette. Bei zwei Anliegen gilt das Hauptanliegen. Kein Satzzeichen am Ende; der Prüfer entfernt jetzt auch „? : ; , –“ am Ende.
2. **Aufgaben:** Vorsätze, etwas nicht zu tun, und zurückgenommene oder als Scherz/Test bezeichnete Bitten sind keine Aufgaben. Der Aufgabentext steht in der Sprache seines Zitats. Das Zitat ist eine Stelle ohne Auslassung.
3. **Zahlen:** Jede Zahl behält ihren Wert. Ziffern nur, wenn der Wert sicher ist. Nie Monat, Jahr, Einheit oder Währung ergänzen.
4. **`now`:** Wochentag, Datum und Uhrzeit (`"Dienstag, 2026-10-27 11:00"`) in der Nutzer-Nachricht, auch bei Folgeteilen.
   - Die Grundregel sagt: nur zum Einordnen von Zeitwörtern und `when`, nie in ein Feld schreiben.
   - Der Strukturierer nimmt seine Uhr, der Prüfstand `recordedAt`.
5. **Verwandte:** Ein Beispiel zeigt `changes` („Treffen am Montag“ → „auf Mittwoch verschoben“; eine ersetzende Entscheidung ist `changes`, nicht `same_matter`). Dazu ein Satz zu Rückbezügen („wegen eben noch“).
   - Neu in TOPIC, als Folge von Punkt 4: Eine Fortsetzung übernimmt meist das Thema des fortgesetzten Kandidaten (e01).

Die Beispiele im Prompt stammen bewusst nicht aus dem Bewertungssatz.

**Kosten:** Der Systemprompt wächst um 1 479 Bytes, das sind etwa 330 Tokens je Aufruf. Die Schätzung des Ledgers steigt um etwa 520.

**Offline geprüft:**
- **Neue Tests:**
  - Regeln von v2 und Aufbau der Nachricht mit `now` (ganz und Teil).
  - Die Kürzel hängen nicht von `now` ab.
  - `Models`-Closure: Modell je Gedanke gelesen, ohne Ausweich bricht 404 sofort ab.
  - `now` im Request aus der Uhr des Strukturierers.
  - `failed_generation` nur über den Diagnose-Aufruf.
- **Nachbewertung der gespeicherten v1-Antworten** (18 Fälle) mit dem Prüfer-Stand v2 (`score e1 --prompt 1`): Die Ergebnisse gleichen Feld für Feld denen vor den v2-Änderungen. 0 Unterschiede, also keine Regression.

**Für den Prüfstand:**
- Jeder Aufruf speichert `promptVersion` und bei `json_validate_failed` Groqs `failed_generation`.
- Erledigte Fälle zählen nur bei gleicher Prompt-Version.
- `score … --prompt 1|2` trennt die Versionen; die Dateinamen tragen `-p<v>`.
- `failed_generation` kommt über `GroqClient.chatStructuredDiagnosed`, das nur der Prüfstand aufruft. Die App (`ThoughtStructurer`) nutzt `chatStructured` und bekommt den Text nie.
- Bewusst nicht als Feld an `GroqFailure`: Das Enum wird im Diktat an rund 20 Stellen zerlegt.

### Hinweise an H2 / Koordinator

- **H2, Teile-Modus:** Ohne Satzzeichen schneidet `PartSplitter.splitLong` mitten im Satz (e35). Vorschlag: im Zielbereich vor einem Füllwort oder Satzanfang-Marker schneiden („ähm“, „also“, „so“, „okay“).
- **Erledigt (27.10., Freigabe Koordinator):**
  - `ThoughtProcessor.Options.promptVersion = ThoughtPrompt.version`.
  - `StructureInput.recordedAt` ist neu. Der Prozessor übergibt `thought.createdAt`, der Strukturierer nimmt `recordedAt ?? jetzt` als `now`.
  - Kandidaten kommen über `CandidateFinding.candidates(…, relativeTo:)`. `when`, 3-h-Fenster und Aktualität beziehen sich damit auf die Aufnahmezeit; spätere Gedanken gelten nicht als „kürzlich“.
  - `ThoughtStructurer(…, models:)` für `paply.thoughts.model`.

### Plan der Folgetage (Budget je Tag ≤ 60 000 für 120b)

| Tag | Stufe | Aufrufe | erwartete Tokens |
| --- | --- | --- | --- |
| 2 | E1 mit Prompt v2: gerade Fälle e02…e36 (e36 im Teile-Modus) | 19 | ≈ 57 000; stoppt der Ledger vor dem letzten Fall, läuft der Rest an Tag 3 |
| 3 | E1 mit Prompt v2: ungerade Fälle e01…e35, Vergleich mit v1 Fall für Fall | 19 | ≈ 57 000 |
| danach | E3 (`medium`, Stabilität), E2 (20b ≤ 40 000), E5 (Kaltstart + Ton) | – | je ≤ 60 000 am Tag |

Befehle: `/tmp/paply-thoughts-eval/run.sh run e1 --cases e02,e04,… --budget 55000` (Wrapper liest den Schlüssel nur in die Umgebung), danach `paply-bench thoughts-eval score e1`.

## Themen mit Beschreibung (Prompt v3), 27.10.: 7 von 8 Fällen, 120b `low`

**Was neu ist:** Ein Thema kann eine Beschreibung haben („Worum geht's?“, `Topic.note`). Treffer findet der Code
(`TopicMentions`), nicht die KI. Der Prompt hat genau eine Zeile mehr (KONZEPT §6.4). Neue Themen, die nur einen
Namen aus einer Beschreibung tragen, leitet der Code auf das beschriebene Thema um (§6.7).

**Satz:** `Tests/Fixtures/Thoughts/described.json`. Er enthält 4 beschriebene Nutzer-Themen ohne Gedanken (Firma
„Kessler Digital“, Kunde „Brandt Logistik“, Verein „Ruderclub“, Person „Oma Ilse“) und dazu store-a. Die 8 Fälle sind
kurz und deutsch, bewertet wird nur das Thema. `expect.mentioned` legt fest, welche Themen der Code als Treffer
markieren soll. Das prüfen `plan` und `swift test` offline; alle 8 Fälle stimmen.

**Lauf:**

- Befehl: `paply-bench thoughts-eval run d1 --set described --ledger described --budget 25000 --tight 1`.
- Budget: eigener Ledger mit hartem Budget von 25 000 Tokens, vom Koordinator freigegeben. Der Ledger des
  Prüfstands stand von E1 Tag 1 noch bei 50 619.
- `--tight`: Ab dem 2. Aufruf rechnet der Wächter mit einer engeren oberen Grenze. Dafür nimmt er die
  Eingabe-Schätzung mal dem größten gemessenen Verhältnis von Groq-Prompt-Tokens zu Schätzung, mal 1,05, und dazu
  das volle `max_completion_tokens`.
- Es gab kein 429.

| Fall | Art | Treffer (Code) | erwartet | erhalten | Tokens |
| --- | --- | --- | --- | --- | --- |
| d01 | Firma, Name | Kessler Digital | Kessler Digital | – (nicht gelaufen, Budget) | – |
| d02 | Kunde, Name gebeugt („Brandts“) | Brandt Logistik, Kessler Digital | Brandt Logistik | Brandt Logistik ✓ | 3 217 |
| d03 | Verein, ohne Namen | – | Ruderclub | Ruderclub ✓ | 2 989 |
| d04 | Person, ohne Namen („meine Großmutter“) | – | Oma Ilse | Familie ✗ | 3 021 |
| d05 | Verein nur beiläufig (Beuel im Umzug) | Ruderclub | Umzug | Umzug ✓ | 3 430 |
| d06 | Firma nur beiläufig (Hauptinhalt Fluxo) | Kessler Digital | Fluxo | Fluxo ✓ | 3 079 |
| d07 | Kunde, ohne Namen (Handscanner, Lagerhalle) | – | Brandt Logistik (auch: Kessler Digital) | Brandt Logistik ✓ | 3 027 |
| d08 | Person mit Namen, Versuchung „Omas Geburtstag“ | Oma Ilse | Oma Ilse | Oma Ilse ✓ | 3 233 |

**Ergebnis: 6/7 richtig, 21 996 Tokens** (Median 3 079, im Mittel 3 142 je Gedanke).

- Alle 7 Antworten waren gültig, und alle Texte überstanden das Sicherheitsnetz.
- Kein neues Thema und kein `mustNotAdd`-Treffer.
- Die Umleitung im Code (`topic:described`) musste kein einziges Mal greifen. Nachtrag (2. Prüfrunde): Diese
  Umleitung über Namen aus Beschreibungen gibt es nicht mehr; Treffer sind nur Hinweise, umgeleitet wird nur ein
  gleicher Titel (KONZEPT §6.7). Das Ergebnis oben bleibt davon unberührt.
- Beide Fälle mit nur beiläufigem Namen folgten dem Hauptinhalt.
- Zwei der drei Fälle ohne Namen wurden über die Beschreibung richtig zugeordnet.

**Nicht gelaufen: d01.** Nach 7 Aufrufen blieben 3 004 Tokens. Die obere Grenze des nächsten Aufrufs lag bei 4 375
Tokens, damit wäre das harte Budget nicht sicher gewesen. d01 ist der einfachste Fall (Firmenname direkt genannt),
der Treffer ist offline geprüft.

**Fehlgriff d04:**

- „Großmutter“ steht nicht in der Beschreibung („Meine Oma Ilse …“). Deshalb gibt es keinen Treffer, und die KI
  nahm das breitere KI-Thema Familie (n = 3).
- Der Code kann Synonyme nicht sicher erkennen.
- Für den Nutzer hilft es, wenn die Beschreibung beide Wörter enthält.
- Für den Prompt wäre ein Nachschärfen der neuen Zeile nur mit einer erneuten Messung sinnvoll (offener Punkt).

**Kosten von v3:**

- Systemprompt: 6 436 → 6 723 Bytes (+287 Bytes ≈ +95 Tokens nach Bytes/3).
- Je beschriebenes Thema kommen in der Nutzer-Nachricht `about` (≤ 200 Zeichen) und bei Treffern
  `"mentioned": true` dazu.
- Themen ohne Beschreibung senden dieselben Felder wie in v2.

Dateien: `/tmp/paply-thoughts-eval/d1.jsonl`, `d1-p3-r1-120b-low-results.json`, `d1-p3-r1-120b-low-review.md`.

## Prompt v4 (Befunde vom iPhone), 27.10.: Lauf p4

**Anlass:** Auf Allans iPhone (Prompt v3, 120b `low`) kamen Aufgaben fast wörtlich und klein („bei meiner Firma … noch die
neuesten … einmal bearbeiten“), der Zeitausdruck stand doppelt in Text und `due_hint` („morgen einkaufen gehen“ + „morgen“),
einmalige Besorgungen wurden eigene Themen („… Einkauf“, „<Person> Schrank“), und ein fester Termin des Sprechers (Kunde
kommt um 10 Uhr) ergab keine Aufgabe.

**Prompt v4** (KONZEPT §6.4): genau drei neue Sätze, sonst unverändert. Systemprompt 6 723 → 7 230 Bytes (+507 ≈ +169
Tokens nach Bytes/3), Zeichen 6 668 → 7 174; Kurzprompt der Folgeteile +307 Bytes.

1. TASKS, `text`: „Keep it to the core, about 2 to 6 words: leave out particles ("noch", "mal", "eben", "just"),
   self-references ("ich", "mein", "my") and the time expression, which belongs in due_hint.“
2. TASKS: „A fixed appointment the speaker must attend at a set time (a meeting, a visit to or from someone) is a task
   with due_hint.“ Die Liste der Nicht-Aufgaben (Ideen, Möglichkeiten, Handlungen anderer) bleibt.
3. TOPIC, `new`: „A one-off errand, purchase or appointment is not a topic: name the ongoing area instead (person,
   project, place, area of life), e.g. "Tilda", not "Tilda Schrank"; "Einkäufe", not "Baumarkt Einkauf".“

**Im Code** (`Thoughts/AI/TaskText.swift`, im Validator vor den Prüfungen; nur Weglassen am Rand und Großschreiben):

- Erster Buchstabe groß („übergabe …“ → „Übergabe …“); Ziffern am Anfang bleiben, „iPhone“/„eBay-Konto“ bleiben.
- Zeitausdruck, der wörtlich `due_hint` ist, fällt am Anfang oder Ende weg; nicht, wenn er eine Verneinung enthält.
- „noch“/„mal“/„eben“ am Anfang nur vor großgeschriebenem Wort oder bestimmtem Artikel, am Ende nur nach einem
  kleingeschriebenen Infinitiv. „noch nicht …“, „noch einen …“, „noch mal …“, „erst mal“, „nächstes Mal“ bleiben.
- `due_hint` darf aus ≤ 3 Stücken des Zitats in Reihenfolge innerhalb von ≤ 20 Wörtern bestehen („morgen vormittags“,
  „morgen um 10 Uhr“ aus zwei Satzteilen); wörtlich gilt jetzt an Wortgrenzen („morgen“ steckt nicht in „übermorgen“).
- `beim`, `vom`, `ins`, `ans` gelten wie `zum`/`im`/`am` als kleine Wörter ohne Beleg.
- „Nur Wörter des Sprechers“ bleibt vereinbar: Der Kern ist eine Teilmenge der Wörter des Zitats; Infinitiv und
  Reihenfolge deckt der Abgleich über Lemma/Wortanfang, und ein freies Wort („empfangen“, „nutzen“) war schon erlaubt.

**Offline nachbewertet** (gespeicherte Antworten, keine neuen Aufrufe): E1 Tag 1 (v1, 18 Fälle) und d1 (v3, 7 Fälle)
ergeben dieselben Kennzahlen wie zuvor (Präzision, Recall, `due_hint`, Thema, Prüfer-Codes). Geändert haben sich nur
Aufgabentexte, alle zum Besseren: 7 Texte großgeschrieben, 6 ohne doppelten Zeitausdruck, z. B. „morgen früh Termin beim
Bürgeramt … buchen“ → „Termin beim Bürgeramt in Bonn für Ummeldung buchen“, „Donnerstag vor Ort anschauen“ → „Vor Ort
anschauen“ (due „Donnerstag“). Form der gespeicherten Aufgaben in E1: 12/15 ohne Befund (roh 5/15).

**Diagnose:** Die Verarbeitung schreibt jetzt ins Diagnoseprotokoll (KONZEPT §6.8, `ThoughtTrace`): Beginn/Ende von
Umschrift und Ordnung mit Dauer, je Groq-Aufruf Modell, Tokens, Status und nächster Schritt, Wartegründe. Nie Text.

**Plan des Laufs p4 (so gelaufen):**

- Satz `Tests/Fixtures/Thoughts/prompt4.json` (README §11): 6 neue Fälle n01–n06 und 6 Regressionsfälle e03, e06, e07,
  e10, e18, e26 – zusammen 12 Aufrufe, kein Teile-Modus.
- Nur `openai/gpt-oss-120b`, `low`; eigener Ledger `prompt4` mit hartem Budget 45 000 Tokens, `--tight 1`, Abbruch beim
  ersten 429.
- Obere Grenze laut `plan`: 64 897 Tokens (Eingabe/3 + `max_completion_tokens` + 256); erwartet nach E1/d1 ≈ 3 000–3 300
  je Aufruf, also ≈ 37 000–40 000. Reicht das Budget nicht, entfallen die letzten Regressionsfälle (die neuen Fälle laufen
  zuerst).
- Dauer: Minutenfenster 7 600 Tokens → etwa 2 Aufrufe pro Minute, ≈ 7–8 Minuten.
- Befehl: `/tmp/paply-thoughts-eval/run-p4.sh` (baut den Prüfstand, liest den Schlüssel nur in die Umgebung, `run p4`,
  danach offline `score p4`; Ausgabe in `/tmp/paply-thoughts-eval/p4.log`, `p4-p4-r1-120b-low-results.json`, `…-review.md`).

### Ergebnis p4 (27.10. abends, 120b `low`, Prompt v4)

12 Aufrufe, **37 293 Tokens** (Median 3 140, p95 3 330; Schätzung des Ledgers ≈ 5 400 je Aufruf), kein 429, etwa 7 Minuten.
Dateien: `/tmp/paply-thoughts-eval/p4-run.out`, `p4-p4-r1-120b-low-review.md`; offline mit dem Stand v4.1 (Code und Prüfstand,
siehe unten) nachbewertet: `p4r-p4-r1-120b-low-review.md`.

| Kriterium | wie gelaufen | nachbewertet (v4.1-Code und -Prüfstand) |
| --- | --- | --- |
| gültig · Text übersteht das Netz · `mustKeep` | 12/12 · 12/12 · 36/36 | gleich |
| Thema `existing` korrekt · neu statt bestehend · `none` richtig | 7/8 · 1/8 (e26) · 2/3 (n05) | gleich |
| `mustNotAdd`-Treffer | 1 (n05 Thema „Reisepass“) | 2 (dazu n03 Aufgabentext „kaufen“) |
| Aufgaben-Präzision | 9/9 (Prüfstand zu nachsichtig) | **8/9** – n03 falsch |
| Aufgaben-Recall | 8/11 | **7/11** |
| `due_hint` korrekt | 8/8 | 7/7 |
| Form der Aufgabentexte, gespeichert · roh | 8/9 · 9/11 | 9/9 · 9/11 |

**Je Fall:**

- **Besser:** n01 „Briefe vom Steuerbüro durchlesen“ (statt fast wörtlich mit „noch … einmal“), n02 „Einkaufen gehen“ mit
  due „morgen am besten vormittags“ (aus der Rohantwort „einkaufen gehen“ macht der Code den Großbuchstaben) und „Jana
  Einkaufsliste schicken lassen“, Thema Familie; e07 „Priya updated deck senden“; n04 „Laufrad kaufen“, Thema „Patenkind“
  (die Person, kein „Laufrad“).
- **n03 (Termin) – falsch:** Aufgabe „20 Fluxo Lizenzen kaufen“, due „morgen um 10 Uhr“. Das ist die Handlung des Kunden als
  To-do des Sprechers, irreführender als keine Aufgabe. Der Prüfstand hatte sie über das Zitat als ✓ gezählt; jetzt
  machen `mustNotAdd`-Muster im Aufgabentext (`kaufen`, `kauft`, `vorbeikommen`, `kommt vorbei`) sie zu einem
  Präzisionsfehler, der nie für den Recall zählt.
- **n05:** neues Thema „Reisepass“ (einmaliger Behördengang, `mustNotAdd`); Text „Reisepass bis Ende November verlängern“
  mit due „bis Ende November“ – die Zeit stand doppelt in der Mitte (der v4-Code nahm sie nur am Rand weg).
- **e26:** neues Thema „Milas Schwimmkurs“ statt Familie (stand im Index an erster Stelle); „Schwimmsachen durchsehen“
  fehlt (Recall 1/2).
- **n06** (`task:negation`: „Bescheid sagen beim Fitnessstudio Hantelhaus“ ohne das „nicht verlängern“ des Zitats) und
  **e06** (`task:quote`: das Zitat „ich muss bis Mittwoch den Keller freiräumen“ löst die Selbstkorrektur auf) hat der
  Prüfer verworfen. Bekannt und streng, bewusst noch nicht angegangen.
- e03, e10 ohne Aufgabe und mit richtigem Thema; e18 neues Thema „Bambini-Training“ (richtig); kein Termin-Fehlalarm bei
  e07 (Priyas Meeting), e10 und e26 („samstags um zehn“).

### Prompt v5 („v4.1“) und Code, nach p4

`ThoughtPrompt.version = 5`: Jeder neue Wortlaut bekommt eine eigene Nummer, damit gespeicherte Ergebnisse
(`ai.promptVersion`, Prüfstand `--prompt`) eindeutig bleiben. Die zwei Sätze aus v4 sind umformuliert, keiner ist dazugekommen.
Systemprompt 7 230 → 7 461 Bytes (+231 ≈ +77 Tokens), Zeichen 7 174 → 7 403.

1. Termin: „A fixed appointment the speaker must attend at a set time (a meeting, a visit to or from someone) is a task with
   due_hint; its text names the speaker's part ("Termin mit Frau Roth", "Frau Roth empfangen"), never what the other person
   does.“
2. Thema: „A one-off errand, purchase or appointment is not a topic, and whatever a listed topic covers belongs there (a
   child's dentist appointment → the family topic); only if none fits, name the ongoing area (person, project, place, area
   of life), e.g. "Tilda", not "Tilda Schrank"; "Einkäufe", not "Baumarkt Einkauf".“ Das Beispiel ist bewusst kein Kurs,
   damit e26 die Verallgemeinerung misst.

**Code:** `due_hint` fällt jetzt auch in der **Mitte** des Aufgabentexts weg, wenn er dort wörtlich und zusammenhängend steht,
keine Verneinung enthält, danach ≥ 2 Wörter bleiben und das Wort davor ihn nicht regiert („Anna wegen Freitag anrufen“, „Kuchen
backen für morgen“ bleiben; das gilt jetzt auch am Ende). „Reisepass bis Ende November verlängern“ → „Reisepass verlängern“.

**Deterministischer Themen-Schutz – geprüft, nicht gebaut:** Ein neuer Name, dessen Kandidaten einem vorhandenen Thema
angehören, auf dieses umzuleiten, wäre in p4 dreimal falsch gewesen (e26 → Auto/Fitness, n05 → Freunde, e18 → Auto). Auch
„erstes Thema des Index“ hätte n05 auf Freunde gelegt. Nicht eindeutig sicher, also weggelassen.

**Prüfstand:** `mustNotAdd` mit `tasks` macht eine Aufgabe falsch (Präzisionsfehler, nie Recall), auch wenn ihr Zitat passt.
In `prompt4.json` hat n03 diese Muster; e06 verzichtet auf die due-Regel „Donnerstag“ (die Keller-Frist prüft schon
„`due_hint` korrekt“, und die zulässige Besichtigungs-Aufgabe darf „am Donnerstag um neun“ tragen).

### Nachlauf p4b (vorbereitet, wartet auf Freigabe)

- 6 Fälle: n03, n05, e26, n02, n04, e06 (in dieser Reihenfolge), Prompt v5, nur `openai/gpt-oss-120b` `low`.
- Eigener Ledger `prompt4b`, hartes Budget 22 000 Tokens, `--tight 1`, Abbruch beim ersten 429.
- Erwartet nach p4 ≈ 3 000–3 350 je Aufruf, zusammen ≈ 19 000; etwa 3 Minuten (2 Aufrufe pro Minute).
- Befehl: `/tmp/paply-thoughts-eval/run-p4b.sh` (Ausgabe `p4b.log`, `p4b-p5-r1-120b-low-results.json`, `…-review.md`).

