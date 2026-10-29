# Paply-Knopf · 0.2.0 (6)
Stand: 29.10.2026 · Doppel-Einsetzen-Fix, Basis 43104fa.
Nur android/; kein Emulator, kein Commit, kein Push.

## Einsetzen
- API 29–32: ausschließlich den aktuell fokussierten, editierbaren Nicht-Passwort-
  Knoten beim Einsetzen lesen. Text/Auswahl bleiben lokale Variablen, ohne Logs.
- Hinweistext gilt als leeres Feld. Markierungen werden ersetzt; Leerzeichen
  vor dem Diktat folgen exakt der IME-Regel. Sonstiger Feldinhalt bleibt erhalten.
- ACTION_SET_TEXT setzt den Inhalt. Bestätigt refresh den gesamten erwarteten
  Text ohne Leerzeichen/Großschreibung, ist das Einsetzen erfolgreich.
  ACTION_SET_SELECTION ist nur Komfort; false oder Ausnahme ändert das nicht.
- Nach bestätigtem SET_TEXT gibt es niemals Paste oder Clipboard-Kopie. Bei
  verändertem, gekürztem oder nicht lesbarem Ergebnis bleibt der Status offen:
  „Bitte Text prüfen – liegt im Verlauf“. Die Zwischenablage bleibt unangetastet.
- Nur abgelehntes/nicht verfügbares SET_TEXT erlaubt den Paste-Rückfall
  (auch bei >5.000 Zeichen oder ungültiger Auswahl). Die Pille sagt dann
  „Text liegt auch in der Zwischenablage“; der alte Clip kann verloren gehen.
- Die Pille ist rechts mit 8 dp Rand verankert und wächst nach links. Gemessene
  Fensterbreite und Textbreite sind auf den sicheren Bildschirmbereich begrenzt;
  lange Texte laufen zweizeilig und werden bei Platzmangel mit Ellipse gekürzt.
- API 33+: unverändert commitText zuerst, dann bisheriger Paste-Rückfall.
- Tastaturgrenzen müssen mindestens 150 ms stabil sein, bevor die Pille erscheint.
  Während Änderungen wird sie sofort verborgen, ohne überlappende Ausblendung.
- Gedanken-Karte und Landkarte zeigen bei abgelehntem Schlüssel „ungültig“;
  ein tatsächlich fehlender Schlüssel bleibt als „fehlt“ gekennzeichnet.

## Nachprüfung durch die Bauleitung (hier NICHT ausgeführt)
1. Gerätefreigabe mit T3 device_list → device_open; gelieferten Launcher verwenden.
2. API 30: APKs aus ~/Android/work/knopf4/app/build/outputs/apk/ installieren.
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
8. Manuell: Feld >5.000 Zeichen → Clipboard-Hinweis; kürzendes Feld →
   „Bitte Text prüfen – liegt im Verlauf“, alter Clip unverändert.
   Tastatur öffnen/schließen, drehen, Drag nach unten: nie IME-Überlappung.
9. API 34/37: commitText-Verhalten sowie fieldChangeDuringRecording,
   rotateDuringRecording und dragRemainsAboveKeyboard als Regression prüfen.
10. Gedanken mit abgelehntem Schlüssel: Zeile, Karte und Landkarte konsistent
    „ungültig“; nach Neustart weiterhin gesperrt bis ein anderer Schlüssel kommt.

## Builds (ausschließlich MacBook)
`PAPLY_WORK=knopf4 android/scripts/mb.sh sync`
`PAPLY_WORK=knopf4 GRADLE_TASKS=':core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest :app:lintRelease' android/scripts/mb.sh build`
`PAPLY_WORK=knopf4 android/scripts/mb.sh release`
APK: /tmp/paply-android-release/Paply-0.2.0.apk, niemals Schreibtisch.
Tests: Textaufbau, Auswahl, Hinweistext, IME-Leerzeichen, 5.000-Zeichen-Grenze,
API-Reihenfolge, Aktionsfehler, Inhaltsprüfung, Clipboard-Rückfall, IME-Stabilität.
Geräteabnahme bleibt ausdrücklich offen.
Ergebnis knopf4: 401 Core + 433 Thoughts + 148 App bestanden;
1 Core-Test übersprungen, keine Testfehler. Alle oben genannten Build-Tasks grün.
Debug-/AndroidTest-APK und signiertes Release erfolgreich; Lint: 0 Fehler,
79 Warnungen (inklusive bewusst physischer Rechtsverankerung der Pille).
Release-Signatur und lokale APK-SHA-256 erfolgreich geprüft.
Neue API-30-Gerätefälle (nur gebaut): emptyFieldPreservesClipboardApi30,
hintFieldPreservesClipboardApi30 und cursorAtEndPreservesClipboardApi30.
Alle Einsetzfälle vergleichen den vollständigen Feldinhalt mit dem Verlauf;
Fixture-Knopfbeschriftungen werden ohne Beachtung der Großschreibung gesucht.
Version unverändert 0.2.0 (6).


## 0.2.1 – Einrichtung

Beim Samsung S22 (Android 16 / One UI 8, APK über WhatsApp) war die Anleitung
verkehrt herum: Bei seitengeladenen Apps ab Android 13 erscheint „Eingeschränkte
Einstellungen zulassen“ erst nach einem blockierten Einschaltversuch.

Jetzt zuerst „Bedienungshilfe öffnen“ → bei Samsung „Installierte Apps“ → Paply
→ einschalten (sonst meist „Heruntergeladene Apps“). Erst bei „Eingeschränkte
Einstellung“ die App-Info öffnen → ⋮ oben rechts → „Eingeschränkte Einstellungen
zulassen“, danach Schritt 1 wiederholen. Die Einstellungsseite hebt Paply nach
Möglichkeit hervor; öffentliche Settings-Intents bleiben der Rückfall.

Nach einem Versuch und Rückkehr mit ausgeschaltetem Dienst wird der App-Info-Knopf
hervorgehoben (ab Android 13). Bei eingeschaltetem Dienst verschwinden die Schritte;
Status-Haken und ein kurzer Fertig-Hinweis bleiben. Statusprüfung weiterhin alle
500 ms, zusätzlich sofort bei Rückkehr. Freundetexte und Version: 0.2.1 (7).

Prüfung ausschließlich über `scripts/mb.sh`, `PAPLY_WORK=work-setup021`
(MacBook: `~/Android/work/work-setup021`):
`:core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:lintDebug`
grün. 401 Core + 433 Thoughts + 153 App bestanden, 1 bestehender Core-Test
übersprungen; keine Testfehler. Lint: 0 Fehler, 78 Warnungen.
Neue Tests: Samsung-/Standardtext, beide Hervorhebungs-Extras sowie Rückfälle auf
Bedienungshilfe ohne Extras und allgemeine Einstellungen. Keine Emulator-UI und
keine Groq-Aufrufe; Geräteabnahme der Einrichtung bleibt bei der Bauleitung.
