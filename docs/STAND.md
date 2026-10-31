# Paply — Stand

**Zeitpunkt:** 31.10.2026 · Alle Apps liegen in diesem Repository auf `main`. Verhalten: [`REGELN.md`](../REGELN.md).

Die Tabelle zeigt den Stand von `main`. Veröffentlicht sind noch Mac und Windows v1.15.3, iPhone 0.1.0 und Android 0.2.1.
Alles von heute muss erst in eine neue Version.

## Überblick

| Funktion | Mac | Windows | iPhone | Android |
| --- | --- | --- | --- | --- |
| Diktat | Alltagstauglich, Allans tägliche App | Gebaut, Praxistest beim Freund offen | Bei Testern, Gerätetests offen | Bei Testern, jüngste App |
| Polieren | An | An | An | An |
| Sprachregel, kein Übersetzen | Ja | Ja | Ja | Ja |
| Eigene Begriffe mit Gegenprobe | Ja | Ja | Ja | Ja |
| Gedanken mit KI-Regeln v6 | Neu, Praxistest offen | Neu, ungetestet | Am weitesten | Gleiche Regeln, einfachere Verknüpfung |
| Aufgaben aus Gedanken | Neu, Praxistest offen | Neu, ungetestet | Ja | Ja |
| Erinnerungen, Widgets | Fehlt | Fehlt | Ja | Ja |
| Gespräche | Beta, aus (Gemini) | Beta, aus | Beta, aus, erster Gerätetest läuft | Fehlt |
| Entwicklerbereich | Ja | Ja | Ja | Ja |

## Nachzureichen

Eine Funktion, die nur in einer App gebaut wird, kommt hierher. So bleibt sichtbar, was den anderen fehlt.

- **Android:** „Gespräche“, sobald das iPhone den Gerätetest bestanden hat (A8).
- **Android:** Griff am Bildschirmrand (0.2.2), Abnahme läuft auf Branch `fix/android-knopf-rand`.
- **Mac, Windows:** Gespräche mit Besitzer-Erkennung und Aufgaben-Reiter wie auf dem iPhone (A9). Erinnerungen und Widgets.
- **Alle:** Sprachregel und Begriffs-Gegenprobe mit echten Stimmen prüfen. Gemessen wurde bisher nur mit künstlichen Stimmen,
  bei fremden Sprachen ganz, bei der Begriffs-Gegenprobe ebenfalls.
- **Repository:** Privat stellen, sobald Mac und Windows ihre Updates aus einem eigenen öffentlichen Download-Repository
  holen. Das geht mit dem nächsten Release, weil die installierten Apps die neue Adresse erst kennen müssen.

## Mac und Windows

- **Version:** v1.15.3, veröffentlicht, auf Allans MacBook installiert. `main`: 936 automatische Tests.
- **Offen:** Rückmeldung des Windows-Freunds, Electron-Upgrade.
- **Veröffentlichen:** [RELEASE.md](RELEASE.md). **Verlauf:** [stand/desktop.md](stand/desktop.md).

## iPhone

- **Version:** 0.1.0, TestFlight bis Build 7, Build 9 als Debug auf Allans iPhone. `main`: 748 PaplyKit-Tests.
- **Offen:** Gerätetests (Hauptsprache, Anrufe, Vibration, `idlePause`), Akku in Bereitschaft, „Gespräche“ mit echten
  Aufnahmen. Pilotmessung englische Meetings: 12–19 % der Wörter falsch oder unbekannt zugeordnet, noch keine Freigabe.
- **Veröffentlichen:** [ios/docs/TESTFLIGHT.md](../ios/docs/TESTFLIGHT.md). **Verlauf:** [stand/ios.md](stand/ios.md).

## Android

- **Version:** 0.2.1, als APK für Tester. Emulator-Abnahme API 30/34/36. `main`: 1.081 Tests.
- **Offen:** Echte Geräte (Pixel, Samsung), Anrufe, Bluetooth. „Gespräche“ gibt es noch nicht.
- **Veröffentlichen:** [android/docs/RELEASE.md](../android/docs/RELEASE.md). **Verlauf:** [stand/android.md](stand/android.md).

## So arbeiten wir

- `main` ist die einzige Wahrheit. Für jede Aufgabe ein kurzer Branch von `main`, nach dem Merge wird er gelöscht.
- Neue Stände stehen hier und im Verlauf der jeweiligen App, nicht in Branch-Notizen.
