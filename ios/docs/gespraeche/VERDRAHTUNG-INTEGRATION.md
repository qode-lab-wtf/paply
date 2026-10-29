# Gespräche – App-Verdrahtung

## Anschlussstellen

- `ConversationsEnvironment`: gemeinsame Ablage unter `Application Support/Gespraeche`, eigener Ledger, Schlüsselbund über `AppSettings`, Sprache und Vokabular. Start, Vordergrund, Netz, Schlüssel, Abschluss und Import stoßen denselben Processor an. Geschützte Daten werden erst nach Freigabe gelesen.
- `ConversationRecordingBridge`: echter `ConversationStore`, sofortiger Gedanke mit gleicher ID; auch verworfene Aufnahmen sind gemeinsam wiederherstellbar. Der alte Aufnahme-Stub ist gelöscht.
- `ConversationBackground`: persistierte Warteschlange für BGProcessing, Abbruch bei Ablauf. Processor-Ereignisse liefern zahlenbasierten Fortschritt und inhaltsfreie Live-Activity-Stufen, nur für die passende Aufnahme.
- `ConversationsModel`: Ablage-/Processor-Ereignisse, bedarfsgeladener Wortlaut, Profile, Aktionen über `ConversationEditing`, Teilen mit `ConversationText.render`, Abschnittswiedergabe. Die Wiedergabe setzt weder Audio-Kategorie noch Audio-Modus; die bestehende Sitzung bleibt allein zuständig.
- `ConversationsTab` und `ConversationDetailHost`: reine Views mit echten Daten und Aktionen. Gemeinsame Themenwahl und `TaskCheckoff`; vorhandenes Gedanken-Detail leitet Gespräche um. Löschen, Wiederherstellen, endgültiges Löschen sowie Thema samt Gedanken löschen nehmen die Gesprächsablage mit.
- `RootView`: unabhängiger Beta-Schalter, Deep Links und Import, Vollbildaufnahme und gemeinsame Aufnahmeleiste; ab der vorhandenen iOS-26.1-Accessory-Freigabe im Tab-Zubehör, sonst als unterer Einsatz.
- `ConversationEnrollment`: 20 Sekunden über denselben Sitzung-Mithörer, temporäre WAV wird nach Abschluss oder Abbruch gelöscht. Keine zweite Mikrofon-Sitzung.

## On-Device-Motor (29.10.2026)

- FluidAudio ist auf `e15287985625dbf544a343df679436789ffb03fb` gepinnt. Nemotron-3 fast128 FP16 liest die WAV in 10-s-Blöcken; der Adapter hält nur offene Turns und fertige Intervalle (50 ms Mindestturn). Acht Slots; eine exakte Vorgabe `expectedSpeakers` unterstützt dieser Motor nicht.
- CoreML darf alle Rechenwerke wählen; bei Fehlern wird mit frischem Zustand GPU/CPU, danach CPU versucht. Auf A12–A14 beginnt der Adapter mit GPU/CPU, um eine problematische ANE-Kompilierung des Monolithen zu vermeiden. Die gemessen fehlerhafte W8A8-Variante ist bewusst kein Rückfall. Eine zusätzliche Split-FP16-Variante wurde nicht auf Geräten geprüft.
- CAM++ liegt als rund 14-MB-CoreML-Paket im PaplyKit-Ressourcenbundle. CPU-Inferenz; Swift-Fbank mit 80 Bändern, Povey, 20–7600 Hz, gespiegelten Randfenstern und Mittelwertabzug. Feste 800 Frames; kürzere reine Sprachstücke werden zyklisch verlängert. Je Cluster bis zu fünf lange, von Überlappung bereinigte Ausschnitte; normierter Mittelwert nach Medoid-Ausreißerprüfung. Einzelabdruck nur bei mindestens 8 s dominanter Sprache und mindestens 90 % Anteil.
- Profile: feste Zuordnung ab 0,80 und mindestens 0,10 Abstand sowohl zum nächsten Profil als auch zum nächsten Cluster. 0,65 bleibt lediglich ein bestätigungspflichtiger Vorschlag. Enrollment-Ausreißer unter 0,60 gegen das Medoid werden ab drei Clips entfernt. Pilotwerte, keine unabhängige Freigabe der Falschzuordnungsrate.
- Beim ersten Reiterbesuch oder Aufnahmestart lädt eine Hintergrund-URLSession die unveränderlichen Nemotron-Dateien (HF-Revision und SHA-256 je Datei in `ConversationModelManifest`). Resume-Daten bleiben bei unterbrochenem Download erhalten; jede Datei wird vor Freigabe geprüft. Ablage unter Application Support, vom Backup ausgeschlossen. Danach offline. Statuszeile mit Fortschritt/erneut versuchen; ohne Modelle liefert der Analyzer einen unsicher markierten Wortlaut und lässt die Sprecherstufe offen. Modellbereitschaft stößt die Warteschlange erneut an.
- Bearbeitung und Einsprechen rufen jetzt `ConversationProcessor` bzw. `VoiceProfileStore.enroll` auf. Lernstand kommt aus `learningStatus()`. Startup/Processor führen den vorhandenen Löschabgleich aus; Änderungen am verknüpften Gedanken benutzen `synchronizeLinkedThought`.
- Lizenzseite am Ende der Einstellungen enthält Apache-2.0, OpenMDW 1.1, Herkunftshinweise und mitgelieferte Third-Party-Lizenzen. Der Entwicklerknopf verarbeitet die letzte verfügbare Gesprächsaufnahme. Er protokolliert Hardwarekennung als Zahlen, Laufzeit/RTF, Prozess-RSS-Spitze und Sprecherzahl; **die tatsächliche CoreML-Platzierung ist nicht beobachtet** (`computePlacementKnown=0`). RSS ist die Prozessspitze, keine isolierte ANE-/GPU-Speichermessung.

