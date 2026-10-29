# Paply — Stand

**Zeitpunkt:** 29.10.2026 · **Phase:** Paply Android 0.2.0 (Paply-Knopf) in Abnahme (Branch `feat/android-v1`) · Desktop v1.15.3 mit gemeinsamer Polier-Quelle lokal auf `main` · Paply iOS 0.1.0 bei TestFlight (Branch `feat/ios-v1`)

## Paply Android — V1 im Aufbau (28.10.2026, Branch `feat/android-v1`, Ordner `android/`)

- **Ziel:** gleiche Qualität, gleiches Design und gleiche UX wie Paply iOS V1, als APK-Testversion für Freunde.
  Kotlin + Jetpack Compose, nativ. `ios/` ist nur Vorlage.
- **Arbeitsteilung:** Claude (Opus 5.5) plant und entscheidet, Codex setzt um, Sonnet 5.5 prüft jedes Ergebnis.
- **Rechner:** Gebaut und getestet wird nur auf dem MacBook (M5, 32 GB, 136 GB frei). Dort liegen Java, Android-Werkzeuge
  und der Emulator `paply` in `~/Android`; mit `rm -rf ~/Android` ist alles wieder weg. Allan hat das am 28.10.
  freigegeben. Der Mac mini ist knapp an Platz, dort entsteht nur Quelltext; nach dem T3-Update kann das MacBook
  direkt als Umgebung verknüpft werden.
- **Phase 0 bestanden (28.10., Emulator Android 17/API 37, `android/docs/PHASE0.md`):**
  - Die Paply-Tastatur nimmt beim Erscheinen sofort selbst auf, ohne Bereitschafts-Mikro, und setzt polierten Text
    (de/en) in ein fremdes Feld (Kontakte) ein. Danach geht es zurück zu Gboard, links wischen verwirft.
  - Die Gedanken-Kachel startet eine Aufnahmekarte und einen Mikro-Vordergrunddienst. Die Benachrichtigung zeigt
    einen Zähler sowie „Fertig“ und „Verwerfen“. Ein Live-Update-Chip mit Zähler steht in der Statusleiste.
  - Das klappt auch bei gesperrtem Gerät. Nach 10 Min. ist automatisch Schluss.
  - Der Mikro-Punkt erscheint nur während der Aufnahme.
  - Groq: 8 Aufrufe.
- **Review Phase 0** (Sonnet): 18 Funde mit Zuordnung in `android/docs/REVIEW-P0.md`. Vor Gerätetests Pflicht:
  - Mikro-Recht vor dem Dienststart
  - kein Auto-Start nach Drehen
  - kein Datenverlust bei Lesefehler oder Anruf
- **Einstieg** (`android/docs/EINSTIEG.md`): Auf Pixel mit Android 16/17 wechselt ein Tipp auf die Systemtaste unten rechts
  direkt zur nächsten Tastatur. Das ist ein Ein-Tipp-Start wie 🌐 bei iOS (im Emulator noch zu bestätigen).
  Samsung: Navigations-Tastaturtaste. Eine schwebende Taste wie bei Wispr Flow ist erst nach V1 eine Option
  (Overlay + Bedienungshilfe).
- **Etappe 1 (Diktat komplett), im Emulator abgenommen (`android/docs/E1-IME.md`):**
  - Der Diktat-Kern aus iOS ist portiert (`android/docs/E1-CORE.md`, 284 Tests).
  - Die App-Oberfläche ist in Compose gebaut, der Schlüssel liegt im Keystore.
  - Die Tastatur lädt Stücke schon beim Sprechen hoch (FLAC −36 bis −57 %).
  - Tempo: Tipp → Text im Feld in 0,9 s (kurz) bzw. 1,1 s (26 s langes Diktat).
  - Richtig erkannt: „Testname“ über die Eigenen Begriffe, „Hi, wie geht's?“ auf Deutsch, Englisch unübersetzt.
  - Bei Stille gibt es keinen Groq-Aufruf. In Passwortfeldern nimmt Paply nicht auf.
  - Im Flugmodus wird das Diktat als fehlgeschlagen gespeichert, „Erneut versuchen“ klappt danach.
  - Ein Tipp auf die Systemtaste genügt, bei Gboard mit zwei Sprachen teils zwei Tipps.
  - Offen: ein gebündeltes Review samt Korrekturrunde.
- **Etappen 2 und 3 gebaut (29.10. nachts):**
  - Gedanken: Kern `:thoughts`, E0 10/11, Aufnahme-Dienst, WorkManager, Oberfläche, Landkarte
  - Aufgaben-Reiter, Erinnerungen, Aufgaben-Widgets
  - Release-Vorbereitung: Icon, R8, signierte APK 0.1.0, `android/docs/FREUNDE.md`
  - Endreviews: kein Blocker. Endkorrekturen (`REVIEW-P0.md`, „Endreview“) laufen.
