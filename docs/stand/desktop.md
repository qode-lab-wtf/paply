# Paply Mac und Windows — Verlauf

Übersicht aller Apps: [../STAND.md](../STAND.md).

## v1.15.3 — Gemeinsame Polier-Quelle (29.10.2026, veröffentlicht, MacBook installiert)

- Einziger System-Prompt unter `shared/polish/system-prompt.txt`, bytegleich im Desktop eingebettet;
  englisches JSON-Nachrichtenformat wie iOS/Android, eigene Begriffe normalisiert.
- Mobiles Sicherheitsnetz inklusive Zahlen, Selbstkorrekturen, kleinen Ersetzungen und Profilgrenzen
  portiert. Bei Ablehnung bleibt der Rohtext; Aufnahme, Cmd+X und Einfügen unverändert.
- 744 automatische Tests grün; 100 gemeinsame künstliche Testvektoren und Swift-JSON-Referenz sichern den Abgleich.
  Bekannte mobile Fehlablehnungen/heuristische Grenzen bleiben erhalten (siehe `shared/polish/README.md`).
- Allans Verlauf seit 21.10. (202 polierte Diktate, nur lokal ausgewertet): 24 schlechte Polituren würden jetzt
  gestoppt (z. B. „guter“→„besser“, „sicher“→„nie sicher“, „same day“ übersetzt, „60“→„60000“, „gepolisht“→„gepolst“),
  8 harmlose Grammatikkorrekturen gingen mit verloren (dann Whisper-Rohtext).
- iOS übernommen (feat/ios-v1, `SharedPolishTests`), Android folgt im eigenen Branch.

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
- Releaseprüfung: 616/616 automatische Tests und TypeScript grün. Letzten Notes-Flush-Fehler beim nativen macOS-Beenden korrigiert; unabhängiger Test am echten 1.15.0-Paket bestätigt sauberes Beenden mit einem Aufruf (530 ms). [QA-Nachweis](../notes/QA.md).

## Vorangegangene Notes-Testversion 1.15.0-notes.2 (26.10.2026)

- Nach MacBook-Praxistest korrigiert: Unter deutscher Tastatur löste die als Cmd+Y angezeigte Notes-Belegung tatsächlich auf Z aus (vom Nutzer bestätigt). Notes fragt jetzt über einen eigenen kleinen Carbon-Helfer die unmodifizierten Tastenbeschriftungen ab. Frische Defaults liegen auf dem gedruckten Y; Settings und Leerzustand zeigen die passenden Labels. Selbst gesetzte physische Kürzel bleiben erhalten. Diktat, gemeinsamer Shortcut-Parser, Pille und Audiofilter unverändert. 108 gezielte Tests und TypeScript grün. [QA-Nachtrag](../notes/QA.md).
- `notes.2` auf dem MacBook gestartet, Testprofil und vorhandene Gedanken erhalten. Separat geprüft: deutsche Defaults, Beschriftungen und Erhalt eigener Kürzel; keine echte Tastensimulation. App-Hash `0ae8d939b1a9b1a6d2f04499268d49ecb809d9aeac10ec29c271b75df566ff85`, nativer Helfer `4b5c21f4201bea5c6c9f64e5f34a3b3d8b66c037b62be96cc616dbba56f49e61`; beide auf dem MacBook bestätigt. Starter auf dem Schreibtisch zeigt jetzt `1.15.0-notes.2`.

- Allans Auftrag umgesetzt: neue Gedankenaufnahme (Cmd+Y, änderbar), Öffnen per Cmd+Alt+Y, eigene Pille, ein gemischtes Canvas mit OpenUI/ReactFlow, Drag/Resize/Verbindungen, Edit/Copy/Delete/Undo und Text-/Bild-Paste.
- Recorder, Quelle/Board und begrenzte Groq-Queue getrennt. Audio wird lokal bestätigt gespeichert, bei geschlossenem Board verarbeitet; Diktat/Meeting hat Vorrang. Optionaler Screenshot und begrenzte Bildbeschreibung mit demselben Key.
- Vor-/Abschlussreview durch Opus 5.5 Extra High, separate echte Electron-QA. Gefundene Bugs korrigiert; 608 automatische Tests und TypeScript grün, 14 Paketprüfungen sowie gezielte Editor-/Transkript-/Tabellen-/Konfliktfälle bestanden. Opus-Nachprüfung mit lokaler Testfreigabe abgeschlossen; letzte empfohlene Korrekturen umgesetzt und im finalen Paket nachgetestet. [Implementierung](../notes/IMPLEMENTIERUNG.md), [QA](../notes/QA.md), [Reviewreaktionen](../notes/REVIEW-ANTWORTEN.md).
- Lokaler Starter: `electron-menubar/dist/notes-test/Paply Notes testen.command`; Anleitung: [Notes testen](../notes/TESTEN.md). Eigenes anfangs leeres Profil `~/.paply-notes-test`. Bei dieser Testübergabe erfolgten noch kein Tag, Push, Release oder Austausch der installierten Alltags-App; die spätere Releasefreigabe steht oben. Windows noch nicht praktisch vollständig abgenommen.
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
