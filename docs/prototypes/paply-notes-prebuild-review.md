# Paply Notes – Vorprüfung vor dem Bau

Stand: 26.10.2026, abends · `main` @ `f5e8bff` · App v1.14.1 · Prüfer: Claude Opus 5.5 (extra high)
Bezug: `docs/notes/IMPLEMENTIERUNG.md` (Bauplan des Koordinators), `paply-notes-opus-review.md` (§§11–12),
`paply-notes-generative.html` mit Quelle `openui-notes/src.jsx`.

**Was ich getan habe:**

- Gelesen:
  - `electron-main.js` (Store, Fenster, Diktat-Lebenszyklus, Backups, Hotkeys, IPC, Lifecycle) und `preload.js`
  - `dictation/{policies,jobs,groq-models,polish-client,polish}.js`, `meeting/{beta-mode,meeting-controller,meeting-store}.js`
  - `audio/*` und der Recorder-/Pillen-Code (`useDictationRecorder.ts`, `RecordingPill.tsx`, `recording-pill.css`, `MeetingOverlay.tsx`, `mic-worklet.js`)
  - Einstellungen (`SettingsApp.tsx`, `MeetingBetaSettings.tsx`, `src/lib/shortcut.ts`)
  - `vite.config.ts`, `vitest.config.ts`, `package.json` (`build.files`), `.github/workflows/build-release.yml`
  - Tests: `test/helpers/dictation-main.js`, `settings-sync.test.js`
  - der OpenUI-Prototyp und die OpenUI-Pakete in `openui-notes/node_modules`
- Ausgeführt:
  - `npx vitest run` in `electron-menubar`: **38 Dateien, 529 Tests grün**. Das ist die Ausgangsbasis vor jeder Notes-Änderung.
  - `npm view` für `@xyflow/react` und `@openuidev/react-lang`.
  - `npm pack @xyflow/react@12.12.0 @xyflow/system@0.0.83`, entpackt nach `/tmp/paply-review-xyflow-pkg`. Dort habe ich nur gelesen, nichts ausgeführt.
- **Nicht** getan:
  - App gestartet, Keys gelesen, Groq aufgerufen, App-Code geändert
  - E2E-Tests, Trackpad-Test, Windows
- Groq-Fakten (Limits, strict-Modus, Modellstatus) stammen aus dem Vor-Review vom 26.10. Heute habe ich sie nicht erneut geprüft.

---

## 0. Urteil

**Baubar, ohne Umbau des Diktats.** Es gibt keinen Grundsatz-Blocker. Neun Entscheidungen (§2) müssen vor bzw. beim Bau feststehen. Jede davon ist konkret entschieden und mit Abnahmetests versehen.

Empfehlung in Kürze:

1. **Recorder:** PCM über AudioWorklet (Muster Meeting) wird nur angehängt, dazu Epochen-Gate im Main. Kein MediaRecorder-WebM.
2. **Mikrofon:** Diktat und Meeting haben immer Vorrang, Notes weicht aus. Die Garantie liegt synchron im Main: **eine** Zeile in `publishRecordingState()` plus Epochen. Polling ist keine Arbitrierung.
3. **Grenze:** eigene Preloads (Board, Pille), `sandbox`, Absender- und Payload-Prüfung, CSP, eigenes Protokoll für Bilder und Ton. Der Key bleibt im Main.
4. **Speicher:** atomares JSON, aufgeteilt nach Änderungsrate. Quellen werden einmal geschrieben, der Eintragszustand je Eintrag, das Board als eine Datei mit Generationen. **Kein SQLite in v1.**
5. **KI-Sicherheit:** Satz-Claims plus Grabsteine plus Revisionen. Die KI kann nichts wiederbeleben, nichts löschen und keinen Nutzertext ändern.
6. **Plan:** GPT-OSS-20B mit strict JSON, lokaler Validator, bei hartem Fehler einmal 120B, sonst Rohfassung. Kartentext sind **wörtliche Zitate** mit Verneinungsprüfung, nie Paraphrasen.
7. **Board:** **React Flow 12** als Leinwand mit Paply-Knoten. OpenUI ist der kontrollierte Renderer der Knoteninhalte und hat ein Performance-Gate. Das Modell erzeugt nie OpenUI Lang.
8. **Layout „einmal platzieren“:** Positionen berechnet das Board deterministisch nach Messung. Danach bleiben sie stabil, und beim Öffnen wird nicht neu erzeugt.

**Korrektur am Bauplan** (`docs/notes/IMPLEMENTIERUNG.md`): „Mikrofon-Sperre … in beide Richtungen“ darf **nicht** heißen, dass Notes das Diktat blockiert. Cmd+X muss während einer Notes-Aufnahme exakt wie heute funktionieren. Nur Notes pausiert bzw. startet nicht.

---

## 1. Live-Code-Befunde (verifiziert)

