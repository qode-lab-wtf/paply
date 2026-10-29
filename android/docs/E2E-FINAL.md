# Paply Android 0.1.0 · Abschlussprüfung
29.10.2026 · HEAD `f7abcfe`, anfangs sauber; ausschließlich Tests und dieser Bericht geändert.
Release aus `PAPLY_WORK=rc … sync/release`, MacBook; kein Gradle auf dem Mac mini.
Signatur: apksigner erfolgreich, CN=Paply; Version 0.1.0 (1), nicht debuggable.
APK SHA-256: `1a00fd033175b90ffbb908abd7cc30e7e7e9ed14194fae2c6f9905107ad0dae9`.
Beide Apps vorher deinstalliert, dieselbe Release-APK frisch installiert; keine Debug-Produkt-APK.
Fremdeditor: externe `com.paply.android.test/.ImeFixtureActivity`; Sprache per authentifiziertem gRPC.
Belege: `/tmp/paply-android-final/`, ausschließlich `rc-*` und neue `evidence/*` gehören zu dieser Runde.
B=bestanden, F=Befund, T=Teilnachweis. Kein bestätigter Blocker; keine uneingeschränkte Abnahme wegen F1/F2.

| Punkt | Android 17 / paply:5580 | Android 14 / paply34:5610 |
|---|---|---|
| 1 Erster Start/Einzelschritte/Mikro abgelehnt→Öffnen | B `rc-5580-01-*`; 0/6, App-Einstellungen, Rechte einzeln | B `rc-5610-01-*`; gleicher Weg |
| 2 Key eingeben/prüfen | B `rc-5580-02-key.png` | B `rc-5610-02-key.png` |
| 3 Aktivieren/Systemwechsel/Tipps | B zwei Warnungen; 2 Tipps EN→DE→Paply, `rc-5580-03-*` | B zwei Warnungen; 2 Tipps Systemtaste→Paply, `rc-5610-03-*` |
| 4 DE kurz/lang, EN, Einsetzen/Auto-Rückwechsel | F1 DE; EN/Einsetzen/Rückwechsel B, `rc-5580-04-*` | B alle drei, `rc-5610-04-*`, Verlauf in `rc-5610-07-error.png` |
| 5 Stille/Durchschalten, kein Upload/Text | B Diagnose: speech=false, usable=false, kein dictation.saved/Upload dazwischen | B gleicher Nachweis, `14-diagnostics-before-reboot.txt` |
| 6 Passwort: keine Aufnahme | B `rc-5580-06-password.png`, Sperrpanel | B `rc-5610-06-password.png`, `14-password-audio.txt` |
| 7 Flugmodus/Verlauf/Retry | B `rc-5580-07-error-final.png`, `rc-5580-07-retry.png` | B `rc-5610-07-error.png`, `rc-5610-07-retry.png` |
| 8 Kachel/Zähler/Fertig/Titel/Thema/Aufgabe/Map/Detail | B `rc-5580-08-*`, Detail auch über kleines Widget geprüft | B `rc-5610-08-*`; Garten/Tomaten gießen/morgen 8 Uhr |
| 9 Gedanken-Home-Widget | B `rc-5580-09-*`; offline gespeichert, später verarbeitet | B `rc-5610-09-card.png`; gleicher Weg |
| 10 Aufgaben abhaken/widerrufen/Einladung/Benachrichtigung | B `rc-5580-10-*` | B `rc-5610-10-*` |
| 11 Aufgaben-Widgets klein/mittel: abhaken | B klein öffnet Detail zum Abhaken; mittel direkt 2→1, `rc-5580-11-*` | B klein über Detail; mittel direkt, `rc-5610-11-*` |
| 12 Beta aus: Kachel/Pause; an: weiter | B `rc-5580-12-*`, wartend bis nach Neustart/An | B `rc-5610-12-*`, gleicher Weg |
| 13 Drehen/Dunkel: Karte/Detail/IME | F2 IME; Karte/Detail dargestellt, `rc-5580-13-*` | B IME/Detail; T Karte: Querformat nur im verworfenen Zustand sicher belegt, `rc-5610-13-*` |
| 14 Neustart: Erinnerung/Warteschlange | B exakter Alarm nach Neustart; 1→2 Gedanken nach Beta-An | T 1→2 Gedanken B; offene Aufgabe bleibt, Erinnerung erst vor Neustart ausgelöst |
| 15 Logcat/FATAL/ANR/Mikro frei | B kein Paply-FATAL/ANR; Diagnose/Audiozustände, Schluss frei | B gleicher Nachweis |

