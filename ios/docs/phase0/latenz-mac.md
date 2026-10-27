# Paply iOS – Latenz- und Qualitätsmessung auf dem Mac mini (Phase 0)

Stand: 27.10.2026. Gemessen mit `paply-bench` (ios/PaplyKit, Release-Build) gegen die echte Groq-API.

> **Wichtig:** Mac-Netz ≠ iPhone-Netz. Der Mac mini hängt an einer schnellen, stabilen Leitung. Auf dem iPhone (LTE/5G, wechselndes WLAN) dauern Upload und Verbindungsaufbau deutlich länger. Die Millisekunden hier taugen **nur zum Vergleich von Modellen und Architektur** (Stücke, Vorwärmen, Format). Sie sind keine Zusage für das Gerät.

## Kurzfassung und Empfehlung

**Empfehlung für V1** (entspricht den Standardwerten in PaplyKit):

| Stellschraube | Empfehlung | Begründung |
|---|---|---|
| Modell | **`whisper-large-v3`** | Mit Stücken ist turbo nicht schneller (±60 ms). v3 ist genauer (WER 0,005–0,024 gegen 0,013–0,119) und hält Sprachwechsel. turbo machte bei mix-8 in 3/3 Läufen den deutschen Satzanfang englisch. Kosten $0,111/h gegen $0,04/h, absolut klein. |
| Stücke | **an** | Ab ~30 s halbiert sich die Wartezeit. ~28 s: 862–906 → 400–505 ms. ~68 s: 1705–1779 → 775–781 ms. Auch beim sofortigen Stopp spart es bei ~68 s ~0,9 s Transkription. Kein Qualitätsverlust; alle Schnitte liegen in Pausen. |
| Vorwärmen | **an**, bei erkannter Sprache, höchstens alle paar Minuten | Auf dem Mac 30–70 ms beim kurzen Diktat. Auf dem iPhone ist mehr zu erwarten (Verbindungsaufbau 150–400 ms). Kostet nur ein `HEAD`. |
| Format | **FLAC** | Auf dem Mac gleichauf mit WAV, aber gut ein Drittel kleiner. Das zählt auf dem iPhone-Uplink. |
| Sprachwechsel-Primer | **an** | Mischsprache gehalten: 6/18 → 15/18 Läufe. Ohne Nebenwirkung auf einsprachiges Audio. Nach dem Review auf einen Satz ohne Fachwörter umgestellt und nachgemessen (Befund 1). |

Was nach dem Tippen auf Stopp übrig bleibt (Stücke an, Vorwärmen an, v3, Mac-Netz):

| Diktat | Nutzer stoppt nach ≥ 0,6 s Pause | Nutzer stoppt sofort (0,25 s nach dem letzten Wort) |
|---|---|---|
| ~7 s | ~0,44 s (0,3 s Transkription + 0,13 s Polieren) | gleich |
| ~28 s | ~0,4 s (nur Polieren) | ~0,6–0,8 s (Rest 4–17 s transkribieren: 0,3–0,5 s, plus Polieren ~0,3 s) |
| ~68 s | ~0,8 s (letztes Stück 0,25 s + Polieren 0,5 s) | ~0,75–0,9 s (Rest 4–15 s: 0,24–0,4 s, plus Polieren ~0,5 s) |

Ohne Stücke wären es bei ~68 s 1,7–1,8 s. Das Polieren (qwen, 0,13–0,6 s, wächst mit der Textlänge) ist der größte Restposten.

## Hauptmessung: Modell × Stücke × Vorwärmen

180 Läufe: 9 Audios, 3 Läufe je Konfiguration, FLAC, mit Sprachwechsel-Primer. **Kein Fehler.** Kein Ausreißer deutet auf ein abgefangenes 429 hin (längster Lauf 2,7 s; ein Neuversuch wartet ≥ 1 s). Das Sicherheitsnetz griff nie, poliert hat immer qwen. Werte sind Mediane über Deutsch, Englisch und Gemischt (n = 9 je Zeile). WER ist der Mittelwert der Rohtranskription.

| Länge | Modell | Stücke | Vorwärmen | finish → Text | davon Transkription | davon Polieren | WER roh | Sprache gehalten |
|---|---|---|---|---|---|---|---|---|
| ~7 s | v3 | – | aus | 510 ms | 373 ms | 130 ms | 0,024 | 9/9 |
| ~7 s | v3 | – | an | 439 ms | 280 ms | 133 ms | 0,024 | 9/9 |
| ~7 s | turbo | – | aus | 465 ms | 324 ms | 138 ms | **0,119** | **6/9** |
| ~7 s | turbo | – | an | 434 ms | 304 ms | 135 ms | **0,119** | **6/9** |
| ~28 s | v3 | aus | aus | 862 ms | 565 ms | 308 ms | 0,005 | 9/9 |
| ~28 s | v3 | aus | an | 906 ms | 632 ms | 288 ms | 0,005 | 9/9 |
| ~28 s | v3 | **an** | aus | 505 ms | 1 ms | 469 ms | 0,005 | 9/9 |
| ~28 s | v3 | **an** | an | **400 ms** | 0 ms | 308 ms | 0,005 | 9/9 |
| ~28 s | turbo | aus | aus | 758 ms | 459 ms | 291 ms | 0,015 | 9/9 |
| ~28 s | turbo | aus | an | 795 ms | 463 ms | 337 ms | 0,015 | 9/9 |
| ~28 s | turbo | **an** | aus | 487 ms | 0 ms | 450 ms | 0,015 | 9/9 |
| ~28 s | turbo | **an** | an | **337 ms** | 0 ms | 307 ms | 0,015 | 9/9 |
| ~68 s | v3 | aus | aus | 1705 ms | 1155 ms | 510 ms | 0,011 | 9/9 |
| ~68 s | v3 | aus | an | 1779 ms | 1259 ms | 532 ms | 0,011 | 9/9 |
| ~68 s | v3 | **an** | aus | 781 ms | 230 ms | 573 ms | 0,011 | 9/9 |
| ~68 s | v3 | **an** | an | **775 ms** | 251 ms | 504 ms | 0,011 | 9/9 |
| ~68 s | turbo | aus | aus | 1399 ms | 877 ms | 510 ms | 0,017 | 9/9 |
| ~68 s | turbo | aus | an | 1393 ms | 866 ms | 523 ms | 0,017 | 9/9 |
| ~68 s | turbo | **an** | aus | 743 ms | 198 ms | 583 ms | 0,013 | 9/9 |
| ~68 s | turbo | **an** | an | **798 ms** | 210 ms | 518 ms | 0,013 | 9/9 |

Upload: ~7 s ≈ 125–140 KB, ~28 s ≈ 550–580 KB, ~68 s ≈ 1,3–1,4 MB (FLAC). Mit Stücken gleich viel Bytes, nur verteilt auf 2–6 Anfragen während des Sprechens. Die Tabelle je Audio steht im Anhang.

**Was die Zahlen sagen:**