| # | Befund | Stelle | Folge für Notes |
|---|---|---|---|
| 1 | `setupUioHookKeyUp` ruft `hook.removeAllListeners('keyup')`; `stopUioHook` ebenso | `electron-main.js:1911`, `:1954` | Notes nutzt **kein** uiohook; Kürzel nur über `globalShortcut`, Tippen-Start/-Stopp |
| 2 | `isRecording` ist ein Modul-Global. `publishRecordingState()` ist der zentrale Aufruf bei Start (`:1262`), Fehler (`:1286`) und Stopp (`:1295`) und läuft **vor** `recording:start` an die Pille (`:1275`) | `:1207`, `:1231–1233`, `:1256–1306` | Einziger sauberer synchroner Haken für Vorrang (M2) |
| 3 | Meeting und Diktat arbitrieren heute gar nicht; `start()` prüft kein Diktat | `meeting/meeting-controller.js:199–260` | Kein Vorbild; Notes muss es selbst lösen, ohne `meeting/*` zu ändern |
| 4 | `settings:get` liefert `groqApiKey` und `geminiApiKey`; alle Fenster laden `preload.js`; Absenderprüfung nur bei `recording:*` (`fromRecorder`) | `:2153–2176`, `:2467`; `preload.js` | Eigene Preloads und Absenderprüfung (M3); Bestandsleck bleibt eigener Befund |
| 5 | Keine CSP in irgendeinem `src/*.html`, kein `sandbox` in den `webPreferences` | `src/*.html`, `:826`, `:874`, `:967` | Notes-Fenster explizit härten |
| 6 | `transcribeAudio` wiederholt 429 nach festen 1–3 s ohne `retry-after`; `readResponse` gibt **keine Header** zurück | `:500–504`; `dictation/policies.js` (`readResponse`) | Eigener Groq-Client mit Headern (M7) |
| 7 | `cleanupOldBackups` löscht in `audio-backups/` **alles** über 24 h; `clearSuccessfulBackups` löscht alles Ältere | `:1498–1541` | Notes nie in `audio-backups/` ablegen |
| 8 | Die Test-Harness schneidet Codebereiche per Markertext aus `electron-main.js` und führt sie in einer VM aus (u. a. `publishRecordingState` … `// PUSH-TO-TALK LOGIC` und `settings:set` … `// History`) | `test/helpers/dictation-main.js:44–51`, Kontext `:19–41` | Notes-Code nur außerhalb dieser Bereiche; für den einen Haken einen Stub in den VM-Kontext; Marker nicht verändern |
| 9 | `build.files` ist eine Whitelist; `vitest` schließt nur `test/`, `audio/`, `meeting/`, `src/lib/` ein; Vite hat fünf feste Eingänge | `package.json` (`build.files`), `vitest.config.ts`, `vite.config.ts` | `notes/**`, Preloads, Testmuster und HTML-Eingänge ergänzen; sonst Absturz in der gepackten App oder ungetestete Module (M9) |
| 10 | `@openuidev/react-lang` hängt fest an `@openuidev/devtools` (im Prototyp **45 MB** auf der Platte) | `openui-notes/node_modules/@openuidev` | Renderer-Bibliotheken als **devDependencies**; electron-builder packt sonst `dependencies` in die `app.asar` |
| 11 | `@openuidev/lang-core` sendet beim **postinstall** Telemetrie an PostHog, abschaltbar über `OPENUI_TELEMETRY_DISABLED=1` bzw. `DO_NOT_TRACK=1`. Laufzeit-Telemetrie ist opt-in (`OPENUI_RUNTIME_TELEMETRY_ENABLED`). Devtools werden nur bei `NODE_ENV=development` geladen | `lang-core/package.json:94`, `lang-core/dist/shared-*.mjs:2–18`, `react-lang/dist/index.mjs:15` | Umgebungsvariable lokal und in der CI; CSP `connect-src 'none'` als zweite Sperre |
| 12 | Einstellungen existieren doppelt (Dashboard und Settings-Fenster), ein Drift-Test sichert das ab | `settings-sync.test.js`, `MeetingBetaSettings.tsx` | Gemeinsame `NotesSettings.tsx` in beiden Ansichten |
| 13 | `meeting-store` schreibt mit `writeFileSync` direkt (nicht atomar) | `meeting/meeting-store.js:131, 151` | Muster nicht übernehmen |
| 14 | React-Flow-Standards: `panOnScroll=false`, **`panOnScrollSpeed=0.5`**, `minZoom 0.5`, `maxZoom 2`, `zoomOnDoubleClick=true`, `deleteKeyCode='Backspace'`. Der Pinch-Faktor ×10 gilt **nur auf macOS** | `@xyflow/react` 12.12.0, `index.mjs:3767`; `@xyflow/system` `index.mjs:2759–2796` | Ohne Übersteuerung fühlt es sich träge an (halbe Pan-Geschwindigkeit); unter Windows wäre Pinch rund 10× langsamer |
| 15 | Paply setzt kein Anwendungsmenü; das Electron-Standardmenü mit Zoom-, Reload- und Undo-Rollen ist aktiv | kein `setApplicationMenu` in `electron-main.js` | ⌘0, ⌘+/−, ⌘Z und ⌘R im Notes-Fenster selbst abfangen |
| 16 | Die Diktat-Pille ist klick-durchlässig und nicht fokussierbar | `:961`, `:978` | Das Kamera-Symbol braucht `setIgnoreMouseEvents(true,{forward:true})` mit Hover-Umschaltung und `acceptFirstMouse` (in der App prüfen) |
| 17 | Der Prototyp nutzt feste 900×550-Kompositionen, feste Koordinaten, Annotationen je Thema und Undo als Vollkopie des Zustands. Mehrere Kartentexte sind **Paraphrasen, die so nicht in der Quelle stehen** („Abends soll es gemütlich sein“, „Ein paar Tage raus“) | `openui-notes/src.jsx:17–34` (u. a. `:22`, `:23`), `commit()` `:76` | Nur Optik und Komponenten übernehmen, keinen Code. Die Kürze muss aus wörtlichen Zitaten und Deutungs-Labels kommen (§5.6) |
| 18 | Projektentscheidung vom 21.10.: alles gleichwertig für macOS **und** Windows. Unter Windows bedeutet Strg+Y „Wiederholen“ | `docs/ENTSCHEIDUNGEN.md` | Kürzel-Vorgaben je Plattform; Windows-Grenzen benennen |
| 19 | `dictation/polish.js` exportiert `negationCount` als reine Funktion | `dictation/polish.js:19–21, 51` | Nur lesend für die Zitat-Prüfung wiederverwenden |

---

## 2. Muss-Entscheidungen

Die Reihenfolge entspricht der Bau-Reihenfolge.

### M1 Aufnahme: PCM anhängen statt WebM

**Entscheidung:**

- Das Notes-Pillenfenster ist zugleich Recorder: `notes-pill.html` mit eigenem Preload `notes-capture-preload.js` und `backgroundThrottling:false`.
- Aufgenommen wird über ein AudioWorklet wie in `meeting-overlay/mic-worklet.js`, mit Downsampling auf 16 kHz mono Int16 wie in `MeetingOverlay.tsx:20–55`.
- Etwa alle 200 ms ein Paket `notes:pcm {entryId, epoch, seq, buf}`.

**Main:**

- Prüft Absender, `entryId` und `epoch`.
- Hängt an `sources/<entry>/rec.pcm` an, mit `fsync` spätestens alle 2 s und beim Stopp.
- `entry.json` (atomar) enthält `state`, `sampleRate`, `bytes`, `droppedPackets` und `seqGaps`.
- Ein Ack ist unnötig, weil der Renderer nichts über das Senden hinaus puffert. `seq` dient nur der Lückenerkennung, und Lücken werden nie aufgefüllt.

**Stopp:**

- Letzter Flush, dann `captured`.
- Die WAV-Datei für Whisper entsteht erst beim Upload: Header plus PCM, geschnitten an leisen Stellen in Stücke von höchstens 10 min. 10 min sind 19,2 MB und liegen damit unter der Free-Tier-Grenze von 25 MB.

**Wiederanlauf:**

- Ein Eintrag im Zustand `recording` wird auf eine gerade Byte-Länge gekürzt und auf `captured` gesetzt.
- Verloren gehen höchstens die letzten 2 s.

**Grenzen:** höchstens 30 min je Aufnahme (Pille warnt ab 25 min). Bei vollem Speicher endet die Aufnahme, und das Gesicherte bleibt.

**Nicht verwenden:** `useDictationRecorder`, `recording:*`-Kanäle, `audio-backups/`, `addToHistory`, `autopasteText`. Notes fügt nie ein.

### M2 Mikrofon-Vorrang

Diktat und Meeting bleiben unverändert und haben Vorrang. Notes weicht aus und sperrt nie.

- **Notes-Start**, während `isRecording` gilt oder ein Meeting aktiv ist: kein Start, die Pille zeigt 1,2 s „Diktat läuft“ bzw. „Meeting läuft“. Die Prüfung läuft synchron im Main vor dem ersten `await`.
- **Diktat startet während einer Notes-Aufnahme:**
  - Eine Zeile in `publishRecordingState()` (`:1231`): `notesBridge.dictationState(isRecording);`.
  - Der Main setzt `paused` **synchron** und verwirft ab da jedes PCM-Paket.
  - Das geschieht vor `recording:start` an die Diktat-Pille (`:1275`), also bevor deren Mikro offen ist und der Startton läuft.
  - Die Grenze ist damit deterministisch und unabhängig vom Renderer-Timing.
- **Diktat endet:**
  - Der Main erhöht `epoch` und sendet nach 350 ms `notes:capture:resume {epoch}`. Die Wartezeit deckt den Stoppton ab.
  - Pakete mit alter Epoche werden verworfen, daher gelangt kein Rest des Diktats in die Notiz.
  - Die Pille zeigt währenddessen „Pausiert · Diktat“.
- **Meeting startet:**
  - Nur in der Verdrahtung in `whenReady` (`:2566`): `showOverlay: () => { notesBridge.meetingStarted(); return showMeetingOverlay(); }`. Eine laufende Notes-Aufnahme endet und wird gesichert.
  - `meeting/*` bleibt unberührt.
