# Paply — Stand

**Zeitpunkt:** 31.10.2026 · Alle Apps liegen in diesem Repository auf `main`. Verhalten: [`REGELN.md`](../REGELN.md).

## Überblick

| Funktion | Mac | Windows | iPhone | Android |
| --- | --- | --- | --- | --- |
| Diktat | Alltagstauglich, Allans tägliche App | Gebaut, Praxistest beim Freund offen | Bei Testern, Gerätetests offen | Bei Testern, jüngste App |
| Polieren | Standard an, Entwicklerbereich | Standard an, Entwicklerbereich | An | An |
| Sprachregel | Automatisch mit Gegenprobe | Automatisch mit Gegenprobe | Teilweise | Teilweise |
| Gedanken | KI-Regeln v6, Canvas (unveröffentlicht) | Wie Mac, ungetestet | Am weitesten (KI-Regeln v6) | Gleiche KI-Regeln, einfachere Verknüpfung |
| Aufgaben aus Gedanken | Ja (unveröffentlicht) | Wie Mac, ungetestet | Ja | Ja |
| Erinnerungen, Widgets | Fehlt | Fehlt | Ja | Ja |
| Gespräche | Beta, aus (Gemini) | Beta, aus | Beta, aus, erster Gerätetest läuft | Fehlt |
| Entwicklerbereich | Ja | Ja | Ja | Ja, ohne Polieren-Schalter |

## Begriffs-Gegenprobe (unveröffentlicht)

Alle drei Codebasen prüfen eigene Begriffe bei Diktat und Gedanken nach der Sprachwahl. Stille- und Echo-Filter laufen vor der Begriffs-Gegenprobe und auf dem endgültigen Ergebnis. Nur Klangtreffer mit mindestens drei Schlüsselzeichen und begrenztem Schreibweisen-Abstand lösen aus; kein Unsicherheitsmodus. Klangfenster und Restwort-Prüfung folgen den 28 gemeinsamen Fällen. Der Prompt nennt höchstens drei Kandidaten jeweils zweimal, ohne Begrüßung. Fenster-Schlüssel werden je Text für die Kandidaten geteilt. Lange Stücke behalten die erkannte Sprache, sofern die erwartete nicht mindestens 0,15 besser ist. Gespräche erhalten keine Begriffs-Gegenprobe. Regel-Version bleibt 6.

Review-Prüfung (31.10.2026): 936 Desktop-Tests, Vite und TypeScript; 748 Swift-Tests in 83 Suiten; iOS-App-Build auf dem MacBook bestanden. Android auf dem MacBook: 1.081 Tests (441 Core, 450 Gedanken, 190 App), Lint, Animal Sniffer der beiden Produktionsmodule und Debug-APK bestanden. Regelwächter: 13 Werte, keine neuen Ausnahmen.
Die 28 gemeinsamen Begriffsfälle und der Titel-Fall mit nur gemeinsamem Füllwort bestehen; iPhone und Android hatten den Inhaltswort-Schutz bereits.
200 Begriffe / 1.000 Wörter: 0,643 s lokal, 0,776 s auf dem MacBook (Debug, Testgrenze 5 s).
Echter isolierter Desktop-Lauf mit Anna: „Lawi Min“ → „Law Min“, „Herr Lehmann“ erhalten, 3 s digitale Stille ohne Text.

## Nachzureichen

- **Android:** Die hier ergänzten Desktop-Regressionen für Aufgaben-Zitate, Themen-Dubletten, Abschnittslimits und begrenzte Budget-Neuversuche gegen den mobilen Stand prüfen. iPhone verwendet bereits die Vorlagen; seine 30-Tage-Tonbereinigung ist jetzt ergänzt.

Eine Funktion, die nur in einer App gebaut wird, kommt hierher. So bleibt sichtbar, was den anderen fehlt.

- **Android:** Ton-Regel 8 für Gedanken und Gespräche mit sofortiger Löschung nach gespeichertem Text und maximal 30 Tagen bei Fehlern prüfen/nachziehen (Desktop umgesetzt).
- **iPhone, Android:** Desktop-Review-Korrekturen nachziehen/prüfen: Zeitgrenze der Gegenprobe, Sprachcode-Aliase und Schutz vor Primer-Echos sowie leeren Transkripten.
- **Android:** „Gespräche“, sobald das iPhone den Gerätetest bestanden hat (A8).
- **Mac, Windows:** Gespräche mit Besitzer-Erkennung und Aufgaben-Reiter wie auf dem iPhone (A9). Erinnerungen und Widgets.

## Mac und Windows

