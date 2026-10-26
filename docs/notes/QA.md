# Paply Notes — unabhängige QA

26.10.2026 · Agent/Task `/root/notes_independent_qa` · Plan: `TESTPLAN.md`.

Die unabhängige Prüfung verwendet die echte Electron-App auf diesem Mac, echte Renderer-/Preload-/IPC-/Store-Pfade und echte Pointer-/Zwischenablageaktionen. Die Modellantworten sind kontrollierte synthetische Fixtures. Es wurden weder produktive Profile noch echte API-Keys verwendet. App-Fixes stammen vom Hauptagenten; dieser QA-Agent änderte ausschließlich eigene Tests, Werkzeuge und diesen Bericht.

## Ergebnisstand

Fünf Fehler wurden unabhängig gefunden, an den Hauptagenten zurückgegeben und nach deren Korrektur nachgeprüft. Q1–Q4 wurden praktisch in Electron nachgeprüft; Q5 durch eine eigene Regression. In den unten ausgeführten Fällen bleibt kein offener Befund. Die Grenzen der Abnahme stehen ausdrücklich unten. Es wurde kein Release ausgelöst.

| ID | Befund und Reproduktion | Nachprüfung |
| --- | --- | --- |
| Q1 | Text mit echtem ⌘V einfügen: Quelle wurde gespeichert und Entry später `complete`, aber kein Boardobjekt und kein Modellrequest. `prepare()` hielt einen neu erzeugten Node wegen seines anfänglichen User-Owners für bereits manuell bearbeitet. | Korrigiert. Echter Paste erzeugt sofort eine vollständige Rohnotiz und erreicht die Planpipeline. Eigene Regression prüft Sichtbarkeit und Original. |
| Q2 | Nach erstmaligem Öffnen des Notes-Fensters hing `app.quit()` über 60 Sekunden. Der Close-Handler verhinderte Quit, während der dafür nötige `closing`-Status erst in `will-quit` gesetzt wurde. | Korrigiert. Neustart mit Fix: geöffnetes Board → reguläres Quit in 294 ms. Folgende Testprofile konnten ebenfalls regulär beendet werden. |
| Q3 | Freien Pfeil zeichnen, Endpunkt genau im sichtbaren Kreismittelpunkt ziehen: nichts bewegte sich. Unsichtbare React-Flow-Handles fingen die Eingabe ab. Ziehen am äußersten Rand funktionierte. | Korrigiert. Zentraler Pointer-Drag verändert jetzt live die Punktposition und persistiert sie. |
| Q4 | Karte nach unten vergrößern: gespeicherte/React-Flow-Höhe 234 px, sichtbare Papierfläche blieb kleiner. Zwei OpenUI-Wrapper unterbrachen die Höhenkette. | Korrigiert. Bei 89 % Zoom sind Papier und Node jeweils 208,30 Bildschirm-Pixel hoch. |
| Q5 | `capture.start()` wartet auf ein ladendes Recorderfenster; sofort `stop()`; Fenster wird bereit: Ereignisfolge war `stop, start`. Ein erster Chunk konnte danach den Stop-Timeout entfernen. | Korrigiert. Eigener Test `stop during a slow recorder-window load cannot restart the microphone` reproduzierte den Fehler vor der Korrektur und besteht jetzt. |

## Praktisch bestandene Fälle