- **Polling** von `isRecording` dient höchstens der Anzeige, nie als Grenze.
- **Test-Harness:** `notesBridge: { dictationState: vi.fn(), meetingStarted: vi.fn() }` in den VM-Kontext von `test/helpers/dictation-main.js` aufnehmen. Neuer Test für darwin und win32: `dictationState(true)` kommt vor dem Senden von `recording:start`, und bei Stopp bzw. Fehler wird `dictationState(false)` gerufen.
- **Autorisierung:** Die Zeile ist ein notwendiger Integrationshaken und kein Diktat-Umbau. Sie ist damit vom Auftrag gedeckt.
- **Rückfall ohne diese Zeile:** zusätzlicher `ipcMain.on('recording:started')`-Listener. Dann landen aber Startton und etwa 50–250 ms in der Notiz. Nicht empfohlen.

### M3 Secret- und IPC-Grenze

- **Preloads:** `notes-preload.js` (Board, `window.paplyNotes`) und `notes-capture-preload.js` (Pille). Nie `preload.js`, keine `settings:*`-Kanäle.
- **`webPreferences`:** `{ sandbox:true, contextIsolation:true, nodeIntegration:false, spellcheck:true }`.
- **Navigation:** `setWindowOpenHandler → deny`, `will-navigate → preventDefault`.
- **CSP** in `notes.html`: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' paply-notes: data: blob:; media-src paply-notes:; connect-src 'none'; object-src 'none'; base-uri 'none'`.
- **Absender:** Jeder `notes:*`-Handler prüft `event.sender` gegen genau sein Fenster.
- **Payloads:** Prüfung im Main mit `zod` (CJS-fähig) oder kleinen Hand-Validatoren. Obergrenzen: Notiztext 20.000 Zeichen, Bild 25 MB, Batch 200 Ops, IDs per Muster.
- **Protokoll:** Bilder und Ton laufen über `protocol.handle('paply-notes')`. Erlaubt sind nur `asset/<sha256-hex>.<ext>`, `thumb/<sha256-hex>` und `audio/<entryId>`; der Renderer übergibt nie Pfade. `registerSchemesAsPrivileged` steht vor `ready`.
- **Notes-Einstellungen:** eigene Handler `notes:settings:get/set`, erlaubt nur aus `mainWindow` und `settingsWindow`. Die Antwort enthält `hasGroqKey: boolean`, nie den Key. Im Haupt-Preload kommen nur `getNotesSettings` und `setNotesSettings` hinzu.
- **Modelltext** wird nur als Text gerendert: kein `dangerouslySetInnerHTML`, kein Markdown-HTML.

### M4 Speicher: atomares JSON, aufgeteilt nach Änderungsrate

| | **Atomares JSON (Empfehlung)** | JSONL-Oplog + Snapshot | better-sqlite3 |
|---|---|---|---|
| Absturzsicherheit | tmp → fsync → rename je Datei | erst mit Erkennung abgerissener Zeilen, Replay und Kompaktierung | sehr gut (WAL) |
| Build-Risiko | keins | keins | natives Modul für mac arm64/x64 und Windows x64, CI ohne Tests, Notarisierung |
| Aufwand | klein | mittel bis hoch | mittel, dazu Schema und Migrationen |
| Umstiegssignal | `board.json` > 5 MB oder Schreibzeit p95 > 50 ms → SQLite hinter derselben `NotesRepo`-Schnittstelle | – | – |

```
<userData>/notes/                     (Test-App: ~/.paply-test/notes)
  board.json          kanonisch: Notizen, Themen, Strukturen, Linien, Positionen, Claims, Grabsteine, rev, schemaVersion
  board.prev.json     letzte erfolgreich geschriebene Fassung
  backups/            stündlich ×24, täglich ×7
  sources/<entryId>/  entry.json (Zustandsautomat, atomar) · rec.pcm (nur anhängen)
                      transcript.json (einmal geschrieben: Sätze mit IDs/Zeiten/Modell) · plan.json (akzeptierte Antwort + Prüfprotokoll)
  assets/<sha256>.<ext> · thumbs/<sha256>.jpg (nativeImage.resize)
  ledger.json         Budget · tmp/ (vorläufiger Start-Screenshot, ≤ 10 min)
```

- **Schreiben:**
  - Ein einziger Schreiber im Main (Promise-Kette) mit 250 ms Debounce, spätestens nach 2 s.
  - `flush()` bei `before-quit`, beim Ausblenden des Fensters und in `shutdown`.
  - Unter Windows kann `rename` mit EPERM/EBUSY scheitern (Virenscanner). Dann drei Wiederholungen nach 50, 150 und 400 ms; danach bleibt die alte Fassung, und es erscheint ein Hinweis.
- **Laden:**
  - Reihenfolge `board.json` → `board.prev.json` → neuestes Backup.
  - Quellen ohne Claim erscheinen als Rohfassung. Es geht nie still etwas verloren.
  - Migration über `schemaVersion`.
- **Undo-Verlauf:** nur im Speicher, als inverse Ops, höchstens 200 Schritte. Keine Vollkopien.

### M5 KI-Commits können nichts wiederbeleben

- **Claims:** `claims[sentenceId] = noteId | {tomb:true}`. Jeder Quellsatz gehört höchstens einer lebenden Notiz. Löschen setzt Grabsteine auf ihre Sätze; Rückgängig hebt sie wieder auf.
- **Was die KI übernehmen darf:** nur unbeanspruchte Sätze oder Sätze einer **unberührten** Rohfassung (`rev === createdRev`).
- **Berührte Rohfassung** (bearbeitet, verschoben, verbunden, Thema gesetzt): Der Plan für diese Sätze entfällt, der Eintrag erhält `kept_user`.
- **Prüfung beim Anwenden:** Jede KI-Op trägt Vorbedingungen und wird gegen den **aktuellen** Stand geprüft:
  - Ziel existiert und ist nicht gelöscht.
  - Das Feld gehört nicht dem Nutzer.
  - `rev` ist seit Job-Start unverändert.

  Ein Verstoß überspringt die Op und wird protokolliert.
- **Was die KI nie tut:** löschen; angepinnte (vom Nutzer bewegte) Elemente verschieben; `note.text` nach dem Anlegen ändern; Nutzer-Themen umbenennen; Strukturen mit `owner:user` ändern.
- **Nachtrag an eine bearbeitete Notiz:** neue Notiz daneben mit gestrichelter Beziehung „Nachtrag“, kein Anhängen von Text.
- **„Einordnung zurücknehmen“** gilt je KI-Gruppe und betrifft nur seither unveränderte Elemente. Der Rest bleibt, Meldung „teilweise“.
- **⌘Z/⇧⌘Z** betreffen nur Nutzerbefehle, geführt im Main mit derselben Vorbedingungsprüfung.
- **Eintrag gelöscht, während sein Job läuft:** `AbortController`, das Ergebnis wird verworfen.

### M6 Plan-Vertrag

Strict JSON, lokale Prüfung, keine Teilrettung. Details in §4.

- **Harte Fehler** führen zu genau einem Versuch mit 120B, danach bleibt die Rohfassung. Es gibt keine Zuordnung von Restsätzen und kein Verwerfen von Sätzen; ein Feld zum Verwerfen kommt im Schema gar nicht vor.
- **Weiche Fehler** werden lokal herabgestuft: Zitat → ganzer Satz, Struktur → freie Notizen, Beziehung → entfällt.

### M7 Budget, Netzvorrang, Warteschlange

