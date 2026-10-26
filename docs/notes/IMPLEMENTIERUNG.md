# Paply Notes — Umsetzungsauftrag vom 26.10.2026

Status: Nach der lokalen Apple-Silicon-Testversion 1.15.0-notes.2 hat Allan das reguläre Release 1.15.0 und seine MacBook-Aktualisierung freigegeben. Grundlage ist notes.1 mit 608/608 Tests, separater Electron-/Paket-/Editor-QA und lokaler Freigabe durch Opus 5.5 Extra High. Für die eng begrenzte Hotkeykorrektur: 108 gezielte Tests, TypeScript und Build grün sowie separate Paketnachprüfung. Aktueller Veröffentlichungsstand in `../STAND.md`, historische Testanleitung in `TESTEN.md`.

MacBook-Praxistest: Bei deutscher Belegung löste die alte Y-Voreinstellung auf Z aus, vom Nutzer bestätigt. Electron 33 verwendet für globale macOS-Kürzel physische US-Positionen (siehe [Electron-Hinweis](https://www.electronjs.org/docs/latest/tutorial/keyboard-shortcuts#global-shortcuts)). Ein Notes-eigener Carbon-Helfer liest nun unmodifizierte Tastenbeschriftungen ohne Tastaturüberwachung oder Zusatzberechtigungen. Die Voreinstellung wird daraus gebildet, Anzeige und Erfassung verwenden dieselbe Zuordnung; gespeicherte eigene physische Kürzel bleiben erhalten. Diktat, gemeinsamer Shortcut-Parser, Aufnahme-Pille und Audiofilter wurden hierfür nicht geändert.

## Von Allan bestätigt

- Neue Gedankenablage mit konfigurierbarem Aufnahme-Hotkey (Beispiel Cmd+Y), eigenem Öffnen-Hotkey und Einstieg in der App. Die vorhandene Diktatbedienung bleibt erhalten.
- Eine gemeinsame Fläche. Themen dienen der Navigation/Zuordnung, nicht als getrennte Notizbücher. Karten, freie Notizen, Haftnotizen, Mindmap-Zweige, Abläufe und Vergleiche dürfen sich mischen.
- Optische Referenz: `docs/prototypes/paply-notes-generative.html`. Dezente gezeichnete Anmutung, echte Icons, Paply-Farben und Paply-Marke. Kein Zwang, alle Gedanken in dieselbe Form zu pressen.
- Elemente frei ziehen, Größe ändern, bearbeiten, kopieren, entfernen, Undo/Redo. Angebundene Verbindungen gehen live mit; freie Linien/Pfeile mit beweglichen Endpunkten. Direkte Trackpadnavigation.
- Die Fläche wächst auch bei geschlossenem Fenster aus Sprachaufnahmen. Ein Groq-Key aus den vorhandenen Einstellungen. Keine Recherche und kein Aufgabenmanagement.
- Screenshots/Bilder kompakte Anhänge; Text/Bild einfügen. Keine dauernde Bildschirmaufnahme. Ein Start-Screenshot nur bei bewusst aktiviertem Bildschirmkontext und ausdrücklich gewünschter Übernahme; Kameraaktion nimmt jetzt auf.
- Notes-Pille verwandt mit Echo, aber unterscheidbar: zurückhaltende grün-goldene Aura, kurze lebendige Animation, Reduced Motion beachten.
- Vorprüfung durch Opus 5.5 Extra High, Implementierung, abschließender Opus-Review, separate unabhängige Tests, dann geprüfte Test-App übergeben.

## Umgesetzte Architektur

- Eigene `notes/`-Module im Main-Prozess; eigener Board- und Recorder-Preload ohne API-Key/Settings-Zugriff; klare Sender- und Payload-Prüfung.
- Serieller, atomarer Store im User-Data-Verzeichnis; Originalquellen separat von editierbaren Objekten, Ansicht und lokal abgeleitetem Themenindex. Keine Daten im Repository. Undo als begrenzte inverse Änderungen, nicht als unbeschränkte vollständige Store-Kopien.
- Recorder als eigenständige PCM/AudioWorklet-Spur, sequenzierte bestätigte Chunk-Schreibvorgänge, daraus WAV für Whisper. Dadurch rekonstruierbar ohne abhängig vom letzten MediaRecorder-WebM-Chunk zu sein. Notes reserviert seinen Start vor dem ersten asynchronen Schritt. Bestehendes Diktat/Meeting hat Vorrang: Notes pausiert per synchronem Main-Haken und Epochen-Gate bzw. sichert und beendet.
- Neue Hotkeys separat und transaktional registrieren; keine Notes-uiohook-Listener. Konflikte prüfen, vorherige Registrierung bei Fehler behalten.
- React Flow als Canvas-Grundlage (Drag/Resize/Selection/Reconnect/Pan/Zoom), Paply-Komponenten mit OpenUI als kontrollierte Darstellungsschicht. Modell liefert keine ausführbaren Programme und keine beliebigen Koordinaten.
- Pipeline: lokale Sicherung → Whisper → ein begrenzter Einordnungs-/Darstellungsplan → validierter Commit → lokale Projektion. Bildanalyse optional separat, begrenzt und nach Bildhash/Analyseversion gecacht.
- Offene Bearbeitungen haben eine Main-seitige Lease. Fertige Pläne warten lokal mit ihrer Rohkartenrevision; erneutes Speichern nach einem lokalen Schreibfehler verwendet diesen Cache. Editor speichert gegen die Revision beim Öffnen und bewahrt den Entwurf bei Konflikten.
- Alle Quellenbestandteile müssen abgedeckt sein. Ungültige/geänderte/veraltete Antworten dürfen keine Daten verlieren oder entfernte Notizen wiederherstellen. Bei Limit/offline/fehlendem Key bleiben Rohdaten und manuelle Bedienung verfügbar.
- Gedächtnis: nur abgeleiteter Quellenindex (Themen, Nutzervorrang, begrenzte Textauszüge). Kein autonomer Agent und keine stündliche komplette Neugenerierung.
- Minuten- und Tagesbudgets vor Requests reservieren, tatsächlichen Verbrauch nachhalten; 429/Timeout/Auth sauber unterscheiden, endliche Wiederholungen. Ursprüngliches Diktat erhält Vorrang.

## Prüfstand vor Änderungen

- `npm test -- --reporter=dot`: 38 Dateien, 529 Tests bestanden.
- `npm run vite:build`: bestanden.
- `npx tsc --noEmit`: fünf bereits vorhandene Fehler in `src/apps/dashboard/Dashboard.tsx` (State string/null und vier Profile/CustomAgent-Casts). Keine Notes-Änderungen zu diesem Zeitpunkt.

## Abnahmepunkte

- Start aus leerem Notes-Store, mehrfaches Einsprechen mit einem/mehreren Themen, Rohtext bei Ausfall, anschließende begrenzte Einordnung ohne geöffnetes Board.
- Einstellungen in Dashboard UND separatem Settings-Fenster; Konflikt und fehlgeschlagener Kürzelwechsel ohne Verlust des bisherigen Kürzels.
- Eigene Pille, Mikrofonfreigabe, schnelles Start/Stop, Abbruch, konkurrierende Aufnahme, Renderer-Absturz und Neustart.
- Lesen/Schreiben/Anhänge über dedizierte IPC; unerlaubte Sender, Pfade und Payloads ablehnen.
- Ziehen/Resize, mitlaufende Verbindungen, freie Pfeile/Endpunkte, Text/Tabellenzellen, Paste, Source, Copy/Delete/Undo/Redo; kein Neugenerieren beim Öffnen/Zoom/Edit.
- Mehrere KI-Antworten, Quotenende/429, Timeout/Authfehler, stale edit/delete, vollständige Quellenabdeckung, Restart-Pending-Jobs, gemessene API-Verbräuche soweit ein Schlüssel verfügbar ist.
- Build/Unit-/Integrationstests; echte Electron-Testinstanz isoliert von normalen Nutzerdaten. Auf leer wirkenden Test-Datenordner vor Start hinweisen. macOS praktisch testen, Windows-Testgrenzen benennen.
- Abschlussreview und unabhängiger Testbericht jeweils mit eigener Task-ID und anschließendem Befund-Fix.


## Modellsteuerung und Kosten, Stand nach echten Proben

- Whisper `whisper-large-v3-turbo`, PCM 16 kHz, maximal 9 Minuten je Request; gespeicherte Teiltranskripte werden wiederverwendet.
- Kurze Gedanken: `openai/gpt-oss-20b`, low, 2.500 Ausgabetoken. Ab drei Sätzen bzw. 550 Zeichen: `openai/gpt-oss-120b`, medium, 3.200 Ausgabetoken. Nur ein fehlgeschlagener kleiner Plan darf einmal zum großen Modell wechseln; große fehlerhafte Pläne bleiben als sichtbares Original erhalten. „Erneut“ ist eine bewusste neue Anforderung.
- Höchstens 24 Sätze / 3.000 Zeichen je Plan; ein einzelner übergroßer Satz bleibt vollständig als Rohnotiz. Kontext: höchstens 20 Themen + 10 kleine vorhandene Textauszüge, ohne eigene Quelle. Bei Platzmangel zuerst Kontext verkleinern.
- Lokaler Quellenindex aus den tatsächlichen Notizen; gelöschte und korrigierte Texte verschwinden aus dem nächsten Kontext. Keine separate sich verselbständigende Memory. Themen werden vorerst nicht automatisch zusammengelegt oder umbenannt.
- Optional `qwen/qwen3.8-27b` für ein Bild mit JSON-Modus und ohne Reasoning, maximal 700 Ausgabetoken. Cache nach Bildhash, höchstens 10 Versuche / 24 Stunden, drei je Bild. Kein Vollbild wird in einen Textplan aufgenommen.
- Notes-Voreinstellung: 100.000 reservierte/verbrauchte Token und 60 Audiominuten pro rollierenden 24 Stunden, maximal 7.600 Token pro Modellminute, höchstens ein laufender Notes-Request. Dies koordiniert weder andere Geräte noch die bestehenden Diktat-/Meeting-Quoten; diese haben Vorrang beim Start von Notes-Jobs, ein bereits gestarteter Providerrequest kann noch laufen.
- Echte synthetische Groq-Probe: 4/4 valide (Mindmap, Tabelle, Ablauf, Themenwechsel), 19/19 Sätze abgedeckt, zusammen 13.486 tatsächliche Token. Einzelantworten 2,15–4,29 s. Zusätzlich befülltes Board mit 30 Notizen / 20 Themen und echten UUID-IDs: 12/12 Sätze, Mindmap, 4,34 s, 3.324 Prompttoken + 1.861 Ausgabe = 5.185 gesamt; Reservierung 7.520, Finish `stop`. Das sind Stichproben, kein repräsentativer Qualitätsbenchmark.
- Zusätzliche echte Kurzprobe: 20B, 1/1 Satz als einzelne Notiz ohne neues Thema, 2.092 Token, 823 ms. Bildprobe: künstliches Rechteck mit „LAMPE A / 80 EUR“ korrekt beschrieben und Text gelesen, 331 ms. Vollständige synthetische Messergebnisse in `groq-probes-2026-10-26.json`.
- Das kostenlose Kontingent ist abhängig von Groq-Konto und weiterer Nutzung. Bei etwa 3.400–5.200 Token pro größerem Gedanken passen ungefähr 19–29 solcher Einordnungen ins voreingestellte lokale Tagesbudget, weniger mit Bildern, Fehlerreservierungen und zusätzlichem Kontext. Kleines Modell, STT und die Providergrenzen sind separat zu beachten. Kein Versprechen unbegrenzter Gratisnutzung.
- Verifizierte Providerverträge: [Structured Outputs](https://console.groq.com/docs/structured-outputs), [Vision](https://console.groq.com/docs/vision), [Reasoning](https://console.groq.com/docs/reasoning), [Limits](https://console.groq.com/docs/rate-limits).

## Bewusste Grenzen der ersten Version

- Lokaler Store mit atomarem JSON, vorheriger Generation und maximal 48 stündlichen Sicherungen; Originale separat. Undo/Redo für 200 Benutzeränderungen innerhalb der Sitzung. Ansicht separat und ohne vollständigen Board-Broadcast gespeichert.
- Entfernen heißt: von der Fläche entfernen. Originaltranskript bleibt lokal für Wiederherstellung; erfolgreich verarbeiteter Ton wird nach sieben Tagen beim nächsten Appstart bereinigt, fehlgeschlagene Aufnahmen bleiben erhalten. Startbilder nur nach Opt-in, während ausstehender Transkription höchstens sieben Tage über Neustarts behalten.
- Vergleichszellen sind geprüfte Originalzitate, übriger Wortlaut im Originaldialog. Manuelle Tabelle zunächst 2 Spalten / 1 Zeile. Themenchips navigieren zu Bereichen einer einzigen Fläche; Themenpflege ist noch nicht als eigener Editor ausgebaut.
- Manuell verschobene, vergrößerte oder bearbeitete Rohkarten bleiben bewusst Rohnotizen; kein automatisches Neuordnen dieser Karte. Lange Aufnahmen werden trotzdem vollständig in weiteren Teilen erhalten und eingeordnet.
- Cmd+Y und Cmd+Alt+Y sind globale, änderbare Voreinstellungen und überdecken diese Kürzel in anderen Apps. Nicht zugleich mit einem zweiten Paply mit denselben Kürzeln testen. Für ein späteres Release Standardbelegung noch abstimmen.
- Windows, echte Mikrofon-/Bildschirmberechtigungen und physische Hotkeys sind nicht durch die automatische macOS-QA vollständig abgenommen. Native Tastenkürzelregistrierung, echte Pointeraktionen und Clipboard sind belegt. Die erste WAV-Datei-QA benötigte einen dokumentierten Sandbox-Workaround; der abschließende synthetische Mikrofon-/Editor-Test lief mit Chromiums internem Fake-Mikrofon in normaler Sandbox.
