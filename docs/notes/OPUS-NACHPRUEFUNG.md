# Paply Notes – Opus-Nachprüfung

Stand: 26.10.2026, 20:30 · Prüfer: Claude Opus 5.5 (extra high) · Checkout `main`, Notes-Stand uncommitted.
Basis: mein Abschlussreview `OPUS-ABSCHLUSSREVIEW.md` (v3), Roots Antworten `REVIEW-ANTWORTEN.md`, abgeschlossene QA `QA.md`.
Root hat während der Prüfung `plan.js`, `queue.js`, `NotesApp.tsx`, `electron-main.js` und `core.test.js` geändert (20:23–20:25).
Alle Ergebnisse unten sind am Stand **20:28** erneut ausgeführt. Kopie dieses Stands: `/tmp/opus-notes-review/snap-2028/`.

## 0. Urteil

**Die lokale Test-App ist freigegeben, ein Release nicht.** Bedingung: Roots gepackter Smoke ist grün (siehe §5).

- **B2, P1-1, P1-2 und P1-3 sind behoben.** Ich habe das Ende-zu-Ende über Aufnahme → STT → Vorbereitung → Einordnung
  reproduziert: mit 3 Teilen und Ziehen, Resize oder Tippen während der Aufnahme.
- **„Erneut“ nach einem Fallback holt nichts zurück**, was Allan gelöscht, bearbeitet oder verschoben hat.
  Das gilt auch mehrteilig und mit Undo danach.
- **B3 ist im Code korrekt verdrahtet.** Ein echter Squirrel-Neustart ist nicht getestet. Die Test-App startet
  den Updater bewusst nicht. Der Nachweis bleibt deshalb ein Release-Thema.
- **Es gibt keinen neuen Blocker der B2-Klasse.**
- **Neu gefunden:** N1 und N2.
  - N1 (P1, vor Übergabe empfohlen): Bearbeitet Allan einen frischen Rohgedanken gerade dann, wenn Transkript oder
    Einordnung eintrifft, geht sein Entwurf verloren oder überschreibt das Transkript.
  - N2 (P2): Durch die neue Tiefenvalidierung erzeugt eine KI-Tabelle mit einem Satz über 2.000 Zeichen eine
    Retry-Schleife.
  - Wird N1 nicht behoben, muss der Hinweis aus §4 in Allans Testnotiz.

## 1. Was ich getan habe – und was nicht

**Gelesen** (Stand 20:28):

- `notes/queue.js`, `commands.js`, `contracts.js`, `capture.js`, `index.js`, `repo.js`, `ledger.js`, `groq.js`,
  `plan.js`, `settings.js`, `assets.js`
- `src/apps/notes/NotesApp.tsx`, `bodies.tsx`
- Notes- und Updater-Teil von `electron-main.js` (`git diff`)
- `electron-updater` 6.6.2 `MacUpdater.js`, Electron 33.4.11 `electron.d.ts`, `@xyflow/system` 12.12 `getEdgePosition`
- neue Regressionen in `notes/core.test.js`

**Ausgeführt:**

- `npx vitest run notes src/lib/notes`: **66/66 grün** (20:29; um 20:22 waren es 64/64)
- `npx tsc --noEmit`: 0 Fehler
- alte Reproskripte `placeholder.cjs`, `more.cjs`, `proto.cjs`: alle Befunde jetzt negativ
- neue Skripte unter `/tmp/opus-notes-review/`, mit echten Notes-Modulen, Fake-Groq, Temp-Ordnern und ohne Netz:
  - `nachpruefung.cjs`
  - `edit-race.cjs`
  - `tick-scale.cjs`

**Nicht getan:**

- kein Electron gestartet
- kein Groq-Aufruf, keine Keys gelesen
- keine App-Datei geändert
- keine Gesamtsuite und kein Build (macht Root)
- Renderer-Verhalten nur im Code gelesen, nicht per GUI ausgeführt

## 2. Nachprüfung der Altbefunde

