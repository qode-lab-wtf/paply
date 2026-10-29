# Paply-Knopf · 0.2.1 (7) – runder Aufnahmeknopf

Stand: 29.10.2026. Die folgenden Änderungen ersetzen die Pille; Einsetzlogik,
Mikrofonwege, Passwortschutz und 10-Minuten-Grenze bleiben erhalten.

- Ruhe: 48-dp-Kreis in Forest (#0F2C20), Paply-Marke; 72-dp-Touchfläche.
- Aufnahme: Kreis wächst weich auf 56 dp, drei transparente GreenBright-Ringe
  (#3AD879), maximal 71 dp Außendurchmesser. Pegel direkt aus AudioCapture.level,
  zeitbasierte exponentielle Glättung (120 ms), langsames Atmen (ca. 2,4 s).
  Eigene Canvas-View, ValueAnimator am Displaytakt, keine Layouts pro Animationsframe.
  Tipp: beenden/einsetzen. Links daneben separates X mit 48-dp-Touchziel.
- Verarbeitung: grüner Drehring (2,4 s); kein Zeit- oder Fertig-Text.
  Bestätigtes Senden: Haken für 650 ms, dann Ruhe. Bei commitText bleibt wie bisher
  die Grenze: IPC-Bestätigung ist kein Beweis, dass ein fremder Editor Text annimmt.
- Feste Overlayhöhe 72 dp, vollständig 8 dp oberhalb der stabilen Tastaturgrenze;
  Bildschirmkoordinaten, Cutout-Schutz und Verschieben unverändert. Der Knopf
  bleibt rechts stehen, X und Hinweise wachsen nach links.
- Animatoren stoppen bei Ausblenden/Detach/Zerstören. Systemweit abgeschaltete
  Animationen ergeben statische Zustände. Unveränderte Fensterkoordinaten lösen
  kein erneutes updateViewLayout aus.
- Erfolg und Verwerfen ohne Satz. Handlungs-/Fehlerhinweise stehen separat und
  verschwinden nach 4 s; neuer Start entfernt alte Hinweise.
- Zweitaufnahme: Die alte gemeinsame Label-View wurde vom Hinweis per
  ViewPropertyAnimator auf alpha=0 animiert. Ein gleich langer Coroutine-delay
  setzte alpha=1, ohne den erst am nächsten Frame fertig werdenden Animator zu
  stoppen. Dieser konnte danach erneut alpha=0 schreiben; Aufnahme-render()
  setzte nur Text/visibility zurück. Die konkurrierende Animation ist entfernt;
  Hinweise und Aufnahme haben getrennte Views. Kein Geräte-Repro hier ausgeführt.
- Regression: Unit-Test Start→Fertig→Haken→Ruhe, Start→Verwerfen→Ruhe,
  Start→Fertig→Haken→Ruhe; zusätzlicher Gerätetest für Sichtbarkeit, Zeichnung
  und TalkBack-Beschriftungen über dieselben Runden. Bestehende Gerätetests
  benutzen jetzt die Knopf-Beschriftung und klicken direkt den Knopf.

## Android-/Samsung-Verknüpfung

Die XML fordert weiterhin keinen Accessibility-Button an. Das fehlende
FLAG_REQUEST_ACCESSIBILITY_BUTTON verhindert keine vom Nutzer gewählte
System-Verknüpfung zum Ein-/Ausschalten des Dienstes. Die öffentliche API bietet
Paply keinen Schalter, um diese Nutzerzuordnung zu entfernen. Keine versteckten
APIs, keine Reflection. In der eingeschalteten Einrichtungskarte steht daher
der Hinweis auf das Ausschalten der „Verknüpfung“ (Dienst eingeschaltet lassen).
Die konkrete Zuordnung auf Allans S22 muss dort bestätigt werden.

Quellen (29.10.2026):
- [Android: Flag-Bedeutung](https://developer.android.com/reference/android/accessibilityservice/AccessibilityServiceInfo#FLAG_REQUEST_ACCESSIBILITY_BUTTON)
- [Android: Nutzer entfernt Verknüpfungen](https://support.google.com/accessibility/android/answer/7650693?hl=en)
- [Samsung: Verknüpfung in der Navigationsleiste](https://www.samsung.com/us/support/answer/ANS10001906/)
- [Öffentliche AccessibilityManager-API](https://developer.android.com/reference/android/view/accessibility/AccessibilityManager)

## Prüfung dieser Änderung

Build ausschließlich per android/scripts/mb.sh, PAPLY_WORK=work-knopf021:
:core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug
:app:lintDebug :app:assembleDebugAndroidTest.
Ergebnis: BUILD SUCCESSFUL, alle Unit-Test-Aufgaben und Lint grün (42 s).
Gerätetests nur kompiliert; keine Emulatorsteuerung und keine Groq-Aufrufe.
S22-Abnahme von Bewegung, Touch und mehreren Diktaten bleibt bei der Bauleitung.

---

## Vorheriger Abnahmestand (0.2.0)

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

## 0.2.1 – Knopf über dem Eingabefeld

Die Oberkante des fokussierten editierbaren Feldes (`getBoundsInScreen`, ohne
Textzugriff) bestimmt die Position bei kompakten Feldern: Feld-Unterkante höchstens
96 dp über der Tastatur, Feldhöhe höchstens 200 dp und oberhalb genügend Platz
bis `safeTop`. Dann sitzt der Knopf über dem Feld, auch im Querformat.
Sonst bleibt er über der Tastatur, niemals tiefer als bisher. Der gespeicherte
Zieh-Offset verschiebt ihn zusätzlich nach oben, begrenzt durch `safeTop`.
Wachsende Felder werden nach 150 ms stabiler Lage übernommen; Änderungen bis
4 dp werden ignoriert. Bei Fokuswechsel bleibt der bisherige Anker bis zur
Stabilität erhalten; beim ersten Erscheinen bleibt der Knopf maximal 400 ms
unsichtbar. Auch der Wechsel zum Tastatur-Anker bei großen Editoren wird stabilisiert.

Ruhe: 56 × 56 dp Fenster mit 48-dp-Knopf, ohne unsichtbare 72-dp-Touchfläche.
Start/Aufnahme: 120 × 72 dp einschließlich 48-dp-Abbrechen links; Verarbeitung
und Haken: 72 × 72 dp. Sichtbare Hinweise erweitern nur die benötigte Breite.
Die Position reserviert den 72-dp-Ringbereich mit 8 dp Abstand zum Feld bzw.
zur Tastatur; das Ruhefenster ist darin um 8 dp eingerückt (16 dp Abstand).
So bleibt der Mittelpunkt beim Größenwechsel unverändert. Größe und Position
werden gemeinsam mit einem `updateViewLayout` übernommen.

Prüfung auf dem MacBook über `scripts/mb.sh`, `PAPLY_WORK=work-knopf021`:
`:app:testDebugUnitTest :app:assembleDebug :app:lintDebug :app:assembleDebugAndroidTest`
alle grün (`BUILD SUCCESSFUL`, 26 s).
Neue Unit-Tests decken untere/obere Felder, mehrzeiliges Wachstum, Platzmangel,
Zieh-Offset, Stabilisierung, 4-dp-Toleranz und das Verwerfen alter Grenzen ab.
Keine Emulator-UI, keine Groq-Aufrufe. Geräteabnahme auf dem Samsung S22 bleibt
offen. Version unverändert 0.2.1 (7).

## 0.2.1 – Knopf-Reviewkorrekturen

- Jeder Zwischenablage-Rückfall wird ausdrücklich angesagt, auch neben dem Erfolgshaken;
  die reine Nachrichtenauswahl ist für alle 32 Kombinationen getestet.
- Bei 9:00 einmal System-Haptik und „Noch 1 Minute“ für 4 s, danach bis zum Ende
  dezente bernsteinfarbene Ringe; bei 10:00 nochmals Haptik und Verarbeitungshinweis.
  Die bestehende automatische 10-Minuten-Verarbeitung bleibt unverändert.
- Ziehen begrenzt den Offset auf den aktuellen Ankerbereich; neuer Schlüssel
  `field-offset-v1` ignoriert den alten 0.2.0-Offset.
- Unveränderte Renderdaten überspringen Layoutarbeit; Breiten setzen und Messen
  erfolgen nur bei Änderungen. Insets stammen ab API 30 aus Bildschirmmetriken,
  auf API 29 aus Display-Cutout und Systemressourcen (inklusive seitlicher Navigation).
- Tests sichern Ankerfälle, Fokuswechsel, 400-ms-Ersteinblendung, Zeitwarnungen,
  Insets und wiederholte Aufnahmerunden samt sichtbaren Renderzuständen ab.
  Der Gerätetest prüft den Animator am angehängten View (Ruhe/Aufnahme/Entfernen).

Prüfung: `PAPLY_WORK=work-knopf021 scripts/mb.sh sync`, anschließend über `mb.sh build`
`:app:testDebugUnitTest :app:assembleDebug :app:lintDebug :app:assembleDebugAndroidTest`.
Alle vier Aufgaben grün (`BUILD SUCCESSFUL`, 30 s).
Keine Emulator-Steuerung und keine Groq-Aufrufe; Gerätetest nur kompiliert.
Version bleibt 0.2.1 (7).

## 0.2.1 – Korrekturen aus der Emulator-Endabnahme

- API 33+: dieselbe reine Leerzeichenfunktion wie die IME; die Accessibility-
  Verbindung bietet `getSurroundingText(1, 0, 0)` statt `getTextBeforeCursor`.
  Das Zeichen vor dem kleineren Auswahlindex zählt (auch bei Rückwärtsauswahl).
- Position: Feld rechts/links, Tastatur rechts/links, dann freie Randpositionen;
  vollständige Overlayfläche gegen Feld und klickbare/editierbare Knoten prüfen.
  Falls alles belegt ist: zuerst Feldüberdeckung, dann übrige Überdeckung minimieren.
  Zieh-Offset ist bevorzugt, sichere Positionen haben Vorrang. Hindernisse nur nach
  Fenster-/Inhalts-/Geometrieänderungen, höchstens alle 150 ms, max. 160 Knoten und
  12 Ebenen; API 29–32 recycelt gelesene Knoten und Fenster.
- Drehung: 1,8 s Übergangsfrist; dasselbe Feld wird anhand Knotenidentität oder
  Paket + gemeldeter Ressourcen-ID wiedererkannt. Ohne sichere Zuordnung bleibt
  das Sichern in Verlauf/Zwischenablage. Hinweise erscheinen auch ohne Tastatur
  4 s unten über der Navigation, bei Hindernissen an einer freien Randposition.
- Positionswechsel: 180 ms Ease-out; bei abgeschalteten Animationen oder einem
  Hindernis im Bewegungsweg direkt zur sicheren Position. Kein dauernder Animator.
- Zwischenablage-Hinweise genau einmal; keine Kürzung auf bloßes „Einfügen“.
  Overlay ohne Tastaturfokus/Fokusrahmen, anklickbar und für TalkBack beschriftet.
- Gerätetests: Rotation verlangt Fortsetzung im selben Feld; Fixture mit echten
  Ressourcen-IDs, leeres Zielfeld erkennt auch API-34-Hinweistext. Fokusrahmen-
  und Accessibility-Prüfung im View-Gerätetest ergänzt.

Unit-Tests: Leerzeichen/Auswahl, fünf Platzierungsszenarien, Offset, volle Fläche,
freie Animationswege, begrenzte Rotationsfrist und eindeutige Zustellnachrichten.
Version bleibt 0.2.1 (7). Keine Emulatorsteuerung und keine Groq-Aufrufe;
Gerätetests werden ausschließlich kompiliert, erneute Geräteabnahme steht aus.

Abschlussprüfung ausschließlich über `scripts/mb.sh`, `PAPLY_WORK=work-knopf021`:
`:core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:lintDebug
:app:assembleDebugAndroidTest` vollständig grün (`BUILD SUCCESSFUL`, 31 s).