- **0.1.0 freigabefähig (29.10. vormittags):**
  - Abschlussprüfung der Release-APK auf Android 17 und 14 (`android/docs/E2E-FINAL.md`): kein Blocker, kein Absturz,
    Kernfunktionen bestanden.
  - Die APK liegt mit Anleitung auf Allans MacBook unter `~/Desktop/Paply-Android/`, SHA-256 `1a00fd03…dae9`.
  - Der Signierschlüssel ist auf MacBook und Mac mini gesichert (`android/docs/RELEASE.md`).
- **0.1.1 (2) fertig** (`android/docs/V011.md`): Lange Stille im Live-Diktat geht nicht mehr an Whisper. Drehen auf Android 17
  sichert Gesprochenes (Zwischenablage + Hinweis). Update über 0.1.0 geprüft. APK `~/Desktop/Paply-Android/Paply-0.1.1.apk`
  (SHA-256 `59d4862d…c522`). Rest-Grenze: Periodisches Emulator-Rauschen gilt bewusst nicht als Stille.
- **0.1.2/0.1.3 (29.10.):**
  - Der erste echte Nutzer (Xiaomi Mi 9, Android 11) meldete einen Absturz beim Start. Ursache: `Stream.toList()` gibt es
    erst ab API 34. Behoben, Start auf API 29–37 geprüft (`android/docs/STARTUP-0.1.2.md`). Eine Fehlerseite ersetzt das
    stille Schließen.
  - Seit 0.1.3 prüft Animal Sniffer `:core`/`:thoughts` gegen API 29 (`android/docs/API-29.md`), dabei wurde
    `readNBytes` gefunden und ersetzt.
  - 0.1.4: Die Einrichtung fordert „Tastatur auswählen“ nicht mehr nach jedem Diktat neu (Samsung-Tester).
- **0.2.0 (29.10., Allans Entscheidung nach Testerfeedback):** Paply-Knopf neben der normalen Tastatur (Bedienungshilfe):
  1 Tipp aufnehmen, 1 Tipp einsetzen, eigene Tastatur bleibt. Auf API 29–32 setzt er direkt ins Feld (ohne Zwischenablage), ab
  API 33 per `commitText`. Gedanken-Karte blendet nach dem Speichern aus. Polier-Prompt aus `shared/polish`. Emulator-Abnahme
  API 30/34/37 (`android/docs/KNOPF.md`). Codex darf seit dem T3-Update keine Emulator-UI steuern → Abnahmen macht die
  Leitung per Claude-Helfer. Seit 29.10. abends: MacBook (T3 0.1.4) als Umgebung verknüpft (Tailscale, bis 28.11.,
  `t3 environment list`), SDK unter `~/Library/Android/sdk` verlinkt – Helfer können dort künftig selbst Emulatoren nutzen.
  - Branch `feat/android-v1` liegt als Sicherung auf GitHub (kein PR, `main` unberührt).
  - Aktuell zum Verschicken: `~/Desktop/Paply-Android/Paply-0.2.0.apk`.
- **Offen ohne echtes Gerät:** Pixel bzw. Samsung real, Anrufe, Bluetooth, Hersteller-Sperrbildschirm.
- **Danach V1 in Etappen:** Gedanken (Kachel, Widget, Benachrichtigung, KI ordnet) → Landkarte, Aufgaben,
  Erinnerungen → Feinschliff und Robustheit → APK für Freunde. Ein echtes Gerät entscheidet Allan.

## Paply iOS — Version 1 für TestFlight (27.10.2026, Branch `feat/ios-v1`)

- **Phase 0 auf dem Gerät bestätigt** (iPhone 14 Pro Max, iOS 18.0): 🌐 → Paply-Tastatur → sprechen → Tipp →
  polierter Text im Feld. Gedanken-Knopf startet das Mikro auch ohne laufende App im Hintergrund (S1,
  `ios/docs/gedanken/S1-TEST.md`). iOS zeigt bei Hintergrund-Mikro ein Mikro-Symbol, nicht nur den Punkt.
- **Version 1 (Scope eingefroren):** Diktat über 🌐 und „Gedanken“ (Knopf auf Sperrbildschirm/Kontrollzentrum,
  Fertig/Verwerfen in der Live Activity, KI ordnet Titel/Thema/Aufgaben/Verknüpfungen, Reiter Gedanken),
  Einrichtungskarte, Datenschutz-Klartext, Feedback senden. Konzept `ios/docs/gedanken/KONZEPT.md`,
  KI-Bewertung `ios/docs/gedanken/EVAL.md`, TestFlight-Ablauf und Texte `ios/docs/TESTFLIGHT.md`.
- **TestFlight (27.10., abends):** 0.1.0 Builds 1, 2, 3 per SSH vom MacBook hochgeladen (Ablauf in der Erinnerung
  „TestFlight-Upload per SSH“). Build 3: Landkarte, Aufgaben-Reiter, Themenbilder, KI-Regeln v6, Mikro startet erst bei
  aktiver App, Selbstheilung bei stummem Mikro. Build 4 (28.10., 03:41): Aufgaben-Widgets, Erinnerung zur Uhrzeit,
  Beta-Schalter, neue Anleitung. Offen bei Allan in App Store Connect: externe Gruppe „Freunde“, Testinformationen,
  Prüf-Schlüssel für Apple, dann öffentlicher Link.