- **Stücke** halbieren die Wartezeit ab ~30 s. Bei ~28 s ist die Transkription beim Tippen auf Stopp schon fertig (0 ms). Bei ~68 s fehlt nur noch das letzte Stück (~200–250 ms). Danach dominiert das Polieren (0,3–0,6 s).
  - Bei ~28 s fällt der letzte Schnitt hier in die ≥ 0,6 s Stille nach dem letzten Wort. Stoppt der Nutzer sofort, bleiben 0,24–0,5 s Transkription (Zusatzmessung unten).
- **turbo gegen v3:**
  - Ohne Stücke ist turbo bei ~68 s 300–390 ms schneller, bei ~28 s ~110 ms, bei ~7 s kaum (≤ 45 ms).
  - Mit Stücken verschwindet der Unterschied (±60 ms, im Rauschen).
  - Qualität: turbo macht durchweg mehr Fehler. Vor allem hielt es den Sprachwechsel in **mix-8 in 0/3 Läufen**: „Ich habe den Pull Request gemerged, aber the build is still failing“ wurde zu „**I noticed the pull request**, but the build …“. v3 lag 3/3 richtig.
- **Vorwärmen:**
  - Ohne Stücke spart es auf dem Mac 30–70 ms beim kurzen Diktat. Die TLS-Verbindung zu Groq steht hier in ~40 ms (curl: `time_appconnect`). Bei langen Diktaten ist der Effekt nicht messbar.
  - Mit Stücken wirkt es über die Modellliste: Ohne Vorwärmen holte die damalige Version sie erst nach `finish()`, das kostete 65–160 ms (Polieren bei ~28 s 450–470 statt ~308 ms).
  - Inzwischen wird die Liste schon beim ersten Stück mitgeladen und bei Ablauf nur noch im Hintergrund erneuert. Diese Lücke ist im Code geschlossen.
  - Auf dem iPhone (LTE/5G: DNS + TCP + TLS meist 150–400 ms) zählt Vorwärmen deutlich mehr als hier.

## Aufbau der Messung

- **Audio:** Mit `say` erzeugt (Rate 155 Wörter/min, typisch fürs Diktieren). Stimmen: Anna (de_DE) und Samantha (en_US). Je drei Längen (~7 s, ~28 s, ~65–70 s) mit natürlichen Pausen (`[[slnc 600–900]]`).
  - **Deutsch**: Terminabsprache, Team-Zusammenfassung.
  - **Englisch**: dieselben Inhalte englisch.
  - **Gemischt**: Deutsch mit englischen Fachbegriffen (Pull Request, Deployment, Staging, Token Refresh …). Dazu Sprachwechsel **mitten im Satz**, also deutscher Satzanfang (Anna) und englisches Satzende (Samantha) nach nur 120–150 ms Pause. In mix-75 kommen zwei längere englische Passagen hinzu.
  - Allen Aufnahmen liegt ein Raumrauschen von −60 dBFS unter, damit VAD und Pausenerkennung realistisch arbeiten. Die Dateien liegen unter `/tmp/paply-bench-ios/`, nicht im Repo.
- **Einspeisung in Echtzeit:** Blöcke à 100 ms, so wie das Mikrofon sie liefert, danach `finish()`. Gemessen wird ab `finish()`.
  - Echtzeit gilt immer, sobald Stücke oder Vorwärmen an sind.
  - Nur „Stücke aus, Vorwärmen aus“ wird sofort eingespeist. Vor `finish()` passiert dort kein Netzverkehr, die Zahlen ändern sich also nicht.
- **Kalte Verbindung je Lauf:** Jeder Lauf hat eine eigene `URLSession` und einen eigenen Modell-Cache.
  - „Vorwärmen an“ ruft `prewarm` bei Aufnahmebeginn auf, parallel zur Aufnahme (so macht es die App).
  - „Vorwärmen aus“ beginnt ohne bestehende Verbindung.
- **Matrix:**
  - `whisper-large-v3` gegen `whisper-large-v3-turbo`, Stücke an/aus, Vorwärmen an/aus, je 3 Läufe.
  - Bei ~7 s fällt „Stücke an“ weg. Unter 10 s wird nie geschnitten, es wäre also identisch mit „Stücke aus“.
  - Polieren immer mit `qwen/qwen3.8-27b`.
- **Kennzahlen je Lauf:**
  - Zeit „finish → Text fertig“, getrennt nach Transkription und Polieren.
  - Upload-Bytes und erkannte Sprache(n).
  - Polier-Ergebnis: passiert oder Grund des Sicherheitsnetzes.
  - Wortfehlerrate (WER) gegen den Skripttext, roh und nach dem Polieren.
  - „Sprache gehalten“: Mindestens 70 % der Inhaltswörter (≥ 4 Buchstaben) **jeder** Sprache des Skripts stehen im Ergebnis. Wird eine Passage übersetzt oder verschluckt, bricht der Wert für ihre Sprache ein.
- **Rate-Limits:** Der Schlüssel liegt im Free-Tier, die Header zeigen 2000 Transkriptionen/Tag. Daraus folgen laut Groq 20/min und 7200 Audiosekunden/h; beim Chat sind es 1000/Tag und 8000 Tokens/min. Deshalb laufen alle Messungen nacheinander. Schnelle Läufe werden zusätzlich gebremst.

## Befund 1: Whisper verschluckt oder übersetzt Sprachwechsel – behoben durch einen Primer

Erster Rauchtest (mix-30, ohne Prompt): Der englische Satz mitten im deutschen Diktat („… und *he thinks the issue is caused by the new caching layer in the backend*. …“) fehlte in 7 von 8 Läufen **stillschweigend**. In einem Lauf hat `whisper-large-v3` ihn **ins Deutsche übersetzt** („Er denkt, dass die Frage vom neuen Caching-Layer im Hintergrund ist.“).

- Die Segment-Zeitstempel zeigen dabei keine Lücke. Whisper schlägt die Zeit dem nächsten deutschen Segment zu, eine Erkennung über Lücken ist also nicht möglich.
- Ursache: Whisper legt pro Anfrage eine Sprache fest (hier „German“). Eine kurze Passage in einer anderen Sprache wird dann ausgelassen oder übersetzt.
- Dasselbe passiert mit französischem Audio und einem englischen Einschub.
- Für Paplys Kernversprechen („spricht jede Sprache, auch gemischt“) ist das der wichtigste Befund dieser Phase.

**Lösung: Sprachwechsel-Primer im Whisper-`prompt`.** Er besteht aus einem kurzen Beispiel mit Sprachwechsel mitten im Satz. Die Hauptmessung lief noch mit „Kurzes Update: Das Deployment ist durch, and the build is green now. Ich schreibe dir später, see you tomorrow.“ Seit dem Review gilt „Kurzes Update: Das Meeting ist verschoben, and the new date is next Friday. Ich schreibe dir später, see you tomorrow.“ (Nachmessung unten).
- Gebildet wird er aus den Sprachen des Nutzers: `PaplySettings.spokenLanguages`, sonst die Gerätesprachen. Sätze gibt es für DE/EN/FR/ES/IT/PT/NL/TR/PL.
- Gesendet wird er nur, wenn mindestens **zwei** Nutzersprachen einen Satz haben. Ein erfundenes EN/DE-Paar für andere Sprachen entfällt.

