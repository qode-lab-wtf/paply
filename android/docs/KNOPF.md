# Paply-Knopf · 0.2.0 (6)
Stand: 29.10.2026 · Korrekturen nach Emulator-Abnahme, Basis 4e9323b.
Nur unter android/ geändert; kein Emulator, kein Commit, kein Push.

## Behoben
- Overlay und IME verwenden Bildschirmkoordinaten: TOP|START, LAYOUT_IN_SCREEN,
  LAYOUT_NO_LIMITS, explizite Cutout-/Inset-Behandlung; Text vertikal zentriert.
- 44-dp-Knopf vollständig über dem IME-Fenster, mindestens 8 dp Abstand.
  Ziehen wird begrenzt, auch nach Drehen; ohne sicheren Platz bleibt er verborgen.
- Knopf-Hinweise stehen in der Pille statt in Toasts, 2,5 s + 220 ms Ausblenden.
  Reduce Motion wird berücksichtigt, Meldungen zu Mikro/Schlüssel/Einfügen gekürzt.
- 401/403 sperren den abgelehnten Schlüssel auch über Worker-Neustarts hinweg.
  Lokal liegt nur sein SHA-256-Fingerabdruck; erst ein anderer Schlüssel entsperrt.
- 429 wartet mindestens 15 Minuten; Netzfehler beginnen bei 30 s, exponentiell
  bis 10 Minuten. Persistierte Termine verhindern sofortige Wiederholungen.
- Die Gedanken-Karte beansprucht ihre Rückmeldung; keine zweite Meldung in der App.
- Einrichtung: Mikro → Benachrichtigungen → Groq → Paply-Knopf → Gedanken-Kachel
  (bei Gedanken-Beta). Tastatur nur als Alternative, zählt nicht zum Fortschritt.
  Der neue Knopf-Schritt ist auch nach Update von 0.1.4 offen, bis aktiviert.
- ButtonDeviceTest hat void-Testmethoden, zwingende Freigabe und nichtleeres expected;
  Bedienungshilfe vorher aus, Fremd-App force-stop + frischer Task, Zustand restauriert.
- expected unterstützt Alternativen wie komme|komm. Keine übersprungenen grünen Tests.

## Nachprüfung durch die Bauleitung (hier NICHT ausgeführt)
1. Gerätefreigabe/Host mit T3 device_list → device_open; dortigen Launcher verwenden.
2. API 30, 34, 37: APKs aus ~/Android/work/knopf2/app/build/outputs/apk/ installieren.
   Mikro erlauben, Gboard aktivieren, Schlüssel nur über private Übergabe setzen.
3. Klasse com.paply.android.button.ButtonDeviceTest, Runner
   com.paply.android.test/androidx.test.runner.AndroidJUnitRunner.
   Argumente paplyButtonAcceptance=yes, microphone=direct bzw. fgs,
   expected=komme|komm (passend zur extern eingespeisten echten Sprachaufnahme).
   Testmethoden einzeln wählen; WAV nach audio.start einspeisen (12 s Aufnahme).
4. foreignEditorWithRealMicrophone: beide Mikro-Wege, tatsächlichen Feldinhalt prüfen.
5. fieldChangeDuringRecording: zweites Feld bleibt leer, erwarteter Text im Clip.
6. rotateDuringRecording: Aufnahme/gesicherten Clip und Position nach Drehung prüfen.
7. dragRemainsAboveKeyboard: Drag nach unten; Abstand zur IME-Grenze wird geprüft.
   Zusätzlich nach oben, Hoch-/Querformat, Cutout, große Schrift manuell prüfen.
8. pasteRestoresClipboard nur API 30–32: Einfügung und alter Clip nach 800 ms.
   rejectingEditor: Feld bleibt leer, neues Ergebnis im Verlauf; API 30–32 auch Clip.
   API 33+ bestätigt commitText nur IPC; Ablehnung ist nicht zuverlässig erkennbar.
9. Benachrichtigungen verweigern: Mikro belegt, Stille, fehlender/ungültiger Schlüssel,
   Feldwechsel, manueller Paste-Hinweis müssen sichtbar sein und weich verschwinden.
10. Ungültiger Schlüssel bei Gedanken: genau ein Fehler, danach wartet auf Schlüssel;
    App neu öffnen/Netz wechseln erzeugt keinen neuen Upload. Neuer Key setzt fort.
    429/Netz-Ausfall: Wartezeit beachten, keine Dauerschleife.
11. Aus App Gedanken-Karte öffnen, speichern: „Gedanke gesichert“ genau einmal.
12. Update von 0.1.4: neuer Einrichtungsschritt offen, Tastatur kein Pflichtschritt.

## Builds (nur MacBook)
`PAPLY_WORK=knopf2 android/scripts/mb.sh sync`
`PAPLY_WORK=knopf2 GRADLE_TASKS=':core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:lintRelease' android/scripts/mb.sh build`
`PAPLY_WORK=knopf2 android/scripts/mb.sh release`
APK: /tmp/paply-android-release/Paply-0.2.0.apk, niemals Schreibtisch.
Tests: Koordinaten/Insets/Drag, Worker-Neustart nach 401/403, Backoff,
vorhandene Robolectric-Tests für Clipboard und Knopf-Policy. Geräteabnahme offen.
Ergebnis: 401 Core + 433 Thoughts + 133 App bestanden; 1 Core-Test übersprungen.
Debug-/AndroidTest-APK und Release erfolgreich; Lint: 0 Fehler, 78 Warnungen.
Signatur und lokale SHA-256 geprüft. Version bleibt 0.2.0 (6).
