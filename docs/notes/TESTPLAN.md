# Paply Notes — unabhängiger Abnahmeplan

Stand: 26.10.2026. Vorbereitungsrunde durch Agent `/root/notes_independent_qa`, vor Beginn der Implementierung. Dies ist ein Prüfplan, kein bestandener Testbericht. Grundlage: `IMPLEMENTIERUNG.md`, Projektregeln und `docs/prototypes/openui-notes/`.

Die Baseline wurde bereits vom Hauptagenten geprüft: 529 Tests grün, Vite-Build grün, fünf bestehende TypeScript-Fehler in `Dashboard.tsx`. Diese Runde wiederholt sie nicht. Es wurden keine App-Dateien geändert, Abhängigkeiten installiert, Electron-Instanzen gestartet oder echte Schlüssel verwendet.

## Abnahmeziel und Prioritäten

Aus einem leeren Notes-Speicher entsteht durch neue Aufnahmen eine dauerhaft gespeicherte, bearbeitbare gemeinsame Fläche. Die KI darf mehrere passende Formen mischen, Quellen weder verlieren noch erfinden und nach manuellen Änderungen keine alte Fassung zurückschreiben. Das Board ist nicht erforderlich, um Gedanken aufzunehmen und zu verarbeiten. Diktat bleibt nutzbar.

P0: Datenverlust, Überschreiben manueller Arbeit, Wiederherstellen gelöschter Inhalte durch verspätete Antworten, Zugriff auf fremde Daten/Schlüssel, unbeschränkte Verarbeitung/Kosten, blockiertes Mikrofon oder Diktatregression. P1: fehlende Kernbedienung, nicht persistente Bearbeitung, nicht mitlaufende Verbindungen, inkorrekte Hotkey-Transaktion, Hintergrundaufnahme funktioniert nicht. P2: visuelle/ergonomische Fehler ohne Verlust.

Die frühere Demo ist eine Stilreferenz, kein Verhaltenstest: Ihre Themen wechseln zwischen vorbereiteten Szenen, feste Elemente sind nicht frei beweglich und Linien sind fest gezeichnet. Die echte Abnahme verlangt eine gemeinsame Fläche, gleichzeitig verschiedene Formen und echte Pointer-Bedienung.

## Vorhandene Werkzeuge und Grenzen