- **Build 5 (28.10., Kandidat für Freunde) – zwei Gerätefunde von Allan:**
  - Kurze Sätze („Hi, wie geht's“) kamen auf Englisch, einmal als „ru“: Whisper rät die Sprache je Anfrage. Jetzt
    gehen Stücke mit ≤ 5 s gesprochener Zeit direkt in der Hauptsprache raus (Einstellung „Hauptsprache“, Standard
    erste iPhone-Sprache); längere mit fremd erkannter Sprache werden einmal in der Hauptsprache wiederholt.
  - Anrufe klingelten und vibrierten in Bereitschaft nicht: `setPrefersNoInterruptionsFromSystemAlerts` stand
    dauerhaft an. Jetzt nur während einer Aufnahme. Offen: Ob Nachrichten in Bereitschaft vibrieren (Allan vermutet
    nein) – falls nicht, Mikro im Leerlauf anhalten (Experiment `idlePause`, auf dem Gerät noch ungetestet).
- **Build 6 (28.10., nachmittags):** Absturz nach Anrufen behoben (AVAudioEngine warf beim Wiederaufnehmen eine
  Objective-C-Ausnahme wegen eines veralteten Formats): frische Engine, Tap ohne festes Format, Ausnahmen über das
  neue Ziel `PaplyObjC` abgefangen. Auf drei Test-iPhones per Kabel/WLAN installiert (Debug).
- **„Alle sehen Daten von anderen“ (28.10.) – kein Datenleck:** Es gibt keinen Server und keine geteilte Datenbank,
  alles liegt nur auf dem jeweiligen iPhone. 
  
- **Build 7 (28.10., abends):** Verlässt man die App, während ein Gedanke läuft, erscheint oben sofort ein Banner
  (ohne Dynamic Island, z. B. iPhone 12 Pro) bzw. klappt die Dynamic Island auf – mit Sekundenzähler, „Fertig“
  und „Verwerfen“, dazu eine Vibration; alle 2 Min. wieder, „noch 1 Min.“ ebenso. Grenze bleibt 10 Min. (Allan).
  Hochgeladen und auf alle drei iPhones gespielt.
- **TestFlight extern:** Gruppe „Testing“ mit öffentlichem Link <TestFlight-Link>
  (bis 10 Tester). Build 5 liegt bei Apple zur ersten Prüfung (eingereicht 28.10. mittags); Apple schickt eine
  E-Mail, wenn sie durch ist. **Danach (Allan):** neuesten Build (7) der Gruppe „Testing“ hinzufügen, Link
  verschicken und den Prüf-Schlüssel für Apple bei Groq löschen. Neue Tester bekommen danach jeden Build ohne
  lange Prüfung.
- **Offen – Gerätetests:** kurze Sätze in der Hauptsprache, Anruf in Bereitschaft (klingelt/vibriert?), Diktat
  direkt nach einem Anruf (kein Absturz), WhatsApp-Vibration in Bereitschaft, Banner und Vibration aus Build 7,
  Experiment `idlePause` (Mikro-Symbol weg? Diktat nach 5/30 Min.?). Klappt `idlePause`, wird es Standard und
  das Mikro wacht schon beim Erscheinen der Tastatur auf. Angeboten: Bereithalten standardmäßig „1 Stunde“.
- Offen: Test `cancelAbortsRunningChunkUploadImmediately` wackelt unter Last (einzeln grün).
- Geprüft: PaplyKit 384 Tests grün, App/Tastatur/Widgets bauen Debug und Release; mehrere Opus-Reviews und ein
  unabhängiger Sonnet-Produkttest. Der zusammengeführte Stand ist auf dem Gerät noch nicht getestet.
- Bauen/Signieren: Mac mini entwickelt, MacBook (Xcode 26.5, iOS-Plattform installiert) signiert; Signieren nur
  aus der Xcode-Oberfläche (Schlüsselbund über SSH gesperrt). App in App Store Connect angelegt.
- KI-Prompt v2; Bewertung E1 Tag 1 (v1) mit 18 Fällen, weitere Läufe im Free-Tier verteilt (≤ 60 000 Tokens/Tag,
  gpt-oss-120b, nie qwen).
- **Nach Version 1 (Allan zugestimmt bzw. vorgeschlagen):** Widget „Offen“ (Sperrbildschirm nur Zahl, Home bis
  3 Aufgaben abhakbar, keine Mitteilungen), Gedanken per Tastatur einsetzen, „In WhatsApp öffnen“ für erkannte
  Nachrichten, „Frag deine Gedanken“, Spotlight/Siri, Teilen → Paply, Mehrsprachigkeit der Oberfläche,
  Paply-Zugang ohne eigenen Groq-Schlüssel (Server).
- **Vorgemerkt, noch nicht bauen (Allan, 27.10.):** Eine Aufnahme mit klar getrennten Sachen in mehrere Gedanken
  aufteilen, jeder mit eigenem Thema. Nur aufteilen, wenn die Teile eindeutig nichts miteinander zu tun haben; im
  Zweifel bleibt es ein Gedanke. Die Teile verweisen aufeinander („Aus einer Aufnahme“). Heute wird aus einer
  Aufnahme genau ein Gedanke; Thema und Titel richten sich nach der Hauptsache, Aufgaben werden alle erkannt.
- **Vorgemerkt für später (Allan, 27.10.):** Meeting-Modus – mehrere Personen in einer Besprechung, daraus
  Protokoll und To-dos.
- Nebenwirkung 27.10.: Die Mac-Latenzmessung hat das Free-Tier-Polierkontingent (qwen) von Allans Groq-Schlüssel
  fast aufgebraucht; das Desktop-Diktat setzte bis zur Erholung Rohtext ein.


## v1.15.3 — Gemeinsame Polier-Quelle (29.10.2026, lokal vorbereitet)

- Einziger System-Prompt unter `shared/polish/system-prompt.txt`, bytegleich im Desktop eingebettet;
  englisches JSON-Nachrichtenformat wie iOS/Android, eigene Begriffe normalisiert.
- Mobiles Sicherheitsnetz inklusive Zahlen, Selbstkorrekturen, kleinen Ersetzungen und Profilgrenzen
  portiert. Bei Ablehnung bleibt der Rohtext; Aufnahme, Cmd+X und Einfügen unverändert.
- 744 automatische Tests grün; 100 gemeinsame künstliche Testvektoren und Swift-JSON-Referenz sichern den Abgleich.
  Bekannte mobile Fehlablehnungen/heuristische Grenzen bleiben erhalten (siehe `shared/polish/README.md`).
- Private Verlaufsauswertung nur lokal, ohne Groq-Aufrufe. Keine Veröffentlichung, kein Tag/Push;
  mobile Prompt-Einbettungen und Gleichheitstests in den jeweiligen Branches nachziehen.

## v1.15.2 — Robustheit Mac/Windows nach Log-Sichtung und iOS-Abgleich (28.10.2026)

Allan: „dass auf macOS und Windows alles neueste Version und korrekt läuft“.
- **Polieren:** Bei Groq-Limit (429, z. B. qwen-Tageskontingent) einmal `gpt-oss-120b` mit eigenem Kontingent
  (wie iOS) statt still Rohtext; nur mit ≥ 3 s Restzeit, Sicherheitsnetz gilt weiter.
- **Lange Diktate:** Upload-Zeitlimit wächst mit der Dateigröße (60 s + ~0,5 Mbit/s), alle Versuche zusammen
  höchstens wie bisher 4 × 60 s bzw. ein Upload + 60 s; 413 → „Aufnahme zu lang“ mit Erklärung; bei 429 mit
  Retry-After > 10 s kein sturer Neuversuch.
- **Diagnose-Protokoll:** `<Datenordner>/logs/paply.log` (≤ 2 MB + eine alte Datei), ohne Diktattext, Schlüssel
  geschwärzt; Tray „Protokoll anzeigen“. Damit lassen sich Fehler beim Windows-Freund nachvollziehen.
- **Dashboard:** Aufnahmeminuten und Fehler werden gezählt (vorher immer „0 min“ / „100 %“).
- **Sicherheit:** config.json (API-Schlüssel) nur für den eigenen Benutzer (0600, vorher rw-rw-rw-).
  Laufzeit-Pakete semver-kompatibel aktualisiert (js-yaml, form-data, ajv, fast-uri). GitHub Actions auf
  Node-24-Versionen, Build mit Node 22.
- Bewusst nicht: Zahlen-Schutz beim Polieren (215 echte polierte Diktate: keine verfälschte Zahl, einziger Treffer
  wäre harmlose Formatierung gewesen); `electron-updater` bleibt 6.6.2 (Fix ändert Windows-Update-Ablauf, Lücke
  betrifft Paply nicht); **Electron 33 → 45+** steht aus (viele Sicherheitshinweise, eigenes Projekt mit Praxistest).
- Geprüft: 651 automatische Tests, TypeScript, Review (keine Blocker, Befunde behoben), echter Durchlauf mit
  Fake-Mikro + Groq (Satz → poliert in ~1 s, Stille → nichts, Protokoll ohne Text/Schlüssel, config 0600).
- Log-Sichtung iOS (28.10.): 1 Absturz nach Anruf (Build 5) — in Build 6 behoben, auf dem iPhone noch zu prüfen;
  Akku/Wärme in Bereitschaft ungeklärt (Mikro dauerhaft offen) → Paply-Anteil in Einstellungen › Batterie ansehen.

## v1.15.1 — Abgleich mit Paply iOS (28.10.2026)

- Allans Auftrag: Diktat auf Mac/Windows so flüssig wie Paply iOS, nur Eindeutiges reparieren.
- Abgleich: Die iOS-„Sprachwache“ (≤ 5 s gesprochen → Hauptsprache) betrifft nur automatische Spracherkennung;
  der Desktop schickt immer die feste Sprache (de/en) → dort kein Problem. Stille-Filter (Ursprung des iOS-Filters)
  wirkt: in Allans MacBook-Verlauf 21 reine „Vielen Dank“ vor v1.14.0, 0 in 200 Diktaten danach.
- **Behoben:** Die Modellliste fürs Polieren wurde erst nach dem Stopp seriell geholt, sobald die letzte Prüfung
  > 5 min her war (≥ 37 % von Allans Diktaten). Jetzt wird sie bei Aufnahmestart vorgeladen (wie iOS), nach dem
  Aufnahmestart und ohne Einfluss auf ihn. Echt gemessen: Stopp → polierter Text ~500 → ~200 ms. Text unverändert.
- 623 automatische Tests und TypeScript grün.
- Bewusst nicht übernommen (eigenes Projekt, nur auf Wunsch): Stücke-Upload während des Sprechens (iOS) — spart bei
  Diktaten > 30 s (27 % bei Allan, Median 16 s) ~0,5–1 s, ist aber ein Umbau im Diktat-Kern.

## v1.15.0 — Notes

- Allan hat nach dem MacBook-Test den GitHub-Push, das Release und die Aktualisierung seiner installierten App freigegeben. Grundlage: geprüfte `1.15.0-notes.2`, inklusive deutscher Y/Z-Korrektur.
- Neue Gedankenaufnahme mit eigener Pille, gemeinsames bearbeitbares Canvas, begrenzte Groq-Einordnung, Text-/Bild-Paste und optionale Screenshots. Cmd+Y für Aufnahme, Cmd+Alt+Y zum Öffnen, beides änderbar. Kein zusätzlicher API-Key nötig.
- [Release v1.15.0](https://github.com/qode-lab-wtf/paply/releases/tag/v1.15.0), Commit `946d240`, Tag und `main` gepusht. [GitHub-Build 40399124996](https://github.com/qode-lab-wtf/paply/actions/runs/40399124996): Mac, Windows und Veröffentlichung erfolgreich.
- Normale MacBook-App `/Applications/paply.app` aus dem tatsächlichen GitHub-Release auf **1.15.0** aktualisiert und gestartet. 13 Notes-Quellen mit 60 Dateien aus dem Testprofil übernommen; Kopie per Hashvergleich bestätigt. Produktionskonfiguration inklusive Groq-Key, Cmd+X und 1.300 Verlaufseinträgen unverändert; sämtliche Meeting-Dateien bytegleich erhalten. Startlog bestätigt Version 1.15.0 und aktiven uiohook-Listener.
- Sicherung von alter App und beiden Profilen auf dem MacBook unter `~/Library/Application Support/Paply Update Backups/1.15.0-20261026-215707`. Alter Schreibtisch-Teststarter dort archiviert; im Alltag die normale App verwenden. Das isolierte Testprofil und Testpaket bleiben erhalten.
- Download gegen `latest-mac.yml` geprüft. Release-`app.asar` identisch zum separat geprüften 1.15.0-Kandidaten: SHA-256 `9d961ce553e286634c99fa602ed01d963e80ccac245dbcf5bd8892c34ea736e2`. CI-Keymap-Helper `f360a94958407d21af09f29839fdeacb4aae66b0f527c04cb7a96901f0cfe1da` nach Übertragung geprüft; deutsche Y/Z-Zuordnung auf dem MacBook bestätigt.
- Releaseprüfung: 616/616 automatische Tests und TypeScript grün. Letzten Notes-Flush-Fehler beim nativen macOS-Beenden korrigiert; unabhängiger Test am echten 1.15.0-Paket bestätigt sauberes Beenden mit einem Aufruf (530 ms). [QA-Nachweis](notes/QA.md).

## Vorangegangene Notes-Testversion 1.15.0-notes.2 (26.10.2026)

- Nach MacBook-Praxistest korrigiert: Unter deutscher Tastatur löste die als Cmd+Y angezeigte Notes-Belegung tatsächlich auf Z aus (vom Nutzer bestätigt). Notes fragt jetzt über einen eigenen kleinen Carbon-Helfer die unmodifizierten Tastenbeschriftungen ab. Frische Defaults liegen auf dem gedruckten Y; Settings und Leerzustand zeigen die passenden Labels. Selbst gesetzte physische Kürzel bleiben erhalten. Diktat, gemeinsamer Shortcut-Parser, Pille und Audiofilter unverändert. 108 gezielte Tests und TypeScript grün. [QA-Nachtrag](notes/QA.md).
- `notes.2` auf dem MacBook gestartet, Testprofil und vorhandene Gedanken erhalten. Separat geprüft: deutsche Defaults, Beschriftungen und Erhalt eigener Kürzel; keine echte Tastensimulation. App-Hash `0ae8d939b1a9b1a6d2f04499268d49ecb809d9aeac10ec29c271b75df566ff85`, nativer Helfer `4b5c21f4201bea5c6c9f64e5f34a3b3d8b66c037b62be96cc616dbba56f49e61`; beide auf dem MacBook bestätigt. Starter auf dem Schreibtisch zeigt jetzt `1.15.0-notes.2`.

- Allans Auftrag umgesetzt: neue Gedankenaufnahme (Cmd+Y, änderbar), Öffnen per Cmd+Alt+Y, eigene Pille, ein gemischtes Canvas mit OpenUI/ReactFlow, Drag/Resize/Verbindungen, Edit/Copy/Delete/Undo und Text-/Bild-Paste.
- Recorder, Quelle/Board und begrenzte Groq-Queue getrennt. Audio wird lokal bestätigt gespeichert, bei geschlossenem Board verarbeitet; Diktat/Meeting hat Vorrang. Optionaler Screenshot und begrenzte Bildbeschreibung mit demselben Key.
- Vor-/Abschlussreview durch Opus 5.5 Extra High, separate echte Electron-QA. Gefundene Bugs korrigiert; 608 automatische Tests und TypeScript grün, 14 Paketprüfungen sowie gezielte Editor-/Transkript-/Tabellen-/Konfliktfälle bestanden. Opus-Nachprüfung mit lokaler Testfreigabe abgeschlossen; letzte empfohlene Korrekturen umgesetzt und im finalen Paket nachgetestet. [Implementierung](notes/IMPLEMENTIERUNG.md), [QA](notes/QA.md), [Reviewreaktionen](notes/REVIEW-ANTWORTEN.md).
- Lokaler Starter: `electron-menubar/dist/notes-test/Paply Notes testen.command`; Anleitung: [Notes testen](notes/TESTEN.md). Eigenes anfangs leeres Profil `~/.paply-notes-test`. Bei dieser Testübergabe erfolgten noch kein Tag, Push, Release oder Austausch der installierten Alltags-App; die spätere Releasefreigabe steht oben. Windows noch nicht praktisch vollständig abgenommen.
- MacBook-Übergabe (26.10.2026): Diese Entwicklungsumgebung läuft auf dem **Mac mini**, nicht auf Allans MacBook. Nach Korrektur der zunächst falschen Ortsangabe wurde das unverändert geprüfte Paket per `ssh macbook` nach `/Users/allanha/Applications/Paply-Notes-Test` übertragen und dort als `1.15.0-notes.1` gestartet. Starter auf dem MacBook-Schreibtisch: `Paply Notes testen.command`. Separates Profil `~/.paply-notes-test`; vorhandener Groq-Key und Diktatkürzel wurden ausschließlich auf dem MacBook in dieses Profil übernommen. Die installierte `/Applications/paply.app` bleibt 1.14.1 und wurde für den Test regulär beendet. App-Hash bestätigt; physischer Notes-Hotkey noch nicht bestätigt, Fernsteuerung über System Events ohne Hilfszugriff abgewiesen.

## v1.14.1 (21.10.2026)

- Diktat-Benchmark mit 16 echten Aufnahmen von Allan (Werkzeug `electron-menubar/tools/benchmark/`, Aufnahme nur
  wenn Ordner `benchmark` im Datenordner existiert). Ergebnis: Whisper turbo bleibt (schnell, gut; Fehler fast nur
  bei Fachbegriffen/Namen und Genuscheltem); large-v3 nicht besser, Gemini zu langsam/zu wenig Freikontingent.
- Polieren repariert: P2 „Kontext-Korrektur“ mit `qwen/qwen3.8-27b` (2,2 % riskante Änderungen bei freien
  Diktaten), letzte 3 Roh-Diktate (≤ 30 min) als Hintergrund, unsichere Whisper-Segmente markiert,
  Sicherheitsnetz (Länge, Inhaltswörter, Verneinung, Netto-Zusätze → Rohtext). Hörfehler wie „Push-to-Torque“
  behebt Polieren nicht — dafür optionale Wortliste „Eigene Begriffe“.
- Pille ~70 % mit CSS-Glas-Look, wärmerer Ton; Meeting-LLM `openai/gpt-oss-120b`.


## v1.14.0 — Abrunden für Mac + Windows (21.10.2026)

Allans Auftrag: App abrunden, Fehler raus, schneller, schöneres Design (Logo, Aufnahme-Animation),
Weitergabe an einen Freund mit Windows; alles gleichwertig für macOS und Windows.

- **Stille statt „Vielen Dank“:** Groq Whisper liefert bei Stille „Vielen Dank.“ (`no_speech_prob` ist bei
  Groq immer 0). Pegelmessung während der Aufnahme relativ zum Grundrauschen; ohne Sprache wird Groq gar
  nicht gefragt, typische Stille-Phrasen werden bei kaum Sprachaktivität verworfen. Echt diktiertes
  „Vielen Dank“ bleibt. Durchlauf-Test mit echten Groq-Aufrufen (Stille, Rauschen −50/−40 dB, Klick,
  laut/leise gesprochen, Satz) bestanden.
- **Meeting-Modus (Cmd+Shift+X) ausgeblendet:** standardmäßig aus, in den Einstellungen als „Beta“
  einschaltbar; Meetings und 7-Tage-Löschung bleiben.
- **Ersteinrichtung** für neue Nutzer (Groq-Schlüssel mit Prüfung, Mikrofon, Bedienungshilfen, Kürzel).
  Anleitung zum Weitergeben: `docs/WINDOWS-INSTALLATION.md`.
- **Robustheit Diktat:** Start/Stop-Rennen, Mikrofonfehler, parallele Diktate (Ziel-App pro Diktat),
  Einfüge-Fehler → „In Zwischenablage kopiert“, Polish schneidet nicht mehr ab, transaktionaler
  Kürzel-Wechsel, Single-Instance, keine Diktat-Texte im Log, Backups ≤ 24 h. Windows: Einfügen ins
  Ausgangsfenster + schneller (langlebiger Fokus-Helfer, Ctrl+V über uiohook).
- **Absturz behoben (schon in v1.13.1):** Ohne Bedienungshilfen-Recht brach uiohook die App auf dem Mac
  ab — betraf jeden neuen Mac-Nutzer beim ersten Start.
- **Tempo:** Aufnahme startet ohne Warten auf die Ziel-App-Ermittlung (Test: 20–80 ms statt ~250 ms);
  keine Google-Fonts mehr (Systemschrift).
- **Design:** Logo „p-Kopf“ (Opus-5.5-Entwurf B, von Allan gewählt), neue Icons für Dock/Menüleiste/
  Windows-Tray/Installer, Aufnahme-Pille „Echo“ mit Zeitanzeige, veredelter Start-/Stopp-Ton,
  Markenfarben.
- **Geprüft:** 451 automatische Tests grün; drei Opus-5.5-Reviews (Diktat-Kern, Integration, Gegenprüfung der
  Fixes) — Befunde behoben; echter Durchlauf in der Test-App (Fake-Mikrofon-WAVs + echtes Groq) für Stille,
  Rauschen, Klick, kurze Wörter („Danke.“, „Tschüss.“), „Vielen Dank“ laut/leise/Café und ganze Sätze;
  gepacktes Mac-App-Bundle gestartet und diktiert; CI-Builds Mac + Windows grün.
- **Behoben aus Reviews u. a.:** Windows-Auto-Update (Installer-Name passte nicht zu `latest.yml`, seit
  v1.13.1 kaputt), Test-App startete nicht neben installierter App, Agent-Wechsel während des Diktats,
  Kürzel-Erfassung mit ⌥ auf dem Mac (seit v1.13.1) und QWERTZ unter Windows, Backups/Wiederholen.
- Je Diktat stehen Pegel-Kennzahlen (`level`: speechMs/peak/floor, kein Inhalt) in der Historie — zum
  Nachjustieren des Stille-Filters, falls bei Allan im echten Raum doch ein „Vielen Dank“ durchrutscht.
- Bekannte Restpunkte: Fokus-Helfer unter Windows nur per Code/Tests geprüft (Praxistest beim Freund);
  bei Gruppenrichtlinie „AllSigned“ fügt Windows ohne Fokus-Wiederherstellung ein.

## Offen / braucht Allan

- Praxistest von Notes in v1.15.0 auf dem MacBook; Rückmeldung des Windows-Freunds (Einfügen, Tray, Pille, Notes).
- MacBook geprüft (21.10.2026, per `ssh macbook`, Benutzer `allanha`): dort liegt kein Paply-Repository
  (nur `~/Vibe/paply.dev`, anderes Produkt) → keine ungepushten Stände. App dort auf v1.14.0 aktualisiert,
  Einstellungen/Historie/Meetings erhalten.
- Stimmerkennung im Meeting-Modus (siehe unten) ruht, solange der Modus Beta ist.

## Ideen für die nächste Version (gesammelt, noch nicht beauftragt)

- **Verlauf-Aufbewahrung wählbar:** „Verlauf behalten: 7 / 30 / 90 Tage / immer“ (heute fest 90 Tage;
  Allan, 21.10.2026 — erst bauen, wenn weitere Punkte dazukommen).
- **Profile Coding / Meeting / Diktat prüfen** (Allan; seit v1.14.1 nutzen alle drei dieselbe vorsichtige Politur): Was tun sie, sind sie sinnvoll und gut gebaut (alt),
  mit neueren Modellen besser machen, einfach bedienbar — Allan ist faktisch immer auf „Coding“.
- **Stille-Messung robuster:** Pegel per AudioWorklet statt `setInterval` messen (bei ruckelnder Oberfläche
  fehlen sonst Messdaten → Filter greift nicht; im Test am Mac mini beobachtet, am MacBook 6/6 ok).
- Rückmeldung des Windows-Freunds einarbeiten (Einfügen, Tray, Pille, Ersteinrichtung).
- Windows: Hinweis im Log, wenn der Fokus-Helfer wegen Gruppenrichtlinie (AllSigned) nicht startet.
- Optional, ändert Verhalten (nur auf Wunsch): Zwischenablage nach dem Einfügen wiederherstellen;
  Schlüssel im Schlüsselbund verschlüsseln (bei unsignierter App Passwortabfragen nach Updates).

---

## Stand 22.09.2026 (v1.13.1)

## Bestätigtes Ziel

Siehe `docs/instinct/ZIEL.md`. Kurz: Diktat (Cmd+X) bleibt unverändert; Meeting per Cmd+Shift+X ohne
Konfiguration starten/stoppen, danach verständlicher Bericht mit Todos und darunter die Konversation;
kostenloser Betrieb. **Pflicht (Allan, 21.09.2026):** korrekte Personenzahl und korrekte Zuordnung
per Stimmerkennung.

## Was gilt

- **v1.13.0** ist auf GitHub veröffentlicht (Mac arm64/universal, Windows) — Build 35660413738 grün,
  Release mit DMG/ZIP/EXE und Auto-Update-Dateien. Allans installierte App holt das Update selbst.
- Meeting-Modus v2: Gemini-Audio (Alias `gemini-flash-latest`, Ausweich `gemini-flash-lite-latest`),
  Bericht v2, Nachhören ab Textstelle, Audio 7 Tage, Groq-Whisper-Fallback ohne Sprecher.
- Prüfung 21.09.2026 (Allans Mac, echte 3-Personen-Aufnahme, `scripts/meeting-analyze-wav.js`):
  Wortlaut gut, Bericht inhaltlich richtig; Sprecherzahl schwankt (3–4), Zuordnung wechselt zwischen
  Durchläufen. 140 automatische Tests grün.
- Praxistest v1.13.0 in der Alltags-App (22.09.2026, Allan, 2 Personen, 2 Aufnahmen): Gemini gab beide Male
  HTTP 503 (überlastet, alle -latest-Modelle), die App fiel auf Groq Whisper zurück → 1 Sprecher, schlechterer Wortlaut.
  **v1.13.1:** bei 5xx/429 wechselt Auswertung und Bericht auf `gemini-3.6-flash` → `gemini-3.5-flash`; kürzere
  Wartezeiten je Modell. Nachgeprüft an Allans Aufnahme 1790089914117-192z9h: 2 Sprecher (richtig), Wortlaut gut,
  Bericht über gemini-3.6-flash. Auto-Update in der App scheitert bei unsignierter App (bekannt) → DMG + `xattr -cr`.

## In Arbeit

Lokale akustische Stimmerkennung als Vorgabe für Gemini (Versuch: sherpa-onnx + pyannote-Segmentierung +
wespeaker-resnet34; bei Schwelle 0,7 drei Stimmen, aber stark schwellenabhängig). Es fehlt eine Aufnahme
mit bekannter Wahrheit: nächste Mehrpersonen-Aufnahme mit Namensansage („Ich bin …“) und/oder gelabelte
Forschungsaufnahmen (Download-Freigabe von Allan offen).

### Offen (Stand 22.09.)

- Praxistest v1.13.0 in der Alltags-App und Rückmeldung.
- „ok“ für den Download gelabelter Übungsaufnahmen (Stimmerkennung).
- Papierkorb leeren (`Paply_Codex_aufraeumen_2026-09-22`, `Paply_aufraeumen_2026-09-22`, ~44 GB).
- Nach Abschluss der Stimmerkennung: `~/.paply-test/` (gesicherte Testaufnahmen) entfernen.

## Aufräumen 22.09.2026 (ein Paply)

Entfernt: zweiter Projektordner `~/Vibe/paply-local-meetings` (Codex, 40 GB), Codex-Test-App + 27-GB-Modelle +
LaunchAgent, alte DMGs (Projekt `dist/`, Downloads), alte Web-Version (Next.js) im Repository-Hauptordner,
Zweige `codex/local-meeting-quality`, `claude/funny-hypatia-86wimp` (in main), `feature/meeting-recorder`,
`fix/meeting-mic-quality`, `claude/add-issue-creation-KPFtg` (paply.dev-Planung → `~/Vibe/paply.dev/docs/`),
`claude/evaluate-polishing-models-2MXQA` (überholter Windows-Signing-Fix). Codex-Unterlagen und
Messprotokolle liegen in `docs/archiv/codex-lokalversuch-2026-09-21/`.

## Ideen Android (Tester 29.10., noch nicht beauftragt)
- Konto bzw. Abgleich: Transkripte vom Handy auch am Laptop (Desktop-Paply). Das braucht einen Server oder Sync und
  widerspricht „Daten nur auf dem Gerät“. Allan entscheidet.
- Paply-Knopf in der Werkzeugleiste von Gboard bzw. Samsung-Tastatur: Fremde Apps können das nicht. Die Systemtaste unten
  in der Navigationsleiste ist der Weg.