Erste Sondierung mit dem alten Satz (einzelne Anfragen):

| Audio | ohne Primer | mit Primer |
|---|---|---|
| mix-30, v3 | englischer Satz fehlt | wörtlich da |
| mix-30, turbo | englischer Satz fehlt | wörtlich da |
| Französisch + englischer Einschub, v3 | englischer Satz fehlt | wörtlich da, mit FR/EN- **und** mit DE/EN-Primer |
| en-30 (rein englisch), v3, DE/EN-Primer | – | unverändert fehlerfrei |
| mix-75 (längere englische Passagen), v3 | korrekt | korrekt |

Der Primer kostet höchstens 64 von 200 Prompt-Tokens (konservativ geschätzt; Whisper erlaubt 224). Danach folgen die eigenen Begriffe (≤ 90) und das Ende des Vorstücks.

**Echos:** Wiederholt Whisper Teile des Prompts, wird das Segment entfernt – aber nur, wenn die VAD in seinem Zeitraum weniger als 100 ms stimmhafte Sprache je Wort misst. Als Echo zählen ≥ 3 Wörter am Stück aus dem Beispielsatz (zwei Wörter wie „bis morgen“ werden oft wirklich gesagt, und bei viel Lärm misst die VAD womöglich zu wenig Stimme), ≥ 2 Wörter vom Ende des Vorstücks oder eine Wortfolge fast nur aus eigenen Begriffen. Wer „Ich schreibe dir später.“ wirklich diktiert, bekommt es also; ein Echo über Stille oder Atmen verschwindet. Wiederholt ein Stück am Anfang das Ende des Vorstücks, wird die Doppelung beim Zusammenfügen entfernt.

Die systematische Messung mit/ohne Primer steht unten.

**Systematisch (je 3 Läufe, Stücke aus, Vorwärmen an):**

| Audio | Modell | ohne Primer: gehalten · WER | mit Primer: gehalten · WER |
|---|---|---|---|
| mix-8 | v3 | 3/3 · 0,071 | 3/3 · 0,071 |
| mix-8 | turbo | **0/3** · 0,357 | **0/3** · 0,357 |
| mix-30 | v3 | **0/3** · 0,212 | 3/3 · 0,000 |
| mix-30 | turbo | **0/3** · 0,212 | 3/3 · 0,030 |
| mix-75 | v3 | 3/3 · 0,019 | 3/3 · 0,032 |
| mix-75 | turbo | **0/3** · 0,174 | 3/3 · 0,039 |
| de-30 | v3 / turbo | 3/3 · 0,015 / 0,015 | 3/3 · 0,015 / 0,015 |
| en-30 | v3 / turbo | 3/3 · 0,000 / 0,000 | 3/3 · 0,000 / 0,000 |

- Ohne Primer hielten die gemischten Diktate die Sprache in **6/18** Läufen, mit Primer in **15/18**. Die verbleibenden 3 Ausfälle sind alle turbo bei mix-8: Es macht dort den deutschen Satzanfang englisch, mit und ohne Primer.
- Auf einsprachiges Audio hat der Primer weder bei WER noch bei Latenz einen messbaren Einfluss.
- Hinweis: Die WER „mit Primer“ für mix-75 v3 (0,032) enthält Schreibvarianten wie „Design-System“ gegen „Design System“; die Sprachanteile sind vollständig.

**Nachmessung nach dem Review** (v3, eine Anfrage je Zeile außer wo angegeben, Temperatur 0 und damit reproduzierbar). Das Review verlangte neutrale Sätze ohne Entwickler-Jargon.

