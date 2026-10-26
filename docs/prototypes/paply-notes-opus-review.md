# Paply Notes – Opus-Review: Architektur, Ablauf, Modelle, Design

Stand 26.10.2026 · Reviewer: Claude Opus 5.5 · Repository `main`, App `electron-menubar/` (v1.14.1)
Prototyp: `docs/prototypes/paply-notes-opus.html` (eigenständig, Simulation)

Es gibt **keine** Produktimplementierung, keine echte KI, keine Persistenz und keine globalen Hotkeys.
Für den Groq-Teil wurde kein Key gelesen und kein Request gesendet. Es wurde keine App gestartet.

Drei Ebenen werden hier strikt getrennt:

- **[Code]**: gelesen im Repository.
- **[Doku]**: aktuell in offiziellen Quellen geprüft (26.10.2026; Links in §10).
- **[Prototyp]**: im Browser getestet.

Alles andere ist **Vorschlag** oder ausdrücklich **ungetestet**.

---

## 0. Kurzfassung

1. **Navigation wirkt träge.** Die Ursache ist im alten Prototyp gemessen, nicht geraten ([Prototyp], §2.1):
   - Wheel-Pan wird auf 65 % gedämpft, auf ±80 px je Ereignis gekappt und läuft ~100–230 ms nach.
   - Pinch-Zoom ist etwa 7× schwächer als übliche Board-Apps und läuft ebenfalls nach.
   - Ein Bereichswechsel dauert ~685 ms.
   - Semantic Zoom blendet Inhalte per `display` um; das wirkt wie „Rein-/Rausladen“.

   Neuer Entwurf: direkte Manipulation ohne Glättung, Flüge von 190–330 ms, die jede Eingabe abbricht, und Detailstufen ohne Geometriesprung. Gemessen: Pan und Pinch greifen im ersten Frame, der Bereichssprung braucht ~416 ms bis zum Stillstand.
2. **Die Diktat-Pipeline ist für Notes nicht wiederverwendbar** ([Code]): Der Ton kommt erst nach dem Stopp als ein Puffer in den Main-Prozess, die globalen Zustände `isRecording`/`recordingWindow` gehören dem Diktat, und `setupUioHookKeyUp` entfernt **alle** `keyup`-Listener. Notes braucht deshalb eine eigene, schmale Aufnahme- und Hotkey-Spur, zunächst nur Tippen-Start/Tippen-Stopp ohne Halten-zum-Sprechen. So entsteht keine Regression an Cmd+X.
3. **Die Secret-Grenze ist heute offen** ([Code]): `settings:get` gibt `groqApiKey` und `geminiApiKey` an jedes Fenster mit `preload.js` heraus. Das Notes-Fenster zeigt Modelltext, eingefügte Inhalte und Bilder und braucht deshalb einen **eigenen Preload ohne Settings-Zugriff**; der Key bleibt im Main-Prozess.
4. **Ein Groq-Key reicht für alles**, mit minimalem Routing ([Doku], §4):
   - `whisper-large-v3-turbo` für Sprache
   - `openai/gpt-oss-20b` (Production, strikte Structured Outputs, Prompt-Caching) für die Einordnung
   - `openai/gpt-oss-120b` nur bei konkretem Fehlerbild, höchstens ein Versuch
   - Bildbeschreibung optional über `qwen/qwen3.8-27b`; das ist **Preview** und teilt Kontingent mit dem Polieren.

   Embeddings gibt es bei Groq nicht; eine lokale BM25-Suche reicht als begrenzte Kandidatensuche.
5. **Kernprinzip: Die KI liefert nur Bedeutung, nie Geometrie und nie Prosa für den Inhalt.** Das Modell gibt Satz-IDs, kurze Titel, eine Platzierungswahl und höchstens zwei begründete Bezüge zurück. Der Wortlaut auf der Karte bleibt Allans Transkript. Positionen berechnet ein deterministisches lokales Layout. Das verhindert neue Modellprosa im Notizkörper. Transkriptionsfehler, irreführende Titel, falsche Trennungen und Beziehungen sind damit allerdings nicht ausgeschlossen und bleiben Qualitätsrisiken.
6. **Ablauf**: Ton wird sofort und gestückelt auf Platte geschrieben → STT → die **Rohfassung ist sofort sichtbar** → Einordnung → lokale Prüfung → Layout-Patch als rücknehmbare KI-Gruppe.
   - Fällt Netz, Limit oder Budget aus, liegt die Rohfassung mit vollständigem Wortlaut lose auf dem Board.
   - Hat Allan sie inzwischen angefasst, gewinnt Allan.
7. **„Gedächtnis“ ja, aber als abgeleiteter, lokaler Index** über den Originalen:
   - Themen mit Aliassen und Status, Allans Korrekturen als Zuordnungsbeispiele, Bezüge mit Status und Grabsteinen, Bildableitungen je Inhalts-Hash.
   - Es räumt sich deterministisch auf und kann jederzeit neu aufgebaut werden.
   - Kein Agent, kein Profil, kein Training. JSONL plus Snapshot ist ein möglicher Start; das fehlende eingebaute `node:sqlite` unter Electron 33 allein ist kein Argument gegen eine Datenbank. Persistenzentscheidung und Absturzsicherheit bleiben vor der Produktimplementierung zu prüfen (§11).
8. **Bilder sind kompakte Anhänge in einer Notiz** und nicht Kacheln auf dem Board. Ein Screenshot per Sprache funktioniert nur ehrlich als **ein lokaler Schnappschuss beim Aufnahmestart**, der **nur** bei der Kommandophrase als erste Worte behalten wird. Dazu kommt ein Kamera-Symbol in der Notes-Pille. Eine rückwirkende Sprachauslösung gibt es nicht. ⌘V hängt an die ausgewählte Notiz an oder legt eine neue Notiz an; im Texteditor bleibt es normales Einfügen.
9. **Libraries – ursprüngliches Urteil, durch §12 korrigiert**: Das ursprüngliche pauschale Nein zu OpenUI war nicht gerechtfertigt. OpenUI kann als Darstellungsschicht über einem separaten, dauerhaften Notizbestand verwendet werden. Die damalige weitere Einordnung: tldraw verlangt eine Lizenz für den Produktiveinsatz. Excalidraw ist skizzenhaft, und genau das hatte Allan abgelehnt. React Flow wäre der einzige ernsthafte Kandidat und ist als Rückfall notiert. Empfohlen werden eigene, typisierte Board-Bausteine in React mit DOM-Karten und SVG-Kanten.
10. **Design-Idee**: „Inhalt ist Typografie, Herkunft ist Material, Deutung ist gestrichelt.“
    - Ganze Gedanken stehen auf den Karten, kein separater Leser.
    - Bereiche sind ruhige Flächen.
    - Ein Eingang zeigt, was gerade passiert.
    - Ein „Neu“-Rundgang macht das autonome Wachstum nachvollziehbar und einzeln rücknehmbar.
    - Bereichsübergreifende KI-Bezüge erscheinen als kleines „Bezug“-Zeichen statt als lange Linie quer durch fremde Karten.

---

## 1. Was geprüft wurde – und was nicht

| Ebene | Inhalt |
|---|---|
| [Code] | `electron-main.js` (Store, Aufnahme, Hotkeys, Backups, IPC, Fenster), `preload.js`, `dictation/*` (Groq-Modelle, Polieren, Jobs, Policies), `meeting/*` (Store, Queue, Controller, LLM-Client), `app-setup`, Theme und Motion (`src/globals.css`, `recording-pill.css`, `RecordingPill.tsx`, `useDictationRecorder.ts`) |
| [Doku] | Groq: Modelle, Structured Outputs, Rate Limits, Speech-to-Text, Deprecations, Reasoning, Prompt Caching, Vision; OpenUI-Repository; tldraw-Lizenz; npm-Metadaten; Apple `VNRecognizeTextRequest`; Electron `desktopCapturer` |
| [Lokal geprüft] | Electron 33.4.11 läuft mit Node 20.18.3 und Chrome 130. `require('node:sqlite')` ergibt `ERR_UNKNOWN_BUILTIN_MODULE`. Es ist keine SQLite-Abhängigkeit installiert. |
| [Prototyp] | Alter Prototyp: Kamerawerte gemessen. Neuer Prototyp: siehe §8 |
| **Nicht geprüft** | echtes Trackpad-Gefühl, echte Groq-Antworten und deutsche Segmentierqualität, Electron-Integration, echte Bildschirmaufnahme und OCR, Windows, Screenreader, Verhalten bei 1.000+ Karten |

---

## 2. Befunde, priorisiert

### 2.1 P0 – Navigation im bisherigen Prototyp (`paply-thought-board.html`): Ursache gemessen

Synthetische Wheel-Ereignisse, identisch gegen den alten und den neuen Prototyp im Headless-Browser:

| Messung | alt | neu (`paply-notes-opus.html`) |
|---|---|---|
| Pan, 1 Ereignis `deltaY=40` | erst nach 98 ms ~24 px, Endwert **26 px** nach ~230 ms | **40 px im ersten Frame**, keine Nachlaufzeit |
| Pinch, 10 Ereignisse `ctrlKey, deltaY=-3` | Faktor **×1,046**, läuft ~150 ms nach | Faktor **×1,35**, im ersten Frame |
| Cmd + Mausrad, 1 Raste (`deltaY=100`) | – | ×0,905, also 10 % je Raste |
| Bereichswechsel bis Stillstand | **~685 ms** | **~416 ms** (Flug 190–330 ms plus Messraster) |

Die Ursachen im alten Code:

- `moveCamera` glättet exponentiell mit τ ≈ 35 ms.
- Pan wird mit `*0.65` gedämpft, auf ±80 px je Ereignis und ±120 px gegenüber der Kamera gekappt.
- Zoom rechnet `exp(-raw*0.0015)`; Board-Apps nutzen eher ~`deltaY/100` je Ereignis.
- Der Bereichsflug ist mit 580 ms ease-out-quart fest eingestellt.
- `applyCamera` setzt in jedem Frame `--zoom` und schaltet `.collapsed` per `display`. Das löst Restyle und Layout aus; der Inhalt springt.
- `render()` baut bei jedem Ziehschritt das ganze innere HTML neu.
- Die Kanten liegen in einem 10.000 × 10.000-px-SVG.

Das Trackpad liefert seinen Schwung bereits vom Betriebssystem. Eine zusätzliche Glättung erzeugt doppelte Trägheit, und genau so fühlt es sich an.

**Grenze dieser Messung:** Der Headless-Browser lief mit etwa 30 Hz (Median-Frame 34,6 ms). Das echte Trackpad-Gefühl auf Allans Mac ist **nicht** gemessen und muss in Electron gegengeprüft werden.

### 2.2 P0 – Aufnahme und Hotkeys: Notes darf nicht auf die Diktat-Spur ([Code])

- **Puffer erst nach dem Stopp**: `useDictationRecorder` sammelt die MediaRecorder-Chunks im Renderer und sendet sie erst bei `onstop` als einen Puffer (`recording:audio`). Ein Absturz während einer langen Notes-Aufnahme würde alles verlieren.
  - Der Main-Prozess sichert erst danach (`saveAudioBackup`).
  - Für Notes sind 1–10-minütige Aufnahmen normal; nötig ist ein **Streaming auf die Platte** (Muster: `meeting/chunk-accumulator` und `chunks/`).
- **Globaler Zustand**: `isRecording`, `dictationJobs` und `recordingWindow` gehören dem Diktat; `processAudioData` fügt am Ende ein.
  - Wer daran andockt, riskiert Einfügen in das aktive Textfeld, und genau das soll Notes nie tun.
- **`setupUioHookKeyUp`** ruft `hook.removeAllListeners('keyup')`.
  - Ein Notes-Listener für Halten-zum-Sprechen würde beim nächsten Kürzelwechsel des Diktats verschwinden.
  - Umgekehrt dürfte Notes nie `removeAllListeners` rufen.
  - **Empfehlung:** Notes v1 nutzt Tippen-Start und Tippen-Stopp über eine eigene `globalShortcut`-Registrierung nach dem Muster von `meeting/beta-mode.js`. Halten-zum-Sprechen braucht einen Keyup-Verteiler und damit eine Änderung am Diktat-Code. **Das geht nur mit Allans ausdrücklichem OK.**
- **Mikrofon gleichzeitig**: Zwei `getUserMedia`-Ströme gehen technisch, aber diktierter Text würde in der Notes-Aufnahme landen.
  - **Ursprünglicher Vorschlag:** Notes pollt `isRecording` alle 250 ms und pausiert seinen Recorder. **Im Gegencheck verworfen als Exklusivitätsgarantie:** Zwischen zwei Abfragen kann bereits fremder Ton aufgenommen werden; auch Ende und Neustart können dazwischenliegen. Vor Umsetzung braucht die gemeinsame Mikrofonbelegung eine synchronisierte Startgrenze oder ein explizit definiertes Parallelverhalten. Ein Poll allein genügt nicht.
  - Diktat-Code bleibt in diesem Review unverändert. Ein später notwendiger Eingriff unterliegt weiter der Projektregel zu Cmd+X.

### 2.3 P0 – Secret-Grenze ([Code])

- `ipcMain.handle('settings:get')` liefert `groqApiKey` und `geminiApiKey` im Klartext.
- Alle Fenster (Dashboard, Einstellungen, Verlauf, Aufnahme-Pille) laden **denselben** `preload.js`.
- Die IPC-Handler prüfen den Absender nicht.

Für Notes gilt deshalb:

- Ein eigener `notes-preload.js` stellt nur `notes:*`-Kanäle bereit.
- Jeder Handler prüft `event.sender` gegen das Notes-Fenster.
- `contextIsolation`, `sandbox: true` und eine CSP ohne Remote-Quellen sind gesetzt.
- Modelltext wird nur als Text gerendert, nie als HTML.
- Der Key wird ausschließlich im Main-Prozess gelesen.

Die bestehende Offenheit für die anderen Fenster ist ein eigener Befund und gehört **nicht** in dieses Notes-Projekt (Diktat-Bereich).

### 2.4 P1 – Persistenz-Muster ([Code])

- `electron-store` (`config.json`) hält Einstellungen, Key, Verlauf und den Meeting-Index in **einer** Datei. Notes-Daten gehören dort nicht hinein: Die Datei wird bei jedem Schreiben komplett neu geschrieben, und der Key liegt mit darin.
- `meeting-store` schreibt `transcript.json` und `summary.json` mit `writeFileSync` **ohne** temporäre Datei mit Umbenennen. Ein Absturz mitten im Schreiben hinterlässt eine kaputte Datei. Notes muss atomar schreiben (`tmp` → `fsync` → `rename`).

### 2.5 P1 – Groq-Nutzung im Bestand ([Code] + [Doku])

- `transcribeAudio` wiederholt bei 429 nach festen 1–3 s und ignoriert `retry-after`. Laut Groq-Doku ist dieser Header bei 429 gesetzt. Der Notes-Worker muss ihn auswerten.
- Das Polieren nutzt `qwen/qwen3.8-27b`. Groq führt das Modell als **Preview** („may be discontinued at short notice“); der Vorgänger `qwen/qwen3.6-27b` wurde am 14.09.2026 abgeschaltet. Für das Diktat ist das ein Hinweis, keine Änderung. Für Notes folgt daraus: **kein Kernpfad auf ein Preview-Modell**.
- `llama-3.1-8b-instant` und `llama-3.3-70b-versatile` sind seit 16.08.2026 nur noch Enterprise. Groq empfiehlt als Nachfolger `openai/gpt-oss-20b` bzw. `-120b`.
- Rate Limits gelten **je Organisation**. Diktat und Notes teilen sich also das Kontingent. Notes braucht einen eigenen, konservativen Anteil (§4.3).

### 2.6 P2 – Bisheriger Prototyp als Codebasis

Handgeschriebene Logik ohne Datenmodell, Validierung oder Akteurstrennung. Das Rückgängig per Schnappschuss würde KI-Änderungen mit zurückdrehen, die zwischendurch eingetroffen sind. Als Vorlage für die Produktion ist er nicht geeignet, als Ideenquelle schon.

---

## 3. Zielarchitektur (Vorschlag)

### 3.1 Module

```
Main-Prozess (solange Paply läuft; Notes-Fenster muss nicht offen sein)
  notes/hotkeys.js     eigene globalShortcut-Registrierung (Muster beta-mode), Kollisionsprüfung via sameShortcut
  notes/capture.js     versteckter Aufnahme-Renderer + Notes-Pille (eigenes Fenster), Chunks → Platte
  notes/store.js       Op-Log (JSONL) + Snapshot, atomar; Assets inhaltsadressiert
  notes/queue.js       Zustandsautomat je Eintrag, Prioritäten, max. 1 Netz- + 1 Lokal-Job, Backoff, Budget
  notes/groq.js        ein Client: Reservierung vor dem Request, Header-Auswertung, Fehlerklassen
  notes/plan.js        Prompt-Bau, Schema, lokaler Validator, Planer (Ops), Stale-Prüfung
  notes/layout.js      deterministisches Layout (Bereiche, Spalten, Hindernisse); KI liefert keine Koordinaten
  notes/memory.js      abgeleiteter Index (BM25, Aliasse, Korrekturen, Bild-Ableitungen) + Hausmeister
  notes/ocr-mac        Swift-Helfer (Vision), Muster wie resources/bin/macos-globe-listener
Renderer
  notes.html           Board (React, eigene Bausteine), notes-preload.js mit schmaler API
  notes-pill.html      Pille (RecordingPill wiederverwendet, reine Darstellung)
```

### 3.2 Integration ohne Cmd+X-Regression

- **Unverändert** bleiben `dictation/*`, `processAudioData`, `transcribeAudio`, `beginRecording`/`stopRecording`, `changeDictationShortcut`, `setupUioHookKeyUp`, die Aufnahme-Pille und die vorhandene API von `preload.js`.
- **Neu und klein in `electron-main.js`**:
  - In `app.whenReady` ein `notes = createNotes({ app, getStore, globalShortcut, isDictating: () => isRecording, systemPreferences, screen, desktopCapturer })`.
  - `notes.registerIpc(ipcMain)` mit eigenen Kanälen.
  - In `will-quit` ein `notes.shutdown()`, das offene Aufnahmen finalisiert.
  - Ein Tray-Menüpunkt „Notes öffnen“.
- **Einstellungen**: Schlüssel unter `notes.*` (aktiv, Kürzel, Bildschirmkontext, Budgetanteil). Gelesen über einen eigenen Kanal `notes:settings`; der Key wird dabei nie mitgegeben.
- **Kürzel** (Vorschlag, vorher auf Kollisionen prüfen): `⌥⌘N` nimmt auf bzw. stoppt, `⌥⇧⌘N` öffnet Notes. Geprüft wird gegen das Diktat-, Meeting-, Smart-Paste- und Recovery-Kürzel sowie die Agent-Kürzel. Schlägt die Registrierung fehl, kommt dieselbe verständliche Meldung wie beim Meeting.
- **Gemeinsam genutzt (nur lesend)**: `audio/silence-filter` (Stille, „Vielen Dank“-Phrasen), `vocabularyPrompt` (Eigene Begriffe), Theme-Tokens.

### 3.3 Ablauf eines Sprachbeitrags

