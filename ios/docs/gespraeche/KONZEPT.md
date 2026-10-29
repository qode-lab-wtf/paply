# Paply iOS – „Gespräche“: Konzept

Stand 29.10.2026 · Branch `feat/ios-gespraeche` (von `feat/ios-v1`, Build 8) · Auftrag von Allan am 29.10.2026.
Dieses Dokument ist der Bauplan. Messergebnisse zur Sprechererkennung: [MESSUNG.md](MESSUNG.md) (Abschnitt 5 wird
danach festgezurrt). Schnittstellen: `PaplyKit/Sources/PaplyKit/Conversations/ConversationContracts.swift`.

## 0. Die Entscheidungen auf einen Blick

| Frage | Entscheidung |
| --- | --- |
| Was | iPhone liegt beim Meeting, Gespräch vor Ort oder Telefonat (anderes Gerät auf Lautsprecher) daneben und nimmt auf. Danach: wer hat was gesagt, Zusammenfassung, Aufgaben, Thema. Wie Plaud, nur ohne Extra-Gerät. |
| Bedienung | Ein Knopf. Nichts vorher einstellen. Start: großer Knopf im Reiter „Gespräche“, Steuerelement „Paply-Gespräch“ (Sperrbildschirm, Kontrollzentrum, Aktionstaste), Siri. Stopp: „Fertig“ in App oder Live Activity. |
| Telefonate auf demselben iPhone | iOS sperrt dort das Mikro für andere Apps. Weg: iOS-Anrufaufnahme (ab iOS 18.1, mit Ansage) → Teilen → Paply. Gleiche Auswertung. |
| Live oder danach | Danach, über die ganze Aufnahme (genauer als live). Der Wortlaut darf schon während der Aufnahme stückweise zu Groq (Tempo über Architektur). |
| Sprecher | Auf dem Gerät: Segmentierung + Stimmabdrücke (Embeddings) + Clustering, Motor laut MESSUNG.md. Eigene Logik obendrauf: Wort → Sprecher, Glättung je Satz, Splitter zusammenlegen. Nie Tonhöhe. |
| Eigene Stimme | Lernt Paply nebenbei aus den Gedanken-Aufnahmen (bevor deren Ton gelöscht wird), außerdem aus „Das bin ich“ und sicheren Treffern. Kurzes Einsprechen nur als Rückfall. |
| Andere Personen | Namen aus dem Gespräch („Hallo Herr Müller“) als Vorschlag mit wörtlichem Beleg; Stimmen bekannter Personen wiedererkennen. Höchstens einmal „Ist das Testname?“ mit einem Tipp. |
| Text | Groq `whisper-large-v3` mit Wort-Zeitmarken. Eigenes Kontingent (7200 Audio-s/Std.) – `whisper-large-v3-turbo` bleibt dem Diktat. |
| Auswertung | Groq `openai/gpt-oss-120b` (Ausweich `openai/gpt-oss-20b`), striktes JSON-Schema, Validierung im Code. **Nie `qwen`** (gehört dem Polieren). Free-Tier: 8000 Tokens/Min. je Anfrage → lange Gespräche in Stücken (siehe §6). |
| Aufgaben & Thema | Jedes Gespräch hat einen verknüpften Gedanken (`kind == "conversation"`, gleiche ID). Der trägt Titel, Zusammenfassung, Thema und die Aufgaben des Besitzers → Reiter „Aufgaben“, Widgets, Erinnerungen, Themen-Chips ohne Sonderweg. Feste Themen wie „RA Solartechnik“ werden bevorzugt; neue Themen nur als Vorschlag (gleiche Regeln wie Gedanken). |
| Datenschutz | Sprechererkennung und Stimmprofile nur auf dem Gerät. Ton geht nur zur Verschriftlichung an Groq (wie beim Diktat). Kurzer Hinweis: Alle Beteiligten müssen Bescheid wissen (§ 201 StGB) – Hinweis, keine Hürde. |
| Geräte | Muss auf jedem iPhone mit iOS 18 laufen (Neural Engine hat jedes; sonst CPU/GPU, langsamer). Kein Apple-Intelligence-Zwang. |
| Android | Algorithmus plattformneutral in MESSUNG.md + §5 beschrieben; Android baut ihn mit sherpa-onnx nach. |

