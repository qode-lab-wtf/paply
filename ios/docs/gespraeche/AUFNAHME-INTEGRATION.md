# Gesprächsaufnahme – Anschlussstellen

## Oberfläche

- `ConversationCapture.shared`: beobachtbar, `active` (ID, Beginn, pausiert), `level` (0…1), `notice`.
- `await toggle(trigger: .app)`, `finish()`, `discard()`. Verwerfen ab fünf Sekunden bestätigt die Oberfläche.
- `ConversationNavigation.shared`: beobachtbar, `requestedID`, `showCurrent`, `error`. RootView setzt diesen Zustand für Datei-URLs und `paply-ios://conversation/current` bzw. `…/<id>`; die Oberfläche übernimmt und leert ihn nach der Navigation.
- Nur eine Aufnahme bzw. ein Abschluss gleichzeitig. Unterbrechungen pausieren; der bestehende SessionController übernimmt den frischen Motorstart. Erst danach wird der Zulauf wieder freigegeben.
- Grenzen zählen verstrichene Echtzeit inklusive Anrufen. Lückenpositionen beziehen sich dagegen exakt auf die WAV-Samples. Keine künstliche Stille in der Datei.

## Speicher und Auswertung

`RecordingStoreStub` ist ausdrücklich vorläufig. Er speichert in `Application Support/Gespraeche-Aufnahme-Stub`, erstellt noch keinen verknüpften Gedanken und wird bei der Zusammenführung ersetzt. Die Aufnahme hängt ausschließlich an `ConversationRecordingStore`:

1. `ConversationCapture.shared.store = echterSpeicher` vor dem ersten Start setzen.
2. `onRecordingFinished` an die Auswertung anschließen. Der Haken erhält ein gesichertes `Conversation` und muss bis zum Ende der aktiven Auswertung warten (nicht nur eine unstrukturierte Task starten).
3. Währenddessen `ConversationBackground.shared.progress(id:fraction:)` melden und `ConversationCapture.shared.update(.processing, stage: …)` mit kurzen Stufentexten bedienen. Abschluss über `.done`, `.waiting` oder `.failed`; nie Gesprächsinhalte in die Live Activity.
4. `ConversationBackground.shared.resumePending` an die persistierte Warteschlange anschließen; `onExpiration` muss laufende Arbeit abbrechen und Zwischenstände sichern.
5. Begin/end sind für den Abschluss-Haken und Dateiimporte bereits eingerahmt. Andere Einstiegspunkte verwenden `begin(id:)`/`end(id:success:)` selbst.

Bis der Haken angeschlossen ist, bleibt die gesicherte Aufnahme in „wartend“. Kein Netzaufruf.

## Hintergrundgrenzen

Ab iOS 26 wird eine fortgesetzte Verarbeitung angefragt und ihr Fortschritt gemeldet. Sobald das System sie gewährt, hält Paply den Mikro-Eingang an, sofern kein Diktat/Gedanke/Gespräch ihn braucht. Bis dahin bleibt der bestehende Audiostrom bereit, ohne WAV-Empfänger. Unter iOS 18 dient das zusammen mit einer befristeten UIKit-Hintergrundaufgabe als Rückfall. Eine bloß aktive Audio-Sitzung ohne Audiostrom garantiert keine Laufzeit. iOS kann Ausführungszeit verweigern; der BGProcessing-Nachzügler und persistierte Zwischenstände bleiben deshalb erforderlich.

## Prüfung

- `ios/tools/gespraeche-aufnahme/check-tap.sh`: echter AudioTapProcessor und echte Stille-Erkennung auf dem Mac; nur der ungenutzte Pegel-Dateikanal ist ersetzt. Prüft Samplegleichheit des bisherigen Empfängers mit/ohne Mithörer, unabhängiges Lösen, Vorlauf, Neustart und Formatwechsel.
- Debug/Release nach README ohne Asset-Katalog, PaplyKit `swift test`.
- Echtes iPhone: Start aus gesperrtem Zustand per Control/Siri, Anruf klingelt und Aufnahme setzt fort, Hintergrund-Rückfall, paralleles Tastatur-Diktat/Gedanke, Startbanner ohne Dynamic Island, Hinweise/Vibrationen, Import aus Notizen und Dateien, vier Stunden sowie Speicherknappheit.
- Der Stub ist keine produktive Ablage und übernimmt keine Wiederherstellung abgebrochener Imports; das gehört in den echten PaplyKit-Speicher.