```
Kürzel ─▶ Pille „Notiz 00:03“ ─▶ MediaRecorder (Opus 32 kbit/s, timeslice 1 s) ─▶ Main hängt an notes/audio/<entry>/rec.webm an
          (Diktat startet? → pause(); Pille „pausiert“)
Stop ─▶ entry.state = captured (fsync) ─▶ Queue
      ─▶ STT (whisper-large-v3-turbo; ≤ 5-min-Stücke an Sprechpausen; Satz-IDs lokal)        state: transcribed
      ─▶ Bildschirm-Kommando? (lokale Regel, nur erste Worte) → Schnappschuss behalten/löschen
      ─▶ Rohfassung sofort sichtbar (Eingang; bei Verzögerung lose Karte auf dem Board)
      ─▶ Kandidaten lokal (BM25 + Aliasse + Korrekturen + 3 neueste), Budget reservieren
      ─▶ gpt-oss-20b, strict json_schema ─▶ lokaler Validator ─▶ (bei hartem Fehler einmal 120b) ─▶ sonst lose Rohfassung
      ─▶ Planer: Ops gegen den AKTUELLEN Stand prüfen (Stale-Regeln §3.6) ─▶ Commit als KI-Gruppe ─▶ Layout ─▶ „Neu“
```

### 3.4 Zustandsautomat, Wiederholungen, Fehlerklassen

Zustände: `recording → captured → transcribing → transcribed → structuring → placed | fallback | discarded`, dazu die Wartezustände `waiting_network | waiting_limit | waiting_budget | needs_attention`. Jeder Übergang wird persistiert.

**Beim Neustart:**

- `recording` mit Chunks wird finalisiert.
- `transcribing` fällt zurück auf `captured`.
- `structuring` fällt zurück auf `transcribed`.

| Fehler | Verhalten |
|---|---|
| offline / `ENOTFOUND` | warten auf `online` (Electron `net.isOnline`) und Backoff 30 s · 2 min · 10 min; zählt nicht als Fehlversuch |
| 429 | `retry-after` beachten, plus Jitter; zählt nicht als Fehlversuch |
| 401/403 | Queue pausiert, Hinweis „Schlüssel prüfen“; keine Wiederholungen |
| 5xx / Timeout | höchstens 5 Versuche über 24 h (30 s, 2 min, 10 min, 1 h, 6 h), danach `needs_attention` (sichtbar, „erneut versuchen“) |
| JSON kaputt / abgeschnitten | sofort einmal `gpt-oss-120b` mit höherem `max_completion_tokens`, danach lose Rohfassung |
| Validator: harter Fehler (unbekannte oder doppelte Satz-ID, Schema) | wie oben |
| Validator: weicher Fehler (Bereich weg, Ziel gelöscht, zu wenig Belege) | Element herabstufen (lose), Rest übernehmen |
| `model_decommissioned` / 404 | Modell aus der Liste nehmen, Ausweichmodell, Hinweis |
| Eintrag gelöscht während der Verarbeitung | `AbortController`, Ergebnis verwerfen (Grabstein wird geprüft) |

**Idempotenz:** IDs sind deterministisch (`t_<entry>_<i>`, `a_<entry>_<key>`, `r_<entry>_<i>`, `p_<entry>_<i>`). Ein zweites Anwenden ist ein Leerlauf. Grabsteine verhindern Wiederauferstehung.

### 3.5 Datenmodell: Inhalt, Semantik und Darstellung getrennt

```jsonc
// notes/log.jsonl – eine Zeile je Op (append, fsync gebündelt); notes/snapshot.json alle 200 Ops atomar
{ "seq": 812, "opId": "…", "actor": "user|ai|system", "group": "e12", "base": 809,
  "c": "notes|areas|members|pos|rels|corr", "id": "t_e12_0", "before": {…}, "after": {…} }

// Inhalt – nie von der KI umformuliert
Thought   { id, kind: "thought|sticky|text", title, titleBy: "ai|user",
            passages: [{ id, text, by: "voice|user", src: { entry, sids:[…] }, at, edited, addendum, pasted }],
            attachments: [{ asset: "sha256", kind: "screen|paste", at }], deleted, raw, fallback }
Entry     { id, createdAt, durationMs, state, attempts, nextAt, audio: [chunks], transcript: { sentences:[{id,text,t0,t1}],
            model }, command, snapshot, plan: { model, promptVersion, baseRev, result }, log:[…] }
// Semantik
Area      { id, title, titleBy, aliases:[…], by: "ai|user", entry, status, deleted }
Member    { thoughtId → { area|null, by: "ai|user" } }
Relation  { id, from, to, kind: "line|arrow", by, state: "suggested|kept", reason, evidence:{sids}, entry, deleted, expiresAt }
// Darstellung
Pos       { id → { x, y, pinned, local } }        // nur für angepinnte (= von Allan bewegte) Objekte
Slot      { thoughtId → { area, col, seq } }      // System, stabil: neue Karten an die kürzeste Spalte, nie umsortieren
// Abgeleitet (Gedächtnis, §3.8) und Budget
Correction { id, thought, from, to, terms[] }     // aus Allans Verschieben
ImageDerivative { sha256, version, ocrText, ocrEngine, visionSummary?, status }
Ledger    { day, model → { reservedTokens, usedTokens, requests, audioSeconds } }
```

**Rückgängig wird je Akteur geführt.** ⌘Z nimmt nur Allans Schritte zurück. Eine KI-Gruppe nimmt man im Rundgang mit „Einordnung zurücknehmen“ zurück. Rücknahme greift nur, wenn das Objekt seit dem Schritt unverändert ist; sonst wird es übersprungen und gezählt („teilweise“). Beides ist im Prototyp umgesetzt und getestet.

### 3.6 Vorrang KI gegenüber Mensch (Stale-Regeln)

Jede KI-Op wird **beim Anwenden** gegen den aktuellen Stand geprüft, nicht gegen den Stand bei der Anfrage.

- Titel mit `titleBy=user`, angepinnte Objekte und Zuordnungen mit `by=user` fasst die KI nicht an.
- Von Allan gelöschte Gedanken, Bereiche und Bezüge bleiben gelöscht (Grabstein). Abgelehnte Bezüge werden nie erneut vorgeschlagen.
- Nachträge (`continue_thought`) sind rein **additiv**. Sie sind auch an bearbeitete Karten erlaubt und einzeln rücknehmbar; der Wortlaut wird dabei zu einer eigenen losen Karte.
- Eine Rohfassung, die Allan bearbeitet, verschoben oder verbunden hat, wird **nicht** durch die Einordnung ersetzt.
- Ein neuer Bereich braucht **mindestens zwei geeignete Gedanken**. Geeignet heißt: lose, nicht von Allan platziert, im Kandidatensatz.

### 3.7 Wachstum ab leerem Board

- Gedanke 1 liegt lose („Noch ohne Thema“). Ein Bereich entsteht erst, wenn ein passender zweiter Gedanke kommt; die Karten gleiten dann sichtbar hinein.
- Bereiche wachsen nur: Die Spaltenzahl steigt bei 3 bzw. 7 Gedanken, neue Karten kommen in die kürzeste Spalte. Bestehende Karten springen nie.
- Bereiche liegen in Erstellungsreihenfolge auf Zeilen; von Allan verschobene Bereiche bleiben, wo er sie hingelegt hat.
- Allans Karten im Bereich sind Hindernisse; KI-Karten weichen aus ([Prototyp] geprüft).
- **Verdichtung** nur bei Bedarf, nicht stündlich. Auslöser:
  - mindestens 6 lose Gedanken, die älter als 3 Tage sind,
  - ein Bereich mit mehr als 15 Gedanken,
  - mindestens 3 KI-Bereiche mit nur einem Gedanken, älter als 14 Tage.

  Dann einmal täglich im Leerlauf `gpt-oss-120b` mit **Vorschlägen** zu Zusammenlegen oder Teilen, ausschließlich für KI-eigene Struktur, rücknehmbar als Gruppe. Das ist im Prototyp nicht umgesetzt.

### 3.8 Gedächtnis als Kern: Bewertung von Allans Idee

**Urteil:** Die Idee trägt, wenn das Gedächtnis ein **abgeleiteter Index** ist und keine zweite Wahrheit und kein Agent.

Was es enthält:

1. **Themen**: ID, Titel, Aliasse (frühere Titel, Umbenennungen), Status (`vorläufig` < 3 Gedanken, `gefestigt`, `bestätigt` durch Allan) und eine extraktive Kurzfassung (letzte Titel, Hauptbegriffe). Es gibt **keine** LLM-Zusammenfassung in v1. Später nur für Bereiche mit mehr als 8 Gedanken, wenn sie veraltet ist, budgetiert und mit Satz-Belegen.
2. **Zuordnungsbeispiele aus Korrekturen**: Zieht Allan eine Karte in einen anderen Bereich, entsteht `{thought, from, to, terms}`. Klingen neue Sprachnotizen ähnlich (BM25), kommen **höchstens zwei** dieser Beispiele in den Prompt. Das ist der Lerneffekt, ohne Profil und ohne Fine-Tuning.
3. **Bezüge** mit Status, Beleg-Sätzen und Ablauf: Unbeantwortete Vorschläge blenden sich nach 30 Tagen aus, der Grabstein bleibt.
4. **Bild-Ableitungen** je SHA-256 und Analyseversion (OCR-Text, optionale Beschreibung): einmal berechnet, nie beim Öffnen neu.
5. **Suchindex** (BM25 mit leichtem deutschem Stemming, Aliasse, OCR-Text); beim Start aus den Originalen neu aufbaubar.

**Hausmeister** (deterministisch, ohne KI; beim Start, nach jeweils N Ops und täglich):