- **Gedanken-Endreview (31.10.2026, unveröffentlicht):** Link-Sicherheit und lokale Schwelle getrennt; Aufgaben mit bis zu 200 Zeichen langen, unscharf belegten Zitaten, mobile Textbereinigung und 5/10-Abschnittslimit. Budget-Neuversuch bleibt über Wartezeiten erhalten, Rückfall ist endlich und sichtbar; erfolglose Wiederholung schützt vorhandene KI-Ergebnisse. Themen-Dubletten, Titelbeugung/CJK, Eingabe-Aliase, eigene/erledigte Aufgaben und fehlender Ton korrigiert. Whisper-Begriffe, Meeting-Sprachkontinuität und Aufnahmehinweis nachgezogen. 878 Desktop-Tests, Vite, TypeScript und Regelwächter bestanden. Echter isolierter Lauf: 4 gesprochene Gedanken, 4 eingeordnet, 4 Aufgaben, 1 Verknüpfung, französischer Text und Titel erhalten; 9 HTTP-Anfragen (5 Whisper, 4 Einordnung), 10.447 Chat-Tokens. iPhone: 30-Tage-Tonbereinigung ergänzt, 743 Swift-Tests bestanden. Kein Release oder Windows-/GUI-Gerätetest.

- **Version:** v1.15.3, veröffentlicht, auf Allans MacBook installiert. 744 automatische Tests.
- **Quellstand (noch nicht veröffentlicht):** Sprach-Gegenprobe für Diktat, Notes und Groq-Meeting-Fallback; 62 Stille-Phrasen; Whisper large-v3 und Polieren standardmäßig an. Entwicklerbereich über fünf Versionsklicks. Bestehende Polier-Werte werden einmalig auf an migriert; danach bleibt die Entwicklerwahl erhalten.
- **Prüfung dieses Quellstands:** 774 Tests in 47 Dateien, Vite-Build, TypeScript und Regelwächter bestanden. Isoliertes echtes Diktat mit Anna/Thomas je zweimal: Deutsch und Französisch bleiben wörtlich erhalten, auch nach Polieren. Instrumentierter Lauf: 1 bzw. 2 Whisper-Anfragen. Bei identischem französischem Text in beiden Antworten speichert die vorgeschriebene Gleichtext-Regel die erwartete Sprache `de`. Entwicklerbereich in Electron einschließlich Persistenz und Ausblenden geprüft. Kein Windows-Gerätetest.
- **Desktop-Review (31.10.2026, unveröffentlicht):** Leere Meeting-/Notes-Ergebnisse schützen den Ton; Primer-Echos schützen das Diktat-Backup. Profile ändern die Hauptsprache nicht. Gegenprobe zeitlich begrenzt, Sprachcodes normalisiert, Notes-Modell korrekt gespeichert. 821 Tests in 48 Dateien, Vite-Build, TypeScript und Regelwächter bestanden. Regression gegen Ausgangscode: 30 erwartete Fehler in 103 gezielten Tests.
- **Gedanken v6 (31.10.2026, unveröffentlicht):** Gemeinsamer Prompt, 120b/20b, feldweise Prüfung mit Originaltext-Rückfall, Aufgabenansicht mit Besitzschutz, Hinweis bei 29 Minuten. Keine automatische Neuverarbeitung. 862 Tests in 49 Dateien, Vite-Build, TypeScript und Regelwächter bestanden. Echter isolierter Queue-/Groq-Lauf mit `say`: 3 Gedanken, 3 mit Text fertig, 1 Aufgabe mit Termin, unscharfer Gedanke ohne Thema. Französisch blieb im Text erhalten; zunächst übersetzter Titel durch lokale Belegprüfung abgesichert und mit einem expliziten Neuversuch bestätigt. Insgesamt 8 HTTP-Anfragen. Kein GUI- oder Windows-Gerätetest dieses Stands.
- **Offen:** Rückmeldung des Windows-Freunds, Electron-Upgrade.
- **Veröffentlichen:** [RELEASE.md](RELEASE.md). **Verlauf:** [stand/desktop.md](stand/desktop.md).

## iPhone

- **Version:** 0.1.0, TestFlight bis Build 7, Build 9 als Debug auf Allans iPhone. Letzter belegter Lauf: 723 PaplyKit-Tests.
- **Offen:** Gerätetests (Hauptsprache, Anrufe, Vibration, `idlePause`), Akku in Bereitschaft, „Gespräche“ mit echten
  Aufnahmen. Pilotmessung englische Meetings: 12–19 % der Wörter falsch oder unbekannt zugeordnet, noch keine Freigabe.
- **Veröffentlichen:** [ios/docs/TESTFLIGHT.md](../ios/docs/TESTFLIGHT.md). **Verlauf:** [stand/ios.md](stand/ios.md).

## Android

- **Version:** 0.2.1, als APK für Tester. Emulator-Abnahme API 30/34/36. Letzter belegter Lauf: 852 Tests (0.1.4).
- **Offen:** Echte Geräte (Pixel, Samsung), Anrufe, Bluetooth. „Gespräche“ gibt es noch nicht.
- **Veröffentlichen:** [android/docs/RELEASE.md](../android/docs/RELEASE.md). **Verlauf:** [stand/android.md](stand/android.md).

## So arbeiten wir

- `main` ist die einzige Wahrheit. Für jede Aufgabe ein kurzer Branch von `main`, nach dem Merge wird er gelöscht.
- Neue Stände stehen hier und im Verlauf der jeweiligen App, nicht in Branch-Notizen.