Konvertierung, Paketversionen und Paritätsnachweis: `ios/tools/gespraeche-bench/cam-coreml/`. Die Tastatur und Widgets haben weiterhin keine PaplyKit-/FluidAudio-Abhängigkeit. Keine Änderungen am Diktat.

## Prüfung der Motor-Integration

698 Tests in 74 Suites mit `swift test --no-parallel` grün; App Debug und Release mit dem beauftragten `xcodebuild -target Paply -sdk iphoneos`, ohne Signierung und Asset-Katalog, grün. `-scheme Paply` konnte auf diesem Mac keine Destination finden; `-target Paply` löst die Paketabhängigkeit erfolgreich auf. Keine FluidAudio-/Nemotron-/CAM-Symbole in Tastatur oder Widgets gefunden.

Entpacktes Release-App-Bundle: 51,80 MiB statt 18,88 MiB im unveränderten HEAD, Zuwachs 32,92 MiB (kein IPA-Messwert). Nemotron-Download: 199.096.435 Bytes; CAM++ liegt im Bundle. FluidAudio bringt in diesem Xcode-Build trotz eingeschränktem Trait auch ein G2P-Ressourcenbundle mit; dessen Lizenzhinweise sind enthalten.

Mac-E2E: 600 s AMI → vier Sprecher, 30,77 s, 417,6 MB maximaler Prozess-RSS; 300 s deutsche Mischung → drei Sprecher, 4,91 s, 145,4 MB RSS. AMI-E2E vor der letzten Fbank-Randkorrektur; danach finaler lokaler Lauf über alle 1049,35 s: vier Sprecher, 11,84 s, 78,3 MB RSS. Die Sprecherintervalle sind zum gescorten Lauf exakt gleich: WDER 19,47 % mit Scorer-v4-Glättung (Pilot: 19,4 %). Warme Caches und teilweise parallele Build-Last; Prozess-RSS erfasst nicht den gesamten CoreML-Systemspeicher. Groq insgesamt 20 Audiominuten und 6.393 LLM-Tokens; keine weiteren Aufrufe. Rohdaten und temporäre Konvertierungsumgebung werden entfernt, bestehende Modelle bleiben erhalten.

Die Gerätemessung benötigt eine letzte Gesprächsaufnahme. Sie meldet die tatsächliche ANE-/GPU-Platzierung noch als unbekannt. iPhone-Freigabe, Download-Fortsetzung nach Prozessende, Jetsam, thermische Last und vollständige Offline-Wiederaufnahme sind auf realen Geräten zu prüfen; kein Nachweis für alle iOS-18-iPhones allein durch diese Mac-Läufe.

Messzahlen: `ios/tools/gespraeche-bench/cam-coreml/integration-results.json`; Parität/Herkunft: `provenance.json` daneben.

## Frühere Prüfung der App-Verdrahtung

Debug und Release mit dem beauftragten `xcodebuild` ohne Signierung/Asset-Katalog; PaplyKit vollständig mit `swift test --no-parallel` (671 Tests). Der normale parallele Swift-Testing-Lauf war mit 669 Tests zunächst grün; spätere Läufe mit 671 Tests zeigten die lastabhängigen Bestandsfehler `rateLimitedKeyIsValid` und einmal `cancelAbortsRunningChunkUploadImmediately`. Die neuen VAD-Tests bestanden in allen Läufen. Keine echten Groq-Aufrufe.

