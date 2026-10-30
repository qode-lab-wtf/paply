# Gespräche: Übergabe der Oberfläche

Alle Produkt-Views sind reine SwiftUI-Ansichten. Keine Session-, Speicher-, Netzwerk- oder
Zwischenablagezugriffe. Lokaler State enthält nur Dialoge und Eingaben. Vorschau-Hosts halten
flüchtige Beispieldaten und führen keine echte Aufnahme aus.

| View | Werte | Aktionen |
| --- | --- | --- |
| ConversationsHome | `[ConversationDisplay]`, `showPrivacyHint` | record, open(ID), voices, deleted, settings |
| ConversationRecordingView | elapsed, paused, pausedSince, showGuidance, level | pause, finish, discard, minimize |
| ConversationRecordingBar | elapsed, paused, level | open, pause, finish |
| ConversationDetailView | ConversationDisplay, utterances, pendingTaskIDs | ConversationDetailActions: rename, chooseTopic, speaker, identifyOwner, suggestion, toggleTask, reassign, copyUtterance, share, copyTranscript, retry, delete |
| ConversationSpeakerSheet | speaker, speakers, people | choose(ConversationSpeakerChoice, rememberVoice), cancel |
| ConversationUtteranceSpeakerSheet | speakers, selectedID, title | choose(ID), cancel |
| ConversationSettingsSection | learnedThoughtCount (nil = ungelernt), people | enroll, forgetOwner, deletePerson(ID) |
| ConversationKnownVoicesView | people | delete(ID) |
| ConversationEnrollmentView | elapsed, isRecording, level | start, finish, cancel |
| ConversationThoughtRow | ConversationDisplay, time, showsIcon | keine, in navigierenden Button einbetten |
| ConversationTaskRow | ThoughtTask, recordedAt, pendingDone | toggle |
| ConversationUtteranceRow | utterance, speaker | reassign, copy |
| ConversationStatusBand | Conversation | retry |
| ConversationSpeakerLabel | speaker, showSuggestion | keine |

`ConversationDisplay` ergänzt den unveränderten Vertrag `Conversation` um den Themennamen und
`[ThoughtTask]` des verknüpften Gedankens. Die Leitung liefert sortierbare Gesprächswerte,
Wortlaut (auch teilweise fertig), Stimmprofile.
Zeit/Pegel werden von außen aktualisiert. Beim Einsprechen beendet das Aufnahme-Modell nach 20 Sekunden; der Host schließt das Blatt.
`pendingTaskIDs` an die vorhandene verzögerte Aufgaben-Erledigung anbinden.

Datenschutzhinweis und Aufnahmehilfe außen nach den ersten drei Aufnahmen ausblenden.
Personenentscheidungen müssen dort gespeichert, Zusammenlegungen auf alle Beiträge angewendet,
Teilen/Kopieren ausgeführt werden. Nach der Auswertung gibt es keine Wiedergabe. Der Aufnahmeverwerfen-Dialog
ab fünf Sekunden und der Löschen-Dialog sind bereits in den Views enthalten.

Integration: `ConversationsPlaceholderTab` in RootView ersetzen; den reinen
`ConversationSettingsSection` im produktiven Settings-Form einsetzen. Beta-Schalter „Gespräche“
(Standard an) gehört zur anschließenden Einstellungs-/Modellverdrahtung. Bei Gedanken mit
`kind == "conversation"` die bereitgestellte Zeile einsetzen und zum Gespräch navigieren.
Die Aufnahmeleiste am gemeinsamen Tab-Container platzieren (iOS 26 ggf. Tab-Accessory wie CaptureBar).
Vorschau: Einstellungen → Version 5× → Entwicklerbereich → Gespräche-Vorschau.

Geräteabnahme steht aus: Glas auf iOS 26, VoiceOver, größte Schriftgröße und Scroll-Test mit
1.200 Beiträgen. #Previews und die Entwicklerseite enthalten die erforderlichen Zustände.