- Ableitungen ohne Quelle entfernen.
- Leere KI-Bereiche auflösen.
- Bezüge zu Gelöschtem entfernen.
- Veraltete Kurzfassungen markieren.
- Caches begrenzen.
- Verwaiste Assets nach Ablauf der Grabstein-Frist löschen.

**Nie** angefasst werden Originalnotizen, Wortlaut, Widersprüche (bleiben stehen) und von Allan gesetzte Dinge.

**Speicher:** Unter Electron 33 / Node 20.18.3 gibt es kein `node:sqlite` (lokal geprüft). `better-sqlite3` wäre ein natives Modul mit Rebuild für arm64, x64, universal und Windows; das ist zusätzliches Build-Risiko neben `uiohook-napi`. Für den persönlichen Maßstab (einige tausend Gedanken) genügen JSONL plus Snapshot plus ein Index im Speicher. Der Store wird hinter einer Schnittstelle gebaut. SQLite mit FTS5 kommt erst, wenn Größe oder Abfragen es verlangen, per Electron-Upgrade oder nativem Modul; beides ist vorher zu prüfen.

**Grenze:** BM25 ist nicht semantisch.

- Synonyme („Lampe“ ↔ „Leuchte“, „Urlaub“ ↔ „Auszeit“) und deutsche Komposita („Esstischlampe“) werden verfehlt.
- Ausgleich: Das Modell sieht **immer alle Bereichstitel mit Aliassen** (höchstens 30), dazu die drei neuesten Gedanken; Korrekturbeispiele gleichen Wiederholungsfehler aus.
- Ob das reicht, ist **empirisch ungeprüft**. Geplant ist ein Messsatz mit synthetischen deutschen Notizen (§9).

Im Prototyp sind Korrekturen, Aliasse, Status, Budgetkonto und Hausmeister umgesetzt (Simulationsleiste → „Gedächtnis“).

### 3.9 Bilder, Screenshots, Einfügen

**Anhang-Modell**

- Inhaltsadressiert: `notes/assets/<sha256>.<ext>` als Original (bis 25 MB) und `notes/thumbs/<sha256>-640.jpg` über Electrons `nativeImage.resize`, also ohne `sharp` zur Laufzeit.
- Im Board-JSON nur Referenzen, **nie Base64**.
- Schreibreihenfolge: Asset nach `tmp`, dann `fsync`, dann `rename`, **danach** die Op. Verwaiste Assets ohne Op werden nach 24 h entfernt.
- Löschen der Notiz setzt einen Grabstein, das Asset bleibt (Rückgängig möglich). Endgültig gelöscht wird nach 30 Tagen oder per „Papierkorb leeren“.
- Exakte Duplikate (gleicher Hash) werden einmal gespeichert und einmal analysiert. **Nur ähnliche** Bilder werden **nicht** zusammengelegt.

**Einfügen (⌘V)**

| Fokus | Bild | Text |
|---|---|---|
| Texteditor (Karte im Bearbeiten-Modus) | – (normales Einfügen, `plaintext-only`) | normales Einfügen |
| Notiz ausgewählt | hängt als Anhang an | hängt als neuer Abschnitt „Eingefügt“ an |
| Leerfläche | neue Notiz mit Bild an freier Stelle | neue Notiz mit Text |

Im Prototyp ist das über den echten `paste`-Handler umgesetzt und getestet.

**Screenshot per Sprache: das Timing-Problem.** STT läuft erst nach dem Aufnahmestopp. Ein Bild, das *nach* der Erkennung von „Bildschirm merken“ entsteht, zeigt den falschen Moment. Rückwirkend geht es nicht. Die Optionen:

| Option | Moment | Kosten / Risiko | Empfehlung |
|---|---|---|---|
| **A. Kamera-Symbol in der Notes-Pille** | genau jetzt | ein Klick; die Pille muss klickbar sein, ohne Fokus zu nehmen | **ja**, immer verfügbar |
| **B. Bildschirmkontext-Modus** (Einstellung, Standard **aus**) | Aufnahmestart | **ein** lokaler, vorläufiger Schnappschuss je Aufnahme; behalten **nur**, wenn die ersten Worte die Kommandophrase sind; sonst sofort nach STT gelöscht (beim Start: Reste älter als 10 min löschen) | **ja**, ehrlich und sprachgesteuert |
| C. Frühe Spracherkennung | einige Sekunden *nach* dem Sprechen | zusätzliche STT-Aufrufe (je ≥ 10 s abgerechnet), Latenz, offline unmöglich, trotzdem falscher Moment möglich | nein |
| D. Ringpuffer (laufende Aufnahme) | beliebig | heimliche Daueraufnahme, Datenschutz, Speicher | nur als ausdrücklich gewählter Modus, nicht empfohlen |

- **Kommando** ist ein enges lokales Muster, nur als **erster Satz bzw. erste Worte**: `(Paply,) Bildschirm merken | Screenshot machen/anhängen/merken | Bild merken`.
  - „Ich müsste mal einen Screenshot machen“ mitten im Satz löst **nicht** aus ([Prototyp] getestet).
  - Die Kommandoerkennung macht der Code, nicht das Modell.
  - Der Kommandosatz verschwindet aus der Karte und bleibt in der Herkunft durchgestrichen sichtbar.
- **Welcher Bildschirm**: der Bildschirm unter dem Mauszeiger beim Auslösen (`screen.getCursorScreenPoint` → `getDisplayNearestPoint` → `desktopCapturer.getSources({types:['screen'], thumbnailSize})`).
  - Die konkrete Quellenzuordnung über `display_id` und ihr Verhalten auf mehreren Displays sind in der App zu prüfen.
  - Nur das aktive Fenster wäre auf dem Mac per nativem Helfer (CGWindowList) möglich; das ist v2.
  - Paplys Pille wird per `setContentProtection(true)` ausgenommen; unter macOS 15 mit ScreenCaptureKit **zu prüfen**.
- **Rechte**: macOS „Bildschirmaufnahme“ (Electron-Doku: Zustimmung ab 10.15). Abgefragt wird nur, wenn Allan die Funktion einschaltet. Das Verhalten unter Sequoia (wiederkehrende Bestätigungen) ist in der Electron-Doku nicht beschrieben und **ungeprüft**.

**OCR und Bildverstehen**