Auf dem iPhone offen: Wiedergabe mit aktiver/ruhender Diktat-Bereitschaft und Bluetooth, sofortiger Aufnahmewechsel, Anrufunterbrechungen, gesperrter Start, Hintergrund-Ablauf/fortgesetzte Verarbeitung, Import aus Dateien/Notizen, VoiceOver, große Schrift, lange Transkripte sowie iOS-26-Tab-Zubehör. Sprechererkennung und Einsprechen sind jetzt im Motor angeschlossen; die Geräteprüfung steht aus.

## Geänderte Bestandsdateien

- `App/Conversations/ConversationBackground.swift`: Hintergrundablauf bricht auch ohne bereits gemeldete Fortschritts-ID die Warteschlange ab und meldet den Abbruch als solchen.
- `App/Conversations/ConversationCapture.swift`: Echte Ablage ersetzt den Stub, und Auswertungszustände aktualisieren ausschließlich die passende Live Activity.
- `App/Conversations/RecordingStoreStub.swift`: Der vorläufige Speicher ist gelöscht.
- `App/PaplyApp.swift`: Startet die Gesprächsumgebung beim App-Start.
- `App/Store/AppSettings.swift`: Speichert Gesprächs-Beta und Aufnahmezähler.
- `App/Thoughts/ThoughtsEnvironment.swift`: Setzt den Lernhaken vor dem ersten Gedanken-Housekeeping.
- `App/Thoughts/ThoughtsModel.swift`: Gesprächsgedanken nehmen beim Löschen, Wiederherstellen und endgültigen Entfernen die Gesprächsablage mit.
- `App/UI/Conversations/ConversationRecordingView.swift`: Der Aufnahmetipp verspricht beim Rückfall keine Sprechererkennung.
- `App/UI/Conversations/ConversationsHome.swift`: Der Startknopf beschreibt Text und Aufgaben statt einer noch fehlenden Sprechererkennung.
- `App/UI/RootView.swift`: Verbindet echten Reiter, Beta-Sichtbarkeit, Navigation und Vollbildaufnahme; die laufende Aufnahme bleibt auch bei ausgeschalteten Reitern erreichbar.
- `App/UI/SettingsView.swift`: Hängt Gesprächseinstellungen und Beta-Schalter ein.
- `App/UI/Thoughts/CaptureBar.swift`: Zeigt die Gesprächsaufnahme neben der Gedankenleiste im vorhandenen Tab-Zubehör.
- `App/UI/Thoughts/ThoughtDetailView.swift`: Leitet Gesprächsgedanken ins Gesprächsdetail um.
- `App/UI/Thoughts/ThoughtRow.swift`: Zeigt für Gesprächsgedanken die bereitgestellte Gesprächszeile.
- `Shared/Core/BetaFeatures.swift`: Definiert die standardmäßig eingeschaltete Gesprächs-Beta.

## Geänderte Bestandsdateien dieser Motor-Integration

- `ios/App/Conversations/ConversationCapture.swift`
- `ios/App/Conversations/ConversationEnrollment.swift`
- `ios/App/Conversations/ConversationsEnvironment.swift`
- `ios/App/Conversations/ConversationsModel.swift`
- `ios/App/PaplyApp.swift`
- `ios/App/Thoughts/ThoughtsModel.swift`
- `ios/App/UI/Conversations/ConversationsTab.swift`
- `ios/App/UI/SettingsView.swift`
- `ios/PaplyKit/Package.swift`
- `ios/PaplyKit/Sources/PaplyKit/Conversations/ConversationAnalyzer.swift`
- `ios/PaplyKit/Sources/PaplyKit/Conversations/SpeakerAlignment.swift`
- `ios/PaplyKit/Sources/PaplyKit/Conversations/SpeakerThresholds.swift`
- `ios/PaplyKit/Sources/PaplyKit/Conversations/VoiceProfileStore.swift`
- `ios/PaplyKit/Sources/paply-bench/ConversationsBench.swift`
- `ios/PaplyKit/Tests/PaplyKitTests/Conversations/ConversationCoreTests.swift`
- `ios/docs/gespraeche/VERDRAHTUNG-INTEGRATION.md`

Gelöscht: `ios/App/Conversations/EditingPlaceholder.swift`. Neue Motor-, Download-, Lizenz-, Mess- und Testdateien stehen im Commit.