Alle belegten Aufgaben bleiben am Gespräch (`summary.commitments`, Sprecher-ID oder `shared`).
Nur sicher erkannte oder als „Ich“ bestätigte Personen liefern Aufgaben für den Reiter; gemeinsame/unklare
Aufgaben ausschließlich nach ausdrücklichem „In meine Aufgaben“. Alte Zusagen bleiben lesbar, alte KI-Aufgaben werden einmal
als unklar in den Katalog übernommen (niemals Nutzer-Aufgaben) (`taskCatalogVersion = 1`).

## 1. Erlebnis

**In einem Satz:** Knopf drücken, iPhone hinlegen, reden. Danach steht da, wer was gesagt hat, was herauskam und was
du zu tun hast – am richtigen Thema.

1. **Aufnehmen ist heilig.** Ton liegt auf der Platte, bevor etwas ins Netz geht. Anruf, Diktat, Netzverlust,
   Absturz verzögern höchstens die Auswertung.
2. **Lieber „Person 2“ als falsch.** Ein falscher Name ist schlimmer als kein Name. Feste Namen nur bei sicherem
   Stimmtreffer oder nach Bestätigung; sonst Vorschlag mit Fragezeichen.
3. **Ein Tipp korrigiert.** Name bestätigen, Sprecher zusammenlegen, einen Beitrag umhängen – je ein Tipp bzw. ein
   kurzes Menü. Was der Nutzer setzt, fasst die KI nie wieder an.
4. **Sofort etwas sehen.** Sprecher und Wortlaut erscheinen, sobald sie fertig sind; die Zusammenfassung folgt.
5. **Apple-nativ und ruhig**, wie der Rest der App (dunkel, Wald, Glas ab iOS 26).

## 2. Informationsarchitektur

```
TabView:  Gedanken | Gespräche | Aufgaben | Diktat        (Gespräche: SF „person.2.wave.2“)
Gespräche
├─ Kopf: „Gespräche“ + großer Aufnahme-Knopf (oben, gut erreichbar über der Liste)
├─ Liste: Gespräche, neueste zuerst (Titel, Datum · Dauer, Sprecher-Punkte, Themen-Chip, Zustand)
├─ Gesprächs-Detail
└─ ⋯-Menü: Stimmen verwalten · Zuletzt gelöscht
Gedanken-Liste: Gespräche erscheinen dort als Zeile mit Gesprächs-Symbol (über den verknüpften Gedanken); Tippen
öffnet das Gesprächs-Detail. Reiter „Aufgaben“: Aufgaben aus Gesprächen wie alle anderen, Herkunft „Gespräch“.
```

Der Reiter erscheint, wenn die Reiter-Leiste aktiv ist (Beta „Gedanken & Aufgaben“ an). Eigener Beta-Schalter
„Gespräche“ (Standard an) in den Einstellungen.

## 3. Bildschirme

Unbekannte heißen Person 1, 2 …; das Detail zeigt alle Aufgaben nach Person, „Ich“ zuerst und abhakbar.
Ohne sichere Besitzer-Zuordnung führt „Welche Person bist du?“ zur Auswahl. Zuordnen oder Zusammenlegen
leitet den Aufgaben-Reiter neu ab; abgehakte und selbst bearbeitete Aufgaben bleiben erhalten.
Aufnahme, Leiste und Live Activity bieten Pause / Weiter neben Fertig; die Zeit steht während Pausen.


Akzent für Gespräche: **Himmelblau-Türkis** (z. B. `#5AC8FA` → `#3FD0C9`), damit man Gedanke (Mint-Gold), Diktat
(Grün) und Gespräch (Blau) auf einen Blick unterscheidet. Sprecher-Palette: 8 gut unterscheidbare, gedämpfte Farben
auf dunklem Grund; der Besitzer immer Paply-Grün.

### 3.1 Übersicht (Reiter „Gespräche“)

```
Gespräche                                          ⋯  ⚙
 ┌──────────────────────────────────────────────┐
 │   ◉  Gespräch aufnehmen                       │   große Kapsel, Akzent, 64 pt hoch
 │      iPhone hinlegen – Paply erkennt, wer spricht │
 └──────────────────────────────────────────────┘
 Heute
  Angebot Dachanlage Müller            14:05 · 23 Min
  ● ● ●  Ich, Herr Müller, Person 3    ◆ RA Solartechnik
 Gestern
  Abstimmung Netzgrün                  09:30 · 48 Min
  ● ●    Ich, Testname                    ◆ Netzgrün      ✓ 3 Aufgaben
  Neues Gespräch · Wird ausgewertet …  (Schimmer, Stufe „Wer spricht …“ / „Text …“ / „Zusammenfassung …“)
```

