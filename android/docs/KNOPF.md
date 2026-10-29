# Paply-Knopf · 0.2.0 (6)
Stand: 29.10.2026 · letzte Korrektur, Basis 2f8e8e6.
Nur android/; kein Emulator, kein Commit, kein Push.

## Einsetzen
- API 29–32: ausschließlich den aktuell fokussierten, editierbaren Nicht-Passwort-
  Knoten beim Einsetzen lesen. Text/Auswahl bleiben lokale Variablen, ohne Logs.
- Hinweistext gilt als leeres Feld. Markierungen werden ersetzt; Leerzeichen
  vor dem Diktat folgen exakt der IME-Regel. Sonstiger Feldinhalt bleibt erhalten.
- ACTION_SET_TEXT setzt den Inhalt, ACTION_SET_SELECTION den Cursor dahinter.
  Danach refresh und Vergleich des gesamten Texts ohne Leerzeichen/Großschreibung;
  auch gekürzte Ergebnisse zählen als Fehlschlag.
- Mehr als 5.000 Zeichen, ungültige Auswahl, abgelehnte Aktion oder negative
  Prüfung: Paste-Rückfall. Die Pille sagt „Text liegt auch in der Zwischenablage“.
  Dieser Rückfall behält das Diktat im Clip; der alte Clip kann verloren gehen.
- API 33+: unverändert commitText zuerst, dann bisheriger Paste-Rückfall.
- Tastaturgrenzen müssen mindestens 150 ms stabil sein, bevor die Pille erscheint.
  Während Änderungen wird sie sofort verborgen, ohne überlappende Ausblendung.
- Gedanken-Karte und Landkarte zeigen bei abgelehntem Schlüssel „ungültig“;
  ein tatsächlich fehlender Schlüssel bleibt als „fehlt“ gekennzeichnet.

## Nachprüfung durch die Bauleitung (hier NICHT ausgeführt)
1. Gerätefreigabe mit T3 device_list → device_open; gelieferten Launcher verwenden.
2. API 30: APKs aus ~/Android/work/knopf3/app/build/outputs/apk/ installieren.
   Mikro erlauben, Gboard aktivieren, Schlüssel nur über private Übergabe setzen.
3. Klasse com.paply.android.button.ButtonDeviceTest, Runner
   com.paply.android.test/androidx.test.runner.AndroidJUnitRunner.
   Argumente paplyButtonAcceptance=yes, microphone=direct bzw. fgs,
   expected=komme|komm (passend zur extern eingespeisten Sprachaufnahme).
   Methoden einzeln wählen; bekannte WAV nach audio.start einspeisen (12 s).
4. cursorInsertionPreservesClipboardApi30: Fixture belegt alten Clip, setzt
   „Anfang Ende“, Cursor nach „Anfang“. Ergebnis muss exakt an dieser Stelle
   stehen, inklusive erhaltenem Präfix/Suffix; alter Clip bleibt unverändert.
5. selectionReplacementPreservesClipboardApi30: „ ALT“ wird markiert und ersetzt.
   Gesamter Feldinhalt wird gegen das Diktatergebnis geprüft; alter Clip bleibt.
6. foreignEditorWithRealMicrophone: leeres Feld mit Hinweistext, beide Mikro-Wege.
   Zusätzlich Cursor am Anfang/Ende und Auswahl in echter Xiaomi-App nachprüfen.
7. rejectingEditor: Ablehnung von SET_TEXT und Paste; Ergebnis bleibt im Verlauf
   und Clip. Pille muss „Text liegt auch in der Zwischenablage“ anzeigen.
8. Manuell: Feld >5.000 Zeichen und kürzendes Feld → Clipboard-Hinweis prüfen.
   Tastatur öffnen/schließen, drehen, Drag nach unten: nie IME-Überlappung.
9. API 34/37: commitText-Verhalten sowie fieldChangeDuringRecording,
   rotateDuringRecording und dragRemainsAboveKeyboard als Regression prüfen.
10. Gedanken mit abgelehntem Schlüssel: Zeile, Karte und Landkarte konsistent
    „ungültig“; nach Neustart weiterhin gesperrt bis ein anderer Schlüssel kommt.

## Builds (ausschließlich MacBook)
`PAPLY_WORK=knopf3 android/scripts/mb.sh sync`
`PAPLY_WORK=knopf3 GRADLE_TASKS=':core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:lintRelease' android/scripts/mb.sh build`
`PAPLY_WORK=knopf3 android/scripts/mb.sh release`
APK: /tmp/paply-android-release/Paply-0.2.0.apk, niemals Schreibtisch.
Tests: Textaufbau, Auswahl, Hinweistext, IME-Leerzeichen, 5.000-Zeichen-Grenze,
API-Reihenfolge, Aktionsfehler, Inhaltsprüfung, Clipboard-Rückfall, IME-Stabilität.
Geräteabnahme bleibt ausdrücklich offen.
Ergebnis: 401 Core + 433 Thoughts + 143 App bestanden; 1 Core-Test übersprungen.
Debug-/AndroidTest-APK und signiertes Release erfolgreich; Lint: 0 Fehler,
78 Warnungen. Release-Signatur geprüft; lokale SHA-256-Prüfung erfolgreich.
Version unverändert 0.2.0 (6).