- **Leerstart:** neuer temporärer Datenordner, leere `nodes/edges/topics/claims`, keine Quellen und keine Beispieldaten. F18/F19/F20 waren nativ registriert. Dashboard, Notes-Fenster und getrennte Pille wurden tatsächlich geladen.
- **Audio bis gemischtem Board:** lokaler TTS-Testton als Fake-Mikrofon → `getUserMedia` → AudioWorklet → bestätigte PCM-Schreibvorgänge → wirklicher Multipart-WAV-Upload. Ein 6.117-ms-Lauf ergab 195.798 Byte WAV mit 16 kHz. Danach genau ein Whisper- und ein Planrequest; zehn synthetische Sätze wurden in drei Themen als Karten, freier Text, Haftnotiz, Mindmap-Zentrum, Vergleichstabelle und Ablaufkanten übernommen. Während der Verarbeitung war das Board versteckt.
- **Live-Drag:** mehrere echte `mouse.move/down/move/up`-Schritte. Schon vor Loslassen änderten sich Node- und Kanten-Endpunkt gemeinsam um 35/26 px, später um 85/61 px. Bildschirmkoordinaten wurden aus SVG-Pfad plus CTM gemessen; keine Store-Koordinaten wurden gesetzt, um diesen Nachweis zu erzeugen.
- **Bearbeitung:** Breite und Höhe vergrößern, Notiztext und Tabellenzelle bearbeiten, unverändertes Original öffnen, Kopieren in die echte macOS-Zwischenablage, Delete mit Entfernung inzidenter Kanten, Undo mit Wiederherstellung der Kanten und Redo. Themensprünge und Pan funktionieren auf derselben Fläche. Diese Bedienungen lösten keine zusätzlichen Modellrequests aus.
- **Freie Kanten:** Pfeil durch Ziehen zeichnen, Endpunkte bewegen, an einer bestehenden Karte andocken. Dabei wurde der freie Punkt entfernt und die Kante auf den Zielnode umgestellt. Der zentrale Endpunktgriff wurde nach Q3 erneut geprüft.
- **Paste und Anhänge:** synthetischer PNG-Inhalt über die echte Zwischenablage und ⌘V erzeugte ein Bildobjekt. Text-Paste wurde ebenso über den normalen Paste-Event-Pfad geprüft. Bildbytes, Referenz und Thumbnail überlebten den Neustart; das geladene Thumbnail war 240 px breit.
- **Stale Edit/Delete:** Fake-Planantwort zurückhalten; Rohnotiz über die UI manuell bearbeiten bzw. löschen; Antwort freigeben. Die Bearbeitung bleibt erhalten, gelöschte Notizen kommen nicht zurück. Das Original bleibt auf Platte. Zusätzlich bestehen unabhängige Unit-Regressionen für beide Fälle.
- **Persistenz:** Nodes, Kanten, editierte Texte/Zellen, Größen, Positionen und Bildreferenz nach Prozessneustart identisch. Die zuletzt auf Platte gespeicherte Pan-/Zoomansicht wurde wiederhergestellt. Ein anfänglicher Vergleich mit einem vor Ablauf des Viewport-Debounce aufgenommenen Snapshot wurde als Harness-Timing korrigiert, nicht als Appfehler gezählt.
- **Aufnahme-Recovery:** bei verstecktem Board nach 5,5 s bestätigtem PCM (`176.000` Byte) den eigenen Electron-Prozess mit SIGKILL beenden. Neustart → Quelle mit 5.500 ms wiederhergestellt → WAV/Whisper/Plan → `complete`, bevor überhaupt wieder ein Boardfenster geöffnet wurde. Playwrights drei Hintergrund-Throttling-Abschaltungen waren für diesen Lauf vor App-Ready entfernt und per `hasSwitch` als `false` bestätigt.
- **Wartender Planjob nach Absturz:** einen normalen Text-Paste bis `structuring` verarbeiten, Modellantwort zurückhalten und den eigenen Prozess mit SIGKILL beenden. Neustart desselben Profils → Job erreicht nach etwa 63,7 s `complete` mit `partsDone:1`; Original unverändert und währenddessen kein Boardfenster geöffnet. Die konservative Budgetreservierung vor dem Absturz blieb erhalten und erklärte die Wartezeit bis zur nächsten Minute.
- **Diktat-Vorrang:** laufende Notes-Aufnahme durch den bestehenden Dashboard-Diktatweg pausieren. Epoche 2, Meldung „Pausiert · Diktat“, PCM-Datei wächst während Diktat nicht. Nach Diktat-Ende Epoche 3 und PCM wächst erneut. Umgekehrt verhindert laufendes Diktat den Notes-Start mit „Diktat läuft“. Die isolierte Diktathistorie enthielt den synthetischen Diktattext. Für diesen Test war auch der Diktat-Fetch im Main-Prozess strikt gemockt; es ging kein Request an echtes Groq.
- **Settings und Konflikte:** separates Settings-Fenster bietet beide Kürzel. Ein Konflikt mit einem Paply-Kürzel sowie eine gezielt bereits registrierte OS-Kombination scheitern mit verständlicher Meldung und behalten alte Einstellung und F18-Registrierung. Erfolgreiche Änderung wird zurückgemeldet; Änderung über das Dashboard-Settings-API synchronisiert das separate Fenster. Die Dashboard-Notes-Schaltfläche öffnet dieselbe Notes-Instanz.
- **Fehlergrenzen:** 401 erzeugt einen Request, danach `waiting_key` und sichtbaren Rohtext. Ungültige Pläne führen zu einem 20B- und einem 120B-Versuch, danach vollständiger Rohtext mit erklärender Meldung. Bei 429 bleibt der Rohtext erhalten; die konservativ beibehaltene Reservierung kann den nächsten Versuch zusätzlich bis zum Minutenbudget verschieben. Bei 5.000-Tokenbudget und 6.047 Zeichen Quelltext: null Requests, `waiting_budget`, Original vollständig gesichert.
- **Normale Sandbox:** vor Verwendung des Audio-Testworkarounds separat geprüft. Notes-Renderer hat weder `window.electronAPI` noch `require`, der Snapshot enthält keinen Dummy-Key. CSP `connect-src 'none'` blockiert einen Fetch. Ein fremdes sandboxed BrowserWindow mit eigenem Probe-Preload erhält bei `notes:board:get` „Unzulässiger Notes-Absender“. Board und Capture: `sandbox:true`, `nodeIntegration:false`, `contextIsolation:true`.
- **Reduced Motion, begrenzte Prüfung:** im Pill-Renderer `prefers-reduced-motion: reduce` emuliert; Mediaquery war aktiv und berechnetes `animation-name` der Aura war `none`. Das belegt die CSS-Abschaltung in diesem Zustand, keine vollständige Prüfung sämtlicher Aufnahmezustände.