## Reproduktionen und Grenzen
F1 · Android 17: Testname unter Eigene Begriffe; Fremdfeld→Systemtaste zweimal→Recorder aktiv.
`rc/scripts/inject-audio.py ~/Android/work/ime/.local/audio/testname.wav --wait 10`, Fläche beenden.
Vorlage: „Hallo Testname, ich komme heute etwas später, so gegen halb acht.“ (4,41 s).
Ergebnis: vollständiger Satz plus „I'll write to you later, bis morgen. Testname.“ (`rc-5580-04-short.png`).
Aufnahme insgesamt 29,28 s mit längerem stillen Vorlauf; Retry einer neuen kurzen Aufnahme korrekt.
Lang: `~/Android/work/final/.local/long.wav` (23,37 s), gleiche Schritte; „ungemütlich“ statt „gemütlich“,
Schluss „Film sehen“ statt „Film ansehen“ (`rc-5580-04-long.png`); kein fehlender ganzer Schluss.
Ein führendes `t` im langen Fremdfeld stammt vom Testbedienweg vor dem Diktat, nicht von Groq.
Android 14 erkennt dieselben deutschen Vorlagen korrekt. Englisch bleibt auf beiden englisch.
Dies sind Erkennungsbefunde im synthetischen Emulatorweg, kein belegter App-Pufferverlust.
F2 · Android 17: Fremdeditor erstes Feld→Paply aktiv→Porträt nach Querformat drehen.
Paply-Fläche verschwindet, Feld bleibt fokussiert; Mikro wird freigegeben (`17-ime-rotation-check.txt`).
Belege `rc-5580-13-ime-before.png`/`rc-5580-13-ime-after.png`; erneut mehrfach beobachtet.
Nur mit Stille geprüft: kein belegter Sprach-/Datenverlust; Fortsetzung einer gesprochenen Aufnahme offen.
Android 14 zeigt Paply im Querformat (`rc-5610-13-ime-stable.png`).
Umgebung: API-37-Pixel-Launcher-ANR, API-34-SystemUI-Absturz, UiAutomation-Registrierungsfehler;
keiner mit Paply-Prozess. Launcher nach ANR beendet; Test-Launcher für Widget-Platzierung zurückgesetzt.
Aufnahme-Karte über App/Kachel/Widget; zusätzliche stille Darstellungsaufnahmen verworfen.
Erinnerung über Einladung/exakte Systemfreigabe; Emulator-Uhr auf 30.10. 07:59:55 gestellt, Mitteilungen kamen.
Automatische Uhrzeit anschließend wieder eingeschaltet; keine zukünftige Erinnerung auf API 34 nach Neustart abgewartet.
Logcat ab Installation, bei ADB-/Neustarts wieder angehängt und Puffer nachgesichert; keine behauptete lückenlose Prozesskontinuität über Reboots.

## Budget, Artefakte, Abschluss
8 erfolgreiche Diktat-Pipelines inkl. 2 Retry, 8 Polierläufe; 4 Gedanken-KI-Läufe.
Gedanken-Transkriptionen laut Diagnose: API37 2+1, API34 1+1; regulär insgesamt 13 Online-Transkriptionen.
Zwei Offline-Versuche zusätzlich ohne Netz; kein weiterer Online-Sprachtest. Erste kurze Diktat-Stückzahl nicht mehr im 200er-Diagnosepuffer: Budgetzählung dort aus regulärem Einzelstück abgeleitet.
Key nur zur Laufzeit gelesen und per stdin ins Einstellungsfeld eingegeben; nicht ausgegeben/gespeichert im Repo.
APK + `.sha256`: `/tmp/paply-android-final/Paply-0.1.0.apk` (Mac mini).
MacBook: `~/Desktop/Paply-Android/Paply-0.1.0.apk` + `.sha256`, `FREUNDE.md`, `FREUNDE-NACHRICHT.txt`; Hashprüfung OK.
Buildbeleg `evidence/release-build.txt`; Diagnose vor/nach Reboots, Alarm-/Audiozustände, Logcat und Fehlerkontexte unter `evidence/`.
Beide Emulatoren am Ende per `adb emu kill` beendet; kein Commit, Push oder Publikations-Upload.
