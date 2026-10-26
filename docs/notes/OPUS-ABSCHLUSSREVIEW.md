# Paply Notes – Opus-Abschlussreview

Stand: 26.10.2026, ca. 20:15 · Prüfer: Claude Opus 5.5 (extra high) · Checkout `main`, Notes-Stand uncommitted.
Während des Reviews hat Root `notes/plan.js`, `notes/commands.js`, `notes/queue.js` und `notes/groq.js` geändert.
Alle Befunde unten sind gegen den Stand von ca. 20:08 nachgeprüft (`index.js`-Zeilen gegen 20:15). Bei weiteren Änderungen können Zeilennummern wandern.

## 0. Urteil

**Noch nicht an Allan übergeben.** Architektur, Sicherheitsgrenze und Diktat-Abgrenzung sind solide. Die volle
Suite ist grün, `tsc` meldet keine Fehler. Offen sind:

- **Vor der Test-App zwingend:** B2. Wird der Platzhalter während der Aufnahme verschoben oder in der Größe
  geändert, landet das Transkript nicht auf der Fläche.
- **Vor der Test-App dringend empfohlen (je wenige Zeilen):**
  - P1-1: Leere oder abgebrochene Aufnahmen hinterlassen einen Dauer-Spinner.
  - P1-2: Fehlgeschlagene Einordnung erscheint als „Eingeordnet“, und „Erneut“ wirkt nicht. Allan kann sonst
    beim Testen nicht sehen, ob die KI überhaupt geordnet hat.
  - P1-3: `owner` wird durch Verschieben umgedeutet. Das ist die Ursache von B2, dazu kippen KI-Texte beim
    Ziehen in Handschrift.
- **Vor einem Release:**
  - B3: Nach einmal geöffnetem Board hängt auf macOS das Update „Jetzt neu starten“.
  - B1-Rest: Token-Schätzung an echten `prompt_tokens` eines befüllten Boards kalibrieren.
  - Performance bei 100 % Zoom messen (P2-7).

B1 aus meinem Frühbericht hat Root während des Reviews weitgehend behoben (Abschnitt 2).

## 1. Was ich getan habe – und was nicht

**Gelesen:**

- vollständig: `notes/*.js`, beide Preloads, `src/apps/notes/*`, `src/apps/notes-pill/*`, `src/lib/notes/*`,
  `NotesSettings.tsx`, `types/notes.ts`
- Diffs von `electron-main.js`, `preload.js`, `package.json`, Vite/Vitest, Workflow, Dashboard/Settings, Testhelfer
- Vorbefunde: §§11/12 im Opus-Review, mein Prebuild-Review, `IMPLEMENTIERUNG.md`, `TESTPLAN.md`
- QA-Beweisdateien unter `/var/folders/0p/…/T/paply-notes-qa-fpeetW/`: Screenshots 02, 03, 07, 08, 09,
  `performance-300.png` und `main.log`

**Ausgeführt:**

- `npx vitest run notes src/lib/notes test/settings-sync.test.js test/setup-integration.test.js`: 76/76 grün
- `npx vitest run`: **41 Dateien, 576 Tests grün** (Baseline 529 + 47 neue)
- `npx tsc --noEmit`: **0 Fehler** (die 5 vorbestehenden Dashboard-Fehler sind behoben)
- Reproduktionen mit den echten Notes-Modulen, ohne Netz (Fake-Fetch, Temp-Ordner), Skripte unter
  `/tmp/opus-notes-review/`:
  - `threshold.cjs`, `kept.cjs`: Plan-Budget
  - `placeholder.cjs`: B2
  - `more.cjs`: P1-1, P1-2, P2-6, P3
  - `proto.cjs`: P3-Härtung
  - `entries-scale.cjs`: Skalierung
- Bundle-Prüfung am vorhandenen Build `renderer/` (19:57): kein `posthog`, keine OpenUI-Devtools. Es gibt nur die
  üblichen `__REACT_DEVTOOLS_GLOBAL_HOOK__`-Abfragen von React.

**Nicht getan:**

- keine Electron-Instanz gestartet (QA läuft separat)
- kein Groq-Aufruf, keine Keys gelesen
- keine App-Datei geändert, kein Build, kein Commit
- Windows nur im Code geprüft
- Visuelle Aussagen stützen sich ausschließlich auf die genannten QA-Screenshots (synthetische Inhalte).

