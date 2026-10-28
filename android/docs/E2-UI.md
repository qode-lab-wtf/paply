# E2 Teil U – Gedanken-Oberfläche

Stand: 29.10.2026, Compose-Port der iOS-Vorlage; kein Commit/Push.

## Bildschirme

- Gedanken: kompakter Beta-Kopf, Einrichtung, Suche, Filter, Datumsabschnitte, Themenkopf und offene Aufgaben.
- `ThoughtMapSlot` ist der ausdrücklich vorgesehene Listen-Ersatz; `:thoughts/map` bleibt unberührt.
- Detail: Thema, Datum, bearbeitbarer Titel/Text, Status, Aufgaben, Verwandte und ausklappbares Original.
- Original enthält ausschließlich auswählbaren Rohtext; kein Audio-Player.
- Themenwahl, Neuanlage, Editor mit Beschreibung (200 Zeichen), 24 Symbole und Android Photo Picker.
- Themenverwaltung: aktive/vorläufige Themen, Behalten, Bearbeiten, Entfernen, Mehrfachauswahl/Zusammenführen.
- Hygiene-Vorschläge mit ausdrücklicher Bestätigung; Ablehnen speichert das abgelehnte Paar.
- Verknüpfen, Verbindungen lösen, Papierkorb, Wiederherstellen und bestätigtes endgültiges Löschen.
- Aufgaben-Reiter: Überfällig/Heute/Demnächst/Irgendwann/Erledigt, Herkunft, Bearbeiten, Teilen, Löschen/Widerrufen.
- Abhaken zeigt sofort den Zustand, speichert nach 1,2 s und überlebt den Reiterwechsel; zweiter Tipp widerruft.
- Leerer Start, Android-Anleitung für Kachel/Home-Widget, Aufnahme-Knopf und kompakte Aufnahme-Leiste/Echo.
- Echo übernimmt Wolkenformen, Pegelglättung und Ring-Zeitwerte aus iOS; reduzierte Bewegung stoppt Drehung/Ringe.
- Teilen nutzt das Android-Share-Sheet; Kopieren die System-Zwischenablage.

## Bewusste Plattformanpassungen

- Android-Systemschrift statt SF Rounded; Dokumenttitel 22 sp, vorhandene Paply-Typografie/Farben weiterverwendet.
- Native Compose-Blätter/Dialogs, Android-Zurück und Material-Navigation statt iOS-Glas/Zoom/System-Undo per Schütteln.
- Wald-Darstellung auch im hellen Systemmodus, wie die iOS-Vorlage; beide Systemdarstellungen werden fotografiert.
- Kachel und Home-Widget ersetzen Sperrbildschirm/Kontrollzentrum/Aktionstaste.
- Frisches sRGB-JPEG: EXIF-Drehung, mittiger quadratischer Zuschnitt, maximal 512 px, Weiß unter Transparenz.
- Bilder gehen nie an Netz/KI. Farbplätze und Bilder folgen Zusammenführungen; Widerruf stellt sie wieder her.
- Wartegrund, Fehler-Neuversuch und Audio-Ablaufdatum folgen E2-SERVICE (höchstens 30 Tage).

## Additive Repository-Funktionen

- `renameTopic`, `setTopicIcon`, `setTopicNote`, `keepProvisional`, `updateTopic`, `deleteTopic`.
- `mergeTopics` mit bedingtem Widerruf; `acceptSuggestion`, `declineSuggestion`.
- `addTask`, `editTask`, `deleteTask` mit Widerruf; `addLink`, `removeLink`.
- `reorganize`, `purgeAllDeleted`, `finishRecording`.
- `makeSearchIndex`, `search`, `topicColorSlots`, `topicImages`, `setTopicImage`; private Datei-/Farbhelfer.
- Nutzeränderungen verwenden ausschließlich den Kernstore; bestehende Verarbeitungsfunktionen nicht ersetzt.

## Prüfung und Übergabe

- Build ausschließlich auf dem MacBook mit `PAPLY_WORK=ui2`; Emulator ausschließlich `paply2`, Port 5590.
- Debug-Beispiele: `ThoughtsUiDeviceTest#seedExamples` im Debug-Test-APK; kein produktiver Debug-Einstieg.
- Beispiele umfassen Themen, Aufgaben, Verknüpfungen, Fehler, Warten und Papierkorb; ohne Groq-Schlüssel/Aufrufe.
- 88 PNGs (44 Hell/Dunkel-Paare) unter `/tmp/paply-android-e2/ui-*.png`; Prüfprotokolle unter `evidence/`.
- Gesamtbau: `assembleDebug`, `assembleDebugAndroidTest`, `lintDebug`, `testDebugUnitTest` erfolgreich.
- 64 Unit-Tests grün; 9 Offline-Gerätetests auf `paply2` grün (Repository, Codec und echte UI-Interaktionen).
- 30 Bildschirmzustände je Systemmodus plus Aufnahmeleiste fotografiert und gegen die iOS-Quellen geprüft.
- Aufnahmeleiste nutzt im Screenshot eine Debug-Zustandsattrappe; Mikrofon und Service bleiben dabei aus.
- Nativer Photo Picker, Share-Sheet und Zwischenablage zusätzlich geprüft; gespeichertes Bild: 512 × 512, EXIF leer.
- Startseite/Aufgaben/Detail mit 200 % Schrift und ausgeschalteten Animationen geprüft.
- APKs: `/tmp/paply-android-e2/paply-e2-ui-debug.apk` und `paply-e2-ui-tests.apk`.
- `paply2` um 00:53 Uhr mit dem vorgegebenen Stop-Skript beendet; Port 5590 anschließend nicht mehr verbunden.

## Offen

- Landkarte folgt durch den nächsten Helfer; der benannte Slot und die Karten-Kernlogik sind vorbereitet.
- Physisches Android-Gerät/OEM-Verhalten bleibt die spätere Geräteabnahme.