## Leistung

Eigenes leeres Performanceprofil, 300 synthetische Nodes über gültige User-Commands erstellt, drei Darstellungsformen. Beim Messbeginn waren **300 Nodes tatsächlich im DOM**. Drei Sekunden synthetischer Wheel-Pan bei Gesamtansicht:

| Messung | Ergebnis | Gate |
| --- | ---: | ---: |
| Frame-Abstände, p95 | 16,8 ms | ≤ 20 ms |
| Größter gemessener Abstand | 18,1 ms | dokumentiert |
| Gemessene Frame-Abstände | 186 | dokumentiert |
| Warmes Wiederöffnen inkl. nächstem Frame | 34 ms | ≤ 200 ms |

OpenUI war aktiv. Die Messung ist eine konkrete Momentaufnahme auf diesem Mac, kein plattformübergreifender Benchmark. Die Performance-Fixture bleibt ausschließlich in ihrem QA-Profil.

## Werkzeuge und Belege

Eigene Dateien: `electron-menubar/notes/independent.qa.test.js` sowie `electron-menubar/tools/notes-qa/{harness,background-bootstrap,canvas,performance,arbitration}.cjs`. Die Baseline wurde nicht unnötig erneut ausgeführt; vollständige Suite, TypeScript und Build verantwortet der Hauptagent.

Artefaktwurzel dieses Laufs:

`/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-qa-fpeetW/`

Visuell tatsächlich geöffnet/geprüft: `01-empty.png`, `02-pill.png`, `03-mixed.png`, `05-edited-resized.png`, `09-image-paste.png`, `10-final-topic.png`, `performance-300.png`. `04-live-drag.png` dokumentiert gedrückte Maus; `08-zuhause.png` die lesbare gemischte Themenansicht. `05-edited-resized.png` stammt vor Q4 und ist daher Fehlerbeleg, kein finaler Höhennachweis. `10-final-topic.png` zeigt die abschließende Themenansicht nach den Fixes; die bewusst manuell verschobene Karte überlappt dort ein anderes Objekt. `results.json`, `main.log`, Quellen/Boarddateien in den isolierten Profilen und `before-restart.json` ergänzen die UI-Beweise. Nur synthetische Inhalte sind enthalten.

## Ehrliche Grenzen