| Befund | Ergebnis | Beleg |
|---|---|---|
| **B2** Platzhalter gezogen oder vergrößert ⇒ Text fehlt | **behoben** | `nachpruefung.cjs`, echte Aufnahme mit 60 Sätzen = 3 Teile. Getestete Fälle: Ziehen, Resize, Ziehen+Resize+Ziehen, Ziehen nach Stopp vor STT, Tippen. Ergebnis jeweils: Text in genau dieser Karte, Position erhalten (z. B. `{x:300,y:400}`), `pending:false`, **60/60 Sätze sichtbar**, Board gültig. Teile 1–2 werden von der KI eingeordnet, der verschobene Teil 0 bleibt bewusst roh (`pinned`). Code: `commands.js:32–33` (Geometrie ⇒ nur `pinned`), `queue.js:41–56` (Platzhalter wird immer gefüllt, Folgeteile werden angelegt). |
| **P1-1** Dauer-Spinner bei leerer Aufnahme | **behoben**, ein Restfall (N3) | `more.cjs (a)` und `nachpruefung.cjs`: Bei Stopp ohne Ton und bei `recover()` mit 0 Byte steht `needs_attention`, die Karte zeigt „Kein Ton aufgenommen“ mit `pending:false`, der Eingangszähler zählt nicht mehr (`capture.js:8–16,78`). „Erneut“ darauf schickt keinen Request. |
| **P1-2** Fallback als „Eingeordnet“, „Erneut“ wirkungslos | **behoben** | Neuer Zustand `fallback` (`queue.js:92,104`) mit Label „Original erhalten · Einordnung offen“. „Erneut“ erzeugt genau einen neuen Plan-Request (Aufrufe 1 → 2), unberührt ⇒ `complete`. |
| **P1-3** `owner` durch Verschieben umgedeutet | **behoben**, kosmetischer Rest (N6) | Geometrie setzt nur `pinned`, KI-Herkunft bleibt (Test `keeps AI text provenance…`). No-op-Blur speichert nichts (`bodies.tsx:16`). |
| **Objection: Fallback-Retry darf nichts zurückholen** | **erfüllt** | Nach Fallback und anschließendem Löschen, Text-Edit, Ziehen oder Darstellungswechsel ruft „Erneut“ **keinen** Plan auf (bleibt bei 1), es entsteht kein neuer Knoten, der Nutzerstand bleibt. Löschen + Erneut + Undo: der Rohknoten kehrt zurück, ohne Request. Mehrteilig (Teil 0 eingeordnet, Teil 1 Fallback): Erneut plant nur Teil 1. 30 Satzreferenzen, 30 eindeutig, keine Duplikate. Schutz: `queue.js:94` vor dem Request und `plan.js:88` (`rev`/`owner`/`pinned`/Claims) beim Commit. |
| **B3** macOS „Jetzt neu starten“ | **im Code korrekt**, echter Neustart ungetestet | `electron-main.js:49` hängt an das native `autoUpdater`, das `MacUpdater` selbst nutzt (`MacUpdater.js:16,229`). `prepareQuit()` (`index.js:120`) setzt `closing` synchron vor `CloseAllWindows`, sichert eine laufende Aufnahme und stoppt die Queue. Das danach von Squirrel ausgelöste `before-quit` wird einmal für `flush()` aufgehalten und dann mit `app.quit()` fortgesetzt; ShipIt wartet auf das Prozessende. Die Test-App mit `PAPLY_USER_DATA` startet keinen Updater (`electron-main.js:2549`, `:699`). |
| **B1** Token-Kalibrierung | **für die Test-App akzeptiert** | Roots Live-Wert: Reservierung 7.520 gegenüber tatsächlich 5.185. Der Promptanteil wird um ca. 22 % überschätzt, also konservativ. Kurze ID-Aliasse bleiben Optimierung. |

**Stichproben der P2/P3-Fixes, ohne Regression gefunden:**

- **P2-4:** `budget_small` endet über die Queue in `needs_attention` mit endlichem `retryAt` und 0 Fetches.
- **P3-5:** 429 bucht 0 Token ab, `retryMs` 2000 bleibt.
- **P3-1:** Wird eine freie Linie gelöscht, bleiben keine Punkte zurück.
- **P3-2:** `toString` als ID wird abgewiesen.
- **P3-4:** Mit Cache kostet ein Leerlauf-Tick bei 2.000 Einträgen **2,2 ms** (vorher 31 ms). Das einmalige Einlesen
  beim Start dauert ca. 220 ms.
- **P2-1, P2-6, P2-8, P2-9:** im Code wie beschrieben (`index.js:70,93–97`, `groq.js` `reasoning_effort:'none'`,
  `NotesApp.tsx:117,119`).
- **P2-2:** Roots Änderung um 20:24, beide Griffe `type="source"` (`NotesApp.tsx:25,41`), ist **nötig**. Mit
  `ConnectionMode.Loose` sucht React Flow den `sourceHandle` nur unter den Source-Griffen (`getEdgePosition`).
  Vorher wären linke Mindmap-Kanten (`sourceHandle:'left'`) mit Fehler 008 gar nicht gezeichnet worden.