Leerzustand: kurze Erklärung (3 Zeilen), Aufnahme-Knopf, Hinweis „Telefonate auf diesem iPhone: Anruf mit der
iOS-Aufnahme mitschneiden, danach Teilen → Paply“. Einmaliger Datenschutz-Hinweis als dezente Zeile unter dem Knopf:
„Sag den anderen, dass Paply mitschreibt.“ (nach 3 Aufnahmen ausgeblendet, in den Einstellungen nachlesbar).

### 3.2 Aufnahme-Ansicht (Vollbild, wie die große Gedanken-Ansicht)

```
Verwerfen                                        ⌄
              (Aura in Gesprächs-Blau, ruhig)
                  ◯  Orb 200 pt (Pegel)
                    23:41               (64 pt, SF Rounded light, gleich breite Ziffern)
                   Gespräch
      Leg das iPhone in die Mitte. Paply erkennt danach, wer spricht.   (nur die ersten 3 Male)
      [ ✓  Fertig ]
```

- Verkleinern (⌄/wischen): Aufnahme läuft weiter, Leiste über der Tab-Leiste („Gespräch · 23:41 · Fertig“), Live
  Activity und Dynamic Island übernehmen.
- Verwerfen ab 5 s mit Rückfrage (wie Gedanken).
- Kein Live-Text, keine Sprecher während der Aufnahme.
- Unterbrechung (Anruf): Band „Pausiert – Anruf“; danach läuft die Aufnahme von selbst weiter (Lücke wird vermerkt).

### 3.3 Live Activity

Eigener Typ `ConversationActivityAttributes`. Sperrbildschirm und Dynamic Island: Orb mit blauem Ring · „Gespräch“ ·
laufende Zeit · „Fertig“ (breit). Zustände: `recording`, `paused` („Pausiert – Anruf“), `processing`
(„Wird ausgewertet …“ mit Stufe), `done` („Fertig · 3 Aufgaben“ bzw. Themenname), `waiting`, `failed`. Nie Inhalt
auf dem Sperrbildschirm. Ohne Dynamic Island (iPhone 12 Pro u. a.) ist die Activity auf dem Sperrbildschirm und als
Banner beim Start sichtbar. Keine periodische Vibration (stört Meetings); einmaliger Hinweis mit Vibration bei 2 Std.
und 5 Min. vor der Grenze.

### 3.4 Gesprächs-Detail

```
‹ Gespräche                                     ⋯
Angebot Dachanlage Müller                       (Titel, antippen = umbenennen)
Heute, 14:05 · 23 Min · ◆ RA Solartechnik        (Thema-Chip antippen = Thema wählen)

[● Ich] [● Herr Müller ?] [● Person 3]        Sprecher-Chips; „?“ = Vorschlag → Tipp öffnet Bestätigung

Zusammenfassung
  Kurz (1–3 Sätze) …
  • Kernpunkt …
  • Entscheidung …
Aufgaben                                         (die des Besitzers; abhakbar wie im Reiter „Aufgaben“)
  ○ Angebot bis Freitag schicken     Fr
Zusagen der anderen
  Herr Müller: Dachmaße per Mail schicken

Gespräch                                         (Wortlaut, Beiträge nach Sprecher; Name farbig, Zeit klein)
  Ich · 0:12
  Hallo Herr Müller, …
  Herr Müller · 0:18
  …
```

- **Sprecher-Chip antippen** → Blatt „Wer ist das?“: Vorschläge zuerst (Name aus dem Gespräch mit Beleg-Zitat, bekannte
  Stimmen, „Ich“), Eingabefeld für einen neuen Namen, „Mit anderem Sprecher zusammenlegen …“, „Stimme nicht merken“.
  Bestätigen speichert den Stimmabdruck dieser Person (lokal) → nächstes Mal ohne Frage.
- **Vorschlag als Frage im Kopf**, wenn vorhanden: dezentes Band „Ist Person 2 Herr Müller?  [Ja] [Nein]“ – höchstens
  eins gleichzeitig, das mit dem größten Sprechanteil zuerst.