- Die unabhängige Runde bewertet keine echte Groq-Modellqualität, Transkriptionsgenauigkeit oder realen Providerverbrauch. Ein konformer Mock belegt die Verkabelung, nicht, dass echte Modelle zuverlässig passende Strukturen wählen. Live-Tests des Hauptagenten sind gesonderte Evidenz.
- Auf diesem Mac konnte Chromium die WAV-Datei im normalen Audio-Sandboxprozess nicht lesen (`simple_sources.cc`). Auch eine normalisierte WAV änderte dies nicht. Die Audioläufe verwendeten deshalb ausschließlich in der isolierten QA-Instanz `--no-sandbox`; die oben genannte IPC-/CSP-Prüfung lief vorher ohne diesen Schalter. Kein Produktcode deaktiviert deswegen die Sandbox.
- Native Hotkeyregistrierung ist belegt, tatsächliche globale F18/F19-Tastenauslösung nicht: System-Events-Automation hing, und ein alternativer synthetischer Native-Key-Versuch löste keine Aufnahme aus. Die blockierte AppleScript-Instanz wurde beendet. Es wurden keine Rechte umgangen. Physisches Cmd+X und echte Trackpad-Pinch-Gesten sind dadurch ebenfalls nicht vollständig abgenommen.
- Keine echte Mikrofonhardware, Mikrofon-TCC-Dialoge, Bildschirmaufnahme-/Kameraberechtigungen oder Systemaudio-Meetingaufnahme wurden geprüft. Der Nutzerbildschirm wurde nicht als Testinhalt aufgenommen. Meeting-Arbitrierung und weitere Sender-/Payloadgrenzen benötigen die separaten Unit-/Integrationstests; hier ist kein vollständiger Security-Audit behauptet.
- Windows wurde nicht ausgeführt. Die gepackte App wird in einer gesonderten Smoke-Runde des Hauptagenten geprüft. Reduced Motion in sämtlichen Zuständen, Long-Text/IME-Details und sämtliche 16 Planfälle sind nicht pauschal als vollständig bestanden zu verstehen; oben stehen die tatsächlich ausgeführten Beweise.
- Nach Abschluss dieser praktischen Runde meldete der Hauptagent weitere Härtungen für Diskfehler beim Capture, den Vision-JSON-Modus und das Erfassen bereits registrierter Notes-Kürzel in den Einstellungen. Diese letzten Änderungen wurden in dieser Runde nicht erneut praktisch geprüft; deren Regressionen und Paketprüfung verantwortet der Hauptagent.

## Abschlussnotiz

Der abschließende unabhängige Nachlauf `npx vitest run notes/independent.qa.test.js --reporter=dot` bestand mit **4/4 Tests** in einer Datei (526 ms Gesamtdauer). Syntaxprüfungen der eigenen QA-Werkzeuge und `git diff --check` bestanden. Der separate Neustart eines wartenden Planjobs ist oben dokumentiert. Alle eigenen Electron-Instanzen, der interaktive Harness und der Loopback-Server wurden beendet; die Prozessprüfung fand keine verbliebene Electron-Instanz mit dem QA-Profilpfad. Der Hauptagent kann die gesonderte Paketprüfung übernehmen.

## Begrenzter Nachtrag nach MacBook-Nutzerbefund: Pille und lokale Eingabegrenze

26.10.2026, unabhängige lokale Prüfung auf dem Mac mini; kein Zugriff auf das Nutzer-MacBook. Unverändertes Übergabepaket `dist/notes-test/mac-arm64/paply.app`, `app.asar` SHA-256 `7c410e6a1477dd7cd0c60461da067501b2df9651001317976df955d246479ebe`. Frisches temporäres Profil, Dummy-Key, Loopback-Mock, normale Sandbox und ausschließlich Chromiums synthetisches Audiogerät. Keine Appdatei geändert, keine Analyse menschlicher Aufnahmen.

**Einmaliger Start über das Board-Mikrofon zeigte die Pille korrekt.** Vor dem Start war das vorgeladene native Fenster verborgen. Der Renderer hatte bereits `opacity:1`, `transform:none`, keine laufende Eingangsanimation; die Animation hielt die Pille somit nicht dauerhaft unsichtbar. Nach Start: Electron `isVisible:true`, `opacity:1`, `isVisibleOnAllWorkspaces:true`, `isAlwaysOnTop:true`, Bounds `(790,864,340,90)` vollständig innerhalb der aktuellen WorkArea `(0,25,1920,999)`.

Eine zusätzliche native CoreGraphics-Abfrage, ausschließlich auf den PID der Test-App gefiltert, bestätigte für dasselbe Fenster 6009 `kCGWindowIsOnscreen:true`, Alpha 1 und Layer 1000. Der eigene Pillen-Screenshot wurde visuell geprüft: Paply-Zeichen, „Gedanke“, Timer, Kamera und Stop sichtbar. Stop per Pillenbutton beendete die Aufnahme; anschließend verbarg sich das Fenster regulär. Mehrere Displays, tatsächliche Spaces-Wechsel und menschlich wahrgenommene Sichtbarkeit auf dem MacBook sind damit nicht geprüft.

