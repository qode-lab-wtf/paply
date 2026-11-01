# Paply — Stand

**Zeitpunkt:** 1.11.2026 · Alle Apps liegen in diesem Repository auf `main`. Verhalten: [`REGELN.md`](../REGELN.md).

Die Tabelle zeigt den Stand von `main`. Mac und Windows 1.16.0 sind Vorabversion und nur auf Allans MacBook, die übrigen
Nutzer bleiben bis zur Freigabe auf 1.15.3. iPhone: Build 10 auf Allans iPhone und bei TestFlight. Android bleibt bei
Testern auf 0.2.1, die neue Sprachregel kommt dort mit 0.2.2.

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
- **Alle:** Fremde Sprachen und die Begriffs-Gegenprobe mit echten Stimmen prüfen. Beides ist bisher nur mit künstlichen
  Stimmen gemessen. Echter Lauf am 1.11.: 9 von 9 Sätzen in fünf Fremdsprachen blieben in Originalsprache und -schrift,
  auch nach dem Polieren.
- **Repository:** Privat stellen, sobald die installierten Apps auf 1.16 oder neuer sind. Ab dieser Version holen sie
  ihre Updates aus dem öffentlichen Repository `qode-lab-wtf/paply-downloads`.

## Wunschliste

Ideen für später, noch nicht gebaut. Die Reihenfolge ist keine Rangfolge.

- **Übersetzen als Schalter, für alle Apps:** In den Einstellungen wählt man zwischen Originalsprache und Übersetzung in
  eine gewählte Sprache. Standard bleibt die Originalsprache. Beispiel: Wer in der Muttersprache spricht, aber auf
  Deutsch schreiben will, bekommt deutschen Text. Bis dahin gilt „Paply übersetzt nie“ aus `REGELN.md`.
- **Konto, für alle Apps:** Ein Konto-System, damit Einstellungen wie dieser Schalter pro Person gelten.

## Mac und Windows

- **Version:** 1.16.0 als Vorabversion, auf Allans MacBook installiert. Für alle gilt noch 1.15.3. `main`: 936 automatische Tests.
- **Offen:** Allans Test von 1.16.0, danach Freigabe. Rückmeldung des Windows-Freunds, Electron-Upgrade.
- **Veröffentlichen:** [RELEASE.md](RELEASE.md). **Verlauf:** [stand/desktop.md](stand/desktop.md).

## iPhone

- **Version:** 0.1.0, Build 10 auf Allans iPhone und zu TestFlight hochgeladen. Tester stehen auf Build 7, bis Build 10 der
  Gruppe „Testing“ zugewiesen ist. `main`: 748 PaplyKit-Tests.
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