- **Beitrag lange drücken** → „Anderer Sprecher …“, „Text kopieren“.
- Keine Wiedergabe: Ton wird unmittelbar nach erfolgreicher Auswertung gelöscht.
- ⋯: Teilen (Zusammenfassung + Aufgaben als Text), Wortlaut kopieren, Löschen.
- Zustände: wartend/fehlend wie bei Gedanken (Band oben mit „Erneut versuchen“). Teilweise fertig: Sprecher + Wortlaut
  stehen, Zusammenfassung zeigt „wartet auf Kontingent“ o. ä.

### 3.5 Einstellungen → „Gespräche“

- **Meine Stimme:** „Gelernt aus 4 Gedanken“ ✓ bzw. „Noch nicht gelernt – nimm ein paar Gedanken auf oder tippe im
  ersten Gespräch auf ‚Das bin ich‘.“ Rückfall-Knopf „Jetzt einsprechen (20 s)“. „Stimme vergessen“.
- **Bekannte Stimmen:** Liste (Name, seit wann), Wischen löscht.
- **Hinweis Datenschutz:** 3 Sätze (§ 201 StGB, was lokal bleibt, was an Groq geht).

### 3.6 Nur Mikrofonaufnahme

Gespräche entstehen ausschließlich über das Mikro dieses iPhones. Kein Dateiimport, keine Audio-Dokumenttypen,
keine Inbox-Verarbeitung. Die ungenutzte Importfähigkeit in PaplyKit bleibt für spätere Plattformen erhalten.

## 4. Aufnahme-Technik

- **Mithörer statt Besitzer:** Das Gespräch hängt sich als zweiter, dauerhafter Empfänger an den Audio-Strom
  (`AudioTapProcessor`), unabhängig vom Diktat- bzw. Gedanken-Empfänger. Diktat über die Tastatur und Gedanken
  funktionieren während eines Gesprächs weiter; das Gespräch nimmt einfach weiter auf. Die Änderung am Tap ist klein,
  lock-geschützt und wird gesondert geprüft (Diktat darf sich nicht verändern).
- Format: 16 kHz mono, WAV (vorhandener `WAVWriter`), fortlaufend auf die Platte. 1 Std. ≈ 115 MB.
- Sitzung: wie Gedanken Fall A/B (`AudioRecordingIntent` startet das Mikro auch ohne laufende App). Während einer
  Gesprächsaufnahme: keine Leerlauf-Pause, kein Ablauf der Bereithalte-Dauer, **kein** Schutz vor Systemhinweisen
  (Anrufe sollen klingeln).
- Unterbrechung: Aufnahme pausiert, Lücke wird vermerkt (`ConversationGap`), nach Ende der Unterbrechung automatisch
  fortsetzen; geht das im Hintergrund nicht, Live Activity „Pausiert – zum Fortsetzen tippen“.
- Grenze: 4 Std. aufgenommener Ton oder 8 Std. insgesamt, jeweils Hinweis 5 Min. vorher. Speicher: Start nur mit ≥ 500 MB frei;
  bei < 200 MB während der Aufnahme sauber beenden und auswerten.
- Gleichzeitig nur ein Gespräch. Gedanken-Knopf während eines Gesprächs: Gedanke läuft normal (eigener Empfänger).

Eigene Pausen (`pause`) und Anrufe (`call`) speichern Tonposition, Dauer sowie Uhrzeit von/bis.
Wortlaut und KI sehen eine Trennzeile („Pause · 12 Min. (14:32–14:44)“). Anrufe setzen automatisch fort,
eine zusätzlich gesetzte eigene Pause bleibt bestehen.

## 5. Sprecher erkennen (plattformneutral)

**Entschieden nach [MESSUNG.md](MESSUNG.md) (29.10.):**

- Motor: FluidAudio mit **Nemotron-3 fast128 FP16** (bis 8 Sprecher, CoreML, 10-s-Blöcke → ~0,1 GB Speicher auch bei
  90 Min., 50-ms-Mindestturn). Lizenz OpenMDW 1.1 (Gewichte), Apache-2.0 (FluidAudio). Rückfall-Rechenweg CPU/GPU.