- **Eigener Client** `notes/groq.js` (fetch mit Headern), mit Fehlerklassen und `retry-after`.
- **Vorrang Diktat:** Kein Notes-Request startet, solange `isRecording || dictationJobs.pending().length > 0` gilt. Das ist ein reiner Getter ohne Änderung am Diktat. Laufende Requests werden nicht abgebrochen.
- **Ein Netz-Job gleichzeitig.** Reihenfolge: Aufnahme sichern > STT > Einordnung > Bildbeschreibung.
- **Reservierung vor jedem Request** im Minuten- und Tagesfenster je Modell:
  - Werte aus `x-ratelimit-*` nachführen.
  - Der Notes-Anteil liegt standardmäßig bei höchstens 50 % des Tageslimits.
  - Bei 8K TPM bedeutet das höchstens etwa einen Einordnungsjob pro Minute.
  - Nach dem Request wird `usage` verbucht (prompt, completion, cached).
- **Fehlerklassen:**

  | Fehler | Verhalten |
  |---|---|
  | offline | `net.isOnline()` und Backoff 30 s / 2 min / 10 min; zählt nicht als Versuch |
  | 429 | `retry-after` plus Jitter; zählt nicht; endet nach 24 h |
  | 401/403 | Warteschlange pausiert, Hinweis „Schlüssel prüfen“ |
  | kein Key | `waiting_key`, alle 60 s neu prüfen; kein Settings-Haken nötig |
  | 5xx/Timeout | höchstens 5 Versuche über 24 h, danach `needs_attention` mit „Erneut“ |
  | `model_*` | Modell aus der Liste nehmen, Ausweichmodell |

- **Zustand je Eintrag** steht in `entry.json`. Beim Neustart fällt `transcribing` auf `captured` und `structuring` auf `transcribed` zurück.
- **Keine Folgejobs** durch das Modell, keine periodische Neuordnung, kein Modellaufruf beim Öffnen, Zoomen, Bearbeiten oder Darstellen.

### M8 Board-Grundlage: React Flow 12 mit Paply-Knoten

**Begründung:** React Flow bringt mit, was dem Prototyp fehlt:

- Ziehen und Mehrfachauswahl
- `NodeResizer`
- mitlaufende Kanten und `onReconnect`
- Viewport-Culling, `fitBounds`/`setCenter` und `NodeToolbar`
- Tastatur-A11y

Die Lizenz ist MIT, das Paket entpackt 1,2 MB, Peer ist React ≥ 17.

**Andere Kandidaten:** Das Urteil des Vor-Reviews bleibt bestehen. tldraw scheitert an der Produktionslizenz, Excalidraw am Skizzenstil, Konva am Text-Editing.

**Was selbst gebaut wird:**

- freie Linien über Endpunkt-Knoten
- Themenrahmen über Datenzugehörigkeit
- „Einmal platzieren“-Layout
- Detailstufen

Konfiguration in §5.1.

### M9 Paket- und Testverdrahtung

- **`build.files`:** `notes/**/*`, `notes-preload.js` und `notes-capture-preload.js` ergänzen. Das ohnehin vorhandene `!**/*.test.js` bleibt.
- **`vitest.include`:** `notes/**/*.test.js` und `src/lib/notes/**/*.test.ts` ergänzen.
- **Vite-Eingänge:** `notes` und `notes-pill` ergänzen.
- **devDependencies** (Vite bündelt): `@xyflow/react@12.12.0`, `@openuidev/react-lang@1.0.1`, `zod@4`. Wenn der Main `zod` nutzt, gehört es zusätzlich in die `dependencies`.
- **Telemetrie:** `OPENUI_TELEMETRY_DISABLED=1` in der lokalen Shell und im `env:` von `build-release.yml` setzen. Eine Bundle-Prüfung stellt sicher, dass die gebauten Notes-Assets weder `OpenUIDevtools` noch `posthog` enthalten.
- **TypeScript:** `npx tsc --noEmit` darf in den Notes-Dateien keine **neuen** Fehler bringen. Laut Bauplan gibt es fünf vorbestehende Fehler im Dashboard, und Vite prüft keine Typen.

---

## 3. Zielbild v1

### 3.1 Module

```
electron-menubar/notes/           (Main, CommonJS)
  index.js       createNotes(deps) → { start, shutdown, bridge, openBoard }
  contracts.js   Entitäten, Op-Typen, IPC-Payload-Validatoren (zuerst bauen, gemeinsame Grundlage aller Pakete)
  repo.js        atomares JSON, Generationen, Laden/Wiederherstellen
  commands.js    Nutzer-/KI-/Layout-Ops anwenden, Inverse, Claims, Vorbedingungen, Undo/Redo
  capture.js     Pillenfenster, PCM-Sink, Epochen/Pause, Start-Screenshot, Kamera
  hotkeys.js     Aufnahme-/Öffnen-Kürzel; replaceShortcut (lesend aus dictation/policies) + Kollisionsliste
  queue.js       Zustandsautomat, Prioritäten, Backoff, Netzvorrang
  groq.js · ledger.js · stt.js (WAV, Stücke, Stillefilter, Sätze) · plan.js (Prompt, Schema, Validator)
  vision.js (optional) · assets.js (Hash, Thumbs, Protokoll) · settings.js · index-bm25.js
notes-preload.js · notes-capture-preload.js
src/notes.html · src/notes-pill.html
src/apps/notes/   NotesApp, board/{Canvas, nodes/*, edges/*, Toolbar, ContextBar, Inbox, TopicNav}, openui/{library, compile, render}
src/apps/notes-pill/  NotesPill.tsx (eigene Komponente, nutzt recording-pill.css-Tokens; RecordingPill.tsx bleibt unberührt)
src/lib/notes/    layout.ts, lod.ts, geometry.ts (reine Funktionen, Vitest in Node)
src/components/NotesSettings.tsx
```

### 3.2 IPC-Fläche

| Kanal | Absender | Inhalt |
|---|---|---|
| `notes:board:get` | Board | Snapshot des Boards; Quellen nur auf Anfrage |
| `notes:command` | Board | `{ops[], baseRev}` → `{rev, patches, rejected[]}` |
| `notes:undo` / `notes:redo` | Board | – |
| `notes:patch` (Main → Board) | – | Änderungen durch KI, Layout und andere Wege |
| `notes:source:get` | Board | Transkriptsätze zu einer Notiz („Original“) |
| `notes:attach` | Board | `{bytes, mime, target}`; magische Bytes PNG/JPEG/GIF/WebP; ≤ 25 MB |
| `notes:entry:retry` / `notes:entry:discard` | Board | Eingang |
| `notes:capture:toggle` | Board, Hotkey | Start/Stopp |
| `notes:pcm`, `notes:capture:started/failed`, `notes:camera` | Pille | Aufnahme |
| `notes:capture:state` (Main → Pille) | – | `recording` · `paused` · `saved` · `refused` · `error` · `resume{epoch}` |
| `notes:settings:get/set` | Dashboard, Settings | ohne Key, mit `hasGroqKey` |

### 3.3 Ablauf

```
Kürzel ─▶ Main: Vorrangprüfung (synchron) ─▶ entry=recording ─▶ Pille zeigt sich + Mikro ─▶ PCM → rec.pcm
         [Bildschirmkontext an? → 1 Schnappschuss nach tmp/, Pille mit setContentProtection]
Stopp ─▶ flush + captured ─▶ (Diktat-Vorrang/Online/Key/Budget?) ─▶ STT → transcript.json → Rohfassung (Claims)
      ─▶ Kommando „Bildschirm merken …“ als erster Satz? ja → Anhang behalten, Satz aus der Abdeckung nehmen; sonst tmp löschen
      ─▶ Kandidaten (BM25 + Aliasse + 3 neueste) ─▶ 20B strict ─▶ Validator ─▶ (hart: 120B einmal) ─▶ Commit-Gruppe (pos:null)
Board offen/öffnet ─▶ unplatzierte Elemente messen ─▶ layout.ts ─▶ ein `place`-Befehl (Bedingung pos==null) ─▶ „Neu“-Markierung
```