Für den begrenzt angefragten deutschen Hotkey-Vergleich wurde nur `openHotkey=Command+Alt+Y` über das reguläre Dashboard-Settings-API eingestellt; Capture blieb F18. Deutsches Layout lokal bestätigt. Registrierung erfolgreich, Warnung leer, `isRegistered(Command+Alt+Y)=true`, Z=false. Der anschließende `osascript`-Versuch für den physischen Keycode 6 hing; `CGPreflightPostEventAccess()` meldete `false`. Der hängende Prozess wurde beendet, weitere Tastensimulation unterlassen und der Testwert auf F19 zurückgesetzt. **Kein lokaler Y/Z-Auslösenachweis und insbesondere kein negatives Trigger-Ergebnis werden daraus behauptet.** Die vom Nutzer unabhängig bestätigte Z-Reaktion auf dem MacBook untersucht der Hauptagent gesondert.

Begrenzte Empfehlung: tatsächlichen Hotkey→Capture-Aufruf und layoutgerechte Notes-Anzeige korrigieren; die Pillen-CSS-/Spaces-Logik aufgrund dieses Laufs unverändert lassen. Artefakte unter `/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-packaged-qa-ohN1B7/`, insbesondere `pill-recording.png` und `results.json`. Eigene Appinstanz, Harness, Loopback-Server und hängender AppleScript-Prozess sind beendet.

## Gezielter Paketnachtest notes.2: deutsche Standardkürzel und eigene Belegung

26.10.2026 · **Beide Fälle bestanden.** Tatsächliches Paket `dist/notes-test-next/mac-arm64/paply.app`, Version `1.15.0-notes.2`, `app.isPackaged:true`. `app.asar` SHA-256 vor/nach identisch: `0ae8d939b1a9b1a6d2f04499268d49ecb809d9aeac10ec29c271b75df566ff85`. Eingebauter nativer Helper `Contents/Resources/bin/macos-notes-keymap`: SHA-256 `4b5c21f4201bea5c6c9f64e5f34a3b3d8b66c037b62be96cc616dbba56f49e61`; tatsächlicher Aufruf lieferte unter deutschem Layout `Y→Z`, `Z→Y`.

| Isoliertes Profil | Tatsächliche Registrierung und gespeicherte Werte | Anzeige in der echten App |
| --- | --- | --- |
| Frisch, **ohne** `notesSettings` in `config.json` | `Command+Z` und `Command+Alt+Z` registriert; jeweilige Y-Gegenstücke nicht registriert. Warnung leer. Preferences enthalten echte deutsche Keymap. | Leeres Board: `⌘ Y`. Separate Notes-Einstellungen: `⌘ Y` / `⌘ ⌥ Y`. |
| Bereits gespeicherte eigene physische Belegung `Command+Y` / `Command+Alt+Y` | Beide unverändert aus der vorhandenen Profilkonfiguration übernommen, registriert und auf Disk erhalten; jeweilige Z-Gegenstücke nicht registriert. Warnung leer. | Leeres Board: `⌘ Z`. Separate Notes-Einstellungen: `⌘ Z` / `⌘ ⌥ Z`. Die vorhandene Belegung wird damit korrekt beschriftet, ohne sie zu verschieben. |

DOM-Werte und tatsächliche Main-Registrierung wurden unabhängig verglichen. Default-EmptyBoard sowie beide Settings-Screenshots wurden visuell geöffnet. Eine einzelne optionale Warmopen-Messung vom Dashboard-IPC-Aufruf bis zu zwei Board-Animationsframes ergab **89,8 ms**; kein allgemeiner Benchmark.

Nur temporäre Testprofile/Dummy-Key/Loopback, keine Aufnahme, **null STT-/Planrequests**, keine native Tastensimulation und kein Zugriff aufs Nutzer-MacBook. Tatsächliches globales Auslösen auf der Nutzertastatur ist daher nicht Teil dieses Nachtests; der vorangegangene Nutzerbefund zur Z-Taste ist gesonderte Evidenz. Keine breite Suite erneut ausgeführt und keine Appdateien geändert. `src/lib/shortcut.ts` und Diktat hatten bei der begrenzten Codeprüfung keinen Diff.

Werkzeug: `electron-menubar/tools/notes-qa/keymap-cases.cjs` mit vorhandenem Paket-Harness. Artefakte: `/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-packaged-qa-dBwxPW/` (`results.json`, `keymap-fresh-empty.png`, `keymap-fresh-settings.png`, `keymap-custom-empty.png`, `keymap-custom-settings.png`). Eigene Paketinstanzen, Harness und Loopback-Server regulär beendet; abschließende Prozesssuche ohne Treffer. Syntaxprüfung und `git diff --check` bestanden.

