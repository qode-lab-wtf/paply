# Paply — Stand

**Zeitpunkt:** 31.10.2026 · Alle Apps liegen in diesem Repository auf `main`. Verhalten: [`REGELN.md`](../REGELN.md).

## Überblick

| Funktion | Mac | Windows | iPhone | Android |
| --- | --- | --- | --- | --- |
| Diktat | Alltagstauglich, Allans tägliche App | Gebaut, Praxistest beim Freund offen | Bei Testern, Gerätetests offen | Bei Testern, jüngste App |
| Polieren | Standard aus | Standard aus | An | An |
| Sprachregel | Fest eingestellt | Fest eingestellt | Teilweise | Teilweise |
| Gedanken | Schwach: 4 von 19 Gedanken sauber eingeordnet (MacBook, 26./27.10.) | Wie Mac, ungetestet | Am weitesten (KI-Regeln v6) | Gleiche KI-Regeln, einfachere Verknüpfung |
| Aufgaben aus Gedanken | Fehlt | Fehlt | Ja | Ja |
| Erinnerungen, Widgets | Fehlt | Fehlt | Ja | Ja |
| Gespräche | Beta, aus (Gemini) | Beta, aus | Beta, aus, erster Gerätetest läuft | Fehlt |
| Entwicklerbereich | Fehlt | Fehlt | Ja | Ja, ohne Polieren-Schalter |

## Nachzureichen

Eine Funktion, die nur in einer App gebaut wird, kommt hierher. So bleibt sichtbar, was den anderen fehlt.

- **iPhone, Android:** Ton-Regel 8 für Gedanken und Gespräche mit sofortiger Löschung nach gespeichertem Text und maximal 30 Tagen bei Fehlern prüfen/nachziehen (Desktop umgesetzt).
- **Android:** „Gespräche“, sobald das iPhone den Gerätetest bestanden hat (A8).
- **Mac, Windows:** Gespräche mit Besitzer-Erkennung und Aufgaben-Reiter wie auf dem iPhone (A9). Erinnerungen und Widgets.

## Mac und Windows

- **Version:** v1.15.3, veröffentlicht, auf Allans MacBook installiert. 744 automatische Tests.
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
