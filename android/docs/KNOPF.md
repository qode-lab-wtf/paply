# Paply-Knopf · 0.2.0 (6)
Stand: 29.10.2026. Implementiert; Geräteabnahme ausdrücklich noch offen.
Kein Emulator gestartet, keine Instrumentierung ausgeführt, keine Groq-Aufrufe.
Die T3-Geräteregel erlaubt hier keine ersatzweise UI-Steuerung auf dem MacBook.

## Gebaut
- Accessibility-Overlay, 44-dp-Logo rechts über der Tastatur, vertikal verschiebbar.
- Gespeicherter Abstand, weiches Ein-/Ausblenden; System-Reduce-Motion wird beachtet.
- Nur aktives editierbares Nicht-Passwortfeld + IME-Fenster; kein Lesen von Feldinhalten.
- Tipp: Haptik/Aufnahme; Pille mit Pegel/Zeit, Tipp fertig, ✕ verwirft.
- Gleiche DictationSession/Pipeline wie IME: Sprachwache, Polieren, Begriffe, FLAC,
  Stücke-Upload, Verlauf, kein Live-Text/Pausen-Stopp; 9-Min.-Hinweis/10-Min.-Ende.
- Standard: direkter Recorder; bei Startfehler/Stummschaltung/1,8 s Null-PCM einmal FGS.
  Neustart nur ohne erkannte Sprache, mit Hinweis; Sprache bei Unterbrechung sichern.
- Feldwechsel, Sperren, Bildschirm aus: Mikro beenden, Ergebnis in Zwischenablage/Verlauf.
- Ab API 33 Accessibility-commitText, sonst ACTION_PASTE, sonst manuell einfügen.
- Kein ACTION_SET_TEXT/Readback. IPC-Erfolg heißt „gesendet“, keine Inhaltsbestätigung.
- Paste stellt nach 500 ms den vorherigen Clip wieder her, nur bei eigenem Besitzer-Token.
  Android kann Clip-Lesezugriff verweigern; deshalb am Gerät prüfen, kein Erfolg versprochen.
- Uncommitteter CaptureActivity-/Gedanken-Feinschliff unverändert übernommen.

## Schalter und Einrichtung
- Einstellungen/Einrichtung: „Paply-Knopf neben der Tastatur“ (standardmäßig aus).
- Ab Android 13: App-Info → ⋮ → Eingeschränkte Einstellungen zulassen, falls gesperrt;
  danach Bedienungshilfe einschalten. Live-Status und beide Einstellungslinks vorhanden.
- Paply-Tastatur bleibt unter „Alternativ: Paply-Tastatur“.
- Entwicklerseite: „Immer mit Mikrofondienst“: aus = direkt + Fallback, ein = FGS zuerst.
  Entwicklerseite wie bisher durch wiederholtes Tippen auf die Versionsnummer öffnen.

## Prüfung durch die Bauleitung – NICHT hier ausgeführt
1. MacBook als zulässigen T3-Gerätehost anbinden; device_list → device_open verwenden.
   Ohne gelieferten agent-device-Aufruf keine UI-Steuerung, auch nicht via Instrumentierung.
2. API 30 (`paply30`), 34 (`paply34`), 37 (`paply`) jeweils separat prüfen.
   Debug-APK + Test-APK aus `~/Android/work/knopf/app/build/outputs/apk/` installieren.
   Gboard/Systemtastatur auswählen, Bildschirmtastatur sichtbar, Mikro erlauben;
   vorhandenen Test-Key ausschließlich über die bestehende private Schlüsselübergabe setzen.
3. Vorbereiteter Test: `com.paply.android.button.ButtonDeviceTest` mit Runner
   `com.paply.android.test/androidx.test.runner.AndroidJUnitRunner`.
   Instrumentierungsargumente: `paplyButtonAcceptance=yes`, `microphone=direct`
   oder `microphone=fgs`, `expected=<bekanntes Wort der eingespeisten Aufnahme>`.
   Erst nach geklärter Gerätefreigabe über die erlaubte Testausführung starten.
4. Test schaltet per UiAutomation (DONT_SUPPRESS_ACCESSIBILITY_SERVICES) die Bedienungshilfe
   ein, startet das separate Fremd-Feld der Test-APK, fokussiert es und tippt den Knopf.
   Nach `audio.start` bekannte WAV per vorhandenem gRPC-Audioverfahren einspeisen;
   die Aufnahme läuft 12 Sekunden, dann tippt der Test fertig und prüft das erwartete Wort.
   Diensteinstellungen und Knopf-Schalter werden im finally wiederhergestellt.
5. Beide Mikro-Wege auf jeder API prüfen: sichtbare Pille, isClientSilenced/Pegel,
   Mikrofreigabe nach Fertig/✕; keine automatische zweite Einfügung bei IPC-Erfolg.
6. Manuell zusätzlich: Cursor mitten im vorhandenen Text, Markierung ersetzen,
   Passwort (kein Knopf/kein Mikro), Feldwechsel während Aufnahme und Verarbeitung,
   Tastatur schließen, Bildschirm aus, Drehen, Mikro gesperrt/belegt, fehlende Rechte.
7. Clip vorher befüllen, Paste auf API 30 prüfen: alter Clip nach 500 ms wieder da;
   währenddessen neu kopierten Fremd-Clip behalten. Ablehnenden Editor/manuell prüfen.
8. Stille, kurze Wörter, längere Sprechpause und 10 Minuten prüfen; Hinweise müssen erscheinen.
   Drag verdeckt keine Tasten; Reduce Motion, große Schrift, Hoch-/Querformat prüfen.
9. Testdaten/Schlüssel bei Bedarf entfernen. Erst nach Abnahme Release verteilen.

## Builds (nur MacBook)
`PAPLY_WORK=knopf android/scripts/mb.sh sync`
`PAPLY_WORK=knopf GRADLE_TASKS=':core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:lintRelease' android/scripts/mb.sh build`
`PAPLY_WORK=knopf android/scripts/mb.sh release`
Release nur unter `/tmp/paply-android-release/Paply-0.2.0.apk`, nicht auf dem Schreibtisch.
Unit-/Robolectric-Prüfungen: Sichtbarkeit, Einsetzreihenfolge/Fehler, Pille, Clip-Wiederherstellung.
Prüfergebnis: 300 Core + 431 Thoughts + 132 App bestanden, 1 Core-Test übersprungen.
Debug-/AndroidTest-APK, Release-Lint (0 Fehler, Warnungen vorhanden) und Release erfolgreich.
Signatur und lokale SHA-256 geprüft; neue API-33-Einsetzaufrufe sind per SDK-Guard geschützt.
