# Gespräche – App-Verdrahtung

## Anschlussstellen

- `ConversationsEnvironment`: gemeinsame Ablage unter `Application Support/Gespraeche`, eigener Ledger, Schlüsselbund über `AppSettings`, Sprache und Vokabular. Start, Vordergrund, Netz, Schlüssel, Abschluss und Import stoßen denselben Processor an. Geschützte Daten werden erst nach Freigabe gelesen.
- `ConversationRecordingBridge`: echter `ConversationStore`, sofortiger Gedanke mit gleicher ID; auch verworfene Aufnahmen sind gemeinsam wiederherstellbar. Der alte Aufnahme-Stub ist gelöscht.
- `ConversationBackground`: persistierte Warteschlange für BGProcessing, Abbruch bei Ablauf. Processor-Ereignisse liefern zahlenbasierten Fortschritt und inhaltsfreie Live-Activity-Stufen, nur für die passende Aufnahme.
- `ConversationsModel`: Ablage-/Processor-Ereignisse, bedarfsgeladener Wortlaut, Profile, Aktionen über `ConversationEditing`, Teilen mit `ConversationText.render`, Abschnittswiedergabe. Die Wiedergabe setzt weder Audio-Kategorie noch Audio-Modus; die bestehende Sitzung bleibt allein zuständig.
- `ConversationsTab` und `ConversationDetailHost`: reine Views mit echten Daten und Aktionen. Gemeinsame Themenwahl und `TaskCheckoff`; vorhandenes Gedanken-Detail leitet Gespräche um. Löschen, Wiederherstellen, endgültiges Löschen sowie Thema samt Gedanken löschen nehmen die Gesprächsablage mit.
- `RootView`: unabhängiger Beta-Schalter, Deep Links und Import, Vollbildaufnahme und gemeinsame Aufnahmeleiste; ab der vorhandenen iOS-26.1-Accessory-Freigabe im Tab-Zubehör, sonst als unterer Einsatz.
- `ConversationEnrollment`: 20 Sekunden über denselben Sitzung-Mithörer, temporäre WAV wird nach Abschluss oder Abbruch gelöscht. Keine zweite Mikrofon-Sitzung.

## Beim Zusammenführen ersetzen

1. `EditingPlaceholder` durch die Kern-Konformität von `ConversationEditing` in `ConversationsEnvironment.editing` ersetzen; Platzhalterdatei löschen. Bis dahin melden Benennen, Vorschläge, Zusammenlegen, Umhängen und Umbenennen sichtbar, dass die Funktion fehlt.
2. `ConversationsEnvironment.makeDiarizer()` liefert ausdrücklich nur einen Sprecher anhand vorhandener VAD-Sprachabschnitte. Keine künstlichen Stimmabdrücke, `voiceprint` bleibt `nil`. Die Übersicht sagt, dass Sprecher gemeinsam angezeigt werden. Bei Einbau des Motors auch diesen Hinweis entfernen.
3. `EnrollmentPlaceholder` durch `VoiceProfileStore.enroll(audio:diarizer:)` ersetzen. Der angezeigte Lernstand ist bis zum neuen Kern-Lernstatus die Zahl vorhandener Gedanken-Abdrücke (noch kein dauerhafter Gesamtzähler).

Der Lernhaken sitzt vor dem Gedanken-Housekeeping. Der Rückfall leert keine Lernaufnahmen ohne Ergebnis. Mit einem echten Motor arbeitet der vorbereitete Lernlauf nur bei freier Sitzung; neue Aufnahme/Diktat/Verarbeitung bricht ihn ab. Der Kern begrenzt die Warteschlange auf zehn Dateien.

Einzige additive Änderung an PaplyKit außerhalb des Gesprächskerns: `Audio/SpeechRegions.swift` macht die vorhandene paketinterne VAD über einen lesenden WAV-Helfer nutzbar. `Conversations/` und seine Verträge bleiben unverändert. Zwei Tests prüfen Stille und getrennte Sprachabschnitte.

## Prüfung

Debug und Release mit dem beauftragten `xcodebuild` ohne Signierung/Asset-Katalog; PaplyKit vollständig mit `swift test --no-parallel` (671 Tests). Der normale parallele Swift-Testing-Lauf war mit 669 Tests zunächst grün; spätere Läufe mit 671 Tests zeigten die lastabhängigen Bestandsfehler `rateLimitedKeyIsValid` und einmal `cancelAbortsRunningChunkUploadImmediately`. Die neuen VAD-Tests bestanden in allen Läufen. Keine echten Groq-Aufrufe.

Auf dem iPhone offen: Wiedergabe mit aktiver/ruhender Diktat-Bereitschaft und Bluetooth, sofortiger Aufnahmewechsel, Anrufunterbrechungen, gesperrter Start, Hintergrund-Ablauf/fortgesetzte Verarbeitung, Import aus Dateien/Notizen, VoiceOver, große Schrift, lange Transkripte sowie iOS-26-Tab-Zubehör. Echte Sprechererkennung und erfolgreiches Einsprechen sind erst mit dem Motor prüfbar.

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