Zustände: `recording → captured → transcribing → transcribed → structuring → placed | fallback | kept_user | discarded`. Dazu kommen die Wartezustände `waiting_network | waiting_limit | waiting_budget | waiting_key | needs_attention`.

---

## 4. KI-Job

### 4.1 Kontext und Grenzen

**Inhalt der Anfrage:**

- Statischer Regelblock zuerst; er ist für den Cache über alle Aufrufe identisch.
- Danach höchstens **15 Themen** (ID, Titel, ≤ 3 Aliasse, 3 neueste Labels, Strukturarten).
- Höchstens **10 Kandidatennotizen** (ID, Thema, Label, die ersten 160 Zeichen, Struktur).
- Höchstens 2 Korrekturbeispiele.
- Die neue Aufnahme als `[s3] …`, ausdrücklich als **Daten** markiert und nicht als Anweisung.

**Grenzen:**

- Höchstens 60 Sätze je Job; längere Aufnahmen werden in 60er-Fenster geteilt, und das zweite Fenster sieht die Notizen des ersten als Kandidaten.
- Eingabe-Ziel ≤ 3,5K Token.
- `max_completion_tokens`: 2.500 für 20B (Reasoning `low`/`hidden` zählt mit), 4.000 für 120B.
- `temperature` zwischen 0 und 0,2. Keine Tools.

**Schätzung, nicht gemessen:** 4–5K Token je Eintrag. Bei 200K TPD und 50 % Anteil wären das rund 20–25 eingeordnete Einträge pro Tag. Was darüber liegt, wartet sichtbar als Rohfassung.

### 4.2 Schema (Skizze, `strict:true`, alle Felder Pflicht, optional als `null`)

```jsonc
{ "items": [{ "key":"i1", "sentenceIds":["s1","s2"], "label":"Wohin?"|null, "icon":"map-pin"|null /* Enum aus ~24 lucide-Namen */,
              "quotes":[{ "sentenceId":"s1", "text":"Vielleicht Portugal" }] /* ≤ 3, wörtlich */,
              "topic":{ "kind":"existing|new|none", "topicId":null, "newTopicKey":"t_reise" }, "continuesNoteId":null }],
  "newTopics": [{ "key":"t_reise", "title":"Auszeit" }],
  "structures": [{ "kind":"mindmap|comparison|flow", "topicId":null, "newTopicKey":"t_reise", "extendsStructureId":null,
                   "centerRef":"i1"|null, "memberRefs":["i2","n_17"],            // Ablauf: in genannter Reihenfolge
                   "options":[{ "label":"A", "sentenceId":"s5" }], "criteria":[{ "label":"Material" }],
                   "cells":[{ "option":0, "criterion":0, "sentenceId":"s5"|null, "text":"Papier"|null }],
                   "orderEvidenceSentenceIds":[] }],
  "relations": [{ "from":"i3", "to":"n_9", "reason":"…", "evidenceSentenceIds":["s4"] }] }   // ≤ 2
```

Das Modell erzeugt **nie** OpenUI Lang, keine Koordinaten und keinen Notiztext jenseits wörtlicher Zitate. Labels und Titel sind Deutungen und werden als solche dargestellt.

### 4.3 Lokale Prüfung

**Hart** (→ einmal 120B, danach Rohfassung):

- Schema verletzt oder `finish_reason=length`
- unbekannte oder doppelte Satz-IDs
- nicht **jeder** Inhaltssatz genau einmal abgedeckt (der erkannte Kommandosatz ausgenommen)
- Referenzen außerhalb des Kandidatensatzes, undefinierte `newTopicKey`
- Indizes außerhalb des gültigen Bereichs
- mehr als 40 Items

**Weich** (lokal herabstufen, Rest übernehmen):

| Problem | Folge |
|---|---|
| Zitat ist kein wörtlicher Teilstring (normalisiert: Groß-/Kleinschreibung, Leerraum, Endpunkt) **oder** `negationCount` weicht vom Satz ab | ganzer Satz statt Zitat |
| Label leer oder > 40 Zeichen | `null` (Anzeige: erstes Zitat) |
| neues Thema mit < 2 Gedanken | lose; gleichnamiges Thema bzw. Alias wird stattdessen genutzt |
| Mindmap ohne Zentrum oder mit < 3 Zweigen | Struktur entfällt, Gedanken bleiben Notizen im Thema |
| Vergleich mit < 2 Optionen, < 1 Kriterium oder < 2 belegten Zellen | Struktur entfällt |
| Vergleichszelle | muss wörtliches Zitat aus ihrem Satz sein; leere Zellen füllt **der Code** mit „Nicht genannt“ |
| Ablauf | nur mit ≥ 3 Gliedern **und** einem lokalen Reihenfolgesignal in den Belegsätzen (`zuerst|erst|dann|danach|anschließend|später|schließlich|zum Schluss|am Ende|erstens|zweitens|\d+\.`); sonst entfällt die Struktur |
| Beziehung | Endpunkte müssen leben, kein Grabstein-Paar, Begründung ≤ 120 Zeichen, Belege aus diesem Eintrag; sonst entfällt sie |

### 4.4 Bildbeschreibung (optional, kein Kernpfad)

- Modell `qwen/qwen3.8-27b` (Preview), standardmäßig aus.
- Bild vorher auf höchstens 1.568 px als JPEG verkleinern.
- Strict-Antwort `{caption ≤ 140, visibleText ≤ 400}`, gecacht je `sha256 + Analyseversion`.
- Höchstens 10 Bilder pro Tag.
- Anzeige als gestrichelte Ableitung „Bild zeigt: …“.
- Fließt nur mit eigener Einstellung in die Einordnung ein.

### 4.5 Qualitäts-Gate (vor „Struktur-Vorschläge standardmäßig an“, nicht vor dem Bau)

- Werkzeug `tools/notes-bench/` mit ≥ 40 synthetischen deutschen Notizen und Erwartungen.
- Der Key wird zur Laufzeit aus dem userData-Ordner gelesen, nie aus dem Repository.
- Gemessen werden:
  - Rate harter Fehler (20B und nach 120B)
  - Themen-Treffer
  - Strukturwahl
  - Token inklusive `cached_tokens`
  - Latenz
- Vorschlag für das Gate:
  - harte Fehler: höchstens 10 % mit 20B, höchstens 3 % nach dem 120B-Versuch
  - falsches Thema: höchstens 20 %
- Wird das Gate gerissen, bleibt v1 im Modus „nur Thema + Zitate“, also ohne Strukturen. Das ist ein Schalter, kein Umbau.

---

## 5. Board

### 5.1 React-Flow-Konfiguration (gegen die geprüften Standardwerte)

```tsx
<ReactFlow panOnScroll panOnScrollSpeed={1} panOnScrollMode="free" zoomOnPinch zoomOnScroll={false}
  zoomOnDoubleClick={false} panOnDrag selectionKeyCode="Shift" minZoom={0.1} maxZoom={2.5}
  deleteKeyCode={null} nodeDragThreshold={3} edgesReconnectable elevateEdgesOnSelect
  onlyRenderVisibleElements={nodes.length > 150} proOptions={{ hideAttribution: true }} … />
```

