# Paply — aktueller Stand

2026-09-21 · Phase: Entwicklung/Prüfung · Branch `codex/local-meeting-quality`

## Bestätigtes Ziel und aktuelle Grenze

[Plan](PLAN.md), [Entscheidungen](ENTSCHEIDUNGEN.md). Kostenloser lokaler
Gesprächsmodus; Diktat unverändert. Allan hat nach den Vergleichen ausdrücklich
Produktumsetzung und weitere vorhandene Beispiele angefordert. Deshalb wird eine
getrennte lokale Test-App gebaut. **Keine Qualitäts- oder Produktivfreigabe.**
Die installierte `/Applications/paply.app` und ihre Daten bleiben unverändert.

## Implementiert in der getrennten Testversion

- Eigene App-ID, eigener Datenordner und Shortcut Cmd+Option+Shift+X.
- Mikrofon und Systemton separat in atomaren Zwei-Sekunden-Dateien gesichert.
  Fortlaufende Abtastratenumrechnung statt Rundungsverlust je Audioblock;
  Endstücke werden vor Stop bestätigt und gespeichert.
- Lokales Whisper Large v3 und originales pyannote Community-1 in getrennten,
  sequenziellen Prozessen mit gesperrtem Netzwerk. Checkpoints/Wiederaufnahme.
- Neutrale Sprecher, Wortzeit-Zuordnung und sichtbare Unsicherheit. Erkannte Stimme
  ohne ASR-Text als Lücke sichtbar. Keine pauschale Löschung bei Zeitüberlappung;
  Audio-Korrelation markiert mögliches Echo, löscht keine Beiträge.
- Textstellen-Wiedergabe, unabhängige gespeicherte Text-/Sprecherkorrekturen,
  unverknüpfbare frühere Korrekturen sichtbar, TXT/HTML/PDF-Export.
- Versionierte Sitzung mit Aufnahmezeit, Modellversionen, Fehlern und Ablaufdatum.
  LaunchAgent für neue Audioaufnahmen nach sieben Tagen einschließlich Zwischenkopien.
  Historische Daten werden nicht rückwirkend bereinigt.
- Quellenübersicht als transparenter Ersatz, solange kein Berichtsmodell qualifiziert
  ist. Optionaler abschnittsweiser lokaler Berichtsentwurf in Arbeit, mit echten
  Quellenverweisen und eigener Modellversion. Quellenbezug beweist keine Faktentreue.

## Nachgewiesen am 21.09.2026

- Ursprungsbasis `736f5aa` identisch mit damaligem GitHub main; vier relevante Module
  der installierten v1.12.5 bytegleich. M5/32 GB/macOS26.2.
- Fünf historische Gesprächsausschnitte, neun Tonspuren. Zusätzliche drei Gespräche
  mit zwölf erfolgreichen netzgesperrten Modellläufen:
  [Zusatzaufnahmen](validation/2026-09-21-additional-recordings.json).
- Der neue Zusammenführungscode erhält den gesamten erkannten ASR-Text auf allen
  neun Spuren: [Erhaltungsprüfung](validation/2026-09-21-product-text-preservation.json).
  Das beweist weder vollständige Spracherkennung noch richtige Sprecherzuordnung.
- Reale 21-s-Aufnahme mit dem neuen App-Backend vollständig offline verarbeitet:
  ASR → Sprecheranalyse → Zusammenführung → Quellenübersicht, Status ready.
- 137 App-Tests/18 Dateien; 31 Python-Tests. Fehler/Wiederaufnahme, Korrekturen,
  Aufnahme-Endstücke, Löschung während Verarbeitung, Erhalt überlappender Texte.
- Vite-Build erfolgreich. Vier bekannte TypeScript-Fehler Profile/CustomAgent in
  Dashboard bestehen auch auf der unveränderten Basis; nicht als grüner Typecheck ausgeben.
- Test-App lokal gepackt/ad-hoc signiert und gestartet. Nicht-ASCII-Executable-Name
  verursachte Startabsturz; ASCII-Bündelname `Paply Meeting Test` behebt ihn auf diesem Mac.
- In echter App-Oberfläche fünf Testgespräche geöffnet; Textstelle startet Audio bei
  17,64 s; Korrektur gespeichert; PDF aus der App als Datei erzeugt.
- LaunchAgent geladen, letzter Exit 0. Bei geschlossener Test-App abgelaufene Test-
  Audiodatei entfernt, Transkript und historische Testaufnahme erhalten.

## Offen / nächster Schritt

- Qwen3.5-9B mit Ollama0.34.2 liefert jetzt strukturell gültige Berichte auf zwei
  Beispielen; inhaltlich weiterhin unzulässige Vereinfachungen/Zuordnungen. Nicht
  aktiviert. Größerer Kandidat Qwen3.8-27B wird lokal vorbereitet. Qwen3-8B und Gemma3-4B
  hatten Rollen-/Bedeutungsfehler und bleiben ungeeignet für eine Freigabe.
- Erneute UI-Prüfung bestanden: zwei Sprecher ohne Mitzählen unklarer Zuordnung;
  Wiedergabe auch nach gespeicherter Korrektur bei 17,64 s. PDF vollständig und lesbar
  auf zwei A4-Seiten geprüft. Mikrofon-Neuverbindung erhält erkannte Zeitlücken mit
  Stille; automatischer Test bestanden, echte Gerätewechsel noch ausstehend.
- Echte Aufnahmeberechtigungen, Gerätewechsel, lange Aufnahmen und Raum/Telefon/
  Mischsituation praktisch abnehmen. Systemtonbeginn derzeit aus erster Ankunft
  geschätzt; keine nachgewiesene hardwareübergreifende Langzeitsynchronität.
- Menschlich bestätigte Referenz fehlt: 95 % Sprecherzeit, ≤10 % WER und vollständige
  faktentreue Berichte sind weiterhin Prüfziele. Kurze Anisa-Aufnahme kann TV enthalten.
- Größere Modelle/weitere Sprecherverfahren nur anhand realer Qualitätsverbesserung
  auswählen. Keine Umstellung auf kostenpflichtige Dienste.
- Instinct-Empfang weiterhin nicht nachgewiesen; GitHub-Sichtbarkeit reicht nicht.

Private Rohaufnahmen, Transkripte, Modellartefakte und Laufzeitprotokolle bleiben
lokal in ignoriertem `work/` bzw. im separaten Test-App-Datenordner.
