# Etappe 2 B – Gedanken-Logik (28.10.2026)

JVM-Modul `:thoughts`, Paket `com.paply.thoughts`; Teil-A-Schnittstellen unverändert.
Nur `android/thoughts/**` und dieses Dokument geändert; kein Commit/Push, kein echter Groq-Aufruf.

## Zuordnung Swift → Kotlin
- `Thoughts/Local/*` → `local/{CandidateFinder,LocalIndex,Keywords,TopicIndex,Search,EmbeddingIndex}.kt`.
- `CandidateFinder` implementiert `CandidateFinding` und `KeywordFinding`; `TopicIndex` implementiert `TopicSummarizing`.
- `TopicMentions` und Snowball aus Teil A wiederverwendet; `DescribedTopicsTests` nutzt jetzt den echten Finder.
- `Thoughts/Map/MapLayout` → `map/{MapLayout,MapTypes,MapGeometry,MapLines}.kt`.
- `MapViewport`, `MapInbox`/`MapLandings`, `MapAnchorFile`/`MapAnchorState` → gleichnamige Dateien in `map/`.
- `Display/{TaskAgenda,TaskDigest,TaskReminderPlan,RawTitle,TopicColorRegister,TopicImageFile}` → `display/`.
- `Shared/TaskSnapshot` einschließlich Completion/WidgetSettings → `display/TaskSnapshot.kt`.
- Eigene `MapPoint/MapSize/MapRect` statt CoreGraphics; alle Zeiten als `Instant`, Kalender als `ZoneId`.
- Snapshot/Snooze-Codable verwendet Foundation-Sekunden seit 2001; Gedanken-JSON bleibt bei Unix-Millisekunden.

## Tests und Abweichungen
Zählung nach `@Test` (Parameterzeilen bleiben innerhalb des entsprechenden Tests).

| Suite | iOS | Kotlin | Abweichung |
|---|---:|---:|---|
| LocalTests | 14 | 14 | Snowball-Stämme; Binärdatei durch RAM-Neuaufbau/Refresh geprüft |
| MapLayoutTests | 37 | 37 | Gleicher LCG, Grenzfälle und Laufzeitgrenzen |
| MapInboxTests | 12 | 12 | Originalfälle |
| MapViewportTests | 8 | 8 | JVM-Geometrie statt CoreGraphics |
| MapAnchorFileTests | 5 | 5 | POSIX-Rechte, atomare Datei, Revisionen |
| TaskAgendaTests | 25 | 13 + 12 A | 13 hier; SpokenTime/DueDate bereits in Teil A |
| TaskReminderPlanTests | 20 | 20 | Originalfälle |
| TaskWidgetTests / Shared TaskSnapshot | 13 | 13 | Snapshot-Codable und Timeline enthalten |
| DisplayTests | 13 | 13 | TopicColorRegister 7, RawTitle 6 |
| TopicImageFileTests | 21 | 21 | JVM-ImageIO-Testadapter; Android-Codec separat zu integrieren |
| Lokale E0-Bewertung | Bench | 1 | Fixtures unverändert, Schwellen als Assertions |

156 portierte B-Fälle + 1 E0-Test; zusammen mit A **424 Tests, 0 Fehler, 0 übersprungen**.
MacBook-Lauf: `PAPLY_WORK=thoughtsb android/scripts/mb.sh sync`, danach
`PAPLY_WORK=thoughtsb GRADLE_TASKS=":thoughts:test" android/scripts/mb.sh build` → BUILD SUCCESSFUL.
Map-Leistung: Originalgrenzen 150 ms Erstlayout, 50/100 ms mit Ankern; Suche 50 ms eingehalten.
Keine Testfälle gelöscht; Apple-Lemmata etwa `besichtig`/`submission` → Snowball `besicht`/`submiss`.
Die beiden Binär-/Persistenzfälle prüfen nun Index-Neuaufbau, Änderungen/Löschen und fehlende `embeddings.bin`.
Bildtests: echte EXIF-Drehung, zentraler Zuschnitt, Weiß bei Transparenz, Größenlimit, Metadatenfreiheit;
GPS/Kamerafelder werden im Test als JPEG-Metadatenmarker eingespeist (kein Apple-ImageIO).

## E0: vor und nach der Keywords-Korrektur
Offline-Port von `CandidatesBench.swift` (lokaler E0-Einstieg von `ThoughtsEval.swift`).
40 Gedanken, 14 Themen, 36 Fälle; 11 Pflicht-Verwandte, 22 optionale, 29 bestehende Themen.

| Messung | Vorher | Nachher | Ziel |
|---|---:|---:|---:|
| Pflicht-Kandidaten gesendet | 10/11 | 10/11 | ≥ 10/11 |
| Pflicht in ersten 6 / optionale gesendet | 9/11; 18/22 | 9/11; 19/22 | – |
| Themen Top1 | 19/29 | 24/29 | ≥ 21/29 |
| Themen Top3 | 24/29 | 27/29 | ≥ 27/29 |
| Kandidaten je Fall, Mittelwert | 3,67 | 3,58 | höchstens 7 |

Vorherige Top1-Fehlfälle (Rang): e01(4), e06(9), e09(2), e10(2), e11(3), e12(14), e19(4), e20(2), e22(11), e33(2).
Danach: e01 Umzug(3), e06 Umzug(4), e12 Hochzeit Felix(14), e19 Lesen(2), e22 Garten(3).
Pflicht-Kandidat e33 bleibt ungesendet (Rang 28, Score 0); e01 wird über zeitliche Nähe gesendet.
Änderung: großgeschriebene deutsche Nomen ebenfalls stemmen, Originalnamen zusätzlich behalten;
geschlossene DE/EN-Funktionswörter vor dem Stemmen und Stoppwort-Stämme danach entfernen.
Ohne Sprachangabe beide DE/EN-Stämme. Keine Sonderregeln für Fixtures/Sätze; keine Embeddings.
Der Test gibt Pflicht-Ränge und alle Themen-Fehlfälle im Gradle-Testbericht aus.

## Schnittstellen für die App
- `TopicImageCodec`: Maße lesen, EXIF-orientiertes Thumbnail, zentralen Crop skalieren und frisches JPEG kodieren.
  Standard maximal 512 × 512, keine Vergrößerung, sRGB/Weiß, keinerlei Quellmetadaten übernehmen.
- `TopicImageFile` liefert Datei-/Merge-/Undo-Pläne; App führt Dateibewegungen aus und liefert vollständigen Themenstand.
- App übernimmt Benachrichtigungsberechtigung/Scheduling, Widget-Speicher und Completion-Queue; Kern liefert reine Pläne.
- App liefert Uhr/Kalender, optional `LanguageDetector`, Store und Map-Inputs; Pending-Gedanken separat im Eingang halten.
- `MapAnchorState`-Revision beim Übernehmen prüfen; bei unlesbarer Datei nie schreiben. Kamera nicht speichern.
- `LocalIndex`/Suche sind ableitbarer RAM-Zustand; `EmbeddingIndex.available=false`, `embed=null`, kein Modell/Download.