- **Ziehen:** Transient im Renderer (zustand ist bereits Abhängigkeit von React Flow); Commit erst bei `onNodeDragStop`/Resize-Ende. Keine IPC-Nachricht je Mausbewegung.
- **Themensprung:** `fitBounds(bounds,{duration:260,padding:0.12})`; jede Eingabe bricht die d3-Transition ab.
- **Windows-Pinch:** eigener Capture-Phase-`wheel`-Listener für `ctrlKey && !mac`, der `zoomTo` mit dem Mac-Faktor ruft. Ungetestet bis zum Windows-Test.
- **Fensterkürzel:** Das Notes-Fenster fängt per `before-input-event` ⌘0, ⌘+, ⌘−, ⌘Z, ⇧⌘Z und ⌘R ab, solange nicht im Textfeld bearbeitet wird, und gibt sie als Board-Befehl weiter. Das Standardmenü würde die Seite sonst zoomen oder neu laden.

### 5.2 Elemente

| Element | Knoten / Kante | Besitz | Darstellung |
|---|---|---|---|
| Sprachnotiz | `note` | KI/System, Text danach Nutzer | Papier, Wellen-Symbol, Uhrzeit, Label gedämpft + Icon, Text |
| Haftnotiz | `note` · Variante `sticky` | Nutzer | Gelb, ±2° rein dekorativ |
| freier Text | `text` | Nutzer | ohne Karte; **nur hier** Handschrift-Schrift |
| Bild | Chip in der Notiz; eigener `image`-Knoten nur beim Einfügen auf Leerfläche | – | 64-px-Vorschau, Großansicht |
| Thema | `topic`, z-Index −1, `dragHandle` = Titel; Rahmen = Mitglieder + 48 Rand (berechnet), gespeichert wird nur der Ursprung | KI/Nutzer | ruhige Fläche, Titel, Metazeile „3 Momente · heute“ |
| Mindmap | `hub` (Strukturtitel) + Mitglieder + Kanten `branch` | – | – |
| Vergleich | `comparison` (eine Tabelle, Zellen editierbar → Nutzer-Override) | – | „Nicht genannt“ gedämpft |
| Ablauf | Mitglieder als Variante `step` + Kanten `flow` (Pfeil) | – | – |
| Beziehung | Kante `relation`, gestrichelt; zwischen Themen als Chip, Linie erst bei Auswahl | – | – |
| Linie/Pfeil | Kante zwischen Elementen oder `point`-Knoten (12-px-Griff, nur bei Auswahl sichtbar) | Nutzer | Endpunkt ziehen = drehen/strecken (⇧ rastet 15°), auf Element fallen lassen = andocken, Linie ziehen = beide Punkte |

### 5.3 „Einmal platzieren“

- KI- und System-Commits legen Elemente mit `pos:null` und einem `slot` (Thema, Struktur, Reihenfolge) an.
- Das Board rendert sie unsichtbar zur Messung. Danach rechnet `layout.ts` deterministisch aus Slot, Messgröße und Hindernissen. Ergebnis ist **ein** `place`-Befehl mit der Bedingung `pos==null`.
- Platziertes bewegt sich nie wieder automatisch, mit genau einer Ausnahme: Bei Überlappung dürfen KI-Themenrahmen, die nicht vom Nutzer bewegt wurden, als Ganzes ausweichen (animiert). „Thema aufräumen“ gibt es nur als Nutzerbefehl, und es ist rücknehmbar.
- **Lose Sprachnotizen** landen im Bereich „Eingang“ links vom Ursprung. Themen sitzen in einem Raster aus Zellen à 1.400 × 1.000 in Erstellungsreihenfolge.
- **Langer Text:**
  - Breite: 320 bei Notizen, 260 bei Haftnotizen; die Höhe folgt dem Inhalt.
  - Ab etwa 1.200 Zeichen zeigt die Karte 12 Zeilen und „mehr“, das sich an Ort und Stelle aufklappt.
  - `nowheel` nur, wenn der Inhalt wirklich scrollt.
- **Detailstufen:**
  - ab 0,6: alles
  - 0,3–0,6: Label und 3 Zeilen
  - unter 0,3: Label, dazu Thementitel im Bildschirmraum
  - Hysterese, Größen bleiben gleich, kein Sprung.

### 5.4 Bedienung

- **Werkzeugleiste unten**, nur Icons mit Tooltip:
  - Auswahl `V`, Hand `H`, Notiz `N`, Text `T`, Linie/Pfeil `L`
  - Aufnehmen (gefüllt)
  - Rückgängig/Wiederholen
  - „73 %“-Menü
- **Kopfzeile:**
  - Marke
  - **Themen-Sprungleiste**: Chips auf derselben Fläche, keine Reiter; das aktive Thema liegt unter der Bildschirmmitte
  - Suche `⌘F` (lokal BM25, springt hin)
  - Eingang mit Zähler, Zuständen, „Erneut“ und „Einordnung zurücknehmen“
- **Kontextleiste** (`NodeToolbar`): Bearbeiten, Original, Kopieren, Duplizieren, Thema …, Darstellung, Entfernen.
  - Bei „Original“ ist ein entfernter Kommandosatz durchgestrichen sichtbar.
  - „Darstellung“ wechselt zwischen Notizen, Mindmap, Vergleich und Ablauf. Eine Nutzerwahl setzt `owner:user`.
- **Bearbeiten:**
  - Doppelklick oder Enter öffnet ein Textfeld vor Ort (`nodrag nowheel`).
  - Esc oder ⌘Enter übernimmt.
  - Tasten mit `isComposing` werden ignoriert (IME).
  - Reiner Text, kein Rich Text.
- **Kürzel:**

  | Kürzel | Wirkung |
  |---|---|
  | ⌘C | Klartext kopieren |
  | ⌘D | duplizieren |
  | ⌘V | Text bzw. Bild (Regeln aus dem Vor-Review, §3.9) |
  | ⌫ | Grabstein, inzidente Kanten entfallen mit; Rückgängig stellt beides wieder her |
  | `[` `]` | voriges/nächstes Thema |
  | ⇧1 / ⇧2 | alles / Auswahl zeigen |
  | ⌘0 | 100 % |
  | Leertaste + Ziehen | Hand |

- **Öffnen:**
  - Das Fenster wird beim ersten Öffnen erzeugt und beim Schließen nur ausgeblendet.
  - Ziel: warm ≤ 150 ms, kalt ≤ 800 ms.
  - `backgroundColor` passt zum Theme, damit nichts weiß aufblitzt.

### 5.5 OpenUI-Einbindung (Trennung von strict JSON)

- **Bibliothek:** `defineComponent` für `NoteBody`, `StickyBody`, `ComparisonTable`, `HubLabel`, `StepBody` und `ImageChip`.
  - Props sind nur IDs (Zod).
  - Die Daten kommen aus dem Store, wie im Prototyp über einen Context.
- **Compiler:**
  - Element → Mini-Programm, z. B. `root = ComparisonTable("st_7")`, gecacht nach ID und Art.
  - Unit-Test: `createParser(library)` meldet für jede Art null Fehler.
- **Renderer** je Knoten mit `isStreaming={false}` und `publishObservability={false}`, memoisiert. `generateSystemPrompt` wird nicht genutzt.
- **Performance-Gate (E2E)** bei 300 sichtbaren Knoten:
  - p95-Frame ≤ 20 ms bei 3 s synthetischem Pan auf Allans Mac
  - Öffnen (warm) ≤ 200 ms