## 2. Blocker

### B2 – Platzhalter verschoben/vergrößert ⇒ Transkript erscheint nicht auf der Fläche (zwingend vor Übergabe)

**Repro** (`placeholder.cjs`, Stand 20:08):

1. Aufnahme starten.
2. Den Platzhalter `raw_<id>` ziehen oder in der Größe ändern. Das ist normal, wenn das Board offen ist.
3. Stoppen. Die STT liefert Text.

**Ergebnis:**

- `entry=kept_user`
- kein Knoten mit dem Text
- Platzhalter `owner:'user', pending:false, text:''`

Seit Roots Änderung in `queue.js:41–44` dreht sich kein Spinner mehr. Die Karte zeigt jetzt aber eine leere
„Neuer Gedanke · Ein Gedanke beginnt hier.“-Notiz. Das ist schlechter erkennbar als vorher: Allan hält die
Aufnahme für gescheitert und löscht die Karte. Der Text liegt nur noch in `sources/<id>/transcript.json`
(über Eingang → Original erreichbar). Bei mehrteiligen Aufnahmen fehlen **alle** Teile, weil `prepare()`
früh zurückkehrt.

**Ursache:**

- `commands.js:32` setzt bei jedem `update` `owner:'user'`, auch bei reiner Position oder Größe.
- `queue.js:41` wertet einen nutzereigenen ersten Platzhalter als „Nutzer hat entschieden“.
- Dasselbe passiert bei Doppelklick und anschließendem Verlassen ohne Änderung: `bodies.tsx:15/18` speichert
  immer.

**Minimalfix:**

1. In `prepare()` einen Platzhalter mit `pending:true` **immer** füllen: Text, `sentenceIds`, `sourceId`,
   `pending:false`. Position und Größe bleiben. Ist er nutzereigen, bleibt `owner:'user'`, damit die KI ihn
   nicht umbaut.
2. Die übrigen Teile `raw_<id>_<n>` trotzdem anlegen.
3. `kept_user` nur bei Grabstein setzen.
4. In `NoteBody.save` nichts senden, wenn Text bzw. Tabelle unverändert sind.

**Test:** Ziehen, Resize und Doppelklick+Blur während der Aufnahme. Danach steht der Text in genau dieser Karte
an der neuen Position. Mit drei Teilen sind alle drei sichtbar.

### B1 – Plan-Budget (`too_large`): weitgehend behoben, Rest ist Kalibrierung (P2 vor Release)

**Vorher:** Bei 10 Notizen und 8 Themen passte schon **ein** Satz nicht mehr in die Grenze von 7.600, jede
Aufnahme endete als Rohfassung.

**Jetzt:**

- `groq.js:36–42` schätzt mit `/3` und kürzt vor dem Abbruch erst `existing`, dann `topics`.
- `threshold.cjs`: 28 Sätze passen bei allen geprüften Boardgrößen für beide Modelle.
- `kept.cjs` zeigt, wie viel Gedächtnis übrig bleibt:

  | Board | Sätze | 120B: gesendete Kandidaten / Themen | 20B |
  |---|---|---|---|
  | 30 Notizen / 20 Themen | 3 | 7/10 · 20/20 | 10/10 · 20/20 |
  | 30 Notizen / 20 Themen | 15 | 1/10 · 20/20 | 8/10 · 20/20 |
  | 30 Notizen / 20 Themen | 28 | 0/10 · **8/20** | 3/10 · 20/20 |

**Rest:**

1. Der Divisor `/3` ist ungeprüft. Kontext und Satz-IDs bestehen zu großen Teilen aus 32-stelligem Hex
   (`s_…`, `n_…`, `t_…`), das sehr schlecht tokenisiert. Liegen die echten `prompt_tokens` über der Schätzung,
   antwortet Groq bei 8K TPM mit 413/429. Das läuft über `'invalid'` in die Rohfassung.
   - `tools/notes-bench/run.cjs` misst das nicht: Er nutzt `blankBoard()` und kurze IDs (`s0_s0`).
   - Nötig ist ein Bench-Fall mit befülltem Board und echten IDs, der Schätzung und `usage.prompt_tokens`
     protokolliert.