- Stimmabdrücke: **CAM++** (Apache-2.0); WeSpeaker war für Profile deutlich schlechter.
- Modelle (~220 MB) werden beim ersten Gebrauch automatisch geladen, danach offline. Bis dahin: Wortlaut mit einem
  Sprecher, Trennung wird nachgeholt.
- Schwellen (Pilot): fest ab 0,80 **und** Abstand ≥ 0,10 zum Zweitbesten; Enrollment-Ausreißer < 0,6 zum Medoid.
- Messbild: Simulierte deutsche Gespräche (Telefon, Tisch 3–5, Raum) nahezu fehlerfrei; echte englische Meetings (AMI,
  Fernfeld) 12–19 % falsch zugeordnete Wörter, fast nur in **kurzen Einwürfen** („ja“, „genau“, „okay“: ~55 % falsch).
  Daraus folgt: Einwürfe ohne Inhalt nicht als eigene, womöglich falsche Sätze zeigen, unsichere kurze Beiträge über den
  ohnehin laufenden KI-Lauf plausibilisieren (nur Umhängen markierter kurzer Beiträge, im Code begrenzt) und dezent
  markieren. Echte Aufnahmen von Allans iPhone sind die eigentliche Abnahme.

Gerüst:

1. **Diarisierung auf dem Gerät** über die ganze Datei: Segmente (Start, Ende, Cluster) + Mittelwert-Abdruck je Cluster.
   Sprecherzahl automatisch; in der App gibt es keine Importe.
2. **Aufräumen:** Splitter-Cluster (wenig Sprechzeit) dem ähnlichsten zuschlagen; sehr ähnliche Cluster zusammenlegen.
3. **Wort → Sprecher:** Whisper-Wörter mit Zeitmarken; jedes Wort bekommt den Cluster mit der größten Überlappung
   (Lücken: nächstes Segment). Danach Beiträge bilden: Satzgrenzen aus Satzzeichen/Pausen, Sprecherwechsel innerhalb
   eines Satzes nur bei klarer Evidenz, sonst Mehrheit im Satz. Unsichere Stellen (Überlappung, Einwurf < 1 s) markieren.
4. **Wer ist wer:** Cluster-Abdruck gegen bekannte Profile (Kosinus; mehrere Abdrücke je Person, bester bzw. Mittel der
   besten). Über der festen Schwelle → Name fest (`owner`/`profile`). Im Graubereich → Vorschlag. Darunter → „Person n“.
   Ein Profil höchstens einem Cluster zuordnen (Zuordnung global optimal, nicht gierig).
5. **Namen aus dem Gespräch:** Die KI schlägt je Sprecher-ID einen Namen mit wörtlichem Beleg vor; der Code prüft, dass
   der Beleg im Wortlaut steht und der Name darin vorkommt. Nur Vorschlag, nie fester Name ohne Tipp.
6. **Lernen:** Gedanken-Aufnahmen (ein Sprecher, ≥ 8 s Sprache) liefern Besitzer-Abdrücke; Ausreißer (Abdruck passt nicht
   zu den übrigen) werden verworfen. Bestätigte Sprecher liefern Abdrücke für ihre Person. Obergrenze je Person
   (z. B. 20), vielfältige Lagen bevorzugt behalten.

### Kurze Einwürfe — plattformneutrale Regeln

Wörter werden an Satzzeichen (`.`, `!`, `?`) und Pausen über 0,8 Sekunden gruppiert.
Glättung ändert einen Person nur bei mindestens 70 % Wortmehrheit der Gruppe;
eine normalisierte Überlappungsdifferenz `(beste − zweite) / Wortdauer` ab 0,6 bleibt geschützt
(ohne Überlappung: 0). Gezählt werden Wörter, nicht ihre Dauer.
Isolierte Beiträge ausschließlich aus Lautäußerungen (kleine de/en-Liste: mhm, hm, hmm,
mm, äh, ähm, aha, uh, um, uhm, mmh) entfallen. Lexikalische Einwürfe aus höchstens zwei
Wörtern (ja, genau, okay, ok, stimmt, klar, richtig, yes, yeah, right, sure, yep) bleiben
sichtbar und sind unsicher, außer alle Wörter erreichen die Differenz 0,6.
Im ohnehin laufenden Zusammenfassungs-Aufruf tragen unsichere Beiträge mit höchstens
sechs Wörtern ihre ID und `UNSICHER`; `reassignments` enthält optionale Vorschläge
`utteranceID` → `speakerID`. Der Code akzeptiert ausschließlich markierte, nicht vom
Nutzer gesetzte Beiträge und vorhandene Sprecher, maximal abgerundet 15 % aller
Beiträge; kein zusätzlicher KI-Aufruf. Bei Neuauswertung bleiben Nutzer-Zuordnungen
nur bei mindestens 50 % Überlappung beider Zeitbereiche und gleichem oder ähnlichem
Text erhalten; nur Sprecher und Eigentümerschaft werden übertragen.

