# E3 Teil K – Landkarte der Gedanken

Stand: 29.10.2026; Compose-Port der iOS-Karte, kein Commit/Push, keine Groq-Aufrufe.

## Umsetzung
- Gedanken startet mit der Karte; Kopf-Schalter wechselt zur vorhandenen Liste und zurück.
- Suche öffnet ein gefundenes Thema direkt im Karten-Panel; Auswahl überlebt Detail-/Reiterwechsel.
- `ui/thoughts/map/`: Szene, Kamera/Gesten, Zeichenfläche, MapStyle und eigenes Themen-Panel.
- `MapLayout` rechnet auf Dispatchers.Default, ausschließlich bei geänderter Geometrie-Eingabe.
- Titel/Aufgaben/Bilder/Kamera lösen keinen Layoutlauf aus; Texte, Kugeln, Schein und Raster sind gecacht.
- Anker: `files/thoughts/map-anchors.json`, über MapAnchorFile/MapAnchorState, revisionsgeprüft.
- Unlesbare Ankerdateien werden nicht überschrieben; Kamera und Gesten ändern keine Anker.
- Themenfarben/Bilder verwenden den bestehenden TopicAppearanceProvider und TopicColorRegister.
- Additives `ThoughtsRepository.mapTopics()` liefert auch zusammengeführte Aliasse zur Zielauflösung.
- Eingang: laufende/wartende Gedanken getrennt von „Ohne Thema“, Status aus MapInboxStatus.
- MapLandings steuert zeitlich begrenzte Flüge; keine dauerhafte Zeichen-Schleife im Ruhezustand.
- „Weitere Themen“ und Panel verwenden exakt MapLayout.collected; keine zusätzlichen/fiktiven Linien.
- Kamera: Fokus, Pinch um Fingermitte, Pan, Gummiband, Schwung, Doppeltipp, Übersicht-Rückkehr.
- Panel: klein/mittel/groß, Ziehen/Schließen, offene Aufgaben, Detail-/Aufgabensprung, Themenaktionen.
- Groß: lazies zweispaltiges Mauerwerk; große Schrift: eine Spalte, Aufgabenfälligkeit unter dem Text.
- Tabs und Aufnahme bleiben frei; bestehende Karten, Aufgaben-Checkoff und Widerruf werden wiederverwendet.
- MapStyle folgt Hell/Dunkel des Systems; Panel/App-Leisten behalten iOS-Wald, Einrichtung bleibt kontrastreich.
- TalkBack: Themenname, Anzahl, offene Aufgaben, Auswahl und Aktion; Panel mit Standard-/Größenaktionen.
- Android „Animationen entfernen“ wird live beachtet; keine Kamera-, Panel- oder Eingangsanimation bei 0.

## Prüfung
- Build: assembleDebug, lintDebug, testDebugUnitTest und assembleDebugAndroidTest auf MacBook.
- Sechs MapScene-Unit-Tests: Eingang/Aliasse/Links, 300/30-Sammlung, Persistenz, Cache, Leseschutz, Kamera.
- Debug-Beispiele erweitern E2 offline auf 40 Gedanken/14 Themen, einschließlich lokalem Beispielbild.
- Separater Belastungsdatensatz: 300 Gedanken/30 Themen; keine Änderungen in android/thoughts/**.
- Gerät: ausschließlich paply2, emulator-5590; Installieren/Fotos über PAPLY_WORK=map und mb.sh.
- App: 89 Unit-Tests grün, davon 6 MapScene; Lint und beide Debug-APKs grün.
- Vier Gerätetests grün: Karten-Navigation/Gesten/Raststufen sowie E2-Liste/Detail/Original/Themenwahl/Aufgaben.
- Echte Zwei-Finger-MotionEvents, Pan/Doppeltipp und Anker-Unveränderlichkeit geprüft.
- Fotos: `/tmp/paply-android-e3/map-*.png` (Hell/Dunkel, Fokus/Panel/Liste/Eingang/Sammlung, 200 % Schrift).
- 21 geprüfte PNGs (1080 × 2424) und beide Debug-APKs im Fotoordner; Protokolle unter `evidence/`.
- Ankerdatei nach App-Neustart und zusätzlichem `adb shell input swipe` bytegleich.
- Bei großer Schrift liegt Karte/Liste im Mehr-Menü; Panel bleibt einspaltig, Animationen bei System-Skala 0 aus.
- 300/30, Debug, paply2 mit temporärem `-gpu host`: 640 Frames, Median 17 ms, P95 19 ms, P99 31 ms.
- Leistungsprobe: `ThoughtMapDeviceTest#profileStressGestures` (`-e profile true`), sechs Runden nach Warm-up.
- Jank: 76/640 (11,88 %; Legacy 4,06 %), CPU-Zeichnen Median 3,28 ms/P90 5,06 ms; ein Layoutlauf.
- Zahlen: `gfxinfo-stress.txt`, `gfxinfo-stress-framestats.txt`, `layout-profile.txt` im selben Fotoordner.
- Standardstart nutzt SwiftShader: Median 300 ms unter paralleler Hostlast; Software-Rendering ist hier kein FPS-Beleg.
- GPU-Nachweis auf demselben AVD/Port, ohne Skriptänderung; SwiftShader-Rohdaten liegen daneben.
- Temporärer GPU-Start auf MacBook: `emulator -avd paply2 -port 5590 -no-window -no-snapshot-save -gpu host`.

- `paply2` nach Abschluss mit `PAPLY_AVD=paply2 ~/Android/emu-stop.sh` beendet; Port 5590 getrennt.

## Offen
- Physisches Gerät/OEM und manuelle TalkBack-Sprachausgabe bleiben Geräteabnahme.