2. Billiger und sicherer wären kurze lokale Aliasse im Request (`s1…`, `n1…`, `t1…`), lokal zurückgemappt.
   Das spart Kosten und Kandidaten-Kürzungen.
3. `queue.js:95` nimmt ab 3 Sätzen direkt 120B mit `reasoning_effort:'medium'` und `max 3200` (`groq.js:43`).
   - Für ≥3 Sätze gibt es damit **keinen** zweiten Versuch mehr (`queue.js:102` greift nur bei `!useLarge`).
   - Die Rate von `finish_reason:'length'` bei `medium` sollte der Bench zeigen.
   - 120B ist zugleich `MEETING_MODEL` und Polish-Fallback (`dictation/groq-models.js:3–4`). Notes konkurriert
     dort um dieselbe TPM. Das ist vertretbar, aber zu dokumentieren.

### B3 – macOS-Update „Jetzt neu starten“ hängt, sobald das Notes-Board einmal geöffnet war (Releaseblocker, nicht Test-App)

`notes/index.js:69` verhindert `close` und versteckt das Fenster, solange `closing` falsch ist. `closing`
wird nur in `flush()`/`shutdown()` gesetzt (`:117`, `:122`).

`electron-main.js:689` ruft `updater.quitAndInstall()` auf. Auf macOS schließt Electron dabei **zuerst** alle
Fenster und sendet `before-quit` erst danach. Das steht ausdrücklich in `node_modules/electron/electron.d.ts:168–170`
und `:1927`. Das Board verhindert sein Schließen, also wird „alle Fenster zu“ nie erreicht und der Neustart
bleibt aus.

Electron-Windows (Nsis) ruft `app.quit()` und ist nicht betroffen. Bisher hatte kein Paply-Fenster einen
verhinderten `close`. Das Problem ist also neu.

**Minimalfix:**

```js
require('electron').autoUpdater.on('before-quit-for-update', () => notesApp?.prepareQuit())
```

`prepareQuit()` setzt `closing = true`, bei Bedarf zusätzlich `capture.shutdown()`.

**Test:** gepackte App, Notes einmal öffnen und schließen, Update installieren lassen.

## 3. Testbare Bugs

### P1 – vor Übergabe dringend empfohlen

| # | Befund | Stelle | Repro (Skript) | Minimalfix |
|---|---|---|---|---|
| P1-1 | Leere, abgebrochene oder mikrofonlose Aufnahme (Doppeltipp Cmd+Y, Mikro verweigert, Meeting kurz nach Start) hinterlässt `raw_<id>` mit `pending:true` und Spinner „Dein Gedanke wird gesichert …“ für immer. Der Eingangszähler bleibt ebenfalls stehen. | `capture.js:55–61` (Zustand `needs_attention` bei `bytes==0`), Platzhalter aus `:27` wird nie aufgelöst; ebenso `recover()` `:12` | `more.cjs (a)`: `needs_attention`, Platzhalter `pending:true` | In `finish()` bei `bytes==0` einen unberührten Platzhalter löschen bzw. sonst `pending:false` + Label „Kein Ton aufgenommen“. Dasselbe in `recover()`. |
| P1-2 | Scheitert die Einordnung (Plan-Fehler, `too_large`), zeigt der Eingang „Eingeordnet“. „Erneut“ startet keinen neuen Versuch. Das verdeckt jedes KI-Problem beim Testen. | `queue.js:103` (`partsDone++`, Meldung) → `:91` (`complete`); Label-Vorrang in `NotesApp.tsx:175` (`complete:'Eingeordnet'` vor `e.message`); `queue.js:162` setzt `partsDone`/`fallback` nicht zurück | `more.cjs (b)`: `complete` · 1 Plan-Aufruf, nach „Erneut“ weiter 1 | Eigener Endzustand `fallback` (oder `e.fallback` im Label bevorzugen: „Original erhalten“). `retry()` setzt bei `fallback` `partsDone=0` und `fallback=false`. Das ist nur sicher, solange die Rohknoten unberührt sind; das prüft `applyPlan` bereits über `rawRev`/`owner`. |
| P1-3 | `owner` vermischt „Inhalt vom Nutzer“ mit „vom Nutzer angefasst“. Folgen: (a) B2. (b) Wird eine KI-Notiz vom Typ `text` verschoben, kippt sie von Systemschrift in Handschrift (`.kind-text:not(.derived)`). Handschrift ist laut Stilregel nur für Nutzertext. (c) Doppelklick+Verlassen markiert ohne Änderung als Nutzertext. | `commands.js:32`, `bodies.tsx:18` (`derived` = `owner==='ai'`), `notes.css` (`.kind-text:not(.derived)`), `bodies.tsx:15` | QA-Screenshots zeigen KI-`text` in Systemschrift; Kippen per Code nachvollzogen | Bei `position/width/height` nur `pinned:true` setzen und `owner` nicht ändern. `owner:'user'` nur bei `text/label/table/kind/topicId`. KI-Schutz prüft `owner==='user' || pinned`. `derived` aus einer unveränderlichen Herkunft (`origin`) ableiten. |