- **Reißt das Gate**, rendert der Adapter `openui/render.tsx` **dieselben** Komponenten direkt. Das ist ein Schalter, kein Umbau. OpenUI ist damit kein Risiko für eine funktionierende App.

### 5.6 Visuelle Qualität bewahren (Regeln aus dem freigegebenen Entwurf)

1. **Typografie trägt.**
   - Label: 16 px, gedämpft, grünes Icon
   - Text: 19/1,55
   - Mindmap-Zentrum: 31/1,22
   - Tabelle: 17
   - Systemschrift, Tokens aus `style.css` des Prototyps bzw. `globals.css` (hell und dunkel über `light-dark()`)
2. **Herkunft ist Material.** Sprache auf Papier, Getipptes gelb, frei ohne Karte. **Handschrift nur für Nutzertext.** KI-Inhalt in Handschrift würde Deutung als eigene Notiz ausgeben.
3. **Gestrichelt = Deutung.** Das gilt für KI-Beziehungen und KI-Strukturrahmen. Vom Nutzer Gesetztes ist durchgezogen bzw. grün.
4. **Kürze ohne Erfindung.**
   - Den Kern tragen Labels und Titel, als Deutung gedämpft.
   - Der Körper zeigt wörtliche Zitate.
   - Der ganze Satz ist einen Klick entfernt („Original“).
   - Die Paraphrasen des Prototyps entfallen bewusst.
5. **Icons** wählt das Modell aus einer festen Liste (Enum, etwa 24). Fehlt die Wahl, gilt ein Standard je Art.
6. **Mischformen je Thema:** etwa eine Tabelle, eine lose Frage als Haftnotiz und eine Karte nebeneinander. Es gibt keinen Zwang, ein ganzes Thema in eine Form zu pressen.
7. **Ruhe:**
   - Punktraster 22 px, nur ab Zoom 0,5
   - Themen als weiche Flächen mit Quellstempel
   - keine Seitenleisten außer dem Eingang
8. **Bewegung:**
   - 190–330 ms mit `cubic-bezier(.3,.7,.4,1)`
   - FLIP nur für Systemplatzierungen und Themensprünge
   - `prefers-reduced-motion` → sofort
9. **Notes-Pille:**
   - Eigene Komponente mit `data-variant="notes"`, aufbauend auf den Tokens von `recording-pill.css`.
   - **Mint-Gold-Aura:** Conic-Gradient `--brand-mint` → `--brand-green-bright` → `--brand-beak`, Blur 6 px, Deckkraft ≤ 0,55, dreht sich in 6 s nur während der Aufnahme.
   - Inhalt: Timer und Kamera-Symbol.
   - Zustände: „Pausiert · Diktat“, „Gesichert ✓“ (1,2 s), „Gesichert · später“ (offline/kein Key).
   - Optional eine winzige Brille am p-Kopf nur während „ordnet ein“.
   - Position: eine Pillenhöhe **über** Echo, damit beide gleichzeitig sichtbar sind.

---

## 6. Nahtstellen in `electron-main.js`

Alle Eingriffe sind klein und liegen außerhalb der Harness-Bereiche, mit Ausnahme von Nr. 3.

1. **Kopf** (nach `:93`): `const { createNotes } = require('./notes');` und `const notesBridge = { dictationState() {}, meetingStarted() {} };`. Zusätzlich `protocol` in die Destrukturierung `:1–14`.
2. **Vor `ready`** (oberste Ebene im Primary-Block): `protocol.registerSchemesAsPrivileged([{ scheme:'paply-notes', privileges:{ standard:true, secure:true } }])`.
3. **`publishRecordingState()`** (`:1231–1233`): `notesBridge.dictationState(isRecording);`. Das ist die **einzige** Zeile im Diktatbereich und braucht den Harness-Stub (M2).
4. **`whenReady`, Meeting-Verdrahtung** (`:2566`): `showOverlay`-Hülle (M2).
5. **Nach `registerHotkey()`** (`:2585`):
   - `notes = createNotes({ … }); notes.start(); Object.assign(notesBridge, notes.bridge);`
   - Abhängigkeiten: `app`, `getStore`, `ipcMain`, `globalShortcut`, `BrowserWindow`, `protocol`, `screen`, `desktopCapturer`, `systemPreferences`, `net`, `nativeImage`, `platform`
   - Getter: `isDictating: () => isRecording || dictationJobs.pending().length > 0` und `isMeetingActive: () => !!meetingController?.getStatus().active`
   - `otherShortcuts: () => [currentShortcut≠'GLOBE', meetingEnabled && meetingAccelerator(meetingHotkey), Smart-Paste, Recovery, ...agentHotkeys, Beenden]` sowie `openSettings: createSettingsWindow`
6. **`updateTrayMenu()`** (`:1132–1153`): „Notes öffnen“ und „Notiz aufnehmen“, nur wenn Notes aktiv ist.
7. **Beenden:** `before-quit` → `notes.flush()`; `will-quit` (`:2610`) → `notes.shutdown()` (synchron, Aufnahme wird als `captured` abgeschlossen).
8. **Einstellungen:** `NotesSettings.tsx` in `Dashboard.tsx` und `SettingsApp.tsx`.
   - Inhalt: aktiv, zwei Kürzel mit Kollisionsanzeige, Bildschirmkontext (aus), Bildbeschreibung (aus), Budget unter „Erweitert“ und ein ehrlicher Satz dazu, was Groq sieht.
   - Ändert der Nutzer später das Diktat- oder ein Agent-Kürzel auf das Notes-Kürzel, schlägt dessen Registrierung mit der vorhandenen Meldung fehl, ohne Diktat-Änderung.

**Unverändert bleiben:**

- `settings:get/set` (`settings:set` ist ein Harness-Bereich)
- `recording:*`, `processAudioData`, `transcribeAudio`, `setupUioHookKeyUp`
- `dictation/*`, `meeting/*`, `RecordingPill.tsx`, `useDictationRecorder.ts`

---

## 7. Tests

Keiner der folgenden Tests existiert oder lief bisher. Gelaufen ist nur die bestehende Suite (529 grün).

### 7.1 Unit (Vitest, Node)

- **repo:**
  - Fehler-Injektion zwischen write, fsync und rename
  - kaputte `board.json` → `prev` → Backup
  - `schemaVersion`
  - Windows EPERM (Mock), Debounce/Flush
  - Schreibzeit bei 5.000 Notizen messen
- **capture:**
  - `seq`, Pause und `epoch`
  - Anhängen und fsync-Takt
  - 30-min-Grenze, volle Platte
  - Wiederanlauf mit ungerader Byte-Zahl
- **Vorrang:**
  - Start abgelehnt bei laufendem Diktat bzw. Meeting
  - `dictationState(true)` verwirft Pakete; alte Epoche nach `resume` verworfen
  - `meetingStarted` beendet und sichert
- **hotkeys:**
  - Kollisionen gegen alle Listen (darwin und win32)
  - fehlgeschlagener Wechsel behält das alte Kürzel
  - Notes aus → abgemeldet
- **ipc:**
  - jeder Kanal lehnt fremde Absender ab
  - Größengrenzen
  - Protokoll-Regex (`..`, Nicht-Hex, fremde Endungen)
- **queue/groq/ledger:**
  - alle Fehlerklassen, `retry-after`, offline, kein Key, 401-Pause
  - Reservierung Minute und Tag
  - Diktat-Vorrang
  - ein Netz-Job
  - Abbruch beim Löschen
  - Neustart-Rückfälle
