# Paply Android 0.1.0 · Abschlussprüfung
Stand: 29.10.2026, 03:07 MEZ · läuft · Basis HEAD `f9323b9`.
Nur Tests/Dokumentation; kein Commit/Push/Veröffentlichen. Belege: `/tmp/paply-android-final/`.
MacBook vor Vorbereitung: 115 GiB frei. Release gebaut/signiert; API 34 installiert, AVD paply34 (Pixel 8, 4096 MB, Audio an) läuft auf 5610.
Device-Panel: Android auf lokalem Mac mini nicht verfügbar; Remote-ADB gemäß Projektanleitung.
Legende: B bestanden, F Fehler, O offen/nicht geprüft; keine Übernahme alter Testergebnisse.
| Punkt | Android 17 / API 37 | Android 14 / API 34 |
|---|---|---|
| 1 Installation/Einrichtung einzeln | O | O |
| 2 Schlüssel im Feld/Prüfen | B `17-02-key-valid.png` | O |
| 3 IME aktivieren/Systemwechsel/Tipps | B 2 Tipps (EN→DE→Paply), `17-03-*` | O |
| 4 Deutsch kurz/lang, Englisch/Rückwechsel | O | O |
| 5 Stille/Durchschalten | O | O |
| 6 Passwortfeld | B `17-06-password-paply.png` | O |
| 7 Flugmodus/Verlauf/Retry | B `17-07-history-error/retry-result.png` | O |
| 8 Kachel/Karte/Mitteilung/KI/Karte/Detail | O | O |
| 9 Gedanken-Home-Widget | O | O |
| 10 Aufgaben/Widerruf/Erinnerung | O | O |
| 11 Aufgaben-Widget klein/mittel | O | O |
| 12 Sprache/Begriffe/Beta/Pause | O | O |
| 13 Drehen/Dunkel Karte/Detail/IME | O | O |
| 14 Neustart/Erinnerung/Warteschlange | O | O |
| 15 Release-Logcat/Mikro frei | O | O |
Budgetplan: je Gerät kurz+Offline-Retry+Wortliste kombiniert, lang ≤3 Stücke, Englisch, Kachel = ≤6 Transkriptionen.
Widgetstart ohne weitere Sprache; KI ≤2, Polieren ≤6 insgesamt; tatsächliche Aufrufe laufend zählen.
## Befunde / Einschränkungen
Noch keine abgeschlossene Geräteprüfung; keine Freigabe aus diesem Zwischenstand.

APK: `Paply-0.1.0.apk` + `.sha256` im Belegordner; Hashprüfung OK, Buildlog `evidence/release-build.txt`.
Android 14 hat Gboard; beide Release-Installationen ohne Alt-App-Daten erfolgreich.
Zwischenbudget: Android 17 zwei erfolgreiche kurze Transkriptionen, zwei Polieraufrufe; offline ohne Netz.
Erkennungsabweichung Android 17: Vorlage „so gegen halb acht“ → Retry „so in halb acht“ (`17-07-retry-result.png`).