### P2 – vor Release beheben, Test-App möglich

| # | Befund | Stelle | Minimalfix |
|---|---|---|---|
| P2-1 | Die Kamera im **Board** fotografiert den Bildschirm unter dem Cursor, also das Notes-Board selbst. Die Pillen-Kamera ist korrekt, weil die Pille `setContentProtection` hat. | `index.js:91` → `assets.js:27–32`; Knopf `NotesApp.tsx:172` | Board für die Aufnahme ausblenden (hide → ca. 200 ms → capture → show) oder den Board-Knopf entfernen; Bild-Paste bleibt. |
| P2-2 | Mindmap-Kanten zu linken Zweigen laufen hinter den Karten herum: vom rechten Hub-Griff zum linken Zweig-Griff. Sichtbar in QA `03-mixed.png` und `07-endpoint-inflight.png` („Meer“, „Ruhe“). | `plan.js:101/115` (immer `right→left`), Layout links/rechts `layout.ts:24–25`, nur Griffe links=target und rechts=source `NotesApp.tsx:25` | `connectionMode="loose"` und Griffe je Kante beim Rendern nach relativer Lage wählen (Ziel links vom Start → `left`/`right` tauschen). Das wirkt auch nach Nutzerverschiebung. |
| P2-3 | Der Start-Screenshot (Bildschirmkontext) wird bei **jedem** Neustart gelöscht, auch wenn die Aufnahme noch nicht verschriftet ist (offline, kein Key, Budget). Ein ausdrücklich gesprochenes „Bildschirm merken“ geht dann still verloren. | `capture.js:15`; Verwendung `queue.js` (Kommando-Erkennung nach STT) | Nur `tmp/<id>.png` löschen, deren Eintrag ein Transkript hat, verworfen ist oder fehlt. Zusätzlich eine harte Altersgrenze (z. B. 7 Tage). |
| P2-4 | Ledger: Ist eine Reservierung allein größer als das Tageslimit und es gibt keine Einträge, wird `retryMs = Infinity`. Gespeichert wird `retryAt:null`, und der Eintrag wird in jedem Tick (1,5 s) erneut genommen und geschrieben, ohne je verarbeitet zu werden. Beim erlaubten Minimum `dailyTokens=5000` liegt jede Plan-Reservierung (ca. 5–7,6K) darüber. Notes ordnet dann nie ein. | `ledger.js:15`; Bereich `settings.js:11` und `NotesSettings.tsx:27` (min. 5000); Audio: 1 Minute < 9-Min-Stück | `more.cjs (d)`: `retryMs=Infinity → {"retryAt":null}`. Fix: `amount > limit` als eigener Fehler (`needs_attention`, „Budget zu klein“), `retryMs` auf endliche Werte begrenzen, Untergrenze Tokens ≥ 10.000. |
| P2-5 | Der Plan-Kontext enthält den Rohknoten der **eigenen** Aufnahme als „bestehende Notiz“. Er hat die höchste Wortüberlappung, kostet Kontext, verdrängt echte Kandidaten beim Kürzen und lädt zu Beziehungen auf sich selbst ein. Dazu tokenisiert `score` mit `/\W+/u` nur ASCII und trifft Wörter mit Umlaut nicht, während `words` Unicode nutzt. | `plan.js:36–39` | `context(board, sentences, entryId)`: `n.sourceId !== entryId && !n.pending` filtern; `score` mit derselben `\p{L}`-Regex teilen. |
| P2-6 | Stürzt der Board-Renderer ab, bleibt das versteckte Fenster tot. Jedes weitere Öffnen zeigt eine leere Seite bis zum App-Neustart. | `index.js:65–75` (kein `render-process-gone` am Board, nur an der Pille `:57`) | `render-process-gone` → `destroy()`, `boardWindow=null`; nächstes Öffnen erzeugt neu. Test: `forcefullyCrashRenderer()`. |
| P2-7 | Pan- und Zoom-Leistung: `onMove` setzt bei **jedem** Frame `setZoom`. `ctx` ist ein neues Objekt je Render (`:161`), dadurch rendern alle `ThoughtNode`/`NoteBody` (Context-Konsumenten) je Frame neu, beim Ziehen ebenso über `onNodesChange`. Jedes `onMoveEnd` schreibt außerdem das ganze Board atomar (fsync), erhöht `rev`, broadcastet den vollen Snapshot und baut alle Knoten neu auf. Das QA-Gate misst bei 15 % Zoom (alle Karten im Detailstufen-Minimalmodus), nicht bei 100 % mit vielen sichtbaren Volltexten. | `NotesApp.tsx:165` (`onMove`/`onMoveEnd`), `:161`; `index.js:85` → `commands.js:71` | `useMemo` für `ctx`; Zoom nur bei Wechsel der LOD-Stufe in den State. Viewport separat speichern (`repo.writeLocal('viewport.json')`, ohne `rev`/Broadcast). Messung bei 100 % mit 60–100 sichtbaren Notizen und echtem Pinch. |
| P2-8 | Bildbeschreibung (optional, standardmäßig aus): Qwen ohne `reasoning_effort:'none'`. Denkt das Modell, ist ein Abbruch bei `max 700` wahrscheinlich. Dann ist das JSON leer bzw. unvollständig, und jeder Versuch verbraucht Kontingent (10/Tag, 3 Versuche). | `groq.js:48–50` | `...groqReasoningOptions(model)` aus `dictation/groq-models.js:14–19` übernehmen (auch für den Plan, dort `reasoning_format:'hidden'`). |
| P2-9 | Cmd+C wird immer abgefangen (`preventDefault`). Markierter Text im Dialog „Original“ lässt sich nicht kopieren; bei ausgewählten Karten wird stattdessen deren Text kopiert. Backspace/Entf löscht ausgewählte Karten auch bei offenem Dialog. | `NotesApp.tsx:119`, `:121` | Nur abfangen, wenn `getSelection()` leer ist und kein Dialog offen ist; Entf/Backspace bei offenem Dialog ignorieren. |