- **stt:**
  - WAV-Stücke ≤ 10 min an leisen Stellen
  - Stille überspringen (Pegel aus PCM im Main)
  - „Vielen Dank“-Filter (`filterTranscription` nur lesend)
  - Eigene Begriffe
  - Satztrennung mit „z. B.“, „ca.“, „Dr.“ und „3.5“
- **plan:**
  - jede harte und weiche Regel
  - Abdeckung, Zitat-Teilstring, Verneinung
  - Strukturregeln, Beziehungen, Kommandosatz
  - es gibt kein Feld zum Verwerfen
- **commands:**
  - Claims, Grabsteine
  - Rohfassung unberührt bzw. berührt
  - Bearbeiten oder Löschen während eines laufenden Jobs
  - KI-Gruppe teilweise zurücknehmen
  - Undo/Redo zwischen KI-Commits
  - Idempotenz
- **layout (TS):**
  - deterministisch, einmal platzieren
  - Hindernisse, Rahmen ohne Überlappung
  - LOD-Hysterese
  - zweites Öffnen erzeugt **null** Positionsänderungen
- **openui:** alle Arten parsen fehlerfrei, unbekannte Art wird abgelehnt.
- **settings-sync:** beide Ansichten binden `NotesSettings` ein.

### 7.2 Regression

- Die 529 bestehenden Tests bleiben grün.
- Harness-Stub und neuer Haken-Test laufen für darwin und win32.
- Ein Quelltext-Wächter prüft, dass `notes/**` weder `recording:audio` noch `addToHistory`, `autopasteText` oder `audio-backups` referenziert.

### 7.3 E2E

**Aufbau** (`playwright-core` `_electron`, Technik aus dem Gedächtnis-Eintrag):

- `PAPLY_USER_DATA` zeigt auf einen Temp-Ordner, Allan wird vorher gesagt, dass die Test-App leer aussieht.
- Fake-WAV als Mikrofon.
- Ein **Fake-Groq-Server**, dessen URL der Main nur annimmt, wenn `PAPLY_USER_DATA` gesetzt ist.

**Szenarien:**

1. Leerer Store → zwei Aufnahmen mit einem bzw. zwei Themen → Rohfassung → Einordnung, die ganze Zeit **bei geschlossenem Board**. Danach öffnen: platziert. Zoomen und Bearbeiten lösen **keinen** Request aus.
2. **Kill-Test:** `SIGKILL` nach 5 s Aufnahme → Neustart → ≥ 4 s Ton, Zustand `captured`, wird verarbeitet.
3. **Diktat während Notes:** `transcription:start`/`stop` mitten in der Notes-Aufnahme.
   - `droppedPackets > 0`, Epoche erhöht
   - Diktat-Historie unverändert (`autopaste:false`)
   - Notes-Text enthält den Diktatsatz nicht (unterschiedliche Fake-WAVs bzw. Fake-STT nach Bytes)
4. Offline, 429, 401, kein Key, kaputtes JSON → 120B → Rohfassung.
5. **Stale:** Rohfassung löschen, während die Fake-Antwort wartet → bleibt gelöscht.
6. **Bedienung:**
   - Ziehen → die Kanten-Endpunkte folgen
   - Größe ändern
   - Linien-Endpunkt ziehen und andocken
   - Bearbeiten mit Rückgängig/Wiederholen, Löschen mit Rückgängig
   - Text- und Bild-Paste, Kopieren
   - Themensprung
   - ⌘0, ⌘+ und ⌘− zoomen nicht die Seite
7. Performance-Gate (§5.5).
8. Gepackte App über `electron-builder --mac --arm64 --dir`: Notes-Fenster öffnet (prüft die `files`-Whitelist).
9. **Sicherheit:**
   - `notes:*` aus dem Dashboard abgelehnt
   - im Notes-Fenster `window.electronAPI === undefined`
   - CSP blockiert `fetch`

### 7.4 Mit Allan (Mac, Test-App, echter Key aus den Einstellungen)

- Trackpad-Gefühl
- Pille und Aura
- 5–10 echte deutsche Notizen
- Bildschirmrecht und `setContentProtection` unter macOS 15 (ungeprüft)
- Kamera-Klick in der nicht fokussierbaren Pille
- Cmd+X in der echten App unverändert

### 7.5 Vor einem späteren Release (nicht beauftragt)

- Qualitäts-Gate aus §4.5
- Windows-Rauchtest beim Freund oder in einer VM: Pinch, Pille, Kürzel

---

## 8. Akzeptable Grenzen von v1

- Tippen-Start/-Stopp, kein Halten-zum-Sprechen.
- Keine OCR; Bildtext nur über die optionale Bildbeschreibung.
- Reiner Text in Notizen; Rückgängig je Sitzung.
- Ein Fenster, ein Gerät, keine Synchronisation.
- Das Notes-Budget ist lokal; andere Geräte mit demselben Key werden nicht koordiniert.
- BM25 statt Embeddings; Synonyme werden teils verfehlt. Das Modell sieht deshalb immer alle Thementitel samt Aliassen.
- Kartentext aus Zitaten, also weniger knapp als im Entwurf.
- Freie Linien sind gerade (Kanten zwischen Elementen auch als Bézier).
- Keine automatische Gesamt-Neuordnung, nur „Thema aufräumen“ von Hand.
- Ein laufendes Meeting blockiert den Notes-Start. Höchstens 30 min je Aufnahme.
- Windows-Pinch-Korrektur und Pillen-Klick bleiben bis zum Windows-Test ungeprüft.

## 9. Optional (kein Blocker)

- „Neu“-Rundgang. Für v1 genügen Neu-Markierungen und eine Sprungliste im Eingang.
- Brille an der Pille; Nachhören ab Satz.
- Lokale OCR (Swift-Helfer, Muster Globe-Listener).
- Verdichtungsvorschläge; Datei-Drop; Markdown-Export.

## 10. Arbeitspakete für parallele Umsetzung

1. **A (zuerst, klein):** `notes/contracts.js` mit Entitäten, Ops, Payload-Validatoren und IPC-Tabelle.
2. **B Main-Kern:** repo, commands mit Claims und Undo, IPC und Preloads, Protokoll, Einstellungen.
3. **C Aufnahme:** Pille und Recorder, Sink, Vorrang-Haken, Kürzel, Bildschirm (opt-in), Kamera.
4. **D Pipeline:** groq, ledger, queue, stt, plan mit Validator, Bildbeschreibung.
5. **E Board:** React Flow, Knoten und Kanten, `layout.ts`, Werkzeug- und Kontextleiste, Paste, OpenUI-Bibliothek und Compiler, Detailstufen, Notes-Pillen-Optik.
6. **F Tests und E2E** als unabhängiger Prüfer: Fake-Groq, Kill-Test, Performance-Gate.

Ablauf: A → B, C, D, E parallel → Integration → F → abschließendes Opus-Review → Befunde beheben → Übergabe der Test-App.

**Annahmen, die der Bau setzt** (änderbar, nicht blockierend):

- **Kürzel:** Mac ⌘Y (Aufnahme, nach Allans Beispiel; überdeckt Quick Look im Finder und den Safari-Verlauf) und ⌥⌘Y (Öffnen). Windows Strg+Alt+Y bzw. Strg+Alt+Umschalt+Y, weil Strg+Y „Wiederholen“ ist.
- **Standardzustand:** Notes ist an. Bei einer Kollision wird das Kürzel nicht registriert, und Notes zeigt einen Hinweis.
- **Aufbewahrung:** Ton 7 Tage nach erfolgreicher Verschriftung (wie bei Meetings), Transkript dauerhaft.