| Audio | Alltagssätze („Ich gehe heute Nachmittag einkaufen, and then I'll call you …“) | Arbeits-Update ohne Fachwörter („Das Meeting ist verschoben, and the new date is next Friday …“) – **eingebaut** |
|---|---|---|
| mix-8 | 3/3 gehalten · 0,071 | gehalten · 0,071 |
| mix-30 | **0/3** – englischer Satz fehlt (0,212) | gehalten · 0,000 |
| mix-75 | **0/2** – englische Passagen **übersetzt** („Wir sollten nichts in Mainl merken …“), Teile fehlen (0,48) | gehalten · 0,032 |
| fr-mix (Französisch + englischer Einschub, FR/EN) | 2/2 gehalten · 0,02 | gehalten · 0,02 |
| de-30 / en-30 | unverändert (0,015 / 0,000) | unverändert (0,015 / 0,000) |
| de-bild („Schick mir bitte das Bild …“, 2× „Bild“) | 3/3 „Bild“ | „Bild“ (auch mit dem alten „Build“-Satz: „Bild“) |
| mix-30, turbo | 2/2 gehalten | – |

- Der Inhalt des Beispiels entscheidet. Alltagssätze ließen v3 wieder verschlucken und übersetzen, schlechter als ganz ohne Primer.
- Ein kurzes Arbeits-Update im gleichen Aufbau wirkte wie der alte Satz, ohne dessen Fachwörter.
- Die Sorge „Bild“ → „Build“ bestätigte sich in keiner Variante.
- Verbrauch der Nachmessung: 27 Transkriptionen, 673 s Audio, kein Chat-Aufruf.

## Befund 2: Polieren – englischer Prompt hält die Sprachen, Eingriffe minimal

Die Anweisungen sind englisch: Ein deutscher Systemtext zieht das Modell Richtung Deutsch, und Englisch bevorzugt keine Diktatsprache. A/B auf den 9 echten Rohtexten der Messung (qwen, Temperatur 0) mit drei Prompts: englisch (eingebaut), englisch mit strengerer Regel gegen Synonyme und Gendern, Desktop-Prompt (deutsch).

- Alle drei lieferten praktisch dieselben, minimalen Eingriffe: Satzzeichen, Großschreibung, „gemerget“ → „gemerged“. **Kein** Prompt übersetzte, alle hielten de/en vollständig.
- Der Desktop-Prompt strich einmal ein Wort („Vielen Dank dir!“ → „Vielen Dank!“).
- Die strengere Fassung brachte keinen messbaren Vorteil und wurde nicht übernommen.
- In der Hauptmessung gab es einen Ausreißer: Ein Lauf auf de-75 machte „zwei Wochen“ → „zwei Woche“, „Kunden“ → „Kundinnen und Kunden“ und „schlage“ → „schlag“. Das Sicherheitsnetz lässt so kleine Eingriffe durch (unter den Grenzen für Inhalt und Zusätze). Häufigkeit siehe unten.

Häufigkeit in der Hauptmessung: In 19 von 180 Läufen änderte das Polieren Wörter (nicht nur Satzzeichen oder Großschreibung). Fast alles waren richtige Hörfehler-Korrekturen: 8× „Buckend“ → „Backend“, 8× „Unboarding“ → „Onboarding“, 4× „gemerget“ → „gemerged“, 6× „3. Müssen“ → „Drittens müssen“ (so gesprochen). Falsch waren 4× „Im Daily **Morgan**“ → „Im Daily **Morning**“ (gesprochen war „morgen“; die Korrektur landete in der falschen Sprache) und der eine Ausreißer-Lauf oben. Das sind ~3 % der Läufe mit einem sinnverändernden Eingriff, den das Netz nicht erkennt (offener Punkt).

**Neue Netzregeln nach Review und Nachprüfung:**
- **Zahlen:**
  - Ziffernfolgen, zwischen denen nur Leerzeichen, Satzzeichen oder ein Doppelpunkt stehen, werden auf beiden Seiten zusammengezogen und so verglichen: „15.30“ = „15:30“, „0171 123 45 67“ = „0171 1234567“, „1.000“ = „1000“.
  - Jede Zahl des Rohtexts muss in Reihenfolge im Ergebnis stehen, als gleiche Ziffern oder als Zahlwort gleichen Werts („3.“ → „Drittens“).
  - **Neue Zahlen sind verboten.** Das gilt auch für „15 Uhr“ → „15:00 Uhr“; dann bleibt der Rohtext. Ausnahme: ein Zahlwort des Rohtexts als Ziffer („drei Uhr“ → „3 Uhr“).
- **Selbstkorrektur** („um 15 Uhr, ich meine um 16 Uhr“):
  - Eine Rohtext-Zahl darf nur fehlen, wenn nach Komma oder Gedankenstrich ein eindeutiger Marker folgt (ich meine, Moment, warte, sorry, I mean, wait, je veux dire, quiero decir, voglio dire, ik bedoel …; nicht „eigentlich/doch/enfin“) und danach eine Ersatzangabe.
  - Das Netz prüft dann zusätzlich die aufgelöste Lesart: Marker samt „nein/no“ und so viele Wörter davor, wie die Ersatzangabe hat (höchstens 6, nie über ein Satzende).
  - **Entscheidung zur 30-%-Inhaltsgrenze:** Kurze Korrektursätze fielen sonst an Länge oder Inhalt durch, z. B. „Wir treffen uns um 15 Uhr, ich meine um 16 Uhr.“ → „Wir treffen uns um 16 Uhr.“ (Länge 0,57).
  - Deshalb gilt für sie die Untergrenze von Länge und Inhalt gegen die aufgelöste Lesart; die Obergrenze 1,3 weiter gegen den gesprochenen Text.
  - Ohne Marker bleibt alles beim Alten: kein Wegfall von Zahlen, volle Grenzen.
- **Verneinung:**
  - „no/non/nee/nein“ mitten im Satz zählen nur, wenn kein Satzzeichen und kein Korrekturwort folgt („no problem“ ja, „…, no wait, …“ nein).
  - **Am Satzanfang zählen sie immer, egal ob danach ein Komma steht** („Nein das passt …“ = „Nein, das passt …“).
  - Abweichung von der Nachprüfung, die „nie zählen“ vorschlug: Im Spanischen, Italienischen und Portugiesischen verneint satzinitiales „No/Non“ das Verb („No quiero ir“). „Nie zählen“ ließe dort eine gestrichene Verneinung durch. Aufgelöste Selbstkorrekturen am Satzanfang deckt die aufgelöste Lesart ab.
- **Wortgenaue Prüfung von Ersetzungen** (`strictPolishCheck`):
  - Zögerlaute und direkte Doppelwörter („ich ich“) fallen vor dem Vergleich aus dem Rohtext.
  - Ausrichtung per LCS. In jeder Lücke bekommt jedes Ergebniswort das **nächste passende** Rohwort; übersprungene Rohwörter gelten als gelöscht. Vorher wurde stur nach Position gepaart, sodass „ich glaube äh das er“ → „…, dass er“ fälschlich fiel.
  - Passend heißt: gleich, Schreibvariante („ok“ ↔ „okay“), kleine Korrektur (Damerau-Levenshtein ≤ max(1, ⌊Länge/4⌋)), Ziffer ↔ Zahlwort, Zusammen- oder Getrenntschreibung.
  - Nach einer Mengenangabe („zwei Wochen“) darf sich das Wort gar nicht ändern.
  - Neue Inhaltswörter sind nur als eigener Begriff oder Umstellung erlaubt.

**Offline gegen alle gespeicherten Polituren geprüft** (`paply-bench netcheck`): main, primer, formats, Rauchtest und A/B, ohne Netzaufrufe. Nach der Nachprüfung (Zuordnung je Lücke, Zögerlaute, Doppelwörter, Schreibvarianten, Zahlenregel) neu gezählt, mit unverändertem Ergebnis:

| | Läufe | verschiedene Polituren |
|---|---|---|
| gesamt | 275 | 27 |
| mit Wortänderung (nicht nur Satzzeichen/Groß-klein) | 38 | 7 |
| vom alten Netz verworfen | 0 | 0 |
| **vom neuen Netz verworfen** | **12** | **3** |

- **Alle 12 verworfenen Läufe enthalten eine sinnverändernde Ersetzung:** 11× „Morgan“ → „Morning“ statt „morgen“ und 1× der Ausreißer mit „zwei Woche“, „Kundinnen und Kunden“ und „dafür“ → „dazu“.
- **Keine rein gute Politur wurde verworfen.** Durch gingen „Buckend“ → „Backend“, „Unboarding“ → „Onboarding“, „gemerget“ → „gemerged“ und „3.“ → „Drittens“.
- Der Preis: In den Morning-Läufen gehen die guten Korrekturen Backend und Onboarding mit verloren, weil ein ganzer Lauf als Rohtext eingesetzt wird.
- Die Regel bleibt deshalb **an**. Sie lässt sich über `PipelineOptions.strictPolishCheck` abschalten.
- Zusätzlich als Regressionstests: „ich glaube äh das er …“ → „…, dass er …“, „ich äh hab das …“ → „Ich habe das …“, „ich ich hab …“, „die äh daten bank“ → „Datenbank“, „ok“ → „okay“ werden akzeptiert. Morgan/Morning, „zwei Woche“ und „Kundinnen und Kunden“ fallen weiter.
- Einschränkung: nur 27 verschiedene Polituren aus synthetischer Sprache. Auf dem Gerät mit echten Diktaten erneut auszählen.

## Befund 3: Schnittstellen der Stücke liegen in Pausen

Prüfung der Stücke-Logik offline auf allen Testaudios (`paply-bench chunks`). Gemessen wurde das lauteste 30-ms-Fenster ±150 ms um jeden Schnitt:

| Audio | Schnitte (s) | Stücklängen (s) | lautestes Fenster am Schnitt |
|---|---|---|---|
| de-30 | 11,58 · 28,47 | 11,6 · 16,9 · 0,8 | −59, −60 dBFS |
| de-75 | 16,38 · 35,43 · 53,85 · 65,40 | 16,4 · 19,1 · 18,4 · 11,6 · 5,1 | −57 … −56 dBFS |
| en-30 | 11,19 · 26,76 | 11,2 · 15,6 · 0,8 | −60 dBFS |
| en-75 | 14,04 · 28,56 · 43,53 · 59,91 | 14,0 · 14,5 · 15,0 · 16,4 · 4,8 | −60 dBFS |
| mix-30 | 23,01 | 23,0 · 5,3 | −58 dBFS |
| mix-75 | 11,10 · 26,49 · 38,94 · 50,55 · 65,70 | 11,1 · 15,4 · 12,4 · 11,6 · 15,2 · 0,8 | −60 … −57 dBFS |

Alle Schnitte liegen im Rauschboden (−60 dBFS); keiner trifft ein Wort. Unter 10 s (de-8, en-8, mix-8) gibt es keinen Schnitt.

- **Mindestlänge 10 s:** Groq rechnet jede Anfrage mit mindestens 10 s ab, und Whisper erkennt Sprache und Satzbau mit mehr Kontext sicherer. Messung: 11–23 s je Stück, also nie unter der Abrechnungsgrenze. Nur das letzte Reststück kann kürzer sein.
- **Pause ≥ 0,6 s:** Lücken in und zwischen Wörtern liegen bei 50–300 ms. Ein Test mit 30 s Rede und 0,3-s-Lücken ergibt keinen einzigen Schnitt.
- **Ab 20 s ohne Schnitt genügen 0,4 s** (getestet). In mix-30 kam der Schnitt erst bei 23 s, weil die Pausen davor unter 0,6 s lagen.
- Steht am Ende ≥ 0,6 s Stille, ist das letzte Stück meist schon **vor** `finish()` unterwegs; der Rest (0,8 s, nur Stille) wird nicht gesendet. Diesen Vorteil hat das Gerät nur, wenn der Nutzer nicht sofort auf Stopp tippt. Deshalb gibt es unten eine Zusatzmessung mit nur 0,25 s Nachlauf.
- Fällt ein Stück zweimal aus, werden keine weiteren Stücke mehr gesendet. `finish()` lädt ab diesem Stück alles in einem Teil hoch (höchstens 10 min je Teil, WAV < 25 MB); schon erfolgreiche Stücke bleiben. `retry()` sendet ebenfalls nur gescheiterte Teile. Ein hängendes Stück hält das nächste höchstens 1,5 s auf; dann geht es ohne das Vorstück-Ende im Prompt los. Je Transkription gilt ein Leerlauf-Timeout von 30 s.
- Pausen werden nur in nicht-stimmhaften Fenstern erkannt. Ein leiser werdender Vokal ist nie Pause, deshalb kein Schnitt mitten im Wort.

## Befund 4: FLAC gegen WAV

Netzfrei (`paply-bench encode`), Median aus 5 Kodierungen auf dem Mac mini (Apple Silicon):

| Audio | Dauer | WAV | FLAC | FLAC/WAV | FLAC-Kodierung |
|---|---|---|---|---|---|
| de-8 | 7,1 s | 223 KB | 139 KB | 0,62 | 6,7 ms |
| de-30 | 29,2 s | 914 KB | 582 KB | 0,64 | 19,4 ms |
| de-75 | 70,5 s | 2204 KB | 1428 KB | 0,65 | 43,1 ms |
| en-75 | 64,8 s | 2024 KB | 1304 KB | 0,64 | 40,2 ms |
| mix-75 | 66,5 s | 2078 KB | 1332 KB | 0,64 | 41,1 ms |

FLAC spart gut ein Drittel (der Rauschboden begrenzt die Kompression) und kostet ~0,6 ms je Audiosekunde. Die Kodierung ist auf iOS und macOS dieselbe (AVAudioFile/ExtAudioFile). Mit Stücken wird jedes Stück kodiert, sobald es geschnitten ist, also während des Sprechens. Die Latenz-Messung über das Netz steht unten.

**Über das Netz** (Stücke aus, Vorwärmen an, je 3 Läufe; Transkriptionszeit ab `finish()` inkl. Kodierung, Median):

| Audio | v3 FLAC | v3 WAV | turbo FLAC | turbo WAV |
|---|---|---|---|---|
| de-8 (139 / 223 KB) | 312 ms | 278 ms | 302 ms | 248 ms |
| de-30 (582 / 914 KB) | 583 ms | 583 ms | 461 ms | 434 ms |
| de-75 (1428 / 2204 KB) | 1353 ms | 1324 ms | 825 ms | 933 ms |
| mix-75 (1332 / 2078 KB) | 1220 ms | 1226 ms | 839 ms | 941 ms |

- Auf dem Mac gibt es keinen gerichteten Unterschied. Bei kurzen Dateien ist WAV etwas schneller (−30 bis −55 ms, vermutlich weil Groq nicht umwandeln muss), bei langen FLAC (turbo −100 ms). Alles liegt im Bereich der Streuung.
- Auf dem iPhone kehrt sich das Bild um: Bei 5–10 Mbit/s Uplink kostet ein 70-s-Diktat als WAV 0,6–1,3 s mehr Upload. Mit Stücken geht nach `finish()` nur noch das letzte, kleine Stück raus; dann sind es nur noch Dutzende Millisekunden.
- **Entscheidung: FLAC bleibt Standard.** WAV ist über `PipelineOptions.uploadFormat` umschaltbar, falls Gerätemessungen etwas anderes zeigen.
- Nebenbefund: In diesem Lauf (Diktate alle ~6 s, direkt nach der Hauptmessung) bekam das Polieren in 17 von 48 Läufen **HTTP 429**. Ursache war das Tages-Tokenlimit von qwen im Free-Tier, siehe „Kosten und Limits“. Die Pipeline lieferte dann wie vorgesehen sofort den Rohtext: Polieren ~30 ms, ein Retry-After > 20 s wird nicht abgewartet. Die Transkriptionszeiten dieser Tabelle sind davon unberührt.

## Kosten und Limits

- **Abrechnung:** mindestens 10 s je Transkriptionsanfrage. `whisper-large-v3` kostet $0,111/h, `whisper-large-v3-turbo` $0,04/h.
  - Stücke sind hier immer ≥ 10 s. Nur das letzte Reststück kann kürzer sein und wird dann mit 10 s abgerechnet; sein Audio wird zuvor auf Sprache geprüft.
  - Mehrkosten durch Stücke: höchstens ~10 s pro Diktat, also ≤ $0,0003 (v3).
  - Kurze Diktate (< 10 s) kosten immer 10 s, mit und ohne Stücke.
  - Beispiel: 1 h Diktat am Tag mit v3 kostet ~$3,3 im Monat, mit turbo ~$1,2.
- **Neuversuch nach endgültigem Fehler** (`retry()`): lädt nur die gescheiterten Teile erneut hoch. Nach Erfolg liefert es das gespeicherte Ergebnis ohne neue Anfrage.
- **Dateigröße:** Free-Tier ≤ 25 MB, Dev ≤ 100 MB. FLAC ~20 KB/s ergibt 25 MB nach ~20 min (WAV nach ~13 min). Mit Stücken bleibt jede Datei bei ~0,3–0,5 MB. Nur der Rückfall auf das Gesamtaudio wäre bei sehr langen Diktaten groß.
- **Free-Tier-Raten** (für Vielnutzer relevant): 20 Transkriptionen/min, 2000/Tag, 7200 Audiosekunden/h. Ein 75-s-Diktat mit Stücken braucht ~5 Anfragen.
- **Polieren im Free-Tier: 200 000 Tokens pro Tag** (TPD, gleitend) für `qwen/qwen3.8-27b`, dazu 8000 Tokens/min und 1000 Anfragen/Tag. Während der Messung erreicht; Groqs Meldung: „tokens per day (TPD): Limit 200000, Used 199289, Requested 1709“.
  - Ein Polier-Aufruf kostet ~700–2000 Tokens. Allein der Systemprompt hat ~600, dazu kommen Diktat, Hintergrund und Ausgabe.
  - Damit reicht das Kontingent für ~100–250 Diktate am Tag. Vielnutzer stoßen an die Grenze.
  - Reaktion der Pipeline: Bei einem 429 mit langer Wartezeit (Retry-After > 20 s) versucht sie **einmal das Ausweichmodell** `openai/gpt-oss-120b`, das ein eigenes Kontingent hat. Erst danach fällt sie auf den Rohtext zurück. Die Messläufe liefen noch ohne diese Regel und lieferten sofort Rohtext.

## Zusatzmessung: Nutzer stoppt sofort (0,25 s Nachlauf)

In der Hauptmessung folgen auf das letzte Wort ≥ 0,8 s Stille. Darin fällt oft schon der letzte Schnitt, und `finish()` muss nichts mehr transkribieren. Hier ist die Stille auf 0,25 s gekürzt; das Reststück muss dann nach `finish()` hochgeladen werden.
- Gemessen ohne Polieren, nur die Transkription: Das Tageslimit von qwen war erreicht, siehe unten.
- Je 3 Läufe, Vorwärmen an. Transkription ab `finish()`, Median.

| Audio | Reststück | v3 ohne Stücke | v3 mit Stücken | turbo ohne Stücke | turbo mit Stücken |
|---|---|---|---|---|---|
| de-30 | 16,8 s | 709 ms | 498 ms | 403 ms | 390 ms |
| en-30 | 15,5 s | 590 ms | 488 ms | 463 ms | 337 ms |
| mix-30 | 4,5 s | 609 ms | 309 ms | 468 ms | 289 ms |
| de-75 | 4,3 s | 1275 ms | 313 ms | 887 ms | 273 ms |
| en-75 | 4,0 s | 1076 ms | 238 ms | 823 ms | 277 ms |
| mix-75 | 15,1 s | 1256 ms | 405 ms | 865 ms | 371 ms |

(„ohne Stücke“: Hauptmessung, gleiches Audio mit längerem Nachlauf.)

- Auch beim sofortigen Stopp lohnen Stücke klar. Bei ~68 s spart v3 0,85–0,96 s. Bei ~28 s sind es 0,1–0,3 s, weil das Reststück dort oft 15–17 s lang ist.
- Die Länge des Reststücks hängt davon ab, wo die letzten Pausen liegen, nicht von der Mindestlänge. Netzfreie Probe (`paply-bench chunkstudy`) mit 10/8/6/5 s Mindestlänge: kein durchgängiger Gewinn. en-75 wird mit 8 s sogar schlechter (11,2 statt 4,0 s), dafür steigen Anfragen und Mindestabrechnung. 10 s bleibt.
- turbo ist beim langen Reststück bis ~150 ms schneller, sonst gleichauf. Das ändert die Modellempfehlung nicht.

## Offene Punkte und Risiken

- **Synthetische Stimmen:** `say`-Stimmen sind deutlich, gleichmäßig und ohne Akzent; die WER-Werte sind daher optimistisch. Auf dem Gerät mit echten Stimmen messen: Dialekt, Akzent, Nuscheln, Straßenlärm, AirPods-Mikro. Dort zeigt sich auch, ob turbo bei echter Sprache weiter zurückliegt.
- **Mac-Netz ≠ iPhone-Netz:** Upload und Verbindungsaufbau auf LTE/5G und schwachem WLAN messen. Erwartung: Stücke, Vorwärmen und FLAC gewinnen dort mehr als hier.
- **Polieren verändert selten den Sinn:** ~3 % der Läufe, z. B. „morgen“ → „Morning“, „zwei Wochen“ → „zwei Woche“, „Kunden“ → „Kundinnen und Kunden“. Das neue Netz fängt alle gemessenen Fälle (Befund 2). Kleine Flexionsänderungen außerhalb von Mengenangaben („schlage“ → „schlag“) gehen weiter durch.
- **Free-Tier-Limits:**
  - qwen: 8000 Tokens/min und **200 000 Tokens/Tag**, also ~100–250 Diktate.
  - Whisper: 20 Anfragen/min; ein langes Diktat mit Stücken braucht ~5.
  - Die Pipeline weicht bei langem 429 einmal auf gpt-oss-120b aus, dessen Kontingent ebenfalls endlich ist.
  - Empfehlung: In der App zeigen, wenn unpoliert eingefügt wurde (`polishError`, z. B. `http-429`). Vielnutzern den Dev-Tier nahelegen. Den Systemprompt kürzen, falls das Kontingent in Gerätetests knapp wird.
- **Sprachangabe:** Whisper meldet eine Sprache je Anfrage. Bei gemischten Diktaten nennt `languages` deshalb meist nur die Hauptsprache, bei Stücken teils mehrere. Für eine genauere Anzeige pro Satz könnte man auf dem Gerät `NLLanguageRecognizer` nutzen; heute dient es nur als Rückfall, falls Groq keine Sprache meldet.
- **Primer nur bei zwei bekannten Sprachen:** Ein Gerät, das nur Deutsch als Sprache führt, bekommt keinen Primer. Damit fehlt dort der Schutz für eingestreute englische Sätze, Paplys Kernfall. Empfehlung an die App: `spokenLanguages` beim Einrichten abfragen oder mit Gerätesprachen + Englisch vorbelegen. Beispielsätze gibt es nur für DE/EN/FR/ES/IT/PT/NL/TR/PL. Gemessen sind nur DE/EN und FR/EN; die Sätze der übrigen Sprachen sind ungetestet.
- **Polieren als Stream:**
  - Antworten kommen per `stream: true`, mit JSON-Rückfall. Das Leerlauf-Timeout von 60 s misst so nur tote Verbindungen, kein Gesamtlimit.
  - Zeilen werden nur an \n getrennt, damit U+2028/U+2029 im Text nichts zerreißen.
  - Ohne `[DONE]` und ohne `finish_reason` gilt die Antwort als unvollständig: ein Neuversuch, danach Rohtext. Ein `finish_reason` ungleich „stop“ wird als „truncated“ verworfen.
  - Ein `rate_limit_exceeded` im Stream zählt wie HTTP 429, mit Wartezeit aus Groqs Text; beim Tageslimit geht es auf das Ausweichmodell.
  - Wegen des aufgebrauchten Tageskontingents ist das gegen das echte Groq noch **nicht live geprüft**, nur mit Mocks im OpenAI-Format. Erster Gerätetest: Diktat mit Polieren, `polishError` muss leer sein.
- **Transkriptions-Timeout:** Leerlauf max(30 s, 15 s + 5 s je Audiominute).
- **Stille-Erkennung neu kalibriert:**
  - Stimmhaft heißt: Grundrauschen + 6 dB und Periodizität ≥ 0,6. Das Grundrauschen gleitet über 30 s.
  - Periodizität: Autokorrelation nach einem Hochpass bei ~150 Hz. Gezählt werden nur echte Gipfel nach dem ersten Nulldurchgang, im Bereich 70–400 Hz.
  - Der Flüster-Pfad zählt nur breitbandige Fenster (≥ 8 % Nulldurchgänge).
  - Die Hauptmessung lief noch mit der alten Erkennung. Die TTS-Stimmen sind durchweg stimmhaft und laut, ein Einfluss ist nicht zu erwarten.
  - Offline verglichen, Anteil Fenster ≥ 0,6:

    | Signal | ohne Vorfilter | Vorverzerrung (x[n] − 0,95·x[n−1]) | **Hochpass 150 Hz (eingebaut)** |
    |---|---|---|---|
    | Stimme 10 dB über Rauschen | 73 % | **0 %** | 72 % |
    | Stimme 6 dB unter Autolärm | 7 % | 0 % | **65 %** |
    | braunes Rauschen, Netzbrummen 50 Hz + Obertöne, Dur-Akkord | 0 % | 0–6 % | 0 % |

  - Die vorgeschlagene Vorverzerrung wurde deshalb verworfen: Sie hebt Rauschen über die tiefen Stimm-Obertöne.
  - Regressionstests: Auto fährt vorbei (Rampe −55 → −30 dBFS), Netzbrummen 50/60 Hz und ein leiser Akkord gelten nicht als Sprache; Stimme über Autolärm und 10–14 dB über Café-Rauschen schon.
  - **Grenze:** Ein reiner Sinuston im Stimmbereich (z. B. 100 Hz ohne Obertöne) ist per Definition periodisch und gilt als stimmhaft, bis er ins Grundrauschen eingeht.
  - Echte Geräuschkulissen auf dem Gerät prüfen.
- **Kurzes Schlusswort:** Nach dem letzten Schnitt genügt schon eine stimmhafte oder breitbandige Folge ab 90 ms für den Upload („Ja.“). Für die ganze Aufnahme gilt weiter `speechDetected` (≥ 150 ms stimmhaft). Ein Diktat, das **nur** aus einem sehr kurzen „Ja“ besteht, kann deshalb als „nichts verstanden“ enden.
- **Mehrsprachiges Sicherheitsnetz:** Wortlisten (Füllwörter, Verneinungen, Meta-Antworten) für 9+ Sprachen und die Bigramm-Regel für CJK/Thai sind nur per Unit-Test geprüft, nicht an echten Modellantworten in diesen Sprachen.
- **Polieren in Stücken** könnte die letzten 0,3–0,6 s weiter senken. Es birgt aber Risiken: Selbstkorrekturen und Satzgrenzen über Stückgrenzen hinweg. Das widerspricht „Perfektion vor Tempo“ und ist bewusst nicht umgesetzt.
- **Speicher:** Das Audio bleibt für `retry()` bis `cancel()` bzw. zur Freigabe der Pipeline im Speicher (Int16, ~1,9 MB/min).

## Anhang: Hauptmessung je Audio

Mediane aus 3 Läufen. „Anfragen“ = Transkriptionsanfragen (Stücke). „Sprachen“ = von Whisper gemeldet, je Anfrage eine.

| Audio | Modell | Stücke | Vorw. | finish→Text | Transkr. | Polieren | Anfragen | Upload KB | WER roh | WER Ergebnis | Sprachen (Whisper) | gehalten |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| de-8 | v3 | aus | aus | 513 ms | 386 ms | 134 ms | 1 | 139 | 0,000 | 0,000 | de | 3/3 |
| de-8 | v3 | aus | an | 440 ms | 312 ms | 129 ms | 1 | 139 | 0,000 | 0,000 | de | 3/3 |
| de-8 | turbo | aus | aus | 466 ms | 324 ms | 142 ms | 1 | 139 | 0,000 | 0,000 | de | 3/3 |
| de-8 | turbo | aus | an | 446 ms | 311 ms | 141 ms | 1 | 139 | 0,000 | 0,000 | de | 3/3 |
| de-30 | v3 | aus | aus | 921 ms | 622 ms | 287 ms | 1 | 582 | 0,015 | 0,015 | de | 3/3 |
| de-30 | v3 | aus | an | 995 ms | 709 ms | 286 ms | 1 | 582 | 0,015 | 0,015 | de | 3/3 |
| de-30 | v3 | an | aus | 505 ms | 0 ms | 493 ms | 2 | 571 | 0,015 | 0,015 | de | 3/3 |
| de-30 | v3 | an | an | 308 ms | 0 ms | 308 ms | 2 | 571 | 0,015 | 0,015 | de | 3/3 |
| de-30 | turbo | aus | aus | 758 ms | 473 ms | 291 ms | 1 | 582 | 0,015 | 0,015 | de | 3/3 |
| de-30 | turbo | aus | an | 767 ms | 403 ms | 349 ms | 1 | 582 | 0,015 | 0,015 | de | 3/3 |
| de-30 | turbo | an | aus | 475 ms | 0 ms | 475 ms | 2 | 571 | 0,015 | 0,015 | de | 3/3 |
| de-30 | turbo | an | an | 301 ms | 0 ms | 301 ms | 2 | 571 | 0,015 | 0,015 | de | 3/3 |
| de-75 | v3 | aus | aus | 2073 ms | 1199 ms | 743 ms | 1 | 1429 | 0,000 | 0,000 | de | 3/3 |
| de-75 | v3 | aus | an | 1806 ms | 1275 ms | 532 ms | 1 | 1429 | 0,000 | 0,000 | de | 3/3 |
| de-75 | v3 | an | aus | 794 ms | 232 ms | 552 ms | 5 | 1429 | 0,007 | 0,020 | de | 3/3 |
| de-75 | v3 | an | an | 846 ms | 310 ms | 537 ms | 5 | 1429 | 0,007 | 0,007 | de | 3/3 |
| de-75 | turbo | aus | aus | 1407 ms | 877 ms | 521 ms | 1 | 1429 | 0,013 | 0,007 | de | 3/3 |
| de-75 | turbo | aus | an | 1398 ms | 887 ms | 529 ms | 1 | 1429 | 0,013 | 0,007 | de | 3/3 |
| de-75 | turbo | an | aus | 814 ms | 213 ms | 541 ms | 5 | 1429 | 0,007 | 0,007 | de | 3/3 |
| de-75 | turbo | an | an | 805 ms | 280 ms | 518 ms | 5 | 1429 | 0,007 | 0,007 | de | 3/3 |
| en-8 | v3 | aus | aus | 501 ms | 313 ms | 129 ms | 1 | 122 | 0,000 | 0,000 | en | 3/3 |
| en-8 | v3 | aus | an | 546 ms | 337 ms | 172 ms | 1 | 122 | 0,000 | 0,000 | en | 3/3 |
| en-8 | turbo | aus | aus | 465 ms | 318 ms | 138 ms | 1 | 122 | 0,000 | 0,000 | en | 3/3 |
| en-8 | turbo | aus | an | 428 ms | 302 ms | 130 ms | 1 | 122 | 0,000 | 0,000 | en | 3/3 |
| en-30 | v3 | aus | aus | 855 ms | 557 ms | 314 ms | 1 | 554 | 0,000 | 0,000 | en | 3/3 |
| en-30 | v3 | aus | an | 900 ms | 590 ms | 310 ms | 1 | 554 | 0,000 | 0,000 | en | 3/3 |
| en-30 | v3 | an | aus | 469 ms | 0 ms | 469 ms | 2 | 542 | 0,000 | 0,000 | en | 3/3 |
| en-30 | v3 | an | an | 400 ms | 0 ms | 395 ms | 2 | 542 | 0,000 | 0,000 | en | 3/3 |
| en-30 | turbo | aus | aus | 750 ms | 443 ms | 286 ms | 1 | 554 | 0,000 | 0,000 | en | 3/3 |
| en-30 | turbo | aus | an | 997 ms | 463 ms | 379 ms | 1 | 554 | 0,000 | 0,000 | en | 3/3 |
| en-30 | turbo | an | aus | 450 ms | 0 ms | 450 ms | 2 | 542 | 0,000 | 0,000 | en | 3/3 |
| en-30 | turbo | an | an | 337 ms | 0 ms | 337 ms | 2 | 542 | 0,000 | 0,000 | en | 3/3 |
| en-75 | v3 | aus | aus | 1619 ms | 1133 ms | 501 ms | 1 | 1304 | 0,000 | 0,000 | en | 3/3 |
| en-75 | v3 | aus | an | 1568 ms | 1076 ms | 509 ms | 1 | 1304 | 0,000 | 0,000 | en | 3/3 |
| en-75 | v3 | an | aus | 810 ms | 237 ms | 573 ms | 5 | 1305 | 0,000 | 0,000 | en | 3/3 |
| en-75 | v3 | an | an | 775 ms | 251 ms | 504 ms | 5 | 1305 | 0,000 | 0,000 | en | 3/3 |
| en-75 | turbo | aus | aus | 1412 ms | 800 ms | 510 ms | 1 | 1304 | 0,000 | 0,000 | en | 3/3 |
| en-75 | turbo | aus | an | 1387 ms | 823 ms | 566 ms | 1 | 1304 | 0,000 | 0,000 | en | 3/3 |
| en-75 | turbo | an | aus | 792 ms | 209 ms | 570 ms | 5 | 1305 | 0,000 | 0,000 | en | 3/3 |
| en-75 | turbo | an | an | 757 ms | 294 ms | 489 ms | 5 | 1305 | 0,000 | 0,000 | en | 3/3 |
| mix-8 | v3 | aus | aus | 510 ms | 380 ms | 130 ms | 1 | 129 | 0,071 | 0,000 | en | 3/3 |
| mix-8 | v3 | aus | an | 406 ms | 273 ms | 137 ms | 1 | 129 | 0,071 | 0,000 | en | 3/3 |
| mix-8 | turbo | aus | aus | 448 ms | 326 ms | 122 ms | 1 | 129 | 0,357 | 0,357 | en | 0/3 |
| mix-8 | turbo | aus | an | 458 ms | 308 ms | 129 ms | 1 | 129 | 0,357 | 0,357 | en | 0/3 |
| mix-30 | v3 | aus | aus | 862 ms | 553 ms | 308 ms | 1 | 566 | 0,000 | 0,000 | de | 3/3 |
| mix-30 | v3 | aus | an | 893 ms | 609 ms | 308 ms | 1 | 566 | 0,000 | 0,000 | de | 3/3 |
| mix-30 | v3 | an | aus | 564 ms | 252 ms | 303 ms | 2 | 566 | 0,000 | 0,000 | de | 3/3 |
| mix-30 | v3 | an | an | 612 ms | 330 ms | 282 ms | 2 | 566 | 0,000 | 0,000 | de | 3/3 |
| mix-30 | turbo | aus | aus | 774 ms | 450 ms | 314 ms | 1 | 566 | 0,030 | 0,030 | de | 3/3 |
| mix-30 | turbo | aus | an | 743 ms | 468 ms | 284 ms | 1 | 566 | 0,030 | 0,030 | de | 3/3 |
| mix-30 | turbo | an | aus | 621 ms | 285 ms | 336 ms | 2 | 566 | 0,030 | 0,030 | de | 3/3 |
| mix-30 | turbo | an | an | 548 ms | 224 ms | 304 ms | 2 | 566 | 0,030 | 0,030 | de | 3/3 |
| mix-75 | v3 | aus | aus | 1645 ms | 1150 ms | 510 ms | 1 | 1332 | 0,032 | 0,032 | de | 3/3 |
| mix-75 | v3 | aus | an | 1887 ms | 1256 ms | 615 ms | 1 | 1332 | 0,032 | 0,032 | de | 3/3 |
| mix-75 | v3 | an | aus | 651 ms | 2 ms | 649 ms | 5 | 1321 | 0,026 | 0,026 | de+en | 3/3 |
| mix-75 | v3 | an | an | 492 ms | 0 ms | 487 ms | 5 | 1321 | 0,026 | 0,026 | de+en | 3/3 |
| mix-75 | turbo | aus | aus | 1374 ms | 877 ms | 507 ms | 1 | 1332 | 0,039 | 0,026 | de | 3/3 |
| mix-75 | turbo | aus | an | 1374 ms | 865 ms | 510 ms | 1 | 1332 | 0,039 | 0,026 | de | 3/3 |
| mix-75 | turbo | an | aus | 686 ms | 0 ms | 686 ms | 5 | 1321 | 0,032 | 0,019 | de | 3/3 |
| mix-75 | turbo | an | an | 530 ms | 0 ms | 530 ms | 5 | 1321 | 0,032 | 0,019 | de | 3/3 |

## Reproduzieren

Achtung: Die volle Matrix braucht ~95 min und im Free-Tier rund 125 000 qwen-Tokens (gut die Hälfte des Tageslimits). Der Schlüssel teilt sich das Kontingent mit der Desktop-App.

```sh
cd ios/PaplyKit && swift build -c release --product paply-bench
# Schlüssel nur als Umgebungsvariable (nie ausgeben):
export PAPLY_GROQ_KEY=…   # z. B. aus ~/Library/Application Support/paply-menubar/config.json lesen
.build/release/paply-bench gen                          # Testaudio nach /tmp/paply-bench-ios
.build/release/paply-bench run /tmp/paply-bench-ios/main.json 3 1
.build/release/paply-bench primer|formats|tail /tmp/paply-bench-ios/<name>.json 3   # tail: ohne Polieren
.build/release/paply-bench polishab /tmp/paply-bench-ios/main.json /tmp/paply-bench-ios/ab.json 1
.build/release/paply-bench chunks | chunkstudy | encode # netzfrei
.build/release/paply-bench report /tmp/paply-bench-ios/main.json
```