### P3 – Härtung und kleine Fehler (sammeln, nicht blockierend)

| # | Befund | Stelle | Fix |
|---|---|---|---|
| P3-1 | Eine freie Linie löschen hinterlässt zwei unsichtbare `point`-Knoten. Sie bleiben klickbar, und der Leerzustand kommt nie zurück. | `commands.js:47`, `:34–38` (`more.cjs (c)`) | Beim Löschen der Kante bzw. eines Punkts verwaiste Punkte mitlöschen. |
| P3-2 | Geerbte Schlüssel als ID (`toString`, `valueOf`) bestehen `C.id` und die Existenzprüfung. Eine hängende Kante wird gespeichert, und im Main entsteht `Object.prototype.toString.owner='user'`. Ausnutzbar nur über einen kompromittierten Board-Renderer. | `contracts.js:9`, alle `b.nodes[...]`-Zugriffe in `commands.js` (`proto.cjs`) | `Object.hasOwn(b.nodes, id)` bzw. Objekte mit Null-Prototyp. |
| P3-3 | `finish()` ist nicht ausnahmefest. Wirft `fsync` (Platte voll, E/A), bleibt `active` gesetzt: Aufnahme hängt, `isBusy()` blockiert die Queue bis zum Neustart, ein Timer-`finish` erzeugt eine unbehandelte Main-Ausnahme. | `capture.js:55–61` | try/catch um fsync/close, `active=null` im `finally`. |
| P3-4 | `repo.entries()` liest bei jedem Tick (1,5 s) und jedem Snapshot alle `entry.json` synchron im Main: **31 ms bei 2.000 Einträgen** (`entries-scale.cjs`). Das läuft im selben Prozess wie das Diktat. | `repo.js:51`, `queue.js` Tick, `index.js:24` | Einträge im Repo zwischenspeichern (Repo ist einziger Schreiber); Tick nur bei Arbeit oder fälligem `retryAt`. |
| P3-5 | 429/401/4xx verbuchen die volle Reservierung, obwohl Groq nichts verbraucht hat. 429-Serien leeren so das lokale Tagesbudget. | `groq.js:16–22` | Bei `!response.ok` mit 0 abrechnen; nur Timeout/Netz konservativ lassen. |
| P3-6 | Notes-Start wird abgelehnt, solange ein Diktat-**Netzjob** läuft (`isDictating` schließt `pending()` ein). Cmd+Y direkt nach Cmd+X zeigt „Diktat läuft“, obwohl das Mikro frei ist. | `electron-main.js` (Getter), `capture.js:20` | Für die Start-Ablehnung nur `isRecording`; `pending()` weiter für Wiederaufnahme und Queue. |
| P3-7 | Kopieren einer Karte und Einfügen erzeugt einen neuen **Eintrag** mit KI-Einordnung (Groq-Kosten, springt evtl. weg) statt eines Duplikats. | `NotesApp.tsx:137` → `queue.addText` | Eigenen Clipboard-Marker beim Board-Copy setzen und dann lokal duplizieren; oder dokumentieren (⌘D dupliziert). |
| P3-8 | Kleinkram: Tray-Einträge auch bei deaktiviertem Notes (`electron-main.js:1144–1145`). Fester heller `backgroundColor` (`index.js:67`) blitzt im Dark Mode. Text > 20.000 Zeichen einfügen meldet nur „Ungültige Notes-Daten“. Audio im Original ohne Range-Support, Spulen evtl. eingeschränkt (`assets.js:47–50`). Die Pille wird beim Start per `showInactive()` gezeigt und gleich wieder versteckt (`index.js:61/115`), besser nur laden. | – | jeweils klein |