## 6. KI-Rahmen

- Modell `openai/gpt-oss-120b`, `reasoning_effort: low`, striktes JSON-Schema; Ausweich `openai/gpt-oss-20b`.
- Ein Lauf bekommt: Datum, Wortlaut mit Sprecher-IDs und bekannten Namen, Themenliste (ID, Name, Beschreibung).
  Er darf: Titel, Zusammenfassung, Kernpunkte, Aufgaben (mit Zitat), Zusagen anderer (mit Zitat), Thema (vorhandene ID,
  keins oder Vorschlag), Namensvorschläge je Sprecher (mit Zitat). Er darf **nichts** an Themen, anderen Gedanken oder vom
  Nutzer gesetzten Feldern ändern. Prompt knapp, Rechte im Code durchgesetzt.
- Alle Aufgaben mit Zuständigkeit → Gespräch; nur sichere Besitzer-Aufgaben → Aufgaben-Reiter. Zitate werden im Wortlaut geprüft (wie `ThoughtValidator`), Fälligkeiten über `SpokenTime`.
- **Free-Tier-Grenzen (gemessen 29.10.):** `gpt-oss-120b` und `-20b` je 8000 Tokens/Min., 1000 Anfragen/Tag; Whisper je
  Modell 7200 Audio-s/Std. Lange Gespräche: Wortlaut in Stücke (≤ ca. 4500 Tokens Eingabe), je Stück Kernpunkte,
  Aufgaben, Zusagen, Namenshinweise; danach ein Abschluss-Lauf über die Stück-Ergebnisse. Takt nach den
  `x-ratelimit`-Kopfzeilen, bei 429 warten.
- Eigener Ledger „Gespräche“ (getrennt vom Gedanken-Ledger): Tokens und Audiominuten je gleitende 24 Std.; Grenzen so,
  dass Gedanken und Diktat nie leerlaufen.
- Whisper: Stücke ≤ 10 Min. (FLAC/m4a, < 25 MB), Schnitt in Sprechpausen, Wort-Zeitmarken, Versatz addieren. Hinweis-Prompt:
  eigene Begriffe, Namen bekannter Personen, Themennamen (gekürzt). Sprache: Hauptsprache, wenn Whisper bei kurzen Stücken
  unsicher ist (wie Gedanken).

## 7. Datenmodell und Ablage

```
Application Support/Gespraeche/
  conversations/<id>/conversation.json   (Conversation)
                     transcript.json     (ConversationTranscript)
                     voiceprints.json    (Abdruck je Sprecher-ID, lokal)
                     audio.wav           (Ton nur bis done; dann sofort gelöscht, keine m4a-Kopie)
                     work/               (Zwischenstände der Stufen; nach „done“ gelöscht)
  voices.json                            ([VoicePerson], inkl. Besitzer)
  voice-learning/                        (kurz zwischengelagerte Gedanken-WAVs fürs Lernen; nach Abdruck gelöscht)
  ledger.json
Gedanken/thoughts/<id>/thought.json      (verknüpfter Gedanke, kind "conversation", gleiche ID)
```

Dateischutz wie Gedanken (`FileSafety`, atomar). Löschen eines Gesprächs löscht bzw. verschiebt beide Teile gemeinsam
nach „Zuletzt gelöscht“; Wiederherstellen ebenso.

## 8. Datenschutz

- Stimmprofile, Abdrücke, Ton: nur auf dem Gerät, nie in Diagnose oder Feedback. Diagnose-Protokoll nur Zahlen/Codes.
- Groq bekommt nur den Ton (Whisper) und den Wortlaut (Auswertung), wie beim Diktat und bei Gedanken.
- Hinweis § 201 StGB in Übersicht (anfangs) und Einstellungen. Mikrofon-Text in `Info.plist` um Gespräche ergänzen.