- **P3-8, Teil der Anhang-Verteilung (neu 20:23):** Das Bild hängt nur noch an einem Knoten des Moments
  (`plan.js:120–121`) und an Teil 0 (`queue.js:53`). Plausibel, keine Validierungsfolgen.

## 3. Neue Befunde

### N1 – P1 (vor Übergabe empfohlen): Offener Editor auf einem Rohgedanken verliert den Entwurf oder überschreibt das Transkript

**Ursache:**

- `bodies.tsx:13` übernimmt den Entwurf nur beim Öffnen des Editors.
- `bodies.tsx:15–17` speichert mit dem `rev`, das **zum Speicherzeitpunkt** gilt, nicht mit dem `rev` beim Öffnen.
  Die Revisionsprüfung in `commands.js:30` greift damit nie gegen Änderungen, die während des Bearbeitens eintreffen.

**Fall A – Einordnung landet während des Editierens (häufiger):**

1. Gedanke sprechen oder Text einfügen. Die Rohkarte erscheint und steht ca. 2–7 s da, bis der Plan kommt.
2. Doppelklick auf die Rohkarte, einen Whisper-Fehler korrigieren.
3. Der Plan kommt an: `applyPlan` ersetzt die Rohkarte, weil sie noch unverändert `system` ist.
4. Klick daneben ⇒ Meldung „Diese Notiz wurde bereits entfernt.“ Die Karte ist weg, der getippte Entwurf auch.

`edit-race.cjs`: `A: … bereits entfernt | Entwurf im Store: false`. Das Transkript selbst bleibt in den KI-Karten
erhalten.

**Fall B – Platzhalter während der Aufnahme bearbeitet:**

1. Doppelklick auf den Platzhalter und tippen.
2. Mit Cmd+Y stoppen, solange der Editor offen ist.
3. Das Transkript füllt die Karte, der Editor zeigt aber weiter nur den Entwurf.
4. Speichern überschreibt das Transkript.

`edit-race.cjs`: `B: Karte = "Idee:" | Transkript auf Fläche: false`. Das ist das B2-Symptom über den Editor-Pfad.
Roots Aussage „ergänzter Text bleibt vor dem Transkript“ stimmt nur, wenn vor Ankunft des Transkripts gespeichert wurde.

**Minimalfix (ca. 10–15 Zeilen):**

1. In `NoteBody` beim Öffnen `base = { rev, text }` merken und mit `base.rev` speichern.
2. Ist die Notiz entfernt: Entwurf als neue Nutzernotiz an derselben Stelle anlegen, statt ihn zu verwerfen.
3. Hat sich die Notiz geändert, während der Platzhalter `pending` war: `Entwurf + "\n\n" + aktueller Text`
   speichern (gleiche Semantik wie `queue.js:52`). Sonst den Editor offen lassen und einen Hinweis zeigen.
4. Robust gegen Fall A zusätzlich: Edit-Lease vom Board an den Main (`notes:editing`, id|null). `structure()`
   behandelt einen gerade bearbeiteten Rohknoten wie `busy` und versucht es nach 2 s erneut.

**Test:** Text einfügen, Editor öffnen, Plan-Mock auflösen, dann blur. Der Entwurf existiert.
Platzhalter tippen, STT liefern, dann blur. Transkript und Entwurf stehen beide auf der Karte.

### N2 – P2: KI-Tabelle mit einem Satz über 2.000 Zeichen ⇒ fünf Plan-Requests, danach „Ungültige Notes-Daten“

- `plan.js:73` ersetzt ein nicht wörtliches Zitat durch den **ganzen** Originalsatz.
- Die neue Tiefenvalidierung (`contracts.js:29` → `:58`) erlaubt höchstens 2.000 Zeichen je Zelle.
  `commands.commit` → `repo.save` wirft deshalb.
- `queue.js:108` behandelt das wie einen generischen Fehler: Backoff 60–480 s, bei jedem Versuch ein neuer
  120B-Request.

`nachpruefung.cjs` mit einem Satz von 2.218 Zeichen und Tabellen-Plan:

```
entry=needs_attention · message="Ungültige Notes-Daten" · planCalls=5 · rawStillVisible=true
```

- **Daten:** Es geht nichts verloren, die Rohkarte bleibt.
- **Kosten:** ca. 25–37k Token des 100k-Tagesbudgets.
- **Häufigkeit:** selten, nur bei langen, unpunktierten Whisper-Sätzen.

**Fix:**

1. In `validatePlan` die Tabelle verwerfen (`return false`), sobald ein zitierter Originalsatz länger als 2.000 Zeichen
   ist. Die Mitglieder bleiben Notizen.