## 4. Vertretbare V1-Grenzen (dokumentieren, nicht blockieren)

- **Tabellen:** Zellen zeigen geprüfte Zitate, auch Teilstücke eines Satzes. Der Rest eines Satzes ist nur über
  „Original“ sichtbar, weil die Mitgliedskarten in der Tabelle aufgehen. Das ist bewusst sicherer als
  Paraphrasen. Eine Fußzeile „Aus N Sätzen · Original“ würde es transparent machen.
- **Themen:** Es gibt keine Oberfläche zum Anlegen, Umbenennen oder Entfernen. Falsch benannte KI-Themen und
  leere Chips bleiben. Für Allans Test genügt das; bald nachziehen.
- **Tabellen bearbeiten:** Manuell eingefügte Tabellen sind 2×1, Zeilen und Spalten lassen sich nicht hinzufügen.
- **Bearbeiten und Rückgängig:** Das Mindmap-Zentrum ist nicht editierbar. Undo gilt nur innerhalb der Sitzung.
- **„Moment entfernen“:** Entfernt die Karten (rückgängig machbar), Ton und Transkript bleiben auf der Platte.
  Datenschutzhinweis nötig.
- **Windows:**
  - Pinch ist etwa 10× träger (React Flow Faktor nur macOS).
  - Bei `rename` mit EPERM/EBUSY (Virenscanner) gibt es keine Wiederholung; die Nutzeränderung scheitert mit Hinweis.
  - Alles nur im Code geprüft.
- **Standard-Kürzel:** Cmd+Y und ⌥⌘Y sind standardmäßig global aktiv. Das überdeckt Safari-Verlauf, Quick Look
  im Finder und Office-„Wiederholen“. Für die Test-App ok; **vor Release Allan entscheiden lassen**
  (Standard aus oder anderes Kürzel).
- **Testendpunkt:** Der Fake-Endpunkt in `index.js:40–43` ist nur mit `PAPLY_USER_DATA`, Loopback und
  Dummy-Key aktiv. Ein echter Key kann ihn nicht erreichen. Akzeptabel.

## 5. Bestätigt gut

- **Grenze:**
  - eigene Preloads ohne Key; die Einstellungen liefern nur `hasGroqKey`
  - `sandbox`, `contextIsolation`, CSP mit `connect-src 'none'` am Board
  - eigene Session; das Protokoll gibt es nur dort; Mikrofonrecht nur für die Pille
  - Absender- und `mainFrame`-Prüfung je Kanal (QA-Log zeigt die Ablehnung eines fremden Absenders)
  - Navigation und Popups gesperrt, Bild-Magic-Bytes plus Neukodierung, Protokoll-Regex ohne Pfade