## 9. Arbeitspakete

| Paket | Wer | Inhalt |
| --- | --- | --- |
| M | astra | Messung Motoren + eigene Logik → MESSUNG.md, Mess-Werkzeug `ios/tools/gespraeche-bench/` |
| K | astra | PaplyKit `Conversations/`: Speicher, Ledger, Whisper-Stücke, Zuordnung, Profile, KI + Validierung, Warteschlange, Tests |
| A | astra | App: Mithörer im Tap, Aufnahme, Live Activity, Steuerelement/Siri, Hintergrund, Gedanken-Lernhaken, Verknüpfung Gedanke, `ConversationsModel` |
| U | sol | Oberfläche §3 als reine Views mit Beispieldaten; danach Verdrahtung |
| D | astra | Diarisierungs-Motor nach MESSUNG.md hinter `SpeakerDiarizing` |
| R | Sonnet | Gebündeltes Review je Etappe; gezielt: Tap/Diktat, Hintergrund, Daten |

Verträge: `ConversationContracts.swift`. Abnahme: PaplyKit-Tests grün, App/Widgets bauen Debug + Release, echte
Aufnahme auf Allans iPhone (2 Personen, 3+ Personen), keine Verschlechterung bei Diktat und Gedanken.


## Entscheidungen und Härtung nach Review 2 (29.10.2026)

- **E1:** Bei done Ton sofort löschen; wartende/teilweise Gespräche behalten die Aufnahme. Kein Abspielen.
- **E2:** Fertige Gespräche werden nicht erneut ausgewertet; Neuversuch nur mit vorhandener Aufnahme.
- **E3:** Nur Mikro dieses iPhones, kein Import in der App.
- Aufgaben im Reiter stammen nur von sicher zugeordneten Besitzer-Sprechern. Gemeinsam/unklar bleibt im Gespräch;
  die Modellaktion „In meine Aufgaben“ übernimmt eine einzelne Zusage ausdrücklich als Nutzer-Aufgabe.
- Gelöschte KI-Aufgaben erhalten Grabsteine; Ableitung nur bei geändertem Katalog/Besitzer.
  Nutzer-Aufgaben werden niemals in den Gesprächskatalog migriert.
- Vorläufige Einzelsprecher sind keine Identitäten: Benennen und „Welche Person bist du?“ warten auf die Sprecherstufe.
- Modellladen nur mit Beta, 199 MB plus 1 GB Kompilierpuffer; Speicherhinweis statt Dialog.
- Sprecherfehler führen nach drei Versuchen zu needsAttention; Hitze verschiebt die Stufe ohne Fehlerverbrauch.
- Pausen werden bei Zustandswechsel gespeichert, offene Pausen beim Wiederherstellen geschlossen.
  Nach zehn Minuten Pause erscheint einmal ein stiller Live-Activity-Hinweis; Mikro bleibt bereit.
- Stimmprofile, Stimmabdrücke und Diarisierungs-Caches sind vom Backup ausgenommen; Texte bleiben sicherbar.
- Lernen endet bei zehn Besitzer-Abdrücken. Defekte Lerndateien blockieren weitere Kandidaten nicht.
- Groq erhält nur Pausendauer in Minuten, keine Pausen-Uhrzeiten.

### Gerätefeedback: Trennung und Sprecherkorrekturen (29.10.2026)

Gesprächs-Whisper erhält ausschließlich „Eigene Begriffe“, keine Themen- oder Personennamen.
Gespräche besitzen kein Thema. Ihr interner verknüpfter Gedanke transportiert nur Aufgaben
in Aufgaben-Reiter, Widgets und Erinnerungen; Gedankenlisten, Suche, Landkarte, Themen und
Gedanken-KI berücksichtigen ihn nicht. Aufgaben zeigen „aus Gespräch: <Titel>“ und öffnen das Gespräch.
Es gibt höchstens einen bestätigten Besitzer: Eine neue „Ich“-Zuordnung löst die vorherige.
Die [S#]-Platzhalter bleiben gespeichert, sodass Namen sofort ohne erneute Auswertung wechseln.
Aufgaben werden neu abgeleitet; abgehakte und selbst bearbeitete Aufgaben bleiben erhalten.