- **Lokal und automatisch, ohne Groq-Verbrauch:** macOS Vision `VNRecognizeTextRequest` (ab macOS 10.15; [Doku]). Die Sprachen kommen zur Laufzeit aus `supportedRecognitionLanguages()`; Sprachverfügbarkeit und Qualität werden auf dem Zielsystem geprüft. Apples Artikel [Recognizing Text in Images](https://developer.apple.com/documentation/vision/recognizing-text-in-images) bestätigt ausdrücklich Verarbeitung auf dem Gerät (im Gegencheck über die verlinkte Markdown-Fassung gelesen).
  - Umsetzung als Swift-Helfer nach vorhandenem Muster.
  - Der Text dient nur der lokalen Suche und Zuordnung.
  - Windows (`Windows.Media.Ocr`): ungeprüft.
- **Cloud-Beschreibung über denselben Groq-Key** nur als eingerichtetes Verhalten, **nicht** schon deshalb, weil ein Bild eingefügt wurde:
  - Modell `qwen/qwen3.8-27b`, das einzige Vision-Modell mit normalem Zugang ([Doku]); Preview, höchstens 3 Bilder je Anfrage, 2.048 Input-Token je Bild.
  - Auslöser: Einstellung an, Notiz ohne brauchbaren Text („wie hier“) und OCR nicht ausreichend.
  - Ein Aufruf je Hash und Version; Tagesgrenze (Vorschlag 10 Bilder).
  - **Nie** die letzten 30 % des Qwen-Tageskontingents, weil das Polieren dasselbe Modell nutzt.
- **Datenschutz**: OCR-Text eines Screenshots ist Bildschirminhalt. Er geht standardmäßig **nicht** in Prompts; das ist eine eigene Einstellung „Bildtext für die Einordnung nutzen“.
- Transkript-, OCR- und Bildtext sind **Daten, keine Anweisungen**. Das Antwortschema enthält keine zerstörenden Operationen; selbst „lösch alles“ im Text kann nichts löschen.

### 3.10 Sicherheit und Datenschutz (Kurz)

- Key nur im Main-Prozess; Notes-Preload ohne Settings-Zugriff; Absender-Prüfung; CSP; kein Modell-HTML.
- Groq sieht: Transkript-Sätze, Bereichstitel und Aliasse sowie Ausschnitte der Kandidaten (Titel und die ersten etwa 200 Zeichen). Das gehört in die Einstellungen als ehrlicher Satz.
  - Die Aufbewahrungsregeln von Groq sind **nicht geprüft**.
- Audio: 7 Tage (wie Meeting-Entscheidung), Transkript dauerhaft. Vorläufige Schnappschüsse werden nach STT gelöscht.

---

## 4. Modellrouting (minimal, belegt)

### 4.1 Aktuelle Fakten ([Doku], 26.10.2026)

| Modell | Status | Für Notes | Belegt |
|---|---|---|---|
| `whisper-large-v3-turbo` | Production | Sprache (Standard) | 100 MB Dateigröße (Dev); **25 MB im Free-Tier**; mindestens 10 s abgerechnet; `verbose_json`, Segmente; Prompt ≤ 224 Token |
| `whisper-large-v3` | Production | Option bei Kontingent-Konkurrenz mit dem Diktat | Groq: WER 10,3 % gegenüber 12 % (turbo); Paplys eigener Benchmark: für Allans Diktate nicht besser |
| `openai/gpt-oss-20b` | Production | **Einordnung (Standard)** | `strict: true` unterstützt; Prompt-Caching (gecachte Token zählen nicht gegen die Limits, 2 h Ablauf); `reasoning_effort low`, `reasoning_format hidden`; ~1.000 tps |
| `openai/gpt-oss-120b` | Production | **nur Eskalation** und seltene Verdichtung | `strict: true`; Caching |
| `qwen/qwen3.8-27b` | **Preview** | optionale Bildbeschreibung | Vision mit 3 Bildern und je 2.048 Token; `strict: true`; vom Polieren mitgenutzt |
| Embeddings | – | – | kein Embedding-Modell in der Groq-Liste |

Weitere belegte Punkte:

- **Structured Outputs**: `strict: true` verlangt `required` für alle Felder und `additionalProperties:false`; optionale Werte als Typ-Union mit `null`. Streaming und Tool-Use gehen damit **nicht**.
- Die Groq-Doku widerspricht sich: Die Vergleichstabelle nennt nur GPT-OSS für strict, die Modellliste zusätzlich Qwen und Muse. Für Notes egal, Standard ist GPT-OSS.
- **Rate Limits**: Die Tabelle auf `docs/rate-limits` ist als „base limits for the Developer plan“ beschriftet. Ihre Werte entsprechen aber den bekannten freien Grenzen: GPT-OSS und Qwen je **30 RPM / 1K RPD / 8K TPM / 200K TPD**, Whisper je **20 RPM / 2K RPD / 7.200 ASH / 28.800 ASD**. Die Modellseite nennt für den Developer-Plan 250K TPM. **Maßgeblich ist die Limits-Seite der eigenen Organisation.** Limits gelten organisationsweit.
- Header: `x-ratelimit-remaining-requests` (RPD), `x-ratelimit-remaining-tokens` (TPM), `retry-after` nur bei 429.
- Ob die konkrete Nutzung kostenlos bleibt, sichert Groq nicht zu.

### 4.2 Routing-Regeln

1. **STT**: `whisper-large-v3-turbo`, Sprache `de`, Prompt aus „Eigene Begriffe“, Stille-Filter des Diktats lesend wiederverwendet. Lange Aufnahmen in Stücke von höchstens 5 Minuten an Sprechpausen.
2. **Einordnung**: `openai/gpt-oss-20b`, `strict` mit `json_schema`, `temperature 0`, `reasoning_effort low`, `max_completion_tokens` ~1.500. **Keine** Tools (kein `browser_search` oder `code_execution`, also keine Recherche).
3. **Eskalation** zu `gpt-oss-120b`, genau ein Versuch, nur wenn:
   - das JSON kaputt oder abgeschnitten ist,
   - der Validator einen harten Fehler meldet,
   - die Notiz länger als ~1.500 Wörter ist oder mehr als 12 Gedanken enthält.

   Danach folgt die lose Rohfassung.
4. **Konfidenz**: Selbstauskünfte des Modells werden **nicht** genutzt. Stattdessen lokale Signale:
   - Validator-Ergebnis,
   - Belegzahl (Bereich ab zwei Gedanken),
   - Abweichung zwischen Modellwahl und BM25-Spitzenbereich; wird nur protokolliert, kein Veto, wegen Synonymen.

   Dass ein kleines schnelles Modell deutsche Gedanken zuverlässig an Satzgrenzen trennt, ist **unbelegt**. Darum gibt das Modell nur IDs zurück, und der Validator prüft Abdeckung und Doppelungen.
5. **Bilder**: OCR lokal, Vision optional (§3.9).
6. **Keine** stündliche Vollreorganisation; nur Auslöser-gesteuerte Verdichtung (§3.7).

### 4.3 Budget und Planer (im Code, nicht im Modell)

- Jobs entstehen **nur durch Code-Regeln**; das Modell kann keine Folgejobs auslösen.
- Höchstens ein Netz-Job und ein lokaler Job gleichzeitig. Prioritäten: Aufnahme sichern > STT > Einordnung > OCR > Bildbeschreibung > Verdichtung.
- **Vor** jedem Request wird reserviert: geschätzte Eingabe plus `max_completion_tokens`. Geprüft wird gegen das lokale Tageskonto (Notes-Anteil, Vorschlag ≤ 50 % der freien TPD) und gegen die zuletzt gesehenen `x-ratelimit-remaining-*`. **Danach** wird die tatsächliche `usage` verbucht.
- Läuft gerade ein Diktat, wartet Notes mit Netzaufrufen.
- Ist das **Einordnungsbudget** leer, kann STT nur im Rahmen seines eigenen verbleibenden Sprachkontingents weiterlaufen. Ist auch dieses ausgeschöpft, bleibt der Ton gesichert, Text folgt erst später. Vorhandene Rohfassungen bleiben lesbar. Beide Wartezustände und der getrennt budgetierte zweite Versuch sind im Gegencheck ergänzt worden.
- **Schätzung** (ungetestet): Eine Einordnung könnte ~2–3K gezählte Token benötigen. Prompt-Caching, Reasoning-Token, Fehlversuche und die tatsächliche Kontextlänge sind noch nicht gemessen. Daraus folgt keine belastbare Anzahl kostenloser Notizen pro Tag; der vorgeschlagene Notes-Anteil würde die verfügbare Menge zusätzlich begrenzen.

### 4.4 Prompt und Schema (Skizze)

- Anordnung für das Caching: **zuerst** die statischen Regeln und die Schemabeschreibung, identisch über alle Aufrufe. Danach die variablen Teile in dieser Reihenfolge:
  1. Bereiche (ID, Titel, Aliasse, Kurzfassung)
  2. Kandidaten (ID, Titel, Anfang)
  3. höchstens zwei Korrekturbeispiele
  4. die neue Sprachnotiz als nummerierte Sätze `[s1] …`, klar als **Daten** markiert
- Groq empfiehlt für Reasoning-Modelle, Anweisungen in die Nutzernachricht zu legen; der statische Teil steht dann am Anfang der Nutzernachricht. **Empirisch zu prüfen**, auch die Cache-Trefferquote (`cached_tokens` in `usage`).

```jsonc
{ "name": "notes_plan_v1", "strict": true, "schema": {
  "type": "object", "additionalProperties": false, "required": ["thoughts","newAreas","relations","dropSentenceIds"],
  "properties": {
    "thoughts": { "type": "array", "items": { "type": "object", "additionalProperties": false,
      "required": ["sentenceIds","title","placement"], "properties": {
        "sentenceIds": { "type": "array", "items": { "type": "string" } },
        "title": { "type": "string" },
        "placement": { "type": "object", "additionalProperties": false, "required": ["kind","areaId","newAreaKey","thoughtId"],
          "properties": { "kind": { "type": "string", "enum": ["existing_area","new_area","loose","continue_thought"] },
            "areaId": { "type": ["string","null"] }, "newAreaKey": { "type": ["string","null"] }, "thoughtId": { "type": ["string","null"] } } } } } },
    "newAreas": { "type": "array", "items": { "type": "object", "additionalProperties": false, "required": ["key","title","memberThoughtIds"],
      "properties": { "key": { "type": "string" }, "title": { "type": "string" }, "memberThoughtIds": { "type": "array", "items": { "type": "string" } } } } },
    "relations": { "type": "array", "items": { "type": "object", "additionalProperties": false, "required": ["from","to","reason"],
      "properties": { "from": { "type": "string" }, "to": { "type": "string" }, "reason": { "type": "string" } } } },
    "dropSentenceIds": { "type": "array", "items": { "type": "string" } } } } }
```

**Lokaler Validator** (im Prototyp umgesetzt):

- Unbekannte oder doppelte Satz-IDs sind ein harter Fehler.
- Nicht zugeordnete Sätze machen den Plan ungültig. Der Validator hängt sie nicht auf eigene Vermutung an ein anderes Thema; die vollständige Rohfassung bleibt als Fallback.
- **Kein automatisches Verwerfen von Inhaltssätzen.** Die ursprünglich vorgeschlagene Acht-Wörter-Regel war falsch: „Nicht veröffentlichen“ ist kurz und wichtig. Im Gegencheck entfernt. `dropSentenceIds` muss im Prototyp leer bleiben; das Produktionsschema soll das Feld gar nicht anbieten. Nur das separat erkannte, ausdrückliche Bildschirmkommando wird außerhalb des Modellplans aus der sichtbaren Notiz entfernt; der ursprüngliche Wortlaut bleibt zugänglich.
- Titel mit 3–70 Zeichen, sonst lokal ersetzt.
- Referenzen nur aus dem Kandidatensatz.
- Neuer Bereich ab zwei geeigneten Gedanken und bis 12 Bereiche; ein gleichnamiger vorhandener Bereich wird stattdessen genutzt.
- Höchstens zwei Bezüge, Begründung 12–240 Zeichen, keine Duplikate oder Grabstein-Paare.

---

## 5. Bibliotheken: Entscheidung

| Kandidat | Lizenz / Größe ([Doku], npm 26.10.2026) | Passt? |
|---|---|---|
| **OpenUI** (thesysdev; `@openuidev/react-lang` 1.0.1, MIT) | Generative UI: Das LLM streamt eine UI-Sprache, ein Renderer zeigt registrierte Komponenten an (Zod-typisiert). | **Korrigiert, siehe §12:** Ja als Renderer für registrierte Paply-Komponenten. Originale, stabile IDs, Undo, Positionen und Nutzervorrang gehören in einen separaten Store. Kein frei generiertes HTML und kein generiertes Datenmodell als zweite Wahrheit. |
| tldraw 5.5.2 | „SEE LICENSE“: **keine Produktionsnutzung ohne Trial- oder Kommerzlizenz**; ~15 MB entpackt | Nein (Lizenz, eigene Store-Semantik) |
| Excalidraw 0.18.1 | MIT, ~47 MB entpackt, handgezeichneter Stil | Nein (Allan fand „skizzenhaft“ schlecht) |
| React Flow (`@xyflow/react` 12.12.0) | MIT, ~1,2 MB entpackt | **Rückfalloption**: Knotengraph mit Pan und Zoom, aber kein Whiteboard (Text, Bereiche, freie Linien müsste man bauen); Kamera-Feeling über d3-zoom statt eigener Regeln |
| Konva / react-konva | MIT; Canvas statt DOM | Nein: Text-Editing, Typografie und Barrierefreiheit wären schwerer |

**Empfehlung:** eigene Bausteine. Das sind wenige Objektarten (Gedanke, Notiz, Text, Linie/Pfeil, Bereich) mit einer Kamera-Transformation, DOM-Karten (echtes Text-Editing, Typografie, Barrierefreiheit) und SVG-Kanten. Kamera, Layout, Validator und Planer sind reine Funktionen und damit einfach zu testen (Vitest ist vorhanden). Ab einigen hundert sichtbaren Karten kommen Viewport-Culling und eingeklappte Bereiche dazu.

---

## 6. Designentscheidungen (`paply-notes-opus.html`)

1. **Inhalt ist Typografie.**
   - Bei Lesezoom zeigt die Karte den ganzen Gedanken: Titel 17/600, Text 15/1,6, Breite 320. Es gibt keinen separaten Leser und kein unteres Bearbeitungsfeld.
   - Bearbeitet wird direkt auf der Karte, **je Abschnitt**, damit die Herkunft je Abschnitt erhalten bleibt.
2. **Herkunft ist Material, ohne Legende.**
   - Gesprochenes erscheint als weißes Papier mit Wellen-Symbol und Uhrzeit.
   - Getipptes erscheint als blassgelbe Notiz (Schnabel-Gelb der Marke).
   - Freier Text erscheint ohne Karte.
   - Nachträge stehen als eigener Abschnitt mit „Nachtrag · 15:05“.
   - Bilder sind kleine Vorschaubilder in der Karte.
3. **Deutung ist gestrichelt.** Vorgeschlagene Bezüge im selben Bereich sind gestrichelte Kurven. **Über Bereiche hinweg** erscheint nur ein gestricheltes „Bezug“-Zeichen an beiden Karten. Erst bei Auswahl kommt die Linie **über** den Karten und die Begründung mit „Behalten / Entfernen / Zeigen“. Lange Linien hinter fremden Karten hatten im Test die falschen Gedanken optisch verbunden.
4. **Bereiche sind ruhige Flächen** mit großem Titel und Metazeile („4 Gedanken · zuletzt 17:30“).
   - In der Übersicht werden Titel als Schilder im Bildschirmraum über den Bereichen gezeigt.
   - Die Karten zeigen dann großen Titel und Textanfang: ganze Gedanken, keine Schlagworte.
   - Darunter folgen ruhige Blöcke.
   - Die Detailstufen wechseln mit Hysterese (0,63/0,69 und 0,29/0,35); die Kartengröße bleibt gleich, also kein „Nachladen“.
5. **Navigation ohne hässliche Knöpfe.**
   - Ziehen auf freier Fläche verschiebt die Ansicht; zwei Finger schieben 1:1; Pinch oder ⌘+Scrollen zoomt um den Zeiger.
   - `[ ]` springt zum nächsten oder vorigen Bereich.
   - Die Brotkrume „Notes / Bereich ▾“ zeigt beim Stillstand, wo man ist, und dient als Bereichsmenü.
   - Ein Klick auf ein Übersichtsschild fliegt hin; Doppelklick auf eine Bereichsfläche ebenfalls.
   - `⇧1` zeigt alles, `⇧2` die Auswahl, `⌘0` setzt 100 %.
   - Unten rechts nur „73 %“ als Menü.
6. **Bewegung im Paply-Takt**: Kurve `cubic-bezier(.3,.7,.4,1)` aus `recording-pill.css`. Flüge dauern 190–330 ms, interpoliert in logarithmischem Zoom, und jede Eingabe bricht sie ab. Neue Karten fliegen aus dem Eingang oder aus der Rohfassung an ihren Platz (FLIP); umziehende Karten gleiten mit 440 ms. `prefers-reduced-motion` wird beachtet.
7. **Autonomie nachvollziehbar.**
   - Der **Eingang** oben rechts zeigt Zustand und Rohtext („Wird eingeordnet …“, „Offline – Ton gesichert“, „Kontingent aufgebraucht – Rohfassung liegt lose“).
   - **„N neue Gedanken“** startet den Rundgang: Er fliegt zu jedem Eintrag, erklärt aus dem **aktuellen** Stand („liegt inzwischen in ‚Auszeit‘“) und erlaubt „Einordnung zurücknehmen“.
   - Die Kamera rahmt automatisch nur, solange Allan sie nicht selbst bewegt hat.
8. **Leerfläche ist Navigation.** Klicken oder Ziehen erzeugt nie etwas. Das Notiz-Werkzeug gilt für einen einzigen Klick. Bereiche zieht man nur am Titel. Leer verlassene neue Notizen verschwinden. Eingefügtes landet an freier Stelle.
9. **Werkzeuge** in einer schmalen Leiste:
   - Auswahl, Hand, Notiz, Text, Pfeil/Linie (ein Werkzeug, Umschalten im Kontextmenü) und Bereich.
   - Aufnehmen als einzige gefüllte Taste, außerdem Rückgängig und Wiederholen.
   - Kontextleiste an der Auswahl mit Bearbeiten, Kopieren, Herkunft, Heranzoomen und Entfernen.
10. **Theme**: Tokens aus `src/globals.css`, hell und dunkel; Systemschrift; Paply-Zeichen aus `brand/mark.svg` und `PaplyMark.tsx`; Icons aus dem lokalen `lucide-react` 0.561.0.

**Bewusst simuliert** und klar gekennzeichnet (Simulationsleiste, Etikett „Simulation“ in der Pille, Beispielbilder beschriftet):

- Modellantworten liegen als **schemaförmige JSON-Objekte** vor und laufen durch denselben Validator, Planer und dasselbe Layout wie im echten Ablauf.
- Aufnahme und Kamera-Symbol erzeugen keinen echten Ton und kein echtes Bild.
- OCR ist nur als Status angezeigt.
- Das Budgetkonto nutzt Schätzwerte.
- Wartezeiten sind verkürzt.

---

## 7. Prototyp bedienen

Öffnen: `docs/prototypes/paply-notes-opus.html`, gerne über einen lokalen statischen Server. Die Simulationsleiste unten links bietet:

- **Leer & live**: „Nächste Sprachnotiz“ spielt einen Tag ab leerem Board ab, mit 8 Einträgen:
  - zwei Themen in einer Notiz,
  - Nachtrag,
  - „Bildschirm merken“,
  - eine erste Antwort, die ungültig ist und zum zweiten Versuch mit 120b führt,
  - eine fast leere Notiz.
- **Abends öffnen**: Derselbe Tag ist bei geschlossenem Fenster schon verarbeitet; mit „Neu“-Rundgang. Der Entwurf startet in diesem Zustand, auf den Bereich Paply Notes fokussiert. Die Simulationsleiste ist zunächst eingeklappt; „Leer & live“ erlaubt den vollständigen Aufbau ab null.
- **Volles Board**: Drei Tage mit 15 Gedanken, 4 Bereichen, eigener Notiz und eigenem Pfeil; in der Übersicht gut zu sehen.
- Umschalter: Groq-Limit (429), Antwort kaputt, Offline, Kontingent leer, Bildschirmkontext, Gedächtnis, Bild einfügen (⌘V), Dunkel.
- Test-API `window.paplyNotesDemo`:
  - `state()`, `scenario(name)`, `next()`, `idle()`
  - `setOnline(bool)`, `failNext('limit'|'invalid')`, `budgetEmpty(bool)`, `screenContext(bool)`
  - `goArea(id)`, `fitAll()`, `setTool(t)`, `select(t,id)`, `edit(id)`, `undo()`, `redo()`, `deleteSelection()`
  - `tour.{start,next,end,revert,current}`, `pasteDemoImage()`, `pasteText(t)`
  - `memory()`, `janitor()`, `record.{start,shot,stop}`, `screenCommand(text)`, `validate(obj,entryId)`
  - `setCamera()`, `worldToScreen()`

---

## 8. Durchgeführte Tests ([Prototyp], Headless-Browser über T3-Vorschau, 1280×800 und 390×844)

| Test | Ergebnis |
|---|---|
| Live-Tag ab leerem Board (8 Einträge) | Gedanke 1 lose; bei 12:40 Teilung in 2 und Bereich „Paply Notes“ aus 2 Gedanken; Nachtrag an die Lampe statt neuer Karte; Bereiche „Zuhause“ und „Auszeit“ entstehen; Bild nur bei „Bildschirm merken“; 18:03 erst ungültig (unbekannte Satz-ID s4), dann 120b gültig. Im Gegencheck bleibt auch der kurze Beitrag 19:20 erhalten. Keine Konsolenfehler. |
| Kommando-Phrase | „Bildschirm merken.“ als erster Satz → Bild hängt an, Satz in der Herkunft durchgestrichen; „Ich müsste … einen Screenshot … machen“ mitten im Text → Schnappschuss gelöscht |
| 429 | Zustand `waiting_limit`, Wiederaufnahme nach Wartezeit, eingeordnet |
| Antwort abgeschnitten | 20b verworfen, 120b geprüft, eingeordnet |
| Offline | Eintrag wartet und holt nach dem Online-Schalter nach |
| Kontingent leer | verschriftet; Rohfassung mit Bild liegt lose; nach Freigabe ersetzt, Bild an der eingeordneten Karte |
| Stale / Allan gewinnt | Allan legt die Lampe in seinen eigenen Bereich „Wohnung“ → KI-Bereich „Zuhause“ wird mit „zu wenig Belege“ verworfen, der Nachtrag trotzdem angehängt, das Regal bleibt lose |
| Ziehen in fremden Bereich | Karte angepinnt, KI-Karten weichen aus; Korrektur im Gedächtnis; ⌘Z nimmt beides zurück |
| Doppelklick-Bearbeiten, Tippen, Esc | Text gespeichert, Undo-Eintrag. **Fehler gefunden und behoben**: Der Neu-Punkt baute den Karteninhalt neu auf, dadurch kam kein `dblclick` → eigene Doppelklick-Erkennung, Punkt als Klasse |
| Bezug-Chip | Popover mit Begründung, Linie über den Karten, Behalten/Entfernen/Zeigen |
| Pfeil-Werkzeug | Karte zu Karte; umschalten auf Linie; Undo |
| Bereich-Werkzeug | Bereich aufziehen, Karten darin gehören dazu, Umbenennen |
| ⌘V-Pfad (echter `paste`-Handler, `DataTransfer`) | Bild ohne Auswahl → neue Notiz an freier Stelle (nach Fix); Text auf ausgewählte Notiz → Abschnitt „Eingefügt“; Bild auf Auswahl → Anhang |
| Großansicht | geöffnet, beschriftet „Beispielbild (Simulation)“, „Vom Gedanken lösen“ |
| Löschen + Undo | Notiz und angehängte Bezüge entfernt bzw. wiederhergestellt |
| Rundgang | Texte aus dem aktuellen Stand; „Einordnung zurücknehmen“ löst den Bereich auf, Gedanken bleiben lose |
| Aufnahme-Pille | Timer, Simulation-Etikett, Kamera-Symbol → Bild am Gedanken |
| Kamera-Messung | siehe §2.1 |
| Übersicht (42 %), Dunkel, 390 px | lesbare Titel und Anfänge, Schilder über den Bereichen (nach Fix), Werkzeugleiste unten, Simulation eingeklappt |

**Nicht getestet:** echtes Trackpad und Bildrate in Electron, Screenreader, Tastatur-Fokusreihenfolge im Detail, Verhalten mit mehr als 100 Karten, echte Groq-Antworten, echte Aufnahme, Screenshot und OCR, Windows.

---

## 9. Offene Risiken und nächste Schritte

**Risiken**

- **Segmentierqualität und Zuordnung** von `gpt-oss-20b` auf Deutsch sind ungetestet. Nötig ist ein Messsatz mit ≥ 60 **synthetischen** deutschen Notizen (keine echten Aufnahmen): ein Thema, mehrere Themen, Korrekturen („nein, eher …“), Wiederholungen, Füllsätze. Gemessen werden Satzabdeckung, Trennrichtigkeit, Platzierungsübereinstimmung, Rate harter Validator-Fehler, Token je Eintrag und Cache-Trefferquote. Das Gleiche läuft gegen 120b als Vergleich.
- **Kontingent**: Die echten Org-Limits stehen nur in der Konsole; Diktat und Notes teilen Whisper. Wenn Konflikte auftreten, Notes auf `whisper-large-v3` legen (eigener Topf je Modell, laut Tabelle je Modell geführt).
- **Qwen-Preview-Wechsel** betrifft die Bildbeschreibung (und das bestehende Polieren).
- **macOS-Rechte** (Bildschirmaufnahme, Sequoia-Dialoge) und `setContentProtection` unter ScreenCaptureKit sind ungeprüft.
- **BM25 und Synonyme**: Die Qualität der Kandidatensuche ist nicht belegt. Wenn sie nicht reicht, kommt zuerst ein Trigramm-Zusatz, ein lokales Embedding-Modell erst später; Kosten und Größe wären neu zu bewerten.
- **Skalierung des Layouts** (1.000+ Karten): Culling, eingeklappte „ruhende“ Bereiche, Archiv nach Zeit.
- **Groq-Datenaufbewahrung** und Hinweis in den Einstellungen.

**Voreinstellungen für einen späteren Implementierungsplan**

1. Kürzel `⌥⌘N` / `⌥⇧⌘N` sind Platzhalter und werden frei einstellbar; kein Grund, den Review für eine Tastenwahl anzuhalten.
2. Tippen-Start/Tippen-Stopp ist die vorläufige Variante. Halten-zum-Sprechen ist erst nach Klärung der gemeinsamen Hotkey-Verarbeitung belastbar.
3. Kamera-Symbol und ein bewusst aktivierbarer Bildschirmkontext gehören zum Entwurf; keine reale Aufnahme ist hier eingebaut.
4. Notes bekommt ein konservatives, einstellbares Budget. Die vorgeschlagenen Prozentwerte sind noch keine empirisch abgesicherte Vorgabe.
5. Bildverstehen gehört nach Allans Ergänzung direkt in den Plan, als abschaltbarer, budgetierter Zusatz mit lokalem OCR-Fallback. Der Preview-Status des verfügbaren Vision-Modells bleibt ein technisches Risiko.

**Vorgeschlagene Reihenfolge**

1. Aufnahme mit Streaming, Store, Queue und STT, dazu ein Board mit Rohfassungen, Lesen und Bearbeiten. Ohne LLM schon nützlich.
2. Einordnung mit Schema, Validator, Layout und Rundgang sowie Messsatz.
3. Gedächtnis und Hausmeister, Bilder mit ⌘V, lokale OCR (Mac).
4. Optional: Bildschirmkontext, Bildbeschreibung, Verdichtung.

Jede Stufe bekommt Unit-Tests der reinen Funktionen (Kamera, Layout, Validator, Planer, Budget) und einen E2E-Test mit Fake-Audio nach dem vorhandenen Muster.

---

## 10. Quellen (abgerufen 26.10.2026)

- Groq Modelle: https://console.groq.com/docs/models
- Groq Structured Outputs: https://console.groq.com/docs/structured-outputs
- Groq Rate Limits: https://console.groq.com/docs/rate-limits
- Groq Speech-to-Text: https://console.groq.com/docs/speech-to-text
- Groq Deprecations: https://console.groq.com/docs/deprecations
- Groq Reasoning: https://console.groq.com/docs/reasoning
- Groq Prompt Caching: https://console.groq.com/docs/prompt-caching
- Groq Vision: https://console.groq.com/docs/vision
- Groq GPT-OSS 20B: https://console.groq.com/docs/model/openai/gpt-oss-20b
- OpenUI: https://github.com/thesysdev/openui
- tldraw-Lizenz: https://github.com/tldraw/tldraw/blob/main/LICENSE.md
- Apple Vision `VNRecognizeTextRequest`: https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- Electron `desktopCapturer`: https://www.electronjs.org/docs/latest/api/desktop-capturer
- npm-Metadaten über `npm view` (Version, Lizenz, entpackte Größe) für `@xyflow/react`, `tldraw`, `@excalidraw/excalidraw`, `konva`, `@openuidev/*`
- Lokal: `electron-menubar/node_modules/electron` 33.4.11 → Node 20.18.3, Chrome 130; `node:sqlite` nicht verfügbar

---

## 11. Gegencheck und Korrekturen durch den Parent-Agenten (26.10.2026)

Der Opus-Entwurf und seine Grundarchitektur wurden geprüft, nicht als fertige Produktimplementierung übernommen. Änderungen bleiben auf die beiden Prototypdateien begrenzt.

**Im Prototyp korrigiert und nachgeprüft:**

- Keine Löschung nach Wortzahl. Alle Inhaltssätze müssen genau einmal vorkommen; fehlende Abdeckung wird abgewiesen statt still einem Thema zugeschlagen. Auch der kurze letzte Demoeintrag bleibt erhalten. Leichte sprachliche Glättung könnte später eine zusätzliche Darstellung sein, immer mit erhaltenem Original; sie ist nicht grundsätzlich durch den Nutzer ausgeschlossen.
- Reservierung und Verbrauch sind getrennt. Auch `gpt-oss-120b` braucht vor seinem einzigen Versuch Budget. Bei fehlendem Budget bleibt die Rohfassung sichtbar. Die Fortsetzung wiederholt nicht unnötig den bereits fehlgeschlagenen 20B-Aufruf.
- Sprachkontingent ist separat begrenzt: ohne Whisper-Budget bleibt der simulierte Ton gesichert, es wird kein Text vorgetäuscht. Wartende Jobs starten erst nach Budgetfreigabe, ohne schnelle Wiederholungsschleife.
- Eine während der Antwortwartezeit gelöschte oder bearbeitete Rohfassung hat auch unmittelbar beim Commit Vorrang; es entstehen keine nachträglichen Duplikate. Der Hausmeister entfernt keine manuell angepinnten leeren Bereiche.
- Für die eingebettete Vorschau eine feste, inhaltsunabhängige Höhe von 800 px statt viewportabhängiger Wurzel. Start im lesbaren Paply-Bereich; Simulation zunächst eingeklappt. Der Aufbau ab null bleibt auswählbar.

**15 zusätzliche Prüfungen über den echten Browserzustand bestanden:**

1. Verwerfen kurzer Inhalte abgewiesen.
2. Fehlende Satzabdeckung abgewiesen.
3. Explizites Anfangskommando erkannt, gewöhnliche Erwähnung abgewiesen.
4. Erster Gedanke ohne erzwungenes Thema.
5. Tag ab null: 9 Gedanken, 3 Bereiche, 1 Anhang aus 8 simulierten Aufnahmen.
6. Ohne Einordnungsbudget kein semantischer Modellaufruf.
7. Fortsetzung nach Budgetfreigabe ohne Duplikat.
8. Größeres Modell bei Nullbudget nicht aufgerufen.
9. Danach nur den größeren Versuch nachgeholt, genau ein Aufruf je Modell.
10. Ohne Sprachbudget kein STT-Aufruf und kein erfundener Text.
11. STT nach Budgetfreigabe nachgeholt.
12. Rohfassung während laufender Einordnung gelöscht: bleibt gelöscht.
13. Synthetischer Wheel-Pan um 40 px: direkt −40 px, nach 150 ms kein Nachlauf, Zoom unverändert.
14. Bild-Paste hängt an ausgewählte Notiz an.
15. Rückgängig entfernt genau diesen Anhang wieder.

**Noch keine Freigabe als Produktionsarchitektur:**

- Satz-IDs verhindern neue Modellprosa im Notizkörper, garantieren aber weder korrekte Transkription noch richtige Semantik. Titel, Trennung, Beziehungen und deutsche Synonyme brauchen den vorgeschlagenen echten Modellbenchmark.
- Der Recorder braucht einen nachgewiesenen Wiederanlauf aus unvollständigen WebM-Daten, sequenzierte/ bestätigte Chunk-Schreibvorgänge und klare Abbruch-/Shutdown-Regeln. Ein `timeslice` allein garantiert keine unabhängig decodierbaren Dateien. Crash-/Kill-Tests fehlen.
- 250-ms-Polling von `isRecording` ist keine Mikrofon-Arbitrierung. Ebenso schützt eine Prüfung nur während der Aufnahme nicht vor Konkurrenz mit anschließend laufender Diktat-Transkription. Gemeinsame Aufnahme-/Request-Prioritäten müssen vor Integration geklärt werden, ohne unerlaubte Änderungen am bestehenden Diktat.
- JSONL/Snapshots benötigen einen einzigen Writer, atomare Gruppen-Commits, Erkennung unvollständiger letzter Zeilen, sichere Kompaktierung und Replay-Tests. SQLite ist weiterhin eine Alternative; fehlendes `node:sqlite` schließt eine andere Einbindung nicht aus.
- Modellbudgets gelten lokal für Notes. Andere Paply-Pfade, Geräte oder Apps können dieselben Organisationslimits verbrauchen. Header sind eine Momentaufnahme; ein garantierter freier Rest lässt sich ohne gemeinsame Koordination nicht reservieren. Für 429/offline müssen auch Gesamtdauer, Wiederholungsobergrenze und sichtbare Wiederaufnahme festgelegt werden.
- Der selbst gepflegte Index und das Layout müssen mit wachsenden Daten getestet werden. Der Prototyp begrenzt Themen und zeigt nur eine kleine Menge; stabile Bereichspositionen, Hindernisse zwischen Bereichen und Suche über 30 Themen sind nicht abschließend gelöst. Keine Behauptung einer bereits bewiesenen Langzeit-Memory.
- Die Entscheidung für eine selbst geschriebene Board-Engine bleibt vorläufig. Entpackte npm-Größen sind keine gemessenen Bundlegrößen. Vergleich mit einer etablierten Grundlage muss auch Textauswahl/IME, Accessibility, Trackpad, große Boards und Wartungsaufwand bewerten. Eigene Paply-Komponenten sind mit einer solchen Grundlage vereinbar.

Echte API-Nutzung, OCR, Screenshot-Berechtigungen, Persistenz, globale Kürzel und das native Trackpadgefühl bleiben ungetestet. Es wurden dafür keine Nutzerdaten oder Keys verwendet.


## 12. Ergänzung nach Allans Rückmeldung: Darstellungsform nach Inhalt

**Parent-Ergänzung, kein weiterer Opus-Review.** Die vorigen Entwürfe haben „Generative UI“ zu stark auf Textkarten reduziert. Das widerspricht Allans wiederholtem Wunsch nach visuell unterschiedlichen, zum Inhalt passenden Darstellungen. Der neue isolierte Prototyp `paply-notes-generative.html` verwendet tatsächlich `@openuidev/react-lang@1.0.1`. Sein Quellprojekt liegt in `openui-notes/`. Vorbereitete Antworten werden mit dem echten Renderer verarbeitet; es gibt weiterhin keine Live-KI, keine Keys und keine Änderung der App-Abhängigkeiten.

### Trennung von Inhalt und Ansicht

1. Originalaufnahme/Transkript/Anhang werden lokal gesichert. Die im vorherigen Review beschriebenen Absturz- und IPC-Fragen bleiben offen.
2. Ein einziger budgetierter semantischer Job soll neue Inhalte aufteilen, relevante bestehende Themen einbeziehen und zugleich eine Darstellungsform vorschlagen. Für das bloße Auswählen zwischen vier Formen ist keine separate Modellrunde nötig.
3. Ein typisiertes Ergebnis referenziert stabile Notiz- und Satz-IDs, Beziehungen, ein `viewKind` und eine kurze Begründung. Der Code validiert vollständige Inhaltsabdeckung, gültige Referenzen, fehlende Werte, Zyklen bei Hierarchien und Größe des Plans. Nutzeränderungen haben Vorrang. Die Vorlage allein beweist keine semantische Richtigkeit.
4. Ein lokaler Compiler übersetzt den akzeptierten Plan in OpenUI Lang mit registrierten Paply-Komponenten. Layout, Icons, Linien, Zoom, Auswahl und Bearbeitung laufen lokal. Kein beliebiger Modellcode, keine Tools oder Netzwerkzugriffe im Renderer.
5. Notizen sind die Datenquelle; die Ansicht ist eine gespeicherte Projektion. Manueller Ansichtswunsch und manuell verschobene Objekte bleiben erhalten. Neue Gedanken ergänzen den betroffenen Teil statt das ganze Board regelmäßig umzubauen.
6. Passt keine Form eindeutig, bleiben freie Notizen. Kein Zwang zur Tabelle oder Mindmap. Ein Modell darf fehlende Inhalte nicht erfinden, um ein Layout zu füllen.

### Kriterien für die Form

- **Mindmap:** ein Zentralthema mit mehreren unabhängigen, belegten Aspekten; keine künstliche Rangfolge.
- **Vergleich:** mindestens zwei explizite Alternativen mit gemeinsamen Kriterien. Fehlende Angaben heißen „Nicht genannt“. Keine erfundenen Preise, Bewertungen oder Vorteile.
- **Ablauf:** eine tatsächlich genannte Reihenfolge. Nebeneinander genannte Gedanken ergeben nicht automatisch einen Prozess.
- **Freie Notizen:** einzelne, unverbundene oder noch unklare Gedanken, auch langer Text.

Das Modell wählt aus einem kleinen Katalog und kann Elemente kombinieren. Die Designsprache bleibt Paply. Die bisherige Empfehlung „keine Libraries“ und das pauschale Nein zu OpenUI sind damit aufgehoben; die Entscheidung für die darunterliegende Board-Engine ist weiterhin separat zu prüfen.

### Kostenrahmen, kein gemessener Verbrauch

Stand 26.10.2026 zeigt die öffentliche Groq-Limittabelle für GPT-OSS 20B/120B jeweils 200.000 Token pro Tag und 8.000 pro Minute; die tatsächlichen Organisationslimits in der Console sind maßgeblich. Bei **angenommenen**, noch nicht gemessenen 3.000 Gesamttoken pro Einordnung wären 20 Einträge 60.000 Token, 50 Einträge 150.000 Token. Whisper hat eigene Audiolimits. Bestehende Paply-Nutzung, Reasoning, Wiederholungen und größere Kontexte benötigen zusätzliche Reserve. Eine Anzahl kostenloser Notizen lässt sich erst nach einem Modellbenchmark verlässlich nennen.

Einordnung und Darstellungswahl sollten derselbe Job sein. Kein erneuter Aufruf für Öffnen, Zoom, Kopieren, manuelles Bearbeiten oder Darstellen. Ein lokaler Quellenindex liefert nur eine begrenzte Kandidatenmenge, Bilder werden nach Inhalts-Hash/Analyseversion zwischengespeichert. Groq dokumentiert für Qwen3.8 2.048 Eingabetoken pro Bild, zusätzlich zu Prompt und Antwort; das Modell ist Preview, deshalb ist die Bildanalyse optional und austauschbar. Erreichte Limits pausieren ausschließlich die betroffenen KI-Jobs; Rohdaten bleiben verfügbar. Keine stündliche komplette Neugenerierung.

### Prüfung des isolierten Prototyps

15 Browserprüfungen bestanden: drei echte OpenUI-Komponenten gerendert, Kontextleiste, Originaltext, Bearbeiten, Erhalt der Änderung beim Ansichtswechsel, Undo über Ansichtswechsel, Entfernen/Undo, direktes Wheel-Pan um 40 px ohne Zoomänderung, keine Rendererfehler, keine extern geladenen Ressourcen sowie echtes Ziehen eines Pfeils und Platzieren einer editierbaren Haftnotiz. Ein dabei gefundener Fehler (der nachfolgende Klick wählte die darunterliegende Notiz) wurde mit gezielter Klick-Unterdrückung behoben und erneut geprüft. Vorschau bei 728 und 390 Pixel geprüft; schmale Ansichten werden neu angeordnet statt unlesbar verkleinert.

Das belegt die technische Vereinbarkeit von OpenUI und separatem editierbarem Zustand, **nicht** die Qualität eines echten semantischen Routers. Der Prototyp enthält vorbereitete Daten und feste Beispielanordnungen. Er ersetzt weder die Produktions-Board-Engine noch Tests zu langen Texten, IME, vielen Elementen, Persistenz, echten Gesten oder KI-Qualität. Die Gates aus §11 bleiben bestehen.

Quellen: [OpenUI](https://github.com/thesysdev/openui), [React-Lang](https://raw.githubusercontent.com/thesysdev/openui/main/packages/react-lang/README.md), [Groq-Limits](https://console.groq.com/docs/rate-limits), [Groq Vision](https://console.groq.com/docs/vision), [Groq Modelle](https://console.groq.com/docs/models).