## Gezielte Releasevorprüfung: natives macOS-Beenden

26.10.2026 · **Fehler im unveränderten notes.2-Paket bestätigt; kleinste Scheduling-Korrektur experimentell bestätigt.** Geprüft `dist/notes-test/mac-arm64/paply.app`, Version `1.15.0-notes.2`, `app.asar` SHA-256 `0ae8d939b1a9b1a6d2f04499268d49ecb809d9aeac10ec29c271b75df566ff85`. Jeweils frisches isoliertes Profil, leeres geöffnetes Notes-Board, keine Aufnahme, keine OS-Tastensimulation, null Netzwerkrequests.

| Beenden-Pfad | Beobachtung am tatsächlichen Prozess |
| --- | --- |
| Einmaliges `app.quit()` im Main-Prozess | Erstes `before-quit` verhindert, zweites nach 1 ms nicht verhindert; `will-quit`/`quit` nach etwa 550 ms. Prozess beendet. |
| Einmaliges natives `NSRunningApplication(processIdentifier: PID).terminate()` | Nativer Aufruf meldet `true`. Erstes `before-quit` verhindert, zweites nach 1 ms nicht verhindert. Danach kein `will-quit`/`quit`; Prozess blieb auch nach rund 61 s bestehen. Zweiter gezielter nativer `terminate()` beendete ihn mit Exitcode 0. |
| Gleicher nativer Aufruf, frische Instanz, **nur temporärer QA-Wrapper** `app.quit = () => setImmediate(originalQuit)` | Ein einziger nativer `terminate()` genügte. `will-quit`/`quit` nach 536 ms, Exitcode 0, PID verschwunden. |

Der Wrapper änderte ausschließlich den Testprozess; keine Appdatei wurde durch QA geändert. Das belegt den Unterschied zwischen normalem JS-Quit und dem nativen macOS-Dispatch sowie die Wirkung des nächsten Event-Loop-Durchlaufs. Empfehlung an den Hauptagenten: nach abgeschlossenem Notes-Flush `notesQuitReady = true` setzen und `app.quit()` über `setImmediate` ausführen. **Vor Tagging bleibt derselbe Einmal-Terminate-Test am tatsächlich korrigierten Releasepaket erforderlich.**

Artefakte: `/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-packaged-qa-FsdvtR/`, insbesondere `main.log` mit Lifecycle-Zeitstempeln und `results.json`. Kein Prozess-Exit wurde durch Playwright `close`, `app.exit`, Force-Terminate oder Kill erzwungen. Erst nach beobachtetem Prozessende wurde die tote Appreferenz entfernt und der Harness/Mock-Server beendet. Abschließende Prozesssuche ohne Treffer.

### Releasepaket 1.15.0: native Quit-Korrektur bestätigt

26.10.2026 · **Bestanden am echten korrigierten Paket, ohne Wrapper.** `dist/release-candidate/mac-arm64/paply.app`, tatsächliche Version `1.15.0`, `app.isPackaged:true`; `app.asar` SHA-256 **`9d961ce553e286634c99fa602ed01d963e80ccac245dbcf5bd8892c34ea736e2`**. Frisches isoliertes Dummy-Profil, leeres geöffnetes Notes-Board. Ein einziger gezielter `NSRunningApplication(processIdentifier:67340).terminate()` meldete `true`; `will-quit`/`quit` folgten nach **530 ms**, Prozess endete mit **Exitcode 0**, PID verschwunden. Kein zweiter Quit, kein Wrapper, kein Playwright-close, kein Kill. Keine Aufnahme, keine Tastensimulation, null Requests. Damit ist das zuvor offene native Quit-Gate für diesen Releasekandidaten erfüllt.

Artefakte: `/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-packaged-qa-hf6VPI/` (`main.log`, `results.json`). Nach dem belegten Prozessende wurden nur Harness und Loopback-Server geschlossen. Keine zusätzlichen Funktionsprüfungen oder Appänderungen durch QA.

Übergabe: Dieses unveränderte notes.2-Paket liegt anschließend unter `dist/notes-test`; beide Hashes wurden auch nach der Übertragung aufs MacBook bestätigt. Dort gestartet unter `~/Applications/Paply-Notes-Test`, vorhandenes Notes-Profil erhalten.