- macOS arm64, Node `22.22.3`, Electron `33.4.11` in `electron-menubar/node_modules/electron/`.
- Playwright `1.64.1` ist bereits lokal vorhanden: `/Users/allan/.npm/_npx/e41f203b7505f1fb/node_modules/playwright`. Der Export `_electron.launch` wurde ohne App-Start auf Verfügbarkeit geprüft. Keine Projektinstallation erforderlich; ein späterer reproduzierbarer Projekt-Test darf eine reguläre Dev-Abhängigkeit verwenden.
- `say` und `afconvert` sind vorhanden. Damit kann bei Bedarf lokale synthetische Sprache in eine WAV-Fixture umgewandelt werden. Für die Transportprüfung genügt eine vollständig synthetische PCM-WAV mit bekannten Pausen und Dauer.
- Die bestehenden Vitest-Tests laufen in Node. Einige Diktatprüfungen verwenden einen VM-Harness, Settings-Synchronität wird bisher anhand von Quelltext geprüft. Das belegt keine Electron-UI, IPC-Isolation oder Betriebssystem-Hotkeys.
- T3-Preview steuert Browserseiten und ist weiterhin für Web-Prototypen passend. Es bietet hier kein Electron-Attach/Launch. Die eigentliche Abnahme verwendet die echten Electron-`BrowserWindow`s über Playwright.
- Die Electron-Automation von Playwright ist experimentell, unterstützt laut Dokumentation Electron ab v21. Ein kurzer Launch-/Fenster-Smoke entscheidet erst nach Implementierung, ob die hier vorhandene Kombination tatsächlich läuft. [Electron-Testanleitung](https://www.electronjs.org/docs/latest/tutorial/automated-testing), [Playwright Electron](https://playwright.dev/docs/api/class-electron).

## Isolierter Testaufbau

1. Allan vor dem ersten Start ausdrücklich mitteilen: Die Test-App verwendet einen isolierten Datenordner und sieht deshalb zunächst leer aus. Für diese Runde einen neuen temporären Ordner nutzen, nicht vorhandene produktive Daten und auch nicht einen möglicherweise schon befüllten `~/.paply-test` kopieren.
2. Vor Start ausschließlich synthetische Settings einrichten: erkennbar ungültiger Test-Key, keine Auto-Start-Aktion, keine automatischen Einfügeaktionen in fremde Apps, isolierte Kürzel mit F18/F19-Kombinationen auch für den Test-Diktatpfad. Keine bestehenden Keys lesen. Der Notes-Store bleibt leer. `PAPLY_USER_DATA` wird bereits vor Store und Single-Instance-Lock unterstützt.
3. Umgebung aus einer kleinen Liste notwendiger Variablen bilden; keine API-Key-Variablen vererben. `ELECTRON_RUN_AS_NODE` nicht übernehmen. App mit vorhandenem Electron-Binary, aktuellem gebautem Renderer und `PAPLY_USER_DATA` starten. Test-Harness und Beweisdateien liegen außerhalb produktiver Daten.
4. Fenster nach URL/Zweck auswählen; `firstWindow()` kann der versteckte Diktat-Recorder sein. Fenster-, Main- und Rendererfehler getrennt protokollieren. Screenshots enthalten nur synthetische Inhalte.
5. Testinstanz in `finally` schließen, nur ihre Prozesse/Hotkeys aufräumen. Produktive Paply-Instanz nicht beenden. Clipboard vor eigener Nutzung im Speicher sichern und anschließend wiederherstellen; dessen ursprünglichen Inhalt nicht protokollieren.

Ein anderer Datenordner isoliert keine Betriebssystem-Hotkeys. Native Registrierungen sind global und können bei Belegung fehlschlagen. `globalShortcut.isRegistered()` bestätigt Registrierung, aber noch keinen tatsächlichen Tastendruck. [Electron globalShortcut](https://www.electronjs.org/docs/latest/api/global-shortcut/).

### Mikrofon und Groq ohne echte Schlüssel

Electron mit `--use-fake-device-for-media-stream`, `--use-fake-ui-for-media-stream` und `--use-file-for-fake-audio-capture=/absoluter/testpfad.wav` starten. Eine kurze PCM-WAV mit bekannter Länge, hörbaren Abschnitten und Stille verwenden. Der normale `getUserMedia` → AudioWorklet → Chunk/ACK → gespeicherte WAV → Transkriptions-Request-Pfad muss laufen. Keine fertigen Notes-Datensätze oder Recorder-Chunks direkt in den Store injizieren. [Chromium-Definition der WAV-Option](https://chromium.googlesource.com/chromium/src/+/eab2ca123fe2e35ca02e726a7162783817126e37/media/base/media_switches.cc).

Nur die Modell-Transportgrenze wird kontrolliert ersetzt. Bevorzugt einen austauschbaren `fetchImpl`/dynamischen Fetch-Aufruf im Main-Prozess nutzen, dessen Testimplementierung außerhalb des Produktcodes liegt. Alternativ einen externen Electron-Bootstrap verwenden, der den Transport vor dem Laden der App ersetzt; dessen Auswirkungen auf App-Pfade/Metadaten separat prüfen. Renderer-`page.route()` allein reicht für Main-Prozess-Node-Fetch nicht.

Der Mock akzeptiert ausschließlich erwartete Groq-Endpunkte und den bekannten Dummy-Key, lehnt unerwartete Requests ab und protokolliert nur Modell, Job-ID, Anzahl, Größe, Timing und synthetischen Inhalt. Er prüft den wirklichen Audio-Request: RIFF/WAVE-Kopf, Sampleformat, plausible Dauer, nicht nur Stille, endliche Größe. Erst danach liefert er ein festes synthetisches Transkript und anschließend einen zur tatsächlichen Validierung passenden Darstellungsplan. Verzögerungen, Abbruch, 401, 429 mit Retry-After, Timeout, ungültiges JSON und unvollständige Pläne sind steuerbar.

Auf Restart muss die Transportersetzung vor `resumePending` aktiv sein; sonst ist der Test unsicher/unvollständig. Es darf kein produktiver Mockmodus und kein dauerhaft offener Test-IPC-Endpunkt entstehen. Die exakten Schnittstellen werden nach Implementierung vereinbart.

Das beweist echte App-Verkabelung und Audioverarbeitung mit simuliertem Gerät, nicht Mikrofonhardware, TCC-Berechtigungen, Whisper-Genauigkeit oder Qualität echter Modellantworten. Live-Groq ist eine getrennte, ausdrücklich benannte Prüfung, sobald dafür ein Schlüssel verfügbar ist; diese Vorbereitungsrunde nutzt keinen.

### Pointer und Live-Verbindungen

Elemente über zugängliche Rollen/Labels bzw. stabile IDs lokalisieren. `page.mouse.move/down/move/up` ausführen; keine Koordinaten im React-Store setzen und keine Handler direkt aufrufen. Während gedrückter Maustaste mindestens zwei Zwischenpositionen messen. Jeweils sichtbare Elementgrenze und SVG-Pfad-Endpunkt (in denselben Bildschirmkoordinaten) vergleichen. Die verbundene Kante muss schon vor `mouse.up` folgen; nur ein geänderter Pfad nach dem Loslassen reicht nicht. [Playwright Mouse](https://playwright.dev/docs/api/class-mouse).

Bei Zoom/Pan wiederholen, um Fehler zwischen Bildschirm- und Canvas-Koordinaten zu finden. Resize am sichtbaren Griff ausführen. Freie Linie/Pfeil zeichnen, auswählen und beide Endpunkte einzeln ziehen; anschließend Undo/Redo und Persistenz prüfen. Screenshots vor/während/nach dem Drag sowie Messwerte sichern.

### Hintergrund und native Eingaben

Der vorhandene Playwright-Electron-Loader setzt u. a. `--disable-background-timer-throttling` und `--disable-renderer-backgrounding`. Für den gezielten Hintergrundnachweis diese Automationsflags vor App-Ready entfernen und die effektiven Flags dokumentieren, oder denselben Ablauf zusätzlich bei normalem Electron-Start prüfen. Sonst könnte der Harness einen Hintergrundfehler verdecken.

Playwright-Tastendrücke in einer Seite beweisen keinen macOS-globalen Shortcut. Native Eingaben separat mit verfügbaren Betriebssystem-/Computer-Use-Werkzeugen testen, ohne Berechtigungen zu umgehen. Wenn Accessibility/TCC den automatisierten Nachweis verhindert, diesen Fall als offen ausweisen. Ein direkter IPC-Start zählt dann nur als Aufnahme-/Pipelineprüfung. Gleiches gilt für echte Trackpad-Pinch-Gesten gegenüber synthetischen Wheel-Ereignissen.

## Fokussierte Prüfmatrix

| ID | Ablauf | Erwartung / Beweis |
| --- | --- | --- |
| A01 | Leere App öffnen, Notes aufrufen; kein Key, dann Dummy-Key über Settings | Keine Beispieldaten; verständlicher Leer-/Fehlerzustand. Manuelles Anlegen/Ändern funktioniert ohne KI. Notes-Preload enthält keinen Key/Settings-Vollzugriff. |
| A02 | Erste synthetische Aufnahme bei geschlossenem Board, stoppen; erst nach verarbeitetem Job Board öffnen | Echte WAV und unveränderte Quelle vorhanden, Einordnung bereits ohne Board abgeschlossen. Quelle, Job und dargestellte Objekte korrelieren. |
| A03 | Weitere Aufnahmen zu verwandtem und fremdem Thema; ein Transkript enthält zwei Themen | Vorhandene Fläche wächst. Themen springen zu Objekten auf derselben Fläche. Keine versteckten getrennten Boards, keine verlorenen Teilgedanken. Karten, freie/Haftnotizen, Mindmap, Vergleichstabelle und Ablauf gleichzeitig erreichbar. |
| A04 | Knoten ziehen/resize, verbundenen Nachbarn ziehen, freie Linie/Pfeil samt Endpunkten bearbeiten | Tatsächliche Pointer-Aktionen; Pfade folgen während Bewegung. Mindestgröße verhindert unbedienbare Elemente, Text bleibt erreichbar. Bei verändertem Zoom stimmen Koordinaten. |
| A05 | Text und Tabellenzelle bearbeiten, Original öffnen, kopieren, entfernen, Undo/Redo | Darstellung ändert sich, Original bleibt unverändert. Copy entspricht Auswahl. Delete entfernt die richtige Einheit und behandelt Kanten sinnvoll. Ein Drag ist eine sinnvolle Undo-Einheit. Eingabe-Undo/Delete beschädigen nicht versehentlich das Board. |
| A06 | Synthetischen Text und PNG aus Clipboard einfügen; speichern, App beenden/neustarten | Kompakter Bildanhang, persistente Bytes/Referenz und korrekter Text. Kein Bildinhalt als unkontrollierter Dateipfad/HTML. Kameraaktion nimmt jetzt auf; Bildschirmkontext nur nach ausdrücklicher Aktivierung/Übernahme. |
| A07 | Pan/Zoom/Fit, Themenwechsel, Fenster schließen/öffnen, Editieren | Keine Modellrequests durch reine Ansicht/Bedienung. Bestehende Positionen, Größen und Änderungen bleiben erhalten. Neue KI-Ergänzung verschiebt keine manuell geordneten Objekte. |
| A08 | Aufnahme starten, sehr schnell stoppen, abbrechen, erneut starten; Recorder während Aufnahme abstürzen lassen | Höchstens eine aktive Spur. Pille entspricht Status; Stop/Abbruch gibt Mikrofon frei. Bestätigte PCM-Chunks bleiben nach Absturz rekonstruierbar; keine hängende Sperre oder unbegrenzter Job. |
| A09 | Notes↔Diktat und Notes↔Meeting in beiden Startreihenfolgen, einschließlich Start-Race | Mikrofonarbitrierung greift vor asynchroner Freigabe. Vorhandene Aufnahme wird nicht zerstört. Nach Stop sind beide Wege wieder möglich. Bestehende Diktatbedienung funktioniert unverändert; Test-Texte nur in kontrolliertes Ziel. |
| A10 | Notes-Hotkeys in Dashboard UND separatem Settings-Fenster ändern; Konflikt mit Diktat/Notes und belegtem OS-Kürzel erzeugen | Werte/UI synchron. Fehlgeschlagener Wechsel behält alte Registrierung und Einstellung; keine halbe Umstellung. Öffnen und Aufnahme sind getrennt. Native Eingabe gesondert belegen. |
| A11 | Verzögerten Plan anfordern, währenddessen Quelle/Objekt manuell bearbeiten bzw. löschen, danach Antwort freigeben | Nutzereingabe gewinnt; gelöschte Objekte werden nicht wiederbelebt. Andere gültige Ergänzungen gehen nicht verloren. Quellen bleiben nachvollziehbar. |
| A12 | Ungültiger/überlanger Plan, unbekannte IDs/Formen, doppelte IDs, fehlende Quellenabdeckung, fremde Daten/Anweisungen im Transkript | Kein ausführbarer Modellcode, keine fremden Dateien/URLs/Settings. Validierung lehnt unzulässige Operationen ab. Vollständiger Rohtext bleibt sichtbar und wiederverarbeitbar; keine stillschweigende Teilübernahme mit Datenverlust. |
| A13 | Offline, 401, 429, Timeout; Minuten-/Tageslimit knapp vor Request; mehrere wartende Jobs | Persistente endliche Queue, nachvollziehbare Zustände; Auth nicht endlos retryen. Reservierung verhindert paralleles Überbuchen. Backoff/Retry-After eingehalten, keine enge Schleife. Diktat bekommt vorgesehenen Vorrang. |
| A14 | App mit wartendem bzw. laufendem Job schließen/killen, mit gleichem Profil neu starten; wiederholen nach erfolgreichem Commit | Genau einmal sichtbarer Commit, kein Verlust/duplizierter Inhalt. Reservation/Retry-Status bleibt konsistent. Audio wird erst gemäß Aufbewahrungsvertrag entfernt. Keine blockierte Queue durch einen defekten Job. |
| A15 | Fremder Renderer/Frame sendet Notes-IPC; übergroße Payloads, ungültige Chunksequenz, Traversal und unbekannte Attachment-ID | Ablehnung vor Mutation, keine Key-/Pfad-Leaks. Recorder darf kein Board mutieren; Board darf Recorder-/Settingsrechte nicht übernehmen. Gültiger Nutzerpfad bleibt danach nutzbar. |
| A16 | Notes-Pille im laufenden/gestoppten/fehlerhaften Zustand; Light/Dark und Reduced Motion; längerer Text und langes Tabellenfeld | Erkennbar Paply/Echo-verwandt, grün-goldene Unterscheidung, echte Icons, kein Dauerflackern. Reduced Motion wirksam. Texte/Bedienfelder werden nicht abgeschnitten oder von Overlays verdeckt. |

## Technische Ergänzungen ohne endlose Gesamttestschleifen

Nach Stabilisierung zuerst die neuen Notes-Unit-/Integrationstests und die berührten Diktat-/Settings-Tests prüfen. Unabhängige Gegenproben konzentrieren sich auf Persistenzfehler, Chunk-Reihenfolge/Duplikate/fehlende Bestätigung, stale edit/delete, Budget-Reservierung/Rückbuchung und unerlaubte IPC-Sender. Zeitlimits/Backoff in Unit-Tests mit kontrollierter Uhr statt minutenlangem Warten prüfen. Atomare Store-Schreibvorgänge einschließlich beschädigter temporärer Datei/Crash zwischen Schreibschritten prüfen; Fehler niemals still als leeren Store laden.

Danach ein zusammenhängender Electron-Abnahmelauf mit drei bis vier synthetischen Aufnahmen und gezielten Fehlerläufen in separaten leeren Profilen. Erfolgreiche stabile Fälle nicht ohne Anlass ständig wiederholen. Nach Befund-Fix den betroffenen Fall und dessen direkte Nachbarn erneut prüfen. Abschließend einmal vollständige passende Tests, Build und TypeScript-Differenz zur bekannten Baseline. Packaging-Dateiliste muss Notes-Mainmodule, Preloads, Recorder-Worklet und Renderer enthalten; ein Dev-Start allein beweist das nicht.

## Benötigte Implementierungsverträge vor Ausführung

- Namen der Notes-Fenster/Renderer, IPC-Kanäle und erlaubten Sender; stabile sichtbare Labels/IDs für Knoten, Kanten, Resize- und Endpunktgriffe.
- Store-/Queue-/Source-Schema mit Revisions-/Tombstone-Regeln, Audio-Pfaden, Recovery- und ACK-Vertrag, definierten Limits und Retry-Zuständen.
- Konkrete Plan-/Abdeckungsschemata, Modellendpunkte und Transportinjektion; Boot-Reihenfolge für eine sichere Resume-Prüfung.
- Settings-Keys und tatsächliche Kürzelkonflikt-/Arbitrierungsregeln, UI-Einstieg zum Starten/Öffnen sowie klare Produktentscheidung zur Quellen-/Audioaufbewahrung.

Der Testbericht nennt pro Fall Ergebnis, tatsächliche Aktion, Beweisdatei und Einschränkung. Getrennt ausweisen: Node-/Integrationstest, echte Electron-UI mit synthetischem Mikrofon und Modellmock, native macOS-Eingabe/Berechtigung, echte Groq-Antwort. Windows bleibt ohne eigene Ausführung ungetestet. Eine geprüfte Test-App darf keine Mockdaten oder Testtransport-Ersatzimplementierung als Standard enthalten. Diese vorbereitende Task-ID bleibt als Herkunft erhalten; die Ausführungsrunde erhält einen eigenen klaren Status und Befund-Fix-Nachweis.