- **Diktat:**
  - nur der eine Haken in `publishRecordingState()` (vor `recording:start`, `electron-main.js:1242/1286`)
  - die `showOverlay`-Hülle und der Harness-Stub; Notes registriert kein uiohook und keine `recording:*`-Kanäle
  - 576/576 grün
- **Recorder:**
  - Geräterate plus kontinuierliches Resampling (Test für 44,1/48 kHz)
  - `seq`/`epoch`/ACK, fsync je 0,5-s-Paket, synchrone Pause und Epochen-Gate, Meeting-Vorrang
  - Reparatur abgerissener Bytes
- **Speicher:**
  - atomar mit `prev` und 48 stündlichen Sicherungen
  - kein stiller Reset
  - Claims und Grabsteine
  - Die KI kann gelöschte Rohfassungen nicht wiederbeleben (`applyPlan` prüft Existenz, `rev`, `owner` und Claims).
  - vollständige Satzabdeckung, ganze Sätze als Kartentext, Verneinungsprüfung in Tabellenzellen
- **Queue:**
  - ein Request zur Zeit
  - persistente STT-Teile, Reservierung vor dem Request
  - `Retry-After` wird beachtet, Auth-Pause, offline/kein Key ohne Requests
- **Packaging:** `build.files` deckt `notes/**`, beide Preloads und die genutzten `audio/`- und `dictation/`-Module
  ab. Tests sind ausgeschlossen. Der Main braucht kein `zod`.
- **Optik** (nur QA-Screenshots): Mischformen (Karte, Haftnotiz, freier Text, Tabelle, Ablauf, Mindmap) auf
  einer Fläche, Themenrahmen, Paply-Farben, echte Icons. Die Pille zeigt eine zurückhaltende Mint-Gold-Aura.
  Ausnahme: die Mindmap-Kanten aus P2-2.

## 6. Nachtests nach den Fixes (für QA)

1. **B2:** Platzhalter während der Aufnahme ziehen, vergrößern, Doppelklick+Blur → Text erscheint dort. Mit drei
   Teilen sind alle sichtbar.
2. **P1-1:** Cmd+Y zweimal schnell bzw. Mikro verweigert → kein Spinner, Eingang ohne Dauerzähler.
3. **P1-2:** Plan-Mock liefert Fehler → Eingang „Original erhalten“; „Erneut“ ruft den Plan erneut auf, genau
   einmal je Modell.
4. **P1-3:** KI-`text` ziehen → Schrift bleibt.
5. **B3:** gepackte macOS-App, Board öffnen und schließen, Update „Jetzt neu starten“ → Neustart mit neuer Version.
6. **B1-Rest:**
   - Mock: befülltes Board mit 30/20 und 12 Sätzen → Plan wird gesendet.
   - Live, separat und ausdrücklich: Bench mit befülltem Board, Schätzung gegen `usage.prompt_tokens`,
     `finish_reason`-Rate für 120B `medium`.
7. **P2-7:** Frame-Zeiten bei 100 % Zoom mit 60–100 sichtbaren Volltextkarten, echtes Trackpad-Pinch und Ziehen.
8. **Nativ:**
   - Cmd+Y gegen Safari, Finder und Word
   - Abmelden bzw. Neustart des Macs während einer Notes-Aufnahme (Quit-Verzögerung durch `before-quit`)
   - Diktat (Cmd+X) während einer Notes-Aufnahme in der echten App

## 7. Reihenfolge für Root

1. B2 zusammen mit P1-3 (gemeinsame Ursache `owner`), dann P1-1 und P1-2. Alles klein, je mit Unit-Test.
2. B3 (eine Zeile plus `prepareQuit`).
3. P2-1 bis P2-6, P2-8 und P2-9. P2-7 nach Messung.
4. B1-Kalibrierung mit Live-Bench (separat, ausdrücklich, mit Key aus den Einstellungen).

Nach den Fixes reicht eine kurze verknüpfte Nachprüfung von B2, P1-1 bis P1-3 und B3. Die übrigen grünen
Bereiche müssen nicht erneut vollständig geprüft werden.