2. Zusätzlich in `structure()` einen fehlgeschlagenen Commit als `plan`/Fallback behandeln, nie als Retry-Fehler.
   Dann kann keine künftige Validierungsabweichung Requests verbrennen.

### P3 – sammeln, nicht blockierend

| # | Befund | Beleg / Stelle | Fix |
|---|---|---|---|
| N3 | Restfall von P1-1: Wurde in den Platzhalter getippt und die Aufnahme enthält keine Sprache, bleibt `pending:true`. Der Spinner läuft auf Allans eigenem Text für immer. | `nachpruefung.cjs`: `entry=empty, pending:true`; `queue.js:59` (`owner !== 'user'`) | `pending=false` unabhängig vom Owner, Label nur bei Systemkarte. |
| N4 | „Moment entfernen“ lässt das Mindmap-Zentrum allein stehen. Der Hub hat keine `sourceId`. | `nachpruefung.cjs`: nachher `["hub:Garten"]`; `plan.js:113`, `queue.js:165` | Hub mit `sourceId` anlegen oder in `discard` `groupId` beachten. |
| N5 | Ehrliche Eingangslabels, zwei Fälle: (a) Wird die Rohkarte während eines laufenden Plans verschoben, wird der Plan korrekt verworfen, der Eingang zeigt aber „Eingeordnet“. (b) Mehrteiliges „Erneut“ endet mit „Deine Bearbeitung bleibt“, obwohl nichts bearbeitet wurde. | `nachpruefung.cjs` „Drag während Plan“: `complete`, `aiNodes:0`; `queue.js:94,108` | Nach `applyPlan` prüfen, ob der Rohknoten noch existiert ⇒ `keptUser`. „Schon eingeordnet“ von „gelöscht“ trennen. |
| N6 | Verbinden einer Kante (`commands.js:43ff`) oder Bild-Anhängen (`assets.js:36`) setzt `owner:'user'`. KI-Freitext kippt dann in Handschrift (Rest aus P1-3b). | Code | Dort nur `pinned` setzen. |
| N7 | Scheitert `quitAndInstall` nach `prepareQuit`, bleibt Notes bis zum Neustart gestoppt: Queue aus, Pille blendet nicht mehr aus. | `index.js:120`, `capture.js` `quitting` | Bei Updater-`error` zurücksetzen oder Hinweis. Nur Release-relevant. |
| N8 | Produkt: Eine während der Aufnahme verschobene Karte bleibt dauerhaft roh. „Erneut“ ordnet sie bewusst nicht ein, eine Aktion „Einordnen“ gibt es nicht. | `queue.js:94` | Für die Test-App dokumentieren. Später eine explizite Aktion „Einordnen“. |

## 4. Für Allans Testnotiz

**Hinweise zur Bedienung:**

- **Solange N1 offen ist:** Frische Rohgedanken erst bearbeiten, wenn sie eingeordnet sind (Eingang zeigt
  „Eingeordnet“). Den Platzhalter während der Aufnahme nicht im Editor offen lassen.
- Wird der Platzhalter während der Aufnahme verschoben oder vergrößert, bleibt dieser Teil eine Rohnotiz an der
  gewählten Stelle. Weitere Teile werden eingeordnet.
- Wird der Platzhalter während der Aufnahme gelöscht, bleibt der Gedanke nur im Eingang unter „Original“.

**Bekannte Produktgrenzen, keine neuen Projekte:**

- Windows, physische Hotkeys und Berechtigungsdialoge nur begrenzt abgenommen
- Undo nur innerhalb der Sitzung
- manuelle Tabelle 2×1
- Themen-Editor kommt später
- „Moment entfernen“ entfernt die Karten, Ton und Original bleiben lokal
- kein Update in der Test-App

## 5. Was Root im gepackten Smoke belegen sollte

1. **B3:** `before-quit-for-update` emittieren ⇒ das Board schließt, eine laufende Aufnahme steht als `captured`
   in `entry.json`, die App beendet sich. Den echten Squirrel-Neustart vor einem Release einmal mit einem echten
   Update prüfen.
2. **P2-2:** Linke Mindmap-Kanten sind gezeichnet, und die Konsole zeigt keinen React-Flow-Fehler `008`.
   Das prüft die Griff-Änderung von 20:24.
3. **P2-7:** Frame-Zeiten bei 100 % Zoom mit 60–100 sichtbaren Volltextkarten.
4. **Wenn N1 behoben ist:** die beiden Abläufe aus N1 einmal per GUI durchspielen.
5. Gesamtsuite und Build grün.
