# Paply Android 0.1.0 · Abschlussprüfung
Stand: 29.10.2026, 02:31 MEZ · abgebrochen nach dem vereinbarten 20-Minuten-Wartefenster.
Getestete APK aus `f9323b9`; nur Tests/Dokumentation, kein eigener Commit/Push/Veröffentlichen.
Während der Runde wechselte der Worktree extern auf `8dac5a5`; neuere Commits/parallele Produktcodeänderungen sind nicht Teil dieser APK-Abnahme.
Keine Freigabe: Runde unvollständig, Deutsch-Erkennung auffällig.
Belege unter `/tmp/paply-android-final/`; Dateinamen in der Tabelle relativ dazu.
B = bestanden, F = Befund, T = teilweise bestanden, O = offen; keine alten Abnahmen übernommen.

| Punkt | Android 17 / API 37, paply:5580 | Android 14 / API 34, paply34:5610 |
|---|---|---|
| 1 Installation/Einrichtung einzeln | T frisch, Mikro/Mitteilungen/Key/IME; Kachel offen (`17-01-*`, `17-07-history-error.png`) | T frisch, Mikro/Mitteilungen/Key/IME; Kachel offen (`14-01-*`, `14-02-*`, `14-03-*`) |
| 2 Schlüssel im Feld/Prüfen | B `17-02-key-valid.png` | B `14-02-key-valid.png` |
| 3 IME aktivieren/Systemwechsel/Tipps | B 2 Tipps EN→DE→Paply (`17-03-switch-*.png`), später 1 ab DE | B 2 Tipps: Systemtaste→Paply im Picker (`14-03-picker.png`) |
| 4 Deutsch kurz/lang, Englisch/Rückwechsel | F Deutsch, B Einsetzen/Auto-Rückwechsel/Englisch (`17-04-*-result.png`), F1/F2 | O alle Sprachproben |
| 5 Stille/Durchschalten | T Feld leer/automatisch Gboard (`17-05-silence.png`); Null-Upload-Zähler offen | T Feld leer/automatisch Gboard (`14-05-*`); Null-Upload-Zähler offen |
| 6 Passwortfeld | B Sperrpanel (`17-06-password-paply.png`) | B Sperrpanel (`14-06-password.png`) |
| 7 Flugmodus/Verlauf/Retry | B Fehler→Retry mit Text (`17-07-history-error.png`, `17-07-retry-result.png`) | O |
| 8 Kachel/Karte/Mitteilung/KI/Landkarte/Detail | O | O |
| 9 Gedanken-Home-Widget | O | O |
| 10 Aufgaben/Widerruf/Erinnerung | O | O |
| 11 Aufgaben-Widget klein/mittel | O | O |
| 12 Sprache/Begriffe/Beta/Pause | T Deutsch/Englisch eingestellt, Testname im Retry; Beta offen | T Deutsch/Englisch manuell/Hauptsprache Deutsch, Wortliste eingegeben; Anwendung/Beta offen |
| 13 Drehen/Dunkel Karte/Detail/IME | O | O |
| 14 Neustart/Erinnerung/Warteschlange | O | O |
| 15 Durchgehendes Release-Logcat/Mikro frei | T Mikro nach Diktaten frei (`evidence/17-ime-after-audio.txt`); Gesamtauswertung offen | O Gesamtauswertung; Passwortpanel ohne Mikrosymbol |

## Genaue Reproduktionen und Grenzen
F1 · Android 17, kurzer Online-Satz: `~/Android/work/ime/.local/audio/testname.wav` (4,41 s).
Vorlage: „Hallo Testname, ich komme heute etwas später, so gegen halb acht.“
Gboard→Paply; aktiven Recorder per dumpsys bestätigt; `scripts/inject-audio.py … --wait 10`; Panel tippen.
Ergebnis im Fremdfeld: „Ich kürte etwas später, so gegen halb acht.“ Anfang einschließlich Name fehlt.
Beleg `17-04-short-result.png`; dieselbe Vorlage offline gespeichert→App-Retry erkennt Testname,
ändert aber „gegen“ zu „in“ (`17-07-retry-result.png`). Wortliste Testname war eingetragen.
F2 · Android 17, langer Satz: dieselben Schritte mit `~/Android/work/final/.local/long.wav` (23,37 s Sprache).
Mit macOS Anna, Rate 145 synthetisiert; Vorlage unter `evidence/sprachvorlagen.txt`.
Ergebnis enthält u.a. „Abendessen verbreiten“, „kommenden Baum“, „Blumen und Raskis“; Schluss fehlt/ersetzt.
Beleg `17-04-long-result.png`; Text wird eingesetzt und automatisch zu Gboard zurückgewechselt.
Beide Funde gelten für den synthetischen gRPC-Emulatorweg; Ursache App/Erkennung/Audioeinspeisung ungeklärt.
Englisch (7,09 s, `ime/.local/audio/english.wav`) vollständig englisch eingesetzt, Auto-Rückwechsel bestätigt.
Fremd-App ist die unveränderte separate Test-APK `com.paply.android.test` (ImeFixtureActivity), kein Produkt-Testhook.

## Artefakte, Budget und Wiederaufnahme
MacBook vorher 115 GiB frei; API-34-Google-APIs-arm64 installiert, Pixel 8/4096 MB/Audio an, Standardstart 5610.
Beide Geräte haben Gboard (API 34: 12.4.05.482060964); keine AOSP-Ausweich-Tastatur nötig.
Release auf MacBook via `PAPLY_WORK=final … sync/release`; R8/Signatur OK, nicht debuggable, Version 0.1.0 (1).
APK `Paply-0.1.0.apk` + `.sha256` lokal vorhanden; SHA-256-Abgleich OK, Buildlog `evidence/release-build.txt`.
SHA-256: `2232b6ae6772d943330627f8da13fb4ca4d384b3db4389ac767b88e1c8495020`.
Schlüssel nur zur Laufzeit aus Desktop-Konfiguration gelesen, per stdin ins Einstellungsfeld, nie ausgegeben.
Budget bisher: 4 erfolgreiche Online-Diktate inkl. Retry; regulär ≤6 Stück-Transkriptionen, 4 Polierläufe, 0 Gedanken-KI.
Genaue HTTP-/Fallbackzahl nicht belegt; vor weiteren Groq-Tests Diagnose prüfen, keinen Restverbrauch als bestätigt ansehen.
Release logcat läuft seit Installation remote unter `~/Android/work/final/.local/final-evidence/{17,14}-logcat.txt`.
02:08 MEZ SSH-Ausfall (`Operation timed out`), auch Tailscale-Ping ohne Antwort; Logs nicht abgeholt.
Keine bestätigte Kachelaufnahme; API-34-Neustart mit gRPC wurde wegen SSH-Ausfall nicht bestätigt.
Lokal liegen 32 PNGs und Teilbelege; vorrangig 8–15 auf beiden, 4/7 auf API 34, Rest von 1/5/12 nachholen.
Beide Emulatoren zuletzt laufend; letzter sichtbarer Zustand: API 37 Gboard, API 34 Passwort-Sperrpanel.
Stoppen und Gesamt-FATAL/ANR-Prüfung waren ohne SSH nicht ausführbar; Emulatoren konnten nicht gestoppt werden.

Wiederverbindung: 8 Versuche 02:11–02:28 MEZ, jeweils Timeout, 150-s-Takt; 20-Minuten-Fenster bis 02:31 MEZ beendet.
Nachweis: `evidence/ssh-reconnect.txt`; kein weiterer Retry-/Testprozess nach Ende, kein eigener Commit/Push.
